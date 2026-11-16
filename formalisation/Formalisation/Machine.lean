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

/-- Instruction positions visited by a linear scan from PC 0. One-byte
instructions advance by one; all two-byte opcodes advance by two. The latter
includes jumps so the safety predicate below can reject them when reached. -/
inductive LinearReach (memory : Memory) : PC → Prop where
  | start : LinearReach memory 0
  | oneByte {pc : PC} :
      LinearReach memory pc →
      1 ≤ (memory pc).val →
      (memory pc).val ≤ 7 →
      LinearReach memory (pcAdd pc 1)
  | twoByte {pc : PC} :
      LinearReach memory pc →
      8 ≤ (memory pc).val →
      (memory pc).val ≤ 15 →
      LinearReach memory (pcAdd pc 2)

/-- Every ordinary instruction in a no-storage/no-loop memory preserves
memory. -/
theorem safeStep_preserves_memory (s : MachineState)
    (hCodeBound : (s.memory s.pc).val ≤ 10) :
    (step s).state.memory = s.memory := by
  have hCode := hCodeBound
  cases hOpcode : (s.memory s.pc).val with
  | zero => simp [step, hOpcode]
  | succ n =>
      have hn : n ≤ 9 := by omega
      cases n with
        | zero => simp [step, hOpcode]
        | succ n =>
          cases n with
            | zero => simp [step, hOpcode]
            | succ n =>
              cases n with
                | zero => simp [step, hOpcode]
                | succ n =>
                  cases n with
                    | zero => simp [step, hOpcode]
                    | succ n =>
                      cases n with
                        | zero => simp [step, hOpcode]
                        | succ n =>
                          cases n with
                            | zero => simp [step, hOpcode]
                            | succ n =>
                              cases n with
                                | zero => simp [step, hOpcode]
                                | succ n =>
                                  cases n with
                                    | zero => simp [step, hOpcode]
                                    | succ n =>
                                      cases n with
                                        | zero => simp [step, hOpcode]
                                        | succ n =>
                                          cases n with
                                            | zero => simp [step, hOpcode]
                                            | succ n => omega

/-- Away from the final two padded cells, every safe non-HALT instruction
advances the PC strictly without wrapping. -/
theorem safeStep_progresses (s : MachineState)
    (hCodeBound : (s.memory s.pc).val ≤ 10)
    (hPC : s.pc.val < 14)
    (hNotHalt : (s.memory s.pc).val ≠ 0) :
    (step s).halted = false ∧ s.pc.val < (step s).state.pc.val := by
  have hCode := hCodeBound
  cases hOpcode : (s.memory s.pc).val with
  | zero => simp [hOpcode] at hNotHalt
  | succ n =>
      have hn : n ≤ 9 := by omega
      cases n with
        | zero => simp [step, hOpcode, pcAdd] <;> omega
        | succ n =>
          cases n with
            | zero => simp [step, hOpcode, pcAdd] <;> omega
            | succ n =>
              cases n with
                | zero => simp [step, hOpcode, pcAdd] <;> omega
                | succ n =>
                  cases n with
                    | zero => simp [step, hOpcode, pcAdd] <;> omega
                    | succ n =>
                      cases n with
                        | zero => simp [step, hOpcode, pcAdd] <;> omega
                        | succ n =>
                          cases n with
                            | zero => simp [step, hOpcode, pcAdd] <;> omega
                            | succ n =>
                              cases n with
                                | zero => simp [step, hOpcode, pcAdd] <;> omega
                                | succ n =>
                                  cases n with
                                    | zero => simp [step, hOpcode, pcAdd] <;> omega
                                    | succ n =>
                                      cases n with
                                        | zero => simp [step, hOpcode, pcAdd] <;> omega
                                        | succ n =>
                                          cases n with
                                            | zero => simp [step, hOpcode, pcAdd] <;> omega
                                            | succ n => omega

/-- Safe non-HALT instructions advance by one for opcodes 1–7 and by two
for opcodes 8–10. -/
theorem safeStep_nextPC (s : MachineState)
    (hCodeBound : (s.memory s.pc).val ≤ 10)
    (hNotHalt : (s.memory s.pc).val ≠ 0) :
    (step s).halted = false ∧
    (step s).state.pc = if (s.memory s.pc).val ≤ 7
      then pcAdd s.pc 1 else pcAdd s.pc 2 := by
  have hCode := hCodeBound
  cases hOpcode : (s.memory s.pc).val with
  | zero => simp [hOpcode] at hNotHalt
  | succ n =>
      have hn : n ≤ 9 := by omega
      cases n with
        | zero => simp [step, hOpcode] <;> omega
        | succ n =>
          cases n with
            | zero => simp [step, hOpcode] <;> omega
            | succ n =>
              cases n with
                | zero => simp [step, hOpcode] <;> omega
                | succ n =>
                  cases n with
                    | zero => simp [step, hOpcode] <;> omega
                    | succ n =>
                      cases n with
                        | zero => simp [step, hOpcode] <;> omega
                        | succ n =>
                          cases n with
                            | zero => simp [step, hOpcode] <;> omega
                            | succ n =>
                              cases n with
                                | zero => simp [step, hOpcode] <;> omega
                                | succ n =>
                                  cases n with
                                    | zero => simp [step, hOpcode] <;> omega
                                    | succ n =>
                                      cases n with
                                        | zero => simp [step, hOpcode] <;> omega
                                        | succ n =>
                                          cases n with
                                            | zero => simp [step, hOpcode] <;> omega
                                            | succ n => omega

/-- Big-step termination: either this state executes HALT, or its next
instruction state eventually does. -/
inductive EventuallyHalts : MachineState → Prop where
  | halt {s : MachineState} :
      (s.memory s.pc).val = 0 → EventuallyHalts s
  | next {s : MachineState} :
      (s.memory s.pc).val ≠ 0 →
      EventuallyHalts (step s).state →
      EventuallyHalts s

/-- If every linearly reachable instruction is HALT or a non-store,
non-jump opcode, and cells 14 and 15 are zero, execution eventually halts. -/
theorem safeState_eventuallyHalts (s : MachineState)
    (hReach : LinearReach s.memory s.pc)
    (hSafe : ∀ address, LinearReach s.memory address →
      (s.memory address).val ≤ 10)
    (hTail : ∀ address, 14 ≤ address.val → s.memory address = 0) :
    EventuallyHalts s := by
  by_cases hAtTail : 14 ≤ s.pc.val
  · apply EventuallyHalts.halt
    have hZero := hTail s.pc hAtTail
    rw [hZero]
    rfl
  · have hPC : s.pc.val < 14 := by omega
    by_cases hHalt : (s.memory s.pc).val = 0
    · exact EventuallyHalts.halt hHalt
    · have hCodeBound := hSafe s.pc hReach
      have hProgress := safeStep_progresses s hCodeBound hPC hHalt
      apply EventuallyHalts.next hHalt
      have hMemory := safeStep_preserves_memory s hCodeBound
      have hNextPC := (safeStep_nextPC s hCodeBound hHalt).2
      have hNextReach : LinearReach s.memory (step s).state.pc := by
        rw [hNextPC]
        by_cases hOneByte : (s.memory s.pc).val ≤ 7
        · simp [hOneByte]
          have hLower : 1 ≤ (s.memory s.pc).val := by omega
          exact .oneByte hReach hLower hOneByte
        · simp [hOneByte]
          have hLower : 8 ≤ (s.memory s.pc).val := by omega
          have hUpper : (s.memory s.pc).val ≤ 15 := by omega
          exact .twoByte hReach hLower hUpper
      have hNextReach' : LinearReach (step s).state.memory (step s).state.pc := by
        rw [hMemory]
        exact hNextReach
      have hSafeNext : ∀ address, LinearReach (step s).state.memory address →
          ((step s).state.memory address).val ≤ 10 := by
        intro address hAddress
        rw [hMemory] at hAddress ⊢
        exact hSafe address hAddress
      have hTailNext : ∀ address, 14 ≤ address.val → (step s).state.memory address = 0 := by
        intro address hAddress
        rw [hMemory]
        exact hTail address hAddress
      exact safeState_eventuallyHalts (step s).state hNextReach' hSafeNext hTailNext
termination_by 14 - s.pc.val
decreasing_by omega

/-- No STORE or jump opcode occurs at a position reached by scanning the
program linearly from PC 0. Operand cells of two-byte instructions are skipped. -/
def NoStorageOrLoopProgram (program : List Nibble) : Prop :=
  ∀ address, LinearReach (initialState program).memory address →
    ((initialState program).memory address).val ≤ 10

/-- Every program of length at most 14 with no reachable STORE or jump opcode
eventually executes HALT. Data operands are unrestricted. The zero-padded cells
at 14 and 15 ensure termination even after a two-byte instruction at PC 13. -/
theorem shortProgram_eventuallyHalts (program : List Nibble)
    (hLength : program.length ≤ 14)
    (hSafe : NoStorageOrLoopProgram program) :
    EventuallyHalts (initialState program) := by
  apply safeState_eventuallyHalts
  · exact LinearReach.start
  · exact hSafe
  · intro address hAddress
    simp only [initialState, List.getD]
    rw [List.getElem?_eq_none (by omega)]
    rfl

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

/-- A length-15 example with no STORE or jump opcodes: fourteen NOPs followed
by OUTPUT. At PC 14, OUTPUT reads the padded zero at cell 15 and wraps to PC 0. -/
def wraparoundCounterexample : List Nibble := List.replicate 14 7 ++ [8]

theorem wraparoundCounterexample_length :
    wraparoundCounterexample.length = 15 := by
  decide

theorem wraparoundCounterexample_step_at_pc14 :
    let s := { initialState wraparoundCounterexample with pc := 14 }
    (step s).halted = false ∧
    (step s).state.pc = 0 ∧
    (step s).output = some 0 := by
  decide

end Formalisation
