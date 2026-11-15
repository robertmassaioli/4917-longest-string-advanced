#include "4917/machine.h"

#include <string.h>

bool i4917_state_valid(const i4917_state *s) {
    if (s == NULL || s->r0 > 15 || s->r1 > 15 || s->pc > 15) return false;
    for (size_t i = 0; i < I4917_MEMORY_SIZE; ++i) if (s->memory[i] > 15) return false;
    return true;
}

void i4917_init(i4917_state *s, const uint8_t *program, size_t length) {
    memset(s, 0, sizeof(*s));
    if (length > I4917_MEMORY_SIZE) length = I4917_MEMORY_SIZE;
    if (program != NULL && length != 0) memcpy(s->memory, program, length);
}

i4917_error i4917_step(i4917_state *s, i4917_event *event) {
    if (!i4917_state_valid(s) || event == NULL) return I4917_INVALID_STATE;
    *event = (i4917_event){0};
    const uint8_t pc = s->pc;
    const uint8_t op = s->memory[pc];
    const uint8_t operand_pc = (uint8_t)((pc + 1u) & 15u);
    const uint8_t after_operand = (uint8_t)((pc + 2u) & 15u);
    const uint8_t operand = s->memory[operand_pc];
    const uint8_t target = s->memory[operand];
    const uint8_t next = (uint8_t)((pc + 1u) & 15u);
    switch (op) {
    case 0: s->pc = next; event->halted = true; break;
    case 1: s->r0 = (uint8_t)((s->r0 + s->r1) & 15u); s->pc = next; break;
    case 2: s->r0 = (uint8_t)((s->r0 + 16u - s->r1) & 15u); s->pc = next; break;
    case 3: s->r0 = (uint8_t)((s->r0 + 1u) & 15u); s->pc = next; break;
    case 4: s->r1 = (uint8_t)((s->r1 + 1u) & 15u); s->pc = next; break;
    case 5: s->r0 = (uint8_t)((s->r0 - 1u) & 15u); s->pc = next; break;
    case 6: s->r1 = (uint8_t)((s->r1 - 1u) & 15u); s->pc = next; break;
    case 7: s->pc = next; break;
    case 8:
        if (s->output_characters > UINT64_MAX - (operand < 10 ? 1u : 2u)) return I4917_OVERFLOW;
        s->output_characters += operand < 10 ? 1u : 2u;
        s->pc = after_operand; event->emitted = true; event->value = operand; break;
    case 9: s->r0 = target; s->pc = after_operand; break;
    case 10: s->r1 = target; s->pc = after_operand; break;
    case 11: s->memory[operand] = s->r0; s->pc = after_operand; break;
    case 12: s->memory[operand] = s->r1; s->pc = after_operand; break;
    case 13: s->pc = operand; break;
    case 14: s->pc = s->r0 == 0 ? operand : after_operand; break;
    case 15: s->pc = s->r0 != 0 ? operand : after_operand; break;
    default: return I4917_INVALID_STATE;
    }
    return I4917_OK;
}

static bool same_execution(const i4917_state *a, const i4917_state *b) {
    return a->r0 == b->r0 && a->r1 == b->r1 && a->pc == b->pc &&
           memcmp(a->memory, b->memory, I4917_MEMORY_SIZE) == 0;
}

static i4917_run_result result(i4917_state s, uint64_t steps, uint64_t start_output, i4917_termination why) {
    i4917_run_result r = {s, steps, s.output_characters - start_output, why};
    return r;
}

i4917_run_result i4917_run_bounded(const i4917_state *initial, uint64_t limit) {
    if (initial == NULL) { i4917_state empty = {0}; return result(empty, 0, 0, I4917_RUN_ERROR); }
    i4917_state s = *initial;
    const uint64_t initial_output = s.output_characters;
    if (!i4917_state_valid(&s)) return result(s, 0, initial_output, I4917_RUN_ERROR);
    s.r0 = s.r1 = s.pc = 0; s.output_characters = 0;
    for (uint64_t n = 0; n < limit; ++n) {
        i4917_event event;
        if (i4917_step(&s, &event) != I4917_OK) return result(s, n, 0, I4917_RUN_ERROR);
        if (event.halted) return result(s, n + 1, 0, I4917_HALTED);
    }
    return result(s, limit, 0, I4917_LIMIT_REACHED);
}

/* Floyd's algorithm only needs two machine states, regardless of the cycle
   length. Output count is bookkeeping and does not affect future execution;
   clear it on speculative steps so an infinite output loop cannot overflow
   while the hare runs ahead. Once a halt/cycle is known, replay the real path
   to preserve the execution result and detect genuine output-count overflow. */
static i4917_error advance_execution(i4917_state *s, bool *halted) {
    s->output_characters = 0;
    i4917_event event;
    i4917_error error = i4917_step(s, &event);
    s->output_characters = 0;
    *halted = error == I4917_OK && event.halted;
    return error;
}

static i4917_run_result replay_to_halt(i4917_state s) {
    s.r0 = s.r1 = s.pc = 0;
    s.output_characters = 0;
    for (uint64_t n = 0; n < UINT64_MAX; ++n) {
        i4917_event event;
        if (i4917_step(&s, &event) != I4917_OK) return result(s, n, 0, I4917_RUN_ERROR);
        if (event.halted) return result(s, n + 1, 0, I4917_HALTED);
    }
    return result(s, UINT64_MAX, 0, I4917_RUN_ERROR);
}

static i4917_run_result replay_cycle(i4917_state initial, uint64_t cycle_steps) {
    initial.r0 = initial.r1 = initial.pc = 0;
    initial.output_characters = 0;
    for (uint64_t n = 0; n < cycle_steps; ++n) {
        i4917_event event;
        if (i4917_step(&initial, &event) != I4917_OK) return result(initial, n, 0, I4917_RUN_ERROR);
    }
    return result(initial, cycle_steps, 0, I4917_CYCLE);
}

i4917_run_result i4917_run_until_halt_or_cycle(const i4917_state *initial) {
    if (initial == NULL) { i4917_state empty = {0}; return result(empty, 0, 0, I4917_RUN_ERROR); }
    i4917_state start = *initial;
    const uint64_t initial_output = start.output_characters;
    if (!i4917_state_valid(&start)) return result(start, 0, initial_output, I4917_RUN_ERROR);
    start.r0 = start.r1 = start.pc = 0;
    start.output_characters = 0;

    i4917_state tortoise = start, hare = start;
    for (;;) {
        bool halted = false;
        if (advance_execution(&tortoise, &halted) != I4917_OK) return result(tortoise, 0, 0, I4917_RUN_ERROR);
        if (halted) return replay_to_halt(start);

        if (advance_execution(&hare, &halted) != I4917_OK) return result(hare, 0, 0, I4917_RUN_ERROR);
        if (halted) return replay_to_halt(start);
        if (advance_execution(&hare, &halted) != I4917_OK) return result(hare, 0, 0, I4917_RUN_ERROR);
        if (halted) return replay_to_halt(start);

        if (same_execution(&tortoise, &hare)) break;
    }

    /* Find the cycle entry (mu), then its length (lambda). */
    i4917_state entry = start, meeting = tortoise;
    uint64_t mu = 0;
    while (!same_execution(&entry, &meeting)) {
        bool halted = false;
        if (advance_execution(&entry, &halted) != I4917_OK || halted || mu == UINT64_MAX)
            return result(entry, mu, 0, I4917_RUN_ERROR);
        if (advance_execution(&meeting, &halted) != I4917_OK || halted)
            return result(meeting, mu, 0, I4917_RUN_ERROR);
        ++mu;
    }
    i4917_state cursor = entry;
    bool halted = false;
    if (advance_execution(&cursor, &halted) != I4917_OK || halted)
        return result(cursor, mu, 0, I4917_RUN_ERROR);
    uint64_t lambda = 1;
    while (!same_execution(&entry, &cursor)) {
        if (advance_execution(&cursor, &halted) != I4917_OK || halted || lambda == UINT64_MAX)
            return result(cursor, mu + lambda, 0, I4917_RUN_ERROR);
        ++lambda;
    }
    if (mu > UINT64_MAX - lambda) return result(entry, UINT64_MAX, 0, I4917_RUN_ERROR);
    return replay_cycle(start, mu + lambda);
}
