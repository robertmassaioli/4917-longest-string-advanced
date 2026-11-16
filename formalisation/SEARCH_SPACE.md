# Search space eliminated by the length-14 termination theorem

`Formalisation.Termination.shortProgram_eventuallyHalts` proves that a program
of length at most 14 eventually halts when every instruction reached by the
linear scan from PC 0 is HALT or an opcode from 1 through 10. Thus, when
searching for non-halting programs, those programs can be omitted.

This count treats a length-`n` program as an exact vector of `n` nibbles, so
the raw search space has `16^n` candidates. Vectors with trailing zeroes are
counted separately, as in a fixed-length vector search. The table counts
exactly the programs satisfying the theorem's precondition; operands skipped
by two-byte instructions may be any nibble, and cells after an executed HALT
may also be arbitrary.

## Counting recurrence

Let `C(n)` be the number of length-`n` vectors satisfying the theorem's
precondition. The empty suffix has `C(0) = 1`. For `n ≥ 1`, inspect the first
reached instruction:

- Opcode 0 halts immediately; the remaining `n - 1` cells are arbitrary:
  `16^(n - 1)` choices.
- Opcodes 1–7 consume one cell and leave a safe suffix: `7 C(n - 1)` choices.
- Opcodes 8–10 consume an opcode and an operand. For `n ≥ 2`, the operand is
  arbitrary and the remaining suffix must be safe: `3 × 16 × C(n - 2)` choices.
  For `n = 1`, the operand is the padded zero, giving 3 choices.

Therefore:

```text
C(0) = 1
C(1) = 1 + 7 C(0) + 3 = 11
C(n) = 16^(n - 1) + 7 C(n - 1) + 48 C(n - 2),  n ≥ 2
```

## Results by program length

“Proved halting” is the portion eliminated from a search specifically looking
for non-halting programs. “Remaining” is the number not covered by this
theorem; it does not mean those programs fail to halt.

| Length | Total vectors | Proved halting | Search space removed | Remaining candidates |
|---:|---:|---:|---:|---:|
| 1 | 16 | 11 | 68.75% | 5 |
| 2 | 256 | 141 | 55.08% | 115 |
| 3 | 4,096 | 1,771 | 43.24% | 2,325 |
| 4 | 65,536 | 23,261 | 35.49% | 42,275 |
| 5 | 1,048,576 | 313,371 | 29.89% | 735,205 |
| 6 | 16,777,216 | 4,358,701 | 25.98% | 12,418,515 |
| 7 | 268,435,456 | 62,329,931 | 23.22% | 206,105,525 |
| 8 | 4,294,967,296 | 913,962,621 | 21.28% | 3,381,004,675 |
| 9 | 68,719,476,736 | 13,684,542,331 | 19.91% | 55,034,944,405 |
| 10 | 1,099,511,627,776 | 208,381,478,861 | 18.95% | 891,130,148,915 |
| 11 | 17,592,186,044,416 | 3,215,040,011,691 | 18.28% | 14,377,146,032,725 |
| 12 | 281,474,976,710,656 | 50,099,777,111,581 | 17.80% | 231,375,199,599,075 |
| 13 | 4,503,599,627,370,496 | 786,495,337,052,891 | 17.46% | 3,717,104,290,317,605 |
| 14 | 72,057,594,037,927,936 | 12,413,856,288,096,621 | 17.23% | 59,643,737,749,831,315 |
| 15 | 1,152,921,504,606,846,976 | 0 | 0% | 1,152,921,504,606,846,976 |
| 16 | 18,446,744,073,709,551,616 | 0 | 0% | 18,446,744,073,709,551,616 |

Lengths 15 and 16 are outside the theorem's bound, so the theorem rules out
none of their candidates. The known length-15 wraparound example demonstrates
why the bound cannot simply be extended to 15 under the same argument.

## Interpretation

The fraction proved halting decreases with length: the theorem removes about
68.75% of length-1 vectors and about 17.23% of length-14 vectors. Longer
programs have more ways to contain an executed storage or jump opcode, so this
particular theorem covers a smaller share of the raw search space. The
remaining candidates may still halt; they are simply outside this proof's
precondition.
