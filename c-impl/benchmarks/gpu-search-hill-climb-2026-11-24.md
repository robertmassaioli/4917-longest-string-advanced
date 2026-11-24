# GPU search hill climb: M4 Pro

## Campaign definition

- **Baseline:** `ef10dbd` (`codex/gpu-solver`), Apple M4 Pro, macOS 15.7.4,
  AppleClang 17, Release build.
- **Target:** reduce full exhaustive length-7 Metal search wall time by at
  least 50%, from 10.589 seconds median to 5.294 seconds or less.
- **Evaluator:** run
  `/tmp/4917-gpu-build/4917-metal-search --length 7 --gpu-step-limit 256 --json`
  three times serially and measure process wall time. Candidate settings that
  change the GPU budget are passed explicitly. Compare exact result fields to
  `/tmp/4917-gpu-build/4917-cpp search --length 7 --json`.
- **Guardrails:** exact exhaustive candidate count and termination totals;
  same best output, tie count, and first winner as the CPU solver; existing
  CTest suite passes; no approximate step bound for overall classification.
- **Budget:** up to 3 rounds and 3 hypotheses per round, tested serially because
  all candidates share one physical GPU. Stop on target or after two rounds
  without an accepted improvement.
- **Landing target:** campaign branch `codex/gpu-search-hill-climb`; do not
  merge or push as part of this campaign.

## Baseline measurements

Three process-wall measurements at the default GPU budget of 256 steps:

| Run | Wall time | Metal-reported search time |
|---:|---:|---:|
| 1 | 10.618 s | 10.407 s |
| 2 | 10.589 s | 10.383 s |
| 3 | 10.313 s | 10.114 s |
| **Median** | **10.589 s** | **10.383 s** |

All three returned 268,435,456 candidates, 243,947,408 halts, 24,488,048
cycles, zero errors, a best output of 172 characters, 26 winners, and first
winner `[1,8,10,14,4,1,15]`. The median target is therefore 5.294 seconds.

Baseline correctness: CMake Release build succeeded and all 5 CTest tests
passed, including Metal-vs-CPU exhaustive comparisons for lengths 1–3 at GPU
budgets 1, 2, and 4096. Proposal numbering validation passed.

## Idea board

| Hypothesis | Change | Success condition | Main risk |
|---|---|---|---|
| Lower GPU budget | Run fewer GPU steps before exact CPU fallback. | Same exact result and a materially lower median. | More candidates fall back to CPU. |
| Larger batches | Increase candidates per Metal command to reduce per-batch allocation, synchronization, and launch overhead. | Same exact result and at least 10% lower median. | Larger shared buffers may increase memory pressure or reduce responsiveness. |
| Wider threadgroups | Raise threads per Metal threadgroup above the current 256 cap. | Same exact result and repeatable lower median. | Occupancy or register pressure may worsen. |
| Parallel CPU fallback | Classify unresolved candidates across CPU workers, with per-worker counters and deterministic reduction. | Same exact result and at least 10% lower median. | Thread scheduling and simultaneous CPU/GPU contention may erase gains. |

## Candidate results

### Preliminary GPU-budget sweep (baseline code)

One length-7 measurement per budget; these are screening results, not a new
baseline. The final result fields matched across all runs.

| GPU budget | Wall time | GPU halted | CPU exact fallback | Verdict |
|---:|---:|---:|---:|---|
| 8 | 17.619 s | 239,519,904 | 28,915,552 | Reject: fallback dominates. |
| 16 | 15.548 s | 241,060,402 | 27,375,054 | Reject: slower. |
| 32 | 15.113 s | 241,334,196 | 27,101,260 | Reject: slower. |
| 64 | 13.795 s | 242,478,844 | 25,956,612 | Reject: slower. |
| 128 | 10.966 s | 243,795,924 | 24,639,532 | Reject: slightly slower. |
| 256 | 10.354 s | 243,945,960 | 24,489,496 | Current best; consistent with baseline spread. |

## Round 1 results

All candidates started from code baseline `ef10dbd` plus the campaign-record
commit `097f5b3`. Each was built in its own worktree, evaluated serially, and
compared against the same length-7 result fields. The evaluator used three
serial process runs at GPU budget 256.

### Candidate 1: larger Metal batches

- **Branch/worktree:** `codex/hc-gpu-batch`,
  `/Users/robertmassaioli/Code/4917-longest-string-advanced.worktrees/hc-gpu-batch`.
- **Hypothesis:** raising the batch from 262,144 to 1,048,576 reduces Metal
  command submissions, buffer allocations, and waits.
- **Initial result:** the 24 MiB stack-allocated result array crashed with
  `SIGSEGV`; CTest had passed. Moved that array to the heap and reran.
- **Final measurements:** 10.941, 10.439, and 10.564 s; median 10.564 s.
- **Correctness:** all 5 CTest tests passed; length-7 counts and winners matched
  the baseline exactly.
- **Verdict:** reject. The median improves by only 0.2%, within noise, and is
  far from the 50% goal. The larger heap buffer adds memory usage.

### Candidate 2: 512-thread threadgroups

- **Branch/worktree:** `codex/hc-gpu-threadgroup`,
  `/Users/robertmassaioli/Code/4917-longest-string-advanced.worktrees/hc-gpu-threadgroup`.
- **Hypothesis:** increasing threadgroup width from 256 to 512 improves GPU
  occupancy and latency hiding.
- **Measurements:** 10.797, 11.305, and 11.333 s; median 11.305 s.
- **Correctness:** all 5 CTest tests passed; length-7 counts and winners matched
  the baseline exactly.
- **Verdict:** reject. It regressed by 6.8% at the median.

### Candidate 3: lower GPU step budgets

- **Branch/worktree:** `codex/gpu-solver`, baseline code, parameter-only sweep.
- **Hypothesis:** lower budgets avoid wasting GPU cycles on loops that need
  exact CPU cycle classification anyway.
- **Measurements:** recorded above for budgets 8–256.
- **Correctness:** all budgets returned identical exact length-7 outcomes.
- **Verdict:** reject. Every budget below 256 was slower; budget 8 took 17.619 s.

### Round 1 decision

No candidate produced a meaningful improvement. The baseline remains the
campaign best at 10.589 s median. Continue to round 2 with CPU/GPU overlap,
parallel fallback classification, and an exact GPU cycle-classification
hypothesis. Preserve the current 256-step exact-fallback behavior unless a
candidate proves a faster exact alternative.
