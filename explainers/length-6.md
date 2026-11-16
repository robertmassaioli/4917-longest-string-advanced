# Length-6 search winners

The exhaustive length-6 search considered all `16^6 = 16,777,216` six-nibble programs. Each program is zero-padded to 16 cells before execution, so a shorter effective instruction stream can include trailing zero cells. The score counts decimal characters emitted by programs that halt; cycles do not qualify. The search reports 15,407,834 halted candidates, 1,369,382 cycles, zero errors, a best score of 93 characters, and two tied winners. These counts and the step traces are recorded in [`optimal-programs-length-1-to-7.md`](../optimal-programs-length-1-to-7.md).

## Winners and patterns

Both winners halt after 187 steps and emit 93 characters. Running `generalize` on each yields:

| Winner | Generalized pattern |
| --- | --- |
| `[4,8,8,13,2,15]` | `4881321500********` |
| `[6,8,8,13,2,15]` | `6881321500********` |

In these 16-cell patterns, cells 0–7 are fixed and cells 8–15 are wildcarded. The usage summary for both runs reports instruction locations `[0,1,2,3,4,5,7]`, operand/data locations `[2,3,4,6]`, unused locations `[8,9,10,11,12,13,14,15]`, and that both R0 and R1 are consumed and R0 contains a combination of R0 and R1. The wildcarded suffix is therefore the part `generalize` observed to be unused in these executions.

## Shared loop, opposite register motion

The common instruction layout prints 8 at cell 1, jumps from cell 3 back to cell 2, prints 13 there, subtracts the current R1 value from R0 at cell 4, then uses `JNZ` at cell 5 to return to cell 0. Cell 0 changes R1: opcode 4 increments it in the first winner; opcode 6 decrements it in the second. The changing R1 and subtract result drive the loop toward its eventual zero condition. Each pass emits one one-digit value and one two-digit value, or three characters. The recorded 31 passes account for all 93 characters before execution falls through to HALT.

The winners show two ways to arrange a long halting run with only six specified nibbles: update a register, emit a fixed-width pair of values, and use the wrapped arithmetic state as a loop condition. Their only difference is whether R1 moves upward or downward; the print, jump, subtract, and branch instructions are shared.

## What the patterns do and do not show

The exact values 8 and 13 both print one and two decimal characters respectively, so together they contribute three characters per pass. Here they are literal output values, and the generalized patterns keep those cells fixed. The patterns also show that the unused memory tail can vary without affecting these observed runs.

These are execution-based generalizations from the two winners, not proofs that arbitrary substitutions at wildcard cells preserve behavior in every context. Likewise, changing a printed value to another value of the same digit width can preserve the score while changing output text, but neither length-6 pattern generalizes 8 or 13 that way.
