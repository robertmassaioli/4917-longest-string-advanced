# Proposal: Move the 4917 native implementation to C++17

## Recommendation

Use C++17 for the processor core and CLI. The instruction engine is small and
uses fixed-width values, a 16-cell machine state, and a switch over 16 opcodes.
Equivalent C and C++ implementations should compile to comparable optimized
code; the language change alone is not expected to slow the search. Runtime
differences should be measured with the same compiler, optimization flags, and
workloads before claiming a speedup or regression.

Keep the bounded hot path allocation-free. Use the standard library for safer
ownership in diagnostic cycle detection and CLI output collection. Expose a
small C ABI at the machine boundary for existing C clients and independent
cross-language checks.

## Library choices

| Need | Recommendation | Reason |
| --- | --- | --- |
| Command-line parsing | CLI11 | Native C++ interface, typed option binding, subcommands, help generation, and a small package footprint. It replaces Argtable3 without pulling the C parser into the C++ CLI. |
| Core and data structures | C++17 standard library | `std::array`, `std::vector`, `std::string_view`, and `std::from_chars` cover current needs without another runtime dependency. |
| Microbenchmarks | Keep Google Benchmark optional | Useful calibration and result reporting, but unnecessary for production builds. It calls the same C++ core through the C ABI; it does not establish whether C or C++ is faster. |
| JSON | No new dependency | The current three small, fixed JSON responses can be emitted directly. If the schema grows, evaluate a JSON library separately rather than adding one preemptively. |

CLI11 is header-only by default and supports C++11 and newer; this project uses
C++17 for `std::string_view` and modern library support. The Homebrew formula
currently provides CLI11 2.7.2. Google Benchmark remains optional; Homebrew
provides it as `google-benchmark`.

## Homebrew setup

For the normal native build, install the required parser:

```sh
brew install cli11
```

For the full developer workflow, including the optional Google Benchmark
target, install both packages:

```sh
brew install cli11 google-benchmark
```

These are the current Homebrew formula names: [CLI11](https://formulae.brew.sh/formula/cli11)
and [Google Benchmark](https://formulae.brew.sh/formula/google-benchmark).
No explicit `CMAKE_PREFIX_PATH` should be needed for a standard Homebrew
installation because CMake searches Homebrew's package-config paths. If no
package is found, the CMake configuration can fetch the pinned CLI11 2.7.2
archive with a SHA-256 check.

## Implementation shape

- Compile `machine.cpp` and `main.cpp` as C++17; remove Argtable3 and its
  fetch fallback from CMake.
- Preserve the merged C implementation's current semantics, including the
  specialized bounded runner and cycle-aware `4917-search-v2` behavior.
- Keep validation and presentation in the CLI layer. Keep `i4917_step` and
  bounded execution free from dynamic allocation.
- Use RAII containers for variable-sized diagnostic data and emitted output.
  Translate allocation failure in the cycle detector to the existing
  execution-error result.
- Retain the C ABI temporarily for the C property-test and benchmark clients.
  This provides useful coverage of the library boundary while the production
  implementation itself is C++.
- Keep the CLI executable name `4917-cpp` so users can distinguish it from
  existing binaries during the transition. Revisit the installed name only
  after downstream scripts are identified.

## Verification and performance comparison

After integrating local `main`, both implementations were rebuilt with Release
settings and compared using the same standalone C benchmark source and fixtures.
The C baseline is commit `3437e7a`; both builds used Apple clang 17.0.0.13,
macOS arm64, and `-O3`. Three paired captures ran sequentially through the
repository benchmark queue. The table reports each fixture's median throughput
across the three run medians; the score is the median of the paired geometric
mean C++/C ratios over the five core workloads.

| Fixture | C throughput | C++ throughput | C++ change |
| --- | ---: | ---: | ---: |
| Short straight-line | 838.0 M instructions/s | 839.6 M instructions/s | +0.0% |
| Arithmetic-heavy | 1,281.8 M instructions/s | 1,282.4 M instructions/s | +0.1% |
| Output-heavy | 869.9 M instructions/s | 866.6 M instructions/s | -0.3% |
| Branch loop | 752.2 M instructions/s | 757.4 M instructions/s | +0.4% |
| Self-modifying | 868.4 M instructions/s | 869.4 M instructions/s | +0.0% |
| Output cycle detection | 79.1 M logical steps/s | 82.5 M logical steps/s | +2.6% |
| Exhaustive length-two search | 42.7 M candidates/s | 42.7 M candidates/s | +0.0% |

The five-workload geometric-mean score was **1.0008× (+0.08%)** for C++ over
C. This is practical parity with the optimized C implementation from `main`;
the earlier C++ measurements against the pre-optimization baseline no longer
describe the comparison. The per-fixture results also show no material
regression, and length-two search is at parity. Small differences are within
the expected timing noise, so this supports “C++ is not slower here,” not a
claim that C++ is faster.

The C and Google Benchmark harnesses both call the same compiled core, so
compare harness reporting separately from this C-versus-C++ comparison.

Per-opcode timings and their raw captures are in
[`c-impl/benchmarks/results/cpp-port-comparison-2026-11-15.md`](c-impl/benchmarks/results/cpp-port-comparison-2026-11-15.md).

The existing C test and standalone benchmark clients can remain during the
transition because the ABI is deliberately stable. A later cleanup can port
those clients to C++ if maintaining a C compiler requirement is not worthwhile.

## Risks and tradeoffs

- CLI11 changes some parser-generated diagnostic wording. Keep the user-facing
  commands, required options, validation rules, exit codes, and JSON schemas
  stable; update exact diagnostic checks where the wording is owned by CLI11.
- A C ABI is an extra compatibility surface. Keep it narrow and avoid exposing
  C++ containers or exceptions across it.
- C++ does not automatically improve runtime. Avoid allocations and abstractions
  in the instruction loop, and measure generated workloads before adopting
  performance-specific changes.
- The C property-test and benchmark clients mean a C compiler is still needed
  in the full development build. Production-only configurations can disable
  tests and the standalone C benchmark.

## Sources

- [CLI11 documentation](https://cliutils.github.io/CLI11/)
- [Google Benchmark repository](https://github.com/google/benchmark)
- [Homebrew CLI11 formula](https://formulae.brew.sh/formula/cli11)
- [Homebrew Google Benchmark formula](https://formulae.brew.sh/formula/google-benchmark)
