#!/usr/bin/env python3
"""Differentially check Metal exhaustive results against the exact CPU solver."""

import argparse
import json
import subprocess


def run(binary, args):
    return json.loads(subprocess.check_output([binary, *args, "--json"], text=True))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--metal", required=True)
    parser.add_argument("--cpu", required=True)
    args = parser.parse_args()
    compared = (
        "candidate_count",
        "halted",
        "cycled",
        "errors",
        "exhaustive",
        "best_output_characters",
        "winner_count",
        "first_winner",
    )
    for length in (1, 2, 3):
        expected = run(args.cpu, ["search", "--length", str(length)])
        for limit in (1, 2, 4096):
            actual = run(args.metal, ["--length", str(length), "--gpu-step-limit", str(limit)])
            for key in compared:
                assert actual[key] == expected[key], (
                    f"length {length}, GPU budget {limit}, field {key}: "
                    f"Metal={actual[key]!r}, CPU={expected[key]!r}"
                )
            assert int(actual["gpu_halted"]) + int(actual.get("gpu_cycled", 0)) + int(actual["cpu_exact_fallback"]) == int(
                actual["candidate_count"]
            )
            if limit == 1:
                assert int(actual["cpu_exact_fallback"]) > 0
    # The compact result encoding reserves two low bits for status and only
    # uses uint output below 2^29 steps. Check both sides of that cutoff.
    expected = run(args.cpu, ["search", "--length", "1"])
    for limit in ((1 << 29) - 1, 1 << 29):
        actual = run(args.metal, ["--length", "1", "--gpu-step-limit", str(limit)])
        for key in compared:
            assert actual[key] == expected[key], (
                f"length 1, GPU budget {limit}, field {key}: "
                f"Metal={actual[key]!r}, CPU={expected[key]!r}"
            )
    wrapped_print = run(
        args.metal,
        ["--program", "13,15,0,0,0,0,0,0,0,0,0,0,0,0,0,8", "--gpu-step-limit", "16"],
    )
    assert wrapped_print == {
        "schema": "4917-metal-run-v1",
        "termination": "halted",
        "steps": "4",
        "output_characters": "2",
    }
    self_modifying = run(args.metal, ["--program", "11,4,13,4,8,15,0", "--gpu-step-limit", "16"])
    assert self_modifying["termination"] == "halted" and self_modifying["output_characters"] == "0"
    cycle = run(args.metal, ["--program", "13,0", "--gpu-step-limit", "1"])
    assert cycle["termination"] == "cycle"
    print("Metal search matches exact CPU results for lengths 1–3 at GPU budgets 1, 2, and 4096.")


if __name__ == "__main__":
    main()
