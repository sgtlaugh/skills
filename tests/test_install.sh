#!/usr/bin/env bash
# Tests for install.sh, run against a throwaway HOME
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
pass=0; fail=0

check() {
    if eval "$2"; then
        echo "  PASS: $1"; pass=$((pass+1))
    else
        echo "  FAIL: $1"; fail=$((fail+1))
    fi
}

echo "=== install.sh ==="
H=$(mktemp -d)
trap 'rm -rf "$H"' EXIT

mkdir -p "$H/.claude/skills/darkmoon" "$H/.claude/skills/retired-skill"
echo "hand-edited" > "$H/.claude/skills/darkmoon/SKILL.md"
ln -s "$H/nowhere" "$H/.claude/skills/retired-skill/SKILL.md"

HOME="$H" bash "$REPO/install.sh" >/dev/null; rc=$?
check "first run exits 0" '[ $rc -eq 0 ]'

check "every skill file is linked" '[ "$(find "$REPO/skills" -type f | wc -l)" -eq "$(find "$H/.claude/skills" -type l | wc -l)" ]'
check "agent is linked to the repo" '[ "$(readlink "$H/.claude/agents/darkmoon-skeptic.md")" = "$REPO/agents/darkmoon-skeptic.md" ]'
check "hook is linked" '[ -L "$H/.claude/hooks/darkmoon-readonly.sh" ]'
check "existing file backed up, not lost" 'grep -q hand-edited "$H/.claude/skills/darkmoon/SKILL.md.bak"'
check "dangling link and its empty dir pruned" '[ ! -e "$H/.claude/skills/retired-skill" ]'
check "services.md seeded from the template" 'cmp -s "$REPO/services.example.md" "$H/.config/claude-skills/services.md"'
check "credentials.json created mode 600" '[ "$(stat -c %a "$H/.config/claude-skills/credentials.json" 2>/dev/null || stat -f %Lp "$H/.config/claude-skills/credentials.json")" = 600 ]'

echo '{"jiraApiToken": "estus-flask"}' > "$H/.config/claude-skills/credentials.json"
echo "# my catalog" > "$H/.config/claude-skills/services.md"
HOME="$H" bash "$REPO/install.sh" >/dev/null; rc=$?
check "second run exits 0" '[ $rc -eq 0 ]'
check "second run keeps credentials" 'grep -q estus-flask "$H/.config/claude-skills/credentials.json"'
check "second run keeps the catalog" 'grep -q "my catalog" "$H/.config/claude-skills/services.md"'

echo ""
echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
