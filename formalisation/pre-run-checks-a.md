# Pre-run checks 1–5: Lean conclusions

All five precise rules below are proved against `Formalisation.Machine.step`
in `Formalisation/PreRunChecksA.lean`. There are no unresolved attempts in this
batch. The rules are sufficient conditions: failure to establish a condition
means **unknown**, and does not justify rejecting a candidate.

A candidate is eligible for a longest-string comparison only if it halts.
An output bound of zero rejects it only when a known halting candidate of the
same fixed-vector length has a positive score. Rejecting ties requires a
strictly larger incumbent. These proofs do not establish an incumbent or its
length, and do not assert that any reported maximum is optimal.

| Check | Conclusion | Lean declarations | Required static evidence |
|---|---|---|---|
| 1. HALT at entry | **Proved:** any positive-fuel execution halts immediately with empty output. Its score is below any positive incumbent. | `entryHalt_emptyOutput`, `emptyOutput_below_positive` | Initial cell 0 has value 0. |
| 2. No possible OUTPUT | **Proved:** any bounded execution preserves its existing output accumulator, whether it halts or runs out of fuel. | `noOutputOrStore_runFuel` | Every one of the 16 initial cells excludes values 8, 11 and 12. This deliberately conservative scan includes operands and padded cells. |
| 3. No reachable HALT | **Proved:** an initial state in an invariant with no opcode-0 states cannot eventually halt. A closed immutable PC region supplies a concrete static certificate. | `invariant_without_halt_cannot_halt`, `closedPCRegion_cannot_halt` | Initial PC belongs to the region; each region address excludes HALT and STORE; every concrete successor for every pair of nibble register values stays in the region. |
| 4. Resolve branches using register invariants | **Proved:** opcode 14 jumps exactly when R0 is zero; opcode 15 jumps exactly when R0 is nonzero. Established state invariants hold after any number of concrete steps. | `conditionalJump_outcomes`, `invariant_iterates` | Establish the register fact at the branch, through an initial invariant and a proved invariant-preserving transition. This rule alone supplies branch-edge removal, not a rejection. Compose it with a sound bound or nonhalting certificate. |
| 5. Unavoidable jump trap | **Proved:** a closed region containing only unconditional jumps cannot halt, for any register contents. In particular, an entry jump targeting itself cannot halt. | `unconditionalJumpRegion_cannot_halt`, `selfJump_cannot_halt`, `entry13zero_cannot_halt` | Every region opcode is 13 and every operand points inside the region. For a trap reached later, establish that execution reaches it through a proved transition invariant. |

The PC-region certificate is a finite pre-run obligation: there are only 16
addresses and 256 register pairs per address. It reads the exact concrete
successor PC from `step`, so operands entered as instructions, both branch
outcomes, and modulo-16 PC/operand wraparound are covered. It excludes STORE
inside the region, rather than assuming writable code remains unchanged.
The Haskell CLI does not yet construct these certificates; the Lean result
is the soundness proof a later analyser must satisfy.

`runFuel_halted_eventuallyHalts` proves that any bounded execution returning
HALT supplies an `EventuallyHalts` witness. Thus the nonhalting certificates
exclude every possible successful `runFuel` result; this is not an inference
from a timeout. `haltedOutput` explicitly returns `none` for a timeout.

## Lean-checked counterexamples to unsafe weakenings

These examples use kernel reduction (`rfl`) or decidable finite propositions
(`decide`). They are proofs in the source, rather than logged execution results.

1. **“No raw OUTPUT byte means no output” is false.**
   `manufacturesOutput` is
   `[3,3,3,3,3,3,3,3,11,10,0,10,0]`.
   It contains no 8 (`manufacturesOutput_noRaw8`). Eight INC instructions set
   R0 to 8; STORE writes it to cell 10. That new OUTPUT prints 10, then HALT
   occurs (`manufacturesOutput_prints`). Excluding STORE is essential for
   the simple byte-scan rule.
2. **“A zero anywhere means the program halts” is false.**
   `[13,0]` has a zero operand and zero padding, but PC stays at address 0.
   `rawZero_does_not_ensure_halting` proves both the raw-zero fact and
   nonhalting. Reachable instructions must be distinguished from raw cells.
3. **“No initial zero anywhere means the program cannot halt” is false.**
   `manufacturesHalt` is the full 16-cell vector
   `[11,3,7,7,7,7,7,7,7,7,7,7,7,7,7,7]`.
   `manufacturesHalt_noInitialZero` proves that all 16 initial cells are
   nonzero. STORE writes initial R0 = 0 into cell 3; after the NOP at cell 2,
   execution halts there (`manufacturesHalt_halts`). An analysis that ignores
   writable code would reject a halting program.
4. **“R0 starts at zero, so every later JZ is taken” is false.**
   `[3,14,0,8,10,0]` increments R0 before JZ. The branch falls through,
   OUTPUT prints 10, and HALT follows
   (`initialZero_does_not_fix_branches`). A register fact must be preserved
   or re-established at the branch.

These rules do not use effective program length. Examples and incumbent
comparisons retain the searcher's convention of exact supplied vectors,
including trailing zeros; machine memory is padded/truncated exactly as
`initialState` specifies.

## Verification

From `formalisation/`, run:

```sh
lake build
lake env lean Formalisation/PreRunChecksA.lean
```

The first build supplies the imported module artifacts in a fresh worktree.
The second command explicitly checks this new module, which is intentionally
not added to the shared umbrella import by this independent worktree.
