import Formalisation.R1Erasure

/-!
# Removing NOPs

This file separates ordinary sequential instruction lists from the machine's
byte-addressed program image. NOP deletion is semantics-preserving for a
sequential instruction list, but it is not generally semantics-preserving for
bytecode whose jumps and memory operands contain absolute addresses.
-/

namespace Formalisation.NopRemoval

open Formalisation.R1Erasure

/-- A sequential command either does nothing or applies an effect that may
update abstract state and emit output. -/
inductive LinearCommand (State Output : Type) where
  | nop : LinearCommand State Output
  | effect : (State → State × List Output) → LinearCommand State Output

/-- Execute a sequential command list from left to right, concatenating output
in execution order. -/
def runLinear {State Output : Type} : List (LinearCommand State Output) →
    State → State × List Output
  | [], state => (state, [])
  | .nop :: rest, state => runLinear rest state
  | .effect action :: rest, state =>
      let (nextState, emitted) := action state
      let (finalState, laterOutput) := runLinear rest nextState
      (finalState, emitted ++ laterOutput)

/-- Delete NOP entries from a sequential command list. -/
def eraseLinearNops {State Output : Type} :
    List (LinearCommand State Output) → List (LinearCommand State Output)
  | [] => []
  | .nop :: rest => eraseLinearNops rest
  | .effect action :: rest => .effect action :: eraseLinearNops rest

/-- In a sequential instruction model, removing NOP commands preserves both
the final state and the emitted output. -/
theorem runLinear_eraseNops {State Output : Type}
    (commands : List (LinearCommand State Output)) (initial : State) :
    runLinear commands initial = runLinear (eraseLinearNops commands) initial := by
  induction commands generalizing initial with
  | nil => rfl
  | cons command rest ih =>
      cases command with
      | nop => exact ih initial
      | effect action =>
          simp only [runLinear, eraseLinearNops]
          rw [ih (action initial).1]

/-- Executing opcode 7 on the concrete machine emits nothing, does not halt,
and changes only the PC by advancing it once. -/
theorem machine_nop_step (state : MachineState)
    (hOpcode : (state.memory state.pc).val = 7) :
    (step state).output = none ∧
    (step state).halted = false ∧
    (step state).state = { state with pc := pcAdd state.pc 1 } := by
  simp [step, hOpcode]

/-- A concrete NOP removal that is safe in straight-line code: deleting the
leading NOP from `NOP; OUTPUT 5; HALT` preserves the output trace. -/
theorem leading_nop_straight_line_example :
    outputTraceFuel step 4 (initialState ([7, 8, 5, 0] : List Nibble)) =
      outputTraceFuel step 4 (initialState ([8, 5, 0] : List Nibble)) := by
  decide

/-- Absolute jump targets are byte positions. Deleting a NOP before the target
without relocating the jump changes this program's output. -/
theorem deleting_nop_breaks_absolute_jump_example :
    outputTraceFuel step 4
        (initialState ([13, 5, 7, 7, 7, 8, 9, 0] : List Nibble)) = [9] ∧
    outputTraceFuel step 4
        (initialState ([13, 5, 7, 7, 8, 9, 0] : List Nibble)) = [] := by
  decide

/-- The same byte deletion can change an operand even without a jump: deleting
the NOP used as OUTPUT's literal operand changes the emitted value. This is why
deletion must target decoded NOP instructions, not bytes equal to 7. -/
theorem deleting_nop_byte_from_operand_changes_output :
    outputTraceFuel step 3 (initialState ([8, 7, 0] : List Nibble)) = [7] ∧
    outputTraceFuel step 3 (initialState ([8, 0] : List Nibble)) = [0] := by
  decide

end Formalisation.NopRemoval
