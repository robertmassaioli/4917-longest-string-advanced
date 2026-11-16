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

The full claim—programs of length at most 15 satisfying the intended
forward-control-flow condition will halt—remains unproved. The next steps are
to define that condition for the concrete machine, account for self-modifying
stores, and connect zero-padding to eventual HALT. A condition on original
instruction cells alone may not suffice if a store changes a future opcode.

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
