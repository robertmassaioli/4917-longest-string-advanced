# Length-15 best-known output program

## Result

This 15-nibble program is tied for the best length-15 candidate found in the
local exploration recorded here. It changes the fixed PRINT operand from 10
to 15 in the earlier candidate:

```text
Address:  0  1  2   3   4  5  6   7  8  9   10 11 12 13 14
Program: [1, 8, 15, 14, 4, 2, 4, 15, 0, 10, 5, 5, 11, 11, 14]
```

The Haskell CLI trace confirms that it halts after **2,925 instructions**
with **962 output characters**. It prints 15 for 481 rounds, so each print
contributes two characters. The earlier variant prints 10 for those same 481
rounds and ties at 962 characters. Changing the fixed printed value from 10
to 15 does **not** make this program run longer; unlike the length-16 program,
cell 2 is not used as a changing outer-loop counter here. This is a found
candidate, not an exhaustive search result or a proof of the maximum for
length 15.

From `haskell-impl/`, run:

```sh
stack run -- trace --program 1,8,10,14,4,2,4,15,0,10,5,5,11,11,14 --detect-loops
```

For the 15-print variant above, use loop detection instead of a step limit:

```sh
stack run -- trace --program 1,8,15,14,4,2,4,15,0,10,5,5,11,11,14 --detect-loops
```

## Haskell CLI generalization

Run the CLI's dynamic memory-usage generalizer with:

```sh
stack run -- generalize --program 1,8,15,14,4,2,4,15,0,10,5,5,11,11,14
```

It reports a halted execution in 2,925 steps with 962 output characters. The
optimized 16-cell memory pattern is:

```text
[1, 8, AnyOf(10-15), 14, 4, 2, 4, 15, 0, 10, 5, 5, 11, 11, 14, 0]
```

Every cell is required except address 2, the PRINT operand. Any value from
10 through 15 preserves two output characters per round, so the CLI finds six
members of this equivalence class. The generalizer counts a 16-cell memory
image; for the length-15 program domain, the final zero is fixed padding, and
the same six candidates sit within the `16^15` possible 15-nibble programs.

## How the storage creates a second long pass

Cells 0–8 are the same modular loop used by the length-8 winner. At the end
of its first 241-round pass, execution falls through to the handler:

1. Cell 9 loads R1 from address 5. Cell 5 contains the value 2, so R1 becomes
   2.
2. Cell 11 initially contains DEC R0. Since R0 is zero at this point, it
   wraps to 15.
3. STORE at cell 12 writes that 15 into cell 11, changing DEC R0 into JNZ.
4. JZ at cell 14 does not branch because R0 is 15. Its fall-through wraps
   from cell 16 to address 0, starting the modular loop again from
   `(R0,R1) = (15,2)`.

That second pass lasts 240 rounds and prints another 10 each time. At its
exit, R0 is zero. The self-modified JNZ at cell 11 then falls through to cell
13, which is STORE R0,[14]. It writes zero over the JZ at cell 14; execution
then reaches the zero-padded HALT at cell 15.

| Pass | Starting registers | Prints | Character score |
|---|---|---:|---:|
| Initial modular loop | `(0,0)` | 241 | 482 |
| Second modular loop | `(15,2)` | 240 | 480 |
| **Total** |  | **481** | **962** |

This candidate is shorter than the 16-nibble, 2,957-character program in
[`length-16.md`](length-16.md), but scores less. The 16-nibble program uses
memory cell 2 as a staged counter; this 15-nibble variant instead uses STORE
to modify an instruction and create one additional long pass.
