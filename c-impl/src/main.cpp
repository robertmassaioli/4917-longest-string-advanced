#include "4917/machine.h"

#include <CLI/CLI.hpp>

#include <array>
#include <charconv>
#include <cinttypes>
#include <cstdio>
#include <cstring>
#include <new>
#include <string>
#include <string_view>
#include <vector>

namespace {

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
    if (length < 1 || length > 5) {
        std::fputs("search length must be from 1 through 5\n", stderr);
        return 2;
    }
    uint64_t total = 1;
    for (uint64_t i = 0; i < length; ++i)
        total *= 16;
    uint64_t halted = 0, cycled = 0, errors = 0, best = 0, winners = 0;
    std::array<uint8_t, I4917_MEMORY_SIZE> first{};
    for (uint64_t id = 0; id < total; ++id) {
        uint64_t encoded = id;
        std::array<uint8_t, I4917_MEMORY_SIZE> program{};
        for (uint64_t i = length; i > 0; --i) {
            program[static_cast<size_t>(i - 1)] = static_cast<uint8_t>(encoded & 15U);
            encoded >>= 4;
        }
        i4917_state initial;
        i4917_init(&initial, program.data(), static_cast<size_t>(length));
        const i4917_run_result result = i4917_run_until_halt_or_cycle(&initial);
        if (result.termination == I4917_HALTED) {
            ++halted;
            if (!winners || result.output_characters > best) {
                best = result.output_characters;
                winners = 1;
                first = program;
            } else if (result.output_characters == best) {
                ++winners;
            }
        } else if (result.termination == I4917_CYCLE) {
            ++cycled;
        } else {
            ++errors;
        }
    }
    if (json) {
        std::printf("{\"schema\":\"4917-search-v2\",\"length\":%" PRIu64
                    ",\"candidate_count\":\"%" PRIu64 "\",\"halted\":\"%" PRIu64
                    "\",\"cycled\":\"%" PRIu64 "\",\"errors\":\"%" PRIu64 "\",\"exhaustive\":%s,"
                    "\"best_output_characters\":\"%" PRIu64 "\",\"winner_count\":\"%" PRIu64
                    "\",\"first_winner\":[",
                    length, total, halted, cycled, errors, errors ? "false" : "true", best, winners);
        for (uint64_t i = 0; i < length; ++i)
            std::printf("%s%u", i ? "," : "", static_cast<unsigned>(first[static_cast<size_t>(i)]));
        std::puts("]}");
    } else {
        std::printf("candidates: %" PRIu64 "\nhalted: %" PRIu64 "\ncycled: %" PRIu64
                    "\nerrors: %" PRIu64 "\nexhaustive: %s\nbest output characters: %" PRIu64
                    "\nwinner count: %" PRIu64 "\n",
                    total, halted, cycled, errors, errors ? "no" : "yes", best, winners);
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
    search->add_option("--length", length_text, "Program length (1-5)")
        ->required()->multi_option_policy(CLI::MultiOptionPolicy::Throw);
    search->add_flag("--json", json, "Write machine-readable JSON")
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
        std::strcmp(argv[1], "step") != 0) {
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
    if (run->parsed())
        return run_cmd(program, limit, json);
    if (search->parsed()) {
        uint64_t length = 0;
        if (!read_number(length_text, "search", "--length", length))
            return 2;
        if (length < 1 || length > 5) {
            command_usage("search");
            std::fprintf(stderr, "search length must be from 1 through 5 (got '%s')\n", length_text.c_str());
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
