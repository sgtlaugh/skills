#!/usr/bin/env bash
# darkmoon-readonly.sh - PreToolUse hook for the darkmoon-skeptic agent: allow read-only Bash only.
# Exit 2 blocks the call; stderr is shown to the agent as the reason.
# An allowlist tripwire, not a sandbox - writes hidden inside quoted jq programs, sed w/e commands and
# uniq's output-file arg are not caught; nor are awk writes or commands it runs (print > or | to a
# string, getline) when they don't take the plain forms blocked below.
# Upgrade path: run the skeptic in a read-only container.
# DARKMOON_ALLOW_SCRIPT=<absolute path>: the one script a caller vouches for as read-only (a credentialed lookup
# tool that checks its own arguments) may run as `bash <path> ...`; nothing else under bash or sh does.

set -uo pipefail

cmd=$(jq -r '.tool_input.command // empty')
[ -n "$cmd" ] || exit 0

block() { echo "Blocked by darkmoon read-only hook: $1" >&2; exit 2; }
# long <option> <min-length>: an argument of this command is the option or an unambiguous prefix of it (GNU
# tools take --in for --in-place), with or without =value
long() { local a n; for a in "${words[@]:1}"; do n="${a%%=*}"; [[ "$n" == --* ]] && [ ${#n} -ge "$2" ] && [[ "$1" == "$n"* ]] && return 0; done; return 1; }

case "$cmd" in *'$('*|*'`'*) block "command substitution" ;; esac
case "$cmd" in *'system('*) block "awk system()" ;; esac
# awk's own redirects and pipes live inside its quoted program, where the redirect check below can't see them
if grep -qE '(^|[^[:alnum:]_])awk([[:space:]]|$)' <<<"$cmd" && grep -qE '[>|][[:space:]]*"|getline' <<<"$cmd"; then
    block "awk writing to a file or running a command"
fi

# Drop heredoc bodies, then quoted strings, so data (fixture JSON, grep patterns like "a|b") can't be
# mistaken for commands or redirects. A here-string (<<<) is not a heredoc, and a delimiter is the whole
# word (E1, not E). Quotes are read the way the shell reads them: a backslash escapes outside single
# quotes, and a ' inside "..." is a plain character - a naive pairing would swallow real commands.
stripped=$(printf '%s\n' "$cmd" | awk '
    delim != "" { line = $0; sub(/^\t+/, "", line); if (line == delim) delim = ""; next }
    {
        probe = $0; gsub(/<<</, "", probe)
        if (match(probe, /<<-?[[:space:]]*["'\'']?[A-Za-z0-9_-]+/)) {
            d = substr(probe, RSTART, RLENGTH); gsub(/<<-?[[:space:]]*["'\'']?/, "", d); delim = d
        }
        print
    }' | awk '
    { text = text (NR > 1 ? "\n" : "") $0 }
    END {
        q = ""; out = ""
        for (i = 1; i <= length(text); i++) {
            c = substr(text, i, 1)
            if (q == "\x27") { if (c == "\x27") q = ""; continue }
            if (c == "\\") { i++; if (q == "") out = out "_"; continue }
            if (q == "\"") { if (c == "\"") q = ""; continue }
            if (c == "\x27" || c == "\"") { q = c; continue }
            out = out c
        }
        print out
    }' | sed -E 's/[0-9]*>&([0-9]+|-)([[:space:]|;&]|$)/\2/g')

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
        grep|egrep|jq|cat|head|tail|wc|ls|echo|printf|uniq|cut|tr|diff|stat|basename|dirname|realpath|readlink|pwd|cd|test|'['|true|false|date|nl|column|awk) ;;
        rg) [[ "$rest" =~ [[:space:]]--pre[=[:space:]] ]] && block "rg --pre runs a command" ;;
        sort) [[ "$rest" =~ [[:space:]]-[a-zA-Z]*o ]] && block "sort output file"
            long "--output" 5 && block "sort output file"; long "--compress-program" 4 && block "sort compress program" ;;
        sed) [[ "$rest" =~ [[:space:]]-[a-zA-Z]*i ]] && block "sed in-place edit"; long "--in-place" 4 && block "sed in-place edit" ;;
        file) [[ "$rest" =~ [[:space:]]-[a-zA-Z]*C ]] && block "file -C writes a compiled magic file"; long "--compile" 5 && block "file --compile writes a file" ;;
        mktemp)
            set -- "${words[@]:1}"
            while [ $# -gt 0 ]; do
                case "$1" in
                    -p|--tmpdir) [[ "${2:-}" == /tmp* ]] || block "mktemp outside /tmp"; shift 2 ;;
                    --tmpdir=*) [[ "${1#*=}" == /tmp* ]] || block "mktemp outside /tmp"; shift ;;
                    -*) shift ;;
                    *) [[ "$1" != */* || "$1" == /tmp/* ]] || block "mktemp outside /tmp"; shift ;;
                esac
            done ;;
        find) [[ "$rest" =~ [[:space:]]-(delete|exec|execdir|ok|okdir|fprint|fprint0|fprintf|fls)[[:space:]] ]] && block "find -${BASH_REMATCH[1]}" ;;
        git)
            set -- "${words[@]:1}"
            while [ $# -gt 0 ]; do
                case "$1" in -C) [ $# -ge 2 ] || block "git -C without a path"; shift 2 ;; --no-pager|-P) shift ;; *) break ;; esac
            done
            case "${1:-}" in log|show|diff|blame|status|grep|rev-parse|ls-files|cat-file|shortlog|describe) ;; *) block "git ${1:-} (read subcommands only)" ;; esac
            # git takes bundled short flags (-iO<cmd>) and any unambiguous prefix of a long option (--outp=,
            # --open-f=), so each argument is checked for both, not matched against the full spelling
            for a in "${@:2}"; do
                case "$a" in
                    --*) n="${a%%=*}"
                        [ ${#n} -ge 4 ] && [[ "--output" == "$n"* ]] && block "git --output writes a file"
                        [ "$1" = grep ] && [ ${#n} -ge 4 ] && [[ "--open-files-in-pager" == "$n"* ]] && block "git grep -O runs a command" ;;
                    -?*) [ "$1" = grep ] && [[ "$a" == *O* ]] && block "git grep -O runs a command" ;;
                esac
            done ;;
        gh)
            case "${words[1]:-} ${words[2]:-}" in
                "pr view"|"pr diff"|"pr checks"|"issue view"|"repo view"|search\ *) ;;
                # Short flags take attached values (-XPOST, -fbody=x), long ones take =value
                # Bundled short flags count too: -iXPOST and -if title=x both POST
                api\ *) [[ "$rest" =~ [[:space:]](-[a-zA-Z]*[XfF]|--method[=[:space:]]|--field[=[:space:]]|--raw-field[=[:space:]]|--input[=[:space:]]) ]] && block "gh api write flags" ;;
                *) block "gh ${words[1]:-} ${words[2]:-} (read subcommands only)" ;;
            esac ;;
        bash|sh)
            [ -n "${DARKMOON_ALLOW_SCRIPT:-}" ] && [[ "$DARKMOON_ALLOW_SCRIPT" == /* ]] && [ "${words[1]:-}" = "$DARKMOON_ALLOW_SCRIPT" ] \
                || block "'$w' is not in the read-only allowlist" ;;
        *) block "'$w' is not in the read-only allowlist" ;;
    esac
done < <(printf '%s\n' "$stripped" | awk '{ gsub(/\|\||&&|[|;&]/, "\n"); print }')

exit 0
