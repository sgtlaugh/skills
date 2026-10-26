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
# tool_seq[] (tool names), cmd_seq[] (normalized bash command heads).

jq -s --argjson slash "$slash" '
  (map(select(type=="object"))) as $L
  | ($L | map(select(.type=="assistant" and .message.id != null))
    | group_by(.message.id) | map(max_by(.timestamp)) | sort_by(.timestamp)) as $a
  | ($a | map(.message.content[]? | select(.type=="tool_use"))) as $t
  | ($t | map(.input.command // empty)) as $cmds
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
        test_run:   ($cmds | map(select(test("pytest|jest|vitest|go +test|cargo +test|(npm|pnpm|yarn) +(run +)?test"))) | length),
        grep:       ($cmds | map(select(test("(^| )(grep|rg|ag) ")))                          | length)
      },
      skill_tooluse: ($t | map(select(.name=="Skill") | .input.skill // empty)),
      slash: $slash,
      # Human intent only: skill text is isMeta, notifications carry a non-human origin.kind.
      # The real intent of a slash invocation is its <command-args>, extracted before the wrapper filter.
      # Only known harness wrapper tags are dropped - a typed prompt may start with "<" or mention "caveman".
      first_prompt: ([ $L[] | select(.type=="user" and .isMeta != true and .isCompactSummary != true
                                     and (.origin.kind // "human") == "human")
          | (if (.message.content|type=="string") then .message.content
             elif (.message.content|type=="array") then ([.message.content[]?|select(.type=="text")|.text]|join(" "))
             else "" end)
          | if test("<command-args>") then (capture("<command-args>(?<a>[\\s\\S]*?)</command-args>").a // "") else . end ]
          | map(gsub("\\s+";" ") | gsub("^ +| +$";""))
          | map(select(length>15
                and (test("^<(command-[a-z]+|local-command-[a-z]+|system-reminder|task-notification|bash-[a-z]+|user-prompt-submit-hook)>")|not)
                and (test("^Base directory for this skill|^\\[Request interrupted")|not)
                and (test("tool_use_error")|not)))
          | .[0:3] | map(.[0:200]) | join(" | ") | .[0:500]),
      tool_seq: ($t | map(.name) | .[0:400]),
      cmd_seq: ([ $t[] | select(.name=="Bash") | .input.command // empty
                  | [splits("\\||&&|;|\n")] | .[]
                  | gsub("^\\s+|\\s+$";"") | select(length>0)
                  | (. / " " | map(select(length>0))) as $toks
                  | ($toks[0] // "" | sub(".*/";"")) as $prog
                  | if ($prog|test("^(git|gh|kubectl|aws|wrangler|docker|terraform|npm|pnpm|yarn|cargo|go|jq|psql|mysql)$"))
                       and (($toks[1] // "")|test("^[a-z]"))
                    then "\($prog) \($toks[1])" else $prog end
                  | select(test("^[a-z][a-z0-9-]+( [a-z][a-z0-9-]+)?$")
                      and (test("^(for|do|done|then|fi|else|elif|while|case|esac|in|function|source|eval|local|export|unset|return|echo|printf|true|false|cd|set|read|sleep|time|touch|cat|ls|mkdir|rmdir|cp|mv|wc|head|tail|tr|cut|sort|uniq|tee|xargs|where|stats|fields|dedup|rename|search|by|as|span|if|def|const|import|from|int|cout|cin|let|var|func|fn|class|struct|enum|type|interface|impl|pub|mod|use|std|public|private|protected|void|static|async|await|yield|lambda|pass|raise|try|except|finally|with|null|none|new|delete|this|self|throw|catch|switch|break|continue|print|println|require|module|exports|default|include|define|namespace|template|command|float|double|char|bool|string|long|short)$")|not)) ] | .[0:600])
    }
' "$f"
