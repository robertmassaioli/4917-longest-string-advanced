#!/usr/bin/env python3
"""Command-level contract checks for the 4917 C frontend."""

import argparse
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    binary = parser.parse_args().binary

    def invoke(*arguments):
        return subprocess.run(
            [binary, *arguments], text=True, capture_output=True, check=False
        )

    def succeeds(*arguments):
        result = invoke(*arguments)
        assert result.returncode == 0, (arguments, result.returncode, result.stderr)
        assert not result.stderr, (arguments, result.stderr)
        return result.stdout

    def rejects(*arguments, diagnostic=None, usage_expected=True):
        result = invoke(*arguments)
        assert result.returncode == 2, (arguments, result.returncode, result.stdout)
        assert result.stderr, (arguments, "expected an error diagnostic")
        if usage_expected:
            assert "Usage:" in result.stderr, (arguments, result.stderr)
        if diagnostic:
            assert diagnostic in result.stderr, (arguments, result.stderr)

    assert "SUBCOMMANDS:" in succeeds("--help")
    assert "--max-steps" in succeeds("run", "--help")
    assert "--length" in succeeds("search", "-h")
    assert "--output-characters" in succeeds("step", "--help")

    assert '"termination":"halted"' in succeeds(
        "run", "--program", "0", "--json"
    )
    assert '"termination":"step_limit"' in succeeds(
        "run", "--program", "7", "--max-steps", "0", "--json"
    )
    length_one_search = succeeds("search", "--length", "1", "--json")
    assert '"candidate_count":"15"' in length_one_search
    assert '"search_space_count":"16"' in length_one_search
    assert '"skipped_candidate_count":"1"' in length_one_search
    assert '"best_output_characters":"1"' in length_one_search
    assert '"first_winner":[8]' in length_one_search
    assert '"schema":"4917-step-v1"' in succeeds(
        "step", "--memory", "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0", "--json"
    )
    default_limit = succeeds("run", "--program", "13,0", "--json")
    assert '"steps":"10000"' in default_limit

    rejects()
    rejects("nonsense", diagnostic="unknown command")
    rejects("run", diagnostic="--program")
    rejects("search", diagnostic="--length")
    rejects("step", diagnostic="--memory")
    rejects("run", "--program", diagnostic="--program")
    rejects("run", "--program", "0", "--max-steps", diagnostic="--max-steps")
    rejects("run", "--program", "0", "--unknown")
    rejects("run", "--program", "0", "--length", "1")
    rejects("search", "--length", "1", "--program", "0")
    rejects("step", "--memory", "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0", "--json", "extra")
    rejects("run", "--program", "0", "--program", "0")
    rejects("run", "--program", "0", "--json", "--json")
    rejects("search", "--length", "1", "--length", "2")

    rejects("run", "--program", "0", "--max-steps", "", diagnostic="--max-steps")
    rejects("run", "--program", "0", "--max-steps", "-1", diagnostic="invalid")
    rejects("run", "--program", "0", "--max-steps", "1x", diagnostic="invalid")
    rejects(
        "run", "--program", "0", "--max-steps", "18446744073709551616",
        diagnostic="invalid"
    )
    rejects("search", "--length", "1", "--max-steps", "0")
    rejects("search", "--length", "0", diagnostic="length must be from 1 through 16")
    rejects("search", "--length", "17", diagnostic="length must be from 1 through 16")
    rejects("search", "--length", "word", diagnostic="invalid")
    rejects("step", "--memory", "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0", "--r0", "16", diagnostic="--r0 must be from 0 through 15")
    rejects("step", "--memory", "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0", "--output-characters", "x", diagnostic="invalid")
    rejects("run", "--program", "0,16", diagnostic="invalid program", usage_expected=False)
    rejects("run", "--program", "0,,1", diagnostic="invalid program", usage_expected=False)
    rejects("step", "--memory", "0", diagnostic="invalid state", usage_expected=False)


if __name__ == "__main__":
    main()
