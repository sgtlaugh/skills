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
check "bash is blocked without an allowed script" 2 'bash /opt/owl/query.sh logs-ppl x'
export DARKMOON_ALLOW_SCRIPT=/opt/owl/query.sh
check "the one allowed script runs under bash" 0 "bash /opt/owl/query.sh logs-ppl 'source=owl | head 5'"
check "another script stays blocked" 2 'bash /opt/owl/other.sh x'
check "the allowed script cannot hide a second command" 2 'bash /opt/owl/query.sh x; touch /home/owl/pwned'
check "the allowed script cannot write through a redirect" 2 'bash /opt/owl/query.sh x > /home/owl/out'
check "bash -c is not the allowed script" 2 'bash -c /opt/owl/query.sh'
# The allowed script reached through a symlinked directory, either way round, is the same file; its neighbour isn't
lnk=$(mktemp -d); mkdir -p "$lnk/real"; printf 'exit 0\n' > "$lnk/real/query.sh"; printf 'exit 0\n' > "$lnk/real/other.sh"; ln -s "$lnk/real" "$lnk/link"
export DARKMOON_ALLOW_SCRIPT="$lnk/real/query.sh"
check "the allowed script by a symlinked path runs" 0 "bash $lnk/link/query.sh logs-ppl x"
check "another script by the symlinked path stays blocked" 2 "bash $lnk/link/other.sh x"
export DARKMOON_ALLOW_SCRIPT="$lnk/link/query.sh"
check "allowed by its symlinked path, the real path runs" 0 "bash $lnk/real/query.sh logs-ppl x"
check "a relative path to the allowed file stays blocked" 2 "cd $lnk/real && bash query.sh x"
rm -rf "$lnk"
export DARKMOON_ALLOW_SCRIPT=query.sh
check "a relative allowed path is ignored" 2 'bash query.sh x'
unset DARKMOON_ALLOW_SCRIPT
# Quotes hide nothing: a quoted command or flag is still that command or flag
check "a quoted command name is still the command" 2 '"touch" "/home/owl/pwned"'
check "a quoted interpreter after a read" 2 'ls; "python3" "-c" "import os"'
check "a quoted gh api write flag" 2 'gh api repos/acme/owl/issues "-ftitle=pwn"'
check "a quoted sed -i" 2 'sed "-i" s/a/b/ README.md'
check "a quoted sort -o" 2 'sort "-o" /home/owl/x /tmp/owl.txt'
check "a quoted find -delete" 2 'find . "-delete"'
check "a quoted git --output" 2 'git log "--output=/home/owl/x"'
check "a quoted rg --pre" 2 'rg "--pre=sh" x'
check "a quoted .. in a redirect target" 2 'echo hi >/tmp/"../home/owl/x"'
check "a heredoc marker inside quotes is not a heredoc" 2 $'echo "<<EOF"\ntouch /home/owl/x\nEOF'
check "a quote inside a comment can't swallow the next line" 2 $'ls #\'\ntouch /home/owl/x\n#\''
check "ANSI-C quoting is refused" 2 "echo \$'\\''; touch /home/owl/x #'"
check "awk -f runs a program file" 2 'awk -f /tmp/p.awk /tmp/owl.txt'
check "sed -f runs a script file" 2 'sed -f /tmp/s.sed README.md'
check "mktemp through /tmp/.. leaves /tmp" 2 'mktemp /tmp/../home/owl/x.XXXX'
check "mktemp -p /tmp/.. leaves /tmp" 2 'mktemp -p /tmp/../home/owl'
check "a grep pattern with a quoted pipe and semicolon stays a read" 0 'grep -rnE "moonlit|grove; rm" .'
check "a comment after a read is fine" 0 'ls -la # list the nest'

# Read commands and shapes a skeptic reaches for
check "base64 decode to stdout" 0 'base64 -d /tmp/owl.b64 | head -5'
check "printenv one variable" 0 'printenv WORKSPACE'
check "git ls-tree" 0 'git -C /home/owl/nest ls-tree -r HEAD --name-only'
check "git merge-base" 0 'git merge-base HEAD origin/main'
check "git ls-tree --output still writes a file" 2 'git ls-tree --output=/home/owl/x HEAD'
check "git branch can create a branch" 2 'git branch owl-heist'
check "gh run view" 0 'gh run view 1234 --log-failed'
check "gh pr list" 0 'gh pr list --author owl'
check "gh run rerun is a write" 2 'gh run rerun 1234'
check "a for loop over reads" 0 'for f in a.ts b.ts; do grep -c owl "$f"; done'
check "a for loop whose body writes" 2 'for f in a b; do rm "$f"; done'
check "a loop body running its variable" 2 'for f in rm; do $f nest; done'
check "read assigns variables, so it stays out" 2 'while read -r l; do echo "$l"; done < /tmp/owls.txt'
check "a loop over reads, with its input from /tmp" 0 'for f in a b; do cat "$f"; done < /tmp/owls.txt'
check "an input redirect in front of a write" 2 '< /tmp/owls.txt rm nest'
check "if test then read" 0 'if test -f nest.md; then head -3 nest.md; else echo none; fi'
check "a bare short assignment, then a read" 0 'T=/home/owl/nest; ls "$T"'
check "a bare longer name could be an exported variable" 2 'nest=/home/owl/nest; cat "$nest/README.md"'
check "a bare http_proxy assignment" 2 'http_proxy=http://evil:8080; gh pr view 1'
check "a bare PAGER assignment" 2 'PAGER=/tmp/evil; git log'
check "a bare GIT_ assignment" 2 'GIT_EXTERNAL_DIFF=/tmp/evil; git diff'
check "a bare IFS assignment" 2 'IFS=x; ls'
check "a short assignment in front of a command keeps the env rule" 2 'T=x git log'
# Bypasses found in review: a stored value expanded again in arithmetic, and an exported variable changed
check "a subscript expansion runs a stored \$(...)" 2 'x=b[\$\(touch\ /home/owl/pwn\)]; echo "${a[x]}"'
check "\$[...] arithmetic expansion" 2 'echo $[x]'
check "a substring expansion" 2 'echo "${x:x}"'
check "plain \$name stays allowed" 0 'f=nest.md; head -3 "$f"'
check "a braced \${var} is blocked with the other brace forms" 2 'f=nest.md; head -3 "${f}"'
check "indirect expansion runs a stored subscript" 2 'x=a[\$\(touch\ /home/owl/pwn\)]; echo "${!x}"'
check "prompt expansion runs a stored \$(...)" 2 'x=\$\(touch\ /home/owl/pwn\); echo "${x@P}"'
check "test -v evaluates a subscript" 2 'test -v a[\$\(touch\ /home/owl/pwn\)]'
check "[ -v evaluates a subscript" 2 '[ -v a["$"\(touch\ /home/owl/pwn\)] ]'
check "test -f stays allowed" 0 'test -f nest.md'
# A variable in a write target can expand to .. and leave /tmp
check "a redirect through a variable holding .." 2 'x=..; echo owl > /tmp/$x/home/owl/pwn'
check "a quoted variable in a redirect target" 2 'x=..; echo owl > "/tmp/$x/home/owl/pwn"'
check "a loop variable in a redirect target" 2 'for x in ..; do echo owl > /tmp/$x/home/owl/pwn; done'
check "\$_ in a redirect target" 2 'echo ..; echo owl > /tmp/$_/home/owl/pwn'
check "a variable in a mktemp path" 2 'x=..; mktemp /tmp/$x/home/owl/mkXXX'
check "a plain /tmp redirect stays allowed" 0 'echo owl > /tmp/owl.txt'
check "an escaped dot in a redirect target forms .." 2 'echo owl > /tmp/.\./home/owl/pwn'
check "an escaped dot in a mktemp path" 2 'mktemp /tmp/.\./home/owl/pwnXXX'
check "an escaped dot in mktemp -p" 2 'mktemp -p /tmp/.\./home/owl pwnXXX'
check "a bare mktemp template lands in the current directory" 2 'mktemp pwnXXX'
check "mktemp -d with a bare template" 2 'mktemp -d pwnXXX'
check "a bare template under -p /tmp stays allowed" 0 'mktemp -p /tmp owlXXX'
check "mktemp -d with no template stays allowed" 0 'mktemp -d'
check "mktemp -p with the directory attached" 2 'mktemp -p/tmp/../home/owl -t pwnXXX'
check "mktemp -dp with the directory attached" 2 'mktemp -dp/tmp/../home/owl -t pwnXXX'
check "mktemp with an abbreviated --tmpdir" 2 'mktemp --tmp=/tmp/../home/owl -t pwnXXX'
check "mktemp -dp DIR outside /tmp" 2 'mktemp -dp /home/owl pwnXXX'
check "mktemp -t with a bare template stays allowed" 0 'mktemp -t owl.XXXX'
check "mktemp --tmpdir=/tmp stays allowed" 0 'mktemp --tmpdir=/tmp owl.XXXX'
check "a variable in a read argument stays allowed" 0 'f=nest.md; grep -c owl "$f"'
check "a loop variable named HOME" 2 'for HOME in /tmp/evil; do git status; done'
check "a loop variable named PATH" 2 'for PATH in /tmp/evil; do ls; done'
check "printf -v assigns HOME" 2 'printf -v HOME /tmp/evil; git status'
check "printf -v with a subscript name" 2 'printf -v a[\$\(touch\ x\)] y'
check "printf to stdout stays allowed" 0 'printf "%s\n" owl'
# Input that can't be read is refused, never let through
out=$(printf 'not json' | bash "$HOOK" 2>/dev/null; echo $?)
if [ "$out" = 2 ]; then echo "  PASS: input that is not JSON is refused"; pass=$((pass+1)); else echo "  FAIL: input that is not JSON is refused (got $out)"; fail=$((fail+1)); fi
# ponytail: known ceiling, not blocked - sed w/e commands, uniq's output-file arg, jq writes.
# Closing them means dropping sed/uniq from the allowlist or parsing their args; a read-only container is the upgrade.

echo "  --- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
