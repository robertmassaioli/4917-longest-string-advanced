import Formalisation.MonotoneOutput
import Formalisation.Termination
import Init.Data.List.Perm

/-! Sound certificates and checked counterexamples for proposed pre-run rules 6–10.
A certificate quantifies over *all* states admitted by its invariant. It is not a
claim that a syntactic CFG produced outside Lean is automatically sound. -/
namespace Formalisation.PreRunChecksB

/-- Concrete terminating execution, listing states at non-HALT instructions. -/
inductive FiniteRun : MachineState → List MachineState → Nat → Prop where
  | halt {s} : (step s).halted = true → FiniteRun s [] 0
  | next {s states score} : (step s).halted = false →
      FiniteRun (step s).state states score →
      FiniteRun s (s :: states) (stepOutputCharacterScore (step s) + score)

/-- A closed invariant is the bridge from a static certificate to concrete runs. -/
structure ClosedInvariant (I : MachineState → Prop) : Prop where
  next : ∀ s, I s → (step s).halted = false → I (step s).state

/-- Rule 6: an invariant in which every non-HALT transition increases the PC. -/
structure IncreasingCertificate (I : MachineState → Prop) : Prop extends ClosedInvariant I where
  increasing : ∀ s, I s → (step s).halted = false → s.pc.val < (step s).state.pc.val

theorem increasingCertificate_monotone {I s states score}
    (cert : IncreasingCertificate I) (hI : I s) (run : FiniteRun s states score) :
    MonotoneMachineRun 15 s score := by
  induction run with
  | halt h => exact .halt (by have := s.pc.isLt; omega) h
  | @next s states score h rest ih =>
      exact .next (cert.increasing s hI h) (by have := (step s).state.pc.isLt; omega)
        h (ih (cert.next s hI h))

theorem increasingCertificate_bound {I s states score}
    (cert : IncreasingCertificate I) (hI : I s) (hStart : s.pc.val = 0)
    (run : FiniteRun s states score) : score ≤ 30 :=
  monotoneMachineRun_score_bound hStart (increasingCertificate_monotone cert hI run)

/-- Rules 7–8: abstract node and cost certificate. Its edge condition includes
both conditional outcomes and any STORE effects through universal state coverage.
A longest-path potential for a DAG is one way to supply `budget`. Zero-cost cycles
are also permitted: their internal edges need not decrease the budget. -/
structure GraphCertificate (Node : Type) (I : MachineState → Prop) where
  node : MachineState → Node
  edge : Node → Node → Prop
  cost : Node → Nat
  budget : Node → Nat
  closed : ClosedInvariant I
  edgeSound : ∀ s, I s → (step s).halted = false → edge (node s) (node (step s).state)
  costSound : ∀ s, I s → stepOutputCharacterScore (step s) ≤ cost (node s)
  budgetEdge : ∀ a b, edge a b → cost a + budget b ≤ budget a

theorem graphCertificate_bound {Node I s states score}
    (cert : GraphCertificate Node I) (hI : I s) (run : FiniteRun s states score) :
    score ≤ cert.budget (cert.node s) := by
  induction run with
  | halt h => omega
  | @next s states score h rest ih =>
      have hc := cert.costSound s hI
      have he := cert.budgetEdge _ _ (cert.edgeSound s hI h)
      have hr := ih (cert.closed.next s hI h)
      omega

/-- Rule 8's SCC contraction is sound when every internal SCC transition costs
zero, and every exit fits the component budget. This is the complete bridge;
merely labelling some syntactically decoded instructions is insufficient. -/
structure ComponentCertificate (Component : Type) (I : MachineState → Prop) where
  component : MachineState → Component
  budget : Component → Nat
  closed : ClosedInvariant I
  internalSilent : ∀ s, I s → (step s).halted = false →
    component s = component (step s).state → stepOutputCharacterScore (step s) = 0
  exitBudget : ∀ s, I s → (step s).halted = false →
    component s ≠ component (step s).state →
    stepOutputCharacterScore (step s) + budget (component (step s).state) ≤ budget (component s)

theorem componentCertificate_bound {Component I s states score}
    (cert : ComponentCertificate Component I) (hI : I s)
    (run : FiniteRun s states score) : score ≤ cert.budget (cert.component s) := by
  induction run with
  | halt h => omega
  | @next s states score h rest ih =>
      have hr := ih (cert.closed.next s hI h)
      by_cases he : cert.component s = cert.component (step s).state
      · have hc := cert.internalSilent s hI h he
        rw [← he] at hr
        omega
      · have hc := cert.exitBudget s hI h he
        omega

/-- Score of a fuel-bounded evaluation, used only for finite checked witnesses. -/
def fuelScore (fuel : Nat) (program : List Nibble) : Option Nat :=
  match runFuel fuel (initialState program) [] with
  | .halted _ values => some (outputCharacterScore values)
  | .outOfFuel _ _ => none

/-- No jump/store opcode does not imply increasing PC: OUTPUT at 14 wraps. -/
theorem noJump_noStore_can_wrap :
    let s : MachineState := { initialState (List.replicate 14 7 ++ [8, 10]) with pc := 14 }
    (s.memory s.pc).val = 8 ∧ (step s).state.pc.val = 0 ∧ ¬ s.pc.val < (step s).state.pc.val := by
  decide

/-- Dropping the taken conditional edge incorrectly predicts zero output. -/
theorem conditional_taken_edge_matters : fuelScore 3 [14, 4, 0, 0, 8, 10, 0] = some 2 := by
  decide

/-- A jump can enter an operand cell; disjoint decoding misses this OUTPUT. -/
theorem operand_entry_matters : fuelScore 3 [13, 3, 13, 8, 10, 0] = some 2 := by
  decide

/-- A useful syntactic instance of rule 6: the existing linear-reach scan is
safe, and the last two cells are zero. Operands remain unrestricted. -/
def linearInvariant (memory : Memory) (s : MachineState) : Prop :=
  s.memory = memory ∧ LinearReach memory s.pc

theorem safeLinear_increasingCertificate (memory : Memory)
    (hSafe : ∀ pc, LinearReach memory pc → (memory pc).val ≤ 10)
    (hTail : ∀ pc, 14 ≤ pc.val → memory pc = 0) :
    IncreasingCertificate (linearInvariant memory) := by
  have localFacts : ∀ s, linearInvariant memory s → (step s).halted = false →
      (step s).state.memory = memory ∧
      LinearReach memory (step s).state.pc ∧ s.pc.val < (step s).state.pc.val := by
    intro s hs hh
    obtain ⟨hm, hr⟩ := hs
    have hb : (s.memory s.pc).val ≤ 10 := by rw [hm]; exact hSafe s.pc hr
    have hn : (s.memory s.pc).val ≠ 0 := by
      intro hz
      have := zeroOpcodeHalts s hz
      simp_all
    have hp : s.pc.val < 14 := by
      by_cases h : s.pc.val < 14
      · exact h
      have hz : s.memory s.pc = 0 := by rw [hm]; exact hTail s.pc (by omega)
      exact False.elim (hn (by rw [hz]; rfl))
    have hm' : (step s).state.memory = memory := (safeStep_preserves_memory s hb).trans hm
    have hnpc := (safeStep_nextPC s hb hn).2
    have hr' : LinearReach memory (step s).state.pc := by
      rw [hnpc]
      by_cases hOne : (s.memory s.pc).val ≤ 7
      · simp [hOne]
        exact .oneByte hr (by rw [← hm]; omega) (by rw [← hm]; exact hOne)
      · simp [hOne]
        exact .twoByte hr (by rw [← hm]; omega) (by rw [← hm]; omega)
    exact ⟨hm', hr', (safeStep_progresses s hb hp hn).2⟩
  exact {
    next := fun s hs hh => ⟨(localFacts s hs hh).1, (localFacts s hs hh).2.1⟩
    increasing := fun s hs hh => (localFacts s hs hh).2.2 }

theorem shortLinear_static_score_bound (program : List Nibble)
    (hLength : program.length ≤ 14) (hSafe : NoStorageOrLoopProgram program)
    {states score} (run : FiniteRun (initialState program) states score) : score ≤ 30 := by
  apply increasingCertificate_bound (I := linearInvariant (initialState program).memory)
    (safeLinear_increasingCertificate _ hSafe ?_) ⟨rfl, .start⟩ rfl run
  intro pc hpc
  simp only [initialState, List.getD]
  rw [List.getElem?_eq_none (by omega)]
  rfl

/-- Completely finite pre-run check: for every admitted PC and both nibble
register values, stepping must preserve memory, stay in the admitted set, and
fit the proposed remaining-character budget. HALT cases need no successor.
The quantifiers include all 4096 register/PC combinations, not a sample run. -/
def StaticPCBudget (memory : Memory) (allowed : PC → Bool) (budget : PC → Nat) : Prop :=
  ∀ (pc : PC) (r0 r1 : Nibble), allowed pc = true →
    let s : MachineState := ⟨memory, r0, r1, pc⟩
    (step s).halted = false →
    (∀ cell, (step s).state.memory cell = memory cell) ∧
    allowed (step s).state.pc = true ∧
    stepOutputCharacterScore (step s) + budget (step s).state.pc ≤ budget pc

theorem staticPCBudget_bound {memory allowed budget s states score}
    (check : StaticPCBudget memory allowed budget)
    (hm : s.memory = memory) (ha : allowed s.pc = true)
    (run : FiniteRun s states score) : score ≤ budget s.pc := by
  induction run with
  | halt h => omega
  | @next s states score hh rest ih =>
      have hs : s = ⟨memory, s.r0, s.r1, s.pc⟩ := by cases s; simp_all
      have hc := check s.pc s.r0 s.r1 ha
      rw [← hs] at hc
      obtain ⟨hm', ha', hb⟩ := hc hh
      have hr := ih (funext hm') ha'
      omega

/-- Rules 7–8 have a finite certificate usable before execution. For this
sample graph the two nodes are PC 0 (OUTPUT) and PC 2 (HALT). -/
theorem sample_static_budget :
    StaticPCBudget (initialState [8, 10, 0]).memory
      (fun pc => pc == 0 || pc == 2) (fun pc => if pc = 0 then 2 else 0) := by
  intro pc r0 r1 ha
  dsimp only
  intro hh
  have hp : pc = 0 ∨ pc = 2 := by simpa using ha
  rcases hp with rfl | rfl
  · change (∀ cell, (initialState [8, 10, 0]).memory cell =
        (initialState [8, 10, 0]).memory cell) ∧ true = true ∧ 2 + 0 ≤ 2
    simp
  · change true = false at hh
    contradiction

/-- Determinism makes the number of non-HALT steps unique. -/
theorem finiteRun_length_unique {s xs a ys b}
    (run : FiniteRun s xs a) (other : FiniteRun s ys b) : xs.length = ys.length := by
  induction run generalizing ys b with
  | halt hh =>
      cases other with
      | halt => rfl
      | next hn _ => simp_all
  | next hn rest ih =>
      cases other with
      | halt hh => simp_all
      | next _ other => simpa using ih other

/-- Every listed state starts a suffix execution no longer than the whole run. -/
theorem finiteRun_member_suffix {s xs score} (run : FiniteRun s xs score)
    {t} (ht : t ∈ xs) :
    ∃ ys score', FiniteRun t ys score' ∧ ys.length ≤ xs.length := by
  induction run with
  | halt hh => simp at ht
  | @next s xs score hh rest ih =>
      simp only [List.mem_cons] at ht
      rcases ht with he | ht
      · subst t
        exact ⟨s :: xs, _, .next hh rest, Nat.le_refl _⟩
      · obtain ⟨ys, score', hy, hlen⟩ := ih ht
        exact ⟨ys, score', hy, by simp; omega⟩

/-- Rule 9's essential fact: a deterministic halting run never repeats a full
state. Memory is part of the full state. -/
theorem finiteRun_states_nodup {s xs score} (run : FiniteRun s xs score) : xs.Nodup := by
  induction run with
  | halt hh => simp
  | @next s xs score hh rest ih =>
      rw [List.nodup_cons]
      refine ⟨?_, ih⟩
      intro hs
      obtain ⟨ys, score', hy, hlen⟩ := finiteRun_member_suffix rest hs
      have he := finiteRun_length_unique (.next hh rest) hy
      simp at he
      omega

/-- Enumerate only states which emit an OUTPUT event. -/
def outputStates (xs : List MachineState) : List MachineState :=
  xs.filter (fun s => (step s).output.isSome)

theorem finiteRun_score_le_outputStates {s xs score} (run : FiniteRun s xs score) :
    score ≤ 2 * (outputStates xs).length := by
  induction run with
  | halt hh => simp [outputStates]
  | @next s xs score hh rest ih =>
      cases ho : (step s).output with
      | none => simpa [outputStates, ho, stepOutputCharacterScore] using ih
      | some value =>
          have hv := decimalCharacterCount_le_two value
          simp [outputStates, ho, stepOutputCharacterScore] at ih ⊢
          omega

/-- A register/PC key omits memory and is injective only under fixed memory. -/
def stateKey (s : MachineState) : Nat := s.pc.val + 16 * s.r0.val + 256 * s.r1.val

theorem stateKey_injective_fixed_memory {s t : MachineState}
    (hm : s.memory = t.memory) (hk : stateKey s = stateKey t) : s = t := by
  have hsp := s.pc.isLt
  have htp := t.pc.isLt
  have hs0 := s.r0.isLt
  have ht0 := t.r0.isLt
  have hs1 := s.r1.isLt
  have ht1 := t.r1.isLt
  simp only [stateKey] at hk
  have hp : s.pc = t.pc := Fin.ext (by omega)
  have h0 : s.r0 = t.r0 := Fin.ext (by omega)
  have h1 : s.r1 = t.r1 := Fin.ext (by omega)
  cases s; cases t; simp_all

/-- Fixed memory makes the keys of a duplicate-free state list duplicate-free. -/
theorem stateKeys_nodup {memory : Memory} {xs : List MachineState}
    (hn : xs.Nodup) (hm : ∀ s ∈ xs, s.memory = memory) :
    (xs.map stateKey).Nodup := by
  induction xs with
  | nil => simp
  | cons s xs ih =>
      rw [List.nodup_cons] at hn
      simp only [List.map_cons, List.nodup_cons]
      refine ⟨?_, ih hn.2 (fun t ht => hm t (by simp [ht]))⟩
      intro hkey
      obtain ⟨t, ht, he⟩ := List.mem_map.mp hkey
      have heq : s = t := stateKey_injective_fixed_memory
        ((hm s (by simp)).trans (hm t (by simp [ht])).symm) he.symm
      exact hn.1 (heq ▸ ht)

/-- Rule 9, refined form: enumerate an overapproximation of *output-producing*
PC/register keys. If every trace state has the same memory, no key repeats,
and at most two characters are emitted per listed output key. -/
theorem immutable_output_key_bound {memory : Memory} {s xs score}
    (run : FiniteRun s xs score) (hm : ∀ t ∈ xs, t.memory = memory)
    (keys : List Nat) (cover : ∀ t ∈ outputStates xs, stateKey t ∈ keys) :
    score ≤ 2 * keys.length := by
  have hn := (finiteRun_states_nodup run).filter (fun s => (step s).output.isSome)
  have hkeys : ((outputStates xs).map stateKey).Nodup :=
    stateKeys_nodup hn (fun t ht => hm t ((List.mem_filter.mp ht).1))
  have hlen : ((outputStates xs).map stateKey).length ≤ keys.length :=
    hkeys.length_le_of_subset (by
      intro k hk
      obtain ⟨t, ht, rfl⟩ := List.mem_map.mp hk
      exact cover t ht)
  have hs := finiteRun_score_le_outputStates run
  simp at hlen
  omega

/-- Broad corollary: fixed memory allows 16*16*16 keys, hence 8192 characters.
The refined theorem is useful when static register analysis admits far fewer. -/
theorem immutable_full_state_bound {memory : Memory} {s xs score}
    (run : FiniteRun s xs score) (hm : ∀ t ∈ xs, t.memory = memory) : score ≤ 8192 := by
  have hb := immutable_output_key_bound run hm (List.range 4096) (by
    intro t ht
    simp only [List.mem_range, stateKey]
    have hp := t.pc.isLt
    have h0 := t.r0.isLt
    have h1 := t.r1.isLt
    omega)
  simpa using hb

theorem finiteRun_states_invariant {I s xs score}
    (closed : ClosedInvariant I) (hI : I s) (run : FiniteRun s xs score) :
    ∀ t ∈ xs, I t := by
  induction run with
  | halt hh => simp
  | @next s xs score hh rest ih =>
      intro t ht
      simp only [List.mem_cons] at ht
      rcases ht with he | ht
      · simpa [he] using hI
      · exact ih (closed.next s hI hh) t ht

/-- Static version of rule 9: the admitted invariant fixes memory and contains
all output-producing register/PC keys in a supplied finite list. -/
structure ImmutableKeyCertificate (I : MachineState → Prop) (memory : Memory)
    (keys : List Nat) : Prop extends ClosedInvariant I where
  fixedMemory : ∀ s, I s → s.memory = memory
  outputCovered : ∀ s, I s → (step s).output.isSome = true → stateKey s ∈ keys

theorem immutableKeyCertificate_bound {I memory keys s xs score}
    (cert : ImmutableKeyCertificate I memory keys) (hI : I s)
    (run : FiniteRun s xs score) : score ≤ 2 * keys.length := by
  have hi := finiteRun_states_invariant cert.toClosedInvariant hI run
  apply immutable_output_key_bound run (fun t ht => cert.fixedMemory t (hi t ht)) keys
  intro t ht
  have hmem := List.mem_filter.mp ht
  exact cert.outputCovered t (hi t hmem.1) hmem.2

/-- A self-modifying halting program revisits the same OUTPUT PC and register
pair. Its memory changes, so omitting memory from cycle identity is unsound. -/
def selfModifyingOutput : List Nibble := [8, 10, 11, 2, 13, 0]

def advance : Nat → MachineState → MachineState
  | 0, s => s
  | n + 1, s => advance n (step s).state

/-- The wrapping OUTPUT above is actually reached from the prescribed reset
state after fourteen NOPs; all initial bytes are at most 10. -/
theorem wrapping_trace_witness :
    let program : List Nibble := List.replicate 14 7 ++ [8, 10]
    (∀ value ∈ program, value.val ≤ 10) ∧
    (advance 14 (initialState program)).pc = 14 ∧
    (advance 15 (initialState program)).pc = 0 := by
  decide

theorem registerPC_key_can_repeat_with_STORE :
    let s := initialState selfModifyingOutput
    let t := advance 3 s
    stateKey s = stateKey t ∧ s.memory 2 ≠ t.memory 2 ∧
    (step s).output = some 10 ∧ (step t).output = some 10 ∧
    fuelScore 5 selfModifyingOutput = some 4 := by
  decide

/-- No literal 8 in the initial vector does not mean no future OUTPUT. -/
theorem STORE_manufactures_OUTPUT :
    let program : List Nibble := [3, 3, 3, 3, 3, 3, 3, 3, 11, 10, 7, 10, 0]
    (∀ value ∈ program, value ≠ 8) ∧ fuelScore 11 program = some 2 := by
  decide

/-- A positive-output self edge cannot satisfy a finite graph budget. -/
theorem graph_self_edge_silent {Node I} (cert : GraphCertificate Node I)
    {node} (edge : cert.edge node node) : cert.cost node = 0 := by
  have h := cert.budgetEdge node node edge
  omega

/-- Two-node cycles also cannot carry positive output cost under such a budget. -/
theorem graph_two_cycle_silent {Node I} (cert : GraphCertificate Node I)
    {a b} (hab : cert.edge a b) (hba : cert.edge b a) :
    cert.cost a = 0 ∧ cert.cost b = 0 := by
  have ha := cert.budgetEdge a b hab
  have hb := cert.budgetEdge b a hba
  omega

/-- Rule 10, a precise syntactic safe class: one OUTPUT, immediate HALT, and an
arbitrary unreachable tail. The literal cannot also be executed or loaded. -/
theorem outputHalt_score (literal : Nibble) (tail : List Nibble) :
    fuelScore 2 (8 :: literal :: 0 :: tail) = some (decimalCharacterCount literal) := by
  rfl

/-- Replacing a one-digit literal by any two-digit nibble in this class gives
a halting program of exactly the same vector length with a strictly larger score. -/
theorem safe_literal_upgrade (literal upgrade : Nibble) (tail : List Nibble)
    (hOne : literal.val < 10) (hTwo : 10 ≤ upgrade.val) :
    (8 :: literal :: 0 :: tail).length = (8 :: upgrade :: 0 :: tail).length ∧
    fuelScore 2 (8 :: literal :: 0 :: tail) = some 1 ∧
    fuelScore 2 (8 :: upgrade :: 0 :: tail) = some 2 := by
  simp only [List.length_cons, outputHalt_score, decimalCharacterCount]
  simp [hOne, show ¬ upgrade.val < 10 by omega]

/-- The exact optimality comparison used by a pruning rule: one known halting
same-length competitor with a strictly higher score suffices. -/
def IsOptimalScore (program : List Nibble) (score : Nat) : Prop :=
  ∀ competitor : List Nibble, competitor.length = program.length →
    ∀ fuel competitorScore, fuelScore fuel competitor = some competitorScore →
      competitorScore ≤ score

theorem outputHalt_oneDigit_not_optimal (literal : Nibble) (tail : List Nibble)
    (hOne : literal.val < 10) : ¬ IsOptimalScore (8 :: literal :: 0 :: tail) 1 := by
  intro optimal
  have hx := safe_literal_upgrade literal 10 tail hOne (by decide)
  have impossible := optimal (8 :: 10 :: 0 :: tail) hx.1.symm 2 2 hx.2.2
  omega

/-- Overbroad operand upgrade is false even without STORE: the literal is also
executed after a jump into that cell. Upgrading 8 to 10 reduces score 3 to 2. -/
theorem literal_upgrade_breaks_with_operand_entry :
    fuelScore 5 [8, 8, 13, 1, 0] = some 3 ∧
    fuelScore 5 [8, 10, 13, 1, 0] = some 2 := by
  decide

/-- Even forbidding operand entry is insufficient: LOAD may read the literal
as data, changing a later branch. Upgrading 0 to 10 reduces score 5 to 2. -/
theorem literal_upgrade_breaks_with_data_alias :
    fuelScore 6 [8, 0, 9, 1, 15, 10, 8, 10, 8, 10, 0] = some 5 ∧
    fuelScore 6 [8, 10, 9, 1, 15, 10, 8, 10, 8, 10, 0] = some 2 := by
  decide

end Formalisation.PreRunChecksB
