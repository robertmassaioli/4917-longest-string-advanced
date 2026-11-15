# 010: Evaluate precompiled instruction plans and superinstructions

**Status:** Proposed
**Created:** 2026-11-15

## Summary

Investigate whether the C implementation can reduce execution cost by compiling
an immutable program image into an internal execution plan, then dispatching
safe groups of instructions as superinstructions. Preserve the existing
`i4917_step` interpreter as the simple semantic reference and fallback. Do not
rewrite the user's program bytes or change the architectural state exposed by
the C API.

The first candidate optimization is to combine adjacent operations such as
three `INC R0` instructions into one plan operation that applies the same
modulo-16 update and advances PC by three logical instructions. Each supported
plan operation must retain the source-PC and logical-step mapping needed for a
step limit, diagnostics, and fallback. Compile-time and cache costs must be
measured against the actual workload, especially the current one-shot
exhaustive search of programs of lengths 1–4. The proposal does not assume that
precompilation is beneficial for that workload.

## Motivation and current behavior

The shared contract defines a 16-cell nibble machine with wrapping PC and
addresses, mutable memory, output events and character counts, a stateless
HALT event, and bounded execution that counts every executed instruction.
`i4917_step` implements one instruction and validates the full state on every
call. `i4917_run_bounded` repeatedly calls it; the `run` command captures
output values, and the initial `search --length N` enumerates all `16^N`
program vectors, zero-pads them, and runs each candidate once. The search range
is currently N=1–4. See [`spec/processor.md`](../spec/processor.md),
[`machine.c`](../c-impl/src/machine.c), and the search loop in
[`main.c`](../c-impl/src/main.c).

The benchmark executable measures individual `i4917_step` calls and repeated
execution fixtures, including a 256-candidate length-two search. This provides
a baseline for comparing interpreter dispatch, plan construction, plan
execution, and their combinations; the existing numbers are informational and
must not be treated as a performance guarantee. See
[`c-impl/README.md`](../c-impl/README.md) and
[`baseline-2026-11-15.md`](../c-impl/benchmarks/baseline-2026-11-15.md).

## Goals and non-goals

Goals:

- Preserve the processor contract and the public result semantics of `step`,
  `run`, and `search`.
- Measure whether plan compilation, guarded superinstructions, and optional
  caching improve representative repeated-run workloads and exhaustive search.
- Make every optimization independently testable against the direct stepper.
- Keep a straightforward interpreter fallback available for unsupported or
  invalidated plans.

Non-goals:

- Changing the ISA, program encoding, or architectural memory/register/PC
  representation.
- Making an optimization mandatory when measurements show a regression.
- Applying speculative transformations whose equivalence depends on an
  undocumented assumption about reachable PCs or memory.
- Changing search ordering, winner selection, or unresolved-candidate rules.

## Proposed architecture

Add an internal compiler that accepts a validated 16-cell initial memory image
and produces an execution plan. The plan is an alternate dispatch structure,
not a replacement program and not a new machine state. `i4917_step` continues
to interpret the architectural memory directly. A plan executor updates the
same `i4917_state` fields and reports equivalent events/results. The original
memory bytes remain present and unchanged except for the processor's ordinary
STORE instructions.

Keep the initial compiled API private to `4917_core` or behind an explicitly
experimental header until its contract stabilizes. A possible shape is:

```c
typedef struct i4917_plan i4917_plan;
i4917_error i4917_plan_compile(const uint8_t memory[16], i4917_plan **out);
void i4917_plan_destroy(i4917_plan *plan);
i4917_run_result i4917_run_bounded_plan(
    const i4917_plan *plan, const i4917_state *initial, uint64_t limit);
```

The final API should avoid mandatory heap allocation for short one-shot runs
unless measurements justify it. It may use a fixed-size plan, caller-provided
storage, or a compile-and-run helper. Plan compilation must validate input
before execution; it must not silently accept invalid nibble values.

Each plan entry should record enough mapping information to restore the
architectural PC and logical step boundary. For a fused sequence starting at
PC `p`, retain its constituent instruction count and source addresses. If
execution consumes only `k` operations because the step limit is reached, the
executor applies exactly the first `k` operations, increments the logical
step count by `k`, and leaves PC at the same cell the interpreter would have
reached after `k` steps. A plan must be dispatchable from every valid PC, not
only PC zero: JMP or a taken branch may enter the middle of a candidate
sequence. The compiler may represent suffix entries or map each source PC to
an appropriate plan position.

The direct interpreter remains the fallback when a plan cannot safely cover
the current state. Any operation that falls back must continue from the exact
architectural state and count already produced by plan execution; it must not
restart the run or lose output.

## Safe transformation rules

### Initial superinstruction set

Start with bounded, measurable rewrites over single-cell, non-observable,
non-branching operations:

- Fuse a maximal adjacent run of `INC R0` (opcode 3) into an internal
  `ADD_R0_CONSTANT(k)` plan operation.
- Similarly evaluate `INC R1` (4), `DEC R0` (5), `DEC R1` (6), and NOP (7).
- Only add repeated ADD (1) or SUB (2) fusion after proving and testing the
  exact modulo-16 equivalence for all starting register pairs and run lengths.

For `k` repeated increments/decrements, applying `k mod 16` to the selected
register is equivalent to executing the constituent instructions, because
each changes only that register and advances PC by one modulo 16. The plan must
still account for `k` logical steps and preserve intermediate-PC entry and
step-limit behavior. A run may wrap from cell 15 to cell 0, but it must not
assume addresses beyond the 16-cell ring are linear or distinct.

Fusion is initially limited to instructions whose semantics have no output
event, no branch, no halt, no memory write, and no memory read. Keep OUTPUT,
LOAD, STORE, JMP, JZ, JNZ, and HALT as individual plan entries in the first
version. This conservative boundary avoids crossing event or control-flow
points and limits invalidation complexity.

### Control flow and entry points

All 16 cells are addressable regardless of the length supplied to the loader:
short programs are zero-padded, and a jump can enter any cell. Therefore,
compilation must decode all 16 cells, including padding, and every PC must
have a semantically correct dispatch entry. Do not fuse across an address
that is the target of a jump/conditional branch unless the plan can enter the
fused sequence at that exact instruction. The simplest initial approach is to
retain a plan entry (or suffix) for every architectural PC and fuse only where
all constituent starts remain mapped.

Branches and jumps must never be folded into arithmetic groups. Their target
comes from the current memory operand and can be affected by self-modification.
The plan executor must preserve taken and not-taken outcomes and the
modulo-16 PC rules exactly.

### Self-modifying programs

STORE R0/R1 writes architectural memory and may alter an instruction, operand,
branch target, or padding cell. A compiled plan derived from old bytes cannot
continue to dispatch as if those bytes remained unchanged. The initial safe
policy is to invalidate the plan immediately after every successful STORE
and continue from the resulting state with `i4917_step` for the remainder of
that run. The STORE itself must read its operand and target from pre-step
memory, perform its write, advance PC, and count one step exactly as the
interpreter does. This invalidation is needed even if the stored value equals
the prior value unless equality is checked soundly and completely.

An alternative for later work is a memory-generation counter and per-block
guards that re-decode affected entries. That adds checks and invalidation
state; adopt it only if self-modifying workloads justify the complexity. A
conservative static scan that disables compilation whenever any cell contains
a STORE is simple but may disable plans unnecessarily when that opcode is
never executed. Benchmark the tradeoff before choosing between static
exclusion and runtime invalidation.

## Observable behavior that must remain exact

- **Architectural state:** memory, R0, R1, PC, and output-character count at
  every returned boundary must equal repeated calls to `i4917_step`.
- **PC wrapping:** both one-cell advancement and instruction sequences wrap
  modulo 16. Operand fetch at PC 15 also follows the current contract.
- **Logical steps and limits:** every source instruction counts once. A limit
  reached partway through a fused group returns the exact partial state and
  logical step count. HALT remains a single instruction and completion on the
  final allowed step remains completion; a zero limit executes nothing.
- **Output:** no fusion may skip, combine, reorder, or duplicate OUTPUT events.
  Character counts for values 0–9 and 10–15 remain exact. If later plans
  include output, the event sequence and output values must be preserved, not
  just the total character count.
- **Control flow:** a plan must honor jumps into any cell, including the
  interior of a potential fused run, and never use stale decoded targets after
  a STORE.
- **Errors and overflow:** preserve invalid-state handling and checked output
  counter overflow. An optimization may not turn an error into a successful
  result or invoke undefined behavior while calculating an aggregate update.
- **HALT:** do not fuse through HALT. It advances PC and counts as one step,
  then terminates that run only; the state has no persistent halted flag.
- **Cycle detection:** keep `i4917_run_until_halt_or_cycle` on the direct
  interpreter until a separate proof establishes equivalent full-state cycle
  identity, self-modification handling, and output-prefix behavior. The
  bounded hot path does not classify cycles.

## Compilation and caching policy

Treat compilation as a cost that must be repaid. Compare at least these modes:

1. Direct interpreter, current baseline.
2. Compile once per run, then execute the plan.
3. Compile once and reuse a plan for repeated runs of the same immutable
   program image, with all per-run machine state reset independently.
4. Lazy or threshold compilation for long-running programs, if it can switch
   from interpreter to plan without restarting or changing the result.
5. Plan execution without fusion, to separate dispatch/layout effects from
   superinstruction effects.

For a repeated workload, estimate break-even run count from measured costs:
if compilation costs `C`, interpreted execution costs `I` per run, and planned
execution costs `P` per run, compilation pays off only when `P < I` and
`n > C / (I - P)`. Measure these quantities; do not infer them from source
instruction counts. For a one-shot run, compilation helps only if its cost is
less than the saved execution time for that particular run.

The current search enumerates each 1–4-cell vector once, with between 16 and
65,536 candidates. It is especially sensitive to per-candidate allocation,
decode, and cache lookup overhead. Benchmark whole-search elapsed time and
candidate throughput at every supported length, including the default step
limit and representative smaller limits. Include workloads with short halting
programs, unresolved loops, and longer executions. Since a candidate is not
currently reused, do not assume a global plan cache is profitable. If testing
suggests caching, include bounded-cache memory cost, collision-safe program
identity (all 16 memory cells and any relevant compilation options), and
invalidation behavior in the measurements.

For lazy compilation, benchmark the threshold cost as part of the run. It
should compile only after the interpreter has executed enough steps to make
the remaining execution likely to amortize that cost; the threshold must be
derived empirically and may vary by plan size or workload. Search candidates
must still be eligible and counted under the unchanged termination policy.

## Benchmark design and acceptance criteria

Extend `4917-bench` with separate fixtures for compile-only cost, plan-only
execution, compile-plus-one-run, repeated-run reuse, and whole-search lengths
1, 2, 3, and 4. Include straight-line arithmetic, wraparound, branch-heavy,
output, self-modifying, and bounded-loop workloads. Each result should state
compiler, build type/flags, revision, repetitions, logical instructions or
candidates, and elapsed/throughput statistics. Keep timing informational;
do not add flaky wall-clock pass/fail thresholds to CTest.

For each benchmark, consume a checksum/result sink and compare the semantic
result against the interpreter outside the timed region. Report both total
time and normalized cost per logical instruction/candidate where meaningful.
Measure on the same machine and build configuration, with repeated samples and
clear separation between compilation and execution costs. Avoid comparing a
Release plan against a Debug interpreter.

Adopt an optimization only when:

- The differential and property checks pass for all relevant generated and
  fixed cases.
- The end-to-end workload it targets improves repeatably beyond benchmark
  noise, including compilation cost and memory overhead.
- It does not cause a material regression in the principal search or run
  workloads; any targeted regression must be an explicit product tradeoff.
- The implementation remains bounded and has a direct-interpreter fallback.

If precompilation fails these criteria for current workloads, retain the
benchmark results and defer it until a repeated-run workload exists. The
research outcome may correctly be that this optimization is not worthwhile.

## Correctness test plan

Keep `i4917_step` as the differential oracle. Add deterministic tests for each
supported rewrite, plus generated tests that compare:

- One direct step versus one plan-dispatched architectural instruction for
  every opcode and all valid PC/register/memory boundaries.
- Complete bounded runs from reset and arbitrary valid initial states, for
  limits from zero through the full run and for limits that stop inside every
  fused run length.
- Entry at every PC, particularly every interior cell of a fused group,
  branch targets at those cells, and groups spanning PC 15 to PC 0.
- Arithmetic equivalence over all 16 values per affected register and all
  fused run lengths that can occur in the 16-cell memory.
- Output values/counts, HALT at/around the limit, taken and untaken branches,
  operand wrapping, and output-count overflow boundaries.
- STORE to each cell, including a fused instruction, its source bytes,
  branch operands, and cells already visited; verify plan invalidation and
  interpreter continuation.
- Random valid programs with repeated runs and random bounded limits, checking
  termination, logical steps, output events/values, all final state fields,
  and search totals/winners against an unoptimized enumeration.

Use fixed seeds and preserve every minimized failure as a named regression
case shared with the Haskell differential harness where applicable. Invalid
program/state inputs should be tested separately at the compiler API boundary.

## Rollout

1. Add benchmark fixtures for the current interpreter that isolate per-run,
   repeated-run, and full-search costs for lengths 1–4.
2. Implement plan compilation with no fusion and compare it to the interpreter
   to measure representation and dispatch costs.
3. Add one safe fusion (`INC R0`) with per-PC entry mapping, logical-step
   accounting, and direct fallback after STORE.
4. Expand only to other operations that have a clear equivalence proof and
   measured benefit. Re-run the complete differential, property, sanitizer,
   and benchmark suite after each change.
5. Decide whether plans belong in `run`, `search`, both, or neither based on
   end-to-end evidence. Keep an opt-out or direct path for diagnostics and
   future oracle checks.

## Open decisions

- Should compilation initially be opt-in, selected by run length, or restricted
  to repeated-run clients until search benchmarks show a benefit?
- Should a first plan use a fixed-size representation, caller-provided storage,
  or heap allocation?
- Is runtime invalidation on every STORE preferable to a conservative
  static exclusion when the program image contains a STORE opcode?
- Should a future plan cache be per search invocation, per process, or omitted
  unless program reuse becomes common?
- Which superinstructions beyond repeated unary arithmetic merit evaluation
  after benchmark evidence is available?
