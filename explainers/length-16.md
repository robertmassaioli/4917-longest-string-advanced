# Length-16 best-known output program

## Result

The best length-16 program found so far is:

```text
Address:  0  1  2   3   4  5  6   7  8  9  10 11 12 13 14 15
Program: [1, 8, 15, 14, 4, 2, 4, 15, 0, 9, 2, 5, 11, 2, 14, 2]
```

The Haskell CLI trace confirms that it halts after **11,078 instructions**,
prints **1,816 values**, and scores **2,957 output characters**. This is the
longest length-16 output found in this exploration. It is an observed
candidate, not a proof or exhaustive search result establishing the maximum
for length 16.

Run it from `haskell-impl/` with:

```sh
stack run -- trace --program 1,8,15,14,4,2,4,15,0,9,2,5,11,2,14,2 --max-steps 11078
```

## Haskell CLI generalization

The CLI's dynamic memory-usage generalizer reports this program as halted
after 11,078 steps with 2,957 output characters. Run it with:

```sh
stack run -- generalize --program 1,8,15,14,4,2,4,15,0,9,2,5,11,2,14,2
```

Its optimized pattern requires every cell:

```text
[1, 8, 15, 14, 4, 2, 4, 15, 0, 9, 2, 5, 11, 2, 14, 2]
```

The CLI therefore finds no generalized alternatives for this candidate: the
reported class contains one 16-nibble program, reduced from `16^16` possible
memory images. The changing output and counter values arise from the program
modifying memory while it runs; they do not make any initial nibble optional.

## How it works

Cells 0–7 are the length-8 modular loop. Cell 2 starts at 15 and acts as both
the PRINT operand and a persistent outer counter. After each inner loop ends,
the handler at cells 9–15 loads cell 2 into R0, decrements R0, and stores the
new value back into cell 2. If it is nonzero, execution wraps from cell 15 to
cell 0. When it reaches zero, JZ at cell 14 jumps to cell 2, which has become
HALT.

| Address | Instruction or data | Role |
|---:|---|---|
| 0 | `1` ADD R0,R1 | Start the inner loop's register recurrence |
| 1–2 | `8,15` OUTPUT 15 | Print the changing counter value |
| 3–4 | `14,4` JZ 4 | Take the extra R1 increment when R0 is zero |
| 4 | `4` INC R1 | Adjust the zero-hit transition |
| 5 | `2` SUB R0,R1 | Update the accumulator |
| 6 | `4` INC R1 | Advance the phase |
| 7–8 | `15,0` JNZ 0 | Return to cell 0 while R0 is nonzero |
| 9–10 | `9,2` LOAD R0,[2] | Read the current outer counter |
| 11 | `5` DEC R0 | Decrease the counter |
| 12–13 | `11,2` STORE R0,[2] | Save it over the PRINT operand |
| 14–15 | `14,2` JZ 2 | Halt through cell 2 at counter zero; otherwise wrap to 0 |

The inner-loop lengths follow a simple pattern. The first pass starts with
`(R0,R1) = (0,0)` and lasts 241 prints. After that, the handler restarts with
`R1 = 1` and R0 equal to the decremented counter. Each later stage lasts 15
times its starting R0 value:

| Printed value | Prints | Character score |
|---:|---:|---:|
| 15 | 241 | 482 |
| 14 | 210 | 420 |
| 13 | 195 | 390 |
| 12 | 180 | 360 |
| 11 | 165 | 330 |
| 10 | 150 | 300 |
| 9 | 135 | 135 |
| 8 | 120 | 120 |
| 7 | 105 | 105 |
| 6 | 90 | 90 |
| 5 | 75 | 75 |
| 4 | 60 | 60 |
| 3 | 45 | 45 |
| 2 | 30 | 30 |
| 1 | 15 | 15 |
| **Total** | **1,816** | **2,957** |

Values 10–15 contribute two characters per print; values 0–9 contribute one.
The first six stages (15 down to 10) contribute 2,282 characters, and the
remaining stages contribute 675.

The closely related 1,157-character staged countdown and a shorter
15-nibble, 962-character variant are documented in
[`storage-extended-loop.md`](storage-extended-loop.md) and
[`length-15.md`](length-15.md).
