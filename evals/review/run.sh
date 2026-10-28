#!/usr/bin/env bash
# run.sh - regression eval for the review skills: /occam and aristarchus's Saboteur lens
#
# Usage: evals/review/run.sh [-n RUNS] [--target occam|saboteur] [--case NAME] [--score DIR]
#   -n RUNS      runs per case and target (default 1); one pass of everything costs about $5
#   --target     only one target (default both)
#   --case       only one case
#   --score DIR  re-score the outputs a previous run saved in DIR, without calling Claude
#
# Each case is cases/<name>.diff (applied to fixture/ as uncommitted work) and cases/<name>.expect:
#   goal :: <one line>                    passed to /occam
#   targets :: occam saboteur             which targets run it
#   find :: <label> :: <regex>            the review must match (ERE, case-insensitive)
#   avoid :: <label> :: <regex>           the review must not match: a false positive
#   max :: <N> :: <label> :: <regex>      at most N output lines may match: one defect reported N times
# The Saboteur brief is read from skills/aristarchus/SKILL.md at run time, so the eval tracks edits to it.
#
# Manual, not CI: it needs your Claude login, costs money, and reviews vary run to run.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$HERE/../../skills/aristarchus/SKILL.md"
runs=1 only_target="" only_case="" score_dir=""
while [ $# -gt 0 ]; do
    case "$1" in
        -n) runs="${2:?-n needs a number}"; shift 2 ;;
        --target) only_target="${2:?--target needs occam or saboteur}"; shift 2 ;;
        --case) only_case="${2:?--case needs a name}"; shift 2 ;;
        --score) score_dir="${2:?--score needs a directory}"; shift 2 ;;
        *) echo "usage: $0 [-n RUNS] [--target occam|saboteur] [--case NAME] [--score DIR]" >&2; exit 2 ;;
    esac
done
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

field() { grep -E "^$2 :: " "$HERE/cases/$1.expect" | head -1 | sed "s/^$2 :: //"; }
cases=$(cd "$HERE/cases" && ls *.expect | sed 's/\.expect$//')
[ -n "$only_case" ] && cases="$only_case"

# The debiased preamble and the Saboteur brief, verbatim from the skill
saboteur_brief() {
    awk '/^\*Debiased lenses \(Saboteur, Operator, Security\):\*$/ { on = 1; next }
         on && /^> / { print; next }
         on && /^>$/ { print; next }
         on && NF && !/^>/ { on = 0 }' "$SKILL"
    grep -E '^1\. \*\*Saboteur\*\*' "$SKILL"
}

if [ -z "$score_dir" ]; then
    command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 2; }
    brief=$(saboteur_brief)
    { grep -q "^> \*\"You are a read-only" <<<"$brief" && grep -q "^1\. \*\*Saboteur" <<<"$brief"; } || { echo "could not extract the Saboteur brief from $SKILL" >&2; exit 2; }
    score_dir=$(mktemp -d "${TMPDIR:-/tmp}/review-eval.XXXXXX")
    jobs=0
    for name in $cases; do
        for target in $(field "$name" targets); do
            [ -n "$only_target" ] && [ "$target" != "$only_target" ] && continue
            for r in $(seq 1 "$runs"); do
                repo="$score_dir/repos/$name-$target-$r/owlpost"
                mkdir -p "$(dirname "$repo")" && cp -R "$HERE/fixture" "$repo"
                # One base commit through plumbing, so the user's git hooks never run; the case stays uncommitted
                (
                    cd "$repo" && git init -q && git add -A &&
                    commit=$(GIT_AUTHOR_NAME=eval GIT_AUTHOR_EMAIL=eval@example.invalid \
                             GIT_COMMITTER_NAME=eval GIT_COMMITTER_EMAIL=eval@example.invalid \
                             git commit-tree --no-gpg-sign -m "owlpost" "$(git write-tree)") &&
                    git update-ref HEAD "$commit" && git apply "$HERE/cases/$name.diff"
                ) || { echo "could not build the repo for $name" >&2; exit 2; }
                if [ "$target" = occam ]; then
                    prompt="/occam $(field "$name" goal)"
                else
                    prompt="$brief

The change under review is the uncommitted work in this repository: run \`git diff HEAD\` to see it. Report each finding with file:line."
                fi
                ( cd "$repo" && claude -p "$prompt" --dangerously-skip-permissions --output-format json \
                    > "$score_dir/$name-$target-$r.json" 2>"$score_dir/$name-$target-$r.err" ) &
                jobs=$((jobs + 1))
            done
        done
    done
    echo "Running $jobs review(s) in parallel..."
    wait
    echo "Outputs: $score_dir"
fi

pass=0 fail=0 cost=0
for f in "$score_dir"/*.json; do
    [ -e "$f" ] || { echo "no outputs in $score_dir" >&2; exit 2; }
    run=$(basename "$f" .json)
    name=${run%-*}; name=${name%-*}
    [ -n "$only_case" ] && [ "$name" != "$only_case" ] && continue
    result=$(jq -r '.result // empty' "$f" 2>/dev/null)
    cost=$(jq -r --arg c "$cost" '($c | tonumber) + (.total_cost_usd // 0)' "$f" 2>/dev/null || echo "$cost")
    while IFS= read -r line; do
        kind=${line%% :: *}; rest=${line#* :: }
        case "$kind" in
            find|avoid) label=${rest%% :: *}; re=${rest#* :: }
                hit=$(printf '%s\n' "$result" | grep -ciE -- "$re")
                if { [ "$kind" = find ] && [ "$hit" -gt 0 ]; } || { [ "$kind" = avoid ] && [ "$hit" -eq 0 ]; }; then
                    status=PASS; pass=$((pass + 1)); else status=FAIL; fail=$((fail + 1)); fi ;;
            max) n=${rest%% :: *}; rest=${rest#* :: }; label=${rest%% :: *}; re=${rest#* :: }
                hit=$(printf '%s\n' "$result" | grep -ciE -- "$re")
                if [ "$hit" -le "$n" ]; then status=PASS; pass=$((pass + 1)); else status=FAIL; fail=$((fail + 1)); fi
                label="$label ($hit lines, max $n)" ;;
            *) continue ;;
        esac
        [ -z "$result" ] && label="$label [no output - see $run.err]"
        printf '  %-4s %-28s %-5s %s\n' "$status" "$run" "$kind" "$label"
    done < "$HERE/cases/$name.expect"
done

echo ""
printf '  --- %d pass, %d fail, $%.2f ---\n' "$pass" "$fail" "$cost"
[ "$fail" -eq 0 ]
