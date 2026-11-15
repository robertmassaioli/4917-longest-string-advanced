# 009: Parallelize exhaustive search with a process work queue

**Status:** Proposed
**Created:** 2026-11-15

## Summary

Add an optional multi-process execution mode to the C exhaustive search. A
coordinator in the parent process divides the candidate ID range into bounded
contiguous chunks, assigns the next available chunk to each idle worker process,
and gathers one summary for each completed chunk. Workers run the existing
candidate evaluation and return aggregate results. The coordinator combines
those summaries and emits the same deterministic search result as the
single-process implementation.

Keep sequential search as the default and correctness baseline. Parallel
execution must preserve candidate-domain, step-limit, winner, tie-breaking, and
incomplete-search semantics. It should not claim a speedup for the current
small ranges until measurements show that process startup and coordination
costs are recovered.

## Motivation and verified starting point

`c-impl/src/main.c::search_cmd` enumerates candidate IDs from zero through
`16^length - 1`, decodes each ID as a length-cell base-16 program, zero-pads
the rest of the 16-cell memory, and calls `i4917_run_bounded`. Only halted
candidates count as completed and can win;
step-limited candidates are unresolved. It tracks the best output-character
count, number of winners, and the first winner in enumeration order. The public
search command currently restricts length to 1–4, so the largest current space
is 65,536 candidates. The search is sequential and uses no inter-process
communication.

This workload is naturally partitionable because each candidate starts from an
independent initialized machine state. A process pool can use multiple CPU
cores while preserving the existing per-candidate evaluator. Dynamic chunk
assignment can also balance candidate groups whose execution costs differ.

## Goals

- Allow a configurable number of worker processes to evaluate independent
  candidate chunks.
- Keep the production machine core reusable and identical for sequential and
  parallel search.
- Preserve exact search semantics and deterministic output regardless of worker
  completion order.
- Bound work-queue, IPC, and aggregation memory independently of total candidate
  count.
- Detect worker and transport failures without double-counting results or
  claiming an exhaustive answer from missing work.
- Measure both end-to-end and steady-state throughput to identify when
  parallelism pays for itself.

## Non-goals

- Changing the candidate domain, machine semantics, pruning rules, or the
  definition of a winner.
- Parallelizing individual program execution or introducing shared mutable
  machine states.
- Making process parallelism the default before benchmarks justify it.
- Depending on a distributed scheduler, database, or third-party message
  broker.
- Using threads as a substitute for the requested process workers. A future
  thread backend may be considered separately if profiling supports it.

## Candidate IDs and chunk ranges

For a search length `L` in the currently supported range 1–4, define
`total = 16^L`. Candidate ID `id` is the base-16 encoding of exactly `L`
nibbles, with the first program cell as the most significant digit. This is
the same ordering as the current loop, including candidates with leading or
trailing zero cells. Decoding must be shared with or directly tested against
the sequential path rather than reimplemented with a different convention.

Here, length counts memory cells containing nibble values, not decoded
instructions: some instructions also consume an operand cell. It specifies
exactly `L` supplied cells, including leading/trailing zeroes, rather than
requiring the last cell to be nonzero. Only those `L` cells vary; memory cells
`L` through 15 start at zero. Shorter programs padded to `L` cells therefore
already occur in this space. Do not enumerate all 16 memory cells and filter
afterward, or require a 16-cell prefix before splitting work.

For example, at `L = 4`, candidate `0x1234` initializes memory with
`[1, 2, 3, 4, 0, ..., 0]`. At a hypothetical `L = 8`, ID `0x01234567`
initializes `[0, 1, 2, 3, 4, 5, 6, 7, 0, ..., 0]`; the leading zero is
retained. Length 8 illustrates the arithmetic below, but remains outside the
current CLI contract.

Represent a chunk as `(search_id, chunk_id, begin, count)`, where `begin` is
the first candidate ID and `count` is positive. Its range is the half-open
interval `[begin, begin + count)`. To avoid addition overflow, validate
`begin <= total` and `count <= total - begin` before constructing or accepting
a range. The coordinator advances a `next_id` cursor by `count` only after
applying the same remaining-range check. Chunk IDs are monotonically increasing
within a search and are for protocol identity; candidate IDs determine
enumeration and tie order.

For a validated positive chunk size `C`, generate fresh chunks lazily:

```text
next_id = 0
on a request for fresh work, if next_id < total:
    begin = next_id
    count = min(C, total - begin)
    next_id = begin + count
    dispatch [begin, next_id)
```

The coordinator is the sole owner of this cursor. A worker claims a range by
receiving an assignment; it does not compute its own static fraction of the
domain. Adjacent fresh chunks share one boundary, so they cover `[0, total)`
without gaps or overlaps regardless of worker count. Retrying a failed chunk
reuses its range and identity without advancing `next_id`. The last fresh
chunk may be smaller than `C`, and `C >= total` produces one chunk. Compute
the number of chunks as `total / C + (total % C != 0)`, avoiding the
potentially overflowing expression `(total + C - 1) / C`.

| Supplied cells `L` | Domain `[0, total)` | Example `C` | Fresh chunks | Final chunk |
| --- | --- | --- | --- | --- |
| 4 | `[0, 65,536)` | 1,000 | 66 | `[65,000, 65,536)`, 536 candidates |
| 8, illustrative future domain | `[0, 4,294,967,296)` | 1,000,000 | 4,295 | `[4,294,000,000, 4,294,967,296)`, 967,296 candidates |

These chunk sizes are arithmetic examples, not proposed defaults. If eight
workers take the first eight length-4 chunks, the next worker to finish
receives `[8,000, 9,000)`, irrespective of which initial chunk it processed.
There is no requirement for the program to fill all 16 memory cells.

Compute `16^L` using checked multiplication. If the supported maximum length is
raised, do not silently wrap a `uint64_t` total or candidate cursor. Either
retain a documented maximum whose entire range fits the chosen integer type,
or introduce a wider candidate-ID representation and update the protocol,
decoder, CLI, JSON schema, tests, and Haskell oracle together. Do not imply that
this proposal expands the current length limit.

Use `uint64_t` consistently for totals, candidate cursors, chunk bounds/counts,
chunk IDs, and aggregate candidate/winner counts. At length 8, individual IDs
fit in 32 bits, but `total = 2^32` and the final exclusive endpoint do not.
With 64-bit arithmetic the full count fits through length 15; at length 16,
the count and exclusive endpoint are `2^64`, which cannot be represented in
`uint64_t` even though every individual packed candidate can. Do not use an
unchecked shift such as `1ULL << (4 * L)` at that boundary. Exercise future
length-8 arithmetic in isolated range tests, without exposing an unsupported
CLI length or executing all of its candidates.

If a future command says “at most `L`”, decide whether it means distinct
zero-padded machine images or separately labelled programs of every supplied
length. The current `16^L` domain already contains all images obtainable from
shorter supplied programs, once padded; searching lengths 1 through `L`
separately instead visits `sum(16^k, k=1..L)` labelled candidates and repeats
some machine images, changing winner counts and tie ordering. This proposal
preserves the existing supplied-length domain; a new length mode needs an
explicit contract rather than a silent reinterpretation of `--length`.

## Coordinator and worker responsibilities

The parent process owns the coordinator event loop. It creates at most the
requested number of worker subprocesses, starts with no materialized list of
chunks, and assigns the next chunk whenever a worker becomes idle. Each worker
evaluates its assigned range sequentially with the production bounded runner,
then sends exactly one result for that chunk and requests more work. The
coordinator stops assigning ranges after all candidate IDs have been
dispatched and all retries have been assigned. Dispatch completion alone is
not search completion: wait until every outstanding assignment is accepted
and the retry queue is empty before finalizing.

The coordinator validates every response against the worker's outstanding
assignment before accepting it. It tracks per-worker state (starting, idle,
assigned, stopping, finished, failed), the current channel instance, and the
outstanding chunk identity. Accepting a complete result merges it and clears
the assignment as one coordinator operation before any next assignment.
Responses must match both the live channel instance and its outstanding
assignment, so stale or duplicate results cannot be accepted a second time.
Do not retain a set of every accepted chunk ID: that would grow with the
search. Retain only bounded worker/assignment and pending-retry records plus
aggregate counters. An unknown, duplicated, malformed, or out-of-range
response is a worker/protocol error; it must not affect totals.

On a clean worker exit, the coordinator verifies that no assignment remains
outstanding. If a worker exits or its channel fails while holding a chunk,
requeue that whole chunk unless cancellation has begun. Drain any complete
buffered result frame before treating EOF as a missing result; a result
already accepted is never requeued. Close the old channel and reap the old
process before reassigning its unaccepted chunk, so two live attempts cannot
race to commit it. Since per-candidate evaluation has no shared side effects,
replay is safe; discard any partial
response and do not count it. Put a bounded retry policy on repeated failure
of the same chunk to avoid an infinite respawn loop. Exhausting the retry
policy fails the search with a nonzero exit status and clearly marks the result
as unavailable/incomplete, never as exhaustive.

Prioritize pending retries before issuing fresh chunks and bound their records
by the configured pool size. If no workers remain, either start a replacement
under a bounded startup/restart policy or fail; never wait forever with pending
work and no process capable of doing it.

The coordinator owns final output. Workers do not print progress or final
search results to the user's stdout. Optional progress reporting, if added,
must be emitted only by the coordinator and must not alter machine-readable
output.

## IPC and result transport

Use framed request/response messages over a private channel per worker. Prefer
the simplest portable subprocess arrangement supported by the selected
platforms: a worker mode in the same executable (or a dedicated internal
worker executable), with stdin/stdout pipes reserved for protocol traffic and
stderr reserved for diagnostics. Do not use inherited stdout for worker logs.
Define a versioned protocol and explicit message lengths; never send raw C
struct bytes as the wire format because padding, endianness, and compiler ABI
can differ.

The initial protocol needs only:

- `READY` from a freshly initialized worker; this is its initial request for
  work, sent once on its private channel;
- `WORK(search_id, chunk_id, begin, count, length, max_steps)` from coordinator
  to worker;
- `RESULT(search_id, chunk_id, completed, unresolved, best_output_chars,
  winner_count, first_winner_id)` from worker to coordinator;
- `STOP` and `ERROR` messages for normal shutdown and protocol/runtime failure.

A valid `RESULT` also requests the next chunk, so no second `READY` is sent
between assignments. The coordinator answers the initial `READY` or an
accepted `RESULT` with either one `WORK` or `STOP` if there is currently no
assignable work. An idle worker may be stopped while other chunks are still
running; pending retries can use remaining or replacement workers. A worker
has at most one assignment, and an unexpected `READY`, `WORK`, or `RESULT`
for its current state is a protocol error. The parent must service all worker
channels using bounded buffers/nonblocking I/O or an equivalent event-loop
mechanism; it must not block waiting for one slow worker while other workers
are blocked trying to send results. Handle short reads/writes and interrupted
I/O, and put bounded startup/shutdown handling around workers that never send
`READY` or fail to exit after `STOP`.

Encode integer fields in a documented fixed-width byte order and validate
message version, type, length, field ranges, and assignment identity. The
worker result is an aggregate, so IPC volume stays proportional to the number
of chunks rather than candidates. The coordinator can validate structural
invariants without overflowing: first check `completed <= count`, then
`unresolved == count - completed`, `winner_count <= completed`, and winner
IDs lying inside the assigned range. Define an explicit absent-winner flag
for `first_winner_id` when `winner_count == 0`; ID zero is a valid winner and
cannot be a sentinel. Require zero winners exactly when `completed == 0`;
otherwise require a positive winner count and an in-range first-winner ID.
These checks detect protocol errors but are not a replacement for differential
correctness tests.

Avoid shared-memory queues and cross-process atomic state in the first version.
A parent-owned queue is small, easy to audit, naturally supports retries, and
does not require platform-specific synchronization or cache-coherence tuning.
If pipe/event-loop overhead is later measured as a bottleneck, evaluate a
different transport in a separate proposal using the same message semantics.

## Aggregation and deterministic output

Worker completion order must not change results. For every accepted chunk,
aggregate the following using checked arithmetic:

- total candidates completed (HALT);
- total unresolved candidates (step limit or whatever non-winning status the
  existing search policy defines);
- global maximum output-character count;
- number of halted candidates attaining that maximum;
- lowest candidate ID attaining the maximum.

For each chunk, the worker reports its maximum, the count at that maximum, and
the lowest winning candidate ID. Ignore chunks with zero halted candidates
when merging winner fields, while still adding their accounting counters.
When merging a nonempty chunk summary, initialize the winner fields if no
halted candidate has yet been accepted; otherwise:

1. If its best score exceeds the global best, replace the score, winner count,
   and first winner ID.
2. If it equals the global best, add its winner count with checked arithmetic
   and take the lower first-winner ID.
3. If it is lower, do not change winner fields.

This produces the same first winner as sequential ascending-ID enumeration
without retaining all results. A chunk with no halted candidate reports zero
winners and no first-winner ID; zero-output halting programs remain winners
under the current behavior. Preserve the existing JSON representation when
the entire search has no winners: `best_output_characters` and `winner_count`
are zero and `first_winner` is an `L`-element zero array. The internal absent
winner flag does not by itself authorize a public schema change. The output
schema and text format should remain stable between sequential and parallel
search, except for explicitly added
optional execution metadata such as worker count. Do not make elapsed time or
worker completion order part of correctness output.

`exhaustive` is true only when every candidate has one accepted result and no
unresolved candidate remains, matching current semantics. If any worker,
protocol, arithmetic, or coordinator failure prevents complete accounting,
return a nonzero status and do not present partial counts as a complete search.

## Cancellation, step limits, and resource limits

Every candidate uses the exact existing `--max-steps` bound; reaching it is an
unresolved candidate, not a worker failure. Keep candidate-level accounting
and aggregate unresolved counts unchanged.

The current sequential `search_cmd` counts every non-HALT runner result,
including `I4917_RUN_ERROR`, as unresolved. Preserve that behavior for parity;
distinguish it from worker startup, IPC, or coordinator errors, which prevent
accounting for a chunk. Changing both search paths to report candidate runner
errors separately would be a separate semantic decision.

On user cancellation or coordinator shutdown, stop assigning chunks, tell idle
workers to stop, request assigned workers to stop at a safe candidate boundary,
and wait for children to exit. Discard partial chunk results unless the
protocol explicitly supports a completed-prefix result with a separately
specified meaning. Cancellation must not be reported as exhaustive. Bound
shutdown waiting and then terminate/reap remaining children using the chosen
platform abstraction. A worker must check for cancellation between candidates
rather than only after an entire chunk; this may require polling the command
channel while a chunk is assigned. A single long candidate may still run until
its bound, so cancellation of the parent must not wait indefinitely for a
candidate boundary. Ensure every child is reaped and every pipe/handle is
closed on all error paths.

Validate `--jobs` and `--chunk-size` before starting workers. Reject zero,
unrepresentable, or unreasonable values rather than overflowing allocation or
process-count calculations. Clamp useful worker count to the number of chunks
or candidates. Avoid allocating one result record per candidate; retain only
worker state and aggregate summaries. A cap for maximum workers may be set by
implementation/platform policy and should be documented.

## Platform and process-launch strategy

Keep process creation, pipes, waiting, termination, and signal handling behind
a small `4917_process` abstraction so search aggregation has no platform
syscalls. Select the initial supported platform baseline before implementation.
The current CMake project uses Unix Makefiles in its presets, but that is a
build-generator choice and does not itself define the supported operating
systems.

On POSIX systems, process creation and waiting can use the platform's process
APIs (for example, `fork`/`exec` or `posix_spawn` with pipes and `waitpid`). On
Windows, use the corresponding process creation and pipe/handle APIs (such as
`CreateProcessW`) or explicitly defer Windows support. The official references
describe distinct APIs and lifecycle details: [POSIX `posix_spawn`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/posix_spawn.html),
[POSIX `waitpid`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/wait.html),
and [Microsoft `CreateProcessW`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw).
Do not assume a C11 standard library provides process management.

Prefer spawning a fresh worker process rather than forking after the parent
has initialized thread/runtime state; this avoids inheriting unrelated open
descriptors and makes worker startup explicit. If POSIX `fork` is chosen,
document the restrictions and ensure only async-signal-safe operations occur
between fork and exec in a multithreaded parent. Do not rely on CMake's Unix
Makefiles preset as a substitute for runtime portability tests.

## CLI proposal

Extend only the C `search` command. Preserve sequential behavior as the default
(`--jobs 1`) and add options such as:

```text
4917-c search --length N [--max-steps N] [--jobs N]
              [--chunk-size N] [--json]
```

Choose and document defaults after benchmarks. A conservative initial proposal
is `--jobs 1` by default and a fixed chunk size in the low hundreds, with
`--jobs 0` rejected rather than treated as an implicit hardware-concurrency
request. If automatic worker count is later desired, specify whether it means
logical CPUs, physical cores, or an explicit platform query. Output should
state the chosen execution mode in human-readable output; machine-readable
fields should be optional additions with a schema-version decision.

The existing search supports lengths only 1–4. Benchmark and implementation
must not silently raise that bound as a side effect of adding parallelism.
Worker mode is internal and must validate all received options, since it is a
process boundary even if only the parent invokes it.

## Correctness and failure testing

Keep the single-process search implementation available as the oracle and
compare sequential and parallel results exactly for the same inputs. Add tests
that cover:

- Every current length (1–4) where runtime permits, varied step limits
  including zero, all-unresolved searches at a zero step limit, mixed
  searches, and isolated chunk fixtures with all halted candidates.
- Chunk sizes 1, a non-divisor of the candidate count, equal to the total,
  greater than the total, and boundary values; jobs 1, 2, and more jobs than
  chunks.
- Candidate range decoding at first/last IDs and chunk boundaries, verifying
  lexicographic program order and no gaps or overlaps in the dispatched ranges.
- Direct scheduling/decoding tests for the length-4 and hypothetical length-8
  examples above, leading/trailing zeroes, the `2^32` endpoint, checked
  `16^16` rejection, and chunk-count arithmetic near `UINT64_MAX`; these
  tests inspect ranges without evaluating the entire large domain.
- Tie aggregation across chunks that complete out of order, including multiple
  zero-output winners and winners split across the first/last chunk.
- Checked range arithmetic, counter aggregation, malformed protocol frames,
  stale/duplicate chunk IDs, worker exits before result, worker exits after a
  full result, retry limit, and coordinator cancellation/shutdown.
- Initial `READY` and implicit request-after-`RESULT` transitions, short or
  truncated frames, cancellation during a chunk, bounded restart failure, and
  no-winner chunk summaries arriving before/after zero-output winners.
- A long sequence of tiny chunks with bounded coordinator storage, verifying
  accepted-result deduplication does not require retaining completed chunk IDs.
- Repeated runs with randomized worker delays to confirm byte-for-byte stable
  result fields and first-winner selection.
- Differential checks against the Haskell or independent unpruned oracle for
  the existing supported small domains, reusing the same semantic cases as the
  sequential C search.

Inject worker failures and delays through a test-only worker option or a
replaceable process launcher. Do not add hidden production environment
variables that change search semantics. Ensure tests cannot leave orphan
workers behind.

## Benchmark plan

Add multi-process search workloads to the existing benchmark executable or a
dedicated benchmark driver. Keep timing out of CTest pass/fail criteria. Record
compiler/version, flags, machine, OS, CPU availability, search length,
step-limit, chunk size, job count, candidate throughput, and whether worker
startup/teardown is included.

Measure at least:

- Sequential baseline and `--jobs` values 2 and several available cores.
- End-to-end time including process launch, protocol setup, and aggregation,
  because this is what a user experiences.
- Repeated warm-pool or worker-reuse timing only if the implementation exposes
  such an API; do not compare it directly to one-shot CLI timing without
  labeling the difference.
- Multiple chunk sizes to show the tradeoff between scheduling overhead and
  load balance.
- Current lengths 1–4 and a range of step limits. In particular, retain small
  spaces that reveal when parallel overhead costs more than useful execution.
- Median and spread from multiple samples, with result checksums verified
  against sequential output outside the timed region.

Define a break-even policy from measured end-to-end time. If a search is below
the empirically supported threshold, run it sequentially even when `--jobs`
requests parallelism, or make the user opt in explicitly; choose between these
behaviors as a CLI product decision. Report the actual chosen job count so
benchmarks remain interpretable. Do not claim linear scaling from candidate
count alone: candidate run lengths, process startup, chunk dispatch, and
available CPU quota affect results.

## Staged implementation

1. Extract or isolate candidate-ID decoding and chunk-range arithmetic, keeping
   the sequential search output unchanged; add direct range and tie-order tests.
2. Define the versioned worker protocol and platform process abstraction. Add a
   persistent worker mode that evaluates one assigned chunk at a time and
   returns one summary before waiting for another assignment.
3. Implement the coordinator's bounded dynamic queue, response validation,
   retry/reap behavior, deterministic summary merge, and cancellation cleanup.
4. Add CLI configuration and CTest coverage for process parity and injected
   failures; run existing C, sanitizer, and Haskell differential suites.
5. Add benchmark cases and collect a sequential/parallel baseline before
   selecting defaults or a break-even threshold.

## Decisions before implementation

- Which operating systems and process APIs are in the initial support
  contract? Is Windows support required for the first release?
- Should `--jobs` opt in to parallel mode, or may the implementation
  automatically choose sequential execution for small searches?
- What initial `--chunk-size`, retry count, worker cap, and shutdown timeout
  are justified by tests and measurements?
- Should there be a distinct `--parallel` switch, or are `--jobs` and
  `--chunk-size` sufficient?
- Should progress reporting be included, and if so, what should it look like
  without destabilizing JSON output?
- Is a worker pool reused across multiple searches in one process worth the
  additional lifecycle complexity, or is one-shot CLI search the only initial
  target?
- If “at most length” is desired later, should candidates be distinct padded
  machine images (already covered by the current domain) or programs labelled
  by supplied length? Should length 8 be supported? Both are separate decisions
  from chunk scheduling and must not silently expand this implementation.
