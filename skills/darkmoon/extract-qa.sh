#!/usr/bin/env bash
# extract-qa.sh - Extract the Q+A pair BEFORE the /darkmoon invocation.
# Usage: bash ~/.claude/skills/darkmoon/extract-qa.sh [transcript.jsonl] [--context N]
#        (no transcript: resolved from $CLAUDE_CODE_SESSION_ID)
#
# Single-pass jq classification + awk selection. Skips darkmoon execution blocks
# so previous darkmoon judgments don't pollute the target answer.

set -euo pipefail

TRANSCRIPT=""
CONTEXT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --context) CONTEXT="${2:?--context requires a number}"; shift 2 ;;
        -*) echo "Unknown flag: $1" >&2; exit 1 ;;
        *) TRANSCRIPT="$1"; shift ;;
    esac
done

# "Newest .jsonl" picks the wrong session when several are open; the session ID is exact.
if [ -z "$TRANSCRIPT" ]; then
    [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || { echo "ERROR: no transcript given and CLAUDE_CODE_SESSION_ID unset" >&2; exit 1; }
    matches=("$HOME"/.claude/projects/*/"$CLAUDE_CODE_SESSION_ID".jsonl)
    [ ${#matches[@]} -eq 1 ] || { echo "ERROR: ${#matches[@]} transcripts match session $CLAUDE_CODE_SESSION_ID" >&2; exit 1; }
    TRANSCRIPT="${matches[0]}"
fi

[ -f "$TRANSCRIPT" ] || { echo "ERROR: transcript not found: $TRANSCRIPT" >&2; exit 1; }

# Phase 1: Classify every JSONL line in a single jq pass.
# jq -R reads raw lines; fromjson parses each; try-catch handles malformed lines.
# Produces exactly one classification per input line (line-number-synchronized).
# For user-text, appends :LENGTH so awk can filter trivial questions.
classify() {
    jq -R -r '
      def has_real_text:
        (if (.message.content | type) == "array" then
           [.message.content[] |
            select(.type == "text") |
            .text // "" |
            select(test("^\\s*<(system-reminder|task-notification)>") | not)]
         elif (.message.content | type) == "string" then
           [.message.content | select(test("^\\s*<(system-reminder|task-notification)>") | not)]
         else [] end) |
        any(test("\\S"));

      def text_length:
        if (.message.content | type) == "array" then
          [.message.content[] | select(.type == "text") | (.text // "") | length] | add // 0
        elif (.message.content | type) == "string" then
          (.message.content | length)
        else 0 end;

      def not_human:
        .isMeta == true or .isCompactSummary == true or ((.origin.kind // "human") != "human");

      try (fromjson |
        if .type == "user" then
          # Peer-session messages, wakeup prompts and compact summaries look like long user text.
          # Demote them after the darkmoon anchor checks - the darkmoon skill text is itself isMeta.
          . as $e |
          (if (.message.content | type) == "string" then
            if (.message.content | contains("<command-message>darkmoon</command-message>")) then "darkmoon"
            elif (.message.content | contains("<command-message>")) then "user-text:\(text_length)"
            elif has_real_text then "user-text:\(text_length)"
            else "skip" end
          elif (.message.content | type) == "array" then
            if any(.message.content[]; .type == "tool_result") then "skip"
            elif any(.message.content[]; (.text // "") | contains("Base directory for this skill")) then
              # Match the skill path, not the word: sibling skills (solaire, aristarchus) mention darkmoon in their text
              if any(.message.content[]; (.text // "") | test("Base directory for this skill: \\S*/darkmoon(\\s|$)")) then "darkmoon"
              else "skill-injection" end
            elif any(.message.content[]; (.text // "") | contains("<command-message>darkmoon</command-message>")) then "darkmoon"
            elif any(.message.content[]; (.text // "") | contains("<command-message>")) then "user-text:\(text_length)"
            elif has_real_text then "user-text:\(text_length)"
            else "skip" end
          else "skip" end)
          | if startswith("user-text") and ($e | not_human) then "skip" else . end
        elif .type == "assistant" then
          if (.message.content | type) == "array" and
             any(.message.content[]; .type == "text" and ((.text // "") | length) > 0)
          then "assistant-text"
          else "skip" end
        else "skip" end
      ) catch "skip"
    ' "$TRANSCRIPT"
}

# Phase 2: Find target question + all answer lines using awk.
# Algorithm: find the last substantive user-text before the anchor (the question),
# then collect ALL assistant-text lines between that question and the anchor (the answer).
# This captures the full response chain - no answer-length filtering needed.
find_targets() {
    awk -v context="$CONTEXT" -v min_q_len=50 '
    {
        # Parse "user-text:11" into class + length; assistant-text has no length suffix
        idx = index($0, ":")
        if (idx > 0 && substr($0, 1, idx-1) == "user-text") {
            class[NR] = "user-text"
            len[NR] = substr($0, idx+1) + 0
        } else {
            class[NR] = $0
            len[NR] = 0
        }
        n = NR
    }
    END {
        anchor = 0
        for (i = n; i >= 1; i--)
            if (class[i] == "darkmoon") { anchor = i; break }
        if (!anchor) { print "error no-anchor"; exit }

        # Forward scan: mark lines inside darkmoon execution blocks.
        in_dm = 0
        for (i = 1; i < anchor; i++) {
            if (class[i] == "darkmoon") in_dm = 1
            if (class[i] == "user-text") in_dm = 0
            dm[i] = in_dm
        }

        # Find question: last substantive user-text before anchor.
        # Skip trivial approvals (<min_q_len chars): "Sure", "Commit", "Yes".
        q = 0
        for (i = anchor - 1; i >= 1; i--)
            if (class[i] == "user-text" && !dm[i] && len[i] >= min_q_len) { q = i; break }
        # Fallback: if no substantive question, take last user-text
        if (!q)
            for (i = anchor - 1; i >= 1; i--)
                if (class[i] == "user-text" && !dm[i]) { q = i; break }

        print "question " q

        # Keep follow-up user turns: a short one ("Is that race-safe?") may be the real question.
        start = (q > 0) ? q + 1 : 1
        for (i = start; i < anchor; i++) {
            if (dm[i]) continue
            if (class[i] == "assistant-text") print "answer " i
            else if (class[i] == "user-text") print "followup " i
        }

        # Context: prior exchanges before the target question
        search = (q > 0) ? q : anchor
        for (ci = 1; ci <= context && search > 1; ci++) {
            # Find prior substantive question
            pq = 0
            for (i = search - 1; i >= 1; i--)
                if (class[i] == "user-text" && !dm[i] && len[i] >= min_q_len) { pq = i; break }
            if (!pq) break
            # Find the first assistant-text after that question (the substantive response)
            pa = 0
            for (i = pq + 1; i < search; i++)
                if (class[i] == "assistant-text" && !dm[i]) { pa = i; break }
            if (!pa) break
            print "ctx " ci " " pq " " pa
            search = pq
        }
    }'
}

# Phase 3: Extract text content from a specific transcript line.
extract_text() {
    [ "${1:-0}" -eq 0 ] 2>/dev/null && { echo "(not found)"; return; }
    sed -n "${1}p" "$TRANSCRIPT" | jq -r '
        if (.message.content | type) == "array" then
            [.message.content[] | select(.type == "text") | .text] | join("\n")
        elif (.message.content | type) == "string" then
            .message.content
        else "(empty)" end
    ' 2>/dev/null || echo "(extraction failed)"
}

# --- Run ---
TARGETS=$(classify | find_targets)

if echo "$TARGETS" | grep -q "^error"; then
    echo "ERROR: no darkmoon invocation found in transcript" >&2
    echo "=== QUESTION ===" && echo "(darkmoon anchor not found)"
    echo "" && echo "=== ANSWER ===" && echo "(darkmoon anchor not found)"
    exit 1
fi

echo "Transcript: $TRANSCRIPT"
echo ""

# Extract question
Q_LINE=$(echo "$TARGETS" | grep "^question" | awk '{print $2}')
echo "=== QUESTION ==="
extract_text "$Q_LINE"
echo ""

# Extract ALL answer lines (full response chain)
echo "=== ANSWER ==="
echo "$TARGETS" | { grep -E "^(answer|followup)" || true; } | while read -r kind line; do
    if [ "$kind" = "followup" ]; then
        echo "[User follow-up]"
        extract_text "$line"
        echo "[Assistant]"
    else
        extract_text "$line"
    fi
done

# Extract context exchanges
echo "$TARGETS" | { grep "^ctx" || true; } | while IFS=' ' read -r _ num pq pa; do
    if [ "$num" = "1" ]; then
        echo ""
        echo "=== CONTEXT ($CONTEXT prior exchanges) ==="
    fi
    echo "--- Exchange -${num} ---"
    echo "[User]"
    extract_text "$pq"
    echo "[Assistant]"
    extract_text "$pa"
    echo ""
done
