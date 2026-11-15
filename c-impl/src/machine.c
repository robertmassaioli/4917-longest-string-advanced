#include "4917/machine.h"

#include <stdlib.h>
#include <string.h>

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
    *event = (i4917_event){0};
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
           memcmp(a->memory, b->memory, I4917_MEMORY_SIZE) == 0;
}

static i4917_run_result result(i4917_state s, uint64_t steps, uint64_t start_output,
                               i4917_termination why) {
    i4917_run_result r = {s, steps, s.output_characters - start_output, why};
    return r;
}

i4917_run_result i4917_run_bounded(const i4917_state *initial, uint64_t limit) {
    if (initial == NULL) {
        i4917_state empty = {0};
        return result(empty, 0, 0, I4917_RUN_ERROR);
    }
    i4917_state s = *initial;
    const uint64_t initial_output = s.output_characters;
    if (!i4917_state_valid(&s)) return result(s, 0, initial_output, I4917_RUN_ERROR);
    uint8_t r0 = 0, r1 = 0, pc = 0;
    uint64_t output = 0;
    uint64_t steps = 0;
    while (steps < limit) {
        const uint8_t op = s.memory[pc];
        const uint8_t operand_pc = (uint8_t)((pc + 1u) & 15u);
        const uint8_t after_operand = (uint8_t)((pc + 2u) & 15u);
        const uint8_t operand = s.memory[operand_pc];
        const uint8_t next = operand_pc;
        bool halted = false;
        switch (op) {
        case 0: pc = next; halted = true; break;
        case 1: r0 = (uint8_t)((r0 + r1) & 15u); pc = next; break;
        case 2: r0 = (uint8_t)((r0 + 16u - r1) & 15u); pc = next; break;
        case 3: r0 = (uint8_t)((r0 + 1u) & 15u); pc = next; break;
        case 4: r1 = (uint8_t)((r1 + 1u) & 15u); pc = next; break;
        case 5: r0 = (uint8_t)((r0 - 1u) & 15u); pc = next; break;
        case 6: r1 = (uint8_t)((r1 - 1u) & 15u); pc = next; break;
        case 7: pc = next; break;
        case 8: {
            const uint64_t amount = operand < 10 ? 1u : 2u;
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

/* A visited-state table preserves the actual run prefix and avoids Floyd's
   speculative output problem. This mode is diagnostic; bounded hot execution
   uses the allocation-free loop above. */
i4917_run_result i4917_run_until_halt_or_cycle(const i4917_state *initial) {
    if (initial == NULL) {
        i4917_state empty = {0};
        return result(empty, 0, 0, I4917_RUN_ERROR);
    }
    i4917_state s = *initial;
    const uint64_t initial_output = s.output_characters;
    if (!i4917_state_valid(&s))
        return result(s, 0, initial_output, I4917_RUN_ERROR);
    s.r0 = s.r1 = s.pc = 0;
    s.output_characters = 0;
    size_t capacity = 1024, count = 0;
    i4917_state *seen = (i4917_state *)malloc(capacity * sizeof(*seen));
    if (seen == NULL)
        return result(s, 0, 0, I4917_RUN_ERROR);
    for (uint64_t n = 0;; ++n) {
        for (size_t i = 0; i < count; ++i)
            if (same_execution(&seen[i], &s)) {
                free(seen);
                return result(s, n, 0, I4917_CYCLE);
            }
        if (n == UINT64_MAX) {
            free(seen);
            return result(s, n, 0, I4917_RUN_ERROR);
        }
        if (count == capacity) {
            if (capacity > SIZE_MAX / 2 / sizeof(*seen)) {
                free(seen);
                return result(s, n, 0, I4917_RUN_ERROR);
            }
            capacity *= 2;
            i4917_state *grown = (i4917_state *)realloc(seen, capacity * sizeof(*seen));
            if (grown == NULL) {
                free(seen);
                return result(s, n, 0, I4917_RUN_ERROR);
            }
            seen = grown;
        }
        seen[count++] = s;
        i4917_event event;
        if (i4917_step(&s, &event) != I4917_OK) {
            free(seen);
            return result(s, n, 0, I4917_RUN_ERROR);
        }
        if (event.halted) {
            free(seen);
            return result(s, n + 1, 0, I4917_HALTED);
        }
    }
}
