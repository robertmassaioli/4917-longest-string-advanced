#include "4917/machine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static void step_case(uint8_t op, uint8_t r0, uint8_t r1, uint8_t operand, uint8_t er0, uint8_t er1,
                      uint8_t epc) {
    i4917_state s = {{0}, r0, r1, 15, 0};
    s.memory[15] = op;
    s.memory[0] = operand;
    s.memory[operand] = 12;
    i4917_event e;
    assert(i4917_step(&s, &e) == I4917_OK);
    assert(s.r0 == er0);
    assert(s.r1 == er1);
    assert(s.pc == epc);
}
int main(void) {
    /* Arithmetic laws cover every operand pair and wrap in both directions. */
    for (unsigned a = 0; a < 16; a++)
        for (unsigned b = 0; b < 16; b++) {
            i4917_state s = {{1}, (uint8_t)a, (uint8_t)b, 0, 0};
            i4917_event e;
            assert(i4917_step(&s, &e) == I4917_OK);
            assert(s.r0 == ((a + b) & 15));
            s = (i4917_state){{2}, (uint8_t)a, (uint8_t)b, 0, 0};
            assert(i4917_step(&s, &e) == I4917_OK);
            assert(s.r0 == ((a - b) & 15));
        }
    step_case(1, 15, 1, 2, 0, 1, 0);
    step_case(2, 0, 1, 2, 15, 1, 0);
    step_case(3, 15, 2, 2, 0, 2, 0);
    step_case(4, 2, 15, 2, 2, 0, 0);
    step_case(5, 0, 2, 2, 15, 2, 0);
    step_case(6, 2, 0, 2, 2, 15, 0);
    step_case(7, 2, 3, 2, 2, 3, 0);
    step_case(0, 2, 3, 2, 2, 3, 0);
    /* Operand wraps from cell 15 to 0; OUTPUT 15 adds two characters. */
    i4917_state s = {{0}, 0, 0, 15, 0};
    s.memory[15] = 8;
    s.memory[0] = 15;
    i4917_event e;
    assert(i4917_step(&s, &e) == I4917_OK && e.emitted && e.value == 15 && s.pc == 1 &&
           s.output_characters == 2);
    /* Load/store use pre-write operand and target values; stores self-modify. */
    s = (i4917_state){{0}, 7, 3, 0, 0};
    s.memory[0] = 11;
    s.memory[1] = 0;
    assert(i4917_step(&s, &e) == I4917_OK);
    assert(s.memory[0] == 7 && s.pc == 2);
    /* Branch outcomes and target cell 15. */
    s = (i4917_state){{0}, 0, 0, 14, 0};
    s.memory[14] = 14;
    s.memory[15] = 15;
    assert(i4917_step(&s, &e) == I4917_OK && s.pc == 15);
    s.r0 = 1;
    assert(i4917_step(&s, &e) == I4917_OK && s.pc == 0);
    s = (i4917_state){{0}, 0, 0, 0, 0};
    s.memory[0] = 9;
    s.memory[1] = 15;
    s.memory[15] = 7;
    assert(i4917_step(&s, &e) == I4917_OK && s.r0 == 7 && s.pc == 2);
    s = (i4917_state){{0}, 4, 0, 0, 0};
    s.memory[0] = 10;
    s.memory[1] = 15;
    s.memory[15] = 13;
    assert(i4917_step(&s, &e) == I4917_OK && s.r1 == 13 && s.r0 == 4 && s.pc == 2);
    s = (i4917_state){{0}, 4, 9, 0, 0};
    s.memory[0] = 12;
    s.memory[1] = 15;
    assert(i4917_step(&s, &e) == I4917_OK && s.memory[15] == 9 && s.pc == 2);
    for (unsigned target = 0; target < 16; target++) {
        s = (i4917_state){{0}, 9, 0, 0, 0};
        s.memory[0] = 11;
        s.memory[1] = (uint8_t)target;
        assert(i4917_step(&s, &e) == I4917_OK && s.memory[target] == 9 && s.pc == 2);
    }
    s = (i4917_state){{0}, 0, 0, 0, 0};
    s.memory[0] = 13;
    s.memory[1] = 12;
    assert(i4917_step(&s, &e) == I4917_OK && s.pc == 12);
    s = (i4917_state){{0}, 0, 0, 0, 0};
    s.memory[0] = 15;
    s.memory[1] = 12;
    assert(i4917_step(&s, &e) == I4917_OK && s.pc == 2);
    s = (i4917_state){{0}, 0, 0, 1, 0};
    s.memory[1] = 0;
    assert(i4917_step(&s, &e) == I4917_OK && e.halted && s.pc == 2);
    s = (i4917_state){{0}, 0, 0, 15, 0};
    s.memory[15] = 7;
    assert(i4917_step(&s, &e) == I4917_OK && !e.halted && s.pc == 0);
    for (unsigned value = 0; value < 16; value++) {
        s = (i4917_state){{0}, 3, 4, 0, 99};
        s.memory[0] = 8;
        s.memory[1] = (uint8_t)value;
        assert(i4917_step(&s, &e) == I4917_OK && e.emitted && e.value == value);
        assert(s.output_characters == 99 + (value < 10 ? 1 : 2) && s.r0 == 3 && s.r1 == 4);
    }
    for (unsigned pc = 0; pc < 16; pc++)
        for (unsigned op = 0; op < 16; op++) {
            s = (i4917_state){{0}, 0, 15, (uint8_t)pc, 0};
            s.memory[15] = 9;
            s.memory[pc] = (uint8_t)op;
            s.memory[(pc + 1) & 15] = 15;
            assert(i4917_state_valid(&s));
            assert(i4917_step(&s, &e) == I4917_OK);
            assert(i4917_state_valid(&s));
        }
    /* Bounded boundary: zero limit, HALT on last permitted step, reset state. */
    i4917_state init;
    i4917_init(&init, (uint8_t[]){3, 0}, 2);
    init.r0 = 9;
    init.output_characters = 90;
    i4917_run_result r = i4917_run_bounded(&init, 0);
    assert(r.termination == I4917_LIMIT_REACHED && r.steps == 0);
    r = i4917_run_bounded(&init, 2);
    assert(r.termination == I4917_HALTED && r.steps == 2 && r.final_state.r0 == 1);
    /* Output loop and self-modifying program distinguish cycle identity. */
    i4917_init(&init, (uint8_t[]){8, 1, 13, 0}, 4);
    r = i4917_run_until_halt_or_cycle(&init);
    assert(r.termination == I4917_CYCLE && r.output_characters > 0);
    i4917_init(&init, (uint8_t[]){11, 0, 13, 0}, 4);
    r = i4917_run_until_halt_or_cycle(&init);
    assert(r.termination == I4917_HALTED && r.steps == 3);
    /* Deterministic generated step/run equivalence and valid-state invariants. */
    uint32_t seed = 0x4917u;
    for (unsigned trial = 0; trial < 10000; trial++) {
        uint32_t trial_seed = seed;
        uint8_t p[16];
        for (unsigned i = 0; i < 16; i++) {
            seed = seed * 1664525u + 1013904223u;
            p[i] = (uint8_t)(seed >> 28);
        }
        i4917_init(&init, p, 16);
        i4917_state walked = init;
        bool halted = false;
        uint64_t steps = 0;
        for (; steps < 64; steps++) {
            assert(i4917_state_valid(&walked));
            assert(i4917_step(&walked, &e) == I4917_OK);
            if (e.halted) {
                halted = true;
                steps++;
                break;
            }
        }
        r = i4917_run_bounded(&init, steps);
        if (r.termination != (halted ? I4917_HALTED : I4917_LIMIT_REACHED) || r.steps != steps ||
            memcmp(&r.final_state, &walked, sizeof(walked)) != 0) {
            fprintf(stderr, "generated mismatch: seed=0x%08x trial=%u limit=%llu\n", trial_seed,
                    trial, (unsigned long long)steps);
            return 1;
        }
    }
    s = (i4917_state){{0}, 16, 0, 0, 0};
    assert(!i4917_state_valid(&s));
    s = (i4917_state){{0}, 0, 0, 0, UINT64_MAX};
    s.memory[0] = 8;
    s.memory[1] = 15;
    assert(i4917_step(&s, &e) == I4917_OVERFLOW && s.output_characters == UINT64_MAX);
    puts("4917 C unit/property checks passed");
    return 0;
}
