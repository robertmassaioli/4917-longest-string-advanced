# Per-instruction C vs C++ benchmarks

These are the per-opcode measurements from the C benchmark harness. Each opcode fixture performs 1,048,576 `i4917_step` calls in each of five timed samples; taken and not-taken conditional branches are separate fixtures. The table uses the median throughput from each of three queued captures, then takes the median across those three run medians. Change is `(C++ / C - 1) × 100`.

The C baseline is local `main` commit `3437e7a`; the candidate is the C++ port in this worktree. Both used the same standalone C harness, Release `-O3`, Apple clang 17.0.0.13, and macOS arm64. Individual opcode differences are especially sensitive to timer and scheduling noise; compare the overall workload results in [`Cpp-Implementation-Proposal.md`](../../../Cpp-Implementation-Proposal.md) for the broader conclusion.

To reproduce all per-instruction fixtures, build the `benchmarks` preset and run `./build/make-benchmarks/4917-bench --instructions --json`. To select one opcode, run `./build/make-benchmarks/4917-bench --instruction 9 --json`.

| Instruction fixture | C (M instr/s) | C++ (M instr/s) | Change |
| --- | ---: | ---: | ---: |
| 00 HALT | 183.9 | 186.8 | +1.6% |
| 01 ADD R0, R1 | 194.7 | 204.3 | +4.9% |
| 02 SUB R0, R1 | 221.5 | 206.3 | -6.9% |
| 03 INC R0 | 191.3 | 209.4 | +9.5% |
| 04 INC R1 | 191.4 | 194.7 | +1.7% |
| 05 DEC R0 | 217.9 | 199.7 | -8.4% |
| 06 DEC R1 | 206.0 | 206.3 | +0.1% |
| 07 NOP | 194.8 | 215.8 | +10.8% |
| 08 OUTPUT | 192.9 | 215.8 | +11.9% |
| 09 LOAD R0 | 206.4 | 230.2 | +11.5% |
| 10 LOAD R1 | 204.2 | 216.7 | +6.2% |
| 11 STORE R0 | 194.4 | 220.3 | +13.3% |
| 12 STORE R1 | 195.8 | 213.3 | +8.9% |
| 13 JUMP | 216.1 | 217.2 | +0.5% |
| 14 JUMP IF ZERO (taken) | 208.4 | 230.0 | +10.4% |
| 14 JUMP IF ZERO (not taken) | 208.4 | 229.9 | +10.3% |
| 15 JUMP IF NONZERO (taken) | 209.5 | 229.5 | +9.6% |
| 15 JUMP IF NONZERO (not taken) | 202.8 | 242.2 | +19.4% |

## Raw captures

Each file contains NDJSON output from one queued run (25 fixtures, five internal samples per fixture).

**C baseline:** [`cpp-port-c-baseline-1.ndjson`](cpp-port-c-baseline-1.ndjson), [`cpp-port-c-baseline-2.ndjson`](cpp-port-c-baseline-2.ndjson), [`cpp-port-c-baseline-3.ndjson`](cpp-port-c-baseline-3.ndjson).
**C++ candidate:** [`cpp-port-candidate-1.ndjson`](cpp-port-candidate-1.ndjson), [`cpp-port-candidate-2.ndjson`](cpp-port-candidate-2.ndjson), [`cpp-port-candidate-3.ndjson`](cpp-port-candidate-3.ndjson).
