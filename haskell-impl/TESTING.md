# Haskell test suite

Run the complete suite from `haskell-impl`:

```sh
stack test
```

The Hspec/QuickCheck properties run at least 300 cases each. QuickCheck prints
the random seed when a property fails. Replay a failure with the reported seed
and an optional test-name filter:

```sh
stack test --test-arguments="--seed=807154426 --match=ProgramExecution"
```

Increase property coverage for a stress run with `--qc-max-success`; the
property specs enforce 300 as a minimum while allowing a larger command-line
value:

```sh
stack test --test-arguments="--qc-max-success=2000"
```

Generators live in `test/ProcessorTestSupport.hs`. They produce valid nibble
memory and register values, bounded programs, and instruction-focused states.
The test-only reference stepper uses list memory and direct instruction
dispatch, separate from the production vector-based implementation. Its
counterexamples include the initial state; QuickCheck's shrinkers reduce
registers, output counts, program lengths, and byte values while retaining
valid machine inputs.
