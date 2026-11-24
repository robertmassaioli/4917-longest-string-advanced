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

Experiments are run serially on the shared GPU. Record each candidate's worktree,
commit, three wall times, exact result comparison, test result, and verdict here.
