import Formalisation.InstructionCommutation

/-!
# Certified instruction swaps

This module separates two claims which are easy to conflate:

* two decoded instruction effects commute when executed consecutively;
* swapping their encoded bytes in an arbitrary program preserves its behavior.

The first is proved here for the register instruction family and follows from
the observable-effect lemmas for literal OUTPUT and LOAD in
`InstructionCommutation`. The second needs control-flow and memory conditions:
the changed locations must be reached in the intended order, no jump may enter
the middle of the pair, and no earlier STORE may modify either instruction.
-/
namespace Formalisation.SafeSwaps

open InstructionCommutation

/-- Two observable instruction effects commute on every possible data state. -/
def ObservableCommute {State Output : Type}
    (first second : ObservableEffect State Output) : Prop :=
  ∀ state,
    sequenceEffects first second state =
      sequenceEffects second first state

/-- Swapping certified adjacent effects preserves both final data and the
exact output sequence. This theorem is deliberately about decoded effects;
encoded-program safety is stated separately below. -/
theorem certified_effect_swap {State Output : Type}
    (first second : ObservableEffect State Output)
    (hCommute : ObservableCommute first second) (state : State) :
    sequenceEffects first second state =
      sequenceEffects second first state :=
  hCommute state

/-- A register instruction represented as a silent observable effect. -/
def registerEffect (instruction : RegisterInstruction) :
    ObservableEffect Registers Nibble :=
  silentEffect (fun registers => applyRegisterInstruction instruction registers)

/-- The existing universal Lean commutation proof lifts directly to observable
execution: all registers agree and neither order emits output. -/
theorem registerEffects_commute (first second : RegisterInstruction)
    (hCommute : Commute first second) :
    ObservableCommute (registerEffect first) (registerEffect second) := by
  intro registers
  simp [sequenceEffects, registerEffect, silentEffect, hCommute registers]

/-- Every pair accepted by the exhaustive checker has a certified effect swap. -/
theorem checked_register_pair_is_safe (first second : RegisterInstruction)
    (hCheck : checkCommute first second = true) :
    ObservableCommute (registerEffect first) (registerEffect second) :=
  registerEffects_commute first second
    ((checkCommute_iff_Commute first second).mp hCheck)

/-- Example: INC R0 and INC R1 are safe to exchange as adjacent decoded
register effects for every starting register state. -/
theorem incR0_incR1_safe :
    ObservableCommute (registerEffect .incR0) (registerEffect .incR1) :=
  registerEffects_commute .incR0 .incR1 inc0_inc1_commute

/-- The length-10 winner's SUB R0 / INC R0 tail pair commutes. -/
theorem subR0_incR0_safe :
    ObservableCommute (registerEffect .subR0) (registerEffect .incR0) := by
  apply registerEffects_commute
  apply r0Arithmetic_pairs_commute
  · change True
    trivial
  · change True
    trivial

/-- The other recurring length-10 tail pair, ADD R0 / DEC R0, commutes. -/
theorem addR0_decR0_safe :
    ObservableCommute (registerEffect .addR0) (registerEffect .decR0) := by
  apply registerEffects_commute
  apply r0Arithmetic_pairs_commute
  · change True
    trivial
  · change True
    trivial

/-- Example: ADD R0 and INC R1 are not safe to exchange for all states. -/
theorem addR0_incR1_not_safe :
    ¬ ObservableCommute (registerEffect .addR0) (registerEffect .incR1) := by
  intro h
  have hRegisters := congrArg Prod.fst
    (h ((0 : Nibble), (0 : Nibble)))
  have hEffects := add_inc1_counterexample
  simp [sequenceEffects, registerEffect, silentEffect] at hRegisters
  exact hEffects hRegisters

/-- Literal output may be exchanged with any silent data-state effect once
both instructions and their operands have already been decoded. -/
theorem literalOutput_safe_with_silent {State Output : Type}
    (value : Output) (update : State → State) :
    ObservableCommute (literalOutput value) (silentEffect update) := by
  intro state
  exact literalOutput_commutes_with_silent value update state

/-- A decoded LOAD R0 and LOAD R1 commute, including their final register
values, when memory is unchanged by both loads. -/
theorem loadR0_loadR1_safe (r0Address r1Address : PC) :
    ObservableCommute
      (silentEffect (Output := Nibble) (loadR0Data r0Address))
      (silentEffect (Output := Nibble) (loadR1Data r1Address)) := by
  intro data
  exact loadR0_loadR1_commute r0Address r1Address data

/-- A code-layout counterexample: the local effects “print 5” and “halt” do
not form a safe whole-program swap when execution starts at their first cell.
The helper stops immediately when either step halts, matching `runFuel`. -/
def executeAtMostTwoUntilHalt (state : MachineState) :
    MachineState × List Nibble :=
  let first := step state
  let firstOutput := match first.output with
    | none => []
    | some value => [value]
  if first.halted then
    (first.state, firstOutput)
  else
    let second := step first.state
    let secondOutput := match second.output with
      | none => []
      | some value => [value]
    (second.state, firstOutput ++ secondOutput)

/-- The original emits 5; swapping the blocks makes HALT execute first. -/
theorem swapping_output_with_halt_changes_program_behavior :
    (executeAtMostTwoUntilHalt (initialState [8, 5, 0])).2 = [5] ∧
      (executeAtMostTwoUntilHalt (initialState [0, 8, 5])).2 = [] := by
  decide

end Formalisation.SafeSwaps
