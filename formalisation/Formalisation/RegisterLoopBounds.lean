import Formalisation.MonotoneOutput

/-!
# A countdown for the length-eight modular register loop

The representative `[1,8,10,14,4,2,4,15]` has a particularly simple
register recurrence. Its round adds R1 to R0, conditionally increments R1
when the sum is zero, subtracts R1, and increments R1 again. This module
analyzes that recurrence independently of instruction decoding.

In coordinates `(counter, phase) = (R0, (R0 + R1) % 16)`, every round
increments the phase; a zero phase also decrements the counter. A natural
number countdown proves the exact first return to counter zero. This is
an explanation of one loop family, not an upper bound over all programs.
-/

namespace Formalisation.RegisterLoopBounds

abbrev Registers := Nibble × Nibble

/-- Register arithmetic of the length-eight loop, including its conditional
increment. The test here is the intermediate ADD result, before SUB. -/
def registerRound (registers : Registers) : Registers :=
  let sum := (registers.1.val + registers.2.val) % 16
  let nextR1 := (registers.2.val + if sum = 0 then 1 else 0) % 16
  (Fin.ofNat 16 (sum + 16 - nextR1), Fin.ofNat 16 (nextR1 + 1))

/-- The second coordinate is the sum tested by JZ at the start of a round. -/
def phaseCoordinates (registers : Registers) : Registers :=
  (registers.1, Fin.ofNat 16 (registers.1.val + registers.2.val))

/-- One round in phase coordinates. This transition does not itself stop
at zero: the loop's final JNZ supplies that stopping condition. -/
def phaseRound (state : Registers) : Registers :=
  (if state.2.val = 0 then Fin.ofNat 16 (state.1.val + 15) else state.1,
    Fin.ofNat 16 (state.2.val + 1))

/-- The phase model is exactly the stated register recurrence for every
possible pair of four-bit registers, not just the initial state. -/
theorem phaseCoordinates_registerRound (registers : Registers) :
    phaseCoordinates (registerRound registers) =
      phaseRound (phaseCoordinates registers) := by
  obtain ⟨a, b⟩ := registers
  by_cases h : (a.val + b.val) % 16 = 0 <;>
    apply Prod.ext <;> apply Fin.ext <;>
    simp [phaseCoordinates, registerRound, phaseRound, h, Fin.val_ofNat] <;> omega

/-- Number of remaining rounds when the counter is nonzero. Phase zero
needs one round for its next decrement; phase `p > 0` needs `17 - p`.
Each further counter decrement costs a full cycle of sixteen rounds. -/
def remainingRounds (state : Registers) : Nat :=
  if state.1.val = 0 then 0
  else 16 * (state.1.val - 1) +
    if state.2.val = 0 then 1 else 17 - state.2.val

theorem remainingRounds_eq_zero_iff (state : Registers) :
    remainingRounds state = 0 ↔ state.1.val = 0 := by
  have := state.1.isLt
  have := state.2.isLt
  simp only [remainingRounds]
  split <;> (try split) <;> omega

/-- Every round before the exit decreases the countdown by exactly one. -/
theorem remainingRounds_phaseRound (state : Registers)
    (hLive : state.1.val ≠ 0) :
    remainingRounds (phaseRound state) + 1 = remainingRounds state := by
  obtain ⟨a, p⟩ := state
  change a.val ≠ 0 at hLive
  have := a.isLt
  have := p.isLt
  by_cases hp : p.val = 0 <;>
    simp [remainingRounds, phaseRound, hp, hLive, Fin.val_ofNat] <;>
    (try split) <;> (try split) <;> omega

/-- Execution after entering the live loop: counter zero is absorbing,
matching the final JNZ's exit rather than beginning another round. -/
def stoppedRound (state : Registers) : Registers :=
  if state.1.val = 0 then state else phaseRound state

def afterRounds : Nat → Registers → Registers
  | 0, state => state
  | rounds + 1, state => stoppedRound (afterRounds rounds state)

theorem remainingRounds_stoppedRound (state : Registers) :
    remainingRounds (stoppedRound state) = remainingRounds state - 1 := by
  by_cases h : state.1.val = 0
  · simp [stoppedRound, h, remainingRounds]
  · have decrement := remainingRounds_phaseRound state h
    simp only [stoppedRound, h, ite_false]
    omega

/-- The countdown gives an exact lifetime from every phase/counter pair. -/
theorem remainingRounds_afterRounds (rounds : Nat) (state : Registers) :
    remainingRounds (afterRounds rounds state) = remainingRounds state - rounds := by
  induction rounds with
  | zero => simp [afterRounds]
  | succ rounds ih =>
      rw [afterRounds, remainingRounds_stoppedRound, ih]
      omega

/-- A general finite-register bound and exact first-exit characterization. -/
theorem afterRounds_counter_zero_iff (rounds : Nat) (state : Registers) :
    (afterRounds rounds state).1.val = 0 ↔ remainingRounds state ≤ rounds := by
  rw [← remainingRounds_eq_zero_iff, remainingRounds_afterRounds]
  omega

/-- From any live register pair the loop exits in at most 240 more rounds. -/
theorem remainingRounds_le_240 (state : Registers) :
    remainingRounds state ≤ 240 := by
  have := state.1.isLt
  have := state.2.isLt
  simp only [remainingRounds]
  split <;> (try split) <;> omega

/-- The initially zero pair must execute one round before the final JNZ
can test it. Its transformed state is then `(15,1)`, with 240 rounds left. -/
theorem initial_round_and_countdown :
    phaseCoordinates (registerRound (0, 0)) = (15, 1) ∧
    remainingRounds (15, 1) = 240 := by
  constructor <;> rfl

/-- The representative recurrence first returns to R0 zero on round 241:
one mandatory initial round, followed by exactly 240 live rounds. -/
theorem lengthEight_first_zero (rounds : Nat) :
    (afterRounds rounds (phaseCoordinates (registerRound (0, 0)))).1.val = 0 ↔
      240 ≤ rounds := by
  rw [afterRounds_counter_zero_iff, initial_round_and_countdown.1]
  exact Iff.rfl

/-- The same exit convention expressed in the original registers. -/
def stoppedRegisterRound (registers : Registers) : Registers :=
  if registers.1.val = 0 then registers else registerRound registers

def afterRegisterRounds : Nat → Registers → Registers
  | 0, registers => registers
  | rounds + 1, registers => stoppedRegisterRound (afterRegisterRounds rounds registers)

theorem phaseCoordinates_stoppedRegisterRound (registers : Registers) :
    phaseCoordinates (stoppedRegisterRound registers) =
      stoppedRound (phaseCoordinates registers) := by
  by_cases h : registers.1.val = 0
  · simp [stoppedRegisterRound, stoppedRound, phaseCoordinates, h]
  · simp only [stoppedRegisterRound, h, ite_false, stoppedRound, phaseCoordinates,
      ite_false]
    exact phaseCoordinates_registerRound registers

theorem phaseCoordinates_afterRegisterRounds (rounds : Nat) (registers : Registers) :
    phaseCoordinates (afterRegisterRounds rounds registers) =
      afterRounds rounds (phaseCoordinates registers) := by
  induction rounds with
  | zero => rfl
  | succ rounds ih =>
      rw [afterRegisterRounds, phaseCoordinates_stoppedRegisterRound, ih, afterRounds]

/-- Exact first exit for the original ADD/conditional-INC/SUB/INC
recurrence. The first round is mandatory even though both registers start
at zero; subsequent rounds stop as soon as their R0 result is zero. -/
theorem registerRecurrence_first_zero (rounds : Nat) :
    (afterRegisterRounds rounds (registerRound (0, 0))).1.val = 0 ↔
      240 ≤ rounds := by
  have coordinates := phaseCoordinates_afterRegisterRounds rounds (registerRound (0, 0))
  have counter := congrArg (fun state : Registers => state.1.val) coordinates
  change (afterRegisterRounds rounds (registerRound (0, 0))).1.val =
    (afterRounds rounds (phaseCoordinates (registerRound (0, 0)))).1.val at counter
  rw [counter, lengthEight_first_zero]

/-- A fixed-width print repeated `count` times has the expected score. -/
theorem outputCharacterScore_replicate (count : Nat) (value : Nibble) :
    outputCharacterScore (List.replicate count value) =
      count * decimalCharacterCount value := by
  induction count with
  | zero => simp [outputCharacterScore]
  | succ count ih =>
      simp only [outputCharacterScore, List.replicate_succ, List.map_cons,
        List.sum_cons] at ih ⊢
      rw [ih, Nat.succ_mul, Nat.add_comm]

/-- Counting one two-character print per round gives the reported 482.
This computes the score of a specified output list; the concrete execution
certificate below supplies the link to machine decoding. -/
theorem lengthEight_output_score (value : Nibble) (hWidth : 10 ≤ value.val) :
    outputCharacterScore (List.replicate 241 value) = 482 := by
  rw [outputCharacterScore_replicate]
  simp [decimalCharacterCount, show ¬ value.val < 10 by omega]

/-- Check a halting result's complete reversed output list. -/
def haltedWithOutput (result : RunResult) (expected : List Nibble) : Bool :=
  match result with
  | .halted _ outputRev => outputRev == expected
  | .outOfFuel _ _ => false

set_option maxRecDepth 100000 in
set_option maxHeartbeats 2000000 in
/-- Kernel evaluation of the concrete representative confirms the decoding
and output behavior in addition to the abstract recurrence argument above.
The list is reversed by `runFuel`; all emitted values here are the same. -/
theorem representative_machine_execution :
    haltedWithOutput
      (runFuel 1463 (initialState [1, 8, 10, 14, 4, 2, 4, 15]) [])
      (List.replicate 241 10) = true := by
  decide

private theorem haltedWithOutput_score (result : RunResult) (expected : List Nibble)
    (h : haltedWithOutput result expected = true) :
    match result with
    | .halted _ outputRev => outputCharacterScore outputRev = outputCharacterScore expected
    | .outOfFuel _ _ => False := by
  cases result with
  | halted state outputRev =>
      have outputs : outputRev = expected := by simpa [haltedWithOutput] using h
      change outputCharacterScore outputRev = outputCharacterScore expected
      rw [outputs]
  | outOfFuel state outputRev => simp [haltedWithOutput] at h

set_option maxRecDepth 100000 in
/-- Consequently this actual eight-cell program halts with score 482.
This is an attainable score, without a global optimality claim. -/
theorem representative_machine_score :
    match runFuel 1463 (initialState [1, 8, 10, 14, 4, 2, 4, 15]) [] with
    | .halted _ outputRev => outputCharacterScore outputRev = 482
    | .outOfFuel _ _ => False := by
  have score := haltedWithOutput_score _ _ representative_machine_execution
  rw [lengthEight_output_score 10 (by decide)] at score
  exact score

end Formalisation.RegisterLoopBounds
