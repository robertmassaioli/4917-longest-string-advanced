# 4917 formalisation (Lean 4)

This is the starting point for proving termination properties of the 4917
processor. It currently proves a small control-flow lemma: a path made entirely
of strictly increasing program-counter transitions cannot return to an earlier
PC (`no_forward_cycle` in `Formalisation.lean`).

That is not yet the complete claim about programs of length at most 15. The
processor model still needs to account for instruction decoding, conditional
jumps, operand cells, the zero padding used by the implementations, and
self-modifying stores. In particular, a condition on the original instructions
alone may not be enough if a store can create a new backward jump. The next
proof steps are to formalise the machine state and one-step semantics, state a
precise forward-control-flow condition, prove that it is preserved during
execution, and then use the padding at lengths up to 15 to establish halting.

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
lake env lean Formalisation.lean  # Check this file directly in the project environment
```
