# Skip immediate-zero programs benchmark

**Date:** 2026-11-25  
**Hardware:** Apple M4 Pro, 20-core Metal 3 GPU  
**Build:** AppleClang 17, CMake Release  
**Baseline:** 7f6b2a32987336e1a889375d43bf30f6dff9ff21  
**Candidate:** codex/skip-leading-zero

Both binaries were built from Release sources on the same machine. The baseline
was extracted from the base commit into /tmp; no checkout or working-tree
changes were made for it. Runs alternated baseline then changed, three times
per backend. CPU measurements used process wall time for the actual
4917-cpp search --length 7 --json command. Metal measurements used process
wall time for the full exhaustive 4917-metal-search --length 9 --json
command. Metal provisional-winner JSONL capture remained enabled (the default);
each run wrote its 311 records to a distinct /tmp path.

| Backend / length | Baseline times (s) | Changed times (s) | Median baseline | Median changed | Speedup |
|---|---|---|---:|---:|---:|
| CPU / 7 | 5.816040, 5.438893, 5.424215 | 5.340056, 5.356378, 5.295045 | 5.438893 | 5.340056 | 1.018x |
| Metal / 9 | 75.247484, 74.689790, 76.153155 | 71.196555, 72.206539, 72.135533 | 74.689790 | 72.135533 | 1.035x |

The CPU search space at length 7 contains 268,435,456 IDs. The changed search
evaluated 251,658,240, skipping the 16,777,216 programs with a zero first
nibble. Its halted count is lower by exactly that skipped prefix; cycles,
best score (172), 26 winners, and first winner
[1,8,10,14,4,1,15] match baseline.

The Metal search space at length 9 contains 68,719,476,736 IDs. The changed
search evaluated 64,424,509,440, skipping 4,294,967,296 immediate-zero
programs. Both versions reported 7,788,055,692 cycles, best score 678, one
winner [8,8,13,1,14,5,2,6,15], and 106,531,232 exact CPU fallbacks. The
changed halt count is lower by exactly the skipped prefix. Winner capture
produced 311 records in all runs.

The speedup reflects avoiding execution of that contiguous ID prefix. These
are local measurements; process startup, Metal shader compilation, thermal
state, and concurrent system load contribute to wall time.

## Verification

- cmake --preset release && cmake --build --preset release -j 8
- ctest --preset release: 6/6 passed, including Metal differential search
- CLI JSON spot checks at lengths 1 and 2 reported searched, full-space, and
  skipped counts consistently
