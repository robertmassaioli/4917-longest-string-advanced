#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: c-impl/scripts/format-c.sh [--check|--fix]

Check C formatting with clang-format-18 (default), or apply it with --fix.
Set CLANG_FORMAT to use another compatible clang-format executable.
USAGE
}

mode="${1:---check}"
case "$mode" in
    --check|--fix) ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
if [[ $# -gt 1 ]]; then
    usage >&2
    exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
formatter="${CLANG_FORMAT:-clang-format-18}"
if ! command -v "$formatter" >/dev/null 2>&1; then
    echo "error: $formatter not found (set CLANG_FORMAT to a clang-format 18 executable)" >&2
    exit 127
fi

files=()
while IFS= read -r file; do
    files+=("$file")
done < <(
    find "$repo_root/c-impl/src" "$repo_root/c-impl/include" \
        "$repo_root/c-impl/tests" "$repo_root/c-impl/benchmarks" \
        -type f \( -name '*.c' -o -name '*.h' \) -print | sort
)
if [[ ${#files[@]} -eq 0 ]]; then
    echo "error: no C source files found" >&2
    exit 1
fi

if [[ "$mode" == "--fix" ]]; then
    "$formatter" -i "${files[@]}"
else
    "$formatter" --dry-run --Werror "${files[@]}"
fi
