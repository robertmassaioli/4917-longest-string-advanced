# 012: Estimate whether a 4917 program is a length-specific winner

**Created:** 2026-11-18

## Goal

Define a function that accepts a program and returns a value in `[0, 1]` estimating whether that program halts and emits the maximum number of decimal characters found for its declared length.

The target is length-specific. A candidate is a nibble vector of declared length `N`, loaded at cells `0..N-1` and zero-padded to the 16-cell memory image. Trailing zero nibbles remain part of the declared candidate length, as they do in the exhaustive searches. The score is output character count, and only halted executions qualify. A candidate is a positive example exactly when its halted score equals the exhaustive best score for `N`; every other candidate, including cycles and execution errors, is negative.

For a fixed candidate, this truth value is deterministic. The returned probability should be understood as a calibrated estimate under the training distribution, not as randomness in the processor. A `1` means the model is confident that the candidate is a tied winner; `0` means it is confident that it is not.

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

### Option 3: Calibrated statistical classifier on execution and static features

Generate labeled candidates from exhaustive searches and train a small model such as logistic regression or gradient-boosted trees. Candidate features can include declared length, opcode and operand positions, instruction counts, presence of PRINT/JZ/JNZ/JMP, static control-flow relationships, register-use summaries, and execution-derived features such as termination kind, output count, steps, and repeated-state/cycle information. Execution-derived features make this a fast surrogate for a slower or bounded evaluator, but if full execution is already cheap, Option 1 remains the simpler exact answer.

- **Output:** a probability from a calibrated classifier, with calibration measured on held-out candidates.
- **Strengths:** more data-efficient and interpretable than a large neural model; can combine program shape with trace evidence; easy to benchmark against simple baselines.
- **Limitations:** the positive class is extremely rare, especially at length 9 (one winner among about 68.7 billion candidates). Training on an artificially balanced sample without correcting for the true class prevalence produces misleading probabilities. Random row splits can also leak near-identical members of a winner family across train and test sets.
- **Best use:** a practical learned predictor if we can generate representative negative examples and maintain per-length calibration.

### Option 4: Neural network or LLM classifier

Train a neural network to consume the nibble sequence as tokens, optionally alongside a compact execution trace. The network can output a sigmoid probability for the binary target. An LLM could instead be prompted or fine-tuned on program/trace examples and asked to return a probability, though it should be treated as a less controlled variant of this option.

- **Strengths:** neural models can learn interactions between instruction positions and loop structure that hand-built features may miss. A trace-aware model can learn from the modular counter patterns visible at lengths 4–9. An LLM can also produce explanations that help inspect candidate families.
- **Limitations:** 240 positives alone are far too few for reliable training. Strong class imbalance, length-specific changes in the winning structures, and LLM probability calibration are major risks. Explanations are not evidence of correctness. A model trained on sampled negatives must be calibrated to the real prevalence for each length.
- **Best use:** research comparison after building the same labeled dataset used for Option 3; use a small sequence model first, and evaluate an LLM as a separate exploratory baseline.

## Recommended approach

Build a hybrid in stages. Keep Option 1 as the exact oracle for lengths with known exhaustive maxima. Implement Option 2 as a transparent baseline and feature source. Then compare Option 3 with Option 4 using the same held-out data. The shipped predictor should use a learned model only if it beats the baselines on both ranking and probability calibration; otherwise the honest behavior is exact `0/1` where affordable and an explicitly uncalibrated heuristic score elsewhere.

Do not claim a useful probability from the winner lists alone. They identify positive programs but do not supply the losing-program distribution needed to estimate false-positive rates. Generate training data by replaying candidates through the production-equivalent simulator. For lengths 1–7, the complete spaces are feasible to regenerate; lengths 8–9 are larger but were already exhaustively searched, so the search path can be extended to stream labels or deterministic feature summaries. Preserve complete per-length prevalence where feasible. If using negative subsampling, record each sampling probability and apply inverse-probability weighting or prior correction during calibration.

## Training and evaluation plan

1. **Create a versioned dataset.** Store the declared length, nibble vector, termination status, output character count, steps, label, and simulator/search version. Record the maximum score and exhaustive-search provenance per length. Keep outputs/trace detail only where needed to manage dataset size.
2. **Use length-aware splits.** Hold out entire structural families, not just random candidates, so the test set measures recognition of unseen variants. Also report per-length results, since a pooled score can conceal a failed length.
3. **Compare against simple baselines.** Include the constant per-length prevalence, exact simulator, and winner-family matcher. Measure precision-recall, Brier score, log loss, and calibration plots. ROC AUC alone is inadequate for this rare positive class.
4. **Calibrate probabilities per length.** Use a held-out calibration set with prevalence representative of the actual search space, or apply a documented prior correction when negatives were subsampled. Report uncertainty when a length has too few positive examples.
5. **Test generalization honestly.** A random split can put programs differing only in a PRINT operand on both sides. Include family-held-out evaluation, plus leave-one-length-out experiments as a stress test. Do not promise that success on lengths 1–9 transfers to length 10 or beyond.
6. **Choose based on the intended cost.** If the function is used to avoid execution, measure classification speed and false positives under that budget. If execution is affordable, prefer the exact result rather than a probability estimate.

## Main risks and open design choices

- **Meaning of probability:** users may read it as physical randomness. Documentation should call it the model's estimated chance of belonging to the tied-winner class under the specified candidate distribution.
- **Candidate distribution:** prevalence is different for each length and changes if candidates are generated from mutations, a search heuristic, or the full uniform space. Return probabilities only with a declared distribution and per-length calibration.
- **Target drift:** a new search result, scoring change, or simulator correction changes the labels. Version the dataset and retrain/calibrate when any of these change.
- **Near-maximum behavior:** the requested target is a tied winner, not “close to the maximum.” If useful, expose estimated score or probability of being within a chosen score margin as a separate function later.
- **Runtime:** if inference requires simulating an input to extract execution features, it may provide no speed benefit over exact scoring. A static-only model is faster but needs stronger validation.

## Decision requested for implementation

If this proposal is accepted, the first implementation should specify whether the primary caller wants (a) an exact answer, (b) a fast learned estimate before full execution, or (c) a candidate-ranking score for search. That choice determines whether execution-derived features are permitted and what false-positive rate is acceptable.
