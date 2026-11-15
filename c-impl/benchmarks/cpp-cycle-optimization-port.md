# C++ cycle-search optimization port

## Goal and evaluator

- Port the three C cycle-search optimizations that cleared the 1% threshold to the current C++ implementation.
- Accept an optimization only when it improves the measured production length-5 exhaustive search by at least 1% and emits byte-for-byte identical JSON.
- Evaluator: `4917-cpp search --length 5 --json`, repeated in alternating baseline/candidate pairs under the shared lock at `/tmp/4917-longest-string-advanced-c-benchmark.lock`.
- Guardrails: preserve the public checked C ABI, halt/cycle and output-count behavior, and no max-step cutoff. Release CTest and output equality must pass.
- Landing target: local `main`, commit `61eb925`. No remote changes are authorized.

## Baseline

- AppleClang 17.0.0.17000013, macOS arm64, Release `-O3 -DNDEBUG`.
- Source: `61eb925` (`Port VM implementation to C++ and record benchmarks`).
- Five alternating baseline self-pairs gave per-run times of 0.110036, 0.117698, 0.115297, 0.111803, and 0.112593 seconds; median 0.112593 s, range 0.110036–0.117698 s.
- Output: 1,048,576 candidates; 969,109 halted; 79,467 cycled; zero errors; best output 62; 72 winners; first winner `[4,1,8,10,15]`.
- Release CTest passed 4/4 before experimentation.
- Baseline paired capture: `results/cpp-cycle-baseline-paired.json`.

## Candidate ideas and results

1. Skip cycle checks while PC strictly increases; if a halt occurs, return that real execution directly. On the first nonincreasing PC, activate Floyd from the original state and replay the result for output accounting.
2. Use private detector-only stepping to skip full-state validation, event/output bookkeeping, and operand/target loads for opcodes that do not need them. Keep public `i4917_step` checked.
3. Let exhaustive search call a private entry point for its already-valid zero-padded program, avoiding public initialization and validation copies.

Each paired timing did an unmeasured output-equality preflight, then alternated baseline and candidate order. Every timed run's JSON matched exactly. Times below are medians of paired per-run speed ratios (`baseline / candidate`); the detailed samples are saved beside this file.

| Candidate | Pairs | Baseline median | Candidate median | Median speedup | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| PC-monotone probe + Floyd | 15 | 112.788 ms | 93.147 ms | 1.2323x (+23.23%) | Keep |
| Private detector stepping with vector history | 15 | 112.972 ms | 99.104 ms | 1.1383x (+13.83%) | Keep |
| Search-only trusted entry | 15 | 110.436 ms | 106.215 ms | 1.0426x (+4.26%) | Retest |
| Search-only trusted entry, repeat | 21 | 111.046 ms | 104.214 ms | 1.0750x (+7.50%) | Keep; all 21 paired ratios exceeded 1.0 |
| PC-monotone probe + trusted entry | 21 | 112.117 ms | 88.458 ms | 1.2655x (+26.55%) | Keep |
| PC-monotone probe + trusted entry + private detector stepping | 21 | 111.468 ms | 73.879 ms | 1.5006x (+50.06%) | Keep; best candidate |

The final candidate combines all three changes. On the same exhaustive length-5 search it improved the median paired time by 50.06% versus `61eb925`. The candidate preserves the output summary (1,048,576 candidates; 969,109 halted; 79,467 cycled; zero errors; best output 62; 72 winners; first winner `[4,1,8,10,15]`). Release CTest passed 4/4 before and after the final combination. The C++ benchmark fixture currently covers only bounded length-2 execution, so these production CLI pairs are the relevant cycle-search measurement.

Result files:

- `results/cpp-opt-probe-paired-15.json`
- `results/cpp-opt-step-paired-15.json`
- `results/cpp-opt-search-entry-paired-15.json`
- `results/cpp-opt-search-entry-repeat-paired-21.json`
- `results/cpp-probe-search-entry-paired-21.json`
- `results/cpp-probe-entry-step-paired-21.json`
- Baseline captures: `results/cpp-cycle-baseline-paired.json` and `results/cpp-cycle-baseline-paired-11.json`
