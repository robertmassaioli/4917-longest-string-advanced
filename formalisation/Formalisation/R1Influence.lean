import Formalisation.Machine

/-!
# How R1 can affect the length-9 winner

The winner's output and control flow do not read R1 directly. R1 is updated
by DEC R1 and is read by ADD R0,R1 / SUB R0,R1, which write the result into
R0. This file first proves the corresponding general one-step facts, then
records that the winner's fixed memory contains no store instruction that
could make R1 observable through memory.
-/

namespace Formalisation.R1Influence

private theorem nibble_val_cases (x : Nibble) :
    x.val = 0 ∨ x.val = 1 ∨ x.val = 2 ∨ x.val = 3 ∨
    x.val = 4 ∨ x.val = 5 ∨ x.val = 6 ∨ x.val = 7 ∨
    x.val = 8 ∨ x.val = 9 ∨ x.val = 10 ∨ x.val = 11 ∨
    x.val = 12 ∨ x.val = 13 ∨ x.val = 14 ∨ x.val = 15 := by
  have h := x.isLt
  omega

/-- The unique length-9 winner found by exhaustive search. -/
def length9WinnerProgram : List Nibble :=
  [8, 8, 13, 1, 14, 5, 2, 6, 15]

/-- The complete 16-cell memory image, including zero padding. -/
def length9WinnerMemory : Memory := (initialState length9WinnerProgram).memory

/-- With memory, R0, and PC fixed, changing R1 cannot change the next
instruction address, halt signal, or output event. -/
theorem step_observation_independent_of_r1
    (s t : MachineState)
    (hMemory : s.memory = t.memory)
    (hR0 : s.r0 = t.r0)
    (hPC : s.pc = t.pc) :
    (step s).state.pc = (step t).state.pc ∧
    (step s).halted = (step t).halted ∧
    (step s).output = (step t).output := by
  cases s with
  | mk sm s0 s1 sp =>
    cases t with
    | mk tm t0 t1 tp =>
      cases hMemory
      cases hR0
      cases hPC
      have hCases := nibble_val_cases (sm sp)
      rcases hCases with h | h | h | h | h | h | h | h | h | h | h | h | h | h | h | h <;>
        simp [step, h]

/-- Outside ADD and SUB, changing only R1 also leaves the next R0 unchanged.
At ADD and SUB, R1 is read precisely to compute the new R0. -/
theorem step_r0_independent_of_r1_unless_arithmetic_merges_it
    (s t : MachineState)
    (hMemory : s.memory = t.memory)
    (hR0 : s.r0 = t.r0)
    (hPC : s.pc = t.pc)
    (hNotAdd : (s.memory s.pc).val ≠ 1)
    (hNotSub : (s.memory s.pc).val ≠ 2) :
    (step s).state.r0 = (step t).state.r0 := by
  cases s with
  | mk sm s0 s1 sp =>
    cases t with
    | mk tm t0 t1 tp =>
      cases hMemory
      cases hR0
      cases hPC
      have hCases := nibble_val_cases (sm sp)
      rcases hCases with h | h | h | h | h | h | h | h | h | h | h | h | h | h | h | h <;>
        simp_all [step, h]

/-- A step can change memory only when its opcode is one of the two STORE
instructions. -/
theorem step_preserves_memory_unless_store
    (s : MachineState)
    (hNotStoreR0 : (s.memory s.pc).val ≠ 11)
    (hNotStoreR1 : (s.memory s.pc).val ≠ 12) :
    (step s).state.memory = s.memory := by
  cases s with
  | mk sm s0 s1 sp =>
      have hCases := nibble_val_cases (sm sp)
      rcases hCases with h | h | h | h | h | h | h | h | h | h | h | h | h | h | h | h <;>
        simp_all [step, h]

/-- The winner's memory has no STORE instruction (opcode 11 or 12), so R1
cannot affect this program by writing a value into memory. -/
theorem length9Winner_has_no_store_instruction :
    ∀ pc : PC, (length9WinnerMemory pc).val ≠ 11 ∧
      (length9WinnerMemory pc).val ≠ 12 := by
  decide

/-- Since no cell in the winner's image contains a STORE opcode, each step
preserves the entire memory image. -/
theorem length9Winner_step_preserves_memory
    (s : MachineState)
    (hMemory : s.memory = length9WinnerMemory) :
    (step s).state.memory = s.memory := by
  apply step_preserves_memory_unless_store
  · rw [hMemory]
    exact (length9Winner_has_no_store_instruction s.pc).1
  · rw [hMemory]
    exact (length9Winner_has_no_store_instruction s.pc).2

/-- In the winner's fixed memory, every instruction other than its ADD and
SUB instructions is independent of R1 even in the resulting R0 value. -/
theorem winner_step_r0_independent_away_from_add_sub
    (s t : MachineState)
    (hMemoryS : s.memory = length9WinnerMemory)
    (hMemoryT : t.memory = length9WinnerMemory)
    (hR0 : s.r0 = t.r0)
    (hPC : s.pc = t.pc)
    (hNotAdd : (s.memory s.pc).val ≠ 1)
    (hNotSub : (s.memory s.pc).val ≠ 2) :
    (step s).state.r0 = (step t).state.r0 := by
  apply step_r0_independent_of_r1_unless_arithmetic_merges_it s t
  · rw [hMemoryS, hMemoryT]
  · exact hR0
  · exact hPC
  · exact hNotAdd
  · exact hNotSub

end Formalisation.R1Influence
