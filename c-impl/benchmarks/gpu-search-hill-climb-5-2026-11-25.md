# GPU search hill climb 5: length-9 end-to-end optimization

## Campaign definition

- **Baseline:** commit `680b55d` on `codex/gpu-search-hill-climb-4`.
- **Target:** reduce median wall time for the exhaustive length-9 Metal search
  by at least 2%, while preserving exact search results.
- **Evaluator:** three serial runs of
  `/tmp/4917-hc5-baseline-build/4917-metal-search --length 9 --gpu-step-limit 256 --json`;
  process wall time measured with Python `time.perf_counter()`.
- **Guardrails:** all candidate counts, halt/cycle/error totals, best score,
  winner count, and first winner must match. Run CTest, including the Metal
  differential test, before accepting each candidate.
- **Hardware:** Apple M4 Pro; AppleClang 17; macOS Metal backend.
- **Acceptance threshold:** each retained candidate must improve the current
  campaign median by at least 2% after correctness checks.
- **Stop rule:** three rounds maximum. The target was reached in all three
  rounds; no further candidates were attempted in this campaign.
- **Landing target:** campaign branch `codex/gpu-search-hill-climb-5`; not
  merged to `main` and not pushed.

## Baseline and corrected earlier timing

The clean release build at the baseline commit passed all five existing CTest
checks. The three length-9 wall times were **132.648716, 130.883858, and
132.530268 seconds**, for a median of **132.530268 seconds**.

Every run exhaustively evaluated the same result:

- 68,719,476,736 candidates; 60,931,421,044 halted; 7,788,055,692 cycled;
  zero errors.
- Best output: 678 characters; one winner:
  `[8,8,13,1,14,5,2,6,15]`.
- GPU classified 60,929,847,271 halts and 7,683,098,233 cycles; 106,531,232
  candidates used exact CPU fallback.

The earlier 342.67-second length-9 timing came from the stale executable
`/tmp/4917-hc3-integrated-build/4917-metal-search`. A fresh release build of
the recorded baseline commit measured about 132.5 seconds, consistent with the
previous 2.15-minute projection. This campaign uses the fresh build and the
same fixed evaluator throughout.

## Sol candidate board and results

Sol reviewed the current Metal kernel, CPU fallback runner, and previous
campaigns. Expected gains below were hypotheses, not measurements.

| Candidate | Hypothesis | Result |
|---|---|---|
| Search-only Brent classifier returns immediately on a repeated full machine state; it does not find the cycle prefix and replay. | Avoids extra passes for the roughly 106 million CPU fallbacks. | **Accepted.** Three-run median 85.763345 s from the fresh baseline comparison, a 35.29% reduction. |
| Smaller CPU result/fallback tickets, 4096 to 256 candidates. | Reduces tail imbalance between CPU workers. | **Rejected.** Median 84.146848 s against the cycle-only median 85.763345 s is a 1.88% reduction, below the 2% cutoff. All correctness checks passed. |
| Use a 32-bit output counter in bounded Metal mode and remove the per-PRINT 64-bit overflow branch. | The 256-step GPU budget bounds output below the packed result's 30-bit score capacity. | **Accepted after paired remeasurement.** Interleaved cycle-only and combined medians were 85.606294 s and 83.714674 s, a 2.21% reduction. |
| Packed 16-nibble CPU machine state and initialize it directly from candidate ID. | Replaces byte-array copies/comparisons with a 64-bit memory word and avoids decoding fallback candidates to arrays. | **Accepted.** Isolated candidate median 73.267681 s; final integrated median 76.096293 s. It improved 9.10% over the previous integrated best in the final build. |
| Resume CPU fallback from GPU continuation state. | Avoids repeating the first 256 instructions on unresolved candidates. | Not tested; needs a new GPU result format and fallback-state protocol. |
| Keep a bounded producer queue so CPU fallbacks can drain across GPU batches. | Reduces GPU idle time when one batch has costly fallbacks. | Not tested; needs cross-batch slot ownership and shutdown changes. |
| Integrate GPU reduction/compaction with asynchronous reusable buffers. | Reduces host scanning of GPU result records while retaining overlap. | Not tested; existing reduction prototype used a synchronous path. |
| Replace 64-bit GPU memory with two 32-bit words. | May reduce variable-shift cost. | Not tested; risk of slower selection logic and address errors. |
| Use a visited-state bitset for conservatively selected immutable-memory programs. | Could avoid Brent work for programs with no STORE. | Not tested; needs a sound store exclusion check and per-worker bitset. |

### Candidate measurements

Cycle-only search measurements (seconds):

```text
132.648716, 130.883858, 132.530268  baseline median 132.530268
87.957410,  85.633317,  85.763345  cycle-stop median 85.763345
```

The compact-output optimization initially showed inconsistent results after
promotion. An interleaved comparison was used to control for machine load:

| Pair | Cycle-only wall time (s) | Cycle + 32-bit compact output (s) |
|---:|---:|---:|
| 1 | 85.606294 | 83.948879 |
| 2 | 85.577420 | 83.622606 |
| 3 | 85.728974 | 83.714674 |
| **Median** | **85.606294** | **83.714674** |

The packed-state candidate measured:

```text
73.208961, 73.274304, 73.267681  isolated candidate median 73.267681
```

After both accepted optimizations were integrated, three serial runs measured:

```text
76.237348, 76.096293, 76.092780  final median 76.096293
```

The integrated median is **42.58% faster** than the clean length-9 baseline
(132.530268 s), or about **1.74× the throughput**. It is **9.10% faster** than
the prior accepted cycle-stop plus compact-output build's paired median.

## Correctness and final result

The final length-9 run still reported 68,719,476,736 candidates, 60,931,421,044
halts, 7,788,055,692 cycles, zero errors, best output 678, one winner, and the
same program `[8,8,13,1,14,5,2,6,15]`. GPU and exact CPU-fallback totals were
unchanged.

The new `search-aggregate-equivalence` test compares the search-only runner to
the exact public runner for every program of lengths 1–4 (69,904 candidates)
and 10,000 deterministic random 16-cell programs. Halt output counts and
halted states must match; cycle candidates must receive the same termination
classification. The Metal differential test also checks lengths 1–3 and GPU
budgets on both sides of the compact-output cutoff.

All **6/6 CTest checks passed** on the final integrated build. `git diff --check`
passed. The final implementation was verified at `f01c3e5`; no changes were
pushed or merged into the default branch.

## Worktrees

- Campaign: `codex/gpu-search-hill-climb-5` at
  `/Users/robertmassaioli/Code/4917-longest-string-advanced.worktrees/gpu-search-hill-climb-5`.
- Accepted cycle-stop experiment: `codex/hc5-search-cycle-stop`.
- Accepted bounded-output experiment: `codex/hc5-narrow-metal-output`.
- Accepted packed-state experiment: `codex/hc5-packed-cpu-state`.
- Rejected small-ticket experiment: `codex/hc5-small-fallback-tickets`.

Experiment branches remain available for review.
