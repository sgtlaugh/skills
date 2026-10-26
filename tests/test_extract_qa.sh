#!/usr/bin/env bash
# Tests for darkmoon/extract-qa.sh
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/../skills/darkmoon/extract-qa.sh"
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

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if ! echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"; pass=$((pass+1))
    else
        echo "  FAIL: $desc (should not contain: $needle)"; fail=$((fail+1))
    fi
}

echo "=== extract-qa.sh ==="

# Test 1: basic extraction exits 0
out=$(bash "$SCRIPT" "$FIX/simple-darkmoon.jsonl" 2>&1); rc=$?
assert_exit "basic extraction exits 0" 0 "$rc"
assert_contains "question extracted" "Is that safe?" "$out"
assert_contains "answer extracted" "validates input before parsing" "$out"

# Test 2: --context 1 exits 0 and includes prior exchange
out=$(bash "$SCRIPT" "$FIX/simple-darkmoon.jsonl" --context 1 2>&1); rc=$?
assert_exit "--context 1 exits 0" 0 "$rc"
assert_contains "context header present" "CONTEXT (1 prior exchanges)" "$out"
assert_contains "prior question included" "What does this function do?" "$out"

# Test 3: no darkmoon invocation exits 1
out=$(bash "$SCRIPT" "$FIX/no-darkmoon.jsonl" 2>&1); rc=$?
assert_exit "no darkmoon exits 1" 1 "$rc"

# Test 4: multi-darkmoon skips previous execution block
out=$(bash "$SCRIPT" "$FIX/multi-darkmoon.jsonl" 2>&1); rc=$?
assert_exit "multi-darkmoon exits 0" 0 "$rc"
assert_contains "targets second answer" "Second answer - this is the target" "$out"
assert_not_contains "skips first answer (inside darkmoon block)" "First answer - should be skipped" "$out"
assert_contains "targets second question" "Second question after darkmoon" "$out"

# Test 5: command-message before darkmoon pairs with correct question
out=$(bash "$SCRIPT" "$FIX/command-before-darkmoon.jsonl" 2>&1); rc=$?
assert_exit "command-before-darkmoon exits 0" 0 "$rc"
assert_contains "question is the command invocation" "ponytail" "$out"
assert_not_contains "question is NOT the earlier user-text" "Is it needed?" "$out"
assert_contains "answer is audit output" "Audit found three issues" "$out"

# Test 6: trivial approval kept as follow-up - question stays the substantive one
out=$(bash "$SCRIPT" "$FIX/trivial-skip.jsonl" 2>&1); rc=$?
assert_exit "trivial-skip exits 0" 0 "$rc"
assert_contains "finds substantive answer" "requests_per_second throttling" "$out"
assert_contains "includes follow-up in answer chain" "Done. Added" "$out"
assert_contains "finds substantive question" "performance implications" "$out"
assert_contains "follow-up label present" "[User follow-up]" "$out"
assert_contains "approval kept as follow-up" "Sure, do it" "$out"

# Test 7: skill-injection darkmoon anchor detected
out=$(bash "$SCRIPT" "$FIX/skill-injection-darkmoon.jsonl" 2>&1); rc=$?
assert_exit "skill-injection darkmoon exits 0" 0 "$rc"
assert_contains "finds answer before skill-injection anchor" "NoSQL injection vector" "$out"
assert_contains "finds question before skill-injection anchor" "security implications" "$out"

# Test 8: task-notification skipped as question
out=$(bash "$SCRIPT" "$FIX/task-notification.jsonl" 2>&1); rc=$?
assert_exit "task-notification exits 0" 0 "$rc"
assert_contains "finds real question, not task-notification" "implications of running this migration" "$out"
assert_not_contains "task-notification not in question" "task-notification" "$(echo "$out" | sed 1d)"
assert_contains "finds answer before task-notification" "ACCESS EXCLUSIVE lock" "$out"

# Test 8b: isMeta peer messages and compact summaries are never the question
out=$(bash "$SCRIPT" "$FIX/meta-before-darkmoon.jsonl" 2>&1); rc=$?
assert_exit "meta fixture exits 0" 0 "$rc"
assert_contains "finds the human question past meta entries" "double-charge when two keepers" "$out"
assert_not_contains "peer-session message not picked" "Another Claude session sent" "$out"
assert_not_contains "compact summary not picked" "being continued from a previous" "$out"

# Test 9: --context 2 returns two prior exchanges
out=$(bash "$SCRIPT" "$FIX/deep-context.jsonl" --context 2 2>&1); rc=$?
assert_exit "--context 2 exits 0" 0 "$rc"
assert_contains "target question is the race condition one" "race condition" "$out"
assert_contains "target answer is the stale snapshot one" "permanently stale" "$out"
assert_contains "context has 2 exchanges" "CONTEXT (2 prior exchanges)" "$out"
assert_contains "context-1 has BFS fanout question" "BFS fanout" "$out"
assert_contains "context-2 has architecture question" "architecture of the permission" "$out"

# Test 10: sibling skill whose text mentions darkmoon is not an anchor
out=$(bash "$SCRIPT" "$FIX/sibling-skill-mentions-darkmoon.jsonl" 2>&1); rc=$?
assert_exit "sibling-skill mention exits 0" 0 "$rc"
assert_contains "answer after sibling skill kept" "hot partitions come from the order-id key" "$out"

# Test 11: short follow-up question reaches the skeptic
out=$(bash "$SCRIPT" "$FIX/short-followup.jsonl" 2>&1); rc=$?
assert_exit "short-followup exits 0" 0 "$rc"
assert_contains "short follow-up kept" "Is that write race-safe?" "$out"
assert_contains "answer to follow-up kept" "last-writer-wins" "$out"

# Question answered by nothing before /darkmoon: report the question, never die silently
out=$(bash "$SCRIPT" "$FIX/question-without-answer.jsonl" 2>&1); rc=$?
assert_exit "question without an answer exits 0" 0 "$rc"
assert_contains "question without an answer still shown" "skip the last day of every month" "$out"

# Test 12: no transcript arg resolves from CLAUDE_CODE_SESSION_ID
fake_home=$(mktemp -d)
mkdir -p "$fake_home/.claude/projects/-home-moonlit-grove"
cp "$FIX/simple-darkmoon.jsonl" "$fake_home/.claude/projects/-home-moonlit-grove/dm-0523-2002.jsonl"
out=$(HOME="$fake_home" CLAUDE_CODE_SESSION_ID=dm-0523-2002 bash "$SCRIPT" 2>&1); rc=$?
assert_exit "session-id resolution exits 0" 0 "$rc"
assert_contains "session-id resolution finds answer" "validates input before parsing" "$out"
assert_contains "resolved path printed for the skeptic" "Transcript: $fake_home/.claude/projects/-home-moonlit-grove/dm-0523-2002.jsonl" "$out"
out=$(HOME="$fake_home" CLAUDE_CODE_SESSION_ID=dm-0820-2025 bash "$SCRIPT" 2>&1); rc=$?
assert_exit "unknown session id exits 1" 1 "$rc"
out=$(env -u CLAUDE_CODE_SESSION_ID bash "$SCRIPT" 2>&1); rc=$?
assert_exit "no arg and no session id exits 1" 1 "$rc"
rm -rf "$fake_home"

# Test 13: missing file exits nonzero
out=$(bash "$SCRIPT" "/tmp/nonexistent-transcript.jsonl" 2>&1); rc=$?
assert_exit "missing file exits nonzero" 1 "$rc"

# Test 14: unknown flag exits nonzero
out=$(bash "$SCRIPT" "$FIX/simple-darkmoon.jsonl" --bogus 2>&1); rc=$?
assert_exit "unknown flag exits nonzero" 1 "$rc"

echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
