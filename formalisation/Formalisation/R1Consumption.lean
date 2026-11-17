import Formalisation.Machine

/-!
# R1 consumption tracking

This formalizes the historical rule used by the Haskell generalizer. An
executed STORE R1 consumes R1 directly. STORE R0, JZ, and JNZ consume R1
when an earlier ADD or SUB has marked R0 as containing an R0/R1 combination.
The combination flag is sticky, matching the current Haskell implementation.
-/

namespace Formalisation.R1Consumption

/-- The two pieces of history tracked by the generalizer. -/
structure Audit where
  combinationSeen : Bool := false
  r1Consumed : Bool := false
  deriving DecidableEq, Repr

def isAddOrSub (opcode : Nat) : Bool := opcode == 1 || opcode == 2

def consumesR0 (opcode : Nat) : Bool :=
  opcode == 11 || opcode == 14 || opcode == 15

def consumesR1Directly (opcode : Nat) : Bool := opcode == 12

/-- Update the historical flags after observing one executed opcode. -/
def observeOpcode (audit : Audit) (opcode : Nat) : Audit :=
  { combinationSeen := audit.combinationSeen || isAddOrSub opcode
    r1Consumed := audit.r1Consumed || consumesR1Directly opcode ||
      (audit.combinationSeen && consumesR0 opcode) }

/-- Fold the analyzer's rule over an opcode history. -/
def auditOpcodes (audit : Audit) : List Nat → Audit
  | [] => audit
  | opcode :: rest => auditOpcodes (observeOpcode audit opcode) rest

/-- Whether an opcode history contains a rule-triggering use of R1,
considering whether a combination had already been seen before each opcode. -/
def hasR1Consumption (combinationSeen : Bool) : List Nat → Bool
  | [] => false
  | opcode :: rest =>
      consumesR1Directly opcode ||
        (combinationSeen && consumesR0 opcode) ||
        hasR1Consumption (combinationSeen || isAddOrSub opcode) rest

/-- The audit flag is true exactly when it was already true or the opcode
history contains a direct STORE R1 or a qualifying use of a combined R0. -/
theorem auditOpcodes_consumed_iff
    (audit : Audit) (opcodes : List Nat) :
    (auditOpcodes audit opcodes).r1Consumed = true ↔
      audit.r1Consumed = true ∨ hasR1Consumption audit.combinationSeen opcodes = true := by
  induction opcodes generalizing audit with
  | nil => simp [auditOpcodes, hasR1Consumption]
  | cons opcode rest ih =>
      simp only [auditOpcodes, hasR1Consumption]
      rw [ih]
      simp only [observeOpcode, Bool.or_eq_true, Bool.and_eq_true]
      simp [or_assoc]

/-- The opcode executed at a machine state is the nibble at its PC. -/
def currentOpcode (state : MachineState) : Nat :=
  (state.memory state.pc).val

/-- Execute one machine step while updating the consumption audit from the
opcode at the pre-step PC. -/
def auditedStep (state : MachineState) (audit : Audit) : MachineState × Audit :=
  ((step state).state, observeOpcode audit (currentOpcode state))

theorem auditedStep_uses_preStepOpcode
    (state : MachineState) (audit : Audit) :
    (auditedStep state audit).2 =
      observeOpcode audit ((state.memory state.pc).val) := by
  rfl

/-- The opcode history of the actual execution prefix, stopping immediately
after the step that halts. -/
def executedOpcodesFuel : Nat → MachineState → List Nat
  | 0, _ => []
  | fuel + 1, state =>
      let opcode := currentOpcode state
      let result := step state
      if result.halted then [opcode]
      else opcode :: executedOpcodesFuel fuel result.state

/-- Run the machine for at most `fuel` steps while accumulating the same
consumption metadata as the Haskell trace analyzer. -/
def runAuditFuel : Nat → MachineState → Audit → Audit
  | 0, _, audit => audit
  | fuel + 1, state, audit =>
      let result := step state
      let audit := observeOpcode audit (currentOpcode state)
      if result.halted then audit
      else runAuditFuel fuel result.state audit

/-- The audit accumulated during execution equals auditing the opcodes that
the machine actually executed. -/
theorem runAuditFuel_eq_auditOpcodes
    (fuel : Nat) (state : MachineState) (audit : Audit) :
    runAuditFuel fuel state audit =
      auditOpcodes audit (executedOpcodesFuel fuel state) := by
  induction fuel generalizing state audit with
  | zero => rfl
  | succ fuel ih =>
      by_cases hHalted : (step state).halted = true
      · simp [runAuditFuel, executedOpcodesFuel, hHalted, auditOpcodes]
      · simp [runAuditFuel, executedOpcodesFuel, hHalted, auditOpcodes, ih]

/-- For any program state and fuel bound, the final R1-consumed flag has the
exact direct-or-combined-use characterization above. -/
theorem runAuditFuel_r1Consumed_iff
    (fuel : Nat) (state : MachineState) :
    (runAuditFuel fuel state {}).r1Consumed = true ↔
      hasR1Consumption false (executedOpcodesFuel fuel state) = true := by
  rw [runAuditFuel_eq_auditOpcodes]
  simpa using auditOpcodes_consumed_iff ({} : Audit) (executedOpcodesFuel fuel state)

end Formalisation.R1Consumption
