# Length-3 search winners

## Search domain and score

The length-3 search considers all `16^3 = 4,096` three-nibble programs in lexicographic order. Each candidate is placed at the start of a 16-cell memory image and the remaining 13 cells are zero-padded. Trailing zero nibbles are still distinct candidates in this length-specific search. A candidate scores the number of decimal characters emitted only if it halts; cycling programs are ineligible. The exhaustive aggregate reports 3,782 halted candidates, 314 cycles, zero errors, and a best score of 3 characters shared by 6 winners.

## All winners

Each winner prints its second nibble as a two-digit decimal value, then prints the zero in the padded cell at location 3. The zero contributes one character, for a total of three.

| Winner | Program nibbles | Emitted values | Score |
|---:|---|---|---:|
| 1 | `8,10,8` | `10`, `0` | 3 |
| 2 | `8,11,8` | `11`, `0` | 3 |
| 3 | `8,12,8` | `12`, `0` | 3 |
| 4 | `8,13,8` | `13`, `0` | 3 |
| 5 | `8,14,8` | `14`, `0` | 3 |
| 6 | `8,15,8` | `15`, `0` | 3 |

The aggregate table in `optimal-programs-length-1-to-7.md` also reports 6 tied winners at length 3, so this list accounts for the complete maximum.

## Generalized pattern

All six `generalize` runs emit the same equivalence class:

```text
8[101112131415]8[0123456789]0***********
```

The class groups the winners into one pattern:

- Location 0 is the required `PRINT` opcode `8`.
- Location 1 is a two-character output operand. Values `10` through `15` all occupy two decimal digits.
- Location 2 is the required `PRINT` opcode `8`.
- Location 3 is a one-character output operand. Values `0` through `9` all occupy one decimal digit.
- Location 4 is the required `HALT` opcode `0`.
- Locations 5 through 15 are unused by the observed execution and are wildcards in the generalized pattern.

The original winners all use `10` through `15` at location 1 and rely on zero padding for location 3. The generalized operand ranges express digit widths that preserve the three-character score; they do not promise that substituted operands preserve the exact output text. The pattern is a hypothesis produced by generalizing one execution, not a claim that every wildcard substitution has been independently exhaustively checked for every behavior.

## Execution footprint

The CLI reports instruction locations `[0,2,4]`, operand/data locations `[1,3]`, and unused locations `[5,6,7,8,9,10,11,12,13,14,15]`. It reports `R0 consumed: False`, `R1 consumed: False`, and `R0 contains R0/R1 combination: False`. Each run takes three steps: print at location 0, print at location 2, and halt at location 4. No register is read for this straight-line output sequence.

## Interpretation

At length 3, the best available shape is two consecutive `PRINT` instructions followed by a halt in the padded memory. The first printed operand supplies two decimal characters, while the padded zero supplies one more. The six winners differ only in which two-digit value they print first; their control flow, second output, halt, and register usage are identical.
