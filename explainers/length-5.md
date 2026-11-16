# Explaining the length-5 winners

Exhaustive enumeration found 72 length-5 programs tied for the best score: 62 output characters. Running the built `4917-cli generalize` command on each winner confirms that every one halts after 125 steps and that the 72 programs fall into 12 emitted patterns, with six winners per pattern.

The 12 patterns have a simple shape: three placements of `PRINT`, crossed with the two choices for updating R1 (`INC_R1` or `DEC_R1`) and the two choices for combining R1 into R0 (`ADD` or `SUB`). Each pattern leaves the `PRINT` operand as `AnyOf 10–15`. Those six operand values are the six winners in that group.

## Shared loop

All winners use a four-bit R0 accumulator and loop while R0 is nonzero. Each iteration prints a fixed value from 10 through 15, changes R1 by one (with wraparound), adds or subtracts R1 from R0, and executes `JNZ 0`. The `JNZ` operand at byte 5 is zero, so a nonzero R0 returns execution to byte 0. When R0 reaches zero, execution falls through to the `HALT` at byte 6.

Arithmetic wraps modulo 16. Starting from R0=R1=0, the R1 update makes its successive values cycle upward or downward through the nibbles. R0 accumulates the signed values of that sequence. With either direction for R1 and either `ADD` or `SUB`, the first return of the accumulator to zero is after 31 iterations: the accumulated magnitude is the triangular sum `1 + 2 + … + 31 = 496`, which is divisible by 16. The loop therefore prints 31 values. Each value from 10 to 15 takes two decimal characters, giving `31 × 2 = 62` characters. The loop uses four instructions per iteration (124 steps), followed by one `HALT` step, matching the observed 125-step execution.

## The three layouts

The patterns differ in where the print and arithmetic instructions sit in the loop:

| Program shape | Order in each iteration | Pattern count |
| --- | --- | ---: |
| `[4|6, 1|2, 8, k, 15]` | Change R1, add/subtract it from R0, print `k`, branch | 4 |
| `[4|6, 8, k, 1|2, 15]` | Change R1, print `k`, add/subtract it from R0, branch | 4 |
| `[8, k, 4|6, 1|2, 15]` | Print `k`, change R1, add/subtract it from R0, branch | 4 |

Here `4` and `6` encode `INC_R1` and `DEC_R1`; `1` and `2` encode `ADD` and `SUB`; `8` is `PRINT`; `15` is `JNZ`; and `k` is any value from 10 through 15. Within each layout, each of the four combinations of R1 direction and R0 arithmetic is a distinct emitted pattern. The six choices of `k` account for its six matching winners.

The placement changes whether printing happens before or after the accumulator update, but the loop still prints exactly once per iteration and tests R0 after the update. That preserves the iteration count. The generalizer marks the active instruction bytes and the required halt bytes; the JNZ target byte remains fixed at zero. Bytes after the halt are wildcarded because these executions never read them.

## What the generalization means

The `AnyOf 10–15` operand preserves the score because every allowed value prints two decimal characters. It does **not** preserve exact output: changing `k` changes every printed pair, even though the output length remains 62. These are score-preserving generalizations for the character-count objective, not exact-output equivalence classes.

The 12 patterns summarize the 72 observed winners compactly and suggest a way to recognize repeated loop structures. They are useful evidence for analysis or candidate prioritization. Before using them to prune a search, validate the generalization against the intended scoring and execution semantics, including the allowed wildcard assignments. A pattern emitted from one run describes that run's observed equivalence conditions; by itself it does not establish that discarding every covered candidate is safe for every search objective.
