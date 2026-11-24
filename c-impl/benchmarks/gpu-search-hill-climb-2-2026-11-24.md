# GPU search hill climb 2: M4 Pro

## Campaign definition

- **Baseline:** `e3f0f7e` (`codex/gpu-search-hill-climb`), Apple M4 Pro / Metal 3,
  macOS 15.7.4, AppleClang 17, Release build.
- **Target:** reduce exhaustive length-8 Metal search wall time by at least 15%.
  The baseline median is 69.049 s, so a candidate must reach 58.7 s or less.
- **Evaluator:** run
  `/tmp/4917-gpu-hill-final-build/4917-metal-search --length 8 --gpu-step-limit 256 --json`
  three times serially and measure process wall time. Compare every result field
  to the baseline result. Keep the 256-step GPU budget fixed.
- **Guardrails:** exhaustive candidate count and termination totals must match;
  best score, tied-winner count, and first winner must match; unresolved GPU
  candidates continue through exact CPU cycle detection; existing CTest passes.
- **Budget:** up to 3 rounds and 3 candidates per round, serially, because all
  candidates use this computer's one GPU. Stop after 2 rounds without an
  accepted improvement, or sooner if the target is met.
- **Landing target:** `codex/gpu-search-hill-climb-2`; do not merge or push.

## Baseline measurements

Three process-wall runs at GPU budget 256:

| Run | Wall time | Solver-reported time |
|---:|---:|---:|
| 1 | 71.733 s | 69.595 s |
| 2 | 64.657 s | 62.454 s |
| 3 | 69.049 s | 66.357 s |
| **Median** | **69.049 s** | **66.357 s** |

All runs searched 4,294,967,296 candidates and returned 3,858,727,572 halts,
436,239,724 cycles, zero errors, best output 482 characters, 102 winners, and
first winner `[1,8,10,14,4,2,4,15]`.

Baseline verification: Release build available at
`/tmp/4917-gpu-hill-final-build`; all 5 CTest tests passed.

## Sol-subagent idea board

The `gpt-6.1-sol` review was read-only and proposed these ranked hypotheses:

| Rank | Hypothesis | Expected upside | Correctness guardrail | Experiment |
|---:|---|---|---|---|
| 1 | Add bounded exact cycle detection on GPU using complete machine-state checkpoints; CPU-fallback anything undecided. | Avoid spending 256 GPU instructions and then restarting common short cycles on CPU. | Compare full memory, registers, and PC; hashes alone cannot prove a cycle. Preserve output-overflow behavior. | Compare all search fields on lengths 1–7 and repeat length-8 timings. |
| 2 | Double-buffer Metal batches so GPU execution overlaps host classification; reuse shared buffers and avoid result copies. | Reduce serial GPU plus CPU time toward the slower stage's time. | Keep buffer ownership safe; preserve ordered reduction and command failures. | Measure stages, then compare repeated timings and exact results. |
| 3 | Replace per-batch creation of eight CPU threads with a persistent worker pool. | Remove thread startup/join overhead and balance expensive fallback work dynamically. | Keep per-worker summaries and deterministic first-winner selection. | Compare block sizes and repeated length-8 timings. |
| 4 | Pack all 16 memory nibbles in a 64-bit word. | Reduce private memory and speed complete-state snapshots. | Preserve nibble order, wrapping, and self-modifying stores. | Differential tests plus length-7/8 timings. |
| 5 | Reduce halted results on GPU and compact only unresolved IDs. | Reduce result transfer and host scanning for billions of candidates. | Preserve all unresolved candidates, ties, first winner, and `2^64` totals. | Compare exact results at small lengths and measure transferred bytes. |

## Candidate results

Experiments were run serially on the shared GPU. Each candidate used the same
Release configuration and the fixed 256-step GPU budget.

| Candidate | Worktree commit | Wall times | Median | Exact result / tests | Verdict |
|---|---|---:|---:|---|---|
| Pack the 16 memory nibbles into one `ulong` | `c4cf488` | 66.23, 65.16, 63.92 s | 65.16 s | Search totals and winners matched; all 5 CTest tests passed. | About 5.6% below baseline, short of the 15% target and within baseline run variation. Keep as an experiment only. |
| Reuse eight host workers across batches | `f7c7a7b` | 66.43, 64.44, 64.93 s | 64.93 s | Search totals and winners matched; all 5 CTest tests passed. | About 6.0% below baseline, short of the target. Keep as an experiment only. |
| Detect exact cycles on GPU with Brent checkpoints over full memory, registers, and PC | `c3b84d1`, promoted as `42a9a9d` | 47.31, 44.16, 56.33 s | 47.31 s | All result fields matched; all 5 CTest tests passed; exact CPU comparisons passed at lengths 4–7. | Accepted. 31.5% faster than baseline median; target met. |

The cycle detector excludes output from the repeated-state key, matching the
machine's execution-state semantics. It counts a candidate as GPU-cycled only
when the complete state repeats; anything still unresolved at the GPU budget
continues to the exact CPU runner. The single-program trace path still uses the
CPU runner for cycles so it reports the exact first-repeat step count.

The accepted length-8 result was identical to baseline: 4,294,967,296
candidates; 3,858,727,572 halted; 436,239,724 cycled; zero errors; best output
482 characters; 102 winners; first winner `[1,8,10,14,4,2,4,15]`. Of those
cycles, 430,609,734 were proven on GPU and 5,668,400 went through exact CPU
fallback. The integrated campaign build measured 53.64 seconds wall time and
returned the same result.

The accepted candidate was built and tested on the campaign branch after
promotion. All five CTest tests passed. In addition, exhaustive CPU-versus-GPU
comparisons at lengths 4, 5, 6, and 7 matched candidate count, halt/cycle/error
totals, exhaustive status, best output, winner count, and first winner. The
existing Metal differential test covers lengths 1–3 at GPU budgets 1, 2, and
4096, plus wrapped PRINT, self-modifying memory, and a single-program cycle.

## Outcome

The 15% target was met in the first round. The campaign branch is
`codex/gpu-search-hill-climb-2`; no merge or push was performed. Packed-state
and persistent-worker experiments remain available on `codex/hc2-gpu-packed-state`
and `codex/hc2-gpu-threadpool` for inspection.
