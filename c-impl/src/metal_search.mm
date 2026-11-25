#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "4917/machine.h"
#include "machine_internal.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <charconv>
#include <chrono>
#include <cinttypes>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr uint32_t kChunkSize = 1048576;
constexpr uint32_t kHalted = 1;
constexpr uint32_t kCycled = 2;

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
    uint32_t compact_results;
};

static_assert(sizeof(GpuResult) == 24, "MSL result layout must match host layout");
static_assert(sizeof(GpuParameters) == 32, "MSL parameter layout must match host layout");

NSString *shader_source() {
    return @R"METAL(
#include <metal_stdlib>
using namespace metal;

struct Result { ulong steps; ulong output_characters; uint status; uint reserved; };
struct Parameters { ulong base_id; ulong step_limit; uint length; uint count; uint compact_results; };
struct MachineState { ulong memory; uchar r0; uchar r1; uchar pc; };

inline uchar read_cell(thread const MachineState &s, uchar address) {
    return uchar((s.memory >> (4ul * ulong(address))) & 15ul);
}

inline void write_cell(thread MachineState &s, uchar address, uchar value) {
    ulong shift = 4ul * ulong(address);
    ulong mask = 15ul << shift;
    s.memory = (s.memory & ~mask) | ((ulong(value) & 15ul) << shift);
}

inline bool same_state(thread const MachineState &a, thread const MachineState &b) {
    return a.memory == b.memory && a.r0 == b.r0 && a.r1 == b.r1 && a.pc == b.pc;
}

inline bool execute(thread MachineState &s, thread ulong &output,
                    thread bool &overflow) {
    uchar op = read_cell(s, s.pc);
    uchar operand_pc = uchar((uint(s.pc) + 1u) & 15u);
    uchar after_operand = uchar((uint(s.pc) + 2u) & 15u);
    uchar operand = read_cell(s, operand_pc);
    uchar next = operand_pc;
    switch (op) {
    case 0: s.pc = next; return true;
    case 1: s.r0 = uchar((uint(s.r0) + uint(s.r1)) & 15u); s.pc = next; break;
    case 2: s.r0 = uchar((uint(s.r0) + 16u - uint(s.r1)) & 15u); s.pc = next; break;
    case 3: s.r0 = uchar((uint(s.r0) + 1u) & 15u); s.pc = next; break;
    case 4: s.r1 = uchar((uint(s.r1) + 1u) & 15u); s.pc = next; break;
    case 5: s.r0 = uchar((uint(s.r0) - 1u) & 15u); s.pc = next; break;
    case 6: s.r1 = uchar((uint(s.r1) - 1u) & 15u); s.pc = next; break;
    case 7: s.pc = next; break;
    case 8: {
        ulong amount = operand < 10 ? 1ul : 2ul;
        if (output > (~0ul) - amount) overflow = true;
        else { output += amount; s.pc = after_operand; }
        break;
    }
    case 9: s.r0 = read_cell(s, operand); s.pc = after_operand; break;
    case 10: s.r1 = read_cell(s, operand); s.pc = after_operand; break;
    case 11: write_cell(s, operand, s.r0); s.pc = after_operand; break;
    case 12: write_cell(s, operand, s.r1); s.pc = after_operand; break;
    case 13: s.pc = operand; break;
    case 14: s.pc = s.r0 == 0 ? operand : after_operand; break;
    case 15: s.pc = s.r0 != 0 ? operand : after_operand; break;
    }
    return false;
}

// Compact mode is used only below 2^29 steps. Even if each instruction emits
// two characters, its output is at most 2^30 - 2 and fits the 30 payload bits
// left after the two status bits in the packed result.
inline bool execute_compact(thread MachineState &s, thread uint &output) {
    uchar op = read_cell(s, s.pc);
    uchar operand_pc = uchar((uint(s.pc) + 1u) & 15u);
    uchar after_operand = uchar((uint(s.pc) + 2u) & 15u);
    uchar operand = read_cell(s, operand_pc);
    uchar next = operand_pc;
    switch (op) {
    case 0: s.pc = next; return true;
    case 1: s.r0 = uchar((uint(s.r0) + uint(s.r1)) & 15u); s.pc = next; break;
    case 2: s.r0 = uchar((uint(s.r0) + 16u - uint(s.r1)) & 15u); s.pc = next; break;
    case 3: s.r0 = uchar((uint(s.r0) + 1u) & 15u); s.pc = next; break;
    case 4: s.r1 = uchar((uint(s.r1) + 1u) & 15u); s.pc = next; break;
    case 5: s.r0 = uchar((uint(s.r0) - 1u) & 15u); s.pc = next; break;
    case 6: s.r1 = uchar((uint(s.r1) - 1u) & 15u); s.pc = next; break;
    case 7: s.pc = next; break;
    case 8: output += operand < 10 ? 1u : 2u; s.pc = after_operand; break;
    case 9: s.r0 = read_cell(s, operand); s.pc = after_operand; break;
    case 10: s.r1 = read_cell(s, operand); s.pc = after_operand; break;
    case 11: write_cell(s, operand, s.r0); s.pc = after_operand; break;
    case 12: write_cell(s, operand, s.r1); s.pc = after_operand; break;
    case 13: s.pc = operand; break;
    case 14: s.pc = s.r0 == 0 ? operand : after_operand; break;
    case 15: s.pc = s.r0 != 0 ? operand : after_operand; break;
    }
    return false;
}

kernel void search_batch(device uchar *result_bytes [[buffer(0)]],
                         constant Parameters &params [[buffer(1)]],
                         uint tid [[thread_position_in_grid]]) {
    if (tid >= params.count) return;
    ulong encoded = params.base_id + ulong(tid);
    ulong memory = 0ul;
    for (uint i = 0; i < params.length; ++i) {
        memory = (memory << 4) | (encoded & 15ul);
        encoded >>= 4;
    }
    MachineState state = {memory, 0, 0, 0};

    if (params.compact_results != 0) {
        // Compact-result mode is selected only for budgets < 2^29, so these
        // iteration counters and Brent's power/distance remain in uint range.
        MachineState checkpoint = state;
        uint power = 1u;
        uint distance = 0u;
        uint steps = 0u;
        uint output = 0u;
        bool halted = false;
        bool cycled = false;
        while (ulong(steps) < params.step_limit) {
            halted = execute_compact(state, output);
            if (halted) { ++steps; break; }
            ++steps;
            ++distance;
            if (same_state(state, checkpoint)) { cycled = true; break; }
            if (distance == power) {
                checkpoint = state;
                power *= 2u;
                distance = 0u;
            }
        }
        const uint status = halted ? 1u : (cycled ? 2u : 0u);
        device uint *packed = reinterpret_cast<device uint *>(result_bytes);
        packed[tid] = (status & 3u) | (uint(output) << 2);
    } else {
        MachineState checkpoint = state;
        ulong power = 1ul;
        ulong distance = 0ul;
        ulong output = 0ul;
        ulong steps = 0ul;
        bool halted = false;
        bool cycled = false;
        bool overflow = false;
        while (steps < params.step_limit) {
            halted = execute(state, output, overflow);
            if (halted) { ++steps; break; }
            if (overflow) { steps = params.step_limit; break; }
            ++steps;
            ++distance;
            if (same_state(state, checkpoint)) { cycled = true; break; }
            if (distance == power) {
                checkpoint = state;
                power = power <= (~0ul) / 2ul ? power * 2ul : ~0ul;
                distance = 0ul;
            }
        }
        const uint status = halted ? 1u : (cycled ? 2u : 0u);
        device Result *results = reinterpret_cast<device Result *>(result_bytes);
        results[tid].steps = steps;
        results[tid].output_characters = output;
        results[tid].status = status;
        results[tid].reserved = 0;
    }
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
    void add(uint64_t amount) {
        if (two_to_64) return;
        if (amount > UINT64_MAX - low) two_to_64 = true;
        low += amount;
    }
    bool zero() const { return low == 0 && !two_to_64; }
    std::string string() const { return two_to_64 ? "18446744073709551616" : std::to_string(low); }
};

struct BatchSummary {
    uint64_t halted = 0;
    uint64_t cycled = 0;
    uint64_t errors = 0;
    uint64_t gpu_halted = 0;
    uint64_t gpu_cycled = 0;
    uint64_t cpu_fallback = 0;
    uint64_t best = 0;
    uint64_t winners = 0;
    uint64_t first_index = UINT64_MAX;
    std::array<uint8_t, 16> first_program{};
    std::vector<uint64_t> best_indices;
};

void write_candidate_record(std::ofstream &output, uint64_t candidate_id,
                            uint64_t length, uint64_t output_characters) {
    std::array<uint8_t, 16> program{};
    uint64_t encoded = candidate_id;
    for (uint64_t i = length; i > 0; --i) {
        program[static_cast<size_t>(i - 1)] = static_cast<uint8_t>(encoded & 15U);
        encoded >>= 4;
    }
    output << "{\"schema\":\"4917-metal-candidate-log-v1\",\"length\":" << length
           << ",\"candidate_id\":\"" << candidate_id
           << "\",\"output_characters\":\"" << output_characters
           << "\",\"program\":[";
    for (uint64_t i = 0; i < length; ++i)
        output << (i == 0 ? "" : ",") << static_cast<unsigned>(program[static_cast<size_t>(i)]);
    output << "]}\n";
}

std::string json_quote(const std::string &value) {
    std::string escaped = "\"";
    for (unsigned char ch : value) {
        switch (ch) {
        case '"': escaped += "\\\""; break;
        case '\\': escaped += "\\\\"; break;
        case '\b': escaped += "\\b"; break;
        case '\f': escaped += "\\f"; break;
        case '\n': escaped += "\\n"; break;
        case '\r': escaped += "\\r"; break;
        case '\t': escaped += "\\t"; break;
        default:
            if (ch < 0x20) {
                constexpr char hex[] = "0123456789abcdef";
                escaped += "\\u00";
                escaped += hex[ch >> 4];
                escaped += hex[ch & 0x0f];
            } else {
                escaped += static_cast<char>(ch);
            }
        }
    }
    escaped += '"';
    return escaped;
}

class WorkerPool {
public:
    explicit WorkerPool(unsigned count) {
        threads_.reserve(count);
        for (unsigned i = 0; i < count; ++i)
            threads_.emplace_back([this, i] { worker_loop(i); });
    }

    ~WorkerPool() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            stopping_ = true;
            ++generation_;
        }
        ready_.notify_all();
        for (auto &thread : threads_) thread.join();
    }

    void run(std::function<void(unsigned)> task) {
        std::unique_lock<std::mutex> lock(mutex_);
        task_ = std::move(task);
        remaining_ = static_cast<unsigned>(threads_.size());
        ++generation_;
        ready_.notify_all();
        complete_.wait(lock, [this] { return remaining_ == 0; });
        task_ = {};
    }

private:
    void worker_loop(unsigned id) {
        uint64_t seen_generation = 0;
        for (;;) {
            std::function<void(unsigned)> task;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                ready_.wait(lock, [this, &seen_generation] {
                    return stopping_ || generation_ != seen_generation;
                });
                if (stopping_) return;
                seen_generation = generation_;
                task = task_;
            }
            task(id);
            {
                std::lock_guard<std::mutex> lock(mutex_);
                if (--remaining_ == 0) complete_.notify_one();
            }
        }
    }

    std::mutex mutex_;
    std::condition_variable ready_;
    std::condition_variable complete_;
    std::vector<std::thread> threads_;
    std::function<void(unsigned)> task_;
    uint64_t generation_ = 0;
    unsigned remaining_ = 0;
    bool stopping_ = false;
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
    std::puts("Usage: 4917-metal-search --length N [--gpu-step-limit N] [--winners-jsonl PATH] [--json]\n"
              "Exhaustively searches programs of 1-16 nibbles. GPU execution is bounded;\n"
              "every candidate not halted by the GPU budget is classified by the exact CPU runner.\n"
              "Always saves provisional best candidates to a JSONL file; --winners-jsonl overrides its path.\n"
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
               uint64_t length, uint64_t step_limit, bool compact_results,
               void *host_results) {
    @autoreleasepool {
    NSError *error = nil;
    const NSUInteger result_bytes = compact_results ? sizeof(uint32_t) * count
                                                    : sizeof(GpuResult) * count;
    id<MTLBuffer> result_buffer = [device newBufferWithLength:result_bytes
        options:MTLResourceStorageModeShared];
    if (result_buffer == nil) { std::fputs("Metal buffer allocation failed\n", stderr); return false; }
    GpuParameters params{base, step_limit, static_cast<uint32_t>(length), count,
                         compact_results ? 1U : 0U};
    id<MTLBuffer> parameter_buffer = [device newBufferWithBytes:&params length:sizeof(params)
        options:MTLResourceStorageModeShared];
    if (parameter_buffer == nil) {
        std::fputs("Metal parameter allocation failed\n", stderr);
        [result_buffer release];
        return false;
    }
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
        [parameter_buffer release];
        [result_buffer release];
        return false;
    }
    std::memcpy(host_results, result_buffer.contents, result_bytes);
    [parameter_buffer release];
    [result_buffer release];
    return true;
    }
}

struct BatchSlot {
    id<MTLBuffer> result_buffer = nil;
    id<MTLBuffer> parameter_buffer = nil;
    id<MTLCommandBuffer> command = nil;
    uint64_t base = 0;
    uint32_t count = 0;
};

bool initialize_slot(id<MTLDevice> device, BatchSlot &slot,
                     bool compact_results) {
    const NSUInteger bytes = compact_results ? sizeof(uint32_t) * kChunkSize
                                             : sizeof(GpuResult) * kChunkSize;
    slot.result_buffer = [device newBufferWithLength:bytes
        options:MTLResourceStorageModeShared];
    if (slot.result_buffer == nil) return false;
    GpuParameters empty{};
    slot.parameter_buffer = [device newBufferWithBytes:&empty length:sizeof(empty)
        options:MTLResourceStorageModeShared];
    return slot.parameter_buffer != nil;
}

bool submit_slot(id<MTLCommandQueue> queue, id<MTLComputePipelineState> pipeline,
                 BatchSlot &slot,
                 uint64_t base, uint32_t count, uint64_t length,
                 uint64_t step_limit, bool compact_results) {
    @autoreleasepool {
        GpuParameters params{base, step_limit, static_cast<uint32_t>(length), count,
                             compact_results ? 1U : 0U};
        std::memcpy(slot.parameter_buffer.contents, &params, sizeof(params));
        id<MTLCommandBuffer> command = [[queue commandBuffer] retain];
        id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
        [encoder setComputePipelineState:pipeline];
        [encoder setBuffer:slot.result_buffer offset:0 atIndex:0];
        [encoder setBuffer:slot.parameter_buffer offset:0 atIndex:1];
        const NSUInteger width = std::min<NSUInteger>(pipeline.maxTotalThreadsPerThreadgroup, 256);
        [encoder dispatchThreads:MTLSizeMake(count, 1, 1)
            threadsPerThreadgroup:MTLSizeMake(width, 1, 1)];
        [encoder endEncoding];
        [command commit];
        slot.command = command;
        slot.base = base;
        slot.count = count;
        return true;
    }
}

bool wait_slot(BatchSlot &slot) {
    [slot.command waitUntilCompleted];
    const bool ok = slot.command.status != MTLCommandBufferStatusError;
    if (!ok) {
        const char *message = slot.command.error.localizedDescription.UTF8String;
        std::fprintf(stderr, "Metal execution failed: %s\n",
                     message == nullptr ? "unknown error" : message);
    }
    [slot.command release];
    slot.command = nil;
    return ok;
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
        if (!run_batch(device, queue, pipeline, encoded, 1, length, step_limit, false, &gpu)) return 1;
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

int search(uint64_t length, uint64_t step_limit, bool json,
           const std::string &winner_jsonl_path) {
    @autoreleasepool {
        const bool save_candidate_log = !winner_jsonl_path.empty();
        std::ofstream winner_output;
        if (save_candidate_log) {
            winner_output.open(winner_jsonl_path, std::ios::out | std::ios::trunc);
            if (!winner_output) {
                std::fprintf(stderr, "could not open winners JSONL file: %s\n",
                             winner_jsonl_path.c_str());
                return 1;
            }
        }
        // Streaming log retains only batch-local ties that could still meet
        // the monotonically increasing provisional score threshold.
        std::atomic<uint64_t> best_seen{10};
        std::atomic<uint64_t> provisional_records{0};
        std::mutex output_mutex;
        bool output_failed = false;
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
        // IDs are lexicographic nibble vectors. Every program whose first
        // nibble is zero occupies this contiguous prefix and halts at once.
        const uint64_t skipped = uint64_t{1} << (4 * (length - 1));
        const uint64_t searched = full_space ? (uint64_t{15} << 60) : total - skipped;
        Counts halted, cycled, errors, winners, gpu_halted, gpu_cycled, cpu_fallback;
        uint64_t best = 0;
        uint64_t first_winner_index = UINT64_MAX;
        std::array<uint8_t, 16> first{};
        const bool use_compact_results = step_limit < (uint64_t{1} << 29);
        const unsigned worker_count = std::min<unsigned>(
            8U, std::max(1U, std::thread::hardware_concurrency()));
        WorkerPool workers(worker_count);
        const auto started = std::chrono::steady_clock::now();
        std::array<BatchSlot, 2> slots{};
        for (BatchSlot &slot : slots) {
            if (!initialize_slot(device, slot, use_compact_results)) {
                std::fputs("Metal buffer allocation failed\n", stderr);
                return 1;
            }
        }
        auto process_slot = [&](BatchSlot &slot) {
            if (!wait_slot(slot)) return false;
            const uint32_t count = slot.count;
            const uint64_t base = slot.base;
            const auto *compact = static_cast<const uint32_t *>(slot.result_buffer.contents);
            const auto *results = static_cast<const GpuResult *>(slot.result_buffer.contents);
            std::array<BatchSummary, 8> summaries{};
            std::atomic<uint32_t> next_candidate{0};
            workers.run([&](unsigned worker) {
                BatchSummary &summary = summaries[worker];
                for (;;) {
                    const uint32_t begin = next_candidate.fetch_add(4096, std::memory_order_relaxed);
                    if (begin >= count) break;
                    const uint32_t end = std::min<uint32_t>(count, begin + 4096);
                    for (uint32_t i = begin; i < end; ++i) {
                    uint64_t output_characters;
                    bool did_halt;
                    const uint32_t gpu_status = use_compact_results
                        ? compact[i] & 3U : results[i].status;
                    const uint64_t gpu_output = use_compact_results
                        ? static_cast<uint64_t>(compact[i] >> 2)
                        : results[i].output_characters;
                    if (gpu_status == kHalted) {
                        ++summary.gpu_halted;
                        output_characters = gpu_output;
                        did_halt = true;
                    } else if (gpu_status == kCycled) {
                        ++summary.cycled;
                        ++summary.gpu_cycled;
                        continue;
                    } else {
                        // Bounded GPU work never decides whether an unfinished
                        // candidate halts or cycles. Keep using exact CPU logic.
                        const i4917_run_result exact =
                            i4917_detail::run_search_aggregate_candidate(base + i, length);
                        ++summary.cpu_fallback;
                        output_characters = exact.output_characters;
                        did_halt = exact.termination == I4917_HALTED;
                        if (exact.termination == I4917_CYCLE) ++summary.cycled;
                        else if (exact.termination != I4917_HALTED) ++summary.errors;
                    }
                    if (!did_halt) continue;
                    ++summary.halted;
                    if (summary.winners == 0 || output_characters > summary.best) {
                        summary.best = output_characters;
                        summary.winners = 1;
                        if (save_candidate_log) {
                            summary.best_indices.clear();
                            if (output_characters > 10)
                                summary.best_indices.push_back(base + i);
                        }
                        summary.first_index = base + i;
                        std::array<uint8_t, 16> program{};
                        uint64_t encoded = base + i;
                        for (uint64_t j = length; j > 0; --j) {
                            program[static_cast<size_t>(j - 1)] =
                                static_cast<uint8_t>(encoded & 15U);
                            encoded >>= 4;
                        }
                        summary.first_program = program;
                    } else if (output_characters == summary.best) {
                        ++summary.winners;
                        if (save_candidate_log && output_characters > 10)
                            summary.best_indices.push_back(base + i);
                        if (base + i < summary.first_index) {
                            summary.first_index = base + i;
                            std::array<uint8_t, 16> program{};
                            uint64_t encoded = base + i;
                            for (uint64_t j = length; j > 0; --j) {
                                program[static_cast<size_t>(j - 1)] =
                                    static_cast<uint8_t>(encoded & 15U);
                                encoded >>= 4;
                            }
                            summary.first_program = program;
                        }
                    }
                    }
                }
            });
            uint64_t batch_best = 0;
            uint64_t batch_winner_count = 0;
            uint64_t batch_first_index = UINT64_MAX;
            std::array<uint8_t, 16> batch_first_program{};
            std::vector<uint64_t> batch_best_indices;
            for (const BatchSummary &summary : summaries) {
                halted.add(summary.halted);
                cycled.add(summary.cycled);
                errors.add(summary.errors);
                gpu_halted.add(summary.gpu_halted);
                gpu_cycled.add(summary.gpu_cycled);
                cpu_fallback.add(summary.cpu_fallback);
                if (summary.winners == 0) continue;
                if (batch_winner_count == 0 || summary.best > batch_best) {
                    batch_best = summary.best;
                    batch_winner_count = summary.winners;
                    batch_first_index = summary.first_index;
                    batch_first_program = summary.first_program;
                    if (save_candidate_log)
                        batch_best_indices = summary.best_indices;
                } else if (summary.best == batch_best) {
                    batch_winner_count += summary.winners;
                    if (summary.first_index < batch_first_index) {
                        batch_first_index = summary.first_index;
                        batch_first_program = summary.first_program;
                    }
                    if (save_candidate_log)
                        batch_best_indices.insert(batch_best_indices.end(),
                                                  summary.best_indices.begin(),
                                                  summary.best_indices.end());
                }
            }
            if (batch_winner_count == 0) return true;

            if (save_candidate_log) {
                uint64_t seen = best_seen.load(std::memory_order_relaxed);
                while (batch_best > seen &&
                       !best_seen.compare_exchange_weak(
                           seen, batch_best, std::memory_order_relaxed)) {}
                if (batch_best > 10 &&
                    batch_best >= best_seen.load(std::memory_order_relaxed)) {
                    std::lock_guard<std::mutex> lock(output_mutex);
                    for (uint64_t candidate_id : batch_best_indices) {
                        write_candidate_record(winner_output, candidate_id, length, batch_best);
                        if (winner_output) ++provisional_records;
                        else output_failed = true;
                    }
                }
            }

            const bool new_global_best = winners.zero() || batch_best > best;
            const bool ties_global_best = batch_best == best;
            if (new_global_best) {
                best = batch_best;
                winners = Counts{batch_winner_count, false};
                first_winner_index = batch_first_index;
                first = batch_first_program;
            } else if (ties_global_best) {
                winners.add(batch_winner_count);
                if (batch_first_index < first_winner_index) {
                    first_winner_index = batch_first_index;
                    first = batch_first_program;
                }
            }

            return !output_failed;
        };
        uint64_t base = skipped;
        bool finished = false;
        bool pending = false;
        unsigned active_slot = 0;
        while (!finished) {
            uint32_t count = kChunkSize;
            if (!full_space) {
                const uint64_t remaining = total - base;
                count = static_cast<uint32_t>(std::min<uint64_t>(remaining, kChunkSize));
            } else if (base > UINT64_MAX - (kChunkSize - 1U)) {
                count = static_cast<uint32_t>(UINT64_MAX - base + 1U);
            }
            if (!submit_slot(queue, pipeline, slots[active_slot], base, count,
                             length, step_limit, use_compact_results)) return 1;
            if (pending && !process_slot(slots[active_slot ^ 1U])) return 1;
            pending = true;
            active_slot ^= 1U;
            const uint64_t last = base + count - 1U;
            if (full_space) {
                if (last == UINT64_MAX) finished = true;
                else base = last + 1U;
            } else if (last + 1U == total) finished = true;
            else base = last + 1U;
        }
        if (pending && !process_slot(slots[active_slot ^ 1U])) return 1;
        // Immediate halts tie for best only when no output was produced by
        // any searched candidate; ID zero is then the first winner.
        if (best == 0) {
            winners.add(skipped);
            first_winner_index = 0;
        }
        if (save_candidate_log) {
            winner_output.flush();
            if (!winner_output || output_failed) {
                std::fprintf(stderr, "could not write provisional candidate log: %s\n",
                             winner_jsonl_path.c_str());
                return 1;
            }
        }
        for (BatchSlot &slot : slots) {
            [slot.result_buffer release];
            [slot.parameter_buffer release];
        }
        const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
        const std::string candidate_count = std::to_string(searched);
        const std::string search_space_count = full_space ? "18446744073709551616" : std::to_string(total);
        if (json) {
            std::printf("{\"schema\":\"4917-metal-search-v1\",\"length\":%" PRIu64
                        ",\"candidate_count\":\"%s\",\"search_space_count\":\"%s\","
                        "\"skipped_candidate_count\":\"%s\",\"halted\":\"%s\",\"cycled\":\"%s\","
                        "\"errors\":\"%s\",\"exhaustive\":%s,\"best_output_characters\":\"%" PRIu64
                        "\",\"winner_count\":\"%s\",\"first_winner\":[",
                        length, candidate_count.c_str(), search_space_count.c_str(),
                        std::to_string(skipped).c_str(), halted.string().c_str(), cycled.string().c_str(),
                        errors.string().c_str(), errors.zero() ? "true" : "false", best, winners.string().c_str());
            for (uint64_t i = 0; i < length; ++i)
                std::printf("%s%u", i ? "," : "", static_cast<unsigned>(first[static_cast<size_t>(i)]));
            std::printf("],\"gpu_halted\":\"%s\",\"gpu_cycled\":\"%s\","
                        "\"cpu_exact_fallback\":\"%s\",\"seconds\":%.6f",
                        gpu_halted.string().c_str(), gpu_cycled.string().c_str(),
                        cpu_fallback.string().c_str(), seconds);
            if (save_candidate_log) {
                const std::string winners_file_json = json_quote(winner_jsonl_path);
                std::printf(",\"candidate_log_saved\":true,\"candidate_log_entries\":\"%" PRIu64
                            "\",\"candidate_log_file\":%s",
                            provisional_records.load(), winners_file_json.c_str());
            }
            std::puts("}");
        } else {
            std::printf("GPU: %s (%s)\nsearched candidates: %s\nsearch space: %s\n"
                        "skipped immediate-zero candidates: %" PRIu64 "\nhalted: %s\ncycled: %s\nerrors: %s\n"
                        "exhaustive: %s\nbest output characters: %" PRIu64 "\nwinner count: %s\n"
                        "GPU halted: %s\nGPU cycled: %s\nCPU exact fallback: %s\nelapsed seconds: %.3f\n",
                        device.name.UTF8String, "Metal", candidate_count.c_str(), search_space_count.c_str(), skipped,
                        halted.string().c_str(), cycled.string().c_str(), errors.string().c_str(),
                        errors.zero() ? "yes" : "no", best, winners.string().c_str(),
                        gpu_halted.string().c_str(), gpu_cycled.string().c_str(),
                        cpu_fallback.string().c_str(), seconds);
            if (save_candidate_log)
                std::printf("provisional candidate records: %" PRIu64 "\nfile: %s\n",
                            provisional_records.load(), winner_jsonl_path.c_str());
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
    std::string winner_jsonl_path;
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
        } else if (std::strcmp(argv[i], "--winners-jsonl") == 0 && i + 1 < argc) {
            winner_jsonl_path = argv[++i];
            if (winner_jsonl_path.empty()) {
                std::fputs("--winners-jsonl requires a non-empty path\n", stderr);
                return 2;
            }
        } else { std::fprintf(stderr, "unknown or incomplete argument: %s\n", argv[i]); return 2; }
    }
    if (has_program) {
        if (has_length) { std::fputs("use either --program or --length, not both\n", stderr); return 2; }
        if (!winner_jsonl_path.empty()) {
            std::fputs("--winners-jsonl is only valid with --length\n", stderr);
            return 2;
        }
        return run_one(program, length, step_limit, json);
    }
    if (length < 1 || length > 16) { std::fputs("--length must be from 1 through 16\n", stderr); return 2; }
    if (winner_jsonl_path.empty()) {
        winner_jsonl_path = "metal-search-length-" + std::to_string(length) +
                            "-provisional-winners.jsonl";
    }
    return search(length, step_limit, json, winner_jsonl_path);
}
