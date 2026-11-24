#include "4917/machine.h"
#include "machine_internal.hpp"

#include <CLI/CLI.hpp>

#include <array>
#include <charconv>
#include <cinttypes>
#include <cstdio>
#include <cstring>
#include <new>
#include <random>
#include <string>
#include <string_view>
#include <vector>

namespace {

struct SearchCount {
    uint64_t low = 0;
    bool is_two_to_64 = false;

    void increment() {
        if (low == UINT64_MAX) {
            low = 0;
            is_two_to_64 = true;
        } else if (!is_two_to_64) {
            ++low;
        }
    }

    bool is_zero() const { return low == 0 && !is_two_to_64; }

    std::string text() const {
        return is_two_to_64 ? "18446744073709551616" : std::to_string(low);
    }
};

bool number(std::string_view text, uint64_t &value) {
    if (text.empty())
        return false;
    uint64_t parsed = 0;
    const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), parsed);
    if (error != std::errc{} || end != text.data() + text.size())
        return false;
    value = parsed;
    return true;
}

bool parse_csv(std::string_view csv, std::array<uint8_t, 16> &values, size_t &length) {
    if (csv.empty())
        return false;
    size_t count = 0;
    size_t begin = 0;
    while (begin <= csv.size()) {
        const size_t comma = csv.find(',', begin);
        const size_t end = comma == std::string_view::npos ? csv.size() : comma;
        uint64_t value = 0;
        if (count == values.size() || !number(csv.substr(begin, end - begin), value) || value > 15)
            return false;
        values[count++] = static_cast<uint8_t>(value);
        if (comma == std::string_view::npos)
            break;
        begin = comma + 1;
    }
    length = count;
    return count != 0;
}

const char *term(i4917_termination termination) {
    switch (termination) {
    case I4917_HALTED:
        return "halted";
    case I4917_LIMIT_REACHED:
        return "step_limit";
    case I4917_CYCLE:
        return "cycle";
    default:
        return "error";
    }
}

void state_json(const i4917_state &state) {
    std::printf("\"memory\":[");
    for (size_t i = 0; i < I4917_MEMORY_SIZE; ++i)
        std::printf("%s%u", i ? "," : "", static_cast<unsigned>(state.memory[i]));
    std::printf("],\"r0\":%u,\"r1\":%u,\"pc\":%u,\"output_characters\":\"%" PRIu64 "\"",
                static_cast<unsigned>(state.r0), static_cast<unsigned>(state.r1),
                static_cast<unsigned>(state.pc), state.output_characters);
}

int run_cmd(const std::string &csv, uint64_t limit, bool json) {
    std::array<uint8_t, I4917_MEMORY_SIZE> program{};
    size_t length = 0;
    if (!parse_csv(csv, program, length)) {
        std::fputs("invalid program: expected 1-16 comma-separated values from 0 through 15\n", stderr);
        return 2;
    }
    i4917_state state;
    i4917_init(&state, program.data(), length);
    std::vector<uint8_t> output;
    i4917_termination termination = I4917_LIMIT_REACHED;
    uint64_t steps = 0;
    for (; steps < limit; ++steps) {
        i4917_event event{};
        if (i4917_step(&state, &event) != I4917_OK) {
            termination = I4917_RUN_ERROR;
            break;
        }
        if (event.emitted) {
            try {
                output.push_back(event.value);
            } catch (const std::bad_alloc &) {
                termination = I4917_RUN_ERROR;
                break;
            }
        }
        if (event.halted) {
            ++steps;
            termination = I4917_HALTED;
            break;
        }
    }
    if (json) {
        std::printf("{\"schema\":\"4917-run-v1\",\"termination\":\"%s\",\"steps\":\"%" PRIu64
                    "\",\"output_values\":[", term(termination), steps);
        for (size_t i = 0; i < output.size(); ++i)
            std::printf("%s%u", i ? "," : "", static_cast<unsigned>(output[i]));
        std::printf("],");
        state_json(state);
        std::puts("}");
    } else {
        std::printf("termination: %s after %" PRIu64 " steps\noutput values:", term(termination), steps);
        for (uint8_t value : output)
            std::printf(" %u", static_cast<unsigned>(value));
        std::printf("\noutput characters: %" PRIu64 "\n", state.output_characters);
    }
    return termination == I4917_RUN_ERROR ? 1 : 0;
}

int step_cmd(const std::string &csv, uint64_t r0, uint64_t r1, uint64_t pc,
             uint64_t output_characters, bool json) {
    std::array<uint8_t, I4917_MEMORY_SIZE> memory{};
    size_t length = 0;
    if (!parse_csv(csv, memory, length) || length != I4917_MEMORY_SIZE || r0 > 15 || r1 > 15 || pc > 15) {
        std::fputs("invalid state: memory must contain 16 nibbles and registers/PC must be 0 through 15\n",
                   stderr);
        return 2;
    }
    i4917_state state;
    i4917_init(&state, memory.data(), length);
    state.r0 = static_cast<uint8_t>(r0);
    state.r1 = static_cast<uint8_t>(r1);
    state.pc = static_cast<uint8_t>(pc);
    state.output_characters = output_characters;
    i4917_event event{};
    if (i4917_step(&state, &event) != I4917_OK) {
        std::fputs("step failed\n", stderr);
        return 1;
    }
    if (json) {
        std::printf("{\"schema\":\"4917-step-v1\",\"event_value\":");
        if (event.emitted)
            std::printf("%u", static_cast<unsigned>(event.value));
        else
            std::fputs("null", stdout);
        std::printf(",\"halted\":%s,", event.halted ? "true" : "false");
        state_json(state);
        std::puts("}");
    } else {
        std::printf("event: %s", event.emitted ? "output" : "none");
        if (event.emitted)
            std::printf(" %u", static_cast<unsigned>(event.value));
        std::printf("\nhalted: %s\n", event.halted ? "yes" : "no");
    }
    return 0;
}

int search_cmd(uint64_t length, bool json) {
    if (length < 1 || length > I4917_MEMORY_SIZE) {
        std::fprintf(stderr, "search length must be from 1 through %u\n",
                     static_cast<unsigned>(I4917_MEMORY_SIZE));
        return 2;
    }
    const bool full_space = length == I4917_MEMORY_SIZE;
    const uint64_t total = full_space ? 0 : (uint64_t{1} << (4 * length));
    SearchCount halted, cycled, errors, winners;
    uint64_t best = 0;
    std::array<uint8_t, I4917_MEMORY_SIZE> first{};
    for (uint64_t id = 0; full_space || id < total;) {
        uint64_t encoded = id;
        std::array<uint8_t, I4917_MEMORY_SIZE> program{};
        for (uint64_t i = length; i > 0; --i) {
            program[static_cast<size_t>(i - 1)] = static_cast<uint8_t>(encoded & 15U);
            encoded >>= 4;
        }
        const i4917_run_result result = i4917_detail::run_search_aggregate_program(program);
        if (result.termination == I4917_HALTED) {
            halted.increment();
            if (winners.is_zero() || result.output_characters > best) {
                best = result.output_characters;
                winners = SearchCount{1, false};
                first = program;
            } else if (result.output_characters == best) {
                winners.increment();
            }
        } else if (result.termination == I4917_CYCLE) {
            cycled.increment();
        } else {
            errors.increment();
        }
        if (full_space && id == UINT64_MAX)
            break;
        ++id;
    }
    const std::string candidate_count = full_space ? "18446744073709551616" : std::to_string(total);
    const std::string halted_text = halted.text();
    const std::string cycled_text = cycled.text();
    const std::string errors_text = errors.text();
    const std::string winners_text = winners.text();
    if (json) {
        std::printf("{\"schema\":\"4917-search-v2\",\"length\":%" PRIu64
                    ",\"candidate_count\":\"%s\",\"halted\":\"%s"
                    "\",\"cycled\":\"%s\",\"errors\":\"%s\",\"exhaustive\":%s,"
                    "\"best_output_characters\":\"%" PRIu64 "\",\"winner_count\":\"%s"
                    "\",\"first_winner\":[",
                    length, candidate_count.c_str(), halted_text.c_str(), cycled_text.c_str(),
                    errors_text.c_str(), errors.is_zero() ? "true" : "false", best, winners_text.c_str());
        for (uint64_t i = 0; i < length; ++i)
            std::printf("%s%u", i ? "," : "", static_cast<unsigned>(first[static_cast<size_t>(i)]));
        std::puts("]}");
    } else {
        std::printf("candidates: %s\nhalted: %s\ncycled: %s"
                    "\nerrors: %s\nexhaustive: %s\nbest output characters: %" PRIu64
                    "\nwinner count: %s\n",
                    candidate_count.c_str(), halted_text.c_str(), cycled_text.c_str(), errors_text.c_str(),
                    errors.is_zero() ? "yes" : "no", best, winners_text.c_str());
    }
    return 0;
}

void program_json(const std::array<uint8_t, I4917_MEMORY_SIZE> &program, size_t length) {
    std::printf("[");
    for (size_t i = 0; i < length; ++i)
        std::printf("%s%u", i ? "," : "", static_cast<unsigned>(program[i]));
    std::printf("]");
}

int dataset_cmd(uint64_t length, uint64_t count, uint64_t max_steps,
                const std::string &strategy, const std::string &initial_program,
                uint64_t seed) {
    if (length < 1 || length > I4917_MEMORY_SIZE) {
        std::fprintf(stderr, "dataset length must be from 1 through %u\n",
                     static_cast<unsigned>(I4917_MEMORY_SIZE));
        return 2;
    }
    if (strategy != "random" && strategy != "mutate" && strategy != "template") {
        std::fputs("dataset strategy must be 'random', 'mutate', or 'template'\n", stderr);
        return 2;
    }
    if (strategy == "template" && length < 10) {
        std::fputs("template strategy supports declared lengths 10 through 16\n", stderr);
        return 2;
    }
    if (strategy != "mutate" && !initial_program.empty()) {
        std::fputs("dataset --program is only valid with --strategy mutate\n", stderr);
        return 2;
    }

    std::array<uint8_t, I4917_MEMORY_SIZE> incumbent{};
    if (strategy == "mutate") {
        size_t initial_length = 0;
        if (!parse_csv(initial_program, incumbent, initial_length) || initial_length != length) {
            std::fputs("mutate strategy requires --program with exactly --length nibbles\n", stderr);
            return 2;
        }
    }

    std::mt19937_64 random(seed);
    std::uniform_int_distribution<unsigned> nibble(0, 15);
    std::uniform_int_distribution<size_t> position(0, static_cast<size_t>(length - 1));
    uint64_t incumbent_score = 0;
    bool have_halted_incumbent = false;

    for (uint64_t sample = 0; sample < count; ++sample) {
        std::array<uint8_t, I4917_MEMORY_SIZE> candidate{};
        if (strategy == "random") {
            for (size_t i = 0; i < length; ++i)
                candidate[i] = static_cast<uint8_t>(nibble(random));
        } else if (strategy == "template") {
            // The length-16 staged counter from explainers/length-16.md. Cells
            // 2 and 15 are exposed as template parameters; all execution is
            // still evaluated by the direct simulator below.
            constexpr std::array<uint8_t, I4917_MEMORY_SIZE> staged_counter = {
                1, 8, 15, 14, 4, 2, 4, 15, 0, 9, 2, 5, 11, 2, 14, 2};
            candidate = staged_counter;
            candidate[2] = static_cast<uint8_t>(nibble(random));
            candidate[15] = static_cast<uint8_t>(nibble(random));
        } else if (sample == 0) {
            candidate = incumbent;
        } else {
            candidate = incumbent;
            const size_t changed = position(random);
            uint8_t value = static_cast<uint8_t>(nibble(random));
            if (value == candidate[changed])
                value = static_cast<uint8_t>((value + 1U) & 15U);
            candidate[changed] = value;
        }

        i4917_state initial;
        i4917_init(&initial, candidate.data(), static_cast<size_t>(length));
        const i4917_run_result result = i4917_run_bounded(&initial, max_steps);
        const bool halted = result.termination == I4917_HALTED;
        const char *status = halted ? "halted" :
                             result.termination == I4917_LIMIT_REACHED ? "unresolved" :
                             result.termination == I4917_CYCLE ? "cycle" : "error";
        if (strategy == "mutate" && halted &&
            (!have_halted_incumbent || result.output_characters > incumbent_score)) {
            incumbent = candidate;
            incumbent_score = result.output_characters;
            have_halted_incumbent = true;
        }

        std::printf("{\"schema\":\"4917-dataset-v1\",\"sample\":\"%" PRIu64
                    "\",\"length\":%" PRIu64 ",\"program\":",
                    sample, length);
        program_json(candidate, static_cast<size_t>(length));
        std::printf(",\"strategy\":\"%s\",\"seed\":\"%" PRIu64
                    "\",\"max_steps\":\"%" PRIu64
                    "\",\"status\":\"%s\",\"output_characters\":",
                    strategy.c_str(), seed, max_steps, status);
        if (halted)
            std::printf("\"%" PRIu64 "\"", result.output_characters);
        else
            std::printf("null");
        std::printf(",\"observed_output_characters\":\"%" PRIu64
                    "\",\"steps\":\"%" PRIu64 "\"}\n",
                    result.output_characters, result.steps);
        if (result.termination == I4917_RUN_ERROR)
            return 1;
    }
    return 0;
}

void command_usage(const char *command) {
    std::fprintf(stderr, "Usage: 4917-cpp %s [OPTIONS]\n", command);
}

bool read_number(const std::string &text, const char *command, const char *option, uint64_t &value) {
    if (number(text, value))
        return true;
    command_usage(command);
    std::fprintf(stderr, "invalid nonnegative decimal value for %s: '%s'\n", option, text.c_str());
    return false;
}

} // namespace

int main(int argc, char **argv) {
    CLI::App app{"4917 microprocessor program runner and search tool"};
    app.require_subcommand(1);

    std::string program;
    std::string memory;
    std::string length_text;
    std::string max_steps_text = "10000";
    std::string dataset_length_text, dataset_count_text = "1000", dataset_max_steps_text = "1000000";
    std::string strategy = "random", dataset_program;
    std::string seed_text = "1";
    std::string r0_text = "0", r1_text = "0", pc_text = "0", output_text = "0";
    bool json = false;

    CLI::App *run = app.add_subcommand("run", "Execute a program");
    run->add_option("--program", program, "Program values (1-16 nibbles)")
        ->required()->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    run->add_option("--max-steps", max_steps_text, "Stop after at most N instructions")
        ->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    run->add_flag("--json", json, "Write machine-readable JSON")
        ->multi_option_policy(CLI::MultiOptionPolicy::Throw);

    CLI::App *search = app.add_subcommand("search", "Exhaustively search programs of a given length");
    search->add_option("--length", length_text, "Program length (1-16)")
        ->required()->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    search->add_flag("--json", json, "Write machine-readable JSON")
        ->multi_option_policy(CLI::MultiOptionPolicy::Throw);

    CLI::App *dataset = app.add_subcommand("dataset", "Generate directly evaluated candidate labels as JSONL");
    dataset->add_option("--length", dataset_length_text, "Declared program length (1-16)")
        ->required()->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    dataset->add_option("--count", dataset_count_text, "Number of candidates to evaluate")
        ->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    dataset->add_option("--strategy", strategy, "Candidate source: random, mutate, or template")
        ->check(CLI::IsMember({"random", "mutate", "template"}))->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    dataset->add_option("--program", dataset_program, "Mutation seed program (required for mutate)")
        ->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    dataset->add_option("--seed", seed_text, "Deterministic random seed")
        ->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    dataset->add_option("--max-steps", dataset_max_steps_text, "Per-candidate execution budget")
        ->multi_option_policy(CLI::MultiOptionPolicy::Throw);

    CLI::App *step = app.add_subcommand("step", "Execute one instruction from a supplied state");
    step->add_option("--memory", memory, "Exactly 16 memory nibbles")
        ->required()->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    step->add_option("--r0", r0_text, "Initial r0 value (0-15)")
        ->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    step->add_option("--r1", r1_text, "Initial r1 value (0-15)")
        ->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    step->add_option("--pc", pc_text, "Initial program counter (0-15)")
        ->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    step->add_option("--output-characters", output_text, "Initial output-character count")
        ->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    step->add_flag("--json", json, "Write machine-readable JSON")
        ->multi_option_policy(CLI::MultiOptionPolicy::Throw);

    if (argc > 1 && std::strcmp(argv[1], "--help") != 0 && std::strcmp(argv[1], "-h") != 0 &&
        std::strcmp(argv[1], "run") != 0 && std::strcmp(argv[1], "search") != 0 &&
        std::strcmp(argv[1], "step") != 0 && std::strcmp(argv[1], "dataset") != 0) {
        std::fprintf(stderr, "4917-cpp: unknown command '%s'\nUsage: 4917-cpp <command> [OPTIONS]\n",
                     argv[1]);
        return 2;
    }

    try {
        app.parse(argc, argv);
    } catch (const CLI::ParseError &error) {
        if (error.get_name() == "CallForHelp")
            return app.exit(error);
        std::fprintf(stderr, "Usage: 4917-cpp %s [OPTIONS]\nError: %s\n",
                     argc > 1 ? argv[1] : "<command>", error.what());
        return 2;
    }

    uint64_t limit = 10000;
    if (run->parsed()) {
        if (!read_number(max_steps_text, "run", "--max-steps", limit))
            return 2;
    }
    if (dataset->parsed()) {
        uint64_t length = 0, count = 0, dataset_max_steps = 0, seed = 0;
        if (!read_number(dataset_length_text, "dataset", "--length", length) ||
            !read_number(dataset_count_text, "dataset", "--count", count) ||
            !read_number(dataset_max_steps_text, "dataset", "--max-steps", dataset_max_steps) ||
            !read_number(seed_text, "dataset", "--seed", seed))
            return 2;
        return dataset_cmd(length, count, dataset_max_steps, strategy, dataset_program, seed);
    }
    if (run->parsed())
        return run_cmd(program, limit, json);
    if (search->parsed()) {
        uint64_t length = 0;
        if (!read_number(length_text, "search", "--length", length))
            return 2;
        if (length < 1 || length > I4917_MEMORY_SIZE) {
            command_usage("search");
            std::fprintf(stderr, "search length must be from 1 through %u (got '%s')\n",
                         static_cast<unsigned>(I4917_MEMORY_SIZE), length_text.c_str());
            return 2;
        }
        return search_cmd(length, json);
    }

    uint64_t r0 = 0, r1 = 0, pc = 0, output_characters = 0;
    if (!read_number(r0_text, "step", "--r0", r0) || !read_number(r1_text, "step", "--r1", r1) ||
        !read_number(pc_text, "step", "--pc", pc) ||
        !read_number(output_text, "step", "--output-characters", output_characters))
        return 2;
    if (r0 > 15 || r1 > 15 || pc > 15) {
        const char *option = r0 > 15 ? "--r0" : r1 > 15 ? "--r1" : "--pc";
        command_usage("step");
        std::fprintf(stderr, "%s must be from 0 through 15\n", option);
        return 2;
    }
    return step_cmd(memory, r0, r1, pc, output_characters, json);
}
