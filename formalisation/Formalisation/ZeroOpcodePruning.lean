import Formalisation.MonotoneOutput
import Init.Omega

/-!
# What zero opcodes justify pruning

The entry-zero rule is unconditional. A zero in cell 1 is only a local rule:
if execution fetches it while it is still zero, that instruction halts.
It does not imply that execution reaches cell 1.
-/

namespace Formalisation

/-- Function-valued memory has decidable extensional equality because its
domain is the finite type `PC`. -/
instance : DecidableEq Memory := fun left right =>
  if h : ∀ pc : PC, left pc = right pc then
    isTrue (funext h)
  else
    isFalse (fun hEq => h (fun pc => congrFun hEq pc))

deriving instance DecidableEq for MachineState

/-- The state reached after `n` transitions when continuing the deterministic
state component of `step`, whether or not an earlier step reported HALT. -/
def stateAfter (program : List Nibble) : Nat → MachineState
  | 0 => initialState program
  | n + 1 => (step (stateAfter program n)).state

/-- A fixed first step leaves the deterministic state trajectory at that same
state forever. -/
theorem stateAfter_fixedPoint (program : List Nibble)
    (hFixed : (step (initialState program)).state = initialState program) :
    ∀ n, stateAfter program n = initialState program := by
  intro n
  induction n with
  | zero => rfl
  | succ n ih => simpa [stateAfter, hFixed, ih]

/-- A list containing every member of a nodup list must be at least as long. -/
theorem nodup_length_le_of_mem {α : Type} [BEq α] [LawfulBEq α]
    (stateList values : List α)
    (hNodup : values.Nodup)
    (hMem : ∀ value, value ∈ values → value ∈ stateList) :
    values.length ≤ stateList.length := by
  cases values with
  | nil => simp
  | cons head tail =>
      have hHead : head ∈ stateList := hMem head (by simp)
      have hStateListNonempty : 0 < stateList.length :=
        List.length_pos_of_mem hHead
      have hParts := List.nodup_cons.mp hNodup
      have hTailMem : ∀ value, value ∈ tail → value ∈ stateList.erase head := by
        intro value hValue
        have hNe : value ≠ head := by
          intro hEq
          subst value
          exact hParts.1 hValue
        apply (List.mem_erase_of_ne hNe).2
        exact hMem value (by simp [hValue])
      have hTail := nodup_length_le_of_mem (stateList.erase head) tail
        hParts.2 hTailMem
      rw [List.length_erase_of_mem hHead] at hTail
      have hTailLt : tail.length < stateList.length :=
        (Nat.le_sub_one_iff_lt hStateListNonempty).mp hTail
      simpa using (Nat.succ_le_iff.mpr hTailLt)
termination_by stateList.length
decreasing_by
  rw [List.length_erase_of_mem hHead]
  exact Nat.sub_one_lt (Nat.ne_of_gt hStateListNonempty)

/-- The state at each time from zero through `n`, in visit order. -/
def stateVisits (program : List Nibble) (n : Nat) : List MachineState :=
  (List.range (n + 1)).map (stateAfter program)

private theorem stateVisits_nodup_of_distinct (program : List Nibble)
    (n : Nat)
    (hDistinct : ∀ i j, i < j → j ≤ n → stateAfter program i ≠ stateAfter program j) :
    (stateVisits program n).Nodup := by
  induction n with
  | zero => simp [stateVisits]
  | succ n ih =>
      rw [stateVisits, List.range_succ, List.map_append]
      apply List.nodup_append.mpr
      refine ⟨?_, by simp, ?_⟩
      · apply ih
        intro i j hij hj
        exact hDistinct i j hij (Nat.le_trans hj (Nat.le_succ n))
      · intro left hLeft right hRight
        have hRightEq : right = stateAfter program (n + 1) := by
          simpa using hRight
        rcases List.mem_map.mp hLeft with ⟨i, hi, hEq⟩
        have hiLt : i < n + 1 := List.mem_range.mp hi
        have hNotEq := hDistinct i (n + 1) hiLt (Nat.le_refl _)
        intro hEqStates
        apply hNotEq
        calc
          stateAfter program i = left := hEq
          _ = right := hEqStates
          _ = stateAfter program (n + 1) := hRightEq

/-- In a finite configuration cover, a deterministic machine trajectory must
repeat a state within one more visit than the cover's size. The cover need
only contain the trajectory states through the stated bound. -/
theorem machine_state_repeats_within_cover (program : List Nibble)
    (configurationCover : List MachineState)
    (hComplete : ∀ n, n ≤ configurationCover.length →
      stateAfter program n ∈ configurationCover) :
    ∃ i j, i < j ∧ j ≤ configurationCover.length ∧
      stateAfter program i = stateAfter program j := by
  classical
  by_cases hRepeat : ∃ i j, i < j ∧ j ≤ configurationCover.length ∧
      stateAfter program i = stateAfter program j
  · exact hRepeat
  ·
    have hImpossible : False := by
      have hDistinct : ∀ i j, i < j → j ≤ configurationCover.length →
          stateAfter program i ≠ stateAfter program j := by
        intro i j hij hj hEq
        apply hRepeat
        exact ⟨i, j, hij, hj, hEq⟩
      have hVisitsNodup := stateVisits_nodup_of_distinct program
        configurationCover.length hDistinct
      have hVisitsMem : ∀ state, state ∈ stateVisits program configurationCover.length →
          state ∈ configurationCover := by
        intro state hState
        rcases List.mem_map.mp hState with ⟨n, hN, hEq⟩
        have hnBound : n ≤ configurationCover.length :=
          Nat.le_of_lt_succ (List.mem_range.mp hN)
        rw [← hEq]
        exact hComplete n hnBound
      have hLength := nodup_length_le_of_mem configurationCover
        (stateVisits program configurationCover.length) hVisitsNodup hVisitsMem
      simp [stateVisits, List.length_map, List.length_range] at hLength
      omega
    exact False.elim hImpossible

/-- Determinism propagates an equal pair of visits forever, exhibiting the
periodic cycle after the earlier visit. -/
theorem repeated_state_visits_cycle (program : List Nibble) (i j : Nat)
    (hEq : stateAfter program i = stateAfter program j) :
    ∀ offset, stateAfter program (i + offset) = stateAfter program (j + offset) := by
  intro offset
  induction offset with
  | zero => simpa using hEq
  | succ offset ih =>
      simpa [Nat.add_assoc, stateAfter] using
        congrArg (fun state => (step state).state) ih

/-- Bounded repeat-or-HALT theorem for the concrete 4917 machine. For any
finite cover of the configurations visited through its length, either a HALT
instruction is encountered during that interval or a machine state repeats. -/
theorem machine_halts_or_repeats_within_cover (program : List Nibble)
    (configurationCover : List MachineState)
    (hComplete : ∀ n, n ≤ configurationCover.length →
      stateAfter program n ∈ configurationCover) :
    (∃ n, n ≤ configurationCover.length ∧
      (step (stateAfter program n)).halted = true) ∨
    (∃ i j, i < j ∧ j ≤ configurationCover.length ∧
      (step (stateAfter program i)).halted = false ∧
      (step (stateAfter program j)).halted = false ∧
      stateAfter program i = stateAfter program j) := by
  classical
  by_cases hHalt : ∃ n, n ≤ configurationCover.length ∧
      (step (stateAfter program n)).halted = true
  · exact Or.inl hHalt
  · right
    obtain ⟨i, j, hij, hj, hEq⟩ :=
      machine_state_repeats_within_cover program configurationCover hComplete
    refine ⟨i, j, hij, hj, ?_, ?_, hEq⟩
    · cases hStep : (step (stateAfter program i)).halted with
      | false => rfl
      | true => exact False.elim (hHalt ⟨i, Nat.le_trans (Nat.le_of_lt hij) hj, hStep⟩)
    · cases hStep : (step (stateAfter program j)).halted with
      | false => rfl
      | true => exact False.elim (hHalt ⟨j, hj, hStep⟩)

/-- On reset, a zero in the first program cell halts on the first instruction.
The length condition is unnecessary: `initialState` zero-pads short lists. -/
theorem firstCellZero_halts (program : List Nibble)
    (hZero : program.getD 0 0 = 0) :
    (step (initialState program)).halted = true := by
  apply zeroOpcodeHalts
  simpa [initialState] using hZero

/-- A fetched zero at cell 1 halts immediately, provided that cell has not
been overwritten before the fetch. This is the strongest unconditional local
claim; the premise records the current memory, not just the original bytes. -/
theorem fetchedCellOneZero_halts (state : MachineState)
    (hZero : (state.memory state.pc).val = 0) :
    (step state).halted = true :=
  zeroOpcodeHalts state hZero

/-- Conditional reachability result: if the execution's state sequence reaches
cell 1 and that cell is still zero at the fetch, the following instruction
halts. This does not claim the sequence reaches cell 1. -/
theorem reachingCellOneZero_halts_next (program : List Nibble) (n : Nat)
    (hPC : (stateAfter program n).pc = 1)
    (hZero : ((stateAfter program n).memory 1).val = 0) :
    (step (stateAfter program n)).halted = true := by
  apply zeroOpcodeHalts
  simpa [hPC] using hZero

/-- If the reset opcode is not one of the two jumps back to cell 0, the
program halts within two steps and its output score is at most one. -/
theorem reset_twoZero_halts_nonJump (program : List Nibble)
    (hCell1 : (initialState program).memory 1 = 0)
    (hCell2 : (initialState program).memory 2 = 0)
    (hNot13 : ((initialState program).memory 0).val ≠ 13)
    (hNot14 : ((initialState program).memory 0).val ≠ 14) :
    ∃ finalState outputRev,
      runFuel 2 (initialState program) [] = .halted finalState outputRev ∧
      outputCharacterScore outputRev ≤ 1 := by
  let initial := initialState program
  let opcode := (initial.memory 0).val
  have hCases : opcode = 0 ∨ opcode = 1 ∨ opcode = 2 ∨ opcode = 3 ∨
      opcode = 4 ∨ opcode = 5 ∨ opcode = 6 ∨ opcode = 7 ∨ opcode = 8 ∨
      opcode = 9 ∨ opcode = 10 ∨ opcode = 11 ∨ opcode = 12 ∨ opcode = 13 ∨
      opcode = 14 ∨ opcode = 15 := by
    have hRange := (initial.memory 0).isLt
    omega
  rcases hCases with h0 | h1 | h2 | h3 | h4 | h5 | h6 | h7 | h8 | h9 | h10 | h11 | h12 | h13 | h14 | h15
  all_goals
    refine ⟨if (step (initialState program)).halted then
        (step (initialState program)).state
      else (step ((step (initialState program)).state)).state,
      ((step (initialState program)).output).toList, ?_⟩
    constructor
    · simp_all [runFuel, step, initial, opcode, initialState, pcAdd,
        writeMemory_preserves_unequal]
    · simp_all [step, initial, opcode, initialState, pcAdd,
        outputCharacterScore, decimalCharacterCount]

/-- Exact reset case split when cells 1 and 2 are both HALT. Opcode 13 and
opcode 14 take a non-HALT, silent transition back to the identical reset state
(the latter because reset R0 is zero). Every other opcode halts within two
instructions with score at most one. -/
theorem reset_twoZero_caseSplit (program : List Nibble)
    (hCell1 : (initialState program).memory 1 = 0)
    (hCell2 : (initialState program).memory 2 = 0) :
    (((initialState program).memory 0).val = 13 ∧
      (step (initialState program)).halted = false ∧
      (step (initialState program)).output = none ∧
      (step (initialState program)).state = initialState program) ∨
    (((initialState program).memory 0).val = 14 ∧
      (step (initialState program)).halted = false ∧
      (step (initialState program)).output = none ∧
      (step (initialState program)).state = initialState program) ∨
    (∃ finalState outputRev,
      runFuel 2 (initialState program) [] = .halted finalState outputRev ∧
      outputCharacterScore outputRev ≤ 1) := by
  let initial := initialState program
  let opcode := (initial.memory 0).val
  simp [initialState] at hCell1 hCell2
  by_cases h13 : opcode = 13
  · left
    refine ⟨?_, ?_, ?_, ?_⟩
    · simpa [initial, opcode, initialState] using h13
    · have h13' : (program[0]?.getD 0).val = 13 := by simpa [initial, opcode, initialState] using h13
      simp [step, initialState, h13', hCell1, pcAdd]
    · have h13' : (program[0]?.getD 0).val = 13 := by simpa [initial, opcode, initialState] using h13
      simp [step, initialState, h13', hCell1, pcAdd]
    · have h13' : (program[0]?.getD 0).val = 13 := by simpa [initial, opcode, initialState] using h13
      simp [step, initialState, h13', hCell1, pcAdd]
  · by_cases h14 : opcode = 14
    · right; left
      refine ⟨?_, ?_, ?_, ?_⟩
      · simpa [initial, opcode, initialState] using h14
      · have h14' : (program[0]?.getD 0).val = 14 := by simpa [initial, opcode, initialState] using h14
        simp [step, initialState, h14', hCell1, pcAdd]
      · have h14' : (program[0]?.getD 0).val = 14 := by simpa [initial, opcode, initialState] using h14
        simp [step, initialState, h14', hCell1, pcAdd]
      · have h14' : (program[0]?.getD 0).val = 14 := by simpa [initial, opcode, initialState] using h14
        simp [step, initialState, h14', hCell1, pcAdd]
    · right; right
      exact reset_twoZero_halts_nonJump program hCell1 hCell2
        (by simpa [initial, opcode] using h13)
        (by simpa [initial, opcode] using h14)

/-- Under the opcode-13/14 branches, every state visit remains the reset state
and every fetched instruction is silent and non-HALT. -/
theorem reset_twoZero_loop_forever (program : List Nibble)
    (hCell1 : (initialState program).memory 1 = 0)
    (hLoop : ((initialState program).memory 0).val = 13 ∨
      ((initialState program).memory 0).val = 14) :
    ∀ n, stateAfter program n = initialState program ∧
      (step (stateAfter program n)).halted = false ∧
      (step (stateAfter program n)).output = none := by
  simp [initialState] at hCell1
  have hFixed : (step (initialState program)).state = initialState program := by
    rcases hLoop with h13 | h14
    · have h13' : (program[0]?.getD 0).val = 13 := by simpa [initialState] using h13
      simp [step, initialState, h13', hCell1, pcAdd]
    · have h14' : (program[0]?.getD 0).val = 14 := by simpa [initialState] using h14
      simp [step, initialState, h14', hCell1, pcAdd]
  have hStep : (step (initialState program)).halted = false ∧
      (step (initialState program)).output = none := by
    rcases hLoop with h13 | h14
    · have h13' : (program[0]?.getD 0).val = 13 := by simpa [initialState] using h13
      simp [step, initialState, h13', hCell1, pcAdd]
    · have h14' : (program[0]?.getD 0).val = 14 := by simpa [initialState] using h14
      simp [step, initialState, h14', hCell1, pcAdd]
  intro n
  rw [stateAfter_fixedPoint program hFixed n]
  exact ⟨rfl, hStep.1, hStep.2⟩

/-- Example: the first instruction jumps to cell 0, skipping a zero at cell 1
forever. -/
def skipsSecondCell : List Nibble := [13, 0, 0]

/-- Opcode 15 uses reset R0 = 0, so it falls through to cell 2. -/
theorem opcode15_reset_falls_through_and_halts :
    (step (initialState [15, 0, 0])).state.pc = 2 ∧
      (step ((step (initialState [15, 0, 0])).state)).halted = true := by
  decide

theorem skipsSecondCell_hasZeroAtOne :
    (initialState skipsSecondCell).memory 1 = 0 := by
  decide

theorem skipsSecondCell_firstStep_skipsOne :
    (step (initialState skipsSecondCell)).state.pc = 0 := by
  decide

theorem skipsSecondCell_firstStep_fixed :
    (step (initialState skipsSecondCell)).state = initialState skipsSecondCell := by
  have hOpcode : ((initialState skipsSecondCell).memory
      (initialState skipsSecondCell).pc).val = 13 := by
    decide
  have hTarget : (initialState skipsSecondCell).memory
      (pcAdd (initialState skipsSecondCell).pc 1) =
      (initialState skipsSecondCell).pc := by
    decide
  simp [step, hOpcode, hTarget]

theorem skipsSecondCell_nonhalting_fixedPoint :
    (step (initialState skipsSecondCell)).halted = false ∧
      (step (initialState skipsSecondCell)).state = initialState skipsSecondCell := by
  have hOpcode : ((initialState skipsSecondCell).memory
      (initialState skipsSecondCell).pc).val = 13 := by
    decide
  have hTarget : (initialState skipsSecondCell).memory
      (pcAdd (initialState skipsSecondCell).pc 1) =
      (initialState skipsSecondCell).pc := by
    decide
  simp [step, hOpcode, hTarget]

theorem skipsSecondCell_repeatsAfterFirstStep :
    (step ((step (initialState skipsSecondCell)).state)).state =
      (step (initialState skipsSecondCell)).state := by
  rw [skipsSecondCell_firstStep_fixed]
  rfl

def skipsSecondCellCover : List MachineState := [initialState skipsSecondCell]

theorem skipsSecondCellCover_complete :
    ∀ n, n ≤ skipsSecondCellCover.length →
      stateAfter skipsSecondCell n ∈ skipsSecondCellCover := by
  intro n hn
  have hnBound : n ≤ 1 := by simpa [skipsSecondCellCover] using hn
  cases n with
  | zero => simp [stateAfter, skipsSecondCellCover]
  | succ n =>
      have hnZero : n = 0 := by omega
      subst n
      simp [stateAfter, skipsSecondCellCover, skipsSecondCell_firstStep_fixed]

theorem skipsSecondCell_finiteCover_repeat_or_halt :
    (∃ n, n ≤ skipsSecondCellCover.length ∧
      (step (stateAfter skipsSecondCell n)).halted = true) ∨
    (∃ i j, i < j ∧ j ≤ skipsSecondCellCover.length ∧
      (step (stateAfter skipsSecondCell i)).halted = false ∧
      (step (stateAfter skipsSecondCell j)).halted = false ∧
      stateAfter skipsSecondCell i = stateAfter skipsSecondCell j) :=
  machine_halts_or_repeats_within_cover skipsSecondCell skipsSecondCellCover
    skipsSecondCellCover_complete

end Formalisation
