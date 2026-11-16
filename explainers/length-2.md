# Length-2 search: winners and pattern

## Search domain and score

The length-2 search considers all 256 ordered pairs of nibbles (values 0–15). Each pair is placed at cells 0 and 1 of a 16-cell memory, with cells 2–15 zero-padded. The score is the number of decimal characters emitted, and only programs that halt are eligible; cycles do not count.

The exhaustive results list 242 halted programs, 14 cycles, no errors, and a best score of **2 characters**, shared by **6 winners**. These counts and the winner total match the length-2 row in `optimal-programs-length-1-to-7.md`.

## Winners grouped by emitted pattern

All six winners belong to the same equivalence class, `8[101112131415]0*************`:

| Pattern | Members | Observed output |
| --- | --- | --- |
| `PRINT`, operand in 10–15, `HALT` | `8,10`; `8,11`; `8,12`; `8,13`; `8,14`; `8,15` | `10`; `11`; `12`; `13`; `14`; `15` respectively |

Each command replay halts after two steps with exactly two output characters. The PRINT operand values are grouped because each value from 10 through 15 has the same decimal digit width and therefore preserves this score. That grouping does not mean those programs emit identical text: the exact output varies with the operand.

## Execution footprint

The `generalize` report for each winner observes instruction locations **0 and 2**, operand/data location **1**, and unused locations **3–15**. Cell 2 is the zero-padded HALT reached after PRINT advances execution. The reports mark **R0 not consumed** and **R1 not consumed**; neither register is needed for this straight-line output.

The shared behavior is a single PRINT of the value stored at cell 1, followed immediately by HALT. The winners differ only in that printed value. The generalized pattern is a hypothesis derived from these individual executions: it records the same-width operand group and unused memory suggested by the traces, but it does not prove that arbitrary substitutions or combinations of wildcard values will preserve behavior in every context.

## Interpretation

At length 2, the strongest output comes from using the first nibble as PRINT and the second as its literal data. Values 10–15 are the only one-instruction operands here that emit two decimal characters, and the zero padding supplies a halt immediately after that instruction. No register setup, branching, or additional output is needed to reach the exhaustive maximum.
