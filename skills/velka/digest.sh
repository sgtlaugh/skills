#!/usr/bin/env bash
# velka digest - reduce ONE session JSONL to a compact mechanical record.
# Dumb extractor: facts only, no thresholds/judgment (that lives in the skill).
# Usage: digest.sh <session.jsonl>   # emits one JSON object to stdout
set -euo pipefail
f="$1"

# Slash-invoked skills/commands live as <command-name>/x</command-name> in user lines,
# a DISJOINT source from the Skill tool_use path - capture both, union in the analyzer.
slash=$(grep -oE '<command-name>/[^<]+</command-name>' "$f" 2>/dev/null \
  | sed -E 's|<command-name>/([^<]+)</command-name>|\1|' \
  | jq -R . | jq -cs . 2>/dev/null || true)
[ -z "${slash:-}" ] && slash='[]'

# Notes live mostly in bash comments; jq 1.6 does accept full-line # comments inside the program.
# Schema: id, project, start/end, assistant_msgs, user_str/arr, tokens{in,out,cache_read,cache_create},
# tools{}, files_edited{}, files_read{}, bash{total,git_commit,git_revert,test_run,grep},
# skill_tooluse[], slash[], first_prompt (first 2-3 substantive human messages joined with " | "),
# corrections[] ({ts, text} human turns that push back), hook_blocks{} (hook or "deny-rule" -> count).
# A line cut off by a crash mid-write is skipped instead of sinking the whole session.

jq -cR 'fromjson? // empty' "$f" | jq -s --argjson slash "$slash" '
  (map(select(type=="object"))) as $L
  | ($L | map(select(.type=="assistant" and .message.id != null))
    | group_by(.message.id) | map(max_by(.timestamp)) | sort_by(.timestamp)) as $a
  | ($a | map(.message.content[]? | select(.type=="tool_use"))) as $t
  | ($t | map(.input.command // empty)) as $cmds
  | ($t | map({key: (.id // ""), value: (.input.command // "")}) | from_entries) as $cmd_by_id
  | [ $L[] | select(.type=="user" and (.message.content|type=="array")) | .message.content[]
      | select(type=="object" and .type=="tool_result")
      | {cmd: ($cmd_by_id[.tool_use_id // ""] // ""),
         c: (.content | if type=="array" then map(.text // "") | join(" ") elif type=="string" then . else "" end)} ] as $results
  # Human turns only: skill text is isMeta, notifications carry a non-human origin.kind.
  # The real intent of a slash invocation is its <command-args>, extracted before the wrapper filter.
  # Only known harness wrapper tags are dropped - a typed prompt may start with "<" or mention "caveman".
  | [ $L[] | select(.type=="user" and .isMeta != true and .isCompactSummary != true
                   and (.origin.kind // "human") == "human")
      | {ts: .timestamp, text: (
          (if (.message.content|type=="string") then .message.content
           elif (.message.content|type=="array") then ([.message.content[]?|select(.type=="text")|.text]|join(" "))
           else "" end)
          | if test("<command-args>") then (capture("<command-args>(?<a>[\\s\\S]*?)</command-args>").a // "") else . end
          | gsub("\\s+";" ") | gsub("^ +| +$";""))}
      | select((.text|length) > 15
          and (.text|test("^<(command-[a-z]+|local-command-[a-z]+|system-reminder|task-notification|bash-[a-z]+|user-prompt-submit-hook)>")|not)
          and (.text|test("^Base directory for this skill|^\\[Request interrupted")|not)
          and (.text|test("tool_use_error")|not)) ] as $human
  | {
      id:      (($L | map(.sessionId) | map(select(.)) | first) // "unknown"),
      project: (($L | map(.cwd)       | map(select(.)) | first) // "unknown"),
      start:   ($a | first | .timestamp?),
      end:     ($a | last  | .timestamp?),
      assistant_msgs: ($a | length),
      user_str: ($L | map(select(.type=="user" and (.message.content | type=="string"))) | length),
      user_arr: ($L | map(select(.type=="user" and (.message.content | type=="array")))  | length),
      tokens: {
        in:           (($a | map(.message.usage.input_tokens          // 0) | add) // 0),
        out:          (($a | map(.message.usage.output_tokens         // 0) | add) // 0),
        cache_read:   (($a | map(.message.usage.cache_read_input_tokens     // 0) | add) // 0),
        cache_create: (($a | map(.message.usage.cache_creation_input_tokens // 0) | add) // 0)
      },
      tools: ($t | group_by(.name) | map({key: .[0].name, value: length}) | from_entries),
      files_edited: ($t | map(select(.name=="Edit" or .name=="Write") | .input.file_path // empty)
                       | group_by(.) | map({key: .[0], value: length}) | from_entries),
      files_read:   ($t | map(select(.name=="Read") | .input.file_path // empty)
                       | group_by(.) | map({key: .[0], value: length}) | from_entries),
      bash: {
        total:      ($cmds | length),
        git_commit: ($cmds | map(select(test("git +commit")))                                | length),
        git_revert: ($cmds | map(select(test("git +(reset|checkout|restore|stash|revert)"))) | length),
        test_run:   ($cmds | map(select(test("pytest|jest|vitest|unittest|rspec|go +test|cargo +test|(npm|pnpm|yarn|bun|deno) +(run +)?test|make +test|(mvn|gradlew?) .*test|\\btox\\b|tests?/run"))) | length),
        grep:       ($cmds | map(select(test("(^| )(grep|rg|ag) ")))                          | length)
      },
      skill_tooluse: ($t | map(select(.name=="Skill") | .input.skill // empty)),
      slash: $slash,
      first_prompt: ($human | map(.text) | .[0:3] | map(.[0:200]) | join(" | ") | .[0:500]),
      # Pushback is the raw material for CLAUDE.md proposals; velka --propose judges which ones recur
      corrections: ($human
          | map(select(.text | test("\\b(don.?t|do not|never|stop|instead|wrong|i said|i told you|i asked|not what i|why did you|you should|shouldn.?t|please (always|stop))\\b"; "i")))
          | map({ts, text: .text[0:300]}) | .[0:20]),
      # Real blocks only: a PreToolUse error is written by the harness, never by a test feeding a hook JSON.
      # commit-msg runs inside git, so its block counts only when the tool call actually ran git commit.
      # A commit in a mktemp repo is a hook test, not a real attempt.
      hook_blocks: ($results
          | map(if (.c | test("^PreToolUse:[A-Za-z|]+ hook error: \\[")) then
                  (.c | capture("^PreToolUse:[A-Za-z|]+ hook error: \\[[^\\]]*?(?<h>[A-Za-z0-9_.-]+)\\]").h // "unknown-hook")
                elif (.c | test("(^|\\n)\\S* ?commit-msg BLOCKED")) and (.cmd | test("(^|[;&|(] *)git( +-[cC] +[^ ]+)* +commit\\b")) and (.cmd | test("mktemp") | not) then "commit-msg"
                elif (.c | test("^Permission to use .* has been denied")) then "deny-rule"
                else empty end)
          | group_by(.) | map({key: .[0], value: length}) | from_entries)
    }
'
