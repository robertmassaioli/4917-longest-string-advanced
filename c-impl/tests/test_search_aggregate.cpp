#include "4917/machine.h"
#include "machine_internal.hpp"

#include <array>
#include <cassert>
#include <cstdint>
#include <cstdio>

static void compare(const std::array<uint8_t, I4917_MEMORY_SIZE> &memory) {
    i4917_state initial{};
    for (size_t i = 0; i < memory.size(); ++i)
        initial.memory[i] = memory[i];

    const i4917_run_result expected = i4917_run_until_halt_or_cycle(&initial);
    const i4917_run_result actual = i4917_detail::run_search_aggregate_program(memory);
    assert(actual.termination == expected.termination);
    if (expected.termination == I4917_HALTED) {
        assert(actual.steps == expected.steps);
        assert(actual.output_characters == expected.output_characters);
        assert(actual.final_state.r0 == expected.final_state.r0);
        assert(actual.final_state.r1 == expected.final_state.r1);
        assert(actual.final_state.pc == expected.final_state.pc);
        for (size_t i = 0; i < memory.size(); ++i)
            assert(actual.final_state.memory[i] == expected.final_state.memory[i]);
    }
}

int main() {
    // Exhaustive short domains cover each opcode, wrapped operands, and stores.
    for (uint32_t length = 1; length <= 4; ++length) {
        const uint32_t total = uint32_t{1} << (4U * length);
        for (uint32_t id = 0; id < total; ++id) {
            uint32_t encoded = id;
            std::array<uint8_t, I4917_MEMORY_SIZE> memory{};
            for (uint32_t cell = length; cell > 0; --cell) {
                memory[cell - 1] = static_cast<uint8_t>(encoded & 15U);
                encoded >>= 4U;
            }
            compare(memory);
        }
    }

    // Exercise arbitrary full-memory programs, including self-modifying code.
    uint32_t random = 0x4917U;
    for (uint32_t sample = 0; sample < 10000; ++sample) {
        std::array<uint8_t, I4917_MEMORY_SIZE> memory{};
        for (uint8_t &cell : memory) {
            random = random * 1664525U + 1013904223U;
            cell = static_cast<uint8_t>((random >> 28U) & 15U);
        }
        compare(memory);
    }

    std::puts("search aggregate runner matches exact runner");
    return 0;
}
