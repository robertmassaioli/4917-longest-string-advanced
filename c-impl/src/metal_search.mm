#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "4917/machine.h"
#include "machine_internal.hpp"

#include <algorithm>
#include <array>
#include <charconv>
#include <chrono>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

namespace {

constexpr uint32_t kChunkSize = 262144;
constexpr uint32_t kHalted = 1;

struct GpuResult {
    uint64_t steps;
    uint64_t output_characters;
    uint32_t status;
    uint32_t reserved;
};

struct GpuParameters {
    uint64_t base_id;
    uint64_t step_limit;
    uint32_t length;
    uint32_t count;
};

static_assert(sizeof(GpuResult) == 24, "MSL result layout must match host layout");
static_assert(sizeof(GpuParameters) == 24, "MSL parameter layout must match host layout");

NSString *shader_source() {
    return @R"METAL(
#include <metal_stdlib>
using namespace metal;

struct Result { ulong steps; ulong output_characters; uint status; uint reserved; };
struct Parameters { ulong base_id; ulong step_limit; uint length; uint count; };

kernel void search_batch(device Result *results [[buffer(0)]],
                         constant Parameters &params [[buffer(1)]],
                         uint tid [[thread_position_in_grid]]) {
    if (tid >= params.count) return;
    ulong encoded = params.base_id + ulong(tid);
    uchar memory[16];
    for (uint i = 0; i < 16; ++i) memory[i] = 0;
    for (uint i = 0; i < params.length; ++i) {
        memory[params.length - i - 1] = uchar(encoded & 15ul);
        encoded >>= 4;
    }

    uchar r0 = 0, r1 = 0, pc = 0;
    ulong output = 0;
    ulong steps = 0;
    bool halted = false;
    while (steps < params.step_limit) {
        uchar op = memory[pc];
        uchar operand_pc = uchar((uint(pc) + 1u) & 15u);
        uchar after_operand = uchar((uint(pc) + 2u) & 15u);
        uchar operand = memory[operand_pc];
        uchar next = operand_pc;
        switch (op) {
        case 0: pc = next; halted = true; break;
        case 1: r0 = uchar((uint(r0) + uint(r1)) & 15u); pc = next; break;
        case 2: r0 = uchar((uint(r0) + 16u - uint(r1)) & 15u); pc = next; break;
        case 3: r0 = uchar((uint(r0) + 1u) & 15u); pc = next; break;
        case 4: r1 = uchar((uint(r1) + 1u) & 15u); pc = next; break;
        case 5: r0 = uchar((uint(r0) - 1u) & 15u); pc = next; break;
        case 6: r1 = uchar((uint(r1) - 1u) & 15u); pc = next; break;
        case 7: pc = next; break;
        case 8: {
            ulong amount = operand < 10 ? 1ul : 2ul;
            if (output > (~0ul) - amount) { steps = params.step_limit; }
            else { output += amount; pc = after_operand; }
            break;
        }
        case 9: r0 = memory[operand]; pc = after_operand; break;
        case 10: r1 = memory[operand]; pc = after_operand; break;
        case 11: memory[operand] = r0; pc = after_operand; break;
        case 12: memory[operand] = r1; pc = after_operand; break;
        case 13: pc = operand; break;
        case 14: pc = r0 == 0 ? operand : after_operand; break;
        case 15: pc = r0 != 0 ? operand : after_operand; break;
        }
        if (halted) { ++steps; break; }
        if (steps < params.step_limit) ++steps;
    }
    results[tid].steps = steps;
    results[tid].output_characters = output;
    results[tid].status = halted ? 1u : 0u;
    results[tid].reserved = 0;
}
)METAL";
}

struct Counts {
    uint64_t low = 0;
    bool two_to_64 = false;
    void increment() {
        if (low == UINT64_MAX) { low = 0; two_to_64 = true; }
        else if (!two_to_64) ++low;
    }
    bool zero() const { return low == 0 && !two_to_64; }
    std::string string() const { return two_to_64 ? "18446744073709551616" : std::to_string(low); }
};

bool parse_u64(const char *s, uint64_t &out) {
    const char *end = s + std::char_traits<char>::length(s);
    auto [ptr, ec] = std::from_chars(s, end, out);
    return ec == std::errc{} && ptr == end;
}

bool parse_program(const char *csv, std::array<uint8_t, 16> &program, uint64_t &length) {
    const std::string input(csv);
    size_t begin = 0;
    while (begin <= input.size()) {
        const size_t end = input.find(',', begin);
        const size_t stop = end == std::string::npos ? input.size() : end;
        uint64_t value = 0;
        if (length == 16 || stop == begin ||
            !parse_u64(input.substr(begin, stop - begin).c_str(), value) || value > 15) return false;
        program[static_cast<size_t>(length++)] = static_cast<uint8_t>(value);
        if (end == std::string::npos) break;
        begin = end + 1;
    }
    return length > 0;
}

const char *termination_name(i4917_termination termination) {
    switch (termination) {
    case I4917_HALTED: return "halted";
    case I4917_LIMIT_REACHED: return "step_limit";
    case I4917_CYCLE: return "cycle";
    default: return "error";
    }
}

void print_usage() {
    std::puts("Usage: 4917-metal-search --length N [--gpu-step-limit N] [--json]\n"
              "Exhaustively searches programs of 1-16 nibbles. GPU execution is bounded;\n"
              "every candidate not halted by the GPU budget is classified by the exact CPU runner.\n"
              "       4917-metal-search --program NIBBLES [--gpu-step-limit N] [--json]\n"
              "The --program form traces one candidate and is useful for checking edge cases.\n"
              "Default GPU budget: 256 instructions per candidate.");
}

id<MTLComputePipelineState> make_pipeline(id<MTLDevice> device, NSError **error) {
    id<MTLLibrary> library = [device newLibraryWithSource:shader_source() options:nil error:error];
    if (library == nil) return nil;
    id<MTLFunction> function = [library newFunctionWithName:@"search_batch"];
    if (function == nil) {
        if (error != nullptr) *error = [NSError errorWithDomain:@"4917-metal-search" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Metal kernel search_batch is missing"}];
        return nil;
    }
    return [device newComputePipelineStateWithFunction:function error:error];
}

bool run_batch(id<MTLDevice> device, id<MTLCommandQueue> queue,
               id<MTLComputePipelineState> pipeline, uint64_t base, uint32_t count,
               uint64_t length, uint64_t step_limit, GpuResult *host_results) {
    NSError *error = nil;
    id<MTLBuffer> result_buffer = [device newBufferWithLength:sizeof(GpuResult) * count
        options:MTLResourceStorageModeShared];
    if (result_buffer == nil) { std::fputs("Metal buffer allocation failed\n", stderr); return false; }
    GpuParameters params{base, step_limit, static_cast<uint32_t>(length), count};
    id<MTLBuffer> parameter_buffer = [device newBufferWithBytes:&params length:sizeof(params)
        options:MTLResourceStorageModeShared];
    if (parameter_buffer == nil) { std::fputs("Metal parameter allocation failed\n", stderr); return false; }
    id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
    [encoder setComputePipelineState:pipeline];
    [encoder setBuffer:result_buffer offset:0 atIndex:0];
    [encoder setBuffer:parameter_buffer offset:0 atIndex:1];
    const NSUInteger width = std::min<NSUInteger>(pipeline.maxTotalThreadsPerThreadgroup, 256);
    [encoder dispatchThreads:MTLSizeMake(count, 1, 1)
        threadsPerThreadgroup:MTLSizeMake(width, 1, 1)];
    [encoder endEncoding];
    [command commit];
    [command waitUntilCompleted];
    if (command.status == MTLCommandBufferStatusError) {
        error = command.error;
            const char *message = error.localizedDescription.UTF8String;
            std::fprintf(stderr, "Metal execution failed: %s\n", message == nullptr ? "unknown error" : message);
        return false;
    }
    std::memcpy(host_results, result_buffer.contents, sizeof(GpuResult) * count);
    return true;
}

int run_one(const std::array<uint8_t, 16> &program, uint64_t length,
            uint64_t step_limit, bool json) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) { std::fputs("no Metal GPU is available\n", stderr); return 1; }
        NSError *error = nil;
        id<MTLComputePipelineState> pipeline = make_pipeline(device, &error);
        if (pipeline == nil) {
            const char *message = error.localizedDescription.UTF8String;
            std::fprintf(stderr, "could not compile Metal kernel: %s\n",
                         message == nullptr ? "unknown error" : message);
            return 1;
        }
        id<MTLCommandQueue> queue = [device newCommandQueue];
        if (queue == nil) { std::fputs("could not create Metal command queue\n", stderr); return 1; }
        uint64_t encoded = 0;
        for (uint64_t i = 0; i < length; ++i) encoded = (encoded << 4) | program[static_cast<size_t>(i)];
        GpuResult gpu{};
        if (!run_batch(device, queue, pipeline, encoded, 1, length, step_limit, &gpu)) return 1;
        i4917_termination termination;
        uint64_t steps;
        uint64_t output_characters;
        if (gpu.status == kHalted) {
            termination = I4917_HALTED;
            steps = gpu.steps;
            output_characters = gpu.output_characters;
        } else {
            i4917_state initial{};
            std::memcpy(initial.memory, program.data(), program.size());
            const i4917_run_result exact = i4917_run_until_halt_or_cycle(&initial);
            termination = exact.termination;
            steps = exact.steps;
            output_characters = exact.output_characters;
        }
        if (json) {
            std::printf("{\"schema\":\"4917-metal-run-v1\",\"termination\":\"%s\","
                        "\"steps\":\"%" PRIu64 "\",\"output_characters\":\"%" PRIu64 "\"}\n",
                        termination_name(termination), steps, output_characters);
        } else {
            std::printf("termination: %s\nsteps: %" PRIu64 "\noutput characters: %" PRIu64 "\n",
                        termination_name(termination), steps, output_characters);
        }
    }
    return 0;
}

int search(uint64_t length, uint64_t step_limit, bool json) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) { std::fputs("no Metal GPU is available\n", stderr); return 1; }
        NSError *error = nil;
        id<MTLComputePipelineState> pipeline = make_pipeline(device, &error);
        if (pipeline == nil) {
            const char *message = error.localizedDescription.UTF8String;
            std::fprintf(stderr, "could not compile Metal kernel: %s\n",
                         message == nullptr ? "unknown error" : message);
            return 1;
        }
        id<MTLCommandQueue> queue = [device newCommandQueue];
        if (queue == nil) { std::fputs("could not create Metal command queue\n", stderr); return 1; }

        const bool full_space = length == 16;
        const uint64_t total = full_space ? 0 : (uint64_t{1} << (4 * length));
        Counts halted, cycled, errors, winners, gpu_halted, cpu_fallback;
        uint64_t best = 0;
        std::array<uint8_t, 16> first{};
        std::array<GpuResult, kChunkSize> results{};
        const auto started = std::chrono::steady_clock::now();
        uint64_t base = 0;
        bool finished = false;
        while (!finished) {
            uint32_t count = kChunkSize;
            if (!full_space) {
                const uint64_t remaining = total - base;
                count = static_cast<uint32_t>(std::min<uint64_t>(remaining, kChunkSize));
            } else if (base > UINT64_MAX - (kChunkSize - 1U)) {
                count = static_cast<uint32_t>(UINT64_MAX - base + 1U);
            }
            if (!run_batch(device, queue, pipeline, base, count, length, step_limit, results.data())) return 1;
            for (uint32_t i = 0; i < count; ++i) {
                std::array<uint8_t, 16> program{};
                uint64_t encoded = base + i;
                for (uint64_t j = length; j > 0; --j) {
                    program[static_cast<size_t>(j - 1)] = static_cast<uint8_t>(encoded & 15U);
                    encoded >>= 4;
                }
                i4917_termination termination;
                uint64_t output_characters;
                if (results[i].status == kHalted) {
                    termination = I4917_HALTED;
                    output_characters = results[i].output_characters;
                    gpu_halted.increment();
                } else {
                    // Bounded GPU work never decides whether an unfinished program
                    // cycles or halts later. The existing constant-space detector
                    // decides that exactly on the CPU.
                    const i4917_run_result exact = i4917_detail::run_search_program(program);
                    termination = exact.termination;
                    output_characters = exact.output_characters;
                    cpu_fallback.increment();
                }
                if (termination == I4917_HALTED) {
                    halted.increment();
                    if (winners.zero() || output_characters > best) {
                        best = output_characters;
                        winners = Counts{1, false};
                        first = program;
                    } else if (output_characters == best) winners.increment();
                } else if (termination == I4917_CYCLE) cycled.increment();
                else errors.increment();
            }
            const uint64_t last = base + count - 1U;
            if (full_space) {
                if (last == UINT64_MAX) finished = true;
                else base = last + 1U;
            } else if (last + 1U == total) finished = true;
            else base = last + 1U;
        }
        const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
        const std::string candidate_count = full_space ? "18446744073709551616" : std::to_string(total);
        if (json) {
            std::printf("{\"schema\":\"4917-metal-search-v1\",\"length\":%" PRIu64
                        ",\"candidate_count\":\"%s\",\"halted\":\"%s\",\"cycled\":\"%s\","
                        "\"errors\":\"%s\",\"exhaustive\":%s,\"best_output_characters\":\"%" PRIu64
                        "\",\"winner_count\":\"%s\",\"first_winner\":[",
                        length, candidate_count.c_str(), halted.string().c_str(), cycled.string().c_str(),
                        errors.string().c_str(), errors.zero() ? "true" : "false", best, winners.string().c_str());
            for (uint64_t i = 0; i < length; ++i)
                std::printf("%s%u", i ? "," : "", static_cast<unsigned>(first[static_cast<size_t>(i)]));
            std::printf("],\"gpu_halted\":\"%s\",\"cpu_exact_fallback\":\"%s\",\"seconds\":%.6f}\n",
                        gpu_halted.string().c_str(), cpu_fallback.string().c_str(), seconds);
        } else {
            std::printf("GPU: %s (%s)\ncandidates: %s\nhalted: %s\ncycled: %s\nerrors: %s\n"
                        "exhaustive: %s\nbest output characters: %" PRIu64 "\nwinner count: %s\n"
                        "GPU halted: %s\nCPU exact fallback: %s\nelapsed seconds: %.3f\n",
                        device.name.UTF8String, "Metal", candidate_count.c_str(),
                        halted.string().c_str(), cycled.string().c_str(), errors.string().c_str(),
                        errors.zero() ? "yes" : "no", best, winners.string().c_str(),
                        gpu_halted.string().c_str(), cpu_fallback.string().c_str(), seconds);
        }
    }
    return 0;
}

} // namespace

int main(int argc, char **argv) {
    uint64_t length = 0;
    uint64_t step_limit = 256;
    bool json = false;
    bool has_program = false;
    bool has_length = false;
    std::array<uint8_t, 16> program{};
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--help") == 0 || std::strcmp(argv[i], "-h") == 0) {
            print_usage(); return 0;
        } else if (std::strcmp(argv[i], "--json") == 0) json = true;
        else if (std::strcmp(argv[i], "--length") == 0 && i + 1 < argc) {
            if (!parse_u64(argv[++i], length)) { std::fputs("invalid --length\n", stderr); return 2; }
            has_length = true;
        } else if (std::strcmp(argv[i], "--gpu-step-limit") == 0 && i + 1 < argc) {
            if (!parse_u64(argv[++i], step_limit) || step_limit == 0) {
                std::fputs("--gpu-step-limit must be a positive integer\n", stderr); return 2;
            }
        } else if (std::strcmp(argv[i], "--program") == 0 && i + 1 < argc) {
            if (has_program || !parse_program(argv[++i], program, length)) {
                std::fputs("--program must contain 1-16 comma-separated nibbles from 0 through 15\n", stderr);
                return 2;
            }
            has_program = true;
        } else { std::fprintf(stderr, "unknown or incomplete argument: %s\n", argv[i]); return 2; }
    }
    if (has_program) {
        if (has_length) { std::fputs("use either --program or --length, not both\n", stderr); return 2; }
        return run_one(program, length, step_limit, json);
    }
    if (length < 1 || length > 16) { std::fputs("--length must be from 1 through 16\n", stderr); return 2; }
    return search(length, step_limit, json);
}
