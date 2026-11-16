# Length-4 search winners

## Search domain and score

A length-4 candidate is a four-nibble vector, with every remaining memory cell zero-padded through the machine's 16-cell memory. The exhaustive search therefore considers all 16⁴ = 65,536 vectors, including vectors whose final listed nibble is zero. The search counts output characters only for programs that halt; cycles are ineligible. At length 4, 61,121 candidates halted, 4,415 cycled, and none errored. The maximum was 32 characters, shared by 24 winners.

The winners all print a two-digit value 16 times. Their common loop is driven by R0, a four-bit register: incrementing or decrementing wraps modulo 16, and JNZ repeats while R0 is nonzero. The loop therefore reaches zero after 16 updates and then halts.

## Winners grouped by generalized pattern

Each winner has three variable nibbles: the update instruction is either INC_R0 (`3`) or DEC_R0 (`5`), and the PRINT operand `k` is any value from 10 through 15. Every group below contains six programs, one for each `k` in that range. The generalized patterns were obtained by running the CLI's `generalize` command separately on all 24 winners; all commands reported a halted termination and 32 output characters.

| Pattern | Six winners | Loop order |
| --- | --- | --- |
| `38[10–15]1500**********` | `[3,8,k,15]`, `k = 10…15` | INC_R0, PRINT k, JNZ |
| `58[10–15]1500**********` | `[5,8,k,15]`, `k = 10…15` | DEC_R0, PRINT k, JNZ |
| `8[10–15]31500**********` | `[8,k,3,15]`, `k = 10…15` | PRINT k, INC_R0, JNZ |
| `8[10–15]51500**********` | `[8,k,5,15]`, `k = 10…15` | PRINT k, DEC_R0, JNZ |

In these patterns, the bracketed range is an **AnyOf** set of PRINT operands. The trailing `*` cells are unused by the observed execution and are generalized as wildcards. In each row, the exact required cells encode the loop: the update and PRINT instructions, JNZ, its zero operand, and the HALT at cell 5. The generalized output labels cell 4 as HALT because its required value is zero, the HALT opcode value; during execution, cell 4 is used only as JNZ’s zero operand. The branch skips to cell 5 when it is not taken, and the actual final HALT executes there.

The usage summaries are consistent across all 24 runs. Update-first programs use instruction locations `[0,1,3,5]` and operand/data locations `[2,4]`; print-first programs use instruction locations `[0,2,3,5]` and operand/data locations `[1,4]`. R0 is consumed, R1 is not, and no R0/R1 combination is reported. The programs execute 49 steps: 16 passes through the three-instruction loop, followed by HALT.

## What differs and what stays the same

The four patterns differ only in whether the counter update occurs before or after PRINT, and whether the update increments or decrements. The update-before-print variants start by moving R0 away from zero, then print; after the sixteenth update wraps R0 to zero, they still print once before JNZ falls through. The print-before-update variants print first, then update and test; on the sixteenth pass the update wraps R0 to zero and the branch exits. In both orders, there are 16 two-character outputs and a total score of 32.

Within each pattern, changing `k` from 10 to 15 preserves the score because every value in that range prints two decimal characters. It changes the emitted text, however: the AnyOf set describes score-preserving alternatives, not identical output. The generated pattern is an inference from each concrete run and its observed memory usage; it is not, by itself, an exhaustive proof of behavior for every possible wildcard substitution.
