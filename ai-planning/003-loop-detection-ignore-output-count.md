# 003: Exclude output count from loop-state equality

**Status:** Proposed
**Created:** 2026-11-15

## Summary

Fix Floyd's tortoise-and-hare loop detection so it compares only the machine
state that determines future execution. The accumulated output-character
count should not be part of that comparison, because it grows on each pass
through a printing loop even when the processor has returned to the same
execution state.

## Current problem

`Processor.runProgramLoopCheck` advances a slow state by one instruction and a
fast state by two instructions, then compares them with `comparePrograms`.
`comparePrograms` currently uses derived equality for `Device`. That equality
includes `outputCount`, which `stepProgram` increments whenever the program
prints. A loop that prints therefore never returns equal states, and the
detector can run forever instead of returning `InfiniteLoopDetected`.

For example, memory `[8, 1, 13, 0]` prints `1` and jumps back to address 0.
The PC, registers, and memory repeat, but `outputCount` keeps increasing.

## Proposed change

Introduce or use a loop-state comparison that checks every field affecting
future instruction execution:

- all 16 memory values, including self-modified memory;
- R0 and R1;
- the program counter.

Exclude `outputCount` from loop-state equality. Keep output accounting separate
from cycle detection. Preserve the existing `ProgramExecutionResult` behavior:
terminating programs return their total output-character count, while loops
return `InfiniteLoopDetected`.

Avoid changing general-purpose `Device` equality unless all its current
callers are intended to disregard output counts. A dedicated predicate such
as `sameExecutionState` makes the loop-detection rule explicit and prevents
other uses of `Eq Device` from changing unexpectedly.

## Acceptance criteria

1. The printing loop `[8, 1, 13, 0]` returns `InfiniteLoopDetected` promptly.
2. A non-printing loop is still detected.
3. A finite program that prints then halts returns the correct output
   character count.
4. States with different memory, registers, or PC are not considered equal,
   even when their output counts match.
5. Existing callers of full `Device` equality retain their current semantics.

## Out of scope

- Changing the public result type or reporting partial output from an infinite
  loop.
- Replacing Floyd's algorithm or adding an execution-step limit.
- Changing the output formatting or counting rules.
