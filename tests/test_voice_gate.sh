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
check "clean comment in the house style" 0 "" "\`load_owl_schedule\` retries forever when the moon API returns 503, as [the retry loop](https://github.com/acme/owl/blob/$SHA/owl/moon.py#L42) never counts.

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
check "permalink URLs do not count toward the cap" 0 "" "$(printf 'hoot %.0s' $(seq 55))

$(printf 'hoot %.0s' $(seq 55))[\`a.py:12\`](https://github.com/acme/owl/blob/$SHA/some/long/path/to/a.py#L12) and [\`b.py:3\`](https://github.com/acme/owl/blob/$SHA/another/long/path/b.py#L3)"
check "code does not count toward the cap" 0 "" "$(printf 'Repro:\n```text\n'; printf 'hoot %.0s' $(seq 200); printf '\n```')"
check "severity tag" 1 "severity tag" "**Critical:** the owl escapes."
check "praise filler" 1 "praise filler" "Great job on this, the cache works."
check "contrast framing" 1 "contrast framing" "It's not a cache, it's a leak."
check "banned phrase from the list" 1 "banned phrase" "It's worth noting that the owl hoots at 3am."
check "self-narration from the list" 1 "banned phrase" "This highlights a race in the scheduler."
check "a chatbot opener" 1 "banned phrase \"Absolutely!\"" "Absolutely! The owl roosts at dusk."
check "a chatbot closer" 1 "banned phrase \"Let me know if you have any [...] questions\"" "The owl roosts at dusk. Let me know if you have any other questions."
check "an empty offer to help" 1 "banned phrase \"Feel free to reach out\"" "The owl roosts at dusk. Feel free to reach out."
check "feel free with a real action is how people write" 0 "" "@barn-owl, feel free to merge if the format looks good to you."
check "absolutely inside a sentence is a word, not an opener" 0 "" "The roost is absolutely full by dusk."
check "a leaked note about the drafting" 1 "note about drafting" "Can we leave the cache out of this PR?

voice-gate.sh ran on this draft, but run it once more before posting."
check "a draft PR is code, not a drafting note" 0 "" "This draft PR still needs the migration from acme/owl#12."
check "an empty trailing participle" 1 "trailing \"ensuring\" clause" "The cron retries on 503, ensuring the owls are always fed."
check "a participle that carries a fact is fine" 0 "" "The cron retries on 503, making it safe to restart the barn."
check "a quoted question is the asker's words: their phrases and dashes are not yours" 0 "" "> Does the barn close at dusk ${EM} or later? Hope this helps!

Yes, at dusk. The night owls use the side door."
check "the reply under a quote is still checked" 1 "banned phrase \"Hope this helps\"" "> Does the barn close at dusk?

Yes, at dusk. Hope this helps."
check "a long quote does not count toward the reply's length" 0 "" "> $(printf 'The barn door sticks every evening and the owls complain. %.0s' $(seq 12))

Fixed the hinge."
check "file:line in backticks is not a link" 1 "is not a link" "Every delete calls \`delay()\` (\`rendition_type.py:128\`)."
check "file:line linked to a SHA blob" 0 "" "Every delete calls \`delay()\` in [\`rendition_type.py:128\`](https://github.com/acme/owl/blob/$SHA/app/rendition_type.py#L128)."
check "cross-repo PR without owner" 1 "needs its owner" "With nest-config#16394 this runs twice."
check "owner/repo#N, PR#N and #N are fine" 0 "" "With acme/nest-config#16394 and PR#12 this runs twice, see #554."
check "two interjections in one review" 1 "one at most" '[{"body":"Hmm, `a` looks off."},{"body":"Ah, and `b` too."}]'
check "same opening twice" 1 "vary the openings" '[{"body":"Can we drop `a`?"},{"body":"Can we rename `b`?"}]'
check "varied openings with one interjection" 0 "" '[{"body":"Hmm, `a` races with the cron."},{"body":"Wondering if `b` needs a lock."},{"body":"Not sure why `c` retries twice."}]'
check "Well, opener" 1 "talking down" "Well, this is wrong."
check "a long paragraph is split" 1 "split it, or turn its parallel facts into bullets" "$(printf 'The owl hoots at three in the morning and wakes the nest. %.0s' $(seq 7))"
check "four short sentences are fine" 0 "" "Looks good. Logs help. I did not test. Merge on Sunday."
check "a bulleted list is not a paragraph" 0 "" "$(printf 'Hops:\n\n'; for i in 1 2 3 4 5 6; do printf -- '- The owl hoots at three in the morning and wakes the nest number %s.\n' $i; done)"
check "six comments in a review" 1 "6 inline comments" '[{"body":"a"},{"body":"b"},{"body":"c"},{"body":"d"},{"body":"e"},{"body":"f"}]'
check "a word the list offers as one alternative is not banned alone" 0 "" "Did you consider caching the token here?"
check "both alternatives of note/consider are banned" 1 "It's important to consider" "It's important to consider the cache."
check "a bracketed choice matches any words" 1 "In today's [...] landscape" "In today's rapidly evolving landscape we ship."
check "a phrase from a bracket's list is not banned alone" 0 "" "A fast-paced migration."
check "a JSON array of strings is refused, not passed" 2 "must hold objects" '["It is important to consider this."]'
check "a host:port is not a file reference" 0 "" 'The pool talks to `db.owlpost.io:5432` now.'
check "ratios and times are not file references" 0 "" "Contrast is 16.9:1 at 10.30:15."
check "iOS and macOS are words, not identifiers" 0 "" "Does this work on iOS and macOS?"
check "a real file:line still needs its link" 1 'file reference "owl.py:12"' "See owl.py:12 for it."
check "a trailing parenthetical link is flagged" 1 "link in parentheses" "One broker for every task ([\`celeryconfig.py:15\`](https://github.com/acme/owl/blob/$SHA/celeryconfig.py#L15)), so it raises too."
check "a link on the words it backs is clean" 0 "" "One broker for [every task](https://github.com/acme/owl/blob/$SHA/celeryconfig.py#L15), so it raises too."
check "a plain parenthesis is not a link" 0 "" "The retry (three attempts) is fine."
check "a tilde estimate is flagged" 1 "approximate number \"~31 minutes\"" "Shrinks the window from ~31 minutes to a few ms."
check "a rounded number is clean" 0 "" "Shrinks the window from 30 minutes to a few ms."
check "a tilde inside a code span is not an estimate" 0 "" "Run \`cd ~/owl\` first."
# perl's alarm, not timeout: macOS has no GNU coreutils, so timeout is not there (exit 127)
out=$(echo "hi" | perl -e 'alarm shift; exec @ARGV' 5 bash "$GATE" --max-chars 2>&1); rc=$?
if [ "$rc" = 2 ] && grep -q 'needs a number' <<<"$out"; then echo "  PASS: --max-chars with no value is a usage error, not a hang"; pass=$((pass+1)); else echo "  FAIL: --max-chars with no value (rc $rc)"; fail=$((fail+1)); fi
out=$(printf -- '- The owl hoots twice at night.\n%.0s' $(seq 30) | bash "$GATE" --max-chars=2000 2>&1); rc=$?
if [ "$rc" = 0 ]; then echo "  PASS: --max-chars=N raises the limit"; pass=$((pass+1)); else echo "  FAIL: --max-chars=N (rc $rc: $out)"; fail=$((fail+1)); fi
check "per-comment numbering in JSON" 1 "comment 2: em dash" "[{\"body\":\"fine\"},{\"body\":\"hoot ${EM} hoot\"}]"

echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
