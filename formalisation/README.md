# 4917 formalisation (Lean 4)

This is the starting point for proving termination properties of the 4917
processor. It includes an executable Lean model of the machine and a first
abstract control-flow lemma.

`Formalisation/Machine.lean` models a complete machine state (16 memory cells,
two registers, and the PC), one instruction step, and execution for a bounded
number of steps. It includes arithmetic modulo 16, PC wrapping, operand reads,
loads and stores, conditional and unconditional jumps, output events, and HALT.
`initialState` loads a list of nibbles into zero-padded memory. Output is kept as
events because it does not affect future machine state or termination.

`Formalisation/PC.lean` proves a small abstract lemma: a path made entirely of
strictly increasing PC transitions cannot return to an earlier PC
(`no_forward_cycle`). The machine model also proves `zeroOpcodeHalts`, which
connects opcode 0 in the concrete step function to its HALT result, and
`runFuel_zeroOpcode_halts`, which proves fuel-bounded execution stops
immediately when the current opcode is HALT.

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

The project uses Lean's standard library only; Mathlib is not needed for this
first lemma.

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
