#!/usr/bin/env python3
"""Run paired production C++ exhaustive searches and save their raw timings."""

import json
import subprocess
import sys
import time
from pathlib import Path


def run(binary: str, length: int) -> tuple[int, str]:
    started = time.perf_counter_ns()
    result = subprocess.run(
        [binary, "search", "--length", str(length), "--json"],
        check=True,
        capture_output=True,
        text=True,
    )
    return time.perf_counter_ns() - started, result.stdout


def main() -> int:
    if len(sys.argv) != 6:
        print(
            "usage: measure_search_pair.py BASELINE CANDIDATE LENGTH PAIRS OUTPUT.json",
            file=sys.stderr,
        )
        return 2
    baseline, candidate = sys.argv[1:3]
    length = int(sys.argv[3])
    pairs = int(sys.argv[4])
    output_path = Path(sys.argv[5])

    baseline_output = run(baseline, length)[1]
    candidate_output = run(candidate, length)[1]
    if baseline_output != candidate_output:
        print("baseline and candidate JSON differ", file=sys.stderr)
        return 1

    captures = []
    for index in range(pairs):
        order = [("baseline", baseline), ("candidate", candidate)]
        if index % 2:
            order.reverse()
        pair = {"pair": index + 1}
        for label, binary in order:
            elapsed_ns, stdout = run(binary, length)
            if stdout != baseline_output:
                print(f"{label} JSON changed during capture", file=sys.stderr)
                return 1
            pair[f"{label}_elapsed_ns"] = elapsed_ns
        captures.append(pair)

    output_path.write_text(
        json.dumps(
            {
                "command": f"4917-cpp search --length {length} --json",
                "baseline": baseline,
                "candidate": candidate,
                "pairs": captures,
                "output": baseline_output,
            },
            indent=2,
        )
        + "\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
