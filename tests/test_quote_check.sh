#!/usr/bin/env bash
# Tests for velka/quote-check.sh
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/../skills/velka/quote-check.sh"
ROOT=$(mktemp -d)
mkdir -p "$ROOT/proj"
cp "$DIR/fixtures/velka-blocks.jsonl" "$ROOT/proj/owl-blocks-0001.jsonl"
cp "$DIR/fixtures/velka-blocks.jsonl" "$ROOT/proj/owl-blocks-0002.jsonl"
pass=0; fail=0

# check <desc> <expected exit> <needle or ""> <json>
check() {
    local desc="$1" expected="$2" needle="$3" out rc
    out=$(printf '%s' "$4" | VELKA_PROJECTS="$ROOT" bash "$SCRIPT" 2>&1); rc=$?
    if [ "$rc" = "$expected" ] && { [ -z "$needle" ] || grep -qF -- "$needle" <<<"$out"; }; then
        echo "  PASS: $desc"; pass=$((pass+1))
    else
        echo "  FAIL: $desc (expected $expected${needle:+ with \"$needle\"}, got $rc: $out)"; fail=$((fail+1))
    fi
}

echo "=== quote-check.sh ==="
check "verbatim human quote passes, whitespace-insensitive" 0 "PASS" '[{"session":"owl-blocks-0001","quote":"never squash my   commits"}]'
check "invented quote fails" 1 "not in any human turn" '[{"session":"owl-blocks-0001","quote":"I love long commit subjects"}]'
check "tool output can't vouch for a quote" 1 "not in any human turn" '[{"session":"owl-blocks-0001","quote":"commit-guard: blocked"}]'
check "ambiguous prefix fails" 1 "2 transcripts match" '[{"session":"owl-blocks","quote":"never squash my commits"}]'
check "unknown session fails" 1 "0 transcripts match" '[{"session":"hoot-hoot-404","quote":"never squash my commits"}]'
check "short id fails" 1 "8+ characters" '[{"session":"owl","quote":"never squash my commits"}]'
check "one bad quote fails the batch" 1 "PASS owl-blocks-0001" '[{"session":"owl-blocks-0001","quote":"never squash my commits"},{"session":"owl-blocks-0002","quote":"made up words here"}]'
check "non-array input is a usage error" 2 "JSON array" '{"session":"owl-blocks-0001"}'

rm -rf "$ROOT"
echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
