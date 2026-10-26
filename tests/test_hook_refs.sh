#!/usr/bin/env bash
# Every ~/.claude/hooks/<script> an agent's frontmatter runs must exist in hooks/,
# since install.sh links hooks/ into ~/.claude/hooks/ - a rename would silently drop the guard
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$DIR/.."
pass=0; fail=0

echo "=== hook references ==="

refs=$(grep -ohE '~/\.claude/hooks/[A-Za-z0-9._-]+' "$REPO"/agents/*.md | sort -u)
[ -n "$refs" ] || { echo "  FAIL: found no hook references - pattern or paths broke"; exit 1; }

for ref in $refs; do
    if [ -f "$REPO/hooks/${ref##*/}" ]; then
        echo "  PASS: $ref"; pass=$((pass+1))
    else
        echo "  FAIL: $ref is referenced but missing from hooks/"; fail=$((fail+1))
    fi
done

echo ""
echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
