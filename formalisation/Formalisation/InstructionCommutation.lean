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

/-- Concrete counterexample for ADD_R0 followed by INC_R1 versus the reverse:
from `(0, 0)` the results are `(0, 1)` and `(1, 1)`. -/
theorem add_inc1_counterexample :
    applyRegisterInstruction .incR1
        (applyRegisterInstruction .addR0 ((0 : Nibble), 0)) ≠
      applyRegisterInstruction .addR0
        (applyRegisterInstruction .incR1 ((0 : Nibble), 0)) := by
  decide

/-- Concrete counterexample for ADD_R0 and DEC_R1, starting at `(0, 0)`. -/
theorem add_dec1_counterexample :
    applyRegisterInstruction .decR1
        (applyRegisterInstruction .addR0 ((0 : Nibble), 0)) ≠
      applyRegisterInstruction .addR0
        (applyRegisterInstruction .decR1 ((0 : Nibble), 0)) := by
  decide

/-- Concrete counterexample for SUB_R0 and INC_R1, starting at `(0, 0)`. -/
theorem sub_inc1_counterexample :
    applyRegisterInstruction .incR1
        (applyRegisterInstruction .subR0 ((0 : Nibble), 0)) ≠
      applyRegisterInstruction .subR0
        (applyRegisterInstruction .incR1 ((0 : Nibble), 0)) := by
  decide

/-- Concrete counterexample for SUB_R0 and DEC_R1, starting at `(0, 0)`. -/
theorem sub_dec1_counterexample :
    applyRegisterInstruction .decR1
        (applyRegisterInstruction .subR0 ((0 : Nibble), 0)) ≠
      applyRegisterInstruction .subR0
        (applyRegisterInstruction .decR1 ((0 : Nibble), 0)) := by
  decide

/-- A compact record of the four distinct conflict patterns. Reversing either
instruction order preserves each inequality by symmetry. -/
theorem all_crossConflict_counterexamples :
    (∃ registers, applyRegisterInstruction .incR1
        (applyRegisterInstruction .addR0 registers) ≠
      applyRegisterInstruction .addR0
        (applyRegisterInstruction .incR1 registers)) ∧
    (∃ registers, applyRegisterInstruction .decR1
        (applyRegisterInstruction .addR0 registers) ≠
      applyRegisterInstruction .addR0
        (applyRegisterInstruction .decR1 registers)) ∧
    (∃ registers, applyRegisterInstruction .incR1
        (applyRegisterInstruction .subR0 registers) ≠
      applyRegisterInstruction .subR0
        (applyRegisterInstruction .incR1 registers)) ∧
    (∃ registers, applyRegisterInstruction .decR1
        (applyRegisterInstruction .subR0 registers) ≠
      applyRegisterInstruction .subR0
        (applyRegisterInstruction .decR1 registers)) := by
  exact ⟨⟨(0, 0), add_inc1_counterexample⟩,
    ⟨(0, 0), add_dec1_counterexample⟩,
    ⟨(0, 0), sub_inc1_counterexample⟩,
    ⟨(0, 0), sub_dec1_counterexample⟩⟩

/-- ADD, SUB, INC_R0, and DEC_R0 all transform R0 while leaving R1 fixed.
With the common R1 value held constant, every pair of these transformations
commutes. -/
def r0Arithmetic : RegisterInstruction → Prop
  | .addR0 | .subR0 | .incR0 | .decR0 => True
  | _ => False

theorem r0Arithmetic_pairs_commute (first second : RegisterInstruction)
    (hFirst : r0Arithmetic first) (hSecond : r0Arithmetic second) :
    Commute first second := by
  rw [commute_iff_no_crossConflict]
  cases first <;> cases second <;> simp_all [r0Arithmetic, crossConflict]

/-- INC_R1 and DEC_R1 commute with each other because they are translations
of the same four-bit register. -/
def r1UnitUpdate : RegisterInstruction → Prop
  | .incR1 | .decR1 => True
  | _ => False

theorem r1UnitUpdates_commute (first second : RegisterInstruction)
    (hFirst : r1UnitUpdate first) (hSecond : r1UnitUpdate second) :
    Commute first second := by
  rw [commute_iff_no_crossConflict]
  cases first <;> cases second <;> simp_all [r1UnitUpdate, crossConflict]

/-- Small independent increment/decrement changes to the two different registers always
commute, including when either change wraps around modulo 16. -/
theorem independentUnitUpdates_commute (first second : RegisterInstruction)
    (hFirst : first = .incR0 ∨ first = .decR0)
    (hSecond : second = .incR1 ∨ second = .decR1) :
    Commute first second := by
  rw [commute_iff_no_crossConflict]
  rcases hFirst with rfl | rfl <;> rcases hSecond with rfl | rfl <;>
    rfl

/-- NOP commutes with every instruction in this module because it is the
identity on registers. -/
theorem nop_commutes (instruction : RegisterInstruction) :
    Commute .nop instruction ∧ Commute instruction .nop := by
  constructor <;> rw [commute_iff_no_crossConflict] <;>
    cases instruction <;> rfl

/-! ## Literal OUTPUT and arbitrary silent effects

The register-only model above is extended here to observable effects. An
effect transforms some data state and emits a finite output sequence. This
state may include registers and memory, so a silent effect can represent a
LOAD, STORE, or another deterministic state update. Program-counter movement
is handled separately because straight-line instruction widths add modulo 16.
At the encoded-program level, the moved instructions must both execute, and a
STORE must not rewrite the OUTPUT opcode or operand before it is fetched.
-/

/-- A data-state effect together with the values it emits. -/
abbrev ObservableEffect (State Output : Type) := State → State × List Output

/-- A silent instruction effect changes data state but emits nothing. -/
def silentEffect {State Output : Type} (update : State → State) :
    ObservableEffect State Output := fun state => (update state, [])

/-- A literal OUTPUT effect leaves data state alone and emits its operand. -/
def literalOutput {State Output : Type} (value : Output) :
    ObservableEffect State Output := fun state => (state, [value])

/-- Sequentially compose two observable instruction effects. -/
def sequenceEffects {State Output : Type}
    (first second : ObservableEffect State Output) :
    ObservableEffect State Output := fun state =>
  let (middle, firstOutput) := first state
  let (final, secondOutput) := second middle
  (final, firstOutput ++ secondOutput)

/-- A literal two-byte OUTPUT commutes observably with every silent data-state
effect: the final state is the same and the output sequence is unchanged. This
includes silent updates that read or write memory, because the output value is
the already-decoded literal operand. -/
theorem literalOutput_commutes_with_silent {State Output : Type}
    (value : Output) (update : State → State) (state : State) :
    sequenceEffects (literalOutput value) (silentEffect update) state =
      sequenceEffects (silentEffect update) (literalOutput value) state := by
  simp [sequenceEffects, literalOutput, silentEffect]

/-- Two literal outputs commute exactly when they emit the same value. -/
theorem two_literal_outputs_commute_iff {State Output : Type}
    [DecidableEq Output] (first second : Output) (state : State) :
    sequenceEffects (literalOutput first) (literalOutput second) state =
      sequenceEffects (literalOutput second) (literalOutput first) state ↔
        first = second := by
  constructor
  · intro h
    have hOutput := congrArg Prod.snd h
    have hEqualities : first = second ∧ second = first := by
      simpa [sequenceEffects, literalOutput] using hOutput
    exact hEqualities.1
  · intro h
    subst second
    rfl

/-- Concrete encoding fact for opcode 8: it emits the operand at the wrapped
next cell, preserves data state, advances by two bytes, and does not halt. -/
theorem step_literalOutput_effect (state : MachineState)
    (hOpcode : (state.memory state.pc).val = 8) :
    (step state).output = some (state.memory (pcAdd state.pc 1)) ∧
      (step state).state.memory = state.memory ∧
      (step state).state.r0 = state.r0 ∧
      (step state).state.r1 = state.r1 ∧
      (step state).state.pc = pcAdd state.pc 2 ∧
      (step state).halted = false := by
  simp [step, hOpcode]

/-- The user's example: printing literal 5 and incrementing R0 have the same
final register state and exact output sequence in either order. -/
theorem print5_incR0_observably_commute (registers : Registers) :
    sequenceEffects (literalOutput (5 : Nibble))
        (silentEffect (applyRegisterInstruction .incR0)) registers =
      sequenceEffects (silentEffect (applyRegisterInstruction .incR0))
        (literalOutput (5 : Nibble)) registers := by
  exact literalOutput_commutes_with_silent 5 _ registers

/-- Literal OUTPUT commutes with every register instruction in the opcode 1–7
family, not only INC_R0. -/
theorem literalOutput_commutes_with_registerInstruction (value : Nibble)
    (instruction : RegisterInstruction) (registers : Registers) :
    sequenceEffects (literalOutput value)
        (silentEffect (applyRegisterInstruction instruction)) registers =
      sequenceEffects (silentEffect (applyRegisterInstruction instruction))
        (literalOutput value) registers := by
  exact literalOutput_commutes_with_silent value _ registers

/-- Run two concrete machine steps and collect the values emitted by them. -/
def executeTwoSteps (state : MachineState) : MachineState × List Nibble :=
  let first := step state
  let second := step first.state
  let firstOutput := match first.output with
    | none => []
    | some value => [value]
  let secondOutput := match second.output with
    | none => []
    | some value => [value]
  (second.state, firstOutput ++ secondOutput)

/-- End-to-end machine check of the user's example. The two code layouts
`OUTPUT 5; INC_R0` and `INC_R0; OUTPUT 5` finish with equal registers and PC,
and emit exactly `[5]`. Their program bytes differ because the instructions
were physically reordered. -/
theorem machine_output5_incR0_example :
    let printedThenIncremented := executeTwoSteps (initialState [8, 5, 3])
    let incrementedThenPrinted := executeTwoSteps (initialState [3, 8, 5])
    printedThenIncremented.1.r0 = incrementedThenPrinted.1.r0 ∧
      printedThenIncremented.1.r1 = incrementedThenPrinted.1.r1 ∧
      printedThenIncremented.1.pc = incrementedThenPrinted.1.pc ∧
      printedThenIncremented.2 = incrementedThenPrinted.2 ∧
      printedThenIncremented.2 = [5] := by
  decide

/-- Instruction widths add modulo the 16-cell PC space, so the final PC after
two straight-line instructions is independent of their order, even for one-
and two-byte mixed pairs and across address wraparound. -/
theorem pcAdd_two_instruction_order (pc : PC) (firstWidth secondWidth : Nat) :
    pcAdd (pcAdd pc firstWidth) secondWidth =
      pcAdd (pcAdd pc secondWidth) firstWidth := by
  apply Fin.ext
  simp [pcAdd, Fin.val_ofNat, Nat.add_mod]
  omega

end Formalisation.InstructionCommutation
