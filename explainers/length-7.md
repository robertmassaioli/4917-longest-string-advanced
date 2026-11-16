# Length-7 winners: accumulator loops

## Search domain and result

The exhaustive search considers all `16^7 = 268,435,456` seven-nibble vectors. Each vector is placed at memory addresses 0–6 and zero-padded through address 15; trailing zeroes remain distinct search candidates. A candidate counts only if it halts. Its score is the number of decimal characters emitted, and every tied maximum is included.

Length 7 has 26 tied winners, each emitting 172 characters. The search summary reports 243,947,408 halts and 24,488,048 cycles, with no errors. The source traces show that each winner emits 86 values, all two-character decimal values, then halts.

The exact programs below are grouped by the pattern emitted by `4917-cli generalize`. In the families with `k`, each listed winner uses one value from 10 through 15. The CLI generalizes that PRINT operand to `AnyOf [10-15]`; this preserves the character count, but the emitted text changes with the chosen value.

## Generalized pattern groups

| Winners | Exact programs | Generalized memory pattern |
|---|---|---|
| 1–6 | `[1,8,k,14,4,1,15]`, `k = 10…15` | `[ADD, PRINT, k (PRINT operand), JZ, INC_R1, ADD, JNZ, HALT, HALT, *,*,*,*,*,*,*]` |
| 7–12 | `[2,8,k,14,4,2,15]`, `k = 10…15` | `[SUB, PRINT, k (PRINT operand), JZ, INC_R1, SUB, JNZ, HALT, HALT, *,*,*,*,*,*,*]` |
| 13 | `[2,14,4,8,13,2,15]` | `[SUB, JZ(4), INC_R1, PRINT(13), JMP(2), SUB, JNZ(0), HALT, HALT, *,*,*,*,*,*,*]` |
| 14 | `[2,14,4,8,14,2,15]` | `[SUB, JZ(4), INC_R1, PRINT(14), JZ(2), SUB, JNZ(0), HALT, HALT, *,*,*,*,*,*,*]` |
| 15, 17, 19, 21, 23, 25 | `[8,k,1,14,4,1,15]`, `k = 10…15` | `[PRINT, k (PRINT operand), ADD, JZ, INC_R1, ADD, JNZ, HALT, HALT, *,*,*,*,*,*,*]` |
| 16, 18, 20, 22, 24, 26 | `[8,k,2,14,4,2,15]`, `k = 10…15` | `[PRINT, k (PRINT operand), SUB, JZ, INC_R1, SUB, JNZ, HALT, HALT, *,*,*,*,*,*,*]` |

Each list gives cells 0–15 in order. `*` means the CLI marks a cell as unused and accepts any nibble there. In the four families, `k` is a PRINT operand and the CLI marks it `AnyOf`: any value from 10 through 15 prints two characters. The names `JZ`, `JNZ`, `JMP`, and `PRINT` denote the opcodes stored in their cells; their following cells hold operands. Some cells serve both roles: for example, cell 2 is the JZ target operand and the INC_R1 instruction in the two special variants. The branch targets shown in parentheses are operand values, not additional memory cells.

The two middle variants remain separate generalized patterns. Their differing cell 4 is a different opcode (`JMP` versus `JZ`), so `generalize` does not combine them. All 26 winners appear in the table.

## How the loops work

The four six-winner families share the same counter-and-accumulator shape. R1 begins at zero. `INC_R1` advances it only when the conditional jump encounters R0 at zero; the ADD or SUB instruction combines R1 with R0, and `JNZ(0)` repeats the loop while R0 is nonzero. Depending on whether PRINT appears before or after the update, the output instruction is at address 0 or 1. The add and subtract variants move the accumulator in opposite directions, but both reach the same maximum output count and halt.

The `[2,14,4,8,13,2,15]` variant subtracts R1 from R0 at address 0, branches on zero to the JMP at address 4, and that JMP routes execution to `INC_R1` at address 2. The normal path prints 13, subtracts R1 again, and uses JNZ to return to address 0. The `[2,14,4,8,14,2,15]` variant places JZ at address 4 instead: when the accumulator is zero, it branches to the same increment instruction; otherwise it falls through to JNZ. Both produce 86 two-character outputs, but use a different path and take 463 steps rather than 447.

## Memory and registers

The `generalize` summaries agree on a small footprint:

- The four six-winner families use instruction locations `[0,1,3,4,5,6,8]`, operand/data locations `[2,4,7]`, and leave locations 9–15 unused. Address 4 is both an instruction and an operand/data location across the code layout.
- The two special variants use instruction locations `[0,1,2,3,4,5,6,8]`, operand/data locations `[2,4,5,7]`, and leave locations 9–15 unused. Their compact layout reuses some cells as instruction and operand locations.
- All summaries report both R0 and R1 as consumed, including an R0 value that combines R0 and R1. The traces show the arithmetic accumulator in R0 and the incrementing counter in R1.
- The winners do not modify memory. Their memory footprint is instruction fetches and operand reads; no data is stored back into memory.

## What these winners suggest

Across the main families, a two-register loop can use zero detection to advance a secondary counter while repeatedly changing an accumulator. Reordering output around the update, choosing ADD versus SUB, and selecting any two-character PRINT operand each retain the 172-character score in these observed programs. The two extra winners use a distinct branch arrangement to reach the same score.

These patterns describe the tested winners and the CLI's reported equivalence classes. They do not establish that arbitrary substitutions preserve halting or score. In particular, changing a PRINT operand within its reported `AnyOf` set preserves the two-character output width here but changes output text; wildcard cells were classified as unused by this analysis, but arbitrary substitutions should still be validated by running the resulting program.
