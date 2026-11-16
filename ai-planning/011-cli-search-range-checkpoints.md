# 011: Add resumable Haskell search over deterministic program ranges

**Status:** Proposed
**Created:** 2026-11-16

## Summary

Add an opt-in Haskell search mode that evaluates an explicit half-open range of
program IDs, writes candidate outcomes incrementally, and checkpoints a durable
completed prefix. Separate CLI processes can search disjoint ranges without
sharing mutable files. A cancelled search can resume without losing accepted
outcomes or counting a candidate twice.

Partitioning distributes the existing domain; it does not reduce it. The first
version evaluates every candidate in its range directly. A future Lean-verified
screen may reduce execution work, but needs its own proof, implementation
refinement argument, and accounting contract before being enabled here.

## Current behavior and motivation

[`CLI.hs`](../haskell-impl/src/CLI.hs) exposes `search --length N`, `--fresh`,
`--cache-file`, and `--verbose`.
[`Commands/Search.hs`](../haskell-impl/src/Commands/Search.hs) delegates to
[`BruteForceSearch.hs`](../haskell-impl/src/BruteForceSearch.hs), which accepts
lengths 1–8 and generates `sequence (replicate N [0..15])`. It materializes
results, selects a positive-output best candidate, and saves an advanced cache
at the end. There is no ID range, durable progress cursor, or candidate result
stream. Interrupted long searches therefore have no explicit coverage record.

The existing path also uses a heuristic unreachable-HALT filter for lengths
up to four, maps timeouts to zero output, and labels advanced-cache hits as
`Halt` when converting them to results. Those behaviors cannot support a new
claim of exhaustive, sound coverage. Introduce the range mode through a new
runner and direct evaluator; do not route it through these shortcuts. Keep the
legacy invocation available and clearly label its behavior until a separate
migration addresses those issues.

Proposal [009](009-multiprocess-search-work-queue.md) covers an in-process
coordinator and worker processes for the C implementation. This proposal
covers independently launched Haskell searches, file durability, and resumption.
It requires no worker pool or network scheduler.

## Candidate identity and length

For supplied length `N`, the domain is all `16^N` vectors of exactly `N` nibbles,
including trailing zeroes. Accept `1 <= N <= 8` initially, matching the existing
Haskell search limit. Zero-pad the vector to all 16 memory cells and initialize
PC and registers exactly as the processor loader does.

Define a program ID using memory order, with cell zero most significant:

```text
id([b0, ..., b(N-1)]) = sum(bi * 16^(N-1-i), i = 0..N-1)
bi = (id div 16^(N-1-i)) mod 16
```

For length four, ID `0x380f` means `[3,8,0,15]`; ID `0x0001` means
`[0,0,0,1]`. This is nibble order, not a host integer's byte order. Ascending
IDs match `generateAllPrograms` ordering. Preserve leading zeroes in program
vectors and fixed-width hexadecimal displays.

The effective length is the last nonzero cell index plus one (zero for an
all-zero image). It is metadata only. Do not filter vectors by effective
length or merge equal padded images across supplied lengths. The candidate
identity is `(supplied_length, program_id)`; a witness or incumbent from another
supplied length must be explicitly re-encoded before comparison.

Use Haskell `Integer` for IDs, powers, endpoints, counters, scores, and persisted
integer arithmetic. Do not use `Int`, floating point, or a JSON number for those
fields. This also represents the future length-16 exclusive endpoint `16^16`
without wraparound; supporting length 16 remains a separate change.

## CLI contract

All syntax below is proposed. Run from `haskell-impl/`:

```sh
# Search [0x30000000, 0x40000000), not including the second endpoint.
stack exec 4917-cli -- search --length 8 \
  --range 0x30000000:0x40000000 --max-steps 1000000 \
  --checkpoint shard3.checkpoint.json --results shard3.results.jsonl

# Search shard index 3 of 16 equal proportional ranges (zero-based).
stack exec 4917-cli -- search --length 8 --shard 3/16 \
  --max-steps 1000000 --checkpoint shard3.checkpoint.json \
  --results shard3.results.jsonl --checkpoint-every 1000

# Resume using the entire saved configuration; no range flags to retype.
stack exec 4917-cli -- search --resume shard3.checkpoint.json
```

`--range A:B` accepts unsigned decimal or `0x` hexadecimal endpoints and means
`A <= id < B`. Require `0 <= A <= B <= 16^N`; allow an empty range and report
zero coverage and no best candidate. Reject negative numbers, fractions,
missing endpoints, embedded signs, and overflow into any bounded internal
representation. Reject `--range` with `--shard`.

For `--shard K/S`, require `S > 0` and `0 <= K < S`, and compute:

```text
begin = floor(K * 16^N / S)
end   = floor((K + 1) * 16^N / S)
```

These contiguous intervals partition the domain exactly even when `S` does not
divide it. Shards may be empty when `S > 16^N`. Give each shard distinct result,
checkpoint, and lock paths. No shared cache or result file is supported.

New mode is selected by `--range`, `--shard`, or `--resume`. A new invocation
requires `--length`, explicit `--max-steps`, `--checkpoint`, and `--results`.
Keep legacy `search` defaults out of this mode. Reject its `--fresh` and
`--cache-file` flags here; do not silently reuse or delete an advanced cache.

`--checkpoint-every C` defaults to 1000 candidate outcomes and must be positive.
A monotonic five-second timer also triggers a checkpoint at the next candidate
boundary, whichever trigger occurs first. This bounds the normal pending result
batch without writing a checkpoint after every fast candidate. One bounded
candidate may take longer than five seconds. `--verbose` writes progress to
stderr; stdout is a final versioned JSON summary. Candidate JSONL uses its
explicit file, so diagnostics cannot corrupt it.

## Evaluation, best scores, and unresolved candidates

Extract a bounded evaluator with an explicit result sum:

- `halt`: HALT was executed within the limit; store the final character score.
- `cycle`: a repeated execution state was established; store cycle evidence.
- `unknown`: the instruction bound was reached without either conclusion;
  store the observed prefix score, never a final score or winning result.

HALT on the last allowed instruction is a halt. A zero step limit evaluates no
instruction and yields unknown, even when the initial opcode is HALT. A cycle
key contains all 16 current memory cells, both registers, and PC; output count
and elapsed time do not affect future behavior. STORE therefore cannot be
ignored. Use only a cycle detector whose state identity and HALT ordering have
been established against the processor contract; until that is ready, emit
`unknown` at the bound and omit early cycle classification. Repeated PC alone
is insufficient evidence. No timeout, externally killed run, missing result,
or error can be converted into `cycle`.

Unexpected evaluator errors stop the search with a nonzero exit status. Keep
the cursor at the failing candidate so it is not silently skipped on resume.
Do not mark interrupted in-flight execution as a completed candidate. Restart
that candidate from its initial state when resuming.

Track the maximum score among halted candidates in the range, the number of
candidates tying it, and the lowest ID at that score. Include zero-output
halters; absence of a halted candidate is `null`, rather than a fabricated
zero-array winner. Accumulate ties exactly. Since every outcome is streamed,
all tied programs can be recovered without retaining them in memory.

No user-supplied scalar incumbent changes evaluation or output retention in
version one. The durable best-so-far is an incumbent derived from recorded
halting results and survives resume. If a later version accepts an external
witness, it must verify a halt and score at this exact supplied length, label
it separately from in-range winners, and never let it inflate the range's tie
count. Any future safe rejection must use `upper_bound < incumbent` when ties
are preserved; `<=` would discard potential co-winners.

Distinguish `coverage_complete` (every ID has an outcome) from `all_resolved`
(no unknown outcomes). `optimum_established` requires both, and applies only to
the stated range. A partial interval's optimum does not establish the full
length's optimum. Exit zero for completed coverage, including unknown outcomes;
make the booleans explicit so scripts cannot confuse completion with proof of
optimality. Exit nonzero for I/O, validation, corruption, evaluator, or
cancellation failures.

## Result stream and checkpoint format

Use UTF-8 JSON Lines with one object and newline per record. Version the schema
independently from the machine-semantics and evaluator revisions. Start with a
header containing a random run ID and normalized immutable search configuration.
Each candidate record contains run ID, increasing sequence number, decimal ID
string, exact program vector, effective length, outcome, instruction count,
and either final or prefix character count. A cycle record includes the two
matching step indices and state fingerprint; the fingerprint identifies stored
evidence and must not replace full-state equality in the evaluator.

Example candidate record (illustrative field subset):

```json
{"type":"candidate","schema_version":1,"run_id":"example","sequence":"0","program_id":"35328","program":[8,10,0,0],"effective_length":2,"outcome":"halt","steps":"2","output_characters":"2"}
```

This length-four vector executes OUTPUT 10 and HALT. Confirm the fixture against
the processor oracle during implementation. Avoid wall-clock timestamps in
correctness comparisons; optional timing metadata is separate.

Checkpoint JSON contains schema/run identity, full normalized configuration,
machine/evaluator revisions, range endpoints, next ID, committed result byte
offset and SHA-256 prefix digest, aggregate counters and best/tie fields,
checkpoint generation, and operational timing totals. Persist IDs and counters
as decimal strings. Its counters describe exactly `[begin, next_id)`.
Store the resolved absolute results path and encoding ID in the configuration.
Persisted hashes detect accidental mismatch/corruption; they are not a claim
that an arbitrary result file is mathematically certified.

## Atomicity, append safety, and recovery

Initial creation fails if either target already exists. Resume requires an
existing checkpoint and results file. Canonicalize paths before locking and
reject result/checkpoint aliases, including symlink/hard-link aliases. Acquire
an exclusive OS advisory lock for the checkpoint and a separate lock for the
result file for the entire invocation; acquire in canonical path order. A
second writer must fail immediately. Locks release on process death; a stale
lock pathname alone is not a reason to override a live lock.

At a candidate boundary, commit a batch in this order:

1. Append complete candidate lines; flush and fsync the result file.
2. Write the new checkpoint to a unique temporary file in its target directory,
   flush and fsync it, then atomically rename over the old checkpoint.
3. Fsync the checkpoint's parent directory before reporting the generation
   durable. Never advance the durable cursor before its outcomes are durable.

A kill between steps can leave valid result records after the checkpoint's
committed offset. On resume, validate the checkpoint schema/configuration,
prefix digest, header, contiguous sequence numbers and IDs, record shapes,
and aggregates. Fold complete valid tail records in order and publish a new
checkpoint before evaluating fresh IDs. This accepts already-written outcomes
once, without duplicating lines or counting them twice.

A partial final line, invalid JSON, altered prefix, ID gap/duplicate, or invalid
aggregate must stop resumption without appending. Do not silently truncate or
skip suspect data. A later explicit repair operation may archive the original
file and retain the longest validated prefix; that operation is outside the
initial CLI. Keep temporary files left by failed writes for diagnosis, but do
not select the newest-looking file as the authoritative checkpoint.

Resume accepts only `--resume` and presentation/checkpoint-frequency options.
Do not allow changed length, range, results path, instruction bound, encoding,
or evaluator policy under the same run ID. Reject unsupported versions and
semantic/evaluator revision mismatches with a migration instruction. Increasing
the instruction bound is a new run (possibly targeting unresolved IDs in a
future sparse-range mode), not an invisible reinterpretation of old outcomes.

On SIGINT/SIGTERM, request cancellation, stop after the current bounded candidate,
commit any complete pending batch, and return a distinct cancellation status.
A second signal may terminate immediately; recovery handles the previous
checkpoint/tail. If fsync or rename fails, report failure and never print a
successful completion summary. Initial scope is local POSIX filesystems on
macOS/Linux; network filesystem locking and power-loss durability guarantees
need separate investigation. Windows is deferred until equivalent locking and
durability primitives are implemented and tested.

## Aggregation and progress

The final summary reports configured and covered intervals, `next_id`, coverage
and resolution booleans, halted/cycle/unknown counts, range best score, tie count,
first winning ID, wall time, candidate throughput, and checkpoint generation.
Every covered candidate belongs to exactly one outcome count. Coverage is based
on integer IDs, not elapsed time or an estimated cache hit count. Report both
lifetime and current-invocation elapsed time; neither affects result identity.

Independent shard summaries can be merged by a small pure aggregation function
and a later CLI command. Validate identical semantics, length, and limits;
reject overlapping intervals instead of summing them twice. A full-domain claim
requires sorted intervals to cover `[0,16^N)` with no gaps and all outcomes
resolved. Merge maximum scores deterministically: replace on greater, add tie
counts on equal, and take the minimum winning ID. This proposal includes the
pure function and its tests; a general distributed scheduler and merge CLI are
separate follow-ups.

## Implementation phases

1. Add pure `SearchRange` ID encoding/decoding, range/shard validation, summaries,
   and serialization. Establish ordering parity with the existing generator.
2. Add a direct bounded evaluator and lazy, strict-aggregate range runner. Keep
   traces and result retention bounded by the current candidate/batch; do not
   call `length` on or retain the entire candidate list.
3. Add `SearchJournal` schemas, advisory locks, durable append/checkpoint order,
   recovery validation, and cancellation handling. Decide dependency versions
   compatible with `stack.yaml` before changing the Cabal file: likely
   `bytestring`, `filelock`, `unix`, and a maintained SHA-256 package alongside
   existing `aeson`, `directory`, and `temporary`.
4. Wire CLI parsing and diagnostics, document examples and the legacy/range
   distinction, then add integration and fault-injection coverage.
5. Measure complete small searches and bounded length-eight intervals. Report
   throughput, checkpoint cost, peak memory, and result file growth; tune batch
   defaults only after durability and correctness pass.

## Acceptance criteria and verification

Use the existing Hspec/QuickCheck suite (`stack test` from `haskell-impl/`) and
add range, journal, and CLI specs to the Cabal test-suite module list.

- Round-trip every small-domain ID; check ordering against `generateAllPrograms`,
  leading/trailing zeroes, first/last IDs, empty ranges, and hexadecimal parsing.
- Property-test arbitrary valid shard counts: pairwise disjoint intervals whose
  concatenation equals the domain, including non-divisors and empty shards.
- Exercise arithmetic at the length-eight endpoint and future length-sixteen
  endpoint without enumerating those spaces. Reject unsupported lengths.
- Compare whole-domain small searches with the same evaluator used in shards;
  require identical outcomes, maximum, ties, and first ID independent of shard
  completion order. Compare fixed processor fixtures with the unpruned oracle.
- Cover zero-output halts, no halts, all unknown at limit zero, HALT exactly at
  the limit, wraparound, mutable memory, and repeated PC with changing registers.
  Confirm unknown scores never enter winner calculations.
- Interrupt at every append, fsync, temp-write, rename, and directory-fsync
  boundary. Resume must match an uninterrupted run semantically, with exactly
  one accepted record per ID. Test valid tail recovery and every corruption
  rejection without modifying the original files.
- Reject concurrent writers, path aliases, configuration/version mismatches,
  missing files, duplicate/gapped IDs, partial final lines, permission errors,
  disk-full failures, and invalid checkpoint aggregates. Verify lock release
  after termination and bounded batch memory on a long synthetic stream.
- Demonstrate cancellation/resume and merging disjoint shard summaries on a
  small exhaustive domain. Ensure a gap or unknown result prevents any
  full-domain optimum claim.

For this proposal alone, run the documented numbering validator:
`bun run ai-planning/validate-proposals.ts`. Implementation tests belong to the
phases above; this proposal makes no claim that the CLI already exists.

## Risks and tradeoffs

Streaming every candidate creates substantial disk traffic: length eight has
4,294,967,296 candidates. Make projected record size visible before execution;
benchmark it, and consider a separately versioned compact or outcome-filtered
journal only if it retains complete coverage and recovery evidence. Do not
quietly drop unknowns or non-winners to reduce storage.

SHA-256 prefix revalidation and tail scanning make resume proportional to file
size in the initial version. Chunked checksums or immutable journal segments
may improve this later, but complicate recovery. A strict direct runner may
execute slower than the heuristic cache path; measure it as the auditable
baseline before reintroducing any proved optimization. Cycle detection itself
can consume substantial memory, so use a bounded-memory detector or preserve
unknown outcomes when resources are exhausted. File durability, semantic
correctness, and formally proved pruning are distinct obligations; a reliable
checkpoint cannot make an unsound cache or rejection rule safe.
