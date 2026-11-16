import Formalisation.MonotoneOutput

/-!
# Length-specific bounds for read-only straight-line runs

These theorems concern runs whose PC strictly increases and whose memory is
unchanged. The memory premise matters: a store could otherwise write new
instructions into zero-padded cells. Scores count decimal characters.
-/

namespace Formalisation

/-- A forward, read-only execution that eventually halts. -/
inductive ReadOnlyStraightLineRun (program : List Nibble) :
    MachineState → Nat → Prop where
  | halt {state : MachineState} :
      state.memory = (initialState program).memory →
      (step state).halted = true →
      ReadOnlyStraightLineRun program state 0
  | next {state : MachineState} {restScore : Nat} :
      state.memory = (initialState program).memory →
      state.pc.val < (step state).state.pc.val →
      (step state).state.memory = state.memory →
      (step state).halted = false →
      ReadOnlyStraightLineRun program (step state).state restScore →
      ReadOnlyStraightLineRun program state
        (stepOutputCharacterScore (step state) + restScore)

private def remainingCells (program : List Nibble) (pc : PC) : Nat :=
  program.length - pc.val

private theorem initialMemory_at (program : List Nibble) (pc : PC) :
    (initialState program).memory pc = program.getD pc.val 0 := rfl

private theorem output_charge_le_remaining
    (program : List Nibble) (hLength : program.length ≤ 3)
    (state : MachineState)
    (hMemory : state.memory = (initialState program).memory)
    (hPC : state.pc.val < program.length)
    (hProgress : state.pc.val < (step state).state.pc.val) :
    stepOutputCharacterScore (step state) +
      remainingCells program (step state).state.pc ≤
      remainingCells program state.pc := by
  have hOpcodeBound : (state.memory state.pc).val < 16 := Fin.isLt _
  have hPCsmall : state.pc.val < 16 := state.pc.isLt
  have hLen : program.length ≤ 3 := hLength
  have hMem : state.memory state.pc = program.getD state.pc.val 0 := by
    rw [hMemory]
    exact initialMemory_at program state.pc
  cases hStepOut : (step state).output with
  | none =>
      simp [stepOutputCharacterScore, hStepOut, remainingCells]
      omega
  | some value =>
      have hOpcode : (state.memory state.pc).val = 8 := by
        simp only [step] at hStepOut
        split at hStepOut <;> simp_all
      have hOut : (step state).output = some value := hStepOut
      have hOutValue : value = state.memory (pcAdd state.pc 1) := by
        simp [step, hOpcode] at hStepOut
        exact hStepOut.symm
      have hVal : (state.memory (pcAdd state.pc 1)).val =
          (program.getD (state.pc.val + 1) 0).val := by
        have hm := congrArg (fun m : Memory => m (pcAdd state.pc 1)) hMemory
        rw [hm]
        have hIndex : (pcAdd state.pc 1).val = state.pc.val + 1 := by
          simp [pcAdd, Fin.val_ofNat]
          omega
        simp [initialState, hIndex]
      have hNext : (step state).state.pc.val = state.pc.val + 2 := by
        have hAdv := outputStep_advances_two state value hOut
        rw [hAdv]
        simp [pcAdd, Fin.val_ofNat]
        omega
      simp [stepOutputCharacterScore, hOut, remainingCells]
      have hOperandIndex : state.pc.val + 1 < program.length ∨
          state.pc.val + 1 ≥ program.length := by omega
      rcases hOperandIndex with hInside | hPadding
      · have hCount := decimalCharacterCount_le_two value
        omega
      · have hZero : program.getD (state.pc.val + 1) 0 = 0 := by
          simp [List.getD_eq_getElem?_getD,
            List.getElem?_eq_none (by omega)]
        have hOne : decimalCharacterCount value = 1 := by
          have hz : (program.getD (state.pc.val + 1) 0).val = 0 :=
            congrArg Fin.val hZero
          have hv : value = 0 := by
            apply Fin.ext
            rw [hOutValue, hVal]
            exact hz
          simp [decimalCharacterCount, hv]
        omega

private theorem straightLine_score_le_length {program : List Nibble}
    {state : MachineState} {score : Nat}
    (hLength : program.length ≤ 3)
    (hStart : state.pc.val = 0)
    (run : ReadOnlyStraightLineRun program state score) :
    score ≤ program.length := by
  have bound : ∀ {state score}, ReadOnlyStraightLineRun program state score →
      score ≤ remainingCells program state.pc := by
    intro state score hRun
    induction hRun with
    | halt hMemory hHalt => simp [remainingCells]
    | @next state restScore hMemory hProgress hMemoryNext hNotHalt hRest ih =>
        have hOpcode := hMemory
        have hPC : state.pc.val < program.length := by
          by_cases h : program.length ≤ state.pc.val
          · have hPad : (state.memory state.pc).val = 0 := by
              rw [hMemory]
              change (program.getD state.pc.val 0).val = 0
              rw [List.getD_eq_getElem?_getD]
              rw [List.getElem?_eq_none h]
              rfl
            have hHalt : (step state).halted = true := by simp [step, hPad]
            simp [hHalt] at hNotHalt
          · omega
        have hLocal := output_charge_le_remaining program hLength state
          hMemory hPC hProgress
        omega
  have hBound := bound run
  simp [remainingCells, hStart] at hBound
  exact hBound

/-- A read-only strictly increasing halting run from a one-cell input emits
at most one decimal character. -/
theorem length1_straightLine_score_le_one
    {program : List Nibble} (hLength : program.length = 1)
    {state : MachineState} {score : Nat}
    (hStart : state.pc.val = 0)
    (run : ReadOnlyStraightLineRun program state score) : score ≤ 1 := by
  have h := straightLine_score_le_length (by omega) hStart run
  omega

/-- A read-only strictly increasing halting run from a two-cell input emits
at most two decimal characters. -/
theorem length2_straightLine_score_le_two
    {program : List Nibble} (hLength : program.length = 2)
    {state : MachineState} {score : Nat}
    (hStart : state.pc.val = 0)
    (run : ReadOnlyStraightLineRun program state score) : score ≤ 2 := by
  have h := straightLine_score_le_length (by omega) hStart run
  omega

/-- A read-only strictly increasing halting run from a three-cell input emits
at most three decimal characters. -/
theorem length3_straightLine_score_le_three
    {program : List Nibble} (hLength : program.length = 3)
    {state : MachineState} {score : Nat}
    (hStart : state.pc.val = 0)
    (run : ReadOnlyStraightLineRun program state score) : score ≤ 3 := by
  have h := straightLine_score_le_length (by omega) hStart run
  omega

/-- The reported one-cell winner `[8]` attains the read-only straight-line
upper bound: it emits padded zero once, for one character. -/
theorem length1_exact_straightLine_maximum :
    ∃ score, ReadOnlyStraightLineRun [8] (initialState [8]) score ∧ score = 1 ∧
      ∀ score', ReadOnlyStraightLineRun [8] (initialState [8]) score' →
        score' ≤ 1 := by
  refine ⟨stepOutputCharacterScore (step (initialState [8])) + 0, ?_, ?_, ?_⟩
  · apply ReadOnlyStraightLineRun.next
    · rfl
    · decide
    · rfl
    · decide
    · apply ReadOnlyStraightLineRun.halt
      · rfl
      · decide
  · decide
  · intro score' run
    exact length1_straightLine_score_le_one rfl rfl run

/-- The reported two-cell winner `[8, 10]` attains the read-only straight-line
upper bound with one two-character output. -/
theorem length2_exact_straightLine_maximum :
    ∃ score, ReadOnlyStraightLineRun [8, 10] (initialState [8, 10]) score ∧
      score = 2 ∧
      ∀ score', ReadOnlyStraightLineRun [8, 10] (initialState [8, 10]) score' →
        score' ≤ 2 := by
  refine ⟨stepOutputCharacterScore (step (initialState [8, 10])) + 0, ?_, ?_, ?_⟩
  · apply ReadOnlyStraightLineRun.next
    · rfl
    · decide
    · rfl
    · decide
    · apply ReadOnlyStraightLineRun.halt
      · rfl
      · decide
  · decide
  · intro score' run
    exact length2_straightLine_score_le_two rfl rfl run

/-- The reported three-cell winner `[8, 10, 8]` attains the read-only
straight-line upper bound: a two-character output followed by padded zero. -/
theorem length3_exact_straightLine_maximum :
    ∃ score, ReadOnlyStraightLineRun [8, 10, 8] (initialState [8, 10, 8]) score ∧
      score = 3 ∧
      ∀ score', ReadOnlyStraightLineRun [8, 10, 8] (initialState [8, 10, 8]) score' →
        score' ≤ 3 := by
  refine ⟨stepOutputCharacterScore (step (initialState [8, 10, 8])) +
    (stepOutputCharacterScore (step (step (initialState [8, 10, 8])).state) + 0),
    ?_, ?_, ?_⟩
  · apply ReadOnlyStraightLineRun.next
    · rfl
    · decide
    · rfl
    · decide
    · apply ReadOnlyStraightLineRun.next
      · rfl
      · decide
      · rfl
      · decide
      · apply ReadOnlyStraightLineRun.halt
        · rfl
        · decide
  · decide
  · intro score' run
    exact length3_straightLine_score_le_three rfl rfl run

end Formalisation
