#!/usr/bin/env bash
# Tests for velka/collect.sh
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/../skills/velka/collect.sh"
FIX="$DIR/fixtures"
pass=0; fail=0

assert_exit() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"; pass=$((pass+1))
    else
        echo "  FAIL: $desc (expected exit $expected, got $actual)"; fail=$((fail+1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"; pass=$((pass+1))
    else
        echo "  FAIL: $desc (expected to contain: $needle)"; fail=$((fail+1))
    fi
}

echo "=== collect.sh ==="

# Setup: temp project root with a session file
TMPROOT=$(mktemp -d)
TMPPROJECT="$TMPROOT/test-project"
mkdir -p "$TMPPROJECT"
cp "$FIX/basic-session.jsonl" "$TMPPROJECT/session-hobbit.jsonl"
# bash 3.2 compares -nt in whole seconds; an old mtime keeps the cache check from racing the copy
touch -t 202601050000 "$TMPPROJECT/session-hobbit.jsonl"

export VELKA_DIGDIR="$TMPROOT/digests"

# Test 1: processes new files
out=$(bash "$SCRIPT" "$TMPROOT" 2>&1); rc=$?
assert_exit "collect exits 0" 0 "$rc"
assert_contains "reports digested count" "1 digested" "$out"

# Test 2: second run uses cache
out=$(bash "$SCRIPT" "$TMPROOT" 2>&1); rc=$?
assert_exit "cached run exits 0" 0 "$rc"
assert_contains "reports cached count" "1 cached" "$out"

# Cleanup
rm -rf "$TMPROOT"

echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
