import Formalisation.R1Consumption

/-!
# Erasing R1 operations when R1 is never consumed

Erasure here preserves instruction addresses and PC advances: an R1-affecting
instruction has its data effect neutralized, while retaining its one- or
two-byte advance. This avoids changing the program layout by physically
deleting bytes.
-/

namespace Formalisation.R1Erasure

open Formalisation.R1Consumption

private theorem nibble_val_cases (x : Nibble) :
    x.val = 0 ∨ x.val = 1 ∨ x.val = 2 ∨ x.val = 3 ∨
    x.val = 4 ∨ x.val = 5 ∨ x.val = 6 ∨ x.val = 7 ∨
    x.val = 8 ∨ x.val = 9 ∨ x.val = 10 ∨ x.val = 11 ∨
    x.val = 12 ∨ x.val = 13 ∨ x.val = 14 ∨ x.val = 15 := by
  have h := x.isLt
  omega

/-- Neutralize the data effects of ADD, SUB, INC R1, DEC R1, LOAD R1, and
STORE R1, but retain the original PC advance and output/halt event. -/
def stepWithoutR1DataEffect (state : MachineState) : StepResult :=
  match currentOpcode state with
  | 1 | 2 | 4 | 6 =>
      ⟨{ state with pc := pcAdd state.pc 1 }, false, none⟩
  | 10 | 12 =>
      ⟨{ state with pc := pcAdd state.pc 2 }, false, none⟩
  | _ => step state

/-- The paired executions have the same memory and PC. Before any ADD/SUB,
they also have the same R0; once a combination exists, R0 may differ as long
as the audit has not observed a consuming operation. -/
def Related (original erased : MachineState) (audit : Audit) : Prop :=
  original.memory = erased.memory ∧
  original.pc = erased.pc ∧
  (audit.combinationSeen = false → original.r0 = erased.r0) ∧
  audit.r1Consumed = false

/-- If observing this instruction does not mark R1 consumed, the real and
neutralized steps preserve the execution relation and agree on output/halt. -/
theorem step_preserves_relation_when_not_consumed
    (original erased : MachineState) (audit : Audit)
    (hRelated : Related original erased audit)
    (hNextClean : (observeOpcode audit (currentOpcode original)).r1Consumed = false) :
    (step original).output = (stepWithoutR1DataEffect erased).output ∧
    (step original).halted = (stepWithoutR1DataEffect erased).halted ∧
    Related (step original).state
      (stepWithoutR1DataEffect erased).state
      (observeOpcode audit (currentOpcode original)) := by
  rcases hRelated with ⟨hMemory, hPC, hR0, hClean⟩
  cases original with
  | mk om o0 o1 op =>
    cases erased with
    | mk em e0 e1 ep =>
      cases hMemory
      cases hPC
      have hCases := nibble_val_cases (om op)
      rcases hCases with h | h | h | h | h | h | h | h | h | h | h | h | h | h | h | h
      all_goals
        cases hCombination : audit.combinationSeen <;>
          simp_all [step, stepWithoutR1DataEffect, currentOpcode, observeOpcode,
            isAddOrSub, consumesR0, consumesR1Directly, Related]

/-- The emitted values in a bounded execution, stopping at HALT. -/
def outputTraceFuel (nextStep : MachineState → StepResult) : Nat → MachineState → List Nibble
  | 0, _ => []
  | fuel + 1, state =>
      let result := nextStep state
      match result.output with
      | none => if result.halted then [] else outputTraceFuel nextStep fuel result.state
      | some value =>
          value :: if result.halted then [] else outputTraceFuel nextStep fuel result.state

/-- Once the audit says R1 was consumed, later steps cannot unset that flag. -/
theorem runAuditFuel_preserves_consumed
    (fuel : Nat) (state : MachineState) (audit : Audit)
    (hConsumed : audit.r1Consumed = true) :
    (runAuditFuel fuel state audit).r1Consumed = true := by
  induction fuel generalizing state audit with
  | zero => exact hConsumed
  | succ fuel ih =>
      by_cases hHalted : (step state).halted = true
      · simp [runAuditFuel, hHalted, observeOpcode, hConsumed]
      · simp [runAuditFuel, hHalted, observeOpcode, hConsumed, ih]

/-- If the consumption audit remains false over the executed prefix, replacing
R1 data effects by address-preserving no-ops leaves the emitted output intact. -/
theorem outputTraceFuel_r1_erasure_aux
    (fuel : Nat) (original erased : MachineState) (audit : Audit)
    (hRelated : Related original erased audit)
    (hAuditClean : (runAuditFuel fuel original audit).r1Consumed = false) :
    outputTraceFuel step fuel original =
      outputTraceFuel stepWithoutR1DataEffect fuel erased := by
  induction fuel generalizing original erased audit with
  | zero => rfl
  | succ fuel ih =>
      let audit' := observeOpcode audit (currentOpcode original)
      let originalResult := step original
      have hAuditStep : audit'.r1Consumed = false := by
        cases hNow : audit'.r1Consumed with
        | false => rfl
        | true =>
            by_cases hHalted : originalResult.halted = true
            · simp [runAuditFuel, audit', originalResult, hHalted, hNow] at hAuditClean
            · have hTail := runAuditFuel_preserves_consumed
                fuel originalResult.state audit' hNow
              have hTailClean :
                  (runAuditFuel fuel originalResult.state audit').r1Consumed = false := by
                simpa [runAuditFuel, audit', originalResult, hHalted] using hAuditClean
              rw [hTailClean] at hTail
              contradiction
      have hSimulation := step_preserves_relation_when_not_consumed
        original erased audit hRelated hAuditStep
      rcases hSimulation with ⟨hOutput, hHalted, hRelatedNext⟩
      simp only [outputTraceFuel]
      rw [hOutput, hHalted]
      by_cases hStop : (stepWithoutR1DataEffect erased).halted = true
      · cases hValue : (stepWithoutR1DataEffect erased).output <;>
          simp [hStop]
      · have hTailClean :
            (runAuditFuel fuel originalResult.state audit').r1Consumed = false := by
          simpa [runAuditFuel, audit', originalResult, hHalted, hStop] using hAuditClean
        have hTailEq := ih originalResult.state (stepWithoutR1DataEffect erased).state
          audit' hRelatedNext hTailClean
        cases hValue : (stepWithoutR1DataEffect erased).output with
        | none =>
            simp only [hStop, Bool.false_eq_true, ite_false]
            exact hTailEq
        | some value =>
            simp only [hStop, Bool.false_eq_true, ite_false]
            exact congrArg (List.cons value) hTailEq

/-- Starting both executions from the same state, if R1 is never consumed,
neutralizing all its instructions preserves the complete emitted output trace. -/
theorem outputTraceFuel_r1_erasure
    (fuel : Nat) (state : MachineState)
    (hAuditClean : (runAuditFuel fuel state {}).r1Consumed = false) :
    outputTraceFuel step fuel state =
      outputTraceFuel stepWithoutR1DataEffect fuel state := by
  apply outputTraceFuel_r1_erasure_aux fuel state state {}
  · simp [Related]
  · exact hAuditClean

end Formalisation.R1Erasure
