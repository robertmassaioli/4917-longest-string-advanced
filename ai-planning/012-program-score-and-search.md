# 012: Find higher-output programs at lengths 10–16

**Created:** 2026-11-18

## Goal

Use program execution data to discover halted programs of declared lengths 10–16 that emit more decimal characters than the best candidates currently known for their length. The central task is score-guided search, not classification of the already-known tied winners at lengths 1–9.

No exhaustive maximum is currently established for lengths 10–16. For those lengths, the useful model target is the exact output character count of a halted candidate, and the useful search signal is whether a candidate is likely to beat the best verified score so far. A candidate that improves a known record gives a new lower bound; it does not prove an optimum.

The simulator is a deterministic labeling oracle. For every candidate selected for training or evaluation, run the program and record its declared length, termination status, and exact character count if it halts. This lets us train on arbitrary programs we choose to simulate, including losing candidates. We do not need to exhaustively simulate the entire `16^N` space to train a search-guiding model.

## Current evidence and starting point

Lengths 1–9 have exhaustive maximum scores documented in the repository. These programs and their traces provide examples of short loop structures, but their exact winner labels are not the target for lengths 10–16.

The repository records these longer candidates:

| Declared length | Best recorded score | Evidence status |
|---:|---:|---|
| 10–14 | No consolidated best-known score found in the explainer docs | Establish an initial exact baseline before comparing methods |
| 15 | 962 characters | Best found in local exploration; not exhaustive |
| 16 | 2,957 characters | Best found in local exploration; not exhaustive |

See [length-15.md](../explainers/length-15.md), [length-16.md](../explainers/length-16.md), and [storage-extended-loop.md](../explainers/storage-extended-loop.md). Length 15's recorded candidate builds on the length-8 modular loop and uses self-modifying code. Length 16's 2,957-character candidate uses a staged counter that changes its own PRINT operand and eventually halts. These are valuable seeds, but they do not show that the same structures will remain best for other lengths.

Exhaustive search is not a practical baseline for the full target range. Candidate counts grow from about 1.1 trillion at length 10 to `2^64` at length 16. Existing timing notes project multi-day or longer runs from smaller measurements; those projections are uncertain but make the scale clear. The search CLI's support for a length does not make exhaustive search of that length computationally feasible.

Relevant constraints:

- [spec/processor.md](../spec/processor.md) defines output score as decimal characters, with values 0–9 adding one and 10–15 adding two. Only halted programs have a finite eligible score. Cycles are not scored as winners; bounded runs, errors, and counter overflows are unresolved outcomes.
- Candidate identity is `(declared_length, nibble_vector)`. Trailing zeroes are part of the supplied vector, and the remaining cells are zero-padded. Preserve the declared length and exact nibbles in data and search results.
- The machine supports self-modifying code, jumps into operand cells, and PC wraparound. Static disassembly features must not assume a fixed instruction boundary map.
- The C++ simulator provides a direct run-until-halt-or-cycle path and checks integer overflow. A training-data adapter should preserve HALTED, CYCLE, and unresolved statuses instead of mapping timeouts or errors to zero scores. The legacy Haskell brute-force/cache path has known heuristic and timeout-labeling issues described in [proposal 011](011-cli-search-range-checkpoints.md); it is not a source of clean labels without a direct-evaluator path.
- Length 16 has `16^16 = 2^64` candidates. This count exceeds a 64-bit unsigned integer, so search enumeration and data tooling must use a representation that handles the exclusive endpoint safely or partition the space without overflowing.

## Prediction interface

For this search objective, prioritize score prediction over winner probability:

```text
predict_program(program: [Nibble]) -> ProgramPrediction
```

A prediction should include an estimated termination outcome and, conditional on halting, a predicted output-character score or score distribution. It may include uncertainty and the model version. An acquisition value can estimate `P(score > best_known[N])` or expected improvement over the current record, where `best_known[N]` is the best exact halted score found so far. This is a search heuristic, not a probability of being globally optimal.

The declared length is `len(program)` and remains an explicit model input. Invalid inputs need an explicit error result. A model may rank candidates or prioritize exact simulations, but only direct halted execution establishes a candidate's score. An unresolved execution must not be represented as a low score.

## Options

### Option 1: Simulator-driven mutation and structured search

Use known high-scoring programs as seeds, especially the length-15 and length-16 examples. Generate candidates by changing nibbles, inserting or deleting instructions where length permits, varying operands, and applying carefully scoped templates based on observed counter loops and self-modifying handlers. Simulate each unique candidate and keep the best verified halted result for each length.

- **Strengths:** every evaluated score is exact; works with a small seed corpus; directly targets record improvement.
- **Limitations:** local mutations can get trapped near known structures and may miss radically different programs. Template restrictions can exclude useful solutions unless kept as proposal strategies rather than unsound pruning rules.
- **Best use:** essential non-ML baseline and source of early training examples.

### Option 2: Surrogate-assisted search using simulated score labels

Train a compact model from exact simulations of selected programs. Features can include the nibble sequence, declared length, structural summaries, and possibly execution traces for analysis. At each round, let mutation/template/random proposal methods create candidates; use a model or ensemble to rank them; directly simulate a batch that balances high predicted improvement with uncertainty and structural diversity; then update the training data and model.

- **Strengths:** uses the exact score from every selected program, not only the rare winner label; can spend a fixed simulation budget on candidates predicted to have high upside; uncertainty can direct simulations toward poorly covered structures.
- **Limitations:** predictions can be confidently wrong on unseen loop or self-modification patterns. Training data gathered adaptively are biased toward earlier model choices. A surrogate must never discard candidates as provably inferior unless a separate sound proof justifies that pruning.
- **Best use:** recommended first learned approach, compared against Option 1 under equal exact-simulation and wall-clock budgets.

### Option 3: Neural sequence model or LLM as a proposal generator

Train a sequence model conditioned on declared length and desired score, or use an LLM to propose candidate programs from descriptions and examples. Treat model outputs as candidate proposals only. Deduplicate and run every selected proposal through the exact simulator; use the resulting score as another training example. A score surrogate may rerank generated candidates before spending simulator time.

- **Strengths:** can propose combinations of instructions beyond simple one-nibble mutations and may learn recurring program structure from examples.
- **Limitations:** the corpus of known high-scoring programs at lengths 10–16 is very small. The generator may repeat examples, emit invalid or unproductive candidates, or exploit defects in the score predictor. It cannot establish score or optimality by itself.
- **Best use:** exploratory proposal source after the simulator-driven baseline and score model exist; measure its marginal improvement over mutation, template, and random proposals.

### Option 4: Exhaustive search and proven pruning

Continue optimizing exact enumeration, parallel execution, and formally proven equivalence or pruning rules. This can establish optima only when every candidate is covered or excluded by a sound proof. At lengths 10–16, raw search is too large for current practical budgets, but exact methods remain useful for smaller lengths, validating components, and certifying any reduced domain whose proof covers all omitted programs.

- **Strengths:** gives definitive maxima when complete; supplies rigorous correctness baselines and can benefit from parallelism or proven search-space reductions.
- **Limitations:** exhaustive coverage of the target lengths is outside current single-machine budgets. Empirical patterns, learned scores, or partial enumeration do not prove that omitted programs cannot do better.
- **Best use:** correctness reference and future certification work; do not present heuristic pruning as exhaustive search.

## Recommended experiment

Build a score-guided discovery loop with direct simulation as the authority:

1. **Inventory the baseline.** Gather and directly replay existing candidate programs for each target length. Record exact halted scores for 15 and 16; find any already-known candidates for 10–14 and label them with provenance. If a length has no established candidate, make that explicit rather than using an invented baseline.
2. **Create a clean data adapter.** Store `(declared_length, nibbles, status, output_characters_if_halted, logical_steps_if_available, simulator_version, run_limits, provenance)`. Keep CYCLE separate from timeouts, errors, and overflow. Use exact integer scores. Deduplicate identical `(length, program)` rows while retaining proposal method and run history.
3. **Establish non-ML baselines.** Compare random valid programs, random mutations of known candidates, local search, and structured templates. Fix a number of exact simulations per length and a wall-clock budget before each comparison. Use deterministic seeds so runs can be repeated.
4. **Train a score model.** Begin with a simple tabular model or small sequence model. Fit score targets only on HALTED examples and train termination separately. Keep unresolved runs visible in coverage reports. Avoid using full-run features at inference if the aim is to save simulator work.
5. **Run an adaptive loop.** Generate a diverse candidate pool, rank it by predicted improvement and uncertainty, select a batch, simulate it exactly, update per-length records and the training data, then repeat. Reserve a fixed evaluation set from proposal methods that does not change with adaptive rounds.
6. **Compare search outcomes.** Report best verified halted score versus exact simulation count and wall time for each length. Also report unique candidates, duplicate rate, termination mix, unresolved count, and model/training overhead. Compare surrogate-guided search with the fixed-budget mutation/template/random baselines.
7. **Verify record improvements.** Replay each new record directly with the production-equivalent simulator and save its full program, score, termination status, and trace or reproducible replay command. A score exceeding a claimed exhaustive result for lengths 1–9 signals a data or semantics discrepancy; for lengths 10–16, it improves the best-known lower bound only.

## Acceptance criteria for a first search experiment

- The current best-known score and candidate for each target length are documented with their source and evidence level; lengths without a baseline are marked as such.
- The label adapter preserves exact declared length and nibbles, distinguishes HALTED/CYCLE/unresolved outcomes, and agrees with direct replay on representative halting, printing-cycle, self-modifying, wrapping, zero-output, and overflow cases.
- A reproducible manifest records candidate generation method, random seed, execution limits, simulator version, deduplication, and exact simulation budget.
- The report compares at least one learned or model-guided method with mutation/template/random baselines under equal exact-simulation budgets, and includes measured wall time and best verified scores per length.
- No predicted or unresolved score is reported as a record. Every claimed improvement has a directly replayed halted program.
- Conclusions distinguish “best found within this budget” from “proven maximum.”

## Risks and decisions

- **Per-length tradeoff:** lengths 10–14 have no consolidated known records in the current explainer set, while 15 and 16 have starting candidates. Decide whether to spread budget across all seven lengths or prioritize likely structural payoff.
- **Search budget:** choose a maximum number of simulator calls and wall-clock time per length. Length 16 may have higher runtime per candidate than short lengths because of longer traces and state cycles.
- **Training distribution:** uniform sampling of all `16^N` programs will mostly produce weak candidates and may not expose useful structures. Mutations and adaptive proposals improve search focus but create selection bias; retain proposal provenance and a fixed comparison set.
- **Model objective:** mean score error, probability of exceeding the current record, and top-candidate ranking reward different behavior. Choose the acquisition metric based on search performance, not a generic accuracy score alone.
- **Generation approach:** choose whether neural or LLM generation is worth testing after measuring the mutation/template baseline. Keep it as a candidate source, not a scoring oracle.
- **Certification:** no learned method establishes an optimum. Decide separately whether any formal proof, exhaustive subspace search, or rigorous pruning is needed.

## Decision requested before implementation

Choose the initial target lengths and compute budget, and confirm whether the first experiment should prioritize a balanced search across lengths 10–16 or focus on selected lengths. The recommended starting point is a reproducible direct-simulation dataset and fixed-budget mutation/template baselines, followed by a surrogate-guided search evaluated against those baselines. Train on the exact character scores of every selected halted program; do not train only on winners.
