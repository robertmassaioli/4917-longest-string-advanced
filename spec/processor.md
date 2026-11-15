# 4917 processor contract

## Valid machine state

The machine has 16 memory cells, registers `R0` and `R1`, and a program counter
(`PC`). Each is a four-bit value in `[0, 15]`. A state also records the
cumulative number of decimal output characters; this value does not affect
instructions. Programs contain 1–16 nibble values and are zero-padded to 16
cells by the C loader. Invalid lengths, non-decimal CSV, and values outside
`[0, 15]` are rejected before the core is entered.

`step` executes exactly one instruction. PC and operand addresses wrap modulo
16. Opcodes 1–6 perform nibble arithmetic: ADD, SUB, INC R0, INC R1, DEC R0,
DEC R1. Opcode 7 is NOP and opcode 0 is HALT. Opcodes 8–12 consume the next
cell as an operand and advance PC by two: OUTPUT emits the operand value;
LOAD R0/R1 loads from the memory address in the operand cell; STORE R0/R1
writes the selected register to that address. The operand and target address
are read from pre-step memory before a store. Opcodes 13–15 read the next cell
and jump to it: JMP, JZ R0, JNZ R0. A not-taken conditional branch advances by
two. HALT advances PC by one and marks only that step complete; state has no
persistent halted bit. Output values 0–9 add one character and 10–15 add two.

## Execution policies

Bounded execution starts from reset registers, PC, and output count, executes
at most the requested number of instructions, and counts HALT as an executed
instruction. HALT on the final allowed step is completion; a zero limit executes
nothing and is limited even if cell zero is HALT. The limit takes precedence
over cycle classification when reached: bounded execution does not detect
cycles. A limit result is unresolved, never proof of an infinite run.

Cycle detection uses the full 16-cell memory, both registers, and PC as its
identity, excluding output count. Self-modification therefore changes identity.
This contract classifies cycles, but does not define a canonical partial output
prefix for cycles. Floyd's detector may use speculative steps, which must not
emit externally visible output. Terminating results expose emitted values,
character count, final machine state, and logical steps.

The portable C API uses `uint64_t` for output and step counts, checks overflow,
and reports an error rather than wrapping. This bounds an execution; it does
not claim every theoretically terminating program fits the bound.

## Search contract (initial C command)

`search --length N` enumerates all `16^N` vectors in lexicographic nibble order
as the first N cells, zero pads the rest, and runs each from reset. It supports
N from 1 through 4 (the exhaustive range is finite and practical). Only HALT
results are eligible; cycles and limited runs are unresolved and cannot win.
The command reports total candidates, completed candidates, unresolved
candidates, best character count, the number of winning programs, and the
first winning program in enumeration order. It labels the result exhaustive
only when no candidate is unresolved.
The small range is deliberate: this is a correctness baseline, not an
unbounded full search interface.

## Shared regression cases

`cases/*.csv` contains programs used by both implementations. In particular,
`output-loop.csv` emits while cycling, and `self-modifying-halt.csv` changes a
previously visited instruction before halting.
