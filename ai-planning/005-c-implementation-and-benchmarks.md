# 005: Add an optimized C implementation alongside the Haskell reference

**Status:** Proposed  
**Created:** 2026-11-15

## Summary

Add a C implementation of the 4917 processor as a peer to the existing Haskell
implementation. Keep Haskell as the readable correctness and debugging
reference, and make C the performance-oriented implementation for execution and
search workloads. Both implementations must agree on the processor's core
semantics, even though their command-line interfaces and user workflows may be
different.

Build the C implementation with CMake. Give it an independent test suite,
property-based and differential correctness checks, and a benchmark executable
that measures representative workloads without turning noisy timing results
into a flaky correctness gate.

## Motivation

The Haskell implementation is useful for understanding behavior, inspecting
state, and finding correctness defects. The repository's main search workloads
can benefit from a compiled implementation designed around throughput and
memory efficiency. Keeping both implementations in one repository makes their
relationship reviewable and lets Haskell serve as an executable specification
while C is optimized aggressively.

The C program should not be constrained to copy Haskell's CLI, module layout,
or internal data structures. The shared contract is the machine behavior and
the results of core algorithms. This allows the C interface to expose
performance-oriented workflows while the Haskell interface retains tracing and
debugging features.

## Verified starting point

This proposal was checked against repository revision `a51504c`:

- There is a Haskell implementation and no checked-in C source or CMake
  project. `Processor.hs` provides `stepProgram`, bounded `runProgramResult`,
  and Floyd cycle detection in `runProgramLoopCheck`.
- Proposal 004 has been implemented. `test/ProcessorTestSupport.hs` already
  contains an independent list-based reference stepper and valid-state
  generators; reuse these when building the differential oracle.
- Haskell has multiple execution policies. `Commands.ProgramExecution`
  counts executed HALT instructions, while the older `ExecutionTracing`
  runner checks HALT before stepping and uses a fixed 1,000-step limit.
  These runners are not interchangeable specifications.
- `BruteForceSearch.hs` uses heuristic filtering, cached results, and the
  older tracing runner; it maps timeouts to zero output. Its helper named
  `generateProgramsOfExactLength` currently enumerates every N-cell vector,
  including trailing zeroes. `Processor.programLength` instead uses the last
  nonzero cell. These differences must be resolved in the search contract,
  rather than copied into C as presumed correctness requirements.

The design below is proposed work. C command names, initial search domain,
supported platforms, and dependency versions are not yet settled.

## Proposed repository layout

Add a top-level `c-impl/` directory, leaving `haskell-impl/` in place:

```text
4917-longest-string-advanced/
├── ai-planning/
├── spec/
│   ├── processor.md
│   └── cases/
├── c-impl/
│   ├── CMakeLists.txt
│   ├── CMakePresets.json
│   ├── include/4917/
│   │   └── machine.h
│   ├── src/
│   │   ├── machine.c
│   │   ├── search.c
│   │   └── main.c
│   ├── tests/
│   ├── benchmarks/
│   └── README.md
└── haskell-impl/
```

Keep the processor state transition code in a small C library target such as
`4917_core`, separate from CLI parsing, search orchestration, and benchmark
code. The executable should link that library rather than duplicate its logic.
Use CMake presets for a normal debug build, an optimized release build, and an
optional sanitizer build. Register unit and integration tests with CTest.
Compile the production library and executable as C, with a documented C
standard and compiler baseline. Test and benchmark frameworks may use C++
through an `extern "C"` interface without compiling the production source as
C++. Keep any C++ compiler requirement conditional on those optional targets.

## Shared behavioral contract

Before optimizing the C implementation, write the shared contract in
`spec/processor.md` and encode small examples in `spec/cases/`. A valid
execution state has exactly 16 memory cells and values 0–15 in every cell,
register, and PC. The core state also carries an output-character count,
which is bookkeeping and does not affect instruction behavior. Define one C
step operation that consumes a state and reports the next state, output event,
and halt status. Its behavior must match the Haskell `stepProgram` contract
for all valid machine states and all 16 opcode values.

The contract and tests must cover:

- Nibble arithmetic and wraparound, instruction fetch, and program-counter
  wraparound.
- Operand fetch wrapping from memory cell 15 to cell 0.
- The defined behavior of every opcode, conditional branches, loads, stores,
  and self-modifying programs, including stores to the current instruction
  or operand. Fetch the operand from the pre-step memory before writing.
- HALT advances PC by one modulo 16 and reports completion for that step.
  Runners stop when it reports completion; a stepper does not have a
  persistent halted flag in the Haskell state.
- A bounded run permits at most N instructions, counts HALT as one, and
  completes if HALT is instruction N. A zero bound executes nothing and
  returns a limit result even when the next opcode is HALT. Initialization
  resets registers, PC, and output count; stepping an arbitrary state does
  not reset them.
- Output values and the one- or two-character decimal output count for values
  0 through 15.
- Separate program-loading rules from valid-state stepping. Haskell's
  `createDevice` pads/truncates lists and accepts arbitrary `Word8` values;
  its CLI rejects empty, overlong, and out-of-nibble CSV programs. C needs a
  documented validation boundary before entering an unchecked hot loop.
  All 16 valid opcodes are defined, so the Haskell fallback treating other
  bytes as NOP is outside the valid machine domain. Decide explicitly whether
  a compatibility loader is needed; do not require malformed inputs to reach
  C indexing code.
- Loop detection compares all memory cells, both registers, and PC, excluding
  output count. In particular `[8,1,13,0]` loops while printing and
  `[11,0,13,0]` self-modifies and halts. The latter must not be rejected just
  because PC and registers recur.

Specify separate execution policies: bounded execution without loop detection,
execution until HALT or a proven cycle, and any combined bounded/cycle mode.
A step limit is an unresolved run, not proof of an infinite loop. Document
precedence when a bound and a cycle coincide. For terminating runs compare
final state, output, and logical instructions executed. For cycle-detected
runs compare the classification; Floyd and a visited-state detector may stop
at different prefixes, so their partial output, final snapshots, and detection
step counts are not inherently equal. Any API exposing a canonical loop
prefix needs a separately specified policy. Floyd's speculative fast/slow
steps must never duplicate externally emitted output.

Use fixed-width C types (`uint8_t` for cells and registers, and a documented
wide unsigned type for accumulated character counts). Define checked overflow
or a proven supported bound for both character and step counts; silent wrap
is not a correct result. Haskell currently uses machine-sized `Int`, so run
differential cases only within its representable range and use independent
boundary tests for any wider C range. Do not assume `uint64_t` covers every
theoretically terminating 4917 program: there are up to 2^76 distinct
memory/register/PC states. The C representation may differ internally,
but its observable state transitions and execution results must be equivalent.

If tests find an ambiguity or defect in the current Haskell behavior, resolve
and document the canonical semantics before treating a C/Haskell mismatch as a
C defect. Preserve a regression case for every resolved discrepancy. Haskell
is the reference implementation, but the written contract and independent
tests are the final authority rather than accidental implementation details.

## Search equivalence

Functional equivalence covers the candidate evaluator and the search answer,
not identical enumeration, cache layouts, or pruning algorithms. Before adding
the first C search command, specify its candidate domain (N supplied cells or
exact last-nonzero length), initialization, treatment of zero-output halting
programs, tie ordering, and termination policy. Only proven terminating
programs may win. A search with unresolved candidates must report that it is
incomplete rather than claim a proved global maximum.

Use an exhaustive, unpruned small-domain baseline driven by the Haskell core
to compare the set of winners and their counts. Port heuristic filters or
memoization only after showing that they preserve this contract, including
for self-modifying programs. Do not use legacy cached search output alone as
the oracle. Candidate IDs and totals also need defined arithmetic: 16^16 is
2^64 and does not fit in a `uint64_t` count, even though individual 64-bit
packed programs fit.

## C implementation and optimization approach

Start with a direct, easy-to-audit C stepper that mirrors the contract. Keep
instruction dispatch and state updates explicit, avoid undefined behavior, and
use compiler warnings and sanitizers during development. Add an execution loop
that can run a bounded program and the core search/execution operations needed
by the C CLI.

The C implementation should prioritize speed and efficiency after correctness
is established. Choose compact state layout and hot-loop structure based on
measurements. Avoid allocations, formatting, and diagnostic bookkeeping in
inner loops when the operation does not need them. Keep tracing and verbose
state rendering outside the optimized execution path. Compiler optimization,
link-time optimization, profile-guided optimization, or specialized execution
paths may be added when benchmarks show a meaningful benefit and equivalence
tests cover the optimized path.

Do not preserve a slower structure merely because Haskell uses it. Do preserve
its externally observable results. Every optimized execution path must be
checked against the straightforward C stepper and the Haskell reference.

## C command-line interface

Give the C executable a separately designed CLI aimed at fast workloads. It
does not need to mirror Haskell subcommands, option names, output formatting,
or debugging workflow. Define the initial C commands around its purpose, for
example a fast execution command and a search/solve command, and document their
input formats, defaults, exit codes, and result formats in `c-impl/README.md`.
Keep argument parsing and presentation outside `4917_core` so the core can be
used by tests, benchmarks, and future front ends.

Keep the dedicated benchmark executable described below as the benchmark
entry point; a production CLI benchmark subcommand is optional. Select the
initial execution/search commands in a short CLI design before implementation.
The core does not need to retain printed strings or full traces for a
count-only search. Output capture may be requested by tests or a diagnostic
adapter without adding allocation or formatting to the production hot path.

Where a C command accepts or emits machine execution results, provide a stable
machine-readable mode for integration tests. That mode should expose the
semantic result (termination reason, output values/count, final state, and
steps where relevant) without requiring tests to parse human-oriented prose.
A test-only adapter can expose arbitrary initial states and single steps even
if production commands only accept programs. Use a versioned interchange
schema with exact integer encodings so harness parsers do not lose large
counts. Differential tests must choose matching execution policies explicitly.

## Correctness and testing

Use CTest to run deterministic tests for each instruction and its boundary
cases, plus integration tests for complete programs. Catch2 and RapidCheck
are C++ frameworks, not C testing libraries; they are candidates for optional
C++ harnesses calling the compiled C core. Confirm their integration and
compiler requirements for the pinned versions, or select a C-native unit
framework and a suitable generated-test harness. Acquire dependencies with
CMake `FetchContent` pinned to immutable revisions or verified archives, or
use documented system packages. Provide an explicit offline configuration
without silently fetching missing dependencies. Production-only builds should
not fetch test or benchmark dependencies.

Test the C implementation at several levels:

1. **Unit tests:** opcode behavior, state fields preserved by each instruction,
   arithmetic boundaries, PC and operand wraparound, memory updates, output
   counts, invalid input, and halt/step-limit boundaries.
2. **Property tests:** generated valid machine states and short programs;
   nibble arithmetic laws; PC and memory invariants; and equality between
   repeated single steps and bounded execution. Record seeds and retain
   minimized failures as named regression tests.
3. **Optimized-path checks:** compare any fast loop, search, or specialized
   implementation with the straightforward C reference stepper over generated
   and fixed cases.
4. **Differential tests:** feed the same generated states/programs to a
   test-only Haskell reference runner and the C machine-readable interface,
   then compare normalized state transitions, output events/counts, and
   termination results under the matching policies above. Batch cases through
   the oracle rather than launching Stack per instruction. Bound generated
   executions and harness runtimes so a C defect cannot hang CI. Keep this
   integration target optional for a C-only build, but run it in repository CI
   where both toolchains are installed.
5. **Regression corpus:** store small shared cases for subtle behaviors such
   as self-modifying code, loops that emit output, branches at the end of
   memory, and execution limits. Both implementations should consume the same
   cases where their public interfaces permit.

The Haskell implementation should remain independently testable. C tests must
not call into Haskell internals or make the C core depend on Stack at runtime.
The differential harness is a development/CI tool, not a production runtime
dependency.

Reuse the independent Haskell test model as a third check against correlated
bugs in the production steppers. Deterministic coverage should exercise all
16 opcodes at all 16 PC values, arithmetic over all nibble pairs, all memory
targets, both branch outcomes, print values 0–15, and bounds around any loop
unrolling width. Include near-overflow counter tests and invalid-state
validation tests outside the unchecked core. Add generated sequence tests for
self-modifying memory and reduced-domain exhaustive search comparisons, not
only one-step comparisons. Run supported AddressSanitizer and
UndefinedBehaviorSanitizer configurations separately from performance
measurements.

## Benchmarking

Add a dedicated C benchmark target, preferably using Google Benchmark. Keep it
separate from correctness tests and the production CLI. Include named,
reproducible workloads that represent the actual hot paths: short straight-line
execution, arithmetic-heavy execution, output-heavy execution, branches,
loops, and the search workload the C implementation is intended to accelerate.
Include workload sizes or iteration counts so results can be compared across
runs.

Google Benchmark uses C++; its harness should link the same compiled C core
as production. Measure a direct C baseline and each optimized variant on the
same inputs. Separate step/dispatch costs, bounded execution, cycle detection,
and end-to-end search. Include terminating programs, printing/nonprinting
cycles, and self-modifying programs. Explicitly state whether initialization,
state copying, cache warmup, and output capture are timed. Search benchmarks
must identify candidate ranges and cold/warm cache state; use finite batches
and reset mutable machine state for each intended execution.

Use runtime inputs and benchmark optimization barriers to keep each measured
call and its result observable, including with LTO; checking a constant result
after timing alone does not prevent constant folding or hoisting. Validate
fixture results against the oracle outside the timed region. Report throughput
in useful units such as executed instructions or candidate programs per
second. Document build type,
compiler, flags, machine, and benchmark invocation. Keep benchmark results
informational by default; correctness CI should not fail on small timing
changes. A later performance gate can be considered after stable baselines and
machine-specific noise limits exist. Record the repository revision and fixture
identity, repetitions and spread, and machine-readable results. Count actual
logical instructions or candidates processed rather than merely requested
limits. If comparing against Haskell, use identical workloads and execution
policies, excluding tracing, CLI startup, and compilation unless the benchmark
explicitly measures those costs. No speedup is promised before a baseline is
measured.

## Build and developer workflow

Document commands along these lines in the repository and C implementation
READMEs:

```sh
cd c-impl
cmake --preset debug
cmake --build --preset debug
ctest --preset debug

cmake --preset release
cmake --build --preset release
./build/release/4917-c --help

cmake --preset benchmarks
cmake --build --preset benchmarks
./build/benchmarks/4917-bench --benchmark_repetitions=5 --benchmark_out=results.json
```

Provide clear presets or equivalent commands for configuring tests,
benchmarks, and sanitizers. Keep the Haskell Stack workflow intact and explain
how developers can build either implementation or run the differential suite.
CI should build and test each implementation independently, then run the
cross-implementation checks in a job that has both toolchains.

## Delivery order

1. Document the valid machine domain, execution policies, shared corpus, and
   oracle protocol; make any required Haskell contract clarification explicit.
2. Add CMake, the direct C core, a minimal execution adapter, deterministic and
   generated tests, and the batched Haskell/C differential harness.
3. Specify and implement the first search domain/command with an unpruned
   small-domain baseline; add representative benchmark fixtures and capture a
   reproducible release baseline.
4. Optimize the measured hot paths, retaining equivalence checks and benchmark
   evidence for each accepted change. Add CI jobs and developer documentation
   as their targets become available.

## Decisions before implementation

- Confirm the initial C workflows: execution plus exhaustive length search,
  task-oriented `SolveTask` compatibility, or a narrower first release. This
  proposal does not silently require every Haskell command or cache format.
- Set the supported compiler/platform and C language baseline (C11 is a
  reasonable starting recommendation), and choose the optional test/property
  frameworks. If using C++ harnesses, pin their C++ standard as well.
- Choose search length semantics and tie ordering. Decide whether legacy
  permissive Haskell loading needs a C compatibility API; the recommended
  production input boundary rejects invalid nibble programs.
- Choose counter widths and overflow reporting, maximum accepted execution
  limits, and whether the C CLI exposes partial output at cycle detection.
  These are interface policies to settle, not implied equivalence requirements.

## Acceptance criteria

1. The repository contains separate `haskell-impl/` and `c-impl/` projects;
   the C core is a CMake library used by the C executable and tests.
2. A written, tested processor contract defines all opcode, state, output,
   halt, boundary, and loop-detection behavior shared by both implementations.
3. The direct C stepper agrees with Haskell on deterministic edge cases and
   generated differential cases, including self-modifying and output-producing
   loops.
4. Unit and property-based tests run through CTest, and failures are
   reproducible and retained as regression cases.
5. Any C optimized execution/search path is checked against the direct C core
   and Haskell reference before it is accepted.
6. The C executable has its own documented commands and stable machine-readable
   output for integration tests; no requirement forces its CLI to match
   Haskell's.
7. CMake can build debug and optimized release configurations, with documented
   sanitizer and benchmark options.
8. A dedicated benchmark suite measures representative execution and search
   workloads, reports useful throughput, and is not a flaky pass/fail timing
   test in ordinary CI.
9. Root documentation explains how to build, test, benchmark, and compare the
   two implementations.
10. Small exhaustive searches agree with an unpruned Haskell-core baseline
    under the documented candidate and tie rules; unresolved runs and counter
    overflow cannot be reported as successful exact answers.

## Out of scope

- Replacing or removing the Haskell implementation or its existing CLI.
- Requiring the C CLI to reproduce Haskell's debugging commands or text
  formatting.
- Rewriting the Haskell implementation as part of the initial C project setup,
  except for small test-oracle or contract changes required to make semantics
  explicit and testable.
- Accepting speed improvements that introduce observable semantic differences
  or undefined behavior.
- Making wall-clock benchmark thresholds a default CI correctness requirement.

## Framework references

These references explain candidate harnesses; choosing and pinning versions is
implementation work:

- [Catch2: C++ test framework](https://github.com/catchorg/Catch2).
- [RapidCheck: C++ property tests and shrinking](https://github.com/emil-e/rapidcheck).
- [Google Benchmark requirements](https://github.com/google/benchmark#requirements)
  and [optimization barriers and reporting](https://github.com/google/benchmark/blob/main/docs/user_guide.md).
