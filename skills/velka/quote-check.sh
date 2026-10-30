#!/usr/bin/env bash
# velka quote-check - prove each quoted user message exists verbatim in its session's human turns.
# Usage: quote-check.sh [file]   # JSON array of {"session": "<id or 8+ char prefix>", "quote": "..."}; stdin without a file
# Prints PASS/FAIL per quote; exit 0 only when every quote passed. Whitespace runs compare as one space.
set -uo pipefail
ROOT="${VELKA_PROJECTS:-$HOME/.claude/projects}"
input=$(cat "${1:-/dev/stdin}") || exit 2
jq -e 'type == "array"' <<<"$input" >/dev/null 2>&1 || { echo "quote-check: input must be a JSON array of {session, quote}" >&2; exit 2; }

bad=0
# Records split by NUL and fields by \x1f, not @tsv: @tsv escapes a backslash as \\, which read keeps
while IFS=$'\x1f' read -r -d '' sid quote; do
    if [ ${#sid} -lt 8 ] || [ ${#quote} -lt 10 ]; then
        echo "FAIL $sid: session id needs 8+ characters and the quote 10+"; bad=1; continue
    fi
    files=$(find "$ROOT" -maxdepth 2 -name "$sid*.jsonl" -type f)
    count=$(printf '%s' "$files" | grep -c .)
    if [ "$count" -ne 1 ]; then
        echo "FAIL $sid: $count transcripts match \"$quote\""; bad=1; continue
    fi
    # Human turns only, the same way digest.sh reads them: skill text and notifications can't vouch for a quote
    if jq -cR 'fromjson? // empty' "$files" | jq -e -s --arg q "$quote" '
        ($q | gsub("\\s+"; " ") | gsub("^ +| +$"; "")) as $nq
        | any(.[] | select(type == "object" and .type == "user" and .isMeta != true and .isCompactSummary != true
                           and (.origin.kind // "human") == "human")
              | (if (.message.content | type) == "string" then .message.content
                 elif (.message.content | type) == "array" then ([.message.content[]? | select(.type == "text") | .text] | join(" "))
                 else "" end)
              | gsub("\\s+"; " ");
              contains($nq))' >/dev/null; then
        echo "PASS $sid: \"$quote\""
    else
        echo "FAIL $sid: not in any human turn: \"$quote\""; bad=1
    fi
done < <(jq -j '.[] | (.session // "" | gsub("[\u001f\u0000]"; "")) + "\u001f" + (.quote // "" | gsub("[\u001f\u0000]"; " ")) + "\u0000"' <<<"$input")
exit $bad
