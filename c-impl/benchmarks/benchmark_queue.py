#!/usr/bin/env python3
"""Serialize C benchmark runs across agents sharing this machine.

Usage:
  python3 /absolute/path/benchmark_queue.py --label candidate-a -- COMMAND ARG...

The advisory lock is global to this repository's C benchmark campaign. Keep
builds, tests, and timed benchmark commands inside the queued command so they
cannot contend with another candidate's measurements.
"""

import datetime
import fcntl
import subprocess
import sys
import time
from pathlib import Path


def main() -> int:
    args = sys.argv[1:]
    if len(args) < 4 or args[0] != "--label" or "--" not in args[2:]:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    label = args[1]
    split_at = args.index("--", 2)
    command = args[split_at + 1 :]
    if not command:
        print("benchmark queue requires a command after --", file=sys.stderr)
        return 2

    lock_path = Path("/tmp/4917-longest-string-advanced-c-benchmark.lock")
    with lock_path.open("a") as lock:
        print(f"[{label}] queued at {datetime.datetime.now().astimezone().isoformat()}", flush=True)
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        started = time.monotonic()
        print(f"[{label}] acquired benchmark lock", flush=True)
        try:
            return_code = subprocess.run(command, check=False).returncode
        finally:
            elapsed = time.monotonic() - started
            print(f"[{label}] released benchmark lock after {elapsed:.2f}s", flush=True)
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
    return return_code


if __name__ == "__main__":
    raise SystemExit(main())
