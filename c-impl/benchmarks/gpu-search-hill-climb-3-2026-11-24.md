# GPU search hill climb 3: M4 Pro

## Campaign definition

- **Baseline:** `7dfaafd` on `codex/hc2-combined-experiments`, containing exact
  GPU cycle detection, packed 64-bit memory, and a persistent host worker pool.
- **Target:** at least 2% lower median process wall time for exhaustive length-8
  Metal search at `--gpu-step-limit 256`.
- **Evaluator:** serial process wall-time runs of
  `/tmp/4917-hc2-combined-build/4917-metal-search --length 8 --gpu-step-limit 256 --json`.
- **Acceptance threshold:** baseline median was 38.40 s, so candidates must
  reach 37.63 s or less while returning the exact same exhaustive result.
- **Guardrails:** all candidate totals, halt/cycle/error counts, best output,
  winner count, and first winner must match; GPU and CPU classification counts
  must account for the complete candidate space; all five CTest tests pass.
- **Budget:** up to 3 rounds and 3 independent candidates per round, evaluated
  serially on the shared GPU. Stop after 2 rounds without a qualifying change.
- **Landing target:** `codex/gpu-search-hill-climb-3`; do not merge or push.

## Baseline

The accepted combined version returned 4,294,967,296 candidates, 3,858,727,572
halts, 436,239,724 cycles, zero errors, best output 482 characters, 102 winners,
and first winner `[1,8,10,14,4,2,4,15]`. The prior three wall times were 38.96,
38.40, and 36.89 seconds (median 38.40 s). A refresh before this campaign
returned 39.91 and 38.01 seconds; the existing five observations span 36.89–
39.91 seconds and still have a 38.40-second median. All five CTest tests pass.

## Sol-subagent idea board

The read-only `gpt-6.1-sol` review identified these candidates. Estimates below
are hypotheses, not measured outcomes.

| Rank | Candidate | Expected upside | Main guardrail |
|---:|---|---:|---|
| 1 | Pack exhaustive GPU results into 32-bit records; retain the generic result path for `--program` and unusually large step limits. | 5–20% | Output fits the encoding at the selected step budget; preserve status and all accounting. |
| 2 | Reuse shared Metal buffers and overlap the next GPU batch with host classification. | 5–20% | Do not reuse a slot until GPU and CPU users finish; merge summaries in batch order. |
| 3 | Add a search-only CPU Brent cycle classifier that skips locating and replaying the first cycle. | 3–12% | Full-state equality; exact halted output and overflow behavior; leave single-program trace semantics unchanged. |
| 4 | Delay decoding candidate nibbles until CPU fallback or a new best winner requires the program. | 0–5% | Preserve deterministic first winner and tie counts. |
| 5 | Reduce GPU results per threadgroup and compact unresolved candidate IDs. | 10–30%, higher risk | Preserve every tie and unresolved ID; safe output capacity and barrier participation. |

The previous 8-thread-width retry, batch-size-only changes, and lower GPU budget
were deprioritized because earlier experiments had regressed or shown negligible
benefit.

## Candidate results

Candidate timing and correctness checks were run serially because the M4 Pro
has one shared Metal GPU.

| Candidate | Commit | Wall times | Median | Correctness / tests | Verdict |
|---|---|---:|---:|---|---|
| Compact exhaustive GPU results into 32-bit records | `8e9e8b0`, promoted as `c1f61b2` | 21.19, 21.01, 23.12 s | 21.19 s | Exact length-8 totals and winners; all 5 CTest tests; generic large-budget path matched CPU exhaustively at length 1. | Accepted. 44.8% faster than the 38.40 s baseline median, exceeding the 2% threshold. |

The integrated campaign build ran length 8 in 22.00 seconds and returned the
same 4,294,967,296-candidate result: 3,858,727,572 halts, 436,239,724 cycles,
zero errors, best output 482, 102 winners, first winner
`[1,8,10,14,4,2,4,15]`. It classified 3,858,689,162 halts and 430,609,734
cycles on GPU; the exact CPU fallback handled 5,668,400 candidates.

The compact format stores the status in two low bits and the halted output
count in the remaining 30 bits. A halted candidate within a budget of at most
`2^29` instructions can emit at most `2 × (budget - 1)` characters, so the
encoding is lossless. Larger budgets keep the original 24-byte result layout;
the single-program interface also keeps that layout so it can report exact
instruction counts. At length 8, the search result buffer and host copy shrink
from 96 GiB to 16 GiB across all batches.

The 2% acceptance threshold was reached in the first round, so the campaign
stopped without running the remaining ideas. Separate clean worktrees remain
available for the untried lazy-decode candidate at
`codex/hc3-lazy-decode` and search-only CPU Brent candidate at
`codex/hc3-search-brent`.

## Outcome

The campaign branch is `codex/gpu-search-hill-climb-3`. The accepted commit is
`c1f61b2`; no merge or push was performed.
