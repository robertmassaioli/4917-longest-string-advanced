#!/usr/bin/env python3
"""Score repeated 4917-bench --json output using the campaign's fixed metric."""

import json
import math
import statistics
import sys
from pathlib import Path


PRIMARY_FIXTURES = (
    "short-straight-line",
    "arithmetic-heavy",
    "output-heavy",
    "branch-loop",
    "self-modifying",
)
EXPECTED_ROWS_PER_PASS = 25


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: score_results.py RESULTS.ndjson", file=sys.stderr)
        return 2
    rows = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines() if line.strip()]
    if not rows or len(rows) % EXPECTED_ROWS_PER_PASS:
        print("input must contain complete 25-row benchmark passes", file=sys.stderr)
        return 2

    scores = []
    fixture_rates = {fixture: [] for fixture in PRIMARY_FIXTURES}
    for offset in range(0, len(rows), EXPECTED_ROWS_PER_PASS):
        batch = rows[offset : offset + EXPECTED_ROWS_PER_PASS]
        by_name = {row["fixture"]: row for row in batch}
        if len(by_name) != EXPECTED_ROWS_PER_PASS:
            print("each pass must contain 25 distinct fixtures", file=sys.stderr)
            return 2
        try:
            rates = {
                fixture: float(by_name[fixture]["throughput_per_second_median"])
                for fixture in PRIMARY_FIXTURES
            }
        except KeyError as error:
            print(f"missing primary benchmark fixture: {error}", file=sys.stderr)
            return 2
        if any(rate <= 0 for rate in rates.values()):
            print("throughput values must be positive", file=sys.stderr)
            return 2
        score = math.exp(sum(math.log(rates[name]) for name in PRIMARY_FIXTURES) / len(PRIMARY_FIXTURES))
        scores.append(score)
        for fixture in PRIMARY_FIXTURES:
            fixture_rates[fixture].append(rates[fixture])

    print("pass scores (geometric mean, M instructions/s):")
    for index, score in enumerate(scores, 1):
        print(f"  {index}: {score / 1e6:.3f}")
    print(
        "aggregate median/min/max: "
        f"{statistics.median(scores) / 1e6:.3f} / "
        f"{min(scores) / 1e6:.3f} / {max(scores) / 1e6:.3f} M instructions/s"
    )
    print("per-workload medians:")
    for fixture, values in fixture_rates.items():
        print(f"  {fixture}: {statistics.median(values) / 1e6:.3f} M instructions/s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
