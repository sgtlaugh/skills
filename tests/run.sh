#!/usr/bin/env bash
# Test runner - finds and runs all test_*.sh scripts.
# Usage: ./tests/run.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
failed_suites=()

for t in "$DIR"/test_*.sh; do
    [ -f "$t" ] || continue
    echo ""
    if bash "$t"; then
        : # suite passed
    else
        failed_suites+=("$(basename "$t")")
    fi
done

echo ""
if [ ${#failed_suites[@]} -eq 0 ]; then
    echo "All test suites passed."
else
    echo "FAILED suites: ${failed_suites[*]}"
    exit 1
fi
