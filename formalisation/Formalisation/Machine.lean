import Formalisation.PC

/-!
# The 4917 machine

This module gives a total, executable Lean model of one processor instruction.
It follows the shared processor contract in `spec/processor.md`: memory and
registers are nibbles, addresses wrap modulo 16, operand cells are read from
the pre-step memory, and HALT is reported on the step that executes opcode 0.

Output is represented as an event on a step rather than part of the machine
state. It does not affect future instructions or cycle identity.
-/

namespace Formalisation

abbrev Nibble := Fin 16
abbrev Memory := PC → Nibble

/-- Add an instruction offset to a PC, wrapping in the 16-cell address space. -/
def pcAdd (pc : PC) (offset : Nat) : PC :=
  Fin.ofNat 16 (pc.val + offset)

/-- The complete state that affects future instruction execution. -/
structure MachineState where
  memory : Memory
  r0 : Nibble
  r1 : Nibble
  pc : PC

/-- An instruction's non-state output event, if it emits a value. -/
structure StepResult where
  state : MachineState
  halted : Bool
  output : Option Nibble

private def writeMemory (memory : Memory) (address value : Nibble) : Memory :=
  fun cell => if cell = address then value else memory cell

/-- Execute exactly one instruction according to the 4917 processor contract. -/
def step (s : MachineState) : StepResult := Id.run do
  let next := pcAdd s.pc 1
  let afterOperand := pcAdd s.pc 2
  let operand := s.memory (pcAdd s.pc 1)
  let target := s.memory operand
  match (s.memory s.pc).val with
  | 0 =>
      return ⟨{ s with pc := next }, true, none⟩
  | 1 =>
      return ⟨{ s with r0 := Fin.ofNat 16 (s.r0.val + s.r1.val), pc := next }, false, none⟩
  | 2 =>
      return ⟨{ s with r0 := Fin.ofNat 16 (s.r0.val + 16 - s.r1.val), pc := next }, false, none⟩
  | 3 =>
      return ⟨{ s with r0 := Fin.ofNat 16 (s.r0.val + 1), pc := next }, false, none⟩
  | 4 =>
      return ⟨{ s with r1 := Fin.ofNat 16 (s.r1.val + 1), pc := next }, false, none⟩
  | 5 =>
      return ⟨{ s with r0 := Fin.ofNat 16 (s.r0.val + 15), pc := next }, false, none⟩
  | 6 =>
      return ⟨{ s with r1 := Fin.ofNat 16 (s.r1.val + 15), pc := next }, false, none⟩
  | 7 =>
      return ⟨{ s with pc := next }, false, none⟩
  | 8 =>
      return ⟨{ s with pc := afterOperand }, false, some operand⟩
  | 9 =>
      return ⟨{ s with r0 := target, pc := afterOperand }, false, none⟩
  | 10 =>
      return ⟨{ s with r1 := target, pc := afterOperand }, false, none⟩
  | 11 =>
      return ⟨{ s with memory := writeMemory s.memory operand s.r0, pc := afterOperand }, false, none⟩
  | 12 =>
      return ⟨{ s with memory := writeMemory s.memory operand s.r1, pc := afterOperand }, false, none⟩
  | 13 =>
      return ⟨{ s with pc := operand }, false, none⟩
  | 14 =>
      return ⟨{ s with pc := if s.r0.val == 0 then operand else afterOperand }, false, none⟩
  | _ =>
      return ⟨{ s with pc := if s.r0.val == 0 then afterOperand else operand }, false, none⟩

/-- A list of instruction nibbles, zero-padded and truncated to 16 cells. -/
def initialState (program : List Nibble) : MachineState :=
  { memory := fun cell => program.getD cell.val 0
    r0 := 0
    r1 := 0
    pc := 0 }

/-- Result of running for a fixed number of instruction steps. `outputRev`
stores emitted values in reverse order to make each output step inexpensive. -/
inductive RunResult where
  | halted (state : MachineState) (outputRev : List Nibble)
  | outOfFuel (state : MachineState) (outputRev : List Nibble)

/-- Execute at most `fuel` instructions, stopping immediately on HALT. -/
def runFuel : Nat → MachineState → List Nibble → RunResult
  | 0, state, outputRev => .outOfFuel state outputRev
  | fuel + 1, state, outputRev =>
      let result := step state
      let outputRev := match result.output with
        | none => outputRev
        | some value => value :: outputRev
      if result.halted then
        .halted result.state outputRev
      else
        runFuel fuel result.state outputRev


theorem zeroOpcodeHalts (s : MachineState)
    (hOpcode : (s.memory s.pc).val = 0) :
    (step s).halted = true := by
  simp [step, hOpcode]

/-- With at least one unit of fuel, execution at opcode 0 halts immediately
and emits no value. -/
theorem runFuel_zeroOpcode_halts (s : MachineState) (fuel : Nat)
    (hFuel : 0 < fuel)
    (hOpcode : (s.memory s.pc).val = 0) :
    ∃ finalState, runFuel fuel s [] = .halted finalState [] := by
  cases fuel with
  | zero => simp at hFuel
  | succ remaining =>
      simp [runFuel, step, hOpcode]

/-- The operand byte for an instruction at PC 15 is fetched from cell 0. -/
theorem operand_address_wraps_at_pc15 :
    pcAdd (15 : PC) 1 = 0 := by
  decide

/-- A two-byte instruction at PC 15 advances to PC 1 after reading cell 0. -/
theorem after_two_byte_instruction_at_pc15 :
    pcAdd (15 : PC) 2 = 1 := by
  decide

/-- A two-byte instruction at PC 14 reads its operand at 15, then wraps to 0. -/
theorem after_two_byte_instruction_at_pc14 :
    pcAdd (14 : PC) 1 = 15 ∧ pcAdd (14 : PC) 2 = 0 := by
  decide

/-- For OUTPUT at PC 15, the cell-zero operand is emitted and execution
continues at PC 1. -/
theorem output_at_pc15_uses_wrapped_operand (s : MachineState)
    (hPC : s.pc = 15)
    (hOpcode : (s.memory s.pc).val = 8) :
    (step s).output = some (s.memory 0) ∧ (step s).state.pc = 1 := by
  rw [hPC] at hOpcode
  simp [step, hPC, hOpcode]
  rw [operand_address_wraps_at_pc15, after_two_byte_instruction_at_pc15]
  exact ⟨rfl, rfl⟩

end Formalisation
