import Formalisation.Machine

/-!
# Termination of short linear programs

The machine step function and state model live in `Formalisation.Machine`.
This module proves termination for short programs whose linear instruction
scan contains no STORE or jump opcodes.
-/

namespace Formalisation

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

end Formalisation

