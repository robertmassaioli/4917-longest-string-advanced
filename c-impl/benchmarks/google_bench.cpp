#include "4917/machine.h"

#include <benchmark/benchmark.h>

#include <cstdint>

namespace {

void instruction_benchmark(benchmark::State &bench, unsigned opcode,
                           bool branch_taken) {
  i4917_state state;
  i4917_init(&state, nullptr, 0);
  state.memory[0] = static_cast<uint8_t>(opcode);
  state.memory[1] = 15;
  state.memory[15] = 6;
  state.r0 = static_cast<uint8_t>(opcode == 14 ? (branch_taken ? 0 : 1)
                                : opcode == 15 ? (branch_taken ? 1 : 0)
                                               : 7);
  state.r1 = 9;

  // Verify the fixture before timing. The measured loop intentionally retains
  // the existing C harness semantics: rewind PC, then call the exported C ABI.
  i4917_state check = state;
  i4917_event event{};
  if (i4917_step(&check, &event) != I4917_OK) {
    bench.SkipWithError("instruction preflight failed");
    return;
  }
  const uint8_t expected_pc = (opcode == 13 ||
                               (opcode == 14 && branch_taken) ||
                               (opcode == 15 && branch_taken))
                                  ? 15
                                  : (opcode == 8 || opcode == 9 || opcode == 10 ||
                                     opcode == 11 || opcode == 12 ||
                                     (opcode == 14 && !branch_taken) ||
                                     (opcode == 15 && !branch_taken))
                                        ? 2
                                        : 1;
  if (check.pc != expected_pc) {
    bench.SkipWithError("instruction preflight produced an unexpected PC");
    return;
  }

  for (auto _ : bench) {
    state.pc = 0;
    i4917_event step_event{};
    const i4917_error error = i4917_step(&state, &step_event);
    benchmark::DoNotOptimize(&error);
    benchmark::DoNotOptimize(&step_event);
    benchmark::ClobberMemory();
  }
  benchmark::DoNotOptimize(state);
  bench.SetItemsProcessed(bench.iterations());
  bench.counters["single_steps_per_second"] = benchmark::Counter(
      static_cast<double>(bench.iterations()), benchmark::Counter::kIsRate);
  bench.counters["opcode"] = static_cast<double>(opcode);
  if (opcode == 14 || opcode == 15) {
    bench.counters["branch_taken"] = branch_taken ? 1.0 : 0.0;
  }
}

#define REGISTER_INSTRUCTION(op, label)                                      \
  BENCHMARK_CAPTURE(instruction_benchmark, op##_##label, op, true)            \
      ->Name("instruction/" #op "-" #label)

REGISTER_INSTRUCTION(0, halt);
REGISTER_INSTRUCTION(1, add_r0_r1);
REGISTER_INSTRUCTION(2, sub_r0_r1);
REGISTER_INSTRUCTION(3, inc_r0);
REGISTER_INSTRUCTION(4, inc_r1);
REGISTER_INSTRUCTION(5, dec_r0);
REGISTER_INSTRUCTION(6, dec_r1);
REGISTER_INSTRUCTION(7, nop);
REGISTER_INSTRUCTION(8, output);
REGISTER_INSTRUCTION(9, load_r0);
REGISTER_INSTRUCTION(10, load_r1);
REGISTER_INSTRUCTION(11, store_r0);
REGISTER_INSTRUCTION(12, store_r1);
REGISTER_INSTRUCTION(13, jump);
BENCHMARK_CAPTURE(instruction_benchmark, op14_jump_if_zero_taken, 14, true)
    ->Name("instruction/14-jump-if-zero/taken");
BENCHMARK_CAPTURE(instruction_benchmark, op14_jump_if_zero_not_taken, 14,
                  false)
    ->Name("instruction/14-jump-if-zero/not-taken");
BENCHMARK_CAPTURE(instruction_benchmark, op15_jump_if_nonzero_taken, 15,
                  true)
    ->Name("instruction/15-jump-if-nonzero/taken");
BENCHMARK_CAPTURE(instruction_benchmark, op15_jump_if_nonzero_not_taken, 15,
                  false)
    ->Name("instruction/15-jump-if-nonzero/not-taken");

void run_program(benchmark::State &bench, const uint8_t *program, size_t length,
                 uint64_t limit) {
  i4917_state initial;
  i4917_init(&initial, program, length);
  const i4917_run_result preflight = i4917_run_bounded(&initial, limit);
  if (preflight.termination == I4917_RUN_ERROR || preflight.steps == 0) {
    bench.SkipWithError("program fixture preflight failed");
    return;
  }
  uint64_t checksum = 0;
  for (auto _ : bench) {
    const i4917_run_result result = i4917_run_bounded(&initial, limit);
    benchmark::DoNotOptimize(&result);
    checksum += result.steps + result.output_characters + result.final_state.pc;
  }
  benchmark::DoNotOptimize(checksum);
  bench.SetItemsProcessed(bench.iterations() *
                          static_cast<int64_t>(preflight.steps));
  bench.counters["logical_steps_per_second"] = benchmark::Counter(
      static_cast<double>(bench.iterations()) * preflight.steps,
      benchmark::Counter::kIsRate);
  bench.counters["steps_per_run"] = static_cast<double>(preflight.steps);
}

void short_straight_line(benchmark::State &bench) {
  const uint8_t program[] = {3, 4, 0};
  run_program(bench, program, sizeof(program), 16);
}
BENCHMARK(short_straight_line);

void arithmetic_heavy(benchmark::State &bench) {
  const uint8_t program[] = {3, 4, 1, 5, 6, 2, 13, 0};
  run_program(bench, program, sizeof(program), 128);
}
BENCHMARK(arithmetic_heavy);

void search_length_two(benchmark::State &bench) {
  uint64_t halted = 0;
  uint64_t checksum = 0;
  for (auto _ : bench) {
    for (unsigned id = 0; id < 256; ++id) {
      const uint8_t program[] = {static_cast<uint8_t>(id >> 4),
                                 static_cast<uint8_t>(id & 15)};
      i4917_state initial;
      i4917_init(&initial, program, sizeof(program));
      const i4917_run_result result = i4917_run_bounded(&initial, 128);
      halted += result.termination == I4917_HALTED ? 1U : 0U;
      checksum += result.output_characters + result.steps;
    }
  }
  benchmark::DoNotOptimize(halted);
  benchmark::DoNotOptimize(checksum);
  bench.SetItemsProcessed(bench.iterations() * 256);
  bench.counters["candidates_per_second"] = benchmark::Counter(
      static_cast<double>(bench.iterations()) * 256.0,
      benchmark::Counter::kIsRate);
  bench.counters["halted_per_iteration"] =
      static_cast<double>(halted) / static_cast<double>(bench.iterations());
  bench.counters["checksum"] = static_cast<double>(checksum);
}
BENCHMARK(search_length_two);

} // namespace

int main(int argc, char **argv) {
  benchmark::Initialize(&argc, argv);
  benchmark::AddCustomContext("benchmark_framework", "Google Benchmark 1.9.1");
  benchmark::AddCustomContext("build_type", I4917_BENCH_BUILD_TYPE);
  benchmark::AddCustomContext("c_compiler", I4917_BENCH_C_COMPILER);
  benchmark::AddCustomContext("c_flags", I4917_BENCH_C_FLAGS);
  benchmark::AddCustomContext("cxx_compiler", I4917_BENCH_CXX_COMPILER);
  benchmark::AddCustomContext("cxx_flags", I4917_BENCH_CXX_FLAGS);
  benchmark::AddCustomContext("source_revision", I4917_SOURCE_REVISION);
  benchmark::AddCustomContext("instruction_fixture",
                              "prebuilt state; PC reset inside timed loop; state validation included");
  benchmark::RunSpecifiedBenchmarks();
  benchmark::Shutdown();
  return 0;
}
