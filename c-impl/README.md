# 4917 C implementation

This is the performance-oriented peer to `haskell-impl/`. The production core
is C11 with fixed-width machine values, no allocation in `step` or bounded
execution, and no runtime dependency on Stack, Python, or a test framework.
`spec/processor.md` is the shared behavioral contract.

## Build and run

Requires CMake 3.20+ and a C11 compiler. The presets use Unix Makefiles, so
Ninja is not required.

```sh
cmake --preset debug
cmake --build --preset debug
ctest --preset debug

cmake --preset release
cmake --build --preset release
./build/make-release/4917-c --help

cmake --preset sanitizers
cmake --build --preset sanitizers
ctest --preset sanitizers
```

Production-only builds can disable tests with
`-DI4917_BUILD_TESTS=OFF`; CMake does not fetch dependencies. CTest contains
deterministic instruction/boundary cases and 10,000 fixed-seed generated
program checks. The test harness is plain C to keep the default build offline
and compiler requirements to C11. Generated run-equivalence failures report
the fixed seed and trial index; add any minimized failure as a named test and
shared case.

## Commands

`run` validates 1–16 CSV nibble values, pads memory with zeroes, resets the
machine, and executes up to the default 10,000 steps. HALT counts as a step.
The JSON output schema is `4917-run-v1`; step and output-character counts are
decimal strings to avoid JSON integer precision loss. Output values and final
memory/register/PC are included. Exit codes are 0 for a completed or limited
run, 1 for an internal execution error, and 2 for invalid arguments/input.

```sh
./build/make-release/4917-c run --program 3,4,1,8,10,0 --max-steps 100
./build/make-release/4917-c run --program 8,1,13,0 --max-steps 20 --json
```

`search` is an exhaustive correctness baseline over every N-cell nibble vector
in lexicographic order, zero-padded to 16 cells. Length is restricted to 1–4
so runtime remains bounded. Each candidate starts reset and is run under the
same step limit. Only HALT candidates can win; limited candidates are
unresolved. Output marks the result exhaustive only if every candidate halted.
Search reports the first winner in enumeration order and the total number of
winners. Candidate and count fields are decimal strings in `4917-search-v1`.

```sh
./build/make-release/4917-c search --length 3 --max-steps 10000 --json
```

`step` is a low-level diagnostic adapter for arbitrary valid states. It
requires exactly 16 memory cells and accepts register, PC, and output-count
values; `4917-step-v1` returns the single event and resulting state. It is also
the integration boundary used for one-step differential testing.

```sh
./build/make-release/4917-c step --memory 8,15,0,0,0,0,0,0,0,0,0,0,0,0,0,0 --r0 0 --r1 0 --pc 0 --json
```

## Tests and Haskell differential checks

The C unit/property suite checks arithmetic laws for all nibble pairs, opcode
boundaries, wrapping, output count, self-modification, cycle classification,
run limits, and generated run-vs-step equivalence. Optional differential
testing uses a batched Haskell oracle and Python driver:

```sh
cmake -S . -B build/differential -DI4917_ENABLE_HASKELL_DIFFERENTIAL=ON
cmake --build build/differential
ctest --test-dir build/differential --output-on-failure
```

This requires Stack and Python 3; it runs fixed regressions plus 250 generated
bounded programs using seed `0x4917`, compares all 256 opcode/PC pairs plus
256 additional generated arbitrary states, and checks exact length-two search
against an unpruned Haskell baseline. It batches execution and single-step
requests through the oracle and compares semantic output, final state, and
termination with C's machine-readable interface. C-only builds remain
independent of Haskell.

## Benchmarks

The standalone C benchmark has no third-party timing dependency. It is
informational, not a correctness threshold. Timings include per-run machine
initialization and bounded execution; they exclude process startup and output
formatting. Search uses all 256 two-cell candidates. Each case prints actual
instructions or candidates per second and a result sink to keep calls
observable.

```sh
cmake --preset benchmarks
cmake --build --preset benchmarks
./build/make-benchmarks/4917-bench
./build/make-benchmarks/4917-bench --json > benchmark-results.ndjson
```

The default run includes straight-line, arithmetic-heavy, output-heavy,
branch, self-modifying, and small exhaustive-search workloads, followed by
single-step measurements for every opcode. To measure only the instruction
set, or one opcode, run:

```sh
./build/make-benchmarks/4917-bench --instructions --json
./build/make-benchmarks/4917-bench --instruction 9 --json
```

Opcode selectors are decimal values 0–15. Opcodes 14 and 15 each report both
taken and not-taken cases. Each individual-opcode sample executes 1,048,576
calls to `i4917_step` on one prebuilt valid state, resetting PC before each
call so the selected opcode repeats. Registers and memory evolve as the
instruction specifies. State setup is outside the timed region; the API's
state validation and instruction execution are timed. Each fixture takes five
timed samples and reports min/median/max throughput, so an individual opcode
can be rerun while tuning its implementation. Record revision, compiler,
flags/build type, and machine with saved results. No speedup is claimed before
a baseline is collected.

### Optional Google Benchmark comparison

An opt-in C++17 harness is available to compare calibration, repetitions, and
structured reporting with the dependency-free C harness. The C core and CLI
remain C11; only `4917-google-bench` uses C++. Google Benchmark 1.9.1 is pinned
to commit `c58e6d0710581e3a08d65c349664128a8d9a2461` and its source archive is
SHA-256 verified. The framework's own tests and GoogleTest integration are
disabled. This target adds no CI timing threshold.

The normal build does not enable C++ or fetch anything. To use the pinned
dependency, the explicit preset fetches it during configure:

```sh
cmake --preset google-benchmarks
cmake --build --preset google-benchmarks
./build/make-google-benchmarks/4917-google-bench \
  --benchmark_repetitions=5 \
  --benchmark_report_aggregates_only=false \
  --benchmark_out=google-benchmark-results.json \
  --benchmark_out_format=json
```

The harness registers all 16 single-instruction workloads, with taken and
not-taken cases for both conditional branches, plus short straight-line,
arithmetic-heavy, and exhaustive length-two search workloads. Its
per-instruction fixture uses a prebuilt valid state, rewinds PC in the timed
loop, and measures `i4917_step` through the exported C API, including state
validation. Each fixture performs a correctness preflight before timing. The
Google output includes raw repetition records and aggregates; counters name
single steps, logical steps, or candidates per second. Custom JSON context
records the framework version, C/C++ compilers and flags, build type, source
revision, and fixture semantics. The framework also records host and CPU
context where supported.

For an offline setup, install the exact Google Benchmark 1.9.1 CMake package
and configure with `-DI4917_BUILD_GOOGLE_BENCHMARKS=ON
-DI4917_FETCH_GOOGLE_BENCHMARK=OFF`. Alternatively, pre-populate the CMake
FetchContent source override and disable fetching:

```sh
cmake -S . -B build/google-benchmarks-offline \
  -DCMAKE_BUILD_TYPE=Release \
  -DI4917_BUILD_TESTS=OFF \
  -DI4917_BUILD_GOOGLE_BENCHMARKS=ON \
  -DI4917_FETCH_GOOGLE_BENCHMARK=OFF \
  -DFETCHCONTENT_SOURCE_DIR_GOOGLEBENCHMARK=/path/to/google-benchmark-1.9.1
cmake --build build/google-benchmarks-offline
```

Google Benchmark calibrates iteration counts to its minimum time and reports
repetitions/statistics; set `--benchmark_min_time=0.01s` for a short
registration smoke run. For useful comparisons, keep the C core build,
compiler, flags, machine, and workload fixtures the same, use at least five
repetitions on an otherwise idle host, and retain the complete JSON output. The
existing C harness instead uses fixed work counts and five min/median/max samples. Neither
framework nor repetitions make local timings statistically conclusive: CPU
frequency, thermal state, background work, and machine variation still affect
results. Hardware performance counters remain optional and are not required by
this harness. Treat the framework as an evaluation path until a controlled
comparison establishes ongoing value.

## Optimization rules

Keep argument validation and presentation outside `4917_core`. Any specialized
execution path must be checked against `i4917_step` over generated and fixed
cases. The bounded hot loop intentionally does not allocate or detect cycles;
`i4917_run_until_halt_or_cycle` is a diagnostic API using visited full states,
excluding the output counter. Its output prefix is not a canonical cross-
implementation result. Counter overflow is an explicit error, never wraparound.
