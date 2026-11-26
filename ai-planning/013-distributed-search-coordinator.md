# 013: Coordinate distributed exhaustive search across client machines

## Open questions

None currently identified.

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
proposes resumable Haskell range evaluation, and [009](009-multiprocess-search-work-queue.md),
which proposes an in-process worker queue. It adds network transport, campaign
management, remote clients, result verification, and multi-length aggregation.

## Current implementation and prerequisites

Verified against the current source in this checkout:

- [`metal_search.mm`](../c-impl/src/metal_search.mm) accepts lengths 1–16,
  decodes IDs in the cell order below, and uses a bounded GPU pass followed by
  exact CPU fallback for candidates the GPU does not classify. Its public CLI
  searches a whole length; it does not yet expose arbitrary ranges, durable
  checkpoints, network leases, or resumable task-local execution.
- [`main.cpp`](../c-impl/src/main.cpp) also accepts CPU `search` lengths 1–16,
  and [`machine_internal.hpp`](../c-impl/src/machine_internal.hpp) exposes an
  internal candidate-ID evaluator. The CPU public CLI still searches a whole
  length. A shared remote range interface is prerequisite work. The C++ README
  and the processor contract's initial-search section still describe older
  length limits; use the current CLI source for this capability claim.
- The [processor contract](../spec/processor.md) defines the full execution
  state and decimal output-character score. The portable C API uses checked
  `uint64_t` step/output counters and can report `I4917_RUN_ERROR`; exact cycle
  detection does not guarantee that every candidate resolves within those
  representational limits or an operational time budget.
- The Metal winner writer now skips zero-output records, while its aggregate
  still counts zero-output halters. Its JSONL export is therefore not a
  complete tie manifest for a zero-best range. Do not directly reuse that
  export as evidence that every local maximum was returned.

Proposals 009 and 011 describe related designs, not completed dependencies.
Before attaching the existing evaluator to a coordinator, add a reusable
range runner, cancellation/checkpoint boundaries, and a versioned task-result
contract. A campaign over 1–16 defines the domain; it does not promise that a
full length-16 search is practical. Establish fleet throughput and projected
completion time from measurements before promising a completion date.

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
Use the same exact integer encoding for outcome totals, tie counts, scores,
and progress counters: aggregate coverage and tie counts may reach `2^64`.
Database integer columns must represent that endpoint too; a signed 64-bit
column is insufficient for length-16 candidate IDs or coverage totals.
Before dispatch, require `begin_id < 16^L`, `count > 0`, and
`begin_id + count <= 16^L`.

Maintain a monotonic allocation cursor for each length and issue adjacent
ranges from it. The next fresh range starts exactly at the previous range's
exclusive endpoint. This gives a gap-free, non-overlapping partition for each
length. Retries keep the original task ID and range; they do not advance the
cursor. Persist task states (`queued`, `leased`, `validating`, `accepted`,
`retryable`, `failed`) so a server restart does not lose coverage or issue an
untracked range.

## Adaptive chunk duration and scheduling

Target a configurable wall time, initially **three minutes** per assignment,
with a recommended range of one to five minutes. Clients report a short
calibration rate per length and execution backend. The coordinator chooses
`count = estimated_candidates_per_second * target_seconds`, clamps it between
configured minimum and maximum counts, and checks it against the remaining
range. Bound calibration work so enrollment itself cannot become a long search.
Use recent completed chunks to adjust the estimate. Keep a maximum lease
duration and extend it on periodic heartbeats for a healthy client. Use fixed,
evaluator-versioned execution and replay budgets. Work stopped by a budget is
unresolved, not a cycle; retry it only under an explicitly versioned larger
budget. These limits bound cancellation and server validation work without
misclassifying incomplete candidates.

Candidate cost can vary substantially with program behavior. Chunk duration is
therefore an estimate, not a hard real-time limit. In particular, the existing
exact CPU fallback can spend a long time on one candidate; a three-minute chunk
target does not bound cancellation latency. Define an operational stop/replay
budget before deployment. An interrupted or budget-exhausted candidate is
unresolved or retried, never silently classified as a cycle. Preserve enough
outcome identity to revisit unresolved IDs under a new evaluation policy.

Give each lease attempt a distinct token/generation. Expiry makes the original
range eligible for retry without creating a second coverage interval. Accept
only the current generation; reject stale attempts after expiry or reassignment.
A repeated submission from the accepted attempt is idempotent only if its
canonical payload digest matches the stored accepted digest. A conflicting
payload is an error to record, not an ordinary duplicate. Expiry, reassignment,
and acceptance must serialize against the same task record so concurrent
requests cannot both claim coverage. A heartbeat from a stale attempt cannot
revive it. Use server time for deadline decisions; do not rely on client clocks.

Keep one work queue per length. Use deficit round-robin with equal initial
shares across nonempty queues, so length 16 cannot starve the smaller
searches and a steady flow of easy small-length tasks cannot prevent longer
lengths from receiving workers. Persist per-length candidate coverage and show
progress independently. Clients may advertise supported backends;
for example, a new Metal worker adapter can receive GPU tasks, while a CPU
worker adapter can use the existing portable evaluator. These network clients
are proposed additions.

## Client-server protocol

Use a versioned HTTPS JSON API for the first implementation. Exchange a
one-time enrollment token for a per-client credential so an operator can
revoke and rotate one worker without disabling the fleet. Do not expose an
unauthenticated task-submit endpoint. Keep messages bounded and validate all
fields before database writes.

Suggested exchange:

1. `REGISTER`: client sends client ID, client version, machine/backend
   capabilities, and supported evaluator revisions.
2. `LEASE`: client requests work; server replies with campaign ID, task ID,
   length, decimal-string range start/count, evaluator and machine-semantics
   revision, target duration, lease token, and lease deadline.
3. `HEARTBEAT`: client reports task progress and requests a lease extension.
   Progress is advisory until a complete result is accepted.
4. `SUBMIT`: client sends task/attempt identity, actual examined-candidate count,
   halted/cycle/unresolved/error counters, local maximum output count (nullable
   when there are no halts), exact tie count, a manifest of positive-score ties,
   and a checksum of the canonical result payload. All counters must partition
   the assigned count. A nonempty halter set has a maximum even if that maximum
   is zero; for a zero maximum, preserve the exact tie count but leave the
   program manifest empty, following the established zero-output logging rule.
   For positive maxima, upload the full tie manifest in bounded pages or staged
   objects before finalizing the result. A page being received is not
   accepted range coverage.
5. `ACK`: server returns pending-validation, accepted, duplicate, retry, or
   rejected status and includes the next task when one is available.

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
- tracks halted, cycle-detected, unresolved, and evaluator-error outcomes
  distinctly;
- retains the exact count of candidates tied for the chunk's greatest halted
  output count and exports every positive-score tie without unbounded RAM;
  zero-output program records are omitted while their counts remain exact;
- submits a result only after accounting for the full assigned range;
- checkpoints task-local progress so a client crash can resume if the lease is
  still valid, otherwise it archives its local checkpoint as unaccepted and
  lets the server reissue the full range; never reuse it under a different
  task/attempt identity;
- never reports a step-limited or unknown candidate as a halted solution.

Task checkpoints must include range, campaign/attempt identity, semantics and
evaluator revisions, next uncompleted ID, accepted local outcome counts, and
tie-manifest progress. Persist a completed prefix atomically; do not advance its
cursor while the current candidate is still executing. Proposal 011 provides
related durability requirements, but its Haskell journal is not an existing
checkpoint API for the Metal runner.

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
   task's declared count. Require full range accounting, with each ID assigned
   one reported outcome. Evaluator errors and operational limits prevent
   `all_resolved`; they cannot be relabeled cycles to satisfy the totals.
3. For every submitted candidate, require exactly `L` nibbles in `0..15`,
   encode the vector using the canonical cell order, and verify its ID lies in
   `[begin_id, begin_id + count)`.
4. Run each submitted candidate independently through the server's canonical
   simulator with the campaign's evaluator policy. Accept it as a solution
   only if it halts and the recomputed output-character count equals the
   submitted count. Replay must start from reset registers/PC and zero-padded
   memory, using full mutable state for cycle equality. If replay reaches an
   operational budget or representational limit, leave the result pending
   or return an explicit retry/unresolved validation status; do not accept the
   score or assert that the worker lied. A completed replay with a different
   outcome or score rejects the claim.
5. Reject duplicate IDs within the staged manifest. When the maximum is
   positive, require its unique ID count to equal the reported tie count. When
   the maximum is zero, require an empty program manifest while preserving the
   exact zero-score tie count. Use `(campaign_id, length, candidate_id)` to
   deduplicate aggregate exports; zero is a valid score and candidate ID, not
   an absence sentinel.
6. Stage and validate large manifests outside the final acceptance transaction,
   with bounded replay concurrency and storage. Associate every page and replay
   result with the immutable payload digest and attempt generation. Define a
   bounded validation reservation distinct from the client execution lease;
   a server restart must recover staged validation without accepting a stale
   attempt or expiring a valid upload merely because replay is slow. Recheck
   attempt eligibility in the final transaction. After all required candidate
   validations succeed, atomically accept the chunk result and update the
   per-length aggregate. A larger score replaces that length's incumbent; an
   equal score adds the candidate to its tie set.

Store per-length winner programs and IDs, score, tie count, accepted range
coverage, unresolved count, and completion state. Provide a downloadable JSONL
export and a human-readable status page with separate progress bars for
lengths 1–16. A length is marked `coverage_complete` only after accepted tasks
cover its entire domain exactly once (ignoring duplicate retries). It is marked
`all_resolved` only if every candidate has a reported terminal halt or cycle
outcome, with no unresolved candidates or evaluator errors. These two fields
measure reported accounting; they do not establish that a worker's report is
true. The stronger `optimum_established` gate additionally requires the
campaign's explicitly selected completeness policy below.

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
  policy has been satisfied for the whole length, with zero unresolved/error
  outcomes and complete required tie manifests. Record the policy in every
  status/export so the trust assumption is visible. Agreement between workers
  running the same code is still subject to shared implementation defects.

For initial deployment, mark returned programs as server-validated worker
reports, but keep `optimum_established` false.
Random full-chunk audits may detect errors but do not establish exhaustive
optimality. To claim independently checked optimality, recompute every chunk
on a trusted server or use an explicitly chosen redundant-worker policy.
Sampling and checksums improve confidence; they do not prove unaudited chunks
contain no omitted winner.

## Durable state and operations

Persist campaign, length-queue, task, lease-attempt, client, accepted-summary,
winner-manifest, and audit state as independently keyed, versioned JSON
documents. Keep documents backend-neutral and put persistence behind an
interface that supports atomic conditional writes and transactions for cursor
allocation, lease transitions, and result acceptance. Use PostgreSQL JSONB for
the first shared deployment; a later DynamoDB adapter can store the same
documents without making database-specific fields authoritative. Keep indexes
and query projections rebuildable from these documents. Do not put an entire
campaign in one blob: keep task and lease records separately addressable.
Allocate a task and advance its length cursor atomically. Accept a submission
and update its task/aggregate atomically. Make task IDs stable and result
acceptance idempotent.

Store the normalized campaign configuration, machine semantics revision,
simulator/evaluator build IDs, length domain, chunk-duration target, and
completeness policy. Keep structured server logs for rejected submissions,
lease expiry, retries, client disconnects, and audit mismatches. A mismatch
records the evidence and requeues the chunk. If it concerns an already accepted result, revoke that acceptance, reduce accepted coverage, and
recompute the leaderboard from retained valid task summaries/manifests in one
consistent state transition. A previously published optimum claim must be
withdrawn until the replacement passes the selected policy. Retain accepted
per-task maxima/manifests even after a higher global score is found so recovery
from invalidated results does not require inventing lost contenders.

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
7. Compare complete small-domain campaigns against the direct canonical
   evaluator, including out-of-order task acceptance, all-zero-output halts,
   no halters, cross-chunk ties, and manifest pagination. Check allocation and
   aggregation at the length-16 endpoint without enumerating that domain.
   Force a replay timeout, output overflow/error, stale heartbeat, conflicting
   duplicate digest, crash during staging/final acceptance, and invalidation of
   an accepted incumbent; none may advance coverage twice or leave a false
   optimum flag.
8. Benchmark end-to-end throughput at several client counts and chunk targets.
   Report completed candidates per second by length, client availability,
   retry rate, server validation load, and scheduler overhead. Compare
   aggregate speed with the single-machine baseline; do not infer linear
   scaling solely from the number of enrolled computers.

The first release is acceptable when exact candidate-range coverage is
recoverable after coordinator restart, result submissions are idempotent,
every accepted winner passes server replay, all enabled lengths make progress,
and the UI/exports never label incomplete or unaudited worker summaries as a
proven global optimum.
