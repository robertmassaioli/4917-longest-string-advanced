import Formalisation.Machine

/-!
# What zero opcodes justify pruning

The entry-zero rule is unconditional. A zero in cell 1 is only a local rule:
if execution fetches it while it is still zero, that instruction halts.
It does not imply that execution reaches cell 1.
-/

namespace Formalisation

/-- On reset, a zero in the first program cell halts on the first instruction.
The length condition is unnecessary: `initialState` zero-pads short lists. -/
theorem firstCellZero_halts (program : List Nibble)
    (hZero : program.getD 0 0 = 0) :
    (step (initialState program)).halted = true := by
  apply zeroOpcodeHalts
  simpa [initialState] using hZero

/-- A fetched zero at cell 1 halts immediately, provided that cell has not
been overwritten before the fetch. This is the strongest unconditional local
claim; the premise records the current memory, not just the original bytes. -/
theorem fetchedCellOneZero_halts (state : MachineState)
    (hZero : (state.memory state.pc).val = 0) :
    (step state).halted = true :=
  zeroOpcodeHalts state hZero

/-- The state reached after `n` transitions when continuing the deterministic
state component of `step`, whether or not an earlier step reported HALT. -/
def stateAfter (program : List Nibble) : Nat → MachineState
  | 0 => initialState program
  | n + 1 => (step (stateAfter program n)).state

/-- Conditional reachability result: if the execution's state sequence reaches
cell 1 and that cell is still zero at the fetch, the following instruction
halts. This does not claim the sequence reaches cell 1. -/
theorem reachingCellOneZero_halts_next (program : List Nibble) (n : Nat)
    (hPC : (stateAfter program n).pc = 1)
    (hZero : ((stateAfter program n).memory 1).val = 0) :
    (step (stateAfter program n)).halted = true := by
  apply zeroOpcodeHalts
  simpa [hPC] using hZero

/-- Example: the first instruction jumps to cell 0, skipping a zero at cell 1
forever. -/
def skipsSecondCell : List Nibble := [13, 0, 0]

theorem skipsSecondCell_hasZeroAtOne :
    (initialState skipsSecondCell).memory 1 = 0 := by
  decide

theorem skipsSecondCell_firstStep_skipsOne :
    (step (initialState skipsSecondCell)).state.pc = 0 := by
  decide

theorem skipsSecondCell_repeatsAfterFirstStep :
    (step ((step (initialState skipsSecondCell)).state)).state =
      (step (initialState skipsSecondCell)).state := by
  have hOpcode : ((initialState skipsSecondCell).memory
      (initialState skipsSecondCell).pc).val = 13 := by
    decide
  have hTarget : (initialState skipsSecondCell).memory
      (pcAdd (initialState skipsSecondCell).pc 1) =
      (initialState skipsSecondCell).pc := by
    decide
  simp [step, hOpcode, hTarget]

end Formalisation
