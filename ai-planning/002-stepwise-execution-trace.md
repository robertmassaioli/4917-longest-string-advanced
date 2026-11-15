# 002: Step-by-step program execution trace

**Status:** Proposed  
**Created:** 2026-11-15

## Summary

Add a CLI command that executes a supplied 4917 program one instruction at a
time and prints a complete machine-state snapshot after every step. The trace
will include a cumulative count of output characters and stop when the
program halts or reaches a configurable maximum step count.

## Motivation

The processor exposes `stepProgram`, and the repository has an execution
tracing module. The current tracing implementation captures periodic or
selected trace points rather than printing every step, does not include the
full memory image in each snapshot, and uses a hard-coded step limit. That
makes it difficult to follow short programs instruction by instruction or
understand how stores change the program in memory.

## Proposed interface

Add a `trace` command with syntax along these lines:

```text
4917-cli trace --program 3,4,1,8,0 --max-steps 100
```

The `--program` format should match the proposed `run` command: comma-separated
memory bytes from 0 through 15, up to 16 bytes, with omitted memory padded by
zeroes. `--max-steps` sets the maximum number of instructions to execute; use a
documented default of 10000 and reject negative values.

## Trace output

Print an initial state followed by one line for each instruction executed. The
initial state must show all 16 memory values. A step line should show:

- the step number;
- the instruction address and instruction byte, with its operand when it is a
  two-byte instruction;
- R0, R1, and the program counter before and after the instruction;
- memory after the instruction: print all 16 values if any cell differs from
  the preceding state, otherwise print `memory: unchanged`;
- the number of output characters emitted by that step and the cumulative
  character count.

The cumulative count uses the processor's decimal output convention: values
0–9 count as one character and values 10–15 count as two. A HALT instruction
is itself included as an executed step and appears in the trace. Stop after
that line. If the maximum is reached first, print the final state and clearly
report that execution stopped at the step limit. A zero step limit may print
the initial state and immediately report the limit; it must execute no
instructions.

## Implementation notes

- Drive the trace with `Processor.stepProgram` so it shares instruction
  semantics with the emulator.
- Capture the pre-step state to identify the instruction and operand, then
  print the post-step state returned by `stepProgram`.
- `Device` already contains the 16-cell memory, R0, R1, PC, and cumulative
  `outputCount`. Derive the per-step character delta from the before/after
  counters or `OutputInfo`.
- Keep this command's detailed trace separate from the existing compact
  `ExecutionTracing` output unless that module can be extended without
  changing existing consumers' behavior.
- Reuse the numeric program parser proposed for `run` if that proposal is
  implemented first; otherwise share a parser helper rather than duplicating
  validation.

## Acceptance criteria

1. `4917-cli trace --help` describes the byte format and maximum-step option.
2. The command emits an initial state and exactly one complete state row per
   executed instruction. The initial row includes all 16 memory values.
3. Each step row contains registers, PC, instruction details, per-step output
   delta, and cumulative output-character count. Its memory field shows all 16
   values when memory changed, or `memory: unchanged` when it did not change
   from the preceding row.
4. HALT stops execution after its own row; reaching the maximum stops without
   executing an additional instruction.
5. A program that prints values below and above 10 reports character counts
   of one and two respectively.
6. Tests cover memory mutation, jump instructions, HALT, zero/positive limits,
   and output-count accumulation.

## Out of scope

- Interactive single-key stepping or breakpoints.
- Cycle detection or proving that a program will halt; the step limit bounds
  execution.
- Searching for or optimizing programs.
