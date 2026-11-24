# GPU search hill climb 4: follow-up candidates

## Campaign definition

- **Baseline:** `90c5515` (`codex/gpu-search-hill-climb-3`), the compact-result GPU search with per-batch Metal resource release.
- **Target:** reduce median end-to-end wall time for exhaustive length-8 search by at least 2%, with exact result equivalence.
- **Evaluator:** serial process runs of `/tmp/4917-hc3-integrated-build/4917-metal-search --length 8 --gpu-step-limit 256 --json`; process wall time measured by `time.perf_counter()`.
- **Acceptance threshold:** the initial baseline median was 20.831808 s (2% threshold 20.415172 s). A fresh three-run baseline after the candidate trials measured 21.199288 s, so the final comparisons use the refreshed 2% threshold of 20.775302 s.
- **Guardrails:** candidate count, halted/cycled/error totals, best output, winner count and first winner must match; GPU/fallback accounting must cover all candidates; all five CTest tests must pass. Keep the GPU step limit at 256 and preserve generic large-budget and single-program behavior.
- **Budget:** all seven remaining ideas requested by the user, in three serial rounds (3 + 3 + 1), followed by a compatibility-tested combination of qualifying changes. The GPU is shared, so no overlapping benchmarks.
- **Landing target:** this campaign worktree/branch `codex/gpu-search-hill-climb-4`; no merge or push requested.

## Baseline measurements

Command: `/tmp/4917-hc3-integrated-build/4917-metal-search --length 8 --gpu-step-limit 256 --json`, three serial runs. Initial wall times: 20.548318, 20.894526, and 20.831808 s (median 20.831808 s). A refresh after all candidates measured 21.199288, 21.120323, and 21.238146 s (median 21.199288 s; range 21.120323–21.238146 s). Each returned the same exact search result: 4,294,967,296 candidates; 3,858,727,572 halted; 436,239,724 cycled; 0 errors; best output 482; 102 winners; first winner `[1,8,10,14,4,2,4,15]`; 3,858,689,162 GPU halts; 430,609,734 GPU cycles; and 5,668,400 exact CPU fallbacks.

All five baseline CTest tests passed, including the Metal differential test.

## Candidate idea board

The hypotheses and expected upside come from the previous Sol review; estimates are not measurements.

| ID | Candidate | Expected upside | Key correctness risk |
|---|---|---:|---|
| A | Reuse shared Metal buffers and overlap GPU batches with host classification. | 5–20% | Buffer lifetime, command ordering, and ordered winner reduction. |
| B | Search-only CPU Brent classifier to avoid Floyd prefix/period discovery and replay. | 3–12% | Full-state cycle equality and exact output/error semantics. |
| C | Decode candidate nibbles only for fallback candidates or new best winners. | 0–5% | Deterministic first winner and tie count. |
| D | GPU threadgroup reduction plus compact unresolved candidate IDs. | 10–30% | Exact counters/ties, bounded compaction capacity, barrier safety. |
| E | Use 32-bit instruction/output/cycle counters in the bounded GPU kernel. | 2–10% | No overflow at supported budgets; generic large-budget path unchanged. |
| F | Initialize packed memory directly from encoded nibbles, avoiding repeated `write_cell`. | 2–8% | Preserve nibble order for every length, including 16. |
| G | Schedule CPU fallback work dynamically in atomic ticket blocks. | 2–6% | Preserve exact counts and deterministic earliest winner. |

## Candidate results

All seven candidates were built independently from the baseline, checked with
all five CTest tests, and benchmarked serially. Repeated length-8 runs returned
identical JSON result fields except for elapsed time.

| Candidate | Commit | Process wall times (s) | Median (s) | Change vs refreshed baseline | Verdict |
|---|---|---:|---:|---:|---|
| Reuse two Metal result/parameter buffer slots; dispatch the next GPU batch while the host classifies the previous one. | `93a7f5e` | 12.978743, 12.403402, 13.913505 | 12.978743 | 38.8% faster | Accepted; best standalone result. |
| Search-only exact Brent cycle classifier. | `877642d` | 19.912805, 19.496020, 19.823449 | 19.823449 | 6.5% faster | Accepted; exact first-repeat output is preserved by replay. |
| Decode a candidate only for CPU fallback or a new local winner. | `122c914` | 17.875387, 17.581919, 17.681812 | 17.681812 | 16.6% faster | Accepted. |
| Per-threadgroup reduction and compact unresolved IDs. | `2f4f320` | 13.280053, 13.239443, 13.270850 | 13.270850 | 37.4% faster | Accepted as a standalone candidate; slightly slower than buffer overlap. |
| Use 32-bit instruction/cycle counters for compact bounded GPU mode. | `7beb00d` | 19.198632, 19.016771, 19.531944 | 19.198632 | 9.4% faster | Accepted. Large-budget mode retains 64-bit counters. |
| Initialize packed memory by reversing the encoded nibbles in a shift loop. | `9466dad` | 20.270365, 20.514548, 19.851382 | 20.270365 | 4.4% faster | Accepted. The first naive, unreversed assignment failed the length-2 differential test and was corrected before measurement. |
| Assign CPU fallback candidates through 4096-item atomic tickets. | `5898868` | 16.398159, 15.986800, 16.803519 | 16.398159 | 22.6% faster | Accepted; deterministic earliest-winner tracking retained. |

The first reduction-kernel test caught an address-space qualifier error in the
Metal shader. After correcting it, all five CTest tests passed and the full
length-8 result matched the baseline.

## Combined candidate

The best compatible combination uses buffer reuse/overlap, exact Brent fallback,
lazy program decoding, 32-bit bounded counters, packed-nibble initialization,
and dynamic CPU fallback scheduling. These changes are committed on the campaign
branch as `aebc551` plus the preceding accepted candidate commits.

Three serial process runs measured 7.971867, 7.637133, and 7.259698 s (median
7.637133 s; range 7.259698–7.971867 s). This is 64.0% below the refreshed
21.199288 s baseline, and 41.2% below the best standalone candidate's 12.978743
s median. All five CTest tests passed, and all result fields matched exactly:
4,294,967,296 candidates; 3,858,727,572 halts; 436,239,724 cycles; zero errors;
best output 482; 102 winners; first winner `[1,8,10,14,4,2,4,15]`; 3,858,689,162
GPU halts; 430,609,734 GPU cycles; 5,668,400 exact CPU fallbacks.

The GPU threadgroup reduction is not included in this combination. Its standalone
implementation uses a synchronous two-kernel batch path, while the best buffer
candidate overlaps consecutive batches. The standalone reduction result was
slightly slower than overlap, and combining those two would require integrating
the reduction buffers into the double-buffered asynchronous slots. The six
accepted optimizations already combine cleanly and pass the fixed evaluator.

## Updated CPU-versus-GPU runtime estimates

The CPU length-9 search remains measured at 7,558.18 s. CPU estimates for later
lengths use the prior observed 18.44× growth per nibble. The new combined GPU
build measured 7.637133 s at length 8. Its length-9 estimate scales the prior
measured length-9 GPU time of 371.147 s by the length-8 improvement relative to
the prior integrated build's 22.00 s run:
`371.147 × (7.637133 / 22.00) = 128.84 s` (2.15 min). GPU estimates for lengths
10–16 then use 16× growth per added nibble, matching the candidate-space growth.
Only CPU length 9 and GPU length 8 are measured for the current comparison;
other values are projections.

| Length | Candidates | CPU time | GPU time | Projected speedup |
|---:|---:|---:|---:|---:|
| 9 | 68.7 billion | 2.10 h measured | 2.15 min projected | 58.7× |
| 10 | 1.10 trillion | 1.61 days | 34.36 min | 67.6× |
| 11 | 17.6 trillion | 29.75 days | 9.16 h | 77.9× |
| 12 | 281.5 trillion | 1.50 years | 6.11 days | 89.8× |
| 13 | 4.50 quadrillion | 27.7 years | 97.73 days | 103.5× |
| 14 | 72.06 quadrillion | 510.6 years | 4.3 years | 119.3× |
| 15 | 1.15 quintillion | 9,416.3 years | 68.5 years | 137.5× |
| 16 | 18.45 quintillion | 173,636 years | 1,095.9 years | 158.4× |

## Worktrees

The campaign branch is `codex/gpu-search-hill-climb-4` at
`/Users/robertmassaioli/Code/4917-longest-string-advanced.worktrees/gpu-search-hill-climb-4`.
Each independent candidate remains available for inspection in its own
`hc4-*` worktree and `codex/hc4-*` branch. Nothing was merged or pushed.
