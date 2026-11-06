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

out=$(HOME="$H" WORKSPACE= bash "$REPO/install.sh" 2>&1); rc=$?
check "first run exits 0" '[ $rc -eq 0 ]'
check "first run names the unset jira keys and what they block" '[[ "$out" == *"unset: jiraApiToken, jiraBaseUrl, jiraEmail → /jira, /triage"* ]]'
check "first run names the unset sentry keys" '[[ "$out" == *"sentryAuthToken, sentryOrg → /sentry, /sentry-fix"* ]]'
check "first run flags the catalog as still the template" '[[ "$out" =~ services\.md\ +still\ the\ template ]]'
check "first run flags an unset \$WORKSPACE" '[[ "$out" =~ WORKSPACE\ +unset ]]'
check "first run marks the optional files as optional, not missing" '[[ "$out" =~ ·\ voice\.md\ +optional ]] && [[ "$out" =~ ·\ work\.json\ +optional ]]'
check "piped output carries no colour codes" '[[ "$out" != *$'"'"'\e['"'"'* ]]'
check "setup notes point at the README section" '[[ "$out" == *"Install\" in $REPO/README.md"* ]] && grep -q "^## Install" "$REPO/README.md"'

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
out=$(HOME="$H" WORKSPACE="$H/clones" bash "$REPO/install.sh" 2>&1); rc=$?
check "second run exits 0" '[ $rc -eq 0 ]'
check "second run still lists what is missing" '[[ "$out" == *"unset: jiraBaseUrl, jiraEmail → /jira"* ]]'
check "a set key is no longer listed" '[[ "$out" != *jiraApiToken* ]]'
check "an edited catalog is not flagged" '[[ "$out" != *"still the template"* ]]'
check "a set \$WORKSPACE is not flagged" '[[ "$out" =~ ✓\ \$WORKSPACE ]]'
check "gh without a login is flagged" '[[ "$out" =~ ⚠\ gh\ +not\ logged\ in ]]'
printf '| GitHub org | owlcorp |\n| Log search skill | `<your log search skill>` |\n' > "$H/.config/claude-skills/services.md"
out=$(HOME="$H" WORKSPACE="$H/clones" bash "$REPO/install.sh" 2>&1)
check "a partly filled catalog reports how many values are left" '[[ "$out" == *"1 value still reads <your ...>"* ]]'
echo "# my catalog" > "$H/.config/claude-skills/services.md"
jq 'with_entries(.value = "set")' "$REPO/credentials.example.json" > "$H/.config/claude-skills/credentials.json"
touch "$H/.config/claude-skills/voice.md"
out=$(HOME="$H" WORKSPACE="$H/clones" GH_TOKEN=bonfire bash "$REPO/install.sh" 2>&1)
check "a complete setup is ready, with nothing flagged" '[[ "$out" == *"✓ Ready."* ]] && [[ "$out" != *"⚠"* ]]'
check "gh logged in through GH_TOKEN is accepted" '[[ "$out" =~ ✓\ gh\ +logged\ in ]]'
check "a present optional file gets a tick" '[[ "$out" =~ ✓\ voice\.md ]]'
echo '{"jiraApiToken": "estus-flask"}' > "$H/.config/claude-skills/credentials.json"
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
