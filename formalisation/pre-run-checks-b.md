# Lean conclusions for pre-run checks 6–10

All results below are in `Formalisation/PreRunChecksB.lean`, checked against the
concrete `Machine.step`. There are no `sorry`, `admit`, new axioms, or claims
based on a timeout. This work proves pruning principles and their precise
premises; it does not implement a Haskell graph builder or pruning CLI.

For preserving all longest-string ties, reject only when the proved upper bound
is **strictly below a known halting score at the same exact vector length**.
For finding strict improvements, an upper bound equal to that score also suffices.
A score bound says what a halting candidate can achieve; it does not itself prove
that a candidate halts.

| Check | Decisive conclusion | Lean result |
| --- | --- | --- |
| 6. Increasing PC | Proved: a closed invariant proving every non-HALT PC transition increases implies a 30-character bound from PC 0. A concrete static instance is the existing safe linear scan, with cells 14 and 15 zero. | `increasingCertificate_bound`, `safeLinear_increasingCertificate`, `shortLinear_static_score_bound` |
| 7. Weighted acyclic graph | Proved: a sound abstract graph with a nonnegative per-node cost and remaining-score budgets satisfying every edge bounds the concrete score. A longest weighted path in a DAG supplies such budgets if its graph and weights satisfy these premises. | `graphCertificate_bound`, `StaticPCBudget`, `staticPCBudget_bound`, `sample_static_budget` |
| 8. Silent cyclic components | Proved: component contraction is sound when every concrete internal transition emits zero characters, every exit fits the component budget, and the invariant is closed. Repeated internal transitions need not decrease the budget. | `componentCertificate_bound` |
| 9. Distinct states | Proved: a halting deterministic execution never repeats a full state. With fixed memory, PC/register keys are injective, so an overapproximation containing `K` output-producing keys gives a `2*K` character bound. The unrestricted fixed-memory bound is 8192. | `finiteRun_states_nodup`, `stateKey_injective_fixed_memory`, `immutable_output_key_bound`, `immutableKeyCertificate_bound`, `immutable_full_state_bound` |
| 10. Literal upgrade | Proved for the concrete safe class `OUTPUT literal; HALT; unreachable tail`: upgrading a one-digit literal to any two-digit nibble produces a strictly better halting candidate with the same vector length. General blind operand upgrades are disproved. | `safe_literal_upgrade`, `outputHalt_oneDigit_not_optimal`, the two upgrade counterexamples below |

## Why the certificates are sound

`FiniteRun` is an inductive execution using the actual `Machine.step`, with a
HALT base case and the exact decimal character cost on every non-HALT step.
It records the states before non-HALT instructions. It is not a graph-only
execution model.

`ClosedInvariant` requires every admitted non-HALT successor to remain admitted.
Every certificate also needs proof that the initial state is admitted. These
premises prevent a checker from ignoring STORE effects, a branch outcome, an
operand entered as code, or wraparound.

`GraphCertificate` requires each concrete transition to have a graph edge and
each concrete output to fit its node's cost. Its budget inequality is

```text
cost(node) + budget(successor) <= budget(node)
```

Summing that inequality along a halting execution proves the bound. A verified
budget certificate suffices; an unverified longest-path calculation alone does
not. This formulation also handles silent cycles. Theorems
`graph_self_edge_silent` and `graph_two_cycle_silent` show that finite graph
budgets cannot hide positive output on one-edge or two-edge cycles.

`StaticPCBudget` is a fully finite proposition checking every admitted PC and
both nibble register values against the concrete step. It checks memory
preservation pointwise, successor admission, and the budget inequality. Its
soundness theorem connects these pre-run obligations directly to `FiniteRun`.
`sample_static_budget` proves a complete instance for `[8,10,0]` with bound 2.
An automated checker or DAG/SCC budget generator remains future implementation;
no external graph generator is assumed verified here.

`ImmutableKeyCertificate` similarly requires fixed memory and a finite list
covering all output keys in a closed invariant. Counting only PCs is not enough:
register changes can make a later visit behave differently. Counting PC/register
keys is not enough when STORE changes memory.

## Lean-checked counterexamples

The finite witnesses use `fuelScore`, which computes the score only if the
existing `runFuel` reaches HALT. `none` would mean unknown after that fuel; none of
the score comparisons below use such an unknown result.

- **No jump or STORE does not guarantee increasing PC.** Fourteen NOPs followed
  by `[8,10]` reach OUTPUT at PC 14 and wrap to PC 0. All vector bytes are at most
  10. `noJump_noStore_can_wrap` and `wrapping_trace_witness` check the concrete
  transition and its reachability from reset.
- **Both branch outcomes matter.** `[14,4,0,0,8,10,0]` takes the branch from reset
  and prints two characters. A graph retaining only fallthrough would predict
  zero. See `conditional_taken_edge_matters`.
- **Operands may be executed.** `[13,3,13,8,10,0]` jumps into the operand cell at
  address 3 and prints two characters. Disjoint instruction decoding misses that
  OUTPUT. See `operand_entry_matters`.
- **Initial code is not immutable code.**
  `[3,3,3,3,3,3,3,3,11,10,7,10,0]` contains no literal 8, but constructs OUTPUT
  with STORE and halts with score 2. See `STORE_manufactures_OUTPUT`.
- **A PC/register key may repeat in a halting self-modifying program.**
  `[8,10,11,2,13,0]` emits 10, overwrites its own STORE with HALT, jumps back,
  emits 10 again with identical PC and registers, then halts. The memories differ
  at address 2, and the score is 4. See `registerPC_key_can_repeat_with_STORE`.
- **Upgrading an operand that is also executed can reduce output.**
  `[8,8,13,1,0]` halts with score 3; replacing the first OUTPUT's literal 8 by 10
  gives `[8,10,13,1,0]`, which halts with score 2. The jump enters the changed
  operand. See `literal_upgrade_breaks_with_operand_entry`.
- **Avoiding operand entry alone does not make upgrades safe.**
  `[8,0,9,1,15,10,8,10,8,10,0]` halts with score 5; changing the first literal
  from 0 to 10 reduces the score to 2. LOAD reads the changed literal as data,
  changing the conditional jump. See `literal_upgrade_breaks_with_data_alias`.

## Scope left for later

The general mathematical rules 6–9 above are proved with explicit certificate
premises. Their automatic certificate generators are not implemented. Rule 10
has a proved restricted class and decisive counterexamples to broader versions;
a general noninterference checker for safe operand upgrades remains unproved
and must not be used to discard candidates yet.

These theorems establish facts about the Lean machine. They do not constitute a
proof that an independently implemented Haskell checker, graph builder, or
execution engine conforms to it.

Verification:

```sh
cd formalisation
zsh -ic 'lake env lean Formalisation/PreRunChecksB.lean'
zsh -ic 'lake build'
```
