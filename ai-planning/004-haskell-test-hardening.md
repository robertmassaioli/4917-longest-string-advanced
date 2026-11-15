# 004: Harden the Haskell test suite with property-based testing

**Status:** Proposed  
**Created:** 2026-11-15

## Summary

Expand the Haskell implementation's tests from example-focused checks into a
systematic test suite combining unit tests, edge-case tests, property-based
tests, and differential checks against a small independent reference model.
The goal is to catch instruction-level defects, state corruption, boundary
errors, and inconsistencies between optimized and straightforward execution
paths before they reach users.

The repository already uses Hspec and includes QuickCheck in the test-suite
dependencies. This proposal builds on those tools, organizes coverage around
the public behavior of each subsystem, and makes generated failures
reproducible and easy to minimize.

## Motivation

The current tests cover many representative instructions and several complete
programs, but examples alone cannot explore the large combination of memory,
register, program-counter, branching, self-modifying code, and output states.
Many important guarantees are naturally expressed as properties: arithmetic
wraps modulo 16, a step preserves unrelated state, tracked execution agrees
with ordinary execution, and a bounded interpreter agrees with a simple
reference implementation.

The processor has particularly sensitive edge cases. Instructions and
operands can straddle the end of 16-cell memory, the PC wraps around, stores
can modify future instructions, branches depend on register state, and output
counts one or two decimal characters. The rest of the library also transforms
and caches execution and pattern data, where round trips and equivalence
properties can find errors that hand-picked examples miss.

## Proposed approach

Keep Hspec as the test runner and QuickCheck as the property engine. Organize
the test suite by module and behavior, and add reusable generators and
reference helpers in test-only modules. Avoid changing production behavior
solely to make tests easier; add small pure helpers only where they provide a
useful, independently testable contract.

Use bounded, domain-aware generators rather than unrestricted random bytes:

- Generate valid 16-cell machine states with nibble-valued memory and
  registers, and valid program counters from 0 through 15.
- Generate instruction-focused states that place a selected opcode and its
  operand at any address, especially address 15 where fetches wrap.
- Generate short terminating programs and short bounded instruction streams;
  keep the execution limit small enough that failures shrink quickly.
- Generate structured pattern and cache values that satisfy their invariants,
  alongside separate invalid-input generators for parsers and decoders.
- Provide shrinkers that retain structural validity where possible, while
  reducing programs, instruction sequences, and pattern values to minimal
  counterexamples.

Use fixed, configurable QuickCheck settings in CI, with enough cases to explore
the important state space without making the normal suite slow. Include the
seed and shrunk counterexample in failure output so any CI failure can be
replayed locally. Keep a documented way to increase the case count for local
stress runs.

## Coverage plan

### Processor instructions and execution

- Add table-driven unit tests for every opcode, both branch outcomes, all
  relevant operand and register boundaries, and the exact fields each
  instruction is allowed to change.
- Cover arithmetic boundaries (`0`, `1`, `14`, `15`), increments and
  decrements at wraparound, output values on both sides of the one/two-digit
  boundary, and all PC wrap cases for one- and two-byte instructions.
- Cover jumps and conditional jumps at addresses `0` and `15`, and instructions
  whose operand is in cell `15` and therefore wraps to cell `0` for the next
  fetch.
- Exercise loads and stores at every memory address, self-modifying code,
  branches after register changes, unknown opcode behavior, and HALT at the
  first and last reachable instruction.
- Check constructor and initialization behavior for empty, short, exactly
  16-cell, and overlong memory inputs, including zero padding and truncation.
- Check that a single `stepProgram` call changes only fields permitted by the
  selected instruction, preserves output count when no output is emitted, and
  reports the correct `OutputInfo` and halt flag.
- Check that output accounting is cumulative and that values `0` through `9`
  add one character while values `10` through `15` add two.
- Test finite programs that halt exactly at the execution bound, just beyond
  it, and immediately; test loops with and without output, and distinguish
  halt from timeout and loop detection.
- Verify `sameExecutionState` compares every memory cell, both registers, and
  PC, while deliberately ignoring output count; separately preserve full
  `Device` equality semantics.

### Processor properties and independent reference checks

- Assert modulo-16 laws for increment, decrement, addition, and subtraction
  over generated nibble-valued registers.
- Assert PC remains in the 0–15 range after every valid instruction and memory
  remains exactly 16 cells long.
- Assert instruction-local invariants: NOP changes only PC; arithmetic
  instructions leave memory and R1/R0 as appropriate unchanged; loads do not
  mutate memory; stores write the selected register value only to the
  addressed cell; OUTPUT leaves memory and registers unchanged; HALT advances
  PC according to the documented machine semantics and reports completion.
- Implement a deliberately simple, test-only reference stepper from the
  instruction specification. Compare its full resulting state, output event,
  and halt status with `stepProgram` over generated states and instructions.
  Keep this model structurally different from the optimized production code
  so it does not simply repeat the same implementation mistake.
- Compare bounded execution with repeated reference stepping and with repeated
  `stepProgram` calls for generated short programs, including executions that
  halt at each possible bound. This should cover the optimized/unrolled
  `runProgram` path at bounds around its unrolling size as well as longer
  bounds.
- Where input is guaranteed to halt within the bound, check that
  `runProgram`'s character count equals the count accumulated by the reference
  interpreter. Define and test timeout behavior explicitly so a timeout
  result cannot be confused with a valid zero-output result.
- Generate small loop-shaped programs and assert loop detection terminates
  with `InfiniteLoopDetected`; generate finite programs with output followed
  by HALT and assert the returned count matches the emitted decimal text
  length.

### Tracked execution and tracing

- For generated valid states and bounded programs, compare each tracked step
  with ordinary processor execution for memory, registers, PC, and output
  count.
- Check trace invariants: the first state is the initialized state; each
  subsequent state follows exactly one instruction; reported memory deltas
  reconstruct the full memory; and per-step output deltas sum to the final
  output count.
- Include edge cases for zero step limits, exact-limit HALT, HALT at step one,
  memory updates, output values 9 and 10, and PC wraparound.

### Pattern analysis, matching, and caches

- Add property tests for pattern matching and instruction-space calculations,
  including required, wildcard, and any-of instructions, empty patterns, and
  maximum-size patterns.
- Check that analysis results refer only to valid instruction positions and
  that applying an optimization preserves the behavior of representative
  programs over bounded executions.
- Check cache encode/decode round trips, stable serialization, lookup
  equivalence, and behavior for missing, malformed, truncated, or older cache
  entries. Use temporary directories and isolate filesystem-dependent tests.
- Add boundary tests for empty result sets, duplicate entries, maximum values,
  and programs at the 16-cell limit.

### CLI inputs and public workflows

- Test valid program parsing at lengths 1 and 16, zero-valued cells, and
  values 0 and 15; reject empty input, empty fields, signs, whitespace if
  unsupported, non-numeric values, values outside 0–15, and more than 16
  values.
- Test `run` and `trace` output for halting programs, loops or step-limit
  exhaustion, one- and two-character outputs, and invalid arguments, including
  useful diagnostics and non-zero exit status on invalid input.
- Add smoke coverage for existing subcommands' help and error paths so changes
  to shared CLI parsing do not silently break other commands.

## Test organization

Add test-only modules for shared generators and the reference interpreter, and
split large specs by concern where that makes failures easier to locate. Keep
all new specs registered in `test/Spec.hs`. Use readable assertion labels and
include the generated instruction, address, and initial state in counterexample
output.

Prefer properties that encode a public contract or compare independent
implementations. Avoid tautological properties that merely restate the code,
and avoid unbounded random execution: generated programs must have a bounded
step count or a known termination condition. Keep a small set of named
regression examples for every defect found by property testing.

## Acceptance criteria

1. Every processor opcode has explicit boundary and state-preservation tests,
   including operand and PC wraparound at the end of memory.
2. QuickCheck generators cover valid machine states, instruction boundary
   cases, and short programs, and shrink failing cases to understandable
   counterexamples.
3. A simple independent reference stepper agrees with `stepProgram` over
   generated instructions and states; bounded execution properties agree
   across the reference, single-step, and optimized paths.
4. Tracked execution and trace output are checked against ordinary execution
   for generated programs and output-count edge cases.
5. Pattern, analysis, and cache tests include round-trip, invariant, malformed
   input, and boundary coverage appropriate to their public contracts.
6. CLI parsing and run/trace workflows cover valid inputs, malformed inputs,
   limits, termination modes, and output formatting.
7. QuickCheck failures report replayable seeds and minimized counterexamples;
   normal CI settings provide a useful range of cases while keeping the suite
   practical to run.
8. Existing tests continue to pass, and every discovered defect is retained as
   a deterministic regression test.

## Out of scope

- Replacing Hspec or QuickCheck with a different testing framework.
- Exhaustively enumerating every possible 16-cell program; property tests
  should sample structured states and complement deterministic boundary tests.
- Performance benchmarking as a substitute for correctness checks. Benchmarks
  may be added separately if test runtime becomes a concern.
- Changing the processor's instruction set or semantics as part of the test
  expansion; any discovered behavior ambiguity should be documented and
  resolved separately.
