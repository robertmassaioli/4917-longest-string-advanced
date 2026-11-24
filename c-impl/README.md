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
./build/make-release/4917-cpp dataset --length 10 --count 1000 --strategy random --seed 41 > candidates.jsonl
./build/make-release/4917-cpp dataset --length 15 --count 100 --strategy mutate \
  --program 1,8,15,14,4,2,4,15,0,10,5,5,11,11,14 --seed 41 > mutations.jsonl
./build/make-release/4917-cpp dataset --length 16 --count 100 --strategy template --seed 41 > template.jsonl
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

`dataset` emits one JSON object per line with the candidate and its direct
simulation result. `random` samples uniformly from the declared nibble space
using the supplied deterministic seed. `mutate` starts with the supplied
program, changes one nibble per proposal, and keeps a new incumbent only when
it halts with a strictly larger output-character count. The mutation stream
therefore provides a simple hill-climbing baseline. `template` varies the
PRINT operand and final conditional-jump target in the staged counter pattern
documented in `explainers/length-16.md`. For lengths below 16 it uses the
corresponding prefix as the declared program; remaining memory is zero-padded
by the simulator. This is a proposal source, not a pruning rule or a claim that
these patterns are optimal. All three strategies accept a per-candidate step
budget; a candidate that reaches it is labeled
`unresolved`, with a null training target, rather than being assigned a score.
Halted candidates carry the exact integer target in `output_characters`, plus
the observed count and steps. The JSONL schema is `4917-dataset-v1`; rows keep
the declared length, program, strategy, and random seed for reproducibility.
For a fixed length, count, step budget, and seed, each strategy emits the same
candidate sequence and direct-simulation labels.

`step` executes one instruction from a supplied state with exactly 16 memory
cells. Its JSON schema is `4917-step-v1`.

## Build and run the Metal search on macOS

The Metal backend requires macOS and Apple's Metal framework. Install Xcode's
Command Line Tools if they are not already available, then configure and build
the Release target from `c-impl/`:

```sh
cd c-impl
cmake --preset release
cmake --build --preset release --target 4917-metal-search -j 8
```

If the Xcode Command Line Tools are missing, install them once with
`xcode-select --install` before configuring the build.

The executable is `build/make-release/4917-metal-search`. Run an exhaustive
search by specifying a program length from 1 through 16:

```sh
./build/make-release/4917-metal-search --length 9 --json
./build/make-release/4917-metal-search --length 10 --gpu-step-limit 256 --json
```

By default, an exhaustive search reports only the best score, tie count, and
first winner. To also save every tied best program, pass `--winners-jsonl` with
an output path:

```sh
./build/make-release/4917-metal-search --length 10 --json \
  --winners-jsonl ./length-10-winners.jsonl
```

The command creates or replaces the specified file. It writes one JSON object
per line, with schema
`4917-metal-winner-v1`, the program length, decimal candidate ID,
output-character score, and program vector. Records are ordered by candidate
ID. If a higher score appears later in the exhaustive search, lower-scoring
records are discarded so the completed file contains only the final tied
winners. Because collecting and saving candidate IDs adds overhead, leave off
`--winners-jsonl` for normal high-throughput searches. When the option is used,
the JSON summary reports the file path in `winners_file` and sets
`all_winners_saved` to `true`.

Each GPU thread simulates one candidate up to the GPU step budget (default
256). Candidates that halt or repeat a complete machine state in that budget
are classified on the GPU. Every other candidate is handed to the exact CPU
runner, which determines whether it later halts, cycles, or errors. The budget
only chooses where work runs; it does not limit the search or change its
answer. A candidate with an unusually long execution can still take a long
time to classify. The JSON summary schema is `4917-metal-search-v1`;
`gpu_halted`, `gpu_cycled`, and `cpu_exact_fallback` expose the split. The
Apple-only CTest
`metal-search-differential` compares the solver against CPU exhaustive results
for lengths 1–3 using several GPU budgets, and exercises a wrapped two-byte
PRINT at cell 15, self-modifying memory, and a cycle through the single-program
`--program` mode.

Metal is not automatically faster. The per-candidate instruction path is
sequential and branchy, so GPU work helps only when enough candidates finish
quickly in parallel to outweigh kernel setup and CPU fallback. Measure on the
target Mac for the lengths and GPU budgets that matter; the CPU `search`
command remains the portable baseline.

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
