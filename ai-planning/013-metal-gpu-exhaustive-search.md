# 013: Metal GPU search with exact CPU completion

**Created:** 2026-11-24

## Goal

Use the Apple M4 Pro's Metal GPU to accelerate exhaustive candidate evaluation while preserving the C++ solver's exact winner results. The GPU should handle large, independent batches of short simulations; the existing CPU cycle detector remains the authority for any candidate the GPU does not prove halted within its per-candidate budget.

## Hardware and workload

The target computer reports an Apple M4 Pro with a 20-core Metal 3 GPU. A search candidate is a 16-cell nibble memory image, two four-bit registers, and a four-bit program counter. One instruction updates that state, sometimes modifying memory. Candidate executions are independent, which gives useful GPU parallelism. Instructions within one candidate remain serial and have data-dependent control flow; this is not a matrix-multiplication workload.

The important optimization target is therefore batch throughput. Assign one GPU thread to one candidate, decode its ID into a zero-padded program, and simulate up to a configured instruction budget. A thread that reaches opcode 0 has an exact halted result and score. A thread that exhausts its budget is unresolved, not a cycle and not a failure.

## Exactness strategy

The GPU kernel deliberately does not try to classify cycles. Doing exact cycle detection on the GPU would require substantial per-lane state tracking or multiple Floyd-detection passes and could reduce throughput. Instead:

1. Every candidate is dispatched to the GPU and simulated for at most `gpu_step_limit` steps.
2. Candidates that halt in that interval are classified exactly on the GPU. Their output-character count follows the processor specification, including two-byte operands that wrap from cell 15 to cell 0, loads/stores, self-modifying code, and jumps.
3. Every candidate that has not halted by the limit is passed to `i4917_detail::run_search_program`, which exactly distinguishes a later halt, a cycle, and an execution error using the current constant-space detector.
4. Only exact halted results contribute to the best score. The final search is exhaustive if it finishes with no errors, just like the CPU search.

Thus the GPU's local execution is bounded, but the solver as a whole is not an approximate bounded search. Reducing the GPU step limit cannot alter a completed search's answer; it only changes how much work runs on GPU versus CPU. A candidate that runs for an extremely long time can still delay completion in the exact CPU fallback, as it does in the CPU-only solver.

## Interface and result reporting

Add a separate Apple-only `4917-metal-search` executable to the existing C++ implementation. It accepts:

```text
4917-metal-search --length N [--gpu-step-limit N] [--json]
```

The default GPU budget is 256 instructions per candidate. Initial M4 Pro measurements found that this gave a better balance than 4,096: most short halting paths complete on the GPU, while the kernel avoids spending time on cycles and long executions destined for exact CPU fallback. Results include the existing search totals and winner fields, plus `gpu_halted`, `cpu_exact_fallback`, and elapsed seconds. The default JSON schema is versioned separately as `4917-metal-search-v1`. Search is partitioned into fixed-size batches so candidates are streamed through Metal buffers rather than allocating output storage for the entire search space.

The executable also accepts `--program NIBBLES` to simulate one candidate through the GPU short path and exact CPU completion. This is used to exercise boundary and self-modifying examples without enumerating the whole 16-nibble space.

## Validation and benchmark plan

- Compare every result field from Metal and the CPU executable for exhaustive lengths 1–3, including best score, number of tied winners, and first winner.
- Compare additional cases at GPU limits 1, 2, and 4 to force CPU fallback; all should preserve the CPU result.
- Exercise instruction 8 at a memory boundary, memory loads and stores, conditional and unconditional control flow, immediate halt, and an execution cycle. Include a long-running candidate that exceeds the GPU budget and then halts on CPU.
- Record build/toolchain/hardware, step limit, CPU and Metal wall times, GPU-completed count, and exact-fallback count. Report both total candidates per second and measured speedup rather than assuming the GPU is faster.
- Run the existing C++ CTest suite unchanged to ensure adding the optional target does not disturb the CPU implementation.

The implementation in `c-impl/src/metal_search.mm` passed these checks on the
M4 Pro. The Metal differential test exhaustively compared lengths 1–3 against
the CPU solver at GPU budgets 1, 2, and 4,096; direct cases covered a PRINT
instruction at cell 15 reading its wrapped operand at cell 0, a store that
self-modifies a future instruction, and a detected cycle. The complete CTest
suite passed. Paired exhaustive measurements are recorded in
[`../c-impl/benchmarks/metal-search-m4-pro-2026-11-24.md`](../c-impl/benchmarks/metal-search-m4-pro-2026-11-24.md): length 5 was approximately even, while lengths 6 and 7 were 2.10× and 2.30× faster, respectively, in this run. These measured wins do not guarantee a speedup at every length or GPU budget.

## Limitations and follow-up

- This first version favors a transparent correctness boundary and straightforward Metal integration over a fully GPU-resident cycle detector.
- The exact fallback may dominate if a large fraction of programs do not halt quickly. Try multiple GPU limits and batch sizes in benchmarks.
- Device contention, energy use, thermal throttling, kernel compilation, and buffer synchronization affect measured throughput.
- Keep the CPU-only search as a portable exact baseline and as an oracle for differential checks.
- Do not use matrix multiplication for this transition function. It is a small, branch-heavy, stateful interpreter; batching independent programs is the GPU mapping.
