# What the maximum-output programs share across lengths 1–8

The eight per-length explainers record every tied winner and its pattern from the `generalize` command. This overview compares those groups and summarizes how the winning strategy changes as the program budget grows.

## Exhaustive results

Each candidate is a sequence of nibbles (values 0–15) loaded at the start of a 16-cell memory and zero-padded to cell 15. A candidate scores only if it halts; its score is the number of decimal characters it prints. Pattern counts below mean distinct generalized patterns emitted for the winners at that length.

| Program length | Candidates searched | Maximum characters | Tied winners | Winner patterns |
|---:|---:|---:|---:|---:|
| 1 | 16 | 1 | 1 | 1 |
| 2 | 256 | 2 | 6 | 1 |
| 3 | 4,096 | 3 | 6 | 1 |
| 4 | 65,536 | 32 | 24 | 4 |
| 5 | 1,048,576 | 62 | 72 | 12 |
| 6 | 16,777,216 | 93 | 2 | 2 |
| 7 | 268,435,456 | 172 | 26 | 6 |
| 8 | 4,294,967,296 | 482 | 102 | 22 |
| **Total** | — | — | **239** | **49** |

The exhaustive candidate and halt/cycle counts for lengths 1–7 are recorded in [`optimal-programs-length-1-to-7.md`](../optimal-programs-length-1-to-7.md). Length 8 was enumerated over all 4,294,967,296 candidates: 3,858,727,572 halted, 436,239,724 cycled, none errored, and the maximum was 482 characters. Every winner in each length was then run through `generalize`; the per-length explainers contain the complete winner vectors and groupings: [1](length-1.md), [2](length-2.md), [3](length-3.md), [4](length-4.md), [5](length-5.md), [6](length-6.md), [7](length-7.md), and [8](length-8.md).

## Similarities across the winners

### Repetition is the source of the large scores

Lengths 1–3 are straight-line programs: they print one or two values and reach a zero-padded halt. From length 4 onward, every maximum uses a loop. Short programs encode a compact output instruction, arithmetic on four-bit registers, and a conditional jump. The loop repeats the print enough times to turn a small code footprint into a much larger character count.

The printed operands 10–15 recur because each emits two decimal characters. Where `generalize` groups those values as `AnyOf`, it identifies score-preserving alternatives: the character count is unchanged, but the output text differs. In the length-3 pattern, the second print operand generalizes to 0–9 because that final print contributes one character.

### Arithmetic and branch behavior shape the loop

The loop families use the machine's small register state and wraparound arithmetic to determine when execution exits. Increment/decrement choices, ADD/SUB choices, and instruction ordering often produce different patterns with the same score. For example, length 4 has four patterns from the two counter directions crossed with print-before-update versus update-before-print; length 5 has 12 patterns from three layouts crossed with two R1 directions and two accumulator operations.

### Unreached memory is commonly wildcarded

Every program executes in 16-cell memory, even when the candidate is shorter. Padding supplies useful zero operands and halt instructions near the candidate, while cells beyond the observed path are often reported as unused and wildcarded. This is a fact about the recorded execution trace; arbitrary wildcard substitutions still need validation before they can safely guide pruning.

## How the solution families change with length

- **Lengths 1–3: direct printing.** Length 1 prints the padded zero. Length 2 prints a two-digit literal. Length 3 prints a two-digit literal followed by the padded zero. Their 1, 1, and 1 patterns respectively differ only by operand choices within the generalized digit-width classes.
- **Lengths 4–5: compact accumulator loops.** Length 4 loops 16 times and prints one two-digit value per iteration for 32 characters. Length 5 runs 31 iterations and prints one two-digit value each time for 62 characters. Its 72 winners form 12 patterns, with six possible print values per pattern.
- **Length 6: a two-value loop with few ties.** Both winners run for 31 passes and emit `8` and `13` each pass, for 93 characters. They share the same layout and differ only in whether R1 increments or decrements, yielding two patterns and two winners rather than a six-way print-operand family.
- **Length 7: more branch layouts.** The 26 winners produce 172 characters each and occupy six patterns: four six-winner families parameterized by a two-digit print value, plus two distinct singleton branch arrangements. Some cells serve both as instruction locations and as branch operands, making the compact layouts less like a simple linear instruction stream.
- **Length 8: the largest observed jump.** The 102 winners reach 482 characters in 22 patterns: 16 six-winner families that vary a two-digit print operand, plus six singleton patterns. The code uses more involved combinations of register updates and conditional paths. This is an observed result for the exhaustive length-8 domain, not evidence of a smooth growth law for longer programs.

## What the pattern groups teach us

The generalized patterns separate two kinds of variation. In the large six-member groups, one print operand changes among 10–15 while the control flow stays fixed; this creates multiple winning programs with the same score but different output text. Other pattern differences change the loop itself: operation order, ADD versus SUB, register direction, jump choice, or branch layout. Those are distinct program behaviors that happen to reach the same maximum score.

The compact loop families also show why instruction count alone is a poor predictor of output score. Adding a nibble can enable a different recurrence or branch arrangement, which can greatly extend the number of prints before halting. The increase from 172 characters at length 7 to 482 at length 8 is particularly sharp. The winning patterns suggest candidate structures to investigate, but they do not establish a general recurrence for future lengths.

Finally, `generalize` describes observed execution usage and score-relevant operand classes; it does not prove that every combination of wildcard cells preserves halting or optimality. Use these patterns to explain and organize known winners. Validate them against the actual execution and scoring rules before using them to discard candidates from a search.
