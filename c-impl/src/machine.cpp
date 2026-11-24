#include "4917/machine.h"
#include "machine_internal.hpp"

#include <cstring>

bool i4917_state_valid(const i4917_state *s) {
    if (s == NULL || s->r0 > 15 || s->r1 > 15 || s->pc > 15)
        return false;
    for (size_t i = 0; i < I4917_MEMORY_SIZE; ++i)
        if (s->memory[i] > 15)
            return false;
    return true;
}

void i4917_init(i4917_state *s, const uint8_t *program, size_t length) {
    memset(s, 0, sizeof(*s));
    if (length > I4917_MEMORY_SIZE)
        length = I4917_MEMORY_SIZE;
    if (program != NULL && length != 0)
        memcpy(s->memory, program, length);
}

i4917_error i4917_step(i4917_state *s, i4917_event *event) {
    if (!i4917_state_valid(s) || event == NULL)
        return I4917_INVALID_STATE;
    *event = {};
    const uint8_t pc = s->pc;
    const uint8_t op = s->memory[pc];
    const uint8_t operand_pc = (uint8_t)((pc + 1u) & 15u);
    const uint8_t after_operand = (uint8_t)((pc + 2u) & 15u);
    const uint8_t operand = s->memory[operand_pc];
    const uint8_t target = s->memory[operand];
    const uint8_t next = (uint8_t)((pc + 1u) & 15u);
    switch (op) {
    case 0:
        s->pc = next;
        event->halted = true;
        break;
    case 1:
        s->r0 = (uint8_t)((s->r0 + s->r1) & 15u);
        s->pc = next;
        break;
    case 2:
        s->r0 = (uint8_t)((s->r0 + 16u - s->r1) & 15u);
        s->pc = next;
        break;
    case 3:
        s->r0 = (uint8_t)((s->r0 + 1u) & 15u);
        s->pc = next;
        break;
    case 4:
        s->r1 = (uint8_t)((s->r1 + 1u) & 15u);
        s->pc = next;
        break;
    case 5:
        s->r0 = (uint8_t)((s->r0 - 1u) & 15u);
        s->pc = next;
        break;
    case 6:
        s->r1 = (uint8_t)((s->r1 - 1u) & 15u);
        s->pc = next;
        break;
    case 7:
        s->pc = next;
        break;
    case 8:
        if (s->output_characters > UINT64_MAX - (operand < 10 ? 1u : 2u))
            return I4917_OVERFLOW;
        s->output_characters += operand < 10 ? 1u : 2u;
        s->pc = after_operand;
        event->emitted = true;
        event->value = operand;
        break;
    case 9:
        s->r0 = target;
        s->pc = after_operand;
        break;
    case 10:
        s->r1 = target;
        s->pc = after_operand;
        break;
    case 11:
        s->memory[operand] = s->r0;
        s->pc = after_operand;
        break;
    case 12:
        s->memory[operand] = s->r1;
        s->pc = after_operand;
        break;
    case 13:
        s->pc = operand;
        break;
    case 14:
        s->pc = s->r0 == 0 ? operand : after_operand;
        break;
    case 15:
        s->pc = s->r0 != 0 ? operand : after_operand;
        break;
    default:
        return I4917_INVALID_STATE;
    }
    return I4917_OK;
}

static bool same_execution(const i4917_state *a, const i4917_state *b) {
    return a->r0 == b->r0 && a->r1 == b->r1 && a->pc == b->pc &&
           std::memcmp(a->memory, b->memory, I4917_MEMORY_SIZE) == 0;
}

static i4917_run_result result(i4917_state s, uint64_t steps, uint64_t start_output,
                               i4917_termination why) {
    i4917_run_result r = {s, steps, s.output_characters - start_output, why};
    return r;
}

i4917_run_result i4917_run_bounded(const i4917_state *initial, uint64_t limit) {
    if (initial == NULL) {
        i4917_state empty{};
        return result(empty, 0, 0, I4917_RUN_ERROR);
    }
    i4917_state s = *initial;
    const uint64_t initial_output = s.output_characters;
    if (!i4917_state_valid(&s))
        return result(s, 0, initial_output, I4917_RUN_ERROR);
    uint8_t r0 = 0, r1 = 0, pc = 0;
    uint64_t output = 0;
    uint64_t steps = 0;
    while (steps < limit) {
        const uint8_t op = s.memory[pc];
        const uint8_t operand_pc = static_cast<uint8_t>((pc + 1U) & 15U);
        const uint8_t after_operand = static_cast<uint8_t>((pc + 2U) & 15U);
        const uint8_t operand = s.memory[operand_pc];
        const uint8_t next = operand_pc;
        bool halted = false;
        switch (op) {
        case 0: pc = next; halted = true; break;
        case 1: r0 = static_cast<uint8_t>((r0 + r1) & 15U); pc = next; break;
        case 2: r0 = static_cast<uint8_t>((r0 + 16U - r1) & 15U); pc = next; break;
        case 3: r0 = static_cast<uint8_t>((r0 + 1U) & 15U); pc = next; break;
        case 4: r1 = static_cast<uint8_t>((r1 + 1U) & 15U); pc = next; break;
        case 5: r0 = static_cast<uint8_t>((r0 - 1U) & 15U); pc = next; break;
        case 6: r1 = static_cast<uint8_t>((r1 - 1U) & 15U); pc = next; break;
        case 7: pc = next; break;
        case 8: {
            const uint64_t amount = operand < 10 ? 1U : 2U;
            if (output > UINT64_MAX - amount) {
                s.r0 = r0; s.r1 = r1; s.pc = pc; s.output_characters = output;
                return result(s, steps, 0, I4917_RUN_ERROR);
            }
            output += amount; pc = after_operand; break;
        }
        case 9: r0 = s.memory[operand]; pc = after_operand; break;
        case 10: r1 = s.memory[operand]; pc = after_operand; break;
        case 11: s.memory[operand] = r0; pc = after_operand; break;
        case 12: s.memory[operand] = r1; pc = after_operand; break;
        case 13: pc = operand; break;
        case 14: pc = r0 == 0 ? operand : after_operand; break;
        case 15: pc = r0 != 0 ? operand : after_operand; break;
        default:
            s.r0 = r0; s.r1 = r1; s.pc = pc; s.output_characters = output;
            return result(s, steps, 0, I4917_RUN_ERROR);
        }
        ++steps;
        if (halted) {
            s.r0 = r0; s.r1 = r1; s.pc = pc; s.output_characters = output;
            return result(s, steps, 0, I4917_HALTED);
        }
    }
    s.r0 = r0; s.r1 = r1; s.pc = pc; s.output_characters = output;
    return result(s, steps, 0, I4917_LIMIT_REACHED);
}

/* Detector states ignore output: speculative steps must not overflow before
   the actual execution does. Public stepping still validates every state. */
static void advance_execution(i4917_state *s) {
    const uint8_t pc = s->pc;
    const uint8_t next = static_cast<uint8_t>((pc + 1U) & 15U);
    const uint8_t after_operand = static_cast<uint8_t>((pc + 2U) & 15U);
    switch (s->memory[pc]) {
    case 0: s->pc = next; break;
    case 1: s->r0 = static_cast<uint8_t>((s->r0 + s->r1) & 15U); s->pc = next; break;
    case 2: s->r0 = static_cast<uint8_t>((s->r0 + 16U - s->r1) & 15U); s->pc = next; break;
    case 3: s->r0 = static_cast<uint8_t>((s->r0 + 1U) & 15U); s->pc = next; break;
    case 4: s->r1 = static_cast<uint8_t>((s->r1 + 1U) & 15U); s->pc = next; break;
    case 5: s->r0 = static_cast<uint8_t>((s->r0 - 1U) & 15U); s->pc = next; break;
    case 6: s->r1 = static_cast<uint8_t>((s->r1 - 1U) & 15U); s->pc = next; break;
    case 7: s->pc = next; break;
    case 8: s->pc = after_operand; break;
    case 9: s->r0 = s->memory[s->memory[next]]; s->pc = after_operand; break;
    case 10: s->r1 = s->memory[s->memory[next]]; s->pc = after_operand; break;
    case 11: s->memory[s->memory[next]] = s->r0; s->pc = after_operand; break;
    case 12: s->memory[s->memory[next]] = s->r1; s->pc = after_operand; break;
    case 13: s->pc = s->memory[next]; break;
    case 14: s->pc = s->r0 == 0 ? s->memory[next] : after_operand; break;
    case 15: s->pc = s->r0 != 0 ? s->memory[next] : after_operand; break;
    }
}

static i4917_run_result replay_execution(const i4917_state &initial, uint64_t limit,
                                        i4917_termination termination) {
    i4917_state s = initial;
    for (uint64_t n = 0; n < limit; ++n) {
        i4917_event event;
        if (i4917_step(&s, &event) != I4917_OK)
            return result(s, n, 0, I4917_RUN_ERROR);
        if (event.halted)
            return result(s, n + 1, 0, I4917_HALTED);
    }
    return result(s, limit, 0, termination);
}

/* Strictly increasing PCs cannot revisit an execution state. Count this
   prefix directly, then use constant-space Floyd detection if control goes
   backwards or wraps. Replay restores the first-repeat output semantics. */
static i4917_run_result run_initialized(i4917_state start) {
    i4917_state probe = start;
    for (uint64_t n = 0;; ++n) {
        const uint8_t old_pc = probe.pc;
        i4917_event event;
        if (i4917_step(&probe, &event) != I4917_OK)
            return result(probe, n, 0, I4917_RUN_ERROR);
        if (event.halted)
            return result(probe, n + 1, 0, I4917_HALTED);
        if (probe.pc <= old_pc)
            break;
    }

    i4917_state tortoise = start;
    i4917_state hare = start;
    uint64_t rounds = 0;
    do {
        advance_execution(&tortoise);
        advance_execution(&hare);
        advance_execution(&hare);
        if (++rounds == UINT64_MAX)
            return replay_execution(start, UINT64_MAX, I4917_RUN_ERROR);
    } while (!same_execution(&tortoise, &hare));

    uint64_t prefix = 0;
    tortoise = start;
    while (!same_execution(&tortoise, &hare)) {
        advance_execution(&tortoise);
        advance_execution(&hare);
        if (++prefix == UINT64_MAX)
            return replay_execution(start, UINT64_MAX, I4917_RUN_ERROR);
    }
    uint64_t period = 1;
    advance_execution(&hare);
    while (!same_execution(&tortoise, &hare)) {
        if (period == UINT64_MAX)
            return replay_execution(start, UINT64_MAX, I4917_RUN_ERROR);
        ++period;
        advance_execution(&hare);
    }
    if (prefix > UINT64_MAX - period)
        return replay_execution(start, UINT64_MAX, I4917_RUN_ERROR);
    return replay_execution(start, prefix + period, I4917_CYCLE);
}

/* Search-only variant: Brent finds the cycle length with fewer state
   transitions than Floyd. The final replay keeps the public first-repeat
   output semantics exactly. */
static i4917_run_result run_search_initialized_brent(i4917_state start) {
    i4917_state probe = start;
    for (uint64_t n = 0;; ++n) {
        const uint8_t old_pc = probe.pc;
        i4917_event event;
        if (i4917_step(&probe, &event) != I4917_OK)
            return result(probe, n, 0, I4917_RUN_ERROR);
        if (event.halted)
            return result(probe, n + 1, 0, I4917_HALTED);
        if (probe.pc <= old_pc)
            break;
    }

    i4917_state tortoise = start;
    i4917_state hare = start;
    advance_execution(&hare);
    uint64_t power = 1;
    uint64_t period = 1;
    while (!same_execution(&tortoise, &hare)) {
        if (power == period) {
            tortoise = hare;
            if (power > UINT64_MAX / 2)
                return replay_execution(start, UINT64_MAX, I4917_RUN_ERROR);
            power *= 2;
            period = 0;
        }
        advance_execution(&hare);
        if (period == UINT64_MAX)
            return replay_execution(start, UINT64_MAX, I4917_RUN_ERROR);
        ++period;
    }

    uint64_t prefix = 0;
    tortoise = start;
    hare = start;
    for (uint64_t n = 0; n < period; ++n)
        advance_execution(&hare);
    while (!same_execution(&tortoise, &hare)) {
        advance_execution(&tortoise);
        advance_execution(&hare);
        if (prefix == UINT64_MAX)
            return replay_execution(start, UINT64_MAX, I4917_RUN_ERROR);
        ++prefix;
    }
    if (prefix > UINT64_MAX - period)
        return replay_execution(start, UINT64_MAX, I4917_RUN_ERROR);
    return replay_execution(start, prefix + period, I4917_CYCLE);
}

struct PackedSearchState {
    uint64_t memory;
    uint8_t r0;
    uint8_t r1;
    uint8_t pc;
};

static uint8_t packed_cell(const PackedSearchState &state, uint8_t address) {
    return static_cast<uint8_t>((state.memory >> (4U * address)) & 15U);
}

static void packed_write(PackedSearchState &state, uint8_t address, uint8_t value) {
    const uint32_t shift = 4U * address;
    const uint64_t mask = uint64_t{15} << shift;
    state.memory = (state.memory & ~mask) | (static_cast<uint64_t>(value & 15U) << shift);
}

static bool same_packed_execution(const PackedSearchState &left,
                                  const PackedSearchState &right) {
    return left.memory == right.memory && left.r0 == right.r0 &&
           left.r1 == right.r1 && left.pc == right.pc;
}

static i4917_state unpack_packed_state(const PackedSearchState &packed, uint64_t output) {
    i4917_state state{};
    for (uint8_t cell = 0; cell < I4917_MEMORY_SIZE; ++cell)
        state.memory[cell] = packed_cell(packed, cell);
    state.r0 = packed.r0;
    state.r1 = packed.r1;
    state.pc = packed.pc;
    state.output_characters = output;
    return state;
}

static i4917_run_result packed_result(const PackedSearchState &state, uint64_t output,
                                      uint64_t steps, i4917_termination termination) {
    return result(unpack_packed_state(state, output), steps, 0, termination);
}

static i4917_run_result run_search_initialized_packed_aggregate(uint64_t memory) {
    const PackedSearchState start{memory, 0, 0, 0};
    PackedSearchState tortoise = start;
    PackedSearchState hare = start;
    PackedSearchState overflow_state{};
    uint64_t output = 0;
    uint64_t overflow_output = 0;
    uint64_t steps = 0;
    uint64_t overflow_steps = 0;
    uint64_t power = 1;
    uint64_t distance = 0;
    bool output_overflow = false;

    for (;;) {
        const uint8_t pc = hare.pc;
        const uint8_t op = packed_cell(hare, pc);
        const uint8_t operand_pc = static_cast<uint8_t>((pc + 1U) & 15U);
        const uint8_t after_operand = static_cast<uint8_t>((pc + 2U) & 15U);
        const uint8_t operand = packed_cell(hare, operand_pc);
        if (op == 0) {
            if (output_overflow)
                return packed_result(overflow_state, overflow_output,
                                     overflow_steps, I4917_RUN_ERROR);
            hare.pc = operand_pc;
            return packed_result(hare, output, steps + 1, I4917_HALTED);
        }

        switch (op) {
        case 1: hare.r0 = static_cast<uint8_t>((hare.r0 + hare.r1) & 15U); hare.pc = operand_pc; break;
        case 2: hare.r0 = static_cast<uint8_t>((hare.r0 + 16U - hare.r1) & 15U); hare.pc = operand_pc; break;
        case 3: hare.r0 = static_cast<uint8_t>((hare.r0 + 1U) & 15U); hare.pc = operand_pc; break;
        case 4: hare.r1 = static_cast<uint8_t>((hare.r1 + 1U) & 15U); hare.pc = operand_pc; break;
        case 5: hare.r0 = static_cast<uint8_t>((hare.r0 - 1U) & 15U); hare.pc = operand_pc; break;
        case 6: hare.r1 = static_cast<uint8_t>((hare.r1 - 1U) & 15U); hare.pc = operand_pc; break;
        case 7: hare.pc = operand_pc; break;
        case 8: {
            const uint64_t amount = operand < 10U ? 1U : 2U;
            if (!output_overflow && output > UINT64_MAX - amount) {
                output_overflow = true;
                overflow_state = hare;
                overflow_output = output;
                overflow_steps = steps;
            } else if (!output_overflow) {
                output += amount;
            }
            hare.pc = after_operand;
            break;
        }
        case 9: hare.r0 = packed_cell(hare, operand); hare.pc = after_operand; break;
        case 10: hare.r1 = packed_cell(hare, operand); hare.pc = after_operand; break;
        case 11: packed_write(hare, operand, hare.r0); hare.pc = after_operand; break;
        case 12: packed_write(hare, operand, hare.r1); hare.pc = after_operand; break;
        case 13: hare.pc = operand; break;
        case 14: hare.pc = hare.r0 == 0 ? operand : after_operand; break;
        case 15: hare.pc = hare.r0 != 0 ? operand : after_operand; break;
        default: return packed_result(hare, output, steps, I4917_RUN_ERROR);
        }

        if (steps == UINT64_MAX)
            return run_search_initialized_brent(unpack_packed_state(start, 0));
        ++steps;
        ++distance;

        if (same_packed_execution(tortoise, hare)) {
            if (steps <= UINT64_MAX / 2U)
                return packed_result(hare, 0, steps, I4917_CYCLE);
            return run_search_initialized_brent(unpack_packed_state(start, 0));
        }

        if (distance == power) {
            tortoise = hare;
            if (power > UINT64_MAX / 2U)
                return run_search_initialized_brent(unpack_packed_state(start, 0));
            power *= 2U;
            distance = 0;
        }
    }
}

i4917_run_result i4917_run_until_halt_or_cycle(const i4917_state *initial) {
    if (initial == NULL) {
        i4917_state empty{};
        return result(empty, 0, 0, I4917_RUN_ERROR);
    }
    i4917_state start = *initial;
    if (!i4917_state_valid(&start))
        return result(start, 0, start.output_characters, I4917_RUN_ERROR);
    start.r0 = start.r1 = start.pc = 0;
    start.output_characters = 0;
    return run_initialized(start);
}

i4917_run_result i4917_detail::run_search_program(
    const std::array<uint8_t, I4917_MEMORY_SIZE> &program) {
    i4917_state start{};
    std::memcpy(start.memory, program.data(), I4917_MEMORY_SIZE);
    return run_search_initialized_brent(start);
}

i4917_run_result i4917_detail::run_search_aggregate_program(
    const std::array<uint8_t, I4917_MEMORY_SIZE> &program) {
    uint64_t memory = 0;
    for (uint8_t cell = 0; cell < I4917_MEMORY_SIZE; ++cell)
        memory |= static_cast<uint64_t>(program[cell] & 15U) << (4U * cell);
    return run_search_initialized_packed_aggregate(memory);
}

i4917_run_result i4917_detail::run_search_aggregate_candidate(
    uint64_t candidate_id, uint64_t length) {
    if (length < 1 || length > I4917_MEMORY_SIZE ||
        (length < I4917_MEMORY_SIZE &&
         candidate_id >= (uint64_t{1} << (4U * static_cast<uint32_t>(length))))) {
        i4917_state empty{};
        return result(empty, 0, 0, I4917_RUN_ERROR);
    }
    uint64_t memory = 0;
    for (uint64_t cell = 0; cell < length; ++cell) {
        const uint32_t shift = static_cast<uint32_t>(4U * cell);
        const uint32_t source_shift = static_cast<uint32_t>(4U * (length - cell - 1U));
        memory |= ((candidate_id >> source_shift) & 15U) << shift;
    }
    return run_search_initialized_packed_aggregate(memory);
}
