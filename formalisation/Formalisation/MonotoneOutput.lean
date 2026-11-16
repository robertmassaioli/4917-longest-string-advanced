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

/-- Character score emitted by one concrete machine step. -/
def stepOutputCharacterScore (result : StepResult) : Nat :=
  match result.output with
  | none => 0
  | some value => decimalCharacterCount value

/-- In any strictly increasing machine step, the output (if any) fits within
twice the distance advanced by the PC. OUTPUT advances by two; all other
instructions emit nothing. -/
theorem stepOutputCharacterScore_le_pcDistance (s : MachineState)
    (hProgress : s.pc.val < (step s).state.pc.val) :
    stepOutputCharacterScore (step s) ≤
      2 * ((step s).state.pc.val - s.pc.val) := by
  cases hOutput : (step s).output with
  | none => simp [stepOutputCharacterScore, hOutput]
  | some value =>
      have hAdvance := outputStep_advances_two s value hOutput
      have hPC : (step s).state.pc.val = (s.pc.val + 2) % 16 := by
        rw [hAdvance]
        simp [pcAdd, Fin.val_ofNat]
      simp only [stepOutputCharacterScore, hOutput]
      have hChars := decimalCharacterCount_le_two value
      omega

/-- A finite execution of the concrete machine in which every step strictly
increases the PC and every visited PC stays below `limit`. The score is the
number of decimal characters emitted before HALT. -/
inductive MonotoneMachineRun (limit : Nat) : MachineState → Nat → Prop where
  | halt {state : MachineState} :
      state.pc.val < limit →
      (step state).halted = true →
      MonotoneMachineRun limit state 0
  | next {state : MachineState} {restScore : Nat} :
      state.pc.val < (step state).state.pc.val →
      (step state).state.pc.val < limit →
      (step state).halted = false →
      MonotoneMachineRun limit (step state).state restScore →
      MonotoneMachineRun limit state
        (stepOutputCharacterScore (step state) + restScore)

/-- Every monotone concrete machine run starting at PC 0 prints at most twice
the program length in decimal characters. -/
theorem monotoneMachineRun_score_bound {limit score : Nat}
    {state : MachineState}
    (hStart : state.pc.val = 0)
    (run : MonotoneMachineRun limit state score) :
    score ≤ 2 * limit := by
  have bound : ∀ {state score}, MonotoneMachineRun limit state score →
      score ≤ 2 * (limit - state.pc.val) := by
    intro state score hRun
    induction hRun with
    | halt hPC hHalt => simp
    | @next state restScore hProgress hNextPC hNotHalt hRest ih =>
        have hLocal := stepOutputCharacterScore_le_pcDistance state hProgress
        omega
  have hBound := bound run
  rw [hStart] at hBound
  simpa using hBound

/-- A monotone machine run cannot tie a known score that is strictly above
the monotone upper bound. -/
theorem monotoneMachineRun_cannot_match_score {limit score bestScore : Nat}
    {state : MachineState}
    (hStart : state.pc.val = 0)
    (run : MonotoneMachineRun limit state score)
    (hBest : 2 * limit < bestScore) :
    score < bestScore := by
  have hBound := monotoneMachineRun_score_bound hStart run
  omega

/-- The exhaustive-search explainers report these best scores for lengths
4–8. Lean checks here that each reported score exceeds the monotone-run
bound. The search results themselves are not yet derived inside Lean. -/
theorem reportedBestScoresExceedMonotoneBound :
    2 * 4 < 32 ∧
    2 * 5 < 62 ∧
    2 * 6 < 93 ∧
    2 * 7 < 172 ∧
    2 * 8 < 482 := by
  omega

end Formalisation
