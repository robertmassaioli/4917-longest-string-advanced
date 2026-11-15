#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="${1:-$repo_root/c-impl/build/cppcheck}"
compile_commands="$build_dir/compile_commands.json"
if [[ ! -f "$compile_commands" ]]; then
    echo "error: $compile_commands not found" >&2
    echo "configure with: cmake -S c-impl -B c-impl/build/cppcheck -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DI4917_BUILD_BENCHMARKS=ON" >&2
    exit 2
fi

cppcheck --project="$compile_commands" --std=c11 --enable=warning \
    --error-exitcode=1 --inline-suppr
