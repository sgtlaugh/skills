#!/usr/bin/env bash
# run.sh - regression eval for darkmoon's skeptic: runs cases.txt against fixture/ with headless Claude
#
# Usage: evals/darkmoon/run.sh [-n RUNS] [--score DIR]
#   -n RUNS      runs per case (default 1); one pass of every case costs about $2
#   --score DIR  re-score the outputs a previous run saved in DIR, without calling Claude
#
# Manual, not CI: it needs your Claude login, costs money, and verdicts vary run to run.
# Run it before and after any change to agents/darkmoon-skeptic.md or skills/darkmoon/.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
runs=1
score_dir=""
while [ $# -gt 0 ]; do
    case "$1" in
        -n) runs="${2:?-n needs a number}"; shift 2 ;;
        --score) score_dir="${2:?--score needs a directory}"; shift 2 ;;
        *) echo "usage: $0 [-n RUNS] [--score DIR]" >&2; exit 2 ;;
    esac
done
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

cases=$(grep -vE '^[[:space:]]*(#|$)' "$HERE/cases.txt")
names=$(printf '%s\n' "$cases" | awk -F' :: ' '!seen[$1]++ { print $1 }')

if [ -z "$score_dir" ]; then
    command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 2; }
    score_dir=$(mktemp -d "${TMPDIR:-/tmp}/darkmoon-eval.XXXXXX")
    repo="$score_dir/refundshop"
    cp -R "$HERE/fixture" "$repo"
    # The skeptic reads git history, so the fixture gets one commit with a message that hints at nothing.
    # Plumbing, so the user's own git hooks never run against it.
    (
        cd "$repo" && git init -q && git add -A &&
        commit=$(GIT_AUTHOR_NAME=eval GIT_AUTHOR_EMAIL=eval@example.invalid \
                 GIT_COMMITTER_NAME=eval GIT_COMMITTER_EMAIL=eval@example.invalid \
                 git commit-tree --no-gpg-sign -m "refundshop fixture" "$(git write-tree)") &&
        git update-ref HEAD "$commit"
    ) || { echo "could not build the fixture repo" >&2; exit 2; }

    echo "Running $(printf '%s\n' "$names" | wc -l | tr -d ' ') cases x $runs run(s) in parallel..."
    for name in $names; do
        prompt=$(printf '/darkmoon --claims\n%s\n' "$(printf '%s\n' "$cases" | awk -F' :: ' -v n="$name" '$1 == n { print ++i ". " $3 }')")
        for r in $(seq 1 "$runs"); do
            # Headless runs can't answer permission prompts; the skeptic's read-only hook still applies
            ( cd "$repo" && claude -p "$prompt" --dangerously-skip-permissions --output-format json \
                > "$score_dir/$name-$r.json" 2>"$score_dir/$name-$r.err" ) &
        done
    done
    wait
    echo "Outputs: $score_dir"
fi

pass=0 soft=0 fail=0
for name in $names; do
    expectations=$(printf '%s\n' "$cases" | awk -F' :: ' -v n="$name" '$1 == n { print $2 " :: " $3 }')
    for f in "$score_dir/$name"-*.json; do
        run=$(basename "$f" .json)
        [ -e "$f" ] || run="$name (no output)"
        result=$(jq -r '.result // empty' "$f" 2>/dev/null)
        i=0
        while IFS= read -r line; do
            i=$((i + 1))
            expected=${line%% :: *}
            claim=${line#* :: }
            preferred=${expected%%/*}
            case "$expected" in */*) softs="/${expected#*/}/" ;; *) softs="" ;; esac
            got=$(printf '%s\n' "$result" | awk -F'|' -v n="$i" '$2 ~ "^ *" n " *$" { print $5; exit }' \
                | grep -oE "Refuted|Upheld|Weak|Can't-determine" | head -1)
            if [ "$got" = "$preferred" ]; then
                status=PASS; pass=$((pass + 1))
            elif [ -n "$got" ] && [ -n "$softs" ] && [[ "$softs" == *"/$got/"* ]]; then
                status=SOFT; soft=$((soft + 1))
            else
                status=FAIL; fail=$((fail + 1))
            fi
            printf '  %-4s %-14s #%d %-16s expected %-24s %s\n' "$status" "$run" "$i" "${got:-<no verdict>}" "$expected" "${claim:0:60}"
        done <<< "$expectations"
    done
done

echo ""
echo "  --- $pass pass, $soft soft, $fail fail ---"
[ "$soft" -gt 0 ] && echo "  Soft = an acceptable but weaker verdict. More soft than the last baseline run means a regression."
[ "$fail" -eq 0 ]
