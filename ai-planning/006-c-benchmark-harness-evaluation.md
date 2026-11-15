# 006: Evaluate the C benchmark harness

**Status:** Proposed  
**Created:** 2026-11-15

## Summary

Evaluate whether the C implementation should replace its hand-written timing
harness with a benchmark framework. The production processor remains C11. A
benchmark harness may be written in C++ if it calls the C core through its
existing C interface and if the C++ toolchain and dependency are required only
for opt-in benchmark builds.

The leading candidate is Google Benchmark. It offers the most useful mix for
this repository of calibrated iteration counts, repeated samples and
statistics, machine-readable results, throughput counters, and optional
hardware performance counters. It is a C++ framework, however, so the proposal
is to first build a small, optional comparison harness around the existing
per-opcode and whole-program workloads. Keep the current C harness available
until measured results and usability show that migration is worthwhile. Do not
adopt a framework solely because it reports more statistics: benchmark design,
repeatable workloads, compiler metadata, and controlled measurement
conditions remain necessary.

## Motivation and current state

The benchmark executable in `c-impl/benchmarks/bench.c` currently uses
`clock_gettime(CLOCK_MONOTONIC)`, fixed iteration counts, five samples, and
min/median/max throughput. It measures representative program runs, exhaustive
length-two search, cycle detection, and all individual instructions, including
taken and not-taken conditional branches. Results can be emitted as NDJSON.
For single-instruction fixtures it currently executes 1,048,576 calls per
sample and includes `i4917_step` state validation in the timed region. The
benchmark target is optional in CMake and has no third-party dependency.

This is a compact and understandable baseline with useful fixtures. Its
limitations are that sample duration is fixed by iteration count, samples are
not automatically calibrated to a target duration, and each benchmark manages
its own setup, statistics, and command-line interface. The current min/median/
max record also does not surface spread as directly as standard-deviation or
coefficient-of-variation reports. Those limitations matter most when making
small per-opcode comparisons. Replacing the timer alone does not fix
measurement noise, make unlike workloads comparable, or prove that a timing
difference is real.

## Candidate comparison

The comparison focuses on optional development/benchmark dependencies. None
would be linked into `4917_core` or `4917-c`.

| Candidate | Language and fit | Measurement/reporting | CMake, dependencies, and portability | Assessment |
| --- | --- | --- | --- | --- |
| Existing C harness | Native C, directly calls the C core | Fixed work per sample; five repetitions; min/median/max throughput; project-specific JSON lines | No added dependency; uses POSIX `clock_gettime`, so current source is Unix-oriented | Keep as the baseline and fallback. It is small, transparent, and already covers the workloads we care about. |
| [Google Benchmark](https://github.com/google/benchmark) | C++ framework; benchmark functions can call the C API, while the production library remains C | Chooses iteration counts based on a minimum run time; configurable repetitions report mean, median, standard deviation, and coefficient of variation; supports JSON/CSV output, custom counters, and optional performance counters | CMake project and integration; Apache-2.0. Building the framework requires C++17. Its own test suite can require GoogleTest; disable framework tests for dependency builds. Hardware counters use platform-specific support and may need `libpfm`/permissions. | Best candidate for an optional evaluation. It improves calibration and reporting while preserving the C implementation boundary, at the cost of an optional C++ toolchain and dependency. |
| [Catch2 benchmarks](https://github.com/catchorg/Catch2) | C++ test framework; can benchmark functions in the C core | Convenient microbenchmarks integrated with tests and supports benchmark execution mode; its project describes these as basic microbenchmarking features | CMake integration; current v3 uses C++14/17 or later and is distributed under BSL-1.0; benchmark target still adds C++ and framework dependencies | Consider only if a C++ correctness-test harness is separately adopted. Benchmarking is not enough reason to add Catch2 when the C tests already work without it. |
| [Criterion](https://github.com/Snaipe/Criterion) | C-native C/C++ unit-test framework | Provides process-isolated tests, theories, test reports, and test-running statistics; its documented purpose is unit testing, not calibrated microbenchmark measurement | Cross-platform project, MIT license, CMake find module; has a broader dependency set than the current plain-C test executable | Not a benchmark-harness replacement. It may be evaluated separately for unit testing, but that is outside this proposal. |
| [benchmarkC](https://github.com/pirminschmid/benchmarkC) | C microbenchmark toolbox, explicitly x86_64-focused | Includes low-level timing and statistics utilities, but is positioned as an educational toolbox rather than a maintained general benchmark platform | MIT; source says it uses `rdtsc`, was tested with macOS Clang and Fedora GCC, and dates its current version to 2017 | Not a good portability or maintenance fit. Its README itself points readers to Google Benchmark for microbenchmarks. |

Google Benchmark's iteration calibration and summary statistics are useful,
but they are not a statistical significance test and do not control CPU
frequency, thermal state, competing processes, or machine variation. Its JSON
report includes host and CPU context, and its throughput counters can express
instructions or candidates per second. Its optional performance-counter
support can report quantities such as cycles, retired instructions, and cache
misses where the platform and permissions support them. Treat these as
additional evidence, not as portable or universally available metrics.

## Proposed direction

Run a bounded comparison before choosing a permanent harness:

1. Add Google Benchmark behind the existing opt-in benchmark build setting,
   or a new explicit option if clearer. Keep normal C builds and production
   targets C-only and dependency-free. Enable C++ in CMake only when the
   benchmark framework is requested.
2. Pin Google Benchmark to a reviewed release and immutable source revision or
   verified archive. Fetch dependencies only for the explicit benchmark
   configuration. Disable building the framework's own tests when embedding
   it. Document the optional C++17 requirement, offline behavior, and a
   dependency-free build path.
3. Port a representative subset first: each opcode, both branch outcomes,
   short straight-line execution, arithmetic-heavy execution, and exhaustive
   length-two search. The C++ harness must call the same exported C functions
   as the current C harness; it must not reimplement instructions or compile
   `machine.c` as C++.
4. Keep fixture semantics stable. For per-opcode comparisons, reset the
   program counter as the current fixture does, and report that state
   validation is included. Keep state setup outside the timed operation where
   intended. Use an observable state/result sink and inspect representative
   optimized builds to confirm the measured C calls are not optimized away.
5. Run the current and candidate harnesses against the same release build,
   compiler, flags, host, and workloads. Record raw results, environment
   metadata, build revision, run commands, and benchmark-framework version.
   Repeat on an otherwise idle machine. Compare run-to-run spread and
   per-opcode ranking stability, not just the fastest single sample.
6. Adopt Google Benchmark for ongoing measurements only if the comparison
   demonstrates practical value in per-opcode calibration, reproducibility,
   result handling, or profiling without unacceptable dependency/build
   friction. Otherwise keep the existing C harness and improve its sampling,
   metadata, and reporting directly. Do not keep two permanent harnesses
   unless they serve distinct documented use cases.

No third-party benchmark framework should create a timing pass/fail threshold
in ordinary CI. CI may compile the optional benchmark target and perform a
short dry run to catch broken registrations; performance regression gates need
a stable, dedicated runner and an independently agreed noise policy. The
existing deterministic C correctness tests remain separate from benchmarks.

## CMake and dependency design

The production project currently declares only the C language. If Google
Benchmark is selected, make C++ an optional language for the benchmark-only
configuration, and set the framework's documented language standard on its
own target. Continue compiling `4917_core`, `4917-c`, and C tests as C11.
Link the benchmark harness against `4917_core` so the benchmark crosses the
same C ABI as production callers.

Keep the benchmark dependency opt-in and pinned. Do not fetch it in the
default build, production-only build, or ordinary C test configuration.
Provide a documented way to configure benchmarks from a preinstalled package
or a pre-populated source tree for offline use. The CMake integration must not
implicitly download GoogleTest for the framework's internal tests. Keep the
current standalone C benchmark usable as a fallback during the evaluation
period, then remove it only if the decision is to migrate and the candidate
has equivalent workload coverage.

## Benchmark methodology requirements

Whether the repository adopts a library or retains its own harness, benchmarks
must:

- Separate setup and teardown from timed work unless the named workload
  intentionally measures initialization or end-to-end execution.
- Name the unit of work precisely: `single_steps`, `logical_steps`,
  `candidates`, or complete runs. Report throughput with matching units.
- Preserve the per-opcode breakdown, and distinguish taken/not-taken branches.
- Record compiler identity/version, optimization flags, build type, source
  revision, operating system, CPU model, harness version, and workload
  parameters with saved results.
- Keep correctness checks outside the timed inner loop where possible; perform
  a preflight correctness assertion/checksum for every fixture and retain a
  sink or framework optimization barrier so the compiler cannot discard the
  work.
- Run enough repetitions to expose spread. Retain raw samples and avoid
  presenting min alone as representative performance.
- Keep benchmark output structured and versioned if scripts or CI consume it.
- Avoid comparing timings across unlike compilers, flags, machines, or
  benchmark fixtures as though they isolated an instruction-level change.
- Use hardware counters only as optional diagnostic data and label unsupported
  counters clearly. Do not require privileged access or platform-specific
  counters for a successful benchmark run.

## Acceptance criteria

- A documented comparison covers the current C harness and at least one
  candidate library using the same C workloads and optimized C core.
- Per-opcode records remain available for all 16 opcodes, with separate
  outcomes for conditional branches.
- The benchmark configuration remains opt-in; a normal C11 production build
  does not require a C++ compiler or network access.
- If Google Benchmark is adopted, its source/version is pinned, CMake builds
  the harness cleanly, structured output includes meaningful workload
  counters and run context, and benchmark setup does not alter the C core's
  language or dependency requirements.
- Benchmark documentation explains calibration, repetitions, raw-result
  retention, environment metadata, and the limits of interpreting local
  microbenchmark results.
- Performance results remain informational unless a stable runner and explicit
  regression policy are established in a separate change.

## Open decisions

- Should the optional benchmark target add a C++17 compiler requirement when
  requested, or should the repository prioritize an all-C toolchain even for
  benchmark tooling?
- Is the primary value sought per-opcode calibration and statistics, or do
  future requirements include comparison dashboards, continuous regression
  detection, or hardware-counter analysis?
- Which compiler/OS combinations must be supported for the benchmark target?
- Should optional benchmark dependency fetching use CMake `FetchContent`, a
  package manager/system package, or support both?
- Does the comparison show enough practical improvement over a small C harness
  to justify retaining the extra framework and C++ build path?

## References

- [Google Benchmark repository and build requirements](https://github.com/google/benchmark)
- [Google Benchmark user guide: iteration control, repetitions, and statistics](https://github.com/google/benchmark/blob/main/docs/user_guide.md#timing-and-repetition-control)
- [Google Benchmark user guide: output formats and JSON context](https://github.com/google/benchmark/blob/main/docs/user_guide.md#output-formats)
- [Google Benchmark user guide: performance counters](https://github.com/google/benchmark/blob/main/docs/user_guide.md#performance-counters-and-context)
- [Google Benchmark license](https://github.com/google/benchmark/blob/main/LICENSE)
- [Catch2 repository and benchmark feature](https://github.com/catchorg/Catch2)
- [Catch2 license](https://github.com/catchorg/Catch2/blob/devel/LICENSE.txt)
- [Criterion C/C++ unit-testing framework](https://github.com/Snaipe/Criterion)
- [Criterion license](https://github.com/Snaipe/Criterion/blob/bleeding/LICENSE)
- [benchmarkC repository and scope](https://github.com/pirminschmid/benchmarkC)
- [benchmarkC license](https://github.com/pirminschmid/benchmarkC/blob/main/LICENSE)
