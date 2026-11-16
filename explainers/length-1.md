# Length-1 exhaustive search: winner and pattern

## Search domain and score

The length-1 search covers all 16 possible one-nibble programs. Each candidate is a nibble vector padded with zeroes to 16 cells, so the winner `8` is executed as `[8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]`. The score is the number of decimal characters emitted. Only programs that halt count toward the best score; cycles are ineligible.

The exhaustive results report 14 halted candidates, 2 cycled candidates, no errors, a best score of 1 character, and 1 tied winner. The winning program is:

| Winner | Program | Score | Emitted text |
|---|---|---:|---|
| 1 | `8` | 1 character | `0` |

## Generalized pattern

Running `4917-cli generalize --program 8` reports this equivalence class:

```text
8[0123456789]0*************
```

It consists of one observed execution pattern:

| Pattern | Member winner | Generalizer's locations |
|---|---|---|
| `8[0123456789]0*************` | `8` | Required instruction at 0; single-character-output operand at 1; required HALT at 2; locations 3–15 unused/wildcard |

The program's `PRINT` at location 0 reads the following cell as its operand, emits its decimal value, and advances to the zero at location 2, which halts. For the specific winner, that operand is zero, so the output is `0`.

The equivalence class groups operand values by their decimal digit width: values 0–9 retain a one-character score. This preserves the score, but the emitted text is not necessarily the same as the winner's `0`.

## Instruction, operand, unused cells, and registers

- **Instruction locations:** 0 (`PRINT`, value 8) and 2 (`HALT`, value 0).
- **Operand/data location:** 1, read by `PRINT`.
- **Unused locations:** 3–15. The generalizer marks these as wildcards.
- **Registers:** Neither R0 nor R1 is consumed by this execution; neither is reported as containing a combination of the registers.

There is only one winner, so no variation among tied winners can be compared. Its common structure is the print instruction, one decimal-character operand, then the halt. The emitted digit depends on the operand; the required zero at location 2 ends execution, while later cells are not reached.

## Interpretation and limits

At length 1, the best available behavior is a one-character print followed immediately by the padded zero halt. The generalized class identifies values that keep the observed output width at one character and locations unused by this trace. It is a pattern inferred from one execution, not proof that arbitrary wildcard substitutions in every combination preserve behavior; treat such substitutions as hypotheses requiring separate checking. Likewise, grouping print operand values by digit width preserves the character-count score, not necessarily the exact output text.
