# Google Benchmark harness evaluation

This is a smoke comparison of the dependency-free C harness and the optional
Google Benchmark harness, using the same optimized C core and overlapping
fixtures. It verifies the harnesses produce usable measurements and keeps a
reviewable sample; it does not establish that one harness or implementation is
faster.

## Environment and commands

- Source revision for the C core: `abb9e46` (no core changes were made in the
  harness work).
- AppleClang 17.0.0.17000013, Release, C flags `-O3 -DNDEBUG`; Google harness
  C++ flags `-O3 -DNDEBUG -O3`.
- macOS 15 / Darwin 24.6.0, ARM64 Apple M4 Pro.
- Google Benchmark 1.9.1, pinned source commit
  `c58e6d0710581e3a08d65c349664128a8d9a2461`.
- The host load was elevated and varied during the capture. Google Benchmark
  also reported that it could not determine CPU frequency or set thread
  affinity. These conditions make the small timing differences especially
  unsuitable for optimization decisions.

The existing harness used fixed work counts and five samples:

```sh
cmake --preset benchmarks
cmake --build --preset benchmarks
./build/make-benchmarks/4917-bench --json
```

The framework harness calibrated each fixture and captured five raw
repetitions plus aggregates:

```sh
cmake --preset google-benchmarks
cmake --build --preset google-benchmarks
./build/make-google-benchmarks/4917-google-bench \
  --benchmark_min_time=0.01s \
  --benchmark_repetitions=5 \
  --benchmark_report_aggregates_only=false \
  --benchmark_out=google-benchmark-results.json \
  --benchmark_out_format=json
```

The raw outputs for this capture are
[`c-harness-2026-11-15.ndjson`](results/c-harness-2026-11-15.ndjson) and
[`google-benchmark-2026-11-15.json`](results/google-benchmark-2026-11-15.json).
They include all per-instruction records, including both branch outcomes.

## Common fixture sample

| Fixture | C harness median | Google Benchmark median | Work unit |
| --- | ---: | ---: | --- |
| Short straight line | 145.1 M/s | 147.2 M/s | executed instructions |
| Arithmetic-heavy | 164.0 M/s | 157.8 M/s | executed instructions |
| Exhaustive length-two search | 16.0 M/s | 16.9 M/s | candidates |

Both suites also report every individual opcode. Google Benchmark adapts its
iteration count and reports per-repetition records plus mean, median, standard
deviation, and coefficient of variation. The C harness reports five
fixed-work samples as min/median/max. The two harness loops have different
measurement and reporting overhead, so this table compares usability and
coverage, not framework-independent processor speed. The observed values do
not justify claiming a performance gain.

## Evaluation

Google Benchmark is a useful optional path for calibrated sampling, raw
machine-readable repetitions, aggregate spread, and workload counters. It
preserves the C core boundary and leaves default C11 builds dependency-free.
The current C harness remains simpler and covers additional workloads such as
output-heavy execution, branch loops, self-modification, and cycle detection.
Keep both available during the evaluation period; do not use these local
timings as a CI threshold or as evidence to remove the C harness. Repeat on an
idle host with identical optimized core/compiler settings before choosing a
permanent harness.
