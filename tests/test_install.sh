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
H2=$(mktemp -d)
trap 'rm -rf "$H" "$H2"' EXIT
S="$H/.claude/skills"

mkdir -p "$S/darkmoon" "$S/retired-skill" "$S/other-repo-skill" "$H/other-repo/occam"
echo "hand-edited" > "$S/darkmoon/SKILL.md"
ln -s "$REPO/skills/retired-skill/SKILL.md" "$S/retired-skill/SKILL.md"
ln -s "$H/unmounted-drive/SKILL.md" "$S/other-repo-skill/SKILL.md"
ln -s "$H/other-repo/occam" "$S/occam"

HOME="$H" bash "$REPO/install.sh" >/dev/null; rc=$?
check "first run exits 0" '[ $rc -eq 0 ]'

check "every skill file is linked" '[ "$(find "$REPO/skills" -type f | wc -l)" -eq "$(find "$S" -type l -lname "$REPO/*" | wc -l)" ]'
check "agent is linked to the repo" '[ "$(readlink "$H/.claude/agents/darkmoon-skeptic.md")" = "$REPO/agents/darkmoon-skeptic.md" ]'
check "hook is linked" '[ -L "$H/.claude/hooks/darkmoon-readonly.sh" ]'
check "existing file backed up, not lost" 'grep -q hand-edited "$S/darkmoon/SKILL.md.bak"'
check "dangling link into this repo and its empty dir pruned" '[ ! -e "$S/retired-skill" ]'
check "dangling link from another repo left alone" '[ -L "$S/other-repo-skill/SKILL.md" ]'
check "symlinked skill dir backed up, other repo untouched" '[ -L "$S/occam.bak" ] && [ -z "$(ls -A "$H/other-repo/occam")" ] && [ -L "$S/occam/SKILL.md" ]'
check "services.md seeded from the template" 'cmp -s "$REPO/services.example.md" "$H/.config/claude-skills/services.md"'
check "credentials.json created mode 600" '[ "$(stat -c %a "$H/.config/claude-skills/credentials.json" 2>/dev/null || stat -f %Lp "$H/.config/claude-skills/credentials.json")" = 600 ]'

echo '{"jiraApiToken": "estus-flask"}' > "$H/.config/claude-skills/credentials.json"
echo "# my catalog" > "$H/.config/claude-skills/services.md"
rm "$S/darkmoon/SKILL.md" && echo "edited again" > "$S/darkmoon/SKILL.md"
HOME="$H" bash "$REPO/install.sh" >/dev/null; rc=$?
check "second run exits 0" '[ $rc -eq 0 ]'
check "second run keeps credentials" 'grep -q estus-flask "$H/.config/claude-skills/credentials.json"'
check "second run keeps the catalog" 'grep -q "my catalog" "$H/.config/claude-skills/services.md"'
check "a second backup never overwrites the first" 'grep -q hand-edited "$S/darkmoon/SKILL.md.bak" && cat "$S"/darkmoon/SKILL.md.bak.* | grep -q "edited again"'

mkdir -p "$H2/.config/claude-skills"
ln -s "$H2/missing.json" "$H2/.config/claude-skills/credentials.json"
out=$(HOME="$H2" bash "$REPO/install.sh" 2>&1); rc=$?
check "broken config link warns instead of aborting" '[ $rc -eq 0 ] && [[ "$out" == *"broken link"* ]] && [ -L "$H2/.config/claude-skills/credentials.json" ]'

rm "$H2/.config/claude-skills/credentials.json" && echo "{not json" > "$H2/.config/claude-skills/credentials.json"
out=$(HOME="$H2" bash "$REPO/install.sh" 2>&1); rc=$?
check "invalid credentials JSON warns instead of aborting" '[ $rc -eq 0 ] && [[ "$out" == *"not valid JSON"* ]]'

# The README's uninstall command, taken from the README itself so the two can't drift
uninstall=$(grep -m1 'find ~/.claude -lname' "$REPO/README.md" | sed 's/^cd [^&]*&& //')
check "README has an uninstall command" '[ -n "$uninstall" ]'
( cd "$REPO" && HOME="$H" bash -c "$uninstall" ); rc=$?
check "uninstall exits 0" '[ $rc -eq 0 ]'
check "uninstall removes every link into the repo" '[ -z "$(find "$H/.claude" -lname "$REPO/*")" ]'
check "uninstall leaves other repos' links and the config" '[ -L "$S/other-repo-skill/SKILL.md" ] && [ -e "$H/.config/claude-skills/credentials.json" ]'

echo ""
echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
