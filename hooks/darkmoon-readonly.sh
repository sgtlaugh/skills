#!/usr/bin/env bash
# darkmoon-readonly.sh - PreToolUse hook for the darkmoon-skeptic agent: allow read-only Bash only.
# Exit 2 blocks the call; stderr is shown to the agent as the reason.
# An allowlist tripwire, not a sandbox - writes hidden inside quoted jq programs, sed w/e commands and
# uniq's output-file arg are not caught; nor are awk writes or commands it runs (print > or | to a
# string, getline) when they don't take the plain forms blocked below. A quoted flag counts as a flag, so a
# pattern that quotes " -i " trips the sed check: a false alarm, never a way through.
# Upgrade path: run the skeptic in a read-only container.
# DARKMOON_ALLOW_SCRIPT=<absolute path>: the one script a caller vouches for as read-only (a credentialed lookup
# tool that checks its own arguments) may run as `bash <path> ...`; nothing else under bash or sh does.

set -uo pipefail

block() { echo "Blocked by darkmoon read-only hook: $1" >&2; exit 2; }
# Fail closed: input that can't be read (no jq, not JSON) is not a command that can be let through
cmd=$(jq -r '.tool_input.command // empty') || block "can't read the tool input"
[ -n "$cmd" ] || exit 0
# long <option> <min-length>: an argument of this command is the option or an unambiguous prefix of it (GNU
# tools take --in for --in-place), with or without =value
long() { local a n; for a in "${words[@]:1}"; do n="${a%%=*}"; [[ "$n" == --* ]] && [ ${#n} -ge "$2" ] && [[ "$1" == "$n"* ]] && return 0; done; return 1; }

case "$cmd" in *'$('*|*'`'*) block "command substitution" ;; esac
# ANSI-C quoting ($'...') treats \' as a quote inside a quote; read differently from bash, it could hide a command
case "$cmd" in *"\$'"*) block "\$'...' quoting" ;; esac
case "$cmd" in *'system('*) block "awk system()" ;; esac
# awk's own redirects and pipes live inside its quoted program, where the redirect check below can't see them
if grep -qE '(^|[^[:alnum:]_])awk([[:space:]]|$)' <<<"$cmd" && grep -qE '[>|][[:space:]]*"|getline' <<<"$cmd"; then
    block "awk writing to a file or running a command"
fi

# One left-to-right read of the command the way bash reads it, so data (fixture JSON, grep patterns like "a|b")
# can't be mistaken for commands or redirects, and quotes can't hide a command:
#   - quoted text stays as words (a quoted "touch" is still touch), with the characters that would end a command
#     or redirect (| ; & < > ( ) ` # $ newline) turned into _;
#   - a backslash escapes the next character outside single quotes (a ' inside "..." is a plain character);
#   - an unquoted # at the start of a word comments out the rest of the line;
#   - a heredoc's body (<<EOF, <<-'EOF', a delimiter of any word characters) is dropped; <<< is a here-string.
stripped=$(printf '%s' "$cmd" | awk '
    function meta(ch) { return (ch ~ /[|;&<>()`#$\n]/) ? "_" : ch }
    { text = text (NR > 1 ? "\n" : "") $0 }
    END {
        n = length(text); i = 1; q = ""; out = ""; hn = 0; hdone = 0
        while (i <= n) {
            c = substr(text, i, 1)
            if (q == "\x27") { if (c == "\x27") q = ""; else out = out meta(c); i++; continue }
            if (c == "\\") { out = out "_"; i += 2; continue }
            if (q == "\"") { if (c == "\"") q = ""; else out = out meta(c); i++; continue }
            if (c == "\x27" || c == "\"") { q = c; i++; continue }
            if (c == "#" && (i == 1 || substr(text, i - 1, 1) ~ /[ \t\n;|&(]/)) { while (i <= n && substr(text, i, 1) != "\n") i++; continue }
            if (substr(text, i, 3) == "<<<") { out = out "<<<"; i += 3; continue }
            if (substr(text, i, 2) == "<<") {
                j = i + 2; strip = 0
                if (substr(text, j, 1) == "-") { strip = 1; j++ }
                while (substr(text, j, 1) ~ /[ \t]/) j++
                d = ""; qd = substr(text, j, 1)
                if (qd == "\x27" || qd == "\"") { j++; while (j <= n && substr(text, j, 1) != qd) { d = d substr(text, j, 1); j++ } j++ }
                else while (j <= n && substr(text, j, 1) ~ /[A-Za-z0-9_.-]/) { d = d substr(text, j, 1); j++ }
                if (d != "") { hn++; hd[hn] = d; hs[hn] = strip }
                out = out "<<"; i = j; continue
            }
            if (c == "\n" && hn > hdone) {
                out = out "\n"; i++
                for (k = hdone + 1; k <= hn; k++) {
                    while (i <= n) {
                        e = index(substr(text, i), "\n"); line = (e ? substr(text, i, e - 1) : substr(text, i)); i += (e ? e : n)
                        if (hs[k]) sub(/^\t+/, "", line)
                        if (line == hd[k]) break
                    }
                }
                hdone = hn; continue
            }
            out = out c; i++
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
        grep|egrep|jq|cat|head|tail|wc|ls|echo|printf|uniq|cut|tr|diff|stat|basename|dirname|realpath|readlink|pwd|cd|test|'['|true|false|date|nl|column) ;;
        # A program from a file escapes every check on the command line
        awk) [[ "$rest" =~ [[:space:]]-[a-zA-Z]*f ]] && block "awk -f runs a program file"; long "--file" 4 && block "awk --file" ;;
        rg) [[ "$rest" =~ [[:space:]]--pre[=[:space:]] ]] && block "rg --pre runs a command" ;;
        sort) [[ "$rest" =~ [[:space:]]-[a-zA-Z]*o ]] && block "sort output file"
            long "--output" 5 && block "sort output file"; long "--compress-program" 4 && block "sort compress program" ;;
        sed) [[ "$rest" =~ [[:space:]]-[a-zA-Z]*i ]] && block "sed in-place edit"; long "--in-place" 4 && block "sed in-place edit"
            [[ "$rest" =~ [[:space:]]-[a-zA-Z]*f ]] && block "sed -f runs a script file (its e command runs programs)"; long "--file" 4 && block "sed --file" ;;
        file) [[ "$rest" =~ [[:space:]]-[a-zA-Z]*C ]] && block "file -C writes a compiled magic file"; long "--compile" 5 && block "file --compile writes a file" ;;
        mktemp)
            set -- "${words[@]:1}"
            while [ $# -gt 0 ]; do
                case "$1" in
                    -p|--tmpdir) [[ "${2:-}" == /tmp* && "${2:-}" != *..* ]] || block "mktemp outside /tmp"; shift 2 ;;
                    --tmpdir=*) [[ "${1#*=}" == /tmp* && "$1" != *..* ]] || block "mktemp outside /tmp"; shift ;;
                    -*) shift ;;
                    *) [[ ( "$1" != */* || "$1" == /tmp/* ) && "$1" != *..* ]] || block "mktemp outside /tmp"; shift ;;
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
            # The same file by another absolute path (a symlinked install dir) is the same script
            [ -n "${DARKMOON_ALLOW_SCRIPT:-}" ] && [[ "$DARKMOON_ALLOW_SCRIPT" == /* ]] && [[ "${words[1]:-}" == /* ]] \
                && { [ "${words[1]}" = "$DARKMOON_ALLOW_SCRIPT" ] \
                    || { a=$(realpath -e -- "$DARKMOON_ALLOW_SCRIPT" 2>/dev/null) && [ "$(realpath -e -- "${words[1]}" 2>/dev/null)" = "$a" ]; }; } \
                || block "'$w' is not in the read-only allowlist" ;;
        *) block "'$w' is not in the read-only allowlist" ;;
    esac
done < <(printf '%s\n' "$stripped" | awk '{ gsub(/\|\||&&|[|;&]/, "\n"); print }')

exit 0
