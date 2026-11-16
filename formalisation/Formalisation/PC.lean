/-!
# Program-counter facts for the 4917 processor

This file contains the initial abstract control-flow lemma. The concrete
machine model lives in `Formalisation.Machine`.
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
