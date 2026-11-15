# C implementation benchmark hill climb

## Goal and acceptance

- Improve the C implementation by at least 10%; aim for 2× or better.
- Correctness is required: the release CTest suite must pass for an accepted candidate.
- Keep all benchmark workload definitions unchanged during comparisons.
- Stop after meeting the target; do not spend the remaining candidate budget without a reason.

## Benchmark coordination

`benchmark_queue.py` serializes builds, tests, and timed captures with an exclusive `fcntl` lock at `/tmp/4917-longest-string-advanced-c-benchmark.lock`. Candidate agents and the final baseline/candidate captures all used this queue. Each paired capture ran baseline and candidate sequentially while holding the same lock, so they did not contend with one another.

## Source and worktree

The active task worktree had uncommitted search/report edits. The campaign began from its committed `bba4fae` base in a separate worktree. As requested, local `main` was merged into the campaign branch as `6912510`; the merge brings in Google Benchmark and its CMake preset. The cycle-aware search behavior was preserved while resolving CLI conflicts, and the release CLI contract tests were updated accordingly. The selected optimization is commit `d063793` on branch `codex/c-impl-hill-climb`.

## Evaluation method

After the `main` merge, Google Benchmark became the primary evaluator. The score is the geometric mean of candidate-to-baseline median `items_per_second` ratios for `short_straight_line`, `arithmetic_heavy`, and `search_length_two`. Each fixture uses nine repetitions at `--benchmark_min_time=0.05s`. The raw paired results are `results/google-baseline-paired.json` and `results/google-inline-paired.json`; rerun the comparison with:

```sh
python3 benchmarks/score_google_results.py \
  benchmarks/results/google-baseline-paired.json \
  benchmarks/results/google-inline-paired.json
```

The original five-fixture C harness remains a diagnostic cross-check. `score_results.py` computes its geometric mean, but it is not the accepted score after the harness change.

## Preliminary round before merging `main`

These three candidates used the same clean `bba4fae` source base and the original five-fixture C harness, with five outer passes each. They are retained as screening results; the final decision uses the merged-source Google Benchmark comparison below.

| Candidate | Commit | Median score | Change vs 182.077 M instr/s baseline | CTest | Outcome |
| --- | --- | ---: | ---: | --- | --- |
| `trusted-step` | `ca5d437` | 451.807 M/s | +148.1% | 3/3 passed | Faster; superseded by inline runner. |
| `lazy-operands` | `8a157b0` | 171.497 M/s | −5.8% | 3/3 passed | Rejected; regressed. |
| `inline-runner` | `8ea5ff9` | 911.457 M/s | +400.6% | 3/3 passed | Chosen for final merge-source verification. |

The preliminary baseline and candidate outputs are retained as `results/baseline.ndjson` and `results/*-pre-main.ndjson`.

## Final paired result after merging `main`

- **Baseline:** `6912510` (merge of local `main`), Google Benchmark 1.10.0, AppleClang 17 Release, Apple M4 Pro / macOS 15 arm64.
- **Candidate:** `d063793`, the specialized `i4917_run_bounded` dispatch loop.
- **Correctness:** Release CTest passed 4/4 on both the merged baseline and candidate. The tests include 10,000 run-vs-step comparisons.
- **Primary score:** geometric mean speedup **5.272×** (**+427.2%**).

| Fixture | Baseline median | Candidate median | Speedup | Candidate CV |
| --- | ---: | ---: | ---: | ---: |
| `short_straight_line` | 155.393 M/s | 790.692 M/s | 5.088× | 0.26% |
| `arithmetic_heavy` | 161.669 M/s | 1,282.624 M/s | 7.934× | 0.58% |
| `search_length_two` | 18.030 M candidates/s | 65.441 M candidates/s | 3.630× | 0.20% |

The paired captures recorded 1-minute load averages of 11.62 for baseline and 11.15 for candidate (5-minute: 8.95 and 8.83). Google Benchmark reported it could not set thread affinity on this host. Candidate variation was low; baseline CV was 9.60%, 1.98%, and 6.27% for the three fixtures respectively.

Separate seven-repetition captures (`results/google-baseline.json` and `results/google-inline-candidate.json`) are retained for reference, but excluded from the score because the baseline host load was much higher than the candidate's.

The C harness cross-check also moved from 183.936 to 846.232 M instructions/s in one full capture each (+360.1%). Its five fixture medians all improved. This cross-check is supporting evidence only; the paired Google result is the accepted score.

## Decision

Accept `d063793`. It clears both the 10% target and the 2× stretch goal with all correctness checks passing. No further optimization rounds were run.
