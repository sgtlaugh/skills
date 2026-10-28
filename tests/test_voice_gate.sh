#!/usr/bin/env bash
# Tests for humanize/voice-gate.sh
DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$DIR/../skills/humanize/voice-gate.sh"
EM=$'\xe2\x80\x94'
SHA=4f2a9c1e8b7d6a5f4e3d2c1b0a9f8e7d6c5b4a39
pass=0; fail=0

# check <desc> <expected exit> <needle in output or ""> <text>
check() {
    local desc="$1" expected="$2" needle="$3" out rc
    out=$(printf '%s' "$4" | bash "$GATE" 2>&1); rc=$?
    if [ "$rc" = "$expected" ] && { [ -z "$needle" ] || grep -qF -- "$needle" <<<"$out"; }; then
        echo "  PASS: $desc"; pass=$((pass+1))
    else
        echo "  FAIL: $desc (expected $expected${needle:+ with \"$needle\"}, got $rc: $out)"; fail=$((fail+1))
    fi
}

echo "=== voice-gate.sh ==="
check "clean comment in the house style" 0 "" "\`load_owl_schedule\` retries forever when the moon API returns 503 ([here](https://github.com/acme/owl/blob/$SHA/owl/moon.py#L42)).

Should we cap it at 3 attempts? That might be fine for a cron job, but this runs in the request path."
check "minor nit lead-in is allowed" 0 "" "**Minor nit:** the docstring repeats the function name."
check "em dash" 1 "em dash" "Looks good ${EM} ship it."
check "heading" 1 "heading" "## Summary
The owl hoots."
check "emoji" 1 "emoji" "Looks good 🚀"
check "fence without a language" 1 "without a language" $'Output:\n```\nhoot\n```'
check "long code outside details" 1 "outside <details>" "$(printf 'Repro:\n```python\n'; for i in $(seq 16); do echo "hoot($i)"; done; printf '```')"
check "long code inside details" 0 "" "$(printf 'Repro:\n<details><summary>Repro</summary>\n\n```python\n'; for i in $(seq 16); do echo "hoot($i)"; done; printf '```\n\n</details>')"
check "4-line suggestion" 1 "suggestion block" $'Simpler:\n```suggestion\na = 1\nb = 2\nc = 3\nd = 4\n```'
check "branch permalink" 1 "not a commit SHA" "See https://github.com/acme/owl/blob/main/owl/moon.py#L42"
check "bare identifier" 1 "identifier \"retry_count\"" "Should retry_count reset after a success?"
check "bare camelCase" 1 "identifier \"checkExpiry\"" "Does checkExpiry default to true?"
check "identifier inside a URL is fine" 0 "" "See [the spike](https://github.com/acme/owl/pull/3881) for limits."
check "prose over the cap" 1 "characters of prose" "$(printf 'hoot %.0s' $(seq 130))"
check "code does not count toward the cap" 0 "" "$(printf 'Repro:\n```text\n'; printf 'hoot %.0s' $(seq 200); printf '\n```')"
check "severity tag" 1 "severity tag" "**Critical:** the owl escapes."
check "praise filler" 1 "praise filler" "Great job on this, the cache works."
check "contrast framing" 1 "contrast framing" "It's not a cache, it's a leak."
check "banned phrase from the list" 1 "banned phrase" "It's worth noting that the owl hoots at 3am."
check "self-narration from the list" 1 "banned phrase" "This highlights a race in the scheduler."
check "file:line in backticks is not a link" 1 "is not a link" "Every delete calls \`delay()\` (\`rendition_type.py:128\`)."
check "file:line linked to a SHA blob" 0 "" "Every delete calls \`delay()\` ([\`rendition_type.py:128\`](https://github.com/acme/owl/blob/$SHA/app/rendition_type.py#L128))."
check "cross-repo PR without owner" 1 "needs its owner" "With nest-config#16394 this runs twice."
check "owner/repo#N, PR#N and #N are fine" 0 "" "With acme/nest-config#16394 and PR#12 this runs twice, see #554."
check "six comments in a review" 1 "6 inline comments" '[{"body":"a"},{"body":"b"},{"body":"c"},{"body":"d"},{"body":"e"},{"body":"f"}]'
check "per-comment numbering in JSON" 1 "comment 2: em dash" "[{\"body\":\"fine\"},{\"body\":\"hoot ${EM} hoot\"}]"

echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
