#!/usr/bin/env bash
# darkmoon-readonly.sh - PreToolUse hook for the darkmoon-skeptic agent: allow read-only Bash only.
# Exit 2 blocks the call; stderr is shown to the agent as the reason.
# ponytail: allowlist tripwire, not a sandbox - writes hidden inside quoted awk/jq programs,
# sed w/e commands, uniq's output-file arg, and mktemp -p are not caught.
# Upgrade path: run the skeptic in a read-only container.

set -uo pipefail

cmd=$(jq -r '.tool_input.command // empty')
[ -n "$cmd" ] || exit 0

block() { echo "Blocked by darkmoon read-only hook: $1" >&2; exit 2; }

case "$cmd" in *'$('*|*'`'*) block "command substitution" ;; esac
case "$cmd" in *'system('*) block "awk system()" ;; esac

# Drop heredoc bodies, then quoted strings, so data (fixture JSON, grep patterns like "a|b")
# can't be mistaken for commands or redirects.
stripped=$(printf '%s\n' "$cmd" | awk '
    delim != "" { if ($0 ~ "^[[:space:]]*" delim "[[:space:]]*$") delim = ""; next }
    {
        if (match($0, /<<-?[[:space:]]*["'\'']?[A-Za-z_]+/)) {
            d = substr($0, RSTART, RLENGTH); gsub(/<<-?[[:space:]]*["'\'']?/, "", d); delim = d
        }
        print
    }' | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g; s/[0-9]*>&[0-9]//g")

# Checked after stripping: quoted <( is a grep pattern, not a process substitution.
case "$stripped" in *'<('*|*'>('*) block "process substitution" ;; esac

# Writes are allowed only into /tmp (throwaway fixtures) or /dev/null.
while read -r target; do
    target="${target#&}"; target="${target#>}"; target="${target#>}"; target="${target#"${target%%[![:space:]]*}"}"
    case "$target" in *..*) block "'..' in redirect target '$target'" ;; /tmp/*|/dev/null) ;; *) block "redirect to '$target' (only /tmp/ or /dev/null)" ;; esac
done < <(printf '%s\n' "$stripped" | grep -oE '&?>>?[[:space:]]*[^[:space:]|;&<>]*')

while read -r seg; do
    set -f; read -ra words <<< "$seg"; set +f
    # GIT_EXTERNAL_DIFF=, PAGER=, GIT_PAGER= etc. make an allowlisted command run arbitrary programs
    while [ ${#words[@]} -gt 0 ] && [[ "${words[0]}" == *=* ]]; do
        [[ "${words[0]}" =~ ^(LC_[A-Z]+|LANG|TZ)= ]] || block "env assignment '${words[0]}' (only LC_*, LANG, TZ)"
        words=("${words[@]:1}")
    done
    [ ${#words[@]} -gt 0 ] || continue
    w="${words[0]}"; rest=" ${words[*]:1} "
    case "$w" in
        grep|egrep|jq|cat|head|tail|wc|ls|echo|printf|uniq|cut|tr|diff|stat|file|basename|dirname|realpath|readlink|pwd|cd|test|'['|true|false|date|mktemp|nl|column|awk) ;;
        rg) [[ "$rest" =~ [[:space:]]--pre[=[:space:]] ]] && block "rg --pre runs a command" ;;
        sort) [[ "$rest" =~ [[:space:]](-[a-zA-Z]*o|--output|--compress-program) ]] && block "sort output file or compress program" ;;
        sed) [[ "$rest" =~ [[:space:]](-[a-zA-Z]*i|--in-place) ]] && block "sed in-place edit" ;;
        find) [[ "$rest" =~ [[:space:]]-(delete|exec|execdir|ok|okdir|fprint|fprint0|fprintf|fls)[[:space:]] ]] && block "find -${BASH_REMATCH[1]}" ;;
        git)
            set -- "${words[@]:1}"
            while [ $# -gt 0 ]; do
                case "$1" in -C) shift 2 ;; --no-pager|-P) shift ;; *) break ;; esac
            done
            case "${1:-}" in log|show|diff|blame|status|grep|rev-parse|ls-files|cat-file|shortlog|describe) ;; *) block "git ${1:-} (read subcommands only)" ;; esac
            [[ " $* " =~ [[:space:]]--output ]] && block "git --output writes a file"
            [ "$1" = grep ] && [[ " $* " =~ [[:space:]](-O|--open-files-in-pager) ]] && block "git grep -O runs a command" ;;
        gh)
            case "${words[1]:-} ${words[2]:-}" in
                "pr view"|"pr diff"|"pr checks"|"issue view"|"repo view"|search\ *) ;;
                # Short flags take attached values (-XPOST, -fbody=x), long ones take =value
                api\ *) [[ "$rest" =~ [[:space:]](-X|-f|-F|--method[=[:space:]]|--field[=[:space:]]|--raw-field[=[:space:]]|--input[=[:space:]]) ]] && block "gh api write flags" ;;
                *) block "gh ${words[1]:-} ${words[2]:-} (read subcommands only)" ;;
            esac ;;
        *) block "'$w' is not in the read-only allowlist" ;;
    esac
done < <(printf '%s\n' "$stripped" | awk '{ gsub(/\|\||&&|[|;&]/, "\n"); print }')

exit 0
