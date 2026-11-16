# Executable static budget certificate checker

`Formalisation/PreRunChecksC.lean` evaluates the finite certificate obligation
defined by `StaticPCBudget` in `PreRunChecksB.lean`.

## What the checker checks

Given a program, a Boolean predicate `allowed` over the 16 PCs, and a proposed
remaining-character budget for each PC, `verifyStaticPCBudget` enumerates all
16 PCs and all 256 register pairs at each PC. For every admitted state whose
step is not HALT, it checks:

1. every memory cell is unchanged by the step;
2. the successor PC is admitted;
3. the output cost of this instruction plus the successor budget is no greater
   than the current budget.

The memory check is important: without it, the proof could incorrectly treat
self-modifying code as fixed. The register enumeration ensures that both
outcomes of conditional branches are checked. The PC enumeration includes
operand entry and address wraparound because it calls the concrete `step`.

`verifyStaticPCBudget_sound` proves that a `true` result supplies the semantic
certificate. `verified_budget_bounds_run` then proves that every halting
execution from reset has a score no greater than the budget at PC 0, provided
the entry PC is admitted.

The checked example accepts `[8, 10, 0]` with admitted PCs 0 and 2 and budget 2
at PC 0, and rejects the same proposal with budget 1. The verifier checks a
certificate supplied by the caller; automatic construction of useful PC sets
and budgets remains future work. It is not yet integrated into the Haskell
search CLI.

## Verification

From `formalisation/`, run:

```sh
lake build
lake env lean Formalisation/PreRunChecksC.lean
```
