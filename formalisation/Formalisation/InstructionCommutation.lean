import Formalisation.Machine

/-!
# Commuting instruction effects

This module characterizes reordering for the one-byte, output-free register
instructions. It compares the resulting register values; swapping code bytes
also swaps their memory locations, so memory itself is not part of the
comparison. Instructions with operands, output, stores, or control flow need
additional dependency conditions and are outside this exact classification.
-/
namespace Formalisation.InstructionCommutation

/-- The straight-line instructions whose effects are limited to the two
registers. These correspond to opcodes 1–7 in `Machine.step`. -/
inductive RegisterInstruction where
  | addR0
  | subR0
  | incR0
  | incR1
  | decR0
  | decR1
  | nop
  deriving DecidableEq, Repr

abbrev Registers := Nibble × Nibble

/-- Apply only the data effect of a register instruction. The PC and memory
are intentionally omitted; each listed instruction is one byte and preserves
memory in the concrete machine. -/
def applyRegisterInstruction : RegisterInstruction → Registers → Registers
  | .addR0, (r0, r1) => (Fin.ofNat 16 (r0.val + r1.val), r1)
  | .subR0, (r0, r1) => (Fin.ofNat 16 (r0.val + 16 - r1.val), r1)
  | .incR0, (r0, r1) => (Fin.ofNat 16 (r0.val + 1), r1)
  | .incR1, (r0, r1) => (r0, Fin.ofNat 16 (r1.val + 1))
  | .decR0, (r0, r1) => (Fin.ofNat 16 (r0.val + 15), r1)
  | .decR1, (r0, r1) => (r0, Fin.ofNat 16 (r1.val + 15))
  | .nop, registers => registers

/-- The exact universal commutation property over all valid register values. -/
def Commute (first second : RegisterInstruction) : Prop :=
  ∀ registers,
    applyRegisterInstruction second (applyRegisterInstruction first registers) =
      applyRegisterInstruction first (applyRegisterInstruction second registers)

/-- An executable exhaustive checker for the finite register domain. -/
def checkCommute (first second : RegisterInstruction) : Bool :=
  (List.finRange 16).all fun r0 =>
    (List.finRange 16).all fun r1 =>
      decide (applyRegisterInstruction second
          (applyRegisterInstruction first (r0, r1)) =
        applyRegisterInstruction first
          (applyRegisterInstruction second (r0, r1)))

private theorem all_finRange_true {p : Nibble → Bool}
    (h : (List.finRange 16).all p = true) (x : Nibble) : p x = true := by
  exact (List.all_eq_true.mp h) x (List.mem_finRange x)

theorem checkCommute_iff_Commute (first second : RegisterInstruction) :
    checkCommute first second = true ↔ Commute first second := by
  constructor
  · intro h registers
    obtain ⟨r0, r1⟩ := registers
    have h0 := all_finRange_true h r0
    have h1 := all_finRange_true h0 r1
    exact of_decide_eq_true h1
  · intro h
    unfold checkCommute
    apply List.all_eq_true.mpr
    intro r0 hr0
    apply List.all_eq_true.mpr
    intro r1 hr1
    simp [h (r0, r1)]

/-- The only conflicts are between ADD/SUB on R0 and INC/DEC on R1. -/
def crossConflict (first second : RegisterInstruction) : Bool :=
  (((first == .addR0 || first == .subR0) &&
      (second == .incR1 || second == .decR1)) ||
    ((second == .addR0 || second == .subR0) &&
      (first == .incR1 || first == .decR1)))

/-- Exhaustive kernel reduction establishes the complete 7×7 table. -/
theorem checkCommute_eq_not_crossConflict (first second : RegisterInstruction) :
    checkCommute first second = !crossConflict first second := by
  cases first <;> cases second <;> decide

/-- Exact classification: two register instructions commute for every state
iff neither is a cross-conflicting R0 arithmetic / R1 update pair. -/
theorem commute_iff_no_crossConflict (first second : RegisterInstruction) :
    Commute first second ↔ crossConflict first second = false := by
  rw [← checkCommute_iff_Commute, checkCommute_eq_not_crossConflict]
  simp

/-- Concrete opcode corresponding to each abstract register instruction. -/
def opcode : RegisterInstruction → Nat
  | .addR0 => 1
  | .subR0 => 2
  | .incR0 => 3
  | .incR1 => 4
  | .decR0 => 5
  | .decR1 => 6
  | .nop => 7

/-- Every classified action is exactly the register effect of a concrete
machine step at the matching opcode. -/
theorem step_register_effect (instruction : RegisterInstruction)
    (state : MachineState)
    (hOpcode : (state.memory state.pc).val = opcode instruction) :
    (step state).state.r0 =
        (applyRegisterInstruction instruction (state.r0, state.r1)).1 ∧
      (step state).state.r1 =
        (applyRegisterInstruction instruction (state.r0, state.r1)).2 ∧
      (step state).state.memory = state.memory ∧
      (step state).state.pc = pcAdd state.pc 1 ∧
      (step state).halted = false ∧ (step state).output = none := by
  cases instruction <;> simp [opcode] at hOpcode <;>
    simp [applyRegisterInstruction, step, hOpcode]

/-- The executable table accepts all the expected commuting pairs. -/
theorem inc0_inc1_commute :
    Commute .incR0 .incR1 := by
  rw [commute_iff_no_crossConflict]
  rfl

theorem add_sub_commute :
    Commute .addR0 .subR0 := by
  rw [commute_iff_no_crossConflict]
  rfl

theorem add_inc1_do_not_commute :
    ¬ Commute .addR0 .incR1 := by
  rw [commute_iff_no_crossConflict]
  decide

end Formalisation.InstructionCommutation
