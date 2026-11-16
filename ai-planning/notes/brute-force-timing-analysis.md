# 4917 Processor: Brute Force Timing Analysis & Predictions

**Updated:** 2026-11-16
**Current implementation:** optimized C++ exhaustive search (`4917-cpp`)
**Machine:** MacBook Pro with Apple M4 Pro, running the search single-threaded

## Executive Summary

The current optimized C++ search completes all **1,048,576 length-5 programs in a median 73.9 ms** and all **268,435,456 length-7 programs in 25.13 s**. The length-7 run processed about **10.68 million programs per second**.

A measured length-5-to-length-7 growth factor extrapolates to about **18.44× per additional program slot**. On that model, length 8 takes about 7.7 minutes, length 9 about 2.4 hours, and length 16 about 196,600 years on one comparable core. These long-range estimates are highly uncertain: they extend a two-point scaling measurement, and the length-7 timing was a single run.

The search CLI accepts lengths 1–16, matching the VM's 16-cell memory. Length 16 has exactly 2^64 candidate programs; the C++ search now handles that candidate count without 64-bit overflow. This makes length 16 representable, not practical to search exhaustively.

## Current Measurements

| Length | Programs | Time | Throughput | Result |
|---:|---:|---:|---:|---|
| 5 | 1,048,576 | 73.879 ms median | 14.18 M/s | 969,109 halted; 79,467 cycled; best output 62; 72 winners |
| 7 | 268,435,456 | 25.13 s | 10.68 M/s | 243,947,408 halted; 24,488,048 cycled; zero errors; best output 172; 26 winners |

The length-5 time is the median candidate time from 21 alternating baseline/candidate pairs. It improved from a 111.468 ms median baseline to 73.879 ms, a 50.06% reduction. The optimization campaign, including raw paired timing files, is recorded in [`c-impl/benchmarks/cpp-cycle-optimization-port.md`](../../c-impl/benchmarks/cpp-cycle-optimization-port.md).

The length-7 time was measured by running the production command `4917-cpp search --length 7 --json` on the same optimized implementation. Its first winner was `[1,8,10,14,4,1,15]`.

## Projection for Lengths 8–16

The search space is `P(n) = 16^n`. For the runtime projection, the observed length-5-to-length-7 ratio gives this average multiplier per added slot:

```text
(25.13 s / 0.073879 s)^(1/2) = 18.44×
T(n) = 25.13 s × 18.44^(n - 7)
```

The raw candidate count grows by exactly 16× per slot. The measured time grew about 340× from length 5 to 7, or 18.44× per slot. That difference reflects the measured per-program work and run-to-run/environment variation; it should not be treated as a stable law for every length.

| Length | Programs | Estimated time for that length | Cumulative time, lengths 8 through this length |
|---:|---:|---:|---:|
| 8 | 4,294,967,296 | 7.7 min | 7.7 min |
| 9 | 68,719,476,736 | 2.37 hr | 2.50 hr |
| 10 | 1,099,511,627,776 | 1.8 days | 1.9 days |
| 11 | 17,592,186,044,416 | 33.7 days | 35.6 days |
| 12 | 281,474,976,710,656 | 1.7 years | 1.8 years |
| 13 | 4,503,599,627,370,496 | 31 years | 33 years |
| 14 | 72,057,594,037,927,936 | 578 years | 611 years |
| 15 | 1,152,921,504,606,846,976 | 10,660 years | 11,272 years |
| 16 | 18,446,744,073,709,551,616 | 196,612 years | 207,884 years |

The cumulative estimate for lengths 8–16 is about **208,000 years** on one comparable core. The earlier estimates in this document used a constant per-program cost and substantially underpredicted the measured length-7 runtime; they are retained below only as historical Haskell analysis.

## Current Search Optimizations

The C++ search now uses:

- A direct counted execution while the program counter increases, before enabling cycle detection.
- Floyd cycle detection with a replay pass to preserve exact output and halt behavior.
- A specialized private transition path for speculative cycle detection, while keeping the public checked machine API.
- A search-only entry point for programs the enumerator has already constructed and validated.

These changes reduced the measured length-5 search time by 50.06% versus the pre-optimization C++ baseline. The exhaustive search remains single-threaded. Because candidate programs are independent, dividing the candidate range across workers is a practical next scaling step; real speedup will depend on thread and memory-system overhead.

## Historical Haskell Baseline (2026-02-09)

The original analysis measured the Haskell implementation through length 6. These results are kept for historical comparison and are not used in the current projections.

| Length | Programs | Historical Haskell time | Time per program |
|---:|---:|---:|---:|
| 1 | 16 | <1 ms | — |
| 2 | 256 | <1 ms | — |
| 3 | 4,096 | <1 ms | — |
| 4 | 65,536 | 3 ms | 45.8 ns |
| 5 | 1,048,576 | 79 ms | 75.3 ns |
| 6 | 16,777,216 | 1,207 ms | 71.9 ns |

That analysis approximated a 72 ns per-program cost and predicted 19.3 seconds for length 7. This was a separate Haskell-era model; use the current C++ measurements and projections above for planning.

## Practical Guidance

- Lengths 1–5 are suitable for interactive searches.
- Length 7 takes about 25 seconds on the measured machine.
- Length 8 is estimated at several minutes; length 9 at a few hours.
- Length 10 and above become multi-day to multi-year searches under this extrapolation.
- Length 16 is supported by the CLI and counter representation, but an exhaustive single-core run is far beyond practical use.

For larger searches, prioritize parallel candidate ranges or approaches that reduce the candidate space. GPU acceleration would require a separate implementation of the VM and cycle detector; GPU core counts cannot be treated as equivalent CPU cores.
