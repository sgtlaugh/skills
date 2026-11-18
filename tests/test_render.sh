#!/usr/bin/env bash
# Tests for aristarchus/render.sh: the reader layout it prints from the golden review in references/output-example.md
DIR="$(cd "$(dirname "$0")" && pwd)"
R="$DIR/../skills/aristarchus/render.sh"
EX="$DIR/../skills/aristarchus/references/output-example.md"
T=$(mktemp -d)
pass=0; fail=0
assert() {
    if [ "$2" = "$3" ]; then echo "  PASS: $1"; pass=$((pass+1)); else echo "  FAIL: $1 (expected '$2', got '$3')"; fail=$((fail+1)); fi
}

echo "=== render.sh ==="
out=$(bash "$R" "$EX")
above=$(awk '/^---$/{exit}{print}' <<<"$out")
assert "the title, then who, size, CI and ticket on one line" "**PR #812 · OWL-4521: Retry moon-phase fetches and cache the result per hour**|@ada · 4 files (+96 −12) · CI passing · OWL-4521" \
    "$(sed -n 1,2p <<<"$out" | paste -sd'|' -)"
assert "what it does, then the verdict with its reason, before any finding" "1:1" \
    "$(grep -c '^\*\*What it does:\*\* Wraps the moon-phase API call' <<<"$out"):$(grep -c '^\*\*Verdict:\*\* ❌ Request changes. #1 can take the sighting page down.$' <<<"$out")"
assert "findings to fix, then the pre-existing nit as a small thing" "**Fix before merge (3)**|**Small things (1)**" \
    "$(grep -E '^\*\*(Fix before merge|Also worth knowing|Small things) \(' <<<"$out" | paste -sd'|' -)"
assert "every finding to fix is shown, by its header" "1 2 3" "$(grep -oE '^\S+\s+\*\*#[0-9]+ · (critical|warning)' <<<"$out" | grep -oE '[0-9]+' | paste -sd' ' -)"
assert "a finding leads with what breaks, then why, then the fix" "1|2|3" \
    "$(grep -A3 '^🛑  \*\*#1 ' <<<"$out" | sed -n '2p;3p;4p' | awk '/One slow upstream blocks every page/{print 1} /takes `_lock` before calling/{print 2} /^→ Fix:$/{print 3}' | paste -sd'|' -)"
assert "the evidence line becomes a marker; weak stays weak" "1:1" \
    "$(grep -c '^✓ confirmed · read moon.py:80-95 and the timeout in client.py:12$' <<<"$out"):$(grep -c '^~ weak · would need the worker deployment config' <<<"$out")"
assert "a small thing is one line with its marker" "1" "$(grep -c '^✏️  \*\*#4 · nit · Refactor · owl/moon.py:40 · pre-existing\*\* `MOON_URL` is built with `+`.* ✓ confirmed · read moon.py:40$' <<<"$out")"
assert "no agent names above the footer" "0" "$(grep -ciE 'darkmoon|skeptic|\blens' <<<"$above")"
assert "the footer says how it ran, in plain words" "1:1:1" \
    "$(grep -c '^\*\*Checked:\*\* 5 points by an independent read - 3 confirmed, 1 weak, 0 unsure, 1 dropped as wrong$' <<<"$out"):$(grep -c '^\*\*Ran:\*\* 5/5 review angles · ' <<<"$out"):$(grep -c '^\*\*Read:\*\* CLAUDE.md (8 rules) · 2 existing comments (1 already raised) · ticket OWL-4521 fetched' <<<"$out")"
assert "and its confidence and time" "1:1" "$(grep -c '^\*\*Confidence:\*\* High - traced the lock' <<<"$out"):$(grep -c '^\*\*Time:\*\* 3m 12s$' <<<"$out")"

# More than 3 nits: the first 3 shown, the rest counted; a pre-existing warning is worth knowing, not to fix
perl -0pe 's/(✏️  \*\*#4[^\n]*\n[^\n]*\n[^\n]*\n)/$1\n✏️  **#5 · nit · Naming · owl\/a.py:1**\nRename a.\n*Confirmed - read a.py.* (verified)\n\n✏️  **#6 · nit · Naming · owl\/b.py:1**\nRename b.\n*Confirmed - read b.py.* (verified)\n\n✏️  **#7 · nit · Naming · owl\/c.py:1**\nRename c.\n*Confirmed - read c.py.* (verified)\n/; s/(\*\*#3 · warning · Bug · owl\/cache.py:14)\*\*/$1 · pre-existing**/' "$EX" > "$T/many.md"
out=$(bash "$R" "$T/many.md")
assert "at most 3 small things, the rest counted" "**Small things (3)**:1:3" \
    "$(grep -o '^\*\*Small things ([0-9])\*\*' <<<"$out"):$(grep -c '^+1 more in the full review$' <<<"$out"):$(grep -c '^✏️  ' <<<"$out")"
assert "a pre-existing warning goes under Also worth knowing" "**Fix before merge (2)**|**Also worth knowing (1)**" \
    "$(grep -E '^\*\*(Fix before merge|Also worth knowing) \(' <<<"$out" | paste -sd'|' -)"

# --fast: no independent check, so no marker symbol; the agent steps read as skipped review angles
perl -0pe 's/\*\*Verified\*\*: [^\n]*/**Verified**: skipped (--fast)/; s/ \((verified|weak)\)//g; s/\*\*Agents\*\*: [^\n]*/**Agents**: lenses skipped (--fast) | mutation skipped (--fast)/' "$EX" > "$T/fast.md"
out=$(bash "$R" "$T/fast.md")
assert "--fast: the evidence keeps one dot and no marker; the lenses read as review angles" "1:0:1" \
    "$(grep -c '^· read moon.py:80-95 and the timeout in client.py:12$' <<<"$out"):$(grep -c '· ·' <<<"$out"):$(grep -c '^\*\*Ran:\*\* review angles skipped (--fast) · mutation skipped (--fast)$' <<<"$out")"
bash "$R" "$T/nope.md" >/dev/null 2>&1; assert "a missing file is a usage error" "2" "$?"
rm -rf "$T"
echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
