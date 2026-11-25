# Provisional winner logging hill climb (2026-11-25)

## Goal and method

Reduce the runtime cost of writing provisional length-9 winners while retaining
every candidate that ties the observed best score or exceeds it. The target was
capture-on runtime indistinguishable from capture-off runtime. The evaluator was
the Release Metal solver with `--length 9 --gpu-step-limit 256 --json`; runs
were serial because they share the same GPU. Every accepted candidate had to
produce the same exhaustive totals, best score, and final winning program.

The length-9 expected result was:

- Candidates: `68,719,476,736`
- Halted: `60,931,421,044`
- Cycled: `7,788,055,692`
- Errors: `0`
- Best output: `678`
- Unique winner: candidate ID `36727313007`, program `[8,8,13,1,14,5,2,6,15]`

## Measurements

| Variant | Runtime | Provisional rows | Result |
|---|---:|---:|---|
| Capture off, six runs | 73.42–76.13s; mean 75.03s | — | Reference |
| Initial streaming prototype, two runs | 78.74–81.66s; mean 80.20s | 477–482 | Correct; baseline for this campaign |
| Check worker-local best before shared atomic | 78.69s | 478 | Correct; modest improvement over initial prototype |
| Worker-local threshold only | 88.71s | 14,032,929 | Rejected; generated about 1.8 GB of provisional rows |
| Format a row then do one write under lock | 79.72s | 531 | Correct; no improvement |
| Worker-best guard plus single-write formatting | 78.90s | 516 | Correct; no improvement |
| Batch-level maxima and tie logging, initial two runs | 77.38–78.01s; mean 77.70s | 311 | Correct; fastest candidate in the initial comparisons |
| Batch maxima with inline tie storage | 78.33s | 311 | Correct; no improvement |
| Batch maxima with threshold-gated tie storage | 78.43s | 311 | Correct; no improvement |
| Batch maxima with final buffered file write | 77.66s | 311 | Correct; no repeatable improvement |
| Final campaign build, two consecutive runs | 75.94–76.11s; mean 76.03s | 311 | Correct; final run pair |

The batch-level candidate improves the initial streaming prototype by about
2.5 seconds (3.1%) in the first comparison. Later runs of the final campaign
build were faster: 76.11s and 75.94s. The adjacent capture-off run was 76.05s,
so the on/off difference in that sequence was 0.11s in favor of logging. That
is indistinguishable from run-to-run noise and meets the practical parity
target. Earlier batch-level measurements were 1–2 seconds slower, showing that
single-run measurements are noisy on this machine; the final adjacent pair is
the best available apples-to-apples evidence.

## Correctness checks

All reported length-9 runs had identical exhaustive search counters and the
same unique 678-character winner. The batch-level JSONL had 311 records; its
maximum-score row was candidate ID `36727313007` with program
`[8,8,13,1,14,5,2,6,15]`. Filtering records to the final score yields the same
winner as the regular capture run.

The batch-level implementation keeps each worker's current maximum and its
ties. After the worker pass, the search combines those summaries, advances the
shared provisional threshold once per batch, and writes ties only when the
batch maximum meets that threshold. A final global winner must be a maximum
within its worker summary and its batch, so the final ties remain represented.

## Recommendation

Keep the batch-level candidate as the fastest tested streaming implementation.
The final adjacent run pair found no measurable runtime penalty while preserving
the exact exhaustive result and provisional winner file. The capture-off
reference was built from the regular solver branch, while the experimental
implementation was based on the winner-capture branch; search counters match,
but a same-revision A/B build would make attribution more precise.
