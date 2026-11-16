import Formalisation.Termination
import Formalisation.MonotoneOutput

/-! Concrete-machine certificates for static pre-run checks 1–5. -/
namespace Formalisation.PreRunChecksA

/-- Timeouts remain unknown, rather than being called non-halting. -/
def haltedOutput : RunResult → Option (List Nibble)
  | .halted _ output => some output
  | .outOfFuel _ _ => none

/-- Check 1: an entry HALT prints nothing for any positive fuel. -/
theorem entryHalt_emptyOutput (program : List Nibble) (fuel : Nat)
    (hFuel : 0 < fuel)
    (hEntry : ((initialState program).memory 0).val = 0) :
    haltedOutput (runFuel fuel (initialState program) []) = some [] := by
  obtain ⟨final, hFinal⟩ :=
    runFuel_zeroOpcode_halts (initialState program) fuel hFuel hEntry
  rw [hFinal]
  rfl

theorem emptyOutput_below_positive (incumbent : Nat) (h : 0 < incumbent) :
    outputCharacterScore [] < incumbent := by
  simpa [outputCharacterScore] using h

/-- No cell, including operands and padding, contains a STORE opcode. -/
def NoStore (memory : Memory) : Prop :=
  ∀ address, (memory address).val ≠ 11 ∧ (memory address).val ≠ 12

def NoOutputOrStore (memory : Memory) : Prop :=
  NoStore memory ∧ ∀ address, (memory address).val ≠ 8

theorem noStore_step_preserves_memory (state : MachineState)
    (h : NoStore state.memory) : (step state).state.memory = state.memory := by
  have h11 := (h state.pc).1
  have h12 := (h state.pc).2
  simp only [step]
  split <;> simp_all

theorem notOutput_step_emits_none (state : MachineState)
    (h : (state.memory state.pc).val ≠ 8) : (step state).output = none := by
  simp only [step]
  split <;> simp_all

/-- Check 2: no OUTPUT or STORE byte means no execution can add any output. -/
theorem noOutputOrStore_runFuel (fuel : Nat) (state : MachineState)
    (output : List Nibble) (h : NoOutputOrStore state.memory) :
    match runFuel fuel state output with
    | .halted _ result => result = output
    | .outOfFuel _ result => result = output := by
  induction fuel generalizing state output with
  | zero => rfl
  | succ fuel ih =>
      have hNone := notOutput_step_emits_none state (h.2 state.pc)
      have hMemory := noStore_step_preserves_memory state h.1
      have hNext : NoOutputOrStore (step state).state.memory := by
        rw [hMemory]
        exact h
      simp only [runFuel, hNone]
      by_cases hHalt : (step state).halted = true
      · simp [hHalt]
      · simp only [hHalt]
        exact ih (step state).state output hNext

/-- Static analyses must establish an initial fact and preserve it at each step. -/
def StepInvariant (property : MachineState → Prop) : Prop :=
  ∀ state, property state → property (step state).state

/-- Check 3's general soundness bridge: an invariant without HALT states
rules out eventual halting of the concrete machine. -/
theorem invariant_without_halt_cannot_halt (property : MachineState → Prop)
    (hClosed : StepInvariant property)
    (hNonzero : ∀ state, property state → (state.memory state.pc).val ≠ 0)
    (state : MachineState) (hInitial : property state) :
    ¬ EventuallyHalts state := by
  intro hHalts
  induction hHalts with
  | halt hZero => exact hNonzero _ hInitial hZero
  | next hNonzeroStep hRest ih => exact ih (hClosed _ hInitial)

/-- HALT flags and the big-step termination relation agree on concrete steps. -/
theorem haltedFlag_iff_zero (state : MachineState) :
    (step state).halted = true ↔ (state.memory state.pc).val = 0 := by
  simp only [step]
  split <;> simp_all

/-- A bounded run returning HALT supplies the termination witness needed by
all nonhalting rejection certificates in this module. -/
theorem runFuel_halted_eventuallyHalts (fuel : Nat) (state final : MachineState)
    (output result : List Nibble)
    (hRun : runFuel fuel state output = .halted final result) :
    EventuallyHalts state := by
  induction fuel generalizing state final output result with
  | zero => simp [runFuel] at hRun
  | succ fuel ih =>
    by_cases hHalt : (step state).halted = true
    · exact .halt ((haltedFlag_iff_zero state).mp hHalt)
    · have hNonzero : (state.memory state.pc).val ≠ 0 := by
        intro hZero
        exact hHalt ((haltedFlag_iff_zero state).mpr hZero)
      apply EventuallyHalts.next hNonzero
      cases hOutput : (step state).output with
      | none =>
        simp only [runFuel, hOutput, hHalt] at hRun
        exact ih _ _ _ _ hRun
      | some value =>
        simp only [runFuel, hOutput, hHalt] at hRun
        exact ih _ _ _ _ hRun

/-- A finite conservative PC certificate. Quantification over all register
values covers every conditional branch; excluding STORE preserves memory. -/
def ClosedPCRegion (memory : Memory) (region : PC → Prop) : Prop :=
  (∀ address, region address →
    (memory address).val ≠ 0 ∧
    (memory address).val ≠ 11 ∧ (memory address).val ≠ 12) ∧
  (∀ address r0 r1, region address →
    region (step ⟨memory, r0, r1, address⟩).state.pc)

/-- Check 3 with a static PC region, including the bridge to concrete steps. -/
theorem closedPCRegion_cannot_halt (memory : Memory) (region : PC → Prop)
    (hRegion : ClosedPCRegion memory region)
    (state : MachineState) (hMemory : state.memory = memory)
    (hPC : region state.pc) : ¬ EventuallyHalts state := by
  apply invariant_without_halt_cannot_halt
    (fun state => state.memory = memory ∧ region state.pc) ?_ ?_ state ⟨hMemory, hPC⟩
  · intro state hState
    obtain ⟨hMem, hPC⟩ := hState
    have hCode := hRegion.1 state.pc hPC
    have h11 : (state.memory state.pc).val ≠ 11 := by simpa [hMem] using hCode.2.1
    have h12 : (state.memory state.pc).val ≠ 12 := by simpa [hMem] using hCode.2.2
    have hKeep : (step state).state.memory = state.memory := by
      simp only [step]
      split <;> simp_all
    refine ⟨hKeep.trans hMem, ?_⟩
    cases state with
    | mk mem r0 r1 pc =>
      simp only at hMem hPC ⊢
      subst mem
      exact hRegion.2 pc r0 r1 hPC
  · intro state hState
    simpa [hState.1] using (hRegion.1 state.pc hState.2).1

/-- Check 4: exact branch outcomes follow from established register facts. -/
theorem conditionalJump_outcomes (state : MachineState) :
    ((state.memory state.pc).val = 14 → state.r0.val = 0 →
      (step state).state.pc = state.memory (pcAdd state.pc 1)) ∧
    ((state.memory state.pc).val = 14 → state.r0.val ≠ 0 →
      (step state).state.pc = pcAdd state.pc 2) ∧
    ((state.memory state.pc).val = 15 → state.r0.val = 0 →
      (step state).state.pc = pcAdd state.pc 2) ∧
    ((state.memory state.pc).val = 15 → state.r0.val ≠ 0 →
      (step state).state.pc = state.memory (pcAdd state.pc 1)) := by
  refine ⟨?_, ?_, ?_, ?_⟩ <;> intro hOpcode hRegister <;>
    simp [step, hOpcode, hRegister]

/-- Repeated concrete steps, used only to state invariant preservation. -/
def advance : Nat → MachineState → MachineState
  | 0, state => state
  | count + 1, state => (step (advance count state)).state

/-- An invariant's register facts continue to hold after any number of steps. -/
theorem invariant_iterates (property : MachineState → Prop)
    (hClosed : StepInvariant property) (state : MachineState)
    (hInitial : property state) (count : Nat) :
    property (advance count state) := by
  induction count with
  | zero => exact hInitial
  | succ count ih => exact hClosed _ ih

/-- Check 5's general immutable jump-trap certificate. Every address in the
region is an unconditional jump whose operand targets another region address.
This covers arbitrarily many jump nodes, including closed jump cycles. -/
theorem unconditionalJumpRegion_cannot_halt (memory : Memory) (region : PC → Prop)
    (hOpcodes : ∀ address, region address → (memory address).val = 13)
    (hTargets : ∀ address, region address → region (memory (pcAdd address 1)))
    (state : MachineState) (hMemory : state.memory = memory)
    (hEntry : region state.pc) : ¬ EventuallyHalts state := by
  apply closedPCRegion_cannot_halt memory region ?_ state hMemory hEntry
  constructor
  · intro address hAddress
    have hOpcode := hOpcodes address hAddress
    omega
  · intro address r0 r1 hAddress
    simpa [step, hOpcodes address hAddress] using hTargets address hAddress

/-- Check 5: an unconditional jump to its own opcode cannot halt. -/
theorem selfJump_cannot_halt (state : MachineState)
    (hOpcode : (state.memory state.pc).val = 13)
    (hTarget : state.memory (pcAdd state.pc 1) = state.pc) :
    ¬ EventuallyHalts state := by
  have hStep : (step state).state = state := by
    simp [step, hOpcode, hTarget]
  apply invariant_without_halt_cannot_halt (fun other => other = state) ?_ ?_ state rfl
  · intro other hOther
    subst other
    exact hStep
  · intro other hOther
    subst other
    omega

theorem entry13zero_cannot_halt :
    ¬ EventuallyHalts (initialState [13, 0]) := by
  apply selfJump_cannot_halt <;> rfl

/-- Omitting STORE from check 2 is unsafe: STORE can manufacture OUTPUT. -/
def manufacturesOutput : List Nibble :=
  [3, 3, 3, 3, 3, 3, 3, 3, 11, 10, 0, 10, 0]

theorem manufacturesOutput_noRaw8 : (8 : Nibble) ∉ manufacturesOutput := by decide

theorem manufacturesOutput_prints :
    haltedOutput (runFuel 11 (initialState manufacturesOutput) []) = some [10] := by
  rfl

/-- A raw zero may be an operand rather than a reachable HALT instruction. -/
theorem rawZero_does_not_ensure_halting :
    (0 : Nibble) ∈ ([13, 0] : List Nibble) ∧
      ¬ EventuallyHalts (initialState [13, 0]) := by
  exact ⟨by simp, entry13zero_cannot_halt⟩

/-- Ignoring writable code is also unsafe for HALT reachability: the entire
initial 16-cell memory is nonzero, but STORE creates the HALT that is reached. -/
def manufacturesHalt : List Nibble :=
  [11, 3, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7]

theorem manufacturesHalt_noInitialZero :
    ∀ address, ((initialState manufacturesHalt).memory address).val ≠ 0 := by
  decide

theorem manufacturesHalt_halts :
    haltedOutput (runFuel 3 (initialState manufacturesHalt) []) = some [] := by
  rfl

/-- Initial R0 = 0 does not justify treating all later JZs as taken. -/
theorem initialZero_does_not_fix_branches :
    haltedOutput (runFuel 4 (initialState [3, 14, 0, 8, 10, 0]) []) = some [10] := by
  rfl

end Formalisation.PreRunChecksA
