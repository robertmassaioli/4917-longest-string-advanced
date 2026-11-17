# Extending the length-8 loop with LOAD and STORE

The length-8 winner

```text
[1, 8, 10, 14, 4, 2, 4, 15]
```

prints the value at cell 2 for 241 rounds, scoring 482 characters when that
value is 10. This note records a longer program that uses a memory cell as an
additional persistent counter, plus a shorter variant found while trying to
compress it.

## A 16-cell staged countdown: 1,157 characters

```text
Address:  0  1  2   3   4  5  6   7  8  9  10 11 12 13 14 15
Program: [1, 8, 10, 14, 4, 2, 4, 15, 0, 9, 2, 5, 11, 2, 14, 2]
```

Cells 0–7 are the length-8 loop. Cell 2 is both the PRINT operand and the
outer counter. When an inner loop finishes, the added handler at cells 9–15
loads the value at cell 2 into R0, decrements it, and stores it back there.
JZ then has two outcomes:

- If the new value is nonzero, it falls through from cell 14 to address 0
  (the PC wraps after cell 15), starting another inner loop.
- When the value reaches zero, the jump goes to cell 2. Since STORE has just
  changed that cell to zero, it executes HALT.

The successive PRINT values and round counts are:

| Printed value | Rounds | Character score |
|---:|---:|---:|
| 10 | 241 | 482 |
| 9 | 135 | 135 |
| 8 | 120 | 120 |
| 7 | 105 | 105 |
| 6 | 90 | 90 |
| 5 | 75 | 75 |
| 4 | 60 | 60 |
| 3 | 45 | 45 |
| 2 | 30 | 30 |
| 1 | 15 | 15 |
| **Total** | **916** | **1,157** |

The first loop has the original initial state `(R0,R1) = (0,0)` and lasts 241
rounds. At each later restart, R0 is loaded with the decreasing counter and
R1 retains the phase value 1. The loop therefore lasts 135, 120, ..., 15
rounds. The output value also decreases, so only the first batch prints
two-character values.

I ran this program with the Haskell CLI `trace` command. It halted after
5,598 instructions with 1,157 output characters. For example:

```sh
cd haskell-impl
stack run -- trace --program 1,8,10,14,4,2,4,15,0,9,2,5,11,2,14,2 --max-steps 5598
```

## A 15-nibble variant: 962 characters

This variant is documented separately in
[`length-15.md`](length-15.md).

Removing the final operand and changing two handler nibbles gives a shorter
program with a different self-modifying continuation:

```text
Address:  0  1  2   3   4  5  6   7  8  9   10 11 12 13 14
Program: [1, 8, 10, 14, 4, 2, 4, 15, 0, 10, 5, 5, 11, 11, 14]
```

Cell 9 loads R1 from address 5, whose contents are 2. At the first exit from
the 241-round loop, cell 11 still contains DEC R0. That instruction changes
R0 from 0 to 15; STORE writes the 15 over cell 11, turning it into JNZ. The
program wraps back to address 0 and runs the loop again from `(15,2)`, which
produces 240 more prints of 10. At the second exit, the new JNZ at cell 11
falls through because R0 is zero. The instruction at cell 13 stores zero
over the JZ at cell 14, and the zero-padded cell 15 halts the machine.

The Haskell CLI trace confirms that this 15-nibble program halts after 2,925
instructions with 962 output characters:

```sh
cd haskell-impl
stack run -- trace --program 1,8,10,14,4,2,4,15,0,10,5,5,11,11,14 --max-steps 2925
```

This is a shorter program with a lower score than the 16-cell staged
countdown. It still exceeds the 482-character length-8 winner. The search
here was a small local exploration of deletions and nibble changes, not an
exhaustive search of all 15-nibble programs; it does not show that 962 is the
best score at length 15, or that 1,157 cannot be reached with fewer cells.

Changing the staged countdown's starting value from 10 to 15 gives the
2,957-character length-16 candidate recorded in
[`length-16.md`](length-16.md).
