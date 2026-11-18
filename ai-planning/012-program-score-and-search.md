# 012: Predict 4917 program scores and find long-output programs

**Created:** 2026-11-18

## Goal

Explore whether to build (a) a function that estimates whether a program is tied for the longest output at its declared length, (b) a model that predicts its output character count, or (c) a system that proposes programs likely to produce very long outputs. These goals are related, but they are different prediction and generation tasks.

The target is length-specific. A candidate is a nibble vector of declared length `N`, loaded at cells `0..N-1` and zero-padded to the 16-cell memory image. Trailing zero nibbles remain part of the declared candidate length, as they do in the exhaustive searches. The score is output character count, and only halted executions qualify. A candidate is a positive example exactly when its halted score equals the exhaustive best score for `N`; every other candidate, including cycles and execution errors, is negative.

For a fixed candidate, its execution and score are deterministic. A returned probability is the model's calibrated estimate under a stated candidate distribution, not randomness in the processor. An exact simulator can generate supervised labels: for every program we choose to include, run it and record its termination status and exact output character count. We can train on any selected set of candidates this way; we do not have to limit training data to known winners. Exhaustively labeling every possible program is a separate, potentially enormous choice, especially for lengths 8 and 9.

Predicting output length is often a more informative first learning task than predicting only “winner” or “not winner.” It uses the exact score from each simulation, including distinctions among losing programs. A score model can rank candidates and guide the next batch of simulations. A score estimate alone is not a calibrated winner probability: that probability needs a predicted score distribution and termination prediction, or a separate calibrated winner classifier.

## Available evidence

The exhaustive results for lengths 1–9 record 240 tied winners in total:

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

The winner lists and behavior descriptions are in `optimal-programs-length-1-to-7.md` and `explainers/length-1.md` through `explainers/length-9.md`. The data show repeated families, such as six winners differing only in a two-character PRINT operand, but also singleton winners with distinct control flow. The positive set alone is not enough to train a probability model: it does not describe how often similar-looking losers occur.

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

For training, use `label = 1` iff `termination == HALTED && output_characters == best_score[N]`; otherwise `label = 0`. Use the exhaustive score table as the source of each length's maximum. If the known exhaustive maximum is not available for a requested length, the function must say that the length is unsupported rather than silently reusing another length's target.

## Options

### Option 1: Exact simulator and known-maximum lookup

Run the existing processor semantics for the input candidate, then compare its halt status and output character count with the known maximum for that length.

- **Output:** exactly `1.0` for tied winners and `0.0` for all others.
- **Strengths:** correct and interpretable; requires no model training; a useful reference implementation and label generator.
- **Limitations:** it is not an estimate and it does the program execution that the predictor might have been intended to avoid. A candidate that loops for a long time may also be expensive to classify.
- **Best use:** oracle/baseline for supported lengths, correctness checks, and generation of labeled examples.

### Option 2: Winner-family rules and generalized patterns

Extract structural patterns from the recorded winners and their traces: instruction placement, loop shape, register updates, branch conditions, output width, and operand families. Match a candidate to those patterns and assign a score based on the match. A strict match to a verified family could receive probability 1; an approximate or partially matching candidate could receive a lower value.

- **Strengths:** compact, explainable, and directly grounded in the observed tied winners. It can recognize known families without executing every candidate to completion.
- **Limitations:** the current files mostly explain positive cases. Without negative examples, a pattern match can mistakenly give high probability to a near-match that cycles or emits fewer characters. Generalizer wildcards describe observed executions and must not be treated as proof that arbitrary substitutions preserve a score.
- **Best use:** readable feature extraction and candidate prioritization, paired with negative examples or exact replay before reporting high confidence.

### Option 3: Supervised output-score prediction from simulated programs

Choose programs from the candidate distribution of interest, run each through the exact simulator, and train a model to predict its output character count and termination status. The training labels are the simulator's exact results, not estimates from the winner explanations. Candidate inputs can be the raw nibble sequence plus declared length and optional static features. If prediction is meant to be faster than simulation, do not feed the model features that require running that same full simulation.

- **Output:** predicted termination and output character count. A probabilistic model can estimate a score distribution; combining it with the halt probability gives a candidate winner probability against the known maximum.
- **Strengths:** each simulated candidate contributes a score label, not just a rare positive/negative label. We can label every program in a selected batch and stream large datasets without saving every full trace. The score model supports ranking and can guide which programs to simulate next.
- **Limitations:** errors near the maximum matter more than average score error. A model that predicts average output length accurately may still miss the exact tied winners. Probability of an exact score needs calibration, and cycles need a separate termination target rather than an invented character count.
- **Best use:** the first learned baseline for estimating scores and prioritizing candidates, with exact simulation of promising candidates.

### Option 4: Neural network or LLM for score prediction or winner probability

Train a neural network to consume the nibble sequence as tokens and predict termination plus output character count, or predict the winner label directly. An LLM could instead be prompted or fine-tuned on program/execution examples to estimate a score or winner probability. The same simulator-generated dataset can supply exact labels for every chosen example.

- **Strengths:** neural sequence models may learn interactions between instruction positions and loop structure that hand-built features miss. Using exact scores from all selected simulations gives much richer supervision than the 240 known winners alone. A trace-aware model may learn from modular counter behavior; an LLM can help inspect patterns.
- **Limitations:** success depends on representative candidate coverage and generalization to unseen structures. Winner-only training remains too small and imbalanced. LLM numerical confidence is not automatically calibrated, and explanations are not evidence of correctness.
- **Best use:** compare a small sequence model against simpler score-prediction baselines on the same held-out programs; treat LLM scoring as exploratory.

### Option 5: Generate long-output programs

Train a sequence generator to produce programs conditioned on a declared length and desired score, or use a search algorithm that proposes mutations to known high-scoring programs. Simulate every proposal to obtain its exact score. A learned score predictor from Option 3 can rank proposals and focus simulation on promising ones; exact simulation remains the authority on whether a candidate improves the record.

- **Strengths:** directly targets discovery of new long-output programs instead of merely classifying candidates. Existing winners and other high-scoring examples can seed mutations, while simulation provides exact feedback on every proposal.
- **Limitations:** the 240 known winners are a small dataset for training a generator by imitation. Generators can repeat known structures or exploit errors in a learned scoring model. High predicted score does not guarantee a long halting run.
- **Best use:** begin with mutation/evolutionary search guided by an exact simulator or score-model surrogate; verify all top candidates exactly. Consider a generative neural model later if a broader corpus of simulated programs is available.

## Recommended approach

Build a simulator-labeled score dataset first. Keep Option 1 as the exact oracle and label generator; use Option 2 as an interpretable baseline and feature source. Train Option 3 to predict termination and output characters, then compare a small neural model from Option 4 against it. This provides useful score estimates even for programs that are not winners. Add a calibrated winner probability only if a caller needs it and it performs well against exact outcomes. Explore Option 5 as a separate search objective, with exact simulation verifying every promising proposal.

The winner lists alone are not enough to train a useful probability model, but the simulator can label any programs we choose to sample: store the candidate, whether it halted, and the exact number of output characters it printed. We can use random programs, structured mutations, candidates produced by search, or exhaustively enumerate manageable lengths. Lengths 8–9 have already been exhaustively searched, but storing every candidate and full trace would be wasteful; the search can stream examples, retain compact features, or save a chosen sample. If training on a biased or balanced sample, record its proposal distribution and correct calibration to the distribution in which the predictor will be used.

## Training and evaluation plan

1. **Create a versioned simulator-labeled dataset.** Store declared length, nibble vector, termination status, exact output character count for halted candidates, steps, simulator/search version, and sampling method. Store each length's exhaustive maximum separately. Keep full traces only when useful.
2. **Select training candidates deliberately.** Mix uniform samples with structured mutations and candidates from search. Every included program gets its exact score from simulation. Preserve a representative held-out set from the intended use distribution.
3. **Compare score models.** Start with a per-length mean/median baseline and a small tabular model, then test neural sequence models. Measure score MAE, exact score accuracy, and top-K recall for high-scoring programs by length. Report error near the maximum separately.
4. **Evaluate winner probabilities separately.** Compare the family matcher, exact simulator, and learned winner classifier. Measure precision-recall, Brier score, log loss, and calibration at each length. Correct for sample bias and extreme class imbalance.
5. **Test generalization honestly.** Hold out structural families and report per-length results. A random split can put programs differing only in a PRINT operand on both sides. Do not assume results on lengths 1–9 transfer to length 10 or beyond.
6. **Try guided generation.** Have mutation/evolutionary search propose programs, use exact simulation or a validated score model to prioritize them, and simulate all candidates that may set a record exactly. Track verified scores, not model confidence alone.

## Main risks and open design choices

- **Meaning of probability:** users may read it as physical randomness. Documentation should call it the model's estimated chance of belonging to the tied-winner class under the specified candidate distribution. Predicted output length is a separate quantity.
- **Candidate distribution:** prevalence is different for each length and changes if candidates are generated from mutations, a search heuristic, or the full uniform space. Return probabilities only with a declared distribution and per-length calibration.
- **Target drift:** a new search result, scoring change, or simulator correction changes the labels. Version the dataset and retrain/calibrate when any of these change.
- **Near-maximum behavior:** the requested target is a tied winner, not “close to the maximum.” If useful, expose estimated score or probability of being within a chosen score margin as a separate function later.
- **Runtime:** if inference requires simulating an input to extract execution features, it may provide no speed benefit over exact scoring. A static-only model is faster but needs stronger validation. Training labels can still come from exact simulation even when prediction uses static features only.

## Decision requested for implementation

If this proposal is accepted, the first implementation should choose the primary goal: (a) exact winner classification, (b) output-character prediction, or (c) generation/search for long-output programs. The recommended first step is a reusable simulator-labeling pipeline and an output-score prediction baseline; winner probability and program generation can then use the same exact data and simulator as separate follow-on tasks.
