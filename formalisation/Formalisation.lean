/-!
# First control-flow lemma for the 4917 processor

This is deliberately a small, abstract starting point. `ForwardReach a b`
means that the program counter can move from `a` to `b` along zero or more
strictly increasing steps. The first theorem rules out a cycle in that model.

It is not yet a theorem about the complete processor: the concrete instruction
semantics, memory writes, program padding, and the link from instructions to
these increasing steps are future work.
-/

namespace Formalisation

/-- A program counter in the processor's 16-cell address space. -/
abbrev PC := Fin 16

/-- Zero or more PC transitions, each of which strictly increases the PC. -/
inductive ForwardReach : PC → PC → Prop where
  | refl (pc : PC) : ForwardReach pc pc
  | step {start middle finish : PC} :
      start.val < middle.val →
      ForwardReach middle finish →
      ForwardReach start finish

/-- A forward-only path cannot end at an address below where it began. -/
theorem forwardReach_le {start finish : PC}
    (path : ForwardReach start finish) :
    start.val ≤ finish.val := by
  induction path with
  | refl pc => exact Nat.le_refl _
  | @step start middle finish hStep _ hRest =>
      exact Nat.le_trans (Nat.le_of_lt hStep) hRest

/-- Once a path takes a strictly increasing step, it cannot return to its
starting PC. This is the initial no-loop result for the abstract PC model. -/
theorem no_forward_cycle {start middle : PC}
    (hStep : start.val < middle.val)
    (hReturn : ForwardReach middle start) :
    False := by
  have hReturnLe := forwardReach_le hReturn
  have impossible : start.val < start.val :=
    Nat.lt_of_lt_of_le hStep hReturnLe
  exact Nat.lt_irrefl _ impossible

end Formalisation
