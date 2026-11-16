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

## Additional reduction from proved instruction commutation

The results in
[`Formalisation/InstructionCommutation.lean`](Formalisation/InstructionCommutation.lean)
can remove duplicate search cases by keeping one ordering for a pair of
instructions whose effects commute. This is a different reduction from the
termination theorem above: commutation identifies equivalent orderings; it
does not show that those programs halt or cannot be solutions.

### Exact count for one-byte register instructions

The Lean classification covers the seven one-byte, silent register opcodes
(ADD R0, SUB R0, INC R0, INC R1, DEC R0, DEC R1, and NOP). There are 49
ordered two-instruction opcode sequences. Four unordered opcode pairs have
state-dependent conflicts: ADD or SUB R0 paired with INC or DEC R1. The other
17 distinct mixed pairs commute for every register state, and each of the
seven same-opcode pairs is trivially unchanged by swapping. Therefore a search
over just these two-instruction opcode sequences can reduce:

| Local search space | Before | After keeping one order | Removed |
|---|---:|---:|---:|
| Ordered pairs of the 7 register opcodes | 49 | 24 | 25 (51.02%) |

This is an exact percentage for that small opcode-pair space. It is not a
51.02% reduction of all length-`n` byte vectors: a full-program canonicalizer
would need to establish safe instruction boundaries and account for control
flow, data operands, and later entry into the reordered bytes. The Lean pair
classification compares the data effects; physically swapped code bytes mean
the two whole memories are not identical.

### Concrete two-byte examples

Lean also checks these exact layouts end to end for two instruction steps:

| Reordering | Fixed-length vectors | Proven equal after the two steps | Local reduction |
|---|---|---|---:|
| `OUTPUT 5; INC_R0` ↔ `INC_R0; OUTPUT 5` | `[8,5,3]` ↔ `[3,8,5]` (length 3) | registers, PC, and output `[5]` | 2 layouts → 1 (1 duplicate, 50%) |
| `OUTPUT 5; LOAD_R0 10` ↔ `LOAD_R0 10; OUTPUT 5` | `[8,5,9,10,0,0,0,0,0,0,7]` ↔ `[9,10,8,5,0,0,0,0,0,0,7]` (length 11) | registers, PC, and output `[5]` | 2 layouts → 1 (1 duplicate, 50%) |

The second example's cell 10 contains 7. The abstract theorems are broader:
literal OUTPUT commutes with any deterministic silent data-state update, and
LOAD R0 and LOAD R1 commute with each other for arbitrary addresses. The
concrete encoded-program reduction still requires that both instructions
execute as intended and that stores or control flow do not invalidate the
instruction bytes or operands before they are fetched.

These examples prove local duplicate elimination, not a global percentage for
all length-3 or length-11 vectors. In particular, the two length-11 layouts
are one pair among `16^11` vectors; the Lean development does not yet provide a
program-wide canonicalizer that finds every such reorderable block. Apply the
reduction only after a search tool has checked its premises. The termination
table above is unchanged and remains the measured whole-vector reduction.

## Illustrative single-core search time

The C++ implementation's recorded exhaustive length-2 search rate is 42.7
million candidates per second on macOS arm64 with a Release `-O3` build (see
[`Cpp-Implementation-Proposal.md`](../Cpp-Implementation-Proposal.md)). The
following estimates divide candidate counts by that rate. They assume every
length sustains the length-2 rate, exclude process startup, and ignore the
cost of applying a static filter. Treat them as optimistic throughput
estimates, especially for longer programs: those candidates can execute more
steps and cycle detection costs time. They are not measured full-search times.

“After theorem filter” means the candidates left after removing programs
proved to halt. That filter is useful when searching specifically for
non-halting programs. It cannot discard those programs in a longest-string
search, because a longest-string solution must halt. The raw-time column is
therefore the applicable estimate for an exhaustive longest-string search
with the current documented proofs. The commutation proofs are not included:
they are not yet integrated into a whole-program canonicalizer.

| Length | Raw candidates | After theorem filter | Raw search time | Residual non-halting search time |
|---:|---:|---:|---:|---:|
| 1 | 16 | 5 | < 1 μs | < 1 μs |
| 2 | 256 | 115 | 6 μs | 2.7 μs |
| 3 | 4,096 | 2,325 | < 0.1 ms | < 0.1 ms |
| 4 | 65,536 | 42,275 | 1.5 ms | 1.0 ms |
| 5 | 1,048,576 | 735,205 | 0.025 s | 0.017 s |
| 6 | 16,777,216 | 12,418,515 | 0.39 s | 0.29 s |
| 7 | 268,435,456 | 206,105,525 | 6.3 s | 4.8 s |
| 8 | 4,294,967,296 | 3,381,004,675 | 1.68 min | 1.32 min |
| 9 | 68,719,476,736 | 55,034,934,405 | 26.8 min | 21.5 min |
| 10 | 1,099,511,627,776 | 891,130,148,915 | 7.15 h | 5.80 h |
| 11 | 17,592,186,044,416 | 14,377,146,032,725 | 4.76 days | 3.90 days |
| 12 | 281,474,976,710,656 | 231,375,199,599,075 | 76.3 days | 62.7 days |
| 13 | 4,503,599,627,370,496 | 3,717,104,290,317,605 | 3.34 years | 2.76 years |
| 14 | 72,057,594,037,927,936 | 59,643,737,749,831,315 | 53.5 years | 44.3 years |
| 15 | 1,152,921,504,606,846,976 | 1,152,921,504,606,846,976 | 856 years | 856 years |
| 16 | 18,446,744,073,709,551,616 | 18,446,744,073,709,551,616 | 13,700 years | 13,700 years |

The CLI's documented C++ `search` command currently supports lengths 1–5;
larger rows extrapolate the benchmark rate to the full vector domains. None
of these estimates claims that the current implementation or Lean checker
has already run those larger searches.
