# 013: Coordinate distributed exhaustive search across client machines

**Status:** Proposed  
**Created:** 2026-11-24

## Summary

Add a coordinator service and a lightweight client so participating computers
can contribute bounded pieces of the exhaustive search. The coordinator owns
the search campaign, partitions each program length into non-overlapping
candidate-ID ranges, leases short chunks to clients, records progress, and
combines each chunk's best programs into a per-length leaderboard.

Run lengths 1 through 16 in the same campaign. Keep a separate queue and
coverage record for each length, and schedule work fairly across those queues.
Choose chunk sizes from measured client throughput so a normal assignment is
expected to take a few minutes. A slow or interrupted client can return or
lose its lease without losing campaign progress; another client can retry the
range.

The server independently checks every returned winner: its program length and
ID must place it inside the assigned range, and replay on the canonical
machine implementation must halt with exactly the claimed output-character
count. This validates each submitted solution. A worker's claim that its
solution is the maximum for a whole chunk is a separate completeness claim;
the validation limits and optional audit modes below make that distinction
clear.

This proposal complements [011](011-cli-search-range-checkpoints.md), which
defines resumable range evaluation, and [009](009-multiprocess-search-work-queue.md),
which defines an in-process worker queue. It adds network transport, campaign
management, remote clients, result verification, and multi-length aggregation.

## Goals

- Let a server coordinate many intermittently available client computers over
  authenticated network connections.
- Evaluate exact program-ID ranges for every supported length 1–16, including
  length 16's `2^64` candidates.
- Keep assignments short and retryable, targeting a few minutes per chunk.
- Run all lengths as one campaign and report the best halted programs and ties
  separately for each length.
- Verify every submitted program's length, assigned range membership, halt
  result, and claimed output-character count on the server.
- Preserve a durable audit trail of task leases, accepted results, retries,
  client versions, and per-length coverage.
- Make incomplete, unresolved, or unaudited work visibly different from a
  complete exhaustive result.

## Non-goals

- Reducing the mathematical search space. Chunking distributes candidate
  evaluations; it does not eliminate any candidates.
- Treating client-reported chunk summaries as cryptographic proofs.
- Replacing the existing machine simulator or changing its semantics.
- Requiring every computer to process every length. Clients request work from
  the campaign-wide queues, and the scheduler distributes the lengths across
  the available fleet.
- Supporting arbitrary user-submitted executables or code on clients.

## Search domain and chunk identity

For each declared length `L` in `1..16`, search every vector of exactly `L`
nibbles, with the remaining memory cells initialized to zero. Define the
candidate ID as the vector's base-16 value, with cell zero as its most
significant digit. Thus IDs range from `0` to `16^L - 1`; the final endpoint is
exclusive.

A task is identified by:

```text
(campaign_id, length, task_id, begin_id, count, evaluator_revision)
```

It covers `[begin_id, begin_id + count)`. Validate endpoints using arbitrary
precision integers (or an explicitly wider-than-64-bit checked type) on both
server and client. At length 16, each candidate ID fits in `uint64_t`, but the
exclusive endpoint `2^64` does not. Wire formats therefore encode IDs and
counts as decimal strings; JSON numeric values are not used for these fields.
Before dispatch, require `begin_id < 16^L`, `count > 0`, and
`begin_id + count <= 16^L`.

Maintain a monotonic allocation cursor for each length and issue adjacent
ranges from it. The next fresh range starts exactly at the previous range's
exclusive endpoint. This gives a gap-free, non-overlapping partition for each
length. Retries keep the original task ID and range; they do not advance the
cursor. Persist task states (`queued`, `leased`, `accepted`, `retryable`,
`failed`) so a server restart does not lose coverage or issue an untracked
range.

## Adaptive chunk duration and scheduling

Target a configurable wall time, initially **three minutes** per assignment,
with a recommended range of one to five minutes. Clients report a short
calibration rate per length and execution backend. The coordinator chooses
`count = estimated_candidates_per_second * target_seconds`, clamps it between
configured minimum and maximum counts, and checks it against the remaining
range. Use recent completed chunks to adjust the estimate. Keep a maximum
lease duration and extend it on periodic heartbeats for a healthy client.

Candidate cost can vary substantially with program behavior. Chunk duration is
therefore an estimate, not a hard real-time limit. A worker finishes the
current candidate before acknowledging cancellation; lease expiry makes the
range available for retry. Accept only one result for a task. If an old lease
submits after a retry has already been accepted, treat the duplicate as
idempotent and do not count it twice.

Keep one work queue per length. The scheduler should use weighted round-robin
or deficit round-robin across nonempty queues so length 16 cannot starve the
smaller searches and a steady flow of easy small-length tasks cannot prevent
longer lengths from receiving workers. Persist per-length candidate coverage
and show progress independently. Clients may advertise supported backends;
for example, the current Metal GPU client can receive GPU tasks, while a CPU
client can receive tasks if a compatible CPU evaluator is enabled.

## Client-server protocol

Use a versioned HTTPS JSON API for the first implementation, with mutual TLS
or per-client enrollment tokens. Do not expose an unauthenticated task-submit
endpoint. Keep messages bounded and validate all fields before database writes.

Suggested exchange:

1. `REGISTER`: client sends client ID, client version, machine/backend
   capabilities, and supported evaluator revisions.
2. `LEASE`: client requests work; server replies with campaign ID, task ID,
   length, decimal-string range start/count, evaluator and machine-semantics
   revision, target duration, lease token, and lease deadline.
3. `HEARTBEAT`: client reports task progress and requests a lease extension.
   Progress is advisory until a complete result is accepted.
4. `SUBMIT`: client sends task identity, actual examined-candidate count,
   outcome counters, local maximum output count, all candidates tying that
   local maximum, and a checksum of the canonical result payload.
5. `ACK`: server returns accepted, duplicate, retry, or rejected status and
   includes the next task when one is available.

The checksum detects accidental corruption in transit or storage; it does not
prove that the client evaluated the range correctly. Task messages and result
records must include schema versions, and submissions using an unsupported
machine-semantics or evaluator revision must be rejected rather than silently
interpreted under new behavior.

## Client behavior

The client is a small service or foreground process that:

- enrolls with the coordinator and polls for work;
- validates task bounds and supported evaluator revision before starting;
- evaluates each candidate from a fresh, canonical initial machine state;
- uses the existing optimized GPU backend when available, with a compatible
  CPU backend as a separately versioned option;
- tracks halted, cycle-detected, and unresolved outcomes distinctly;
- retains every candidate tied for the chunk's greatest halted output count;
- submits a result only after completing the full assigned range;
- checkpoints task-local progress so a client crash can resume if the lease is
  still valid, otherwise it discards partial claims and lets the server reissue
  the full range;
- never reports a step-limited or unknown candidate as a halted solution.

The client should run only while the owner has opted in, expose pause/stop
controls, limit resource use, and avoid starting a new chunk when paused. A
three-minute target bounds normal assignments but does not justify continuing
after a user requests a stop.

## Server validation and result aggregation

For each submission, the server performs these checks before changing the
leaderboard:

1. Confirm campaign, task ID, lease token, task state, client, length, and
   evaluator revision match the server's outstanding assignment.
2. Recompute `16^L`, validate the task interval, and confirm the submitted
   candidate count and outcome totals are internally consistent with the
   task's declared count. Require the client to report full range completion.
3. For every submitted candidate, require exactly `L` nibbles in `0..15`,
   encode the vector using the canonical cell order, and verify its ID lies in
   `[begin_id, begin_id + count)`.
4. Run each submitted candidate independently through the server's canonical
   simulator with the campaign's evaluator policy. Accept it as a solution
   only if it halts and the recomputed output-character count equals the
   submitted count. Reject a claimed cycle, timeout, or output score that does
   not match the replay.
5. Reject duplicate IDs in one result, or deduplicate them by
   `(campaign_id, length, candidate_id)` while recording the duplicate.
6. After all candidate validations succeed, atomically accept the chunk result
   and update the per-length aggregate. A larger score replaces that length's
   incumbent; an equal score adds the candidate to its tie set.

Store per-length winner programs and IDs, score, tie count, accepted range
coverage, unresolved count, and completion state. Provide a downloadable JSONL
export and a human-readable status page with separate progress bars for
lengths 1–16. A length is marked `coverage_complete` only after accepted tasks
cover its entire domain exactly once (ignoring duplicate retries). It is marked
`all_resolved` only if every candidate has a terminal halt or cycle outcome
under the defined evaluator. Mark `optimum_established` only when coverage is
complete and there are no unresolved candidates.

### What replay validation proves

Server replay establishes that each accepted returned program is genuinely in
the assigned range and has the claimed halted output length. It does **not**
establish that the client found every best candidate in the chunk or evaluated
every candidate: a client could omit a better program while submitting a valid
lower-scoring one. Therefore distinguish:

- `solution_validated`: all submitted programs passed independent replay;
- `chunk_report_accepted`: the worker's full-range summary passed protocol and
  consistency checks;
- `chunk_audited`: the server or a second independent worker recomputed the
  entire chunk and agreed;
- `optimum_established`: every range is accepted and the selected completeness
  policy has been satisfied for the whole length.

For initial deployment, use authenticated clients and mark results as
worker-reported with server-validated solution candidates. Add deterministic
full-chunk duplicate execution as an optional stronger mode, preferably on a
small random audit fraction first. To claim independently checked exhaustive
optimality, every chunk must be recomputed by a trusted server or by an
explicitly chosen redundant-worker policy. Sampling and checksums improve
confidence and detect errors; they are not mathematical proof that unaudited
chunks contain no omitted winner.

## Durable state and operations

Use a relational database as the source of truth for campaigns, per-length
cursors, tasks, leases, clients, accepted summaries, candidate winners, and
audit records. PostgreSQL is the recommended shared server database; a local
SQLite mode may be useful for a single-machine prototype. Allocate a task and
advance its length cursor in one transaction. Accept a submission and update
its task/aggregate in one transaction. Make task IDs stable and result
acceptance idempotent.

Store the normalized campaign configuration, machine semantics revision,
simulator/evaluator build IDs, length domain, chunk-duration target, and
completeness policy. Keep structured server logs for rejected submissions,
lease expiry, retries, client disconnects, and audit mismatches. A mismatch
invalidates that result, records the evidence, and requeues the chunk; it must
not silently advance coverage.

## CLI and initial operation

Illustrative commands (names are provisional):

```sh
# Start the coordinator with all lengths enabled.
4917-coordinator serve --config coordinator.toml

# Create a campaign searching every declared length.
4917-coordinator campaign create --lengths 1-16 \
  --chunk-target 3m --evaluator cycle-detect --audit none

# Enroll and run a client in the foreground.
4917-worker join --server https://search.example.invalid \
  --enrollment-token TOKEN --backend metal --max-gpu-load 80

# Inspect progress and export validated candidates.
4917-coordinator campaign status CAMPAIGN_ID --json
4917-coordinator campaign export CAMPAIGN_ID --winners winners.jsonl
```

Do not treat the provisional commands as a fixed public interface. Keep admin
operations separate from worker endpoints and avoid printing enrollment
secrets in logs.

## Rollout and acceptance criteria

1. Extract a shared canonical candidate-ID codec and range validator; confirm
   length 16 boundary handling at IDs `0`, `2^64 - 1`, and exclusive endpoint
   `2^64`.
2. Add a local coordinator with persistent queues and a worker process, then
   prove disjoint chunk allocation, retry idempotence, and aggregate tie rules.
3. Add remote transport, authentication, version negotiation, lease renewal,
   and restart recovery.
4. Add server-side replay validation for every returned winner and status that
   distinguishes validated candidates from audited chunk maxima.
5. Add multi-length scheduling and adaptive per-client chunk duration; verify
   a worker fleet receives work from every enabled length without starvation.
6. Exercise disconnects, duplicate and delayed submissions, invalid IDs,
   altered vectors, false output counts, unsupported revisions, expired leases,
   server restart, partial results, and audit disagreement.
7. Benchmark end-to-end throughput at several client counts and chunk targets.
   Report completed candidates per second by length, client availability,
   retry rate, server validation load, and scheduler overhead. Compare
   aggregate speed with the single-machine baseline; do not infer linear
   scaling solely from the number of enrolled computers.

The first release is acceptable when exact candidate-range coverage is
recoverable after coordinator restart, result submissions are idempotent,
every accepted winner passes server replay, all enabled lengths make progress,
and the UI/exports never label incomplete or unaudited worker summaries as a
proven global optimum.
