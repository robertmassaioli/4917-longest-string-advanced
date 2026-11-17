import Formalisation.NopRemoval

/-!
# Relocating absolute jump targets after deleting a NOP

Deleting a byte before a target shifts that target's address down by one.
This module formalizes that relocation rule and checks, in the concrete
byte-addressed machine, that updating the absolute jump target restores the
output of an example program.

This is a first relocation result, not yet a full compiler-correctness theorem:
it does not transform every jump operand in an arbitrary program or establish
simulation for arbitrary control flow and memory aliasing.
-/

namespace Formalisation.Relocation

open Formalisation.R1Erasure

/-- Address correspondence after deleting the byte at `removed`. The deleted
address itself corresponds to the next surviving byte, and later addresses
shift down by one. This linear relocation is intended for code layouts that do
not wrap across address 15. -/
def relocateAddress (removed address : Nat) : Nat :=
  if removed < address then address - 1 else address

theorem relocateAddress_before (removed address : Nat)
    (h : address ≤ removed) :
    relocateAddress removed address = address := by
  simp [relocateAddress, Nat.not_lt_of_ge h]

theorem relocateAddress_after (removed address : Nat)
    (h : removed < address) :
    relocateAddress removed address = address - 1 := by
  simp [relocateAddress, h]

theorem relocateAddress_deleted (removed : Nat) :
    relocateAddress removed removed = removed := by
  simp [relocateAddress]

/-- For any absolute jump target after the deleted byte, its relocated target
is exactly one address earlier. -/
theorem absoluteJump_target_after_deletion (removed target : Nat)
    (h : removed < target) :
    relocateAddress removed target = target - 1 :=
  relocateAddress_after removed target h

/-- Delete one cell from a byte list. This is a physical byte deletion, so
instruction operands and all later byte addresses shift as well. -/
def deleteByteAt {α : Type} : List α → Nat → List α
  | [], _ => []
  | _ :: rest, 0 => rest
  | byte :: rest, index + 1 => byte :: deleteByteAt rest index

/-- Relocate the absolute target in a program whose first instruction is JMP.
The intended use deletes a later NOP, leaving the first two bytes in place. -/
def relocateFirstJump (program : List Nibble) (removed : Nat) : List Nibble :=
  match program with
  | 13 :: target :: rest =>
      13 :: Fin.ofNat 16 (relocateAddress removed target.val) :: rest
  | _ => program

/-- The concrete transformation: delete a byte, then update the first JMP's
target to its relocated address. -/
def deleteNopAndRelocateFirstJump
    (program : List Nibble) (removed : Nat) : List Nibble :=
  relocateFirstJump (deleteByteAt program removed) removed

/-- Deleting the NOP at address 2 and relocating JMP's target from 5 to 4
preserves the emitted trace in this concrete program. -/
theorem relocated_jump_preserves_example_output :
    outputTraceFuel step 4
        (initialState ([13, 5, 7, 7, 7, 8, 9, 0] : List Nibble)) = [9] ∧
    outputTraceFuel step 4
        (initialState ([13, 4, 7, 7, 8, 9, 0] : List Nibble)) = [9] := by
  decide

/-- The transformation itself deletes the NOP at byte 2 and changes JMP 5 to
JMP 4, producing the relocated program used above. -/
theorem delete_and_relocate_example_program :
    deleteNopAndRelocateFirstJump
        ([13, 5, 7, 7, 7, 8, 9, 0] : List Nibble) 2 =
      ([13, 4, 7, 7, 8, 9, 0] : List Nibble) := by
  decide

/-- Applying the deletion-plus-relocation transform preserves the output in
the example, unlike deleting the byte while leaving the jump operand fixed. -/
theorem delete_and_relocate_example_preserves_output :
    outputTraceFuel step 4
        (initialState ([13, 5, 7, 7, 7, 8, 9, 0] : List Nibble)) =
    outputTraceFuel step 4
        (initialState (deleteNopAndRelocateFirstJump
          ([13, 5, 7, 7, 7, 8, 9, 0] : List Nibble) 2)) := by
  rw [delete_and_relocate_example_program]
  decide

/-- Deleting the same NOP without relocating the absolute target changes the
output: JMP 5 now lands on the OUTPUT operand instead of the OUTPUT opcode. -/
theorem unrelocated_jump_changes_example_output :
    outputTraceFuel step 4
        (initialState ([13, 5, 7, 7, 7, 8, 9, 0] : List Nibble)) = [9] ∧
    outputTraceFuel step 4
        (initialState ([13, 5, 7, 7, 8, 9, 0] : List Nibble)) = [] := by
  decide

end Formalisation.Relocation
