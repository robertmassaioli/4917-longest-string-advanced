#ifndef I4917_MACHINE_INTERNAL_HPP
#define I4917_MACHINE_INTERNAL_HPP

#include "4917/machine.h"

#include <array>

namespace i4917_detail {

// Search constructs all 16 cells, zero-padding beyond the program length,
// and guarantees that each cell is a nibble. Registers and output start at 0.
i4917_run_result run_search_program(
    const std::array<uint8_t, I4917_MEMORY_SIZE> &program);

// Search aggregation only needs to distinguish halted programs from cycles.
// The cycle result does not promise first-repeat output or final-state data.
i4917_run_result run_search_aggregate_program(
    const std::array<uint8_t, I4917_MEMORY_SIZE> &program);

i4917_run_result run_search_aggregate_candidate(uint64_t candidate_id,
                                                uint64_t length);

} // namespace i4917_detail

#endif
