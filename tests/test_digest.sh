#!/usr/bin/env bash
# Tests for velka/digest.sh
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/../skills/velka/digest.sh"
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

assert_jq() {
    local desc="$1" expr="$2" expected="$3" json="$4"
    local actual
    actual=$(echo "$json" | jq -r "$expr" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"; pass=$((pass+1))
    else
        echo "  FAIL: $desc (jq '$expr' = '$actual', expected '$expected')"; fail=$((fail+1))
    fi
}

echo "=== digest.sh ==="

# Test 1: produces valid JSON
out=$(bash "$SCRIPT" "$FIX/basic-session.jsonl" 2>/dev/null); rc=$?
assert_exit "produces valid JSON, exits 0" 0 "$rc"
echo "$out" | jq empty 2>/dev/null; jqrc=$?
assert_exit "output is valid JSON" 0 "$jqrc"

# Test 2: correct session metadata
assert_jq "session id" ".id" "test-digest" "$out"
assert_jq "project path" ".project" "/home/dev/project" "$out"

# Test 3: token accounting
assert_jq "input tokens summed" ".tokens.in" "300" "$out"
assert_jq "output tokens summed" ".tokens.out" "90" "$out"
assert_jq "cache read tokens" ".tokens.cache_read" "20" "$out"

# Test 4: tool counts
assert_jq "Read tool count" ".tools.Read" "1" "$out"
assert_jq "Edit tool count" ".tools.Edit" "1" "$out"
assert_jq "Bash tool count" ".tools.Bash" "1" "$out"

# Test 5: file tracking
assert_jq "edited file tracked" '.files_edited["/src/login.py"]' "1" "$out"
assert_jq "read file tracked" '.files_read["/src/login.py"]' "1" "$out"

# Test 6: bash classification
assert_jq "git commit counted" ".bash.git_commit" "1" "$out"
assert_jq "total bash commands" ".bash.total" "1" "$out"

# Test 7: slash command extraction
assert_jq "slash command found" ".slash[0]" "commit" "$out"

# Test 8: first prompt captured
out_prompt=$(echo "$out" | jq -r '.first_prompt' 2>/dev/null)
assert_exit "first_prompt is non-empty" 0 "$([ -n "$out_prompt" ] && echo 0 || echo 1)"

# Test 9: first_prompt keeps only human intent - slash args + typed prompts, no skill text,
# interrupt markers, task notifications or compact summaries
noisy=$(bash "$SCRIPT" "$FIX/velka-noise.jsonl" 2>/dev/null | jq -r '.first_prompt')
assert_exit "first_prompt is slash args + typed prompt only" 0 \
    "$([ "$noisy" = "PROJ-1234 load-shedding retries pile up after the 3am outage | Why does the retry queue double every time the power comes back?" ] && echo 0 || echo 1)"
legacy=$(bash "$SCRIPT" "$FIX/skill-injection-darkmoon.jsonl" 2>/dev/null | jq -r '.first_prompt')
assert_exit "skill text without isMeta (older transcripts) is dropped" 0 \
    "$(printf '%s' "$legacy" | grep -q 'Base directory for this skill' && echo 1 || echo 0)"

# Test 10: real typed prompts that start with "<" or mention a filtered word survive; wrapper tags don't
edges=$(bash "$SCRIPT" "$FIX/velka-human-edges.jsonl" 2>/dev/null | jq -r '.first_prompt')
assert_exit "typed prompts starting with < or naming caveman are kept, wrapper output dropped" 0 \
    "$([ "$edges" = '<div class="owl"> renders twice after the 3am power cut, why? | Why is caveman mode eating my commit messages again?' ] && echo 0 || echo 1)"

# A crash mid-write leaves a cut-off last line; the session must still digest
cutoff=$(mktemp)
cat "$FIX/basic-session.jsonl" > "$cutoff"
printf '{"type":"user","message":{"content":"the bonfire went out mid-wri' >> "$cutoff"
truncated=$(bash "$SCRIPT" "$cutoff" 2>/dev/null); rc=$?
rm -f "$cutoff"
assert_exit "a cut-off last line is skipped, not fatal" 0 "$rc"
assert_exit "the rest of a cut-off session is still digested" 0 \
    "$([ "$(jq -r '.assistant_msgs' <<<"$truncated")" = "$(jq -r '.assistant_msgs' <<<"$out")" ] && echo 0 || echo 1)"

echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
