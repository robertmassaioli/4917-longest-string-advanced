# 4917 formalisation (Lean 4)

This project contains an executable Lean model of the 4917 processor and
machine-checked control-flow and termination theorems.

`Formalisation/Machine.lean` models a complete machine state (16 memory cells,
two registers, and the PC), one instruction step, and execution for a bounded
number of steps. It includes arithmetic modulo 16, PC wrapping, operand reads,
loads and stores, conditional and unconditional jumps, output events, and HALT.
`initialState` loads a list of nibbles into zero-padded memory. Output is kept as
events because it does not affect future machine state or termination.

`Formalisation/PC.lean` proves an abstract lemma: a path made entirely of
strictly increasing PC transitions cannot return to an earlier PC
(`no_forward_cycle`). `Formalisation/Termination.lean` contains the concrete
linear-reachability model and proves `shortProgram_eventuallyHalts` for
programs of length at most 14 with no reachable STORE or jump opcode. The
machine module also proves `zeroOpcodeHalts` and `runFuel_zeroOpcode_halts`.
`Formalisation/Counterexamples.lean` contains the length-15 wraparound example
and its Lean-checked properties.

`Formalisation/MonotoneOutput.lean` defines finite runs using the concrete
machine `step` function and proves an accounting lemma: a run starting at PC
0 whose PC strictly increases prints at most 30 decimal characters. This
bound uses the whole 16-cell address space, so it also allows forward jumps
and stores. OUTPUT advances by two cells and emits at most two characters;
the terminal HALT may be at PC 15. A comparison theorem then rules out a
monotone run whenever a known score exceeds 30.

The exhaustive-search explainers report maxima of 32, 62, 93, 172, and 482
characters for lengths 4–8. Lean verifies that each number exceeds 30, so,
assuming those exhaustive-search maxima, no program achieving them can have
a strictly increasing PC run. The search results themselves are not yet Lean
proofs of optimality; formalizing the exhaustive maximum claims would be a
separate step.

The Lean model's `Fin 16` types enforce valid nibbles and addresses. Conformance
comparisons with Haskell therefore concern valid machine states, matching the
processor contract; Haskell's `Word8` record fields can also represent invalid
values that the Lean state type intentionally excludes.

## Haskell behavior check

`step` uses `pcAdd` for both the wrapped operand address (`PC + 1`) and the
post-instruction address (`PC + 2`). The explicit Lean boundary theorems cover
these cases:

| Lean result | Haskell regression case |
| --- | --- |
| Operand at PC 15 is cell 0; next PC is 1 | “fetches a two-byte operand from address zero when the opcode is at PC 15” |
| Operand at PC 14 is cell 15; next PC is 0 | “fetches a two-byte operand at cell 15 and wraps the next PC” |
| One-byte PC 15 increment wraps to 0 | “wraps one-byte instructions from PC 15 to PC 0” |

The Haskell `ProcessorPropertySpec` also compares `Processor.stepProgram` with
an independent list-based stepper, including every opcode at every PC and
wrapped operand addresses. Run that focused suite from `haskell-impl/`:

```sh
stack test cli4917:test:spec --test-arguments=--match=boundary
```

These are executable conformance checks against the same valid-state behavior;
they are not yet a machine-checked equivalence proof between Lean and Haskell.

The length-15 counterexample `wraparoundCounterexample` is fourteen NOPs
followed by OUTPUT. At PC 14, OUTPUT reads padded cell 15 and advances by two
modulo 16, returning to PC 0. The theorem `wraparoundCounterexample_step_at_pc14`
checks that this step is not HALT, emits zero, and wraps PC to zero.

For length at most 14, `shortProgram_eventuallyHalts` now proves the corrected
claim: if no instruction reached by a linear scan from PC 0 is a STORE or jump,
execution eventually reaches HALT. `LinearReach` advances by one for opcodes
1–7 and by two for opcodes 8–15; the safety condition rules out 11–15 at reached
positions, while operand cells skipped by opcodes 8–10 may contain any nibble.
The proof shows each non-HALT step strictly increases PC below 14, preserves
memory, and therefore cannot wrap. At PC 14 or 15 zero padding supplies HALT.
The exact number of fixed-length search vectors covered at each size is in
[`SEARCH_SPACE.md`](SEARCH_SPACE.md).

The project uses Lean's standard library only; Mathlib is not needed for this
first lemma.

## Executable static budget certificates

`Formalisation/PreRunChecksC.lean` turns the `StaticPCBudget` proof obligation
from `PreRunChecksB.lean` into a finite Boolean checker. Given a program, an
allowed-PC set, and a proposed remaining-output budget for each PC, it checks
every register pair at every admitted PC and verifies memory preservation,
successor closure, and the score inequality. The theorem
`verified_budget_bounds_run` proves that an accepted certificate bounds every
halting run from reset. The examples prove acceptance of the `[8, 10, 0]`
certificate with score bound 2 and rejection of the same certificate with an
incorrect bound of 1.

This is a checker for a supplied certificate; it does not yet generate the
allowed-PC set or budgets from arbitrary input programs. See
[`pre-run-checks-c.md`](pre-run-checks-c.md) for details and commands.

## Instruction reordering

`Formalisation/InstructionCommutation.lean` gives an exact result for the
one-byte, silent register instructions (opcodes 1–7). Of their 49 ordered
pairs, precisely four fail to commute for all register values: ADD or SUB on
R0 paired with INC or DEC on R1. In every other pair, the final register values
are identical in either order. The proof exhaustively checks the 16×16
register-state space and proves that these effects match `Machine.step`.
The result does not yet classify OUTPUT, LOAD, STORE, HALT, or jump
instructions, whose output, memory, operands, and control flow introduce
additional dependencies.

## Install Lean on macOS

Lean is installed and versioned through `elan`. In Terminal, run the official
installer:

```sh
curl https://elan.lean-lang.org/elan-init.sh -sSf | sh
```

Accept the default installation option. If the current Terminal session does
not find the new commands, load elan's PATH setup:

```sh
source "$HOME/.elan/env"
```

Check the installation:

```sh
elan --version
lean --version
lake --version
```

The first project command will download Lean 4.35.0 as selected by
`lean-toolchain`:

```sh
cd /path/to/4917-longest-string-advanced/formalisation
lake build
```

To use the editor, install [Visual Studio Code](https://code.visualstudio.com/)
and its official [Lean 4 extension](https://marketplace.visualstudio.com/items?itemName=leanprover.lean4),
then open the `formalisation` folder (the folder containing `lakefile.toml`).
The extension shows Lean's messages and proof state as you edit
`Formalisation.lean`.

## Useful commands

Run these from `formalisation/`:

```sh
lake build                 # Check and build the Lean project
lake env lean Formalisation.lean  # Check the public module directly
```
