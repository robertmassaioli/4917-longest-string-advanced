# GPU search hill climb 4: follow-up candidates

## Campaign definition

- **Baseline:** `90c5515` (`codex/gpu-search-hill-climb-3`), the compact-result GPU search with per-batch Metal resource release.
- **Target:** reduce median end-to-end wall time for exhaustive length-8 search by at least 2%, with exact result equivalence.
- **Evaluator:** serial process runs of `/tmp/4917-hc3-integrated-build/4917-metal-search --length 8 --gpu-step-limit 256 --json`; process wall time measured by `time.perf_counter()`.
- **Acceptance threshold:** baseline median 20.831808 s; required median at most 20.415172 s.
- **Guardrails:** candidate count, halted/cycled/error totals, best output, winner count and first winner must match; GPU/fallback accounting must cover all candidates; all five CTest tests must pass. Keep the GPU step limit at 256 and preserve generic large-budget and single-program behavior.
- **Budget:** all seven remaining ideas requested by the user, in three serial rounds (3 + 3 + 1), followed by a compatibility-tested combination of qualifying changes. The GPU is shared, so no overlapping benchmarks.
- **Landing target:** this campaign worktree/branch `codex/gpu-search-hill-climb-4`; no merge or push requested.

## Baseline measurements

Command: `/tmp/4917-hc3-integrated-build/4917-metal-search --length 8 --gpu-step-limit 256 --json`, three serial runs. Process wall times: 20.548318, 20.894526, and 20.831808 s (median 20.831808 s; range 20.548318–20.894526 s). Each returned the same exact search result: 4,294,967,296 candidates; 3,858,727,572 halted; 436,239,724 cycled; 0 errors; best output 482; 102 winners; first winner `[1,8,10,14,4,2,4,15]`; 3,858,689,162 GPU halts; 430,609,734 GPU cycles; and 5,668,400 exact CPU fallbacks.

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

_To be filled as candidates are evaluated._
