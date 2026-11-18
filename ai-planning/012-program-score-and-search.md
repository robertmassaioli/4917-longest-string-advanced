# 012: Predict 4917 program scores and find long-output programs

**Created:** 2026-11-18

## Goal

Explore whether to build (a) a function that estimates whether a program is tied for the longest output at its declared length, (b) a model that predicts its output character count, or (c) a system that proposes programs likely to produce very long outputs. These goals are related, but they are different prediction and generation tasks.

The target is length-specific. A candidate is a nibble vector of declared length `N`, loaded at cells `0..N-1` and zero-padded to the 16-cell memory image. Trailing zero nibbles remain part of the declared candidate length, as they do in the exhaustive searches. The score is the number of decimal characters emitted (one for values 0–9, two for 10–15, excluding display separators), and only halted executions qualify. A candidate is a positive example exactly when its halted score equals the exhaustive best score for `N`; proven cycles and halted candidates with other scores are negative. A timeout, execution error, or counter overflow leaves the execution label unresolved; it does not prove a negative outcome.

Candidate identity is `(declared_length, nibble_vector)`, not just the padded memory or the last nonzero cell. For example, `[8,10]` and `[8,10,0]` execute from the same memory and both score 2, but the first wins at length 2 and the second loses at length 3. Preserve both identities and the declared length in datasets and model inputs.

For a fixed candidate, its execution and score are deterministic. A returned probability is the model's calibrated estimate under a stated candidate distribution, not randomness in the processor. A simulator can generate supervised labels: for every program we choose to include, run it and record its observed status and, when it halts, exact output character count. Retain unresolved attempts separately instead of inventing scores for them. We can train on any selected set of resolved candidates this way; we do not have to limit training data to known winners. Exhaustively labeling every possible program is a separate, potentially enormous choice, especially for lengths 8 and 9.

Predicting output length is often a more informative first learning task than predicting only “winner” or “not winner.” It uses the exact score from each simulation, including distinctions among losing programs. A score model can rank candidates and guide the next batch of simulations. A score estimate alone is not a calibrated winner probability: that probability needs a predicted score distribution and termination prediction, or a separate calibrated winner classifier.

## Available evidence

The repository's recorded exhaustive results for lengths 1–9 report zero errors and 240 tied winners in total. This review checked the recorded summaries and implementation; it did not rerun those exhaustive searches:

| Length | Best output characters | Tied winners |
|---:|---:|---:|
| 1 | 1 | 1 |
| 2 | 2 | 6 |
| 3 | 3 | 6 |
| 4 | 32 | 24 |
| 5 | 62 | 72 |
| 6 | 93 | 2 |
| 7 | 172 | 26 |
| 8 | 482 | 102 |
| 9 | 678 | 1 |

The complete winner lists and behavior descriptions are in [optimal-programs-length-1-to-7.md](../optimal-programs-length-1-to-7.md), [length-8.md](../explainers/length-8.md), and [length-9.md](../explainers/length-9.md), with shorter explanations for lengths 1–7 in `explainers/`. The data show repeated families, such as six winners differing only in a two-character PRINT operand, but also singleton winners with distinct control flow. A versioned lookup of all listed vectors can therefore classify winners exactly for these lengths without executing the input. The positive examples alone do not demonstrate that a learned model distinguishes similar-looking losers.

Relevant implementation constraints:

- [spec/processor.md](../spec/processor.md) defines cycle identity as all 16 memory cells, both registers, and PC, excluding output count. A bounded run reaching its step limit is unresolved, even if it has already printed output. Partial output from a cycle is not a finite halted score.
- [c-impl/src/machine.cpp](../c-impl/src/machine.cpp) exposes `i4917_run_until_halt_or_cycle`, resets registers/PC/output, and checks `uint64_t` accounting overflow. Use a direct execution path for labels, with [i4917_step](../c-impl/include/4917/machine.h) as a replay reference; do not assume every theoretical halting execution fits the implementation's counters or practical runtime budget.
- [BruteForceSearch.hs](../haskell-impl/src/BruteForceSearch.hs) contains heuristic filtering, timeout-to-zero conversion, and cache hits reported as halted. Its aggregate/cache results are not authoritative labels for this dataset; proposal [011](011-cli-search-range-checkpoints.md) also identifies these issues. A direct simulator adapter is needed; a durable per-candidate export is proposed work, not an existing dataset.
- Search range documentation is inconsistent: the shared spec describes the initial C length-1–4 command, the C++ README says 1–5, and [main.cpp](../c-impl/src/main.cpp) currently accepts 1–16. This proposal's certified winner target is limited by the recorded maxima for 1–9, independently of what lengths the CLI accepts. The [length-15](../explainers/length-15.md) and [length-16](../explainers/length-16.md) examples are explicitly best-known candidates, not exhaustive maxima.

## Proposed function contract

Conceptually:

```text
probability_of_length_winner(program: [Nibble]) -> Float  // inclusive range [0, 1]
```

The list length is the declared search length, including any trailing zeroes. Reject empty programs and programs longer than the 16-cell memory; reject values outside `0..15`. Keep `N` as an explicit model input even if a later API passes it separately. Return a probability estimate, not a predicted score. A companion diagnostic API may return the predicted halt/cycle status, predicted output character count, model version, and confidence interval, but the simple function should remain easy to call.

Also consider exposing a score prediction:

```text
predict_output_characters(program: [Nibble]) -> ScorePrediction
```

`ScorePrediction` should distinguish predicted termination from predicted output characters and may include uncertainty. A winner probability can be derived only if the model predicts a calibrated discrete distribution over termination and scores, or if a separate winner classifier is calibrated. Keep each API clear about whether it returns an exact simulation result or a model estimate.

For execution-derived training labels, use the following rules:

| Observed result | Halt target | Output-score target | Winner target when `best_score[N]` is certified |
|---|---|---|---|
| HALTED | 1 | Exact nonnegative character count, including zero | 1 iff score equals `best_score[N]`, otherwise 0 |
| Proven CYCLE | 0 | Absent | 0 |
| Step/time limit, error, or counter overflow | Unknown | Absent; retain any prefix only as diagnostic data | Unknown from execution alone |

A complete certified winner lookup can independently resolve the winner target for lengths 1–9 even when an execution attempt is unresolved; for nonmembers it cannot supply termination or score labels. Keep label provenance explicit. Use the exhaustive score table as the source of each length's maximum. If a certified maximum is unavailable, the winner API must report an unsupported length rather than silently reusing another target or treating a best-known score as an optimum. The conceptual `Float` signature above needs a documented error/result mechanism for invalid or unsupported inputs; choosing the language-specific form is implementation work. A score model or search can cover a longer length without claiming a winner label there, but must report its training coverage.

If score probabilities are conditional on halting, the intended relationship is `P(winner | program, N) = P(HALT | program, N) × P(score = best_score[N] | HALT, program, N)`. An unconditional joint distribution already includes halting and must not be multiplied by the halt probability a second time. A predicted mean score or interval does not determine the probability mass at one exact integer score.

## Options

### Option 1: Exact winner lookup, with simulator as the score oracle

For lengths with complete certified winner lists, compare `(N, program)` against a versioned set of all tied winners. Alternatively, execute the candidate directly and compare its halted score with the certified maximum. These are separate exact baselines: membership needs no execution, while simulation supplies termination and score labels for arbitrary candidates.

- **Output:** exactly `1.0` for tied winners and `0.0` for nonmembers of a complete certified list; execution alone must leave unresolved results explicit.
- **Strengths:** correct and interpretable; requires no model training. A 240-entry membership table covers the recorded length-1–9 winner task without simulation.
- **Limitations:** neither route estimates unknown maxima. Membership depends on complete, correctly transcribed lists and supplies no losing score. Simulation can be expensive or unresolved within available resources.
- **Best use:** membership as the baseline for supported-length classification; direct simulation as the score oracle and label generator.

### Option 2: Winner-family rules and generalized patterns

Extract structural patterns from the recorded winners and their traces: instruction placement, loop shape, register updates, branch conditions, output width, and operand families. Match a candidate to those patterns and assign a ranking score. A match warrants exact certainty only if every represented substitution is verified or proved to be a winner within the declared-length domain; approximate match scores need held-out calibration before being called probabilities.

- **Strengths:** compact, explainable, and directly grounded in the observed tied winners. It can recognize known families without executing every candidate to completion.
- **Limitations:** the current files mostly explain positive cases. Without negative examples, a pattern match can mistakenly give high probability to a near-match that cycles or emits fewer characters. Generalizer wildcards describe observed executions and must not be treated as proof that arbitrary substitutions preserve a score.
- **Best use:** readable feature extraction and candidate prioritization, paired with negative examples or exact replay before reporting high confidence.

### Option 3: Supervised output-score prediction from simulated programs

Choose programs from the candidate distribution of interest, run each through the direct simulator, and train a model to predict its termination and output character count conditional on halting. The training labels are resolved simulator results, not estimates from the winner explanations. Candidate inputs can be the raw nibble sequence plus declared length and optional static features. Static features must allow for operands also being executed as instructions, jumps into operands, wrapping, and self-modifying memory; a simple linear disassembly is not authoritative. If prediction is meant to be faster than simulation, do not feed the model features that require running that same full simulation.

- **Output:** predicted termination and output character count. A probabilistic model can estimate a score distribution; combining it with the halt probability gives a candidate winner probability against the known maximum.
- **Strengths:** each halted candidate contributes a score label, not just a rare positive/negative label; proven cycles contribute termination labels. We can stream selected batches without saving every full trace. The score model supports ranking and can guide which programs to simulate next.
- **Limitations:** errors near the maximum matter more than average score error. A model that predicts average output length accurately may still miss the exact tied winners. Probability of an exact score needs calibration. Cycles have no halted-score target, and unresolved attempts must not be silently dropped without reporting coverage and selection bias.
- **Best use:** the first learned baseline for estimating scores and prioritizing candidates, with exact simulation of promising candidates.

### Option 4: Neural network or LLM for score prediction or winner probability

Train a neural network to consume the nibble sequence as tokens and predict termination plus output character count, or predict the winner label directly. An LLM could instead be prompted or fine-tuned on program/execution examples to estimate a score or winner probability. The same simulator-generated dataset can supply resolved labels, with the status and missing-target rules above.

- **Strengths:** neural sequence models may learn interactions between instruction positions and loop structure that hand-built features miss. Using exact scores from selected halted simulations gives much richer supervision than the 240 known winners alone. A trace-aware model may learn from modular counter behavior; an LLM can help inspect patterns.
- **Limitations:** success depends on representative candidate coverage and generalization to unseen structures. Winner-only training remains too small and imbalanced. LLM numerical confidence is not automatically calibrated, and explanations are not evidence of correctness.
- **Best use:** compare a small sequence model against simpler score-prediction baselines on the same held-out programs; treat LLM scoring as exploratory.

### Option 5: Generate long-output programs

Train a sequence generator to produce programs conditioned on a declared length and desired score, or use a search algorithm that proposes mutations to known high-scoring programs. Deduplicate proposals and simulate those selected for evaluation, preserving unresolved results. A learned score predictor from Option 3 can rank proposals and focus simulation on promising ones; exact halted simulation remains the authority on whether a candidate improves the best-known score. For lengths 1–9, a score above the certified maximum signals a semantics, data, or implementation discrepancy to investigate. Discovery of a new record is relevant to lengths without a certified maximum, and establishes a lower bound rather than optimality.

- **Strengths:** directly targets discovery of new long-output programs instead of merely classifying candidates. Existing winners and other high-scoring examples can seed mutations, while simulation provides exact feedback on every proposal.
- **Limitations:** the 240 known winners are a small dataset for training a generator by imitation. Generators can repeat known structures or exploit errors in a learned scoring model. High predicted score does not guarantee a long halting run.
- **Best use:** begin with mutation/evolutionary search guided by an exact simulator or score-model surrogate; verify all top candidates exactly. Consider a generative neural model later if a broader corpus of simulated programs is available.

## Recommended approach

If the primary need is winner classification for lengths 1–9, prefer the exact membership baseline; a learned probability adds no correctness benefit for that closed domain. If the need is score prediction or discovery, the recommended experiment is a simulator-labeled score dataset, followed by an Option 3 baseline. Use Option 2 as an interpretable comparison and feature source, then compare a small neural model from Option 4 on the same data. Add a calibrated winner probability only if a caller needs it and the available held-out positives support that claim. Explore Option 5 as a separate search objective, with direct simulation verifying every promising proposal.

The simulator can label chosen random programs, structured mutations, candidates produced by search, or exhaustive manageable lengths. Existing exhaustive summaries do not contain per-candidate losing scores, so a score corpus requires replay or new execution/export work. Record the sampling method, random seed, search round, duplicate handling, and any known sampling probabilities. Balance or enrich training data when useful, but reserve calibration and evaluation data from the intended deployment distribution. Importance weighting requires known sampling probabilities and coverage of the target distribution; it is not a general correction for arbitrary adaptive search samples.

## Training and evaluation plan

1. **Create a versioned simulator-labeled dataset.** Store declared length, nibble vector, observed execution status, exact output character count for halted candidates, logical steps where defined, simulator revision/build, execution limits, and label provenance. Keep unresolved attempts with their reason. Store certified maxima and complete winner lists with their source/version separately. Keep full traces only when useful. Preserve integer counts losslessly in storage rather than converting them through floating point.
2. **Select training candidates deliberately.** Choose supported lengths, sample counts, execution limits, and a compute/storage budget before collection. Mix uniform samples with structured mutations and search candidates as appropriate to the chosen goal. Every included attempt retains its status; only resolved outcomes supply the corresponding targets. Preserve a representative held-out set from the intended use distribution, and report resolved coverage by length and sampling method.
3. **Compare score models.** Start with per-length mean/median predictions fitted to halted training examples and a small tabular model, then compare neural sequence models. Report termination accuracy/precision-recall separately; compute score MAE and exact score accuracy on truly halted examples. Define the high-score threshold, ranking pool, K, and tie handling before measuring top-K recall. Evaluate candidate ranking across the whole pool, including cycles, and report near-maximum error separately. Measure inference cost including feature extraction against direct simulation on the same candidates.
4. **Evaluate winner probabilities separately.** Compare the family matcher and learned classifier with exact membership and a per-length constant prevalence baseline, `winner_count[N] / 16^N`, for uniform candidates. Report positive/negative counts, precision-recall, Brier score, log loss, and calibration by length. An all-negative evaluation set cannot establish winner recall or calibration near 1. At length 9 the uniform prevalence is `1 / 68,719,476,736`; random sampling is unlikely to include its sole winner. Enriched winner challenges can assess discrimination but cannot alone establish calibration for uniform traffic. Report a metric as unidentifiable when the split has insufficient positives.
5. **Test generalization honestly.** Deduplicate `(N, program)` before splitting. Group structural families and equal padded memory images in the same partition when evaluating transfer across lengths: the latter share execution scores even when their winner labels differ. Reserve separate training, calibration, and final evaluation partitions, and record whether family rules were designed using held-out winners. With singleton winners at lengths 1 and 9, a split cannot both train and test on independent winners at those lengths; report this limitation. Holdout-family evaluation and representative-distribution evaluation answer different questions. Keep adaptive search rounds out of the fixed test set and do not assume results on lengths 1–9 transfer to longer lengths, especially self-modifying programs.
6. **Try guided generation only for the selected search objective.** Compare mutation/evolutionary search and surrogate-guided search with a random proposal baseline at equal simulation budgets, also reporting wall time and model/training overhead. Track unique candidates, duplicates, unresolved attempts, best verified halted score over budget, and rediscovery of known winners where applicable. Freeze the comparison budget and initial seeds before comparing methods; every claimed improvement needs direct halted replay.

## Acceptance criteria for an initial experiment

These criteria define a reviewable experiment, not a commitment to ship a learned API:

- A reproducible data manifest records lengths, sampling seeds/methods, simulator revision, limits, target versions, and split assignments. Counts reconcile across HALTED, CYCLE, and unresolved statuses; no timeout or partial output becomes a halted-score target.
- The labeling adapter is checked against direct single-step replay on representative halted, printing-cycle, wrapping, and self-modifying cases, and against the recorded winner scores. `[0]` is a valid zero-output halt; `[8,1,13,0]` is a printing cycle. Invalid inputs and unsupported winner lengths have explicit outcomes.
- A complete winner artifact reproduces the table's per-length counts and 240 total entries, preserves declared length, and passes the `[8,10]` versus `[8,10,0]` identity example. These checks validate the artifact; they are not evidence that a learned model generalizes.
- The evaluation report includes simple baselines, per-length coverage and positive counts, fixed split definitions, score/ranking metrics, and measured cost. Model promotion thresholds and the initial budget remain decisions to make before running the experiment; a negative result is a valid outcome.

## Main risks and open design choices

- **Meaning of probability:** users may read it as physical randomness. Documentation should call it the model's estimated chance of belonging to the tied-winner class under the specified candidate distribution. Predicted output length is a separate quantity.
- **Candidate distribution:** prevalence is different for each length and changes if candidates are generated from mutations, a search heuristic, or the full uniform space. Return probabilities only with a declared distribution and per-length calibration.
- **Target drift:** a new search result, scoring change, or simulator correction changes the labels. Version the dataset and retrain/calibrate when any of these change.
- **Near-maximum behavior:** the requested target is a tied winner, not “close to the maximum.” If useful, expose estimated score or probability of being within a chosen score margin as a separate function later.
- **Runtime:** if inference requires simulating an input to extract execution features, it may provide no speed benefit over exact scoring. A static-only model is faster but needs stronger validation. Training labels can still come from exact simulation even when prediction uses static features only.

## Decision requested for implementation

Before implementation, choose the primary goal: (a) exact winner classification, (b) output-character prediction, or (c) generation/search for long-output programs. For (a), the complete winner lookup may fully meet the need for lengths 1–9. For (b) or (c), the recommended first step is a reusable direct-simulator labeling adapter and an output-score baseline; winner probability and generation can then use the same data as separate follow-on experiments.

The intended candidate distribution and length range, initial compute/storage budget, acceptable latency/accuracy or search improvement, and treatment of unresolved executions at the public API boundary still need decisions. The invariant is that unresolved execution is not proof of a losing program; whether to retry, return an explicit unresolved result, or use certified membership when available depends on the selected API. No model family, numerical promotion threshold, or promise of calibrated winner probabilities is approved by this proposal alone.
