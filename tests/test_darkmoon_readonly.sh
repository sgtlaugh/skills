#!/usr/bin/env bash
# Tests for hooks/darkmoon-readonly.sh
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/../hooks/darkmoon-readonly.sh"
pass=0; fail=0

check() {
    local desc="$1" expected="$2" cmd="$3" rc
    jq -n --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$HOOK" 2>/dev/null; rc=$?
    if [ "$rc" = "$expected" ]; then
        echo "  PASS: $desc"; pass=$((pass+1))
    else
        echo "  FAIL: $desc (expected $expected, got $rc): $cmd"; fail=$((fail+1))
    fi
}

echo "=== darkmoon-readonly.sh ==="

# Allowed: reads
check "grep with pipe inside quotes" 0 'grep -rnE "moonlit|grove" .claude/skills'
check "git log" 0 'git log --oneline -3'
check "git -C diff" 0 'git -C /home/owl/Github/owl-api diff HEAD~1'
check "jq with > inside program" 0 "jq -r '.visits > 1' /tmp/owl.json"
check "pipeline with stderr to /dev/null" 0 'ls ~/.claude/projects 2>/dev/null | head -5'
check "stderr merged" 0 'grep -c darkmoon README.md 2>&1'
check "find by name" 0 'find . -name "*.sh" -type f'
check "gh pr view" 0 'gh pr view 1234 --json title'
check "gh api GET" 0 'gh api repos/acme/owl-api/pulls/1234/comments'
check "cd then grep" 0 'cd /home/owl/Github/owl-api && grep -n darkmoon README.md'
check "sort numeric" 0 'sort -n /tmp/owl.txt'
check "git grep" 0 'git grep -n darkmoon -- .claude'
check "find -print" 0 'find . -name "*.md" -print'
check "rg read" 0 'rg -n "moonlit" .claude/skills'
check "grep for <( as quoted pattern" 0 'grep -n "touch\|<(\|process sub" tests/test_darkmoon_readonly.sh'
check "gh api GET with jq" 0 "gh api repos/acme/owl-api/pulls/1234 --jq '.title'"
check "heredoc fixture into /tmp, evil-looking body is data" 0 "cat > /tmp/dm-0523-2002.jsonl <<'EOF'
{\"type\":\"user\",\"message\":{\"content\":\"rm -rf / ; git push\"}}
rm -rf /
EOF"

# Blocked: writes and escapes
check "rm" 2 'rm -rf .claude/skills/darkmoon'
check "redirect into repo" 2 'echo pwned > README.md'
check "append into home" 2 'echo x >> ~/.zshrc'
check "git commit" 2 'git commit -am "moonlight heist"'
check "git push after read" 2 'git log -1 && git push origin main'
check "sed in-place" 2 "sed -i 's/a/b/' install.sh"
check "sed combined -Ei" 2 "sed -Ei 's/a/b/' install.sh"
check "find -delete" 2 'find /tmp/grove -name "*.json" -delete'
check "find -exec" 2 'find . -name x -exec rm {} ;'
check "gh api POST" 2 'gh api -X POST repos/acme/owl-api/issues/1/comments -f body=hi'
check "gh pr create" 2 'gh pr create --title "Darkmoon Was Here"'
check "bash -c" 2 "bash -c 'rm x'"
check "command substitution" 2 'grep x $(rm -f y)'
check "backticks" 2 'grep x `rm -f y`'
check "awk system" 2 "awk 'BEGIN{system(\"rm x\")}'"
check "tee" 2 'echo x | tee notes.md'
check "python" 2 'python3 -c "open(\"x\",\"w\")"'
check "heredoc into repo" 2 "cat > install.sh <<'EOF'
nope
EOF"
check "gh api --method=" 2 'gh api repos/acme/owl-api/issues/1/comments --method=POST'
check "gh api -XPOST" 2 'gh api -XPOST repos/acme/owl-api/issues/1/comments'
check "gh api --field=" 2 'gh api repos/acme/owl-api/issues/1/comments --field=body=hi'
check "gh api -fbody=" 2 'gh api repos/acme/owl-api/issues/1/comments -fbody=hi'
check "process substitution <(" 2 'cat <(touch /home/owl/moonlit-grove)'
check "process substitution >(" 2 'grep x README.md | cat >(touch y)'
check "/tmp/.. traversal" 2 'echo x > /tmp/../home/owl/.zshrc'
check "rg --pre" 2 'rg --pre touch darkmoon'
check "git grep -O" 2 'git grep -Otouch darkmoon'
check "git grep --open-files-in-pager" 2 'git grep --open-files-in-pager=touch darkmoon'
check "git diff --output" 2 'git diff --output=README.md'
check "git grep -O bundled behind another flag" 2 "git grep -iO'touch /tmp/owl' darkmoon"
check "git grep --open-files-in-pager abbreviated" 2 "git grep --open-f='touch /tmp/owl' darkmoon"
check "git grep --op, the shortest unique prefix" 2 'git grep --op=touch darkmoon'
check "git diff --output abbreviated" 2 'git diff --outp=README.md'
check "git log --ou abbreviated" 2 'git log --ou=README.md'
check "git log --oneline is not --output" 0 'git log --oneline -3'
check "git grep with bundled read flags" 0 'git grep -niw darkmoon -- .claude'
check "git log -p --stat" 0 'git log -p --stat -2'
check "find -fprintf" 2 'find . -name x -fprintf README.md %p'
check "find -fprint0" 2 'find . -name x -fprint0 README.md'
check "sort -o" 2 'sort -o README.md /tmp/owl.txt'
check "sort --output" 2 'sort --output=README.md /tmp/owl.txt'
check "sort --compress-program" 2 'sort --compress-program=sh /tmp/owl.txt'
check "GIT_EXTERNAL_DIFF assignment" 2 "GIT_EXTERNAL_DIFF='touch /tmp/x' git diff"
check "PAGER assignment" 2 'PAGER=touch git log'
check "LC_ALL assignment allowed" 0 'LC_ALL=C sort /tmp/owl.txt'
check "an escaped double quote can't hide a redirect" 2 'echo \" > /home/owl/.bashrc \"'
check "an escaped single quote can't hide a command" 2 "echo \' ; touch /home/owl/pwned ; echo \'"
check "an apostrophe inside double quotes is a plain character" 2 "echo \"a'b\" | tee /home/owl/x 'y'"
check "grep for can't, then a quoted argument, stays a read" 0 "grep -n \"can't\" README.md | grep -c 'owl'"
check "git -C with no path does not hang" 2 'git -C'
check "a here-string is not a heredoc" 2 $'cat <<<word\ntouch /home/owl/pwned'
check "a heredoc delimiter with a digit ends at the whole word" 2 $'cat <<E1\nhi\nE1\ntouch /home/owl/pwned'
check "gh api bundled -iXPOST" 2 'gh api -iXPOST repos/acme/owl/issues'
check "gh api bundled -if" 2 'gh api -if title=x repos/acme/owl/issues'
check "sed --in (a prefix of --in-place)" 2 'sed --in s/a/Z/ README.md'
check "sort --out= (a prefix of --output)" 2 'sort --out=/home/owl/o /tmp/owl.txt'
check "sort --compress-prog=" 2 'sort --compress-prog=sh /tmp/owl.txt'
check ">&2x is a redirect to a file named 2x" 2 'echo hi >&2x'
check ">&2 stays allowed" 0 'echo hi >&2'
check "mktemp outside /tmp" 2 'mktemp /home/owl/xXXXX'
check "mktemp -p outside /tmp" 2 'mktemp -p /home/owl'
check "mktemp in /tmp stays allowed" 0 'mktemp /tmp/owl.XXXX'
check "file -C compiles a magic file" 2 'file -C -m /tmp/owl.magic'
check "awk piping to a shell" 2 "awk '{ print | \"sh\" }' /tmp/owl.txt"
check "awk getline from a command" 2 "awk 'BEGIN { \"id\" | getline x }'"
check "awk with a comparison stays a read" 0 "awk '\$3 > 5 { print \$1 }' /tmp/owl.txt"
# ponytail: known ceiling, not blocked - sed w/e commands, uniq's output-file arg, jq writes.
# Closing them means dropping sed/uniq from the allowlist or parsing their args; a read-only container is the upgrade.

echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
