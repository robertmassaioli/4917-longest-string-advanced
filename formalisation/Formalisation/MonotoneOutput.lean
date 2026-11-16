import Formalisation.Machine

/-!
# Output bounds for monotonically increasing executions

This is a reusable accounting lemma for the longest-output argument. A
monotone execution that starts at PC 0 can visit each instruction address at
most once. An OUTPUT instruction advances by two cells and emits at most two
decimal characters, so its character contribution is bounded by the PC
distance it consumes. Other forward steps contribute no characters.

`MonotoneOutputTrace` records just those facts. The next step is to connect an
actual machine execution to this trace, and to establish score lower bounds for
the known loop-using winners.
-/

namespace Formalisation

/-- Number of decimal characters printed by one nibble. -/
def decimalCharacterCount (value : Nibble) : Nat :=
  if value.val < 10 then 1 else 2

theorem decimalCharacterCount_le_two (value : Nibble) :
    decimalCharacterCount value ≤ 2 := by
  simp only [decimalCharacterCount]
  split <;> omega

/-- Character score of a finite sequence of emitted nibble values. -/
def outputCharacterScore (values : List Nibble) : Nat :=
  (values.map decimalCharacterCount).sum

theorem outputCharacterScore_le_two_mul_length (values : List Nibble) :
    outputCharacterScore values ≤ 2 * values.length := by
  induction values with
  | nil => simp [outputCharacterScore]
  | cons value values ih =>
      simp [outputCharacterScore, List.map_cons, List.sum_cons,
        List.length_cons] at ih ⊢
      have hValue := decimalCharacterCount_le_two value
      omega

/-- Every concrete machine output event is an OUTPUT instruction, which
advances the PC by two cells. This is the machine-level fact used by the
trace's local output budget. -/
theorem outputStep_advances_two (s : MachineState) (value : Nibble)
    (hOutput : (step s).output = some value) :
    (step s).state.pc = pcAdd s.pc 2 := by
  have hOpcode : (s.memory s.pc).val = 8 := by
    simp only [step] at hOutput
    split at hOutput <;> simp_all
  simp [step, hOpcode]

/-- A finite run whose PC strictly increases and stays below `limit`.
`emitted` is the number of output characters contributed by the step. Its
local budget is bounded by twice the PC distance; this captures OUTPUT's
two-cell encoding and two-character maximum. -/
inductive MonotoneOutputTrace (limit : Nat) : Nat → Nat → Prop where
  | done {pc : Nat} :
      pc < limit → MonotoneOutputTrace limit pc 0
  | next {pc nextPC emitted restScore : Nat} :
      pc < nextPC →
      nextPC < limit →
      emitted ≤ 2 * (nextPC - pc) →
      MonotoneOutputTrace limit nextPC restScore →
      MonotoneOutputTrace limit pc (emitted + restScore)

/-- A monotonically increasing run starting at PC 0 prints at most twice its
program length in characters. -/
theorem monotoneOutputTrace_score_bound {limit score : Nat}
    (trace : MonotoneOutputTrace limit 0 score) :
    score ≤ 2 * limit := by
  have bound : ∀ {pc score}, MonotoneOutputTrace limit pc score →
      score ≤ 2 * (limit - pc) := by
    intro pc score hTrace
    induction hTrace with
    | done hPC => simp
    | @next pc nextPC emitted restScore hAdvance hBound hRest ih =>
        omega
  simpa using bound trace

/-- If a known program of this length prints more than the monotone bound,
then no monotonically increasing execution can tie it. This is the comparison
lemma to apply once the relevant lower bound on the longest score is proved. -/
theorem monotoneOutputTrace_cannot_match_score {limit score bestScore : Nat}
    (trace : MonotoneOutputTrace limit 0 score)
    (hBest : 2 * limit < bestScore) :
    score < bestScore := by
  have hBound := monotoneOutputTrace_score_bound trace
  omega

end Formalisation
