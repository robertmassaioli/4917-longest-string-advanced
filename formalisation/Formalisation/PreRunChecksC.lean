import Formalisation.PreRunChecksB

/-! Executable finite checker for supplied static PC score certificates. -/
namespace Formalisation.PreRunChecksC

open Formalisation.PreRunChecksB

private def allCellsPreserved (before after : Memory) : Bool :=
  (List.finRange 16).all fun cell => decide (after cell = before cell)

private def checkState (memory : Memory) (allowed : PC → Bool)
    (budget : PC → Nat) (s : MachineState) : Bool :=
  let result := step s
  if result.halted then true else
    allCellsPreserved memory result.state.memory &&
    allowed result.state.pc &&
    decide (stepOutputCharacterScore result + budget result.state.pc ≤ budget s.pc)

/-- Evaluate the complete finite `StaticPCBudget` obligation for a concrete
program and proposed PC/budget functions. The check enumerates all PCs,
register pairs, and memory cells. -/
def verifyStaticPCBudget (program : List Nibble) (allowed : PC → Bool)
    (budget : PC → Nat) : Bool :=
  let memory := (initialState program).memory
  (List.finRange 16).all fun pc =>
    (List.finRange 16).all fun r0 =>
      (List.finRange 16).all fun r1 =>
        if allowed pc then checkState memory allowed budget ⟨memory, r0, r1, pc⟩
        else true

private theorem all_finRange_true {p : PC → Bool}
    (h : (List.finRange 16).all p = true) (pc : PC) : p pc = true := by
  exact (List.all_eq_true.mp h) pc (List.mem_finRange pc)

/-- A successful executable check yields the certificate proposition required
by the semantic score-bound theorem. -/
theorem verifyStaticPCBudget_sound (program : List Nibble)
    (allowed : PC → Bool) (budget : PC → Nat)
    (h : verifyStaticPCBudget program allowed budget = true) :
    StaticPCBudget (initialState program).memory allowed budget := by
  intro pc r0 r1 ha
  simp only [verifyStaticPCBudget] at h
  have hp := all_finRange_true h pc
  have hr0 := all_finRange_true hp r0
  have hr1 := all_finRange_true hr0 r1
  simp only [ha, ↓reduceIte] at hr1
  let memory := (initialState program).memory
  let s : MachineState := ⟨memory, r0, r1, pc⟩
  change (step s).halted = false →
    (∀ cell, (step s).state.memory cell = memory cell) ∧
      allowed (step s).state.pc = true ∧
      stepOutputCharacterScore (step s) + budget (step s).state.pc ≤ budget pc
  intro hNotHalted
  have hParts : (allCellsPreserved memory (step s).state.memory = true ∧
      allowed (step s).state.pc = true) ∧
      stepOutputCharacterScore (step s) + budget (step s).state.pc ≤ budget pc := by
    simpa [checkState, s, memory, hNotHalted] using hr1
  have hMemBool := hParts.1.1
  have hMem : ∀ cell, (step s).state.memory cell = memory cell := by
    intro cell
    exact of_decide_eq_true
      ((List.all_eq_true.mp hMemBool) cell (List.mem_finRange cell))
  exact ⟨hMem, hParts.1.2, hParts.2⟩

/-- If the supplied certificate verifies, every concrete halting execution
from reset has score at most the budget assigned to its initial PC. -/
theorem verified_budget_bounds_run (program : List Nibble)
    (allowed : PC → Bool) (budget : PC → Nat)
    (hCheck : verifyStaticPCBudget program allowed budget = true)
    (hEntry : allowed 0 = true)
    {states score}
    (run : FiniteRun (initialState program) states score) :
    score ≤ budget 0 := by
  have hBound := staticPCBudget_bound
    (verifyStaticPCBudget_sound program allowed budget hCheck) rfl hEntry run
  simpa [initialState] using hBound

/-- The finite sample from checks 6–9 is accepted by the executable checker. -/
theorem sample_checker_accepts :
    verifyStaticPCBudget [8, 10, 0]
      (fun pc => pc == 0 || pc == 2)
      (fun pc => if pc = 0 then 2 else 0) = true := by
  decide

/-- A wrong budget is rejected: the one OUTPUT instruction needs two
characters, so a proposed budget of one cannot certify the sample. -/
theorem sample_checker_rejects_too_small_budget :
    verifyStaticPCBudget [8, 10, 0]
      (fun pc => pc == 0 || pc == 2)
      (fun pc => if pc = 0 then 1 else 0) = false := by
  decide

end Formalisation.PreRunChecksC
