import Formalisation.MonotoneOutput

/-!
# Decimal output score classes

These results concern the score of emitted values. A program cell can also be
executed as an instruction or fetched as data, so score equivalence of two
values alone says nothing about the behavior of programs containing them.
-/

namespace Formalisation

/-- Values below ten form the one-character class; the other nibble values
form the two-character class. -/
def sameOutputScoreClass (a b : Nibble) : Prop :=
  (a.val < 10 ↔ b.val < 10)

/-- Corresponding entries of two output traces belong to the same score class. -/
inductive PointwiseOutputScoreClass : List Nibble → List Nibble → Prop where
  | nil : PointwiseOutputScoreClass [] []
  | cons {a b as bs} : sameOutputScoreClass a b →
      PointwiseOutputScoreClass as bs →
      PointwiseOutputScoreClass (a :: as) (b :: bs)

theorem decimalCharacterCount_eq_one_iff (value : Nibble) :
    decimalCharacterCount value = 1 ↔ value.val < 10 := by
  simp only [decimalCharacterCount]
  split <;> omega

theorem decimalCharacterCount_eq_two_iff (value : Nibble) :
    decimalCharacterCount value = 2 ↔ 10 ≤ value.val := by
  simp only [decimalCharacterCount]
  split <;> omega

theorem decimalCharacterCount_eq_iff_sameOutputScoreClass (a b : Nibble) :
    decimalCharacterCount a = decimalCharacterCount b ↔
      sameOutputScoreClass a b := by
  unfold decimalCharacterCount sameOutputScoreClass
  split <;> split <;> simp_all <;> omega

/-- Pointwise class-preserving replacement preserves the score of an output
trace. This assumes the two traces already have corresponding output events. -/
theorem outputCharacterScore_eq_of_forall₂_sameOutputScoreClass
    {as bs : List Nibble}
    (h : PointwiseOutputScoreClass as bs) :
    outputCharacterScore as = outputCharacterScore bs := by
  induction h with
  | nil => rfl
  | @cons a b as bs hab hrest ih =>
      simp only [outputCharacterScore, List.map_cons, List.sum_cons] at ih ⊢
      rw [(decimalCharacterCount_eq_iff_sameOutputScoreClass a b).mpr hab, ih]

theorem outputCharacterScore_map_of_sameOutputScoreClass
    (values : List Nibble) (replace : Nibble → Nibble)
    (h : ∀ value, sameOutputScoreClass value (replace value)) :
    outputCharacterScore values =
      outputCharacterScore (values.map replace) := by
  apply outputCharacterScore_eq_of_forall₂_sameOutputScoreClass
  induction values with
  | nil => exact .nil
  | cons value values ih => exact .cons (h value) ih

/-- Any finite list made of two-character values scores twice its length. -/
theorem outputCharacterScore_eq_two_mul_length_of_all_ge_ten
    (values : List Nibble) (h : ∀ value ∈ values, 10 ≤ value.val) :
    outputCharacterScore values = 2 * values.length := by
  induction values with
  | nil => rfl
  | cons value values ih =>
      have hv : decimalCharacterCount value = 2 :=
        (decimalCharacterCount_eq_two_iff value).mpr (h value (by simp))
      have ht : ∀ v ∈ values, 10 ≤ v.val := by
        intro v hvMem
        exact h v (by simp [hvMem])
      simp only [outputCharacterScore, List.map_cons, List.sum_cons,
        List.length_cons, hv]
      change 2 + outputCharacterScore values = 2 * (values.length + 1)
      rw [ih ht]
      omega

/-- The reported length-two winner family `[8, x]`, for `x = 10..15`, has
one-value output traces `[x]`. This proves those traces have the same score;
it does not prove that the corresponding programs produce those traces. -/
theorem lengthTwo_winner_trace_score (x : Nibble) (hx : 10 ≤ x.val) :
    outputCharacterScore [x] = 2 := by
  simp [outputCharacterScore, (decimalCharacterCount_eq_two_iff x).mpr hx]

/-- The machine executes a two-cell output program and halts on its first
zero-padded cell. The final state depends on `x`, but the control path does not. -/
theorem lengthTwo_outputOperand_run (x : Nibble) :
    ∃ finalState,
      runFuel 2 (initialState [8, x]) [] = .halted finalState [x] := by
  let s := initialState [8, x]
  have hFirst : step s = ⟨{s with pc := 2}, false, some x⟩ := by
    rfl
  have hOpcode : (({s with pc := 2} : MachineState).memory
      ({s with pc := 2} : MachineState).pc).val = 0 := by
    simp [s, initialState]
  have hHalt := zeroOpcodeHalts ({s with pc := 2} : MachineState) hOpcode
  have hOutput : (step ({s with pc := 2} : MachineState)).output = none := by
    rfl
  refine ⟨(step ({s with pc := 2} : MachineState)).state, ?_⟩
  change runFuel 2 s [] =
    .halted (step ({s with pc := 2} : MachineState)).state [x]
  rw [runFuel, hFirst]
  simp only [Bool.false_eq_true, ↓reduceIte]
  rw [runFuel, hHalt, hOutput]
  rfl

/-- Every `x` from 10 through 15 gives a halting length-two program with
the same score of two characters. The emitted values themselves differ. -/
theorem lengthTwo_outputOperand_score (x : Nibble) (hx : 10 ≤ x.val) :
    ∃ finalState,
      runFuel 2 (initialState [8, x]) [] = .halted finalState [x] ∧
      outputCharacterScore [x] = 2 := by
  obtain ⟨finalState, hRun⟩ := lengthTwo_outputOperand_run x
  exact ⟨finalState, hRun, lengthTwo_winner_trace_score x hx⟩

end Formalisation
