#!/usr/bin/env bash
# Tests for aristarchus/parse-findings.sh, against the golden output in references/output-example.md
DIR="$(cd "$(dirname "$0")" && pwd)"
P="$DIR/../skills/aristarchus/parse-findings.sh"
EX="$DIR/../skills/aristarchus/references/output-example.md"
pass=0; fail=0

# check <desc> <expected exit> <needle or ""> <review text>
check() {
    local desc="$1" expected="$2" needle="$3" out rc
    out=$(printf '%s' "$4" | bash "$P" --check 2>&1); rc=$?
    if [ "$rc" = "$expected" ] && { [ -z "$needle" ] || grep -qF -- "$needle" <<<"$out"; }; then
        echo "  PASS: $desc"; pass=$((pass+1))
    else
        echo "  FAIL: $desc (expected $expected${needle:+ with \"$needle\"}, got $rc: $out)"; fail=$((fail+1))
    fi
}
assert() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then echo "  PASS: $desc"; pass=$((pass+1))
    else echo "  FAIL: $desc (expected '$expected', got '$actual')"; fail=$((fail+1)); fi
}
mutate() { perl -0pe "$1" "$EX"; }

echo "=== parse-findings.sh ==="
golden=$(cat "$EX")
check "the golden example passes" 0 "parse-findings: ok" "$golden"
json=$(bash "$P" "$EX")
assert "every finding is extracted" "1,2,3,4" "$(jq -r 'map(.n) | join(",")' <<<"$json")"
assert "severity is read from the word" "critical,warning,warning,nit" "$(jq -r 'map(.severity) | join(",")' <<<"$json")"
assert "verification comes from the closing marker" "verified,verified,weak,verified" "$(jq -r 'map(.verification) | join(",")' <<<"$json")"
assert "pre-existing is its own flag, not a severity" "4" "$(jq -r 'map(select(.pre_existing) | .n) | join(",")' <<<"$json")"
assert "a finding's text stops at the next ---" "0" "$(jq -r '.[0].text' <<<"$json" | grep -c 'retry predicate')"

check "an unknown severity word" 1 "not in the format" "$(mutate 's/#2 · warning · Bug/#2 · major · Bug/')"
check "an old-style header without the severity" 1 "not in the format" "$(mutate 's/#2 · warning · Bug ·/#2 · Bug ·/')"
check "emoji that contradicts the severity" 1 "leads with" "$(mutate 's/⚠️  \*\*#2/🛑  **#2/')"
check "a finding missing from the summary list" 1 "#3 has no line in the summary list" "$(mutate 's/⚠️  #3  owl\/cache.py:14\n[^\n]*\n//')"
check "a summary line with no detailed finding" 1 "#9 is in the summary list" "$(mutate 's/(\*\*Findings summary\*\*\n)/$1\n⚠️  #9  owl\/ghost.py:1\n    Ghost\n/')"
check "a verified count that disagrees with the header" 1 "header says 3 upheld but 2" "$(mutate 's/read moon.py:55-70.\* \(verified\)/read moon.py:55-70.* (unresolved)/')"
check "a finding with no verdict while darkmoon ran" 1 "#2 has no (verified)" "$(mutate 's/read moon.py:55-70.\* \(verified\)/read moon.py:55-70.*/')"
check "the same number twice" 1 "appears twice" "$(mutate 's/#3 · warning · Bug · owl\/cache.py:14/#2 · warning · Bug · owl\/cache.py:14/')"
check "a --- inside a fix block does not end the finding" 0 "parse-findings: ok" "$(mutate 's/phase = fetch_phase\(\)/---\nphase = fetch_phase()/')"
check "a missing --- after the last finding: later sections cannot vote" 0 "parse-findings: ok" "$(mutate 's/\(verified\)\n\n---\n\n\*\*Independent Review Lenses:\*\* saboteur raised #1;/(verified)\n\n**Independent Review Lenses:** (unresolved) saboteur raised #1;/')"
check "a header with extra spaces is reported, not skipped" 1 "not in the format" "$(mutate 's/\*\*#2 · warning/**#2  ·  warning/')"
check "a Verified line with the colon inside the bold still counts" 1 "header says 3 upheld but 2" "$(mutate 's/\*\*Verified\*\*: /**Verified:** /; s/read moon.py:55-70.\* \(verified\)/read moon.py:55-70.* (unresolved)/')"
check "Verified counts in another order still count" 1 "header says 3 upheld but 2" "$(mutate 's/3 upheld, 1 weak, 0 can.t-determine/0 can\x27t-determine, 1 weak, 3 upheld/; s/read moon.py:55-70.\* \(verified\)/read moon.py:55-70.* (unresolved)/')"
check "an unreadable Verified line is a problem" 1 "does not give counts for" "$(mutate 's/3 upheld, 1 weak, 0 can.t-determine, 1 refuted/all good/')"
check "can't-determine is checked against (unresolved)" 1 "can't-determine but 1" "$(mutate 's/read moon.py:55-70.\* \(verified\)/read moon.py:55-70.* (unresolved)/; s/3 upheld/2 upheld/')"
check "no verification run, no markers needed" 0 "parse-findings: ok" "$(mutate 's/\*\*Verified\*\*: [^\n]*/**Verified**: skipped (--fast)/; s/ \((verified|weak)\)//g')"

echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
