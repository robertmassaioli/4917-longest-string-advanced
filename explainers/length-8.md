# Length-8 maximal-output programs

## Search convention and result

The length-8 domain is all `16^8 = 4,294,967,296` vectors over nibble values 0–15. Each vector is loaded at cells 0–7 and zero-padded through cell 15. Only halted candidates count toward the score; cyclic candidates are ineligible. The score is the number of decimal characters emitted, so printing a value from 10 through 15 contributes two characters.

The exhaustive C++ enumeration used the same `i4917_detail::run_search_program` core as the production search. It completed the full domain with zero errors. Every tied winner was then passed once to the Haskell CLI's `generalize` command. The resulting patterns below group winners by exact emitted wildcard pattern.

| Length | Candidates | Halted | Cycled | Errors | Best characters | Tied winners |
|---:|---:|---:|---:|---:|---:|---:|
| 8 | 4,294,967,296 | 3,858,727,572 | 436,239,724 | 0 | 482 | 102 |

The exhaustive run took 7m 27.99s wall time (441.66s user time). The 102 `generalize` runs all reported HALTED and 482 output characters. Their outputs yielded 22 distinct patterns: 16 groups of six winners and six singleton groups.

## Common shape and variations

All 102 winners use both registers, and `generalize` reports that R0 contains an R0/R1 combination in every case. All leave cells 10–15 unused. Their instructions and data are concentrated in cells 0–9; the two largest classes have instruction locations `[0,1,3,4,5,6,7,9]` or `[0,2,3,4,5,6,7,9]`, with print data in the other low cell. The six singletons use instructions at `[0,1,2,3,4,5,6,7,9]` and data at `[2,4,5,8]`.

The 16 six-winner patterns share a print operand `x` at the indicated PRINT instruction, where `x` ranges over 10–15. That preserves two characters per print and therefore preserves the 482-character score, while changing the emitted text. The loop/control structure also varies: patterns include ADD/SUB updates to R0, increments or decrements of either register, and JZ/JNZ loop tests. In the six singleton patterns, the output operand is fixed as part of the control-flow arrangement, including JMP/JZ/JNZ alternatives. Their patterns cannot be merged with the 16 six-winner classes merely because the scores agree.

The displayed `AnyOf` print class is a useful way to describe a score-preserving output-value family, but it does not make the outputs textually identical. Any search pruning based on this grouping needs validation that it preserves the target objective and the relevant control-flow behavior; matching the character count alone is insufficient if exact output text or pattern identity matters.

## Winners grouped by generalized pattern

Notation `x ∈ {10, 11, 12, 13, 14, 15}` below explicitly denotes the six listed winner vectors for that pattern, with the same `x` substituted in the program. Every vector is an eight-nibble candidate, followed by implicit zero padding to 16 cells. Opcode names follow `InstructionSet.txt`: ADD=1, SUB=2, INC_R0=3, INC_R1=4, DEC_R0=5, DEC_R1=6, PRINT=8, JMP=13, JZ=14, JNZ=15, HALT=0.

### Six-winner patterns

Each row is one exact `generalize` pattern. The `x` in each vector occupies the PRINT operand and is generalized as `Double-char output (10-15)`.

| Pattern | Winner vectors |
|---:|---|
| 1 | `[1,8,x,14,4,2,4,15]`, x=10,11,12,13,14,15 |
| 2 | `[1,8,x,14,4,2,6,15]`, x=10,11,12,13,14,15 |
| 3 | `[1,8,x,15,4,2,3,15]`, x=10,11,12,13,14,15 |
| 4 | `[1,8,x,15,4,3,2,15]`, x=10,11,12,13,14,15 |
| 11 | `[2,8,x,14,4,1,4,15]`, x=10,11,12,13,14,15 |
| 12 | `[2,8,x,14,4,1,6,15]`, x=10,11,12,13,14,15 |
| 13 | `[2,8,x,15,4,1,5,15]`, x=10,11,12,13,14,15 |
| 14 | `[2,8,x,15,4,5,1,15]`, x=10,11,12,13,14,15 |
| 15 | `[8,x,1,14,4,2,4,15]`, x=10,11,12,13,14,15 |
| 16 | `[8,x,1,14,4,2,6,15]`, x=10,11,12,13,14,15 |
| 17 | `[8,x,1,15,4,2,3,15]`, x=10,11,12,13,14,15 |
| 18 | `[8,x,1,15,4,3,2,15]`, x=10,11,12,13,14,15 |
| 19 | `[8,x,2,14,4,1,4,15]`, x=10,11,12,13,14,15 |
| 20 | `[8,x,2,14,4,1,6,15]`, x=10,11,12,13,14,15 |
| 21 | `[8,x,2,15,4,1,5,15]`, x=10,11,12,13,14,15 |
| 22 | `[8,x,2,15,4,5,1,15]`, x=10,11,12,13,14,15 |

### Singleton patterns

Each vector below forms its own distinct generalized pattern:

- Pattern 5: `[1,14,4,8,13,2,4,15]`
- Pattern 6: `[1,14,4,8,13,2,6,15]`
- Pattern 7: `[1,14,4,8,14,2,4,15]`
- Pattern 8: `[1,14,4,8,14,2,6,15]`
- Pattern 9: `[1,15,4,8,13,2,3,15]`
- Pattern 10: `[1,15,4,8,15,2,3,15]`

## Relationship to lengths 1–7

The earlier exhaustive results in [optimal-programs-length-1-to-7.md](../optimal-programs-length-1-to-7.md) show a sharp increase in the best score from 172 characters at length 7 to 482 at length 8. The length-8 winners still follow the same broad pattern of using short loops and 4-bit register state to repeat output, but their 8-cell layouts support more involved counter updates and conditional paths. This comparison describes the observed winners; it does not establish a general growth rule for longer lengths.
