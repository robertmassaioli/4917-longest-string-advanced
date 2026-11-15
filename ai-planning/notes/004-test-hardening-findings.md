# Findings from proposal 004 implementation

This file records defects found while implementing the test-hardening proposal.

## Tracked execution did not advance PC on HALT

`Processor.stepProgram` advances the program counter for HALT, while
`TrackedProcessor.stepTrackedProgram` originally only set its `halted` flag.
The two implementations therefore disagreed on the complete machine state
after the same instruction. The tracked implementation now advances PC to the
next wrapped address when it processes HALT. A regression assertion and a
generated one-step differential property cover this behavior.

Reproduction: step a tracked one-byte program `[0]`; before the fix its PC
remained `0`, while the base processor's PC became `1`.

## Tracked program validation skipped operand and data cells

`createTrackedDevice` validated opcode positions but skipped each two-byte
instruction's operand without validating its value. For example, `[8,255,0]`
was accepted even though every machine memory value is a four-bit value from
0 through 15. Program validation now checks every supplied cell and reports
the position of an out-of-range value.

Reproduction: `createTrackedDevice [8,255,0]` previously returned `Right`.

## Tracked loop detection ignored self-modified memory

`runTrackedProgramLoopCheck` originally keyed seen states by PC and registers
only. Two states with the same PC and registers but different memory were
treated as a loop even though the next instruction could differ. The key now
includes all 16 memory cells.

Reproduction: `[11,0,13,0]` stores R0 into cell 0, jumps back to cell 0, then
halts. The old detector stopped at the repeated PC/register tuple before
executing the new HALT instruction.

## A negative tracked step limit could run without a bound

`runTrackedProgram` only treated exactly zero as the stop case. Negative
limits kept decreasing and could run a non-terminating program forever. It now
clamps negative limits to zero before execution.

Reproduction: `runTrackedProgram (createTrackedDevice [7,13,0]) (-1)` did not
honor the requested bound.

## Wildcard search-space multiplication overflowed

`calculateReductionFactor` multiplied instruction-space sizes using `Int`.
For a 16-cell all-wildcard pattern, the search space is `16^16`, which
overflows a 64-bit `Int`; the reported factor could therefore be incorrect.
The calculation now uses `Integer` for both full and reduced search spaces
before converting the ratio to `Double`.

Reproduction: `calculateReductionFactor (replicate 16 Wildcard)` should be
`1.0`, since wildcarding all cells leaves the full search space unchanged.

## Any-of search-space counts included duplicate and invalid values

`instructionSpaceSize (AnyOf options)` originally used the list length. A
repeated value therefore inflated the search-space estimate, and values above
15 were counted even though they cannot be valid machine bytes. It now counts
distinct values in the 0–15 range.

Reproduction: `instructionSpaceSize (AnyOf [3,3,255])` previously returned
`3`; it now returns `1`.

## Program parsing accepted inconsistent whitespace and signed forms

The program parser delegated token syntax to `reads`, which accepted leading
whitespace while rejecting trailing whitespace. This made visually similar
CSV inputs behave differently. Program bytes are now restricted to ASCII
decimal digits before range checking, so whitespace and signs fail
consistently.

Reproduction: `parseProgramBytes " 1"` was accepted while
`parseProgramBytes "1 "` was rejected.

## Bounded `runProgram` made timeout indistinguishable from no output

The existing `runProgram :: Device -> Int -> Int` returned `0` when the step
limit expired. That is indistinguishable from a program that halted without
printing. Added `runProgramResult`, which returns `ProgramCompleted count` or
`ProgramTimedOut partialCount`; the old function remains as a compatibility
wrapper. Properties now compare bounded execution with a reference runner,
including timeout and zero-output cases.

Reproduction: `runProgram (createDevice [7,7,0]) 1` and
`runProgram (createDevice [0]) 1` both returned `0` despite different outcomes.
