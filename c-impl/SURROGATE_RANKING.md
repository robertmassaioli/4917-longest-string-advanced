# Surrogate candidate ranking

`scripts/surrogate_rank.py` is a dependency-free baseline for ordering programs
before spending simulator time. It fits an inverse-Hamming nearest-neighbour
estimate from exact `4917-dataset-v1` JSONL rows. A neighbour must have the same
declared length; within that length, each nibble position contributes equally.
The length and program cells remain separate model inputs, and trailing zeroes
remain part of the candidate identity.

Only rows with `status: "halted"` and an exact integer `output_characters` are
score targets. Cycle, unresolved, and error rows are validated and excluded.
Malformed schema, length, program, status, or label data fail with a file and
line-specific error. Model predictions are estimates for ranking; they are not
verified execution results or probabilities of global optimality. Run a ranked
candidate through the direct simulator before recording its score.

Typical flow from the repository root:

```sh
python3 c-impl/scripts/surrogate_rank.py train \
  --data candidates.jsonl --model score-model.json
python3 c-impl/scripts/surrogate_rank.py rank \
  --model score-model.json --input candidate-pool.jsonl -k 5
python3 c-impl/scripts/surrogate_rank.py evaluate \
  --data candidates.jsonl --test-fraction 0.2 -k 5
```

Candidate-pool JSONL rows need `length` and `program`, for example
`{"length":3,"program":[1,0,15]}`. Ranking output is JSONL sorted by predicted
score descending and includes `predicted_output_characters` and the number of
neighbours used. A candidate whose length has no training examples receives a
null prediction and sorts after scored candidates.

Evaluation assigns each distinct `(declared length, nibble vector)` identity to
train or holdout using its SHA-256 digest, so duplicate rows cannot leak across
the split and the same dataset always produces the same split. The test
fraction controls the digest threshold. MAE and RMSE are reported only for
holdout candidates with at least one same-length training neighbour; the output
reports that scored count separately. This is a reproducible baseline check,
not an estimate of performance on every future proposal distribution.

The model artifact is plain JSON and stores its exact training examples. This
keeps the initial method inspectable and makes predictions deterministic for a
fixed artifact and candidate pool.
