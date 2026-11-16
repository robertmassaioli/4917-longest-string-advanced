import Formalisation.Machine

/-!
# Machine counterexamples

Concrete programs that demonstrate why some termination claims need extra
conditions live here, separately from the machine model.
-/

namespace Formalisation

/-- A length-15 example with no STORE or jump opcodes: fourteen NOPs followed
by OUTPUT. At PC 14, OUTPUT reads the padded zero at cell 15 and wraps to PC 0. -/
def wraparoundCounterexample : List Nibble := List.replicate 14 7 ++ [8]

theorem wraparoundCounterexample_length :
    wraparoundCounterexample.length = 15 := by
  decide

theorem wraparoundCounterexample_step_at_pc14 :
    let s := { initialState wraparoundCounterexample with pc := 14 }
    (step s).halted = false ∧
    (step s).state.pc = 0 ∧
    (step s).output = some 0 := by
  decide

end Formalisation
