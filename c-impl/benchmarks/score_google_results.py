#!/usr/bin/env python3
"""Compare Google Benchmark JSON captures for the fixed C core workloads."""

import json
import math
import statistics
import sys
from pathlib import Path

FIXTURES = ("short_straight_line", "arithmetic_heavy", "search_length_two")


def summarize(path):
    data = json.loads(Path(path).read_text())
    medians = {}
    cvs = {}
    for fixture in FIXTURES:
        values = [
            row["items_per_second"]
            for row in data["benchmarks"]
            if row["name"] == fixture
        ]
        if not values:
            raise ValueError(f"{path}: missing benchmark fixture {fixture}")
        medians[fixture] = statistics.median(values)
        mean = statistics.mean(values)
        cvs[fixture] = statistics.pstdev(values) / mean * 100 if mean else 0.0
    return data, medians, cvs


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} BASELINE.json CANDIDATE.json", file=sys.stderr)
        return 2
    baseline, candidate = summarize(sys.argv[1]), summarize(sys.argv[2])
    for label, summary in (("baseline", baseline), ("candidate", candidate)):
        data, medians, cvs = summary
        context = data.get("context", {})
        print(
            f"{label}: revision={context.get('source_revision', 'unknown')} "
            f"load_avg={context.get('load_avg', 'unknown')}"
        )
        for fixture in FIXTURES:
            print(
                f"  {fixture}: {medians[fixture] / 1e6:.3f} M/s "
                f"(CV {cvs[fixture]:.2f}%)"
            )
    ratios = [candidate[1][fixture] / baseline[1][fixture] for fixture in FIXTURES]
    speedup = math.exp(sum(math.log(value) for value in ratios) / len(ratios))
    print(f"geometric mean speedup: {speedup:.3f}x ({speedup - 1:+.1%})")
    for fixture in FIXTURES:
        ratio = candidate[1][fixture] / baseline[1][fixture]
        print(f"  {fixture}: {ratio:.3f}x ({ratio - 1:+.1%})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
