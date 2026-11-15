#ifndef I4917_MACHINE_H
#define I4917_MACHINE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define I4917_MEMORY_SIZE 16

typedef struct {
    uint8_t memory[I4917_MEMORY_SIZE];
    uint8_t r0, r1, pc;
    uint64_t output_characters;
} i4917_state;

typedef struct {
    bool emitted;
    uint8_t value;
    bool halted;
} i4917_event;

typedef enum { I4917_OK = 0, I4917_OVERFLOW, I4917_INVALID_STATE } i4917_error;
typedef enum { I4917_HALTED, I4917_LIMIT_REACHED, I4917_CYCLE, I4917_RUN_ERROR } i4917_termination;

typedef struct {
    i4917_state final_state;
    uint64_t steps;
    uint64_t output_characters;
    i4917_termination termination;
} i4917_run_result;

bool i4917_state_valid(const i4917_state *state);
void i4917_init(i4917_state *state, const uint8_t *program, size_t length);
i4917_error i4917_step(i4917_state *state, i4917_event *event);
i4917_run_result i4917_run_bounded(const i4917_state *initial, uint64_t limit);
i4917_run_result i4917_run_until_halt_or_cycle(const i4917_state *initial);

#endif
