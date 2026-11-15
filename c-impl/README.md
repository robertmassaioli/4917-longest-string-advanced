# 4917 C++ implementation

This is the performance-oriented C++17 peer to `haskell-impl/`. The processor
core uses fixed-width machine values and keeps bounded execution allocation-
free. Its hot runner has a dedicated dispatch loop; `i4917_step` remains the
reference single-step operation for diagnostics and differential checks.
`spec/processor.md` is the shared behavioral contract.

The library keeps a small C ABI in `include/4917/machine.h`. The C
property-test and standalone benchmark clients use that boundary to exercise
the same C++ engine.

## Build and run

Requires CMake 3.20+, C++17, and CLI11 2.7.2 or newer. Install the normal
build dependency with:

```sh
brew install cli11
```

Google Benchmark is optional and only needed for its comparison target:

```sh
brew install google-benchmark
```

Homebrew package config files are discovered automatically. If CLI11 is not
installed, CMake fetches the pinned 2.7.2 source archive and checks its
SHA-256.

```sh
cmake --preset debug
cmake --build --preset debug
ctest --preset debug

cmake --preset release
cmake --build --preset release
./build/make-release/4917-cpp --help
```

The C property-test and standalone benchmark clients require a C compiler as
well as a C++ compiler. A production-only build needs only C++: disable tests
with `-DI4917_BUILD_TESTS=OFF` and leave `-DI4917_BUILD_BENCHMARKS=OFF`.

## Commands

Run `4917-cpp --help` for commands or append `--help` to a subcommand. Numeric
values must be nonnegative decimal digits and fit in `uint64_t`. CSV parsing
validates 1–16 nibble values.

```sh
./build/make-release/4917-cpp run --program 3,4,1,8,10,0 --max-steps 100
./build/make-release/4917-cpp run --program 8,1,13,0 --max-steps 20 --json
./build/make-release/4917-cpp search --length 3 --json
./build/make-release/4917-cpp step --memory 8,15,0,0,0,0,0,0,0,0,0,0,0,0,0,0 --json
```

`run` executes up to the default 10,000 steps. HALT counts as a step. Its JSON
schema is `4917-run-v1`; output values and final machine state are included.
Exit codes are 0 for a completed or limited run, 1 for an execution error, and
2 for invalid arguments or input.

`search` enumerates every N-cell nibble vector in lexicographic order, padded
to 16 memory cells. Length is restricted to 1–5. Each candidate runs until it
halts or a repeated execution state is found. HALT candidates can win; cycles
are counted separately. The result is exhaustive if no candidate errors. Its
JSON schema is `4917-search-v2`.

`step` executes one instruction from a supplied state with exactly 16 memory
cells. Its JSON schema is `4917-step-v1`.

## Correctness checks

The C property suite checks arithmetic, opcode boundaries, wrapping, output
counts, self-modification, cycle classification, bounded execution, and
10,000 fixed-seed generated run-vs-step cases. The Python CLI contract suite
checks help, option handling, validation, schemas, and exit codes. Optional
differential testing compares with the Haskell oracle:

```sh
cmake -S . -B build/differential -DI4917_ENABLE_HASKELL_DIFFERENTIAL=ON
cmake --build build/differential
ctest --test-dir build/differential --output-on-failure
```

## Benchmarks

The standalone C benchmark measures the C++ core through its C ABI. It reports
five-sample min/median/max instruction or candidate throughput. Individual
opcode fixtures execute 1,048,576 `i4917_step` calls per sample. Build and run
it with:

```sh
cmake --preset benchmarks
cmake --build --preset benchmarks
./build/make-benchmarks/4917-bench --json > benchmark-results.ndjson
./build/make-benchmarks/4917-bench --instruction 9 --json
```

Google Benchmark is an optional C++ harness using the same core; it compares
calibration and reporting, not C and C++ implementations:

```sh
cmake --preset google-benchmarks
cmake --build --preset google-benchmarks
./build/make-google-benchmarks/4917-google-bench \
  --benchmark_repetitions=5 \
  --benchmark_report_aggregates_only=false
```

The C optimization campaign and its paired measurements are documented in
[`benchmarks/hill-climb.md`](benchmarks/hill-climb.md). Those recorded speedups
measure the C campaign candidate against its C baseline; they do not predict
the C++ port's performance. Compare the C++ build directly with the same
fixtures and settings before making a language-level performance claim.

Keep compiler, flags, machine, and fixtures the same for comparisons. CPU
frequency, thermal state, background work, and host load affect local timings;
the benchmarks have no CI timing threshold.
