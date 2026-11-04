#!/usr/bin/env bash
# Tests for aristarchus/mutate.sh against a throwaway repo: one condition its test pins down, one it doesn't
DIR="$(cd "$(dirname "$0")" && pwd)"
M="$DIR/../skills/aristarchus/mutate.sh"
pass=0; fail=0
T=$(mktemp -d)
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
trap 'rm -rf "$T"' EXIT

assert() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then echo "  PASS: $desc"; pass=$((pass+1))
    else echo "  FAIL: $desc (expected '$expected', got '$actual')"; fail=$((fail+1)); fi
}
has() {
    local desc="$1" needle="$2" out="$3"
    if grep -qF -- "$needle" <<<"$out"; then echo "  PASS: $desc"; pass=$((pass+1))
    else echo "  FAIL: $desc (no \"$needle\" in: $out)"; fail=$((fail+1)); fi
}

R="$T/vault"
git init -q "$R"
g() { git -C "$R" -c user.email=keeper@vault.test -c user.name=keeper "$@"; }
cat > "$R/rules.py" <<'EOF'
def may_open(guard):
    raise NotImplementedError('the vault has no rules yet')
EOF
g add . && g commit -qm 'chore: empty vault rules'
BASE=$(g rev-parse HEAD)
cat > "$R/rules.py" <<'EOF'
DENIED = 'no duty and no key'


def may_open(guard):
    return guard.get('on_duty') and guard.get('has_key')


def is_sealed(depth):
    return depth == 0


def keep_spinning():
    return False


def spin():
    while keep_spinning():
        pass
EOF
mkdir -p "$R/tests"
cat > "$R/tests/test_rules.py" <<'EOF'
import os, sys
sys.path.insert(0, os.getcwd())
from rules import is_sealed, may_open, spin
assert may_open({'on_duty': True, 'has_key': True})
assert not may_open({'on_duty': False, 'has_key': False})
assert is_sealed(0) and not is_sealed(3)
spin()
EOF
g add . && g commit -qm 'feat: guards open the vault'
CMD='for f in {files}; do python3 "$f" || exit 1; done'
before=$(g rev-parse HEAD; cat "$R/rules.py")

echo "=== mutate.sh ==="
out=$(bash "$M" --worktree "$R" --base "$BASE" --test "$CMD"); rc=$?
assert "exits 0" 0 "$rc"
has "counts the mutants; a mutant that loops forever counts as timed out" "mutation: 3 mutants: 1 killed, 1 survived, 1 timed out | tests: tests/test_rules.py" "$out"
has "names the surviving condition" 'SURVIVED rules.py:5 `and` -> `or` | return guard.get' "$out"
assert "an operator inside a string literal is not mutated" 0 "$(grep -c 'DENIED' <<<"$out")"
assert "one SURVIVED line" 1 "$(grep -c '^SURVIVED' <<<"$out")"
assert "the reviewed worktree is untouched" "$before" "$(g rev-parse HEAD; cat "$R/rules.py")"
assert "no uncommitted change left behind" "" "$(g status --porcelain)"
assert "the scratch worktree is removed" 1 "$(g worktree list | wc -l | tr -d ' ')"
assert "the scratch directory is removed" "" "$(ls "$TMPDIR")"

out=$(cd "$T" && bash "$M" --worktree vault --base "$BASE" --test "$CMD" --max 1)
has "a relative worktree resolves against the caller's directory, and --max caps" "mutation: 1 mutant: 0 killed, 1 survived, 2 more over the --max 1 cap" "$out"

out=$(bash "$M" --worktree "$R" --base "$BASE" --test "$CMD" --budget 6 2>&1); rc=$?
has "the hard budget stops a looping mutant short of its loop cap" "1 not run (time budget)" "$out"
assert "no survivor is claimed for it" 0 "$(grep -c '^SURVIVED rules.py:13' <<<"$out")"
assert "exits 0 after the budget" 0 "$rc"
assert "no scratch worktree left after a budget stop" 1 "$(g worktree list | wc -l | tr -d ' ')"

mkdir -p "$T/shared_modules/deep" && echo kept > "$T/shared_modules/deep/file"
out=$(bash "$M" --worktree "$R" --base "$BASE" --test "$CMD" --max 1 --setup "ln -s '$T/shared_modules' node_modules")
has "setup runs in the scratch worktree" "1 survived" "$out"
assert "cleanup removes a setup symlink, not its target" kept "$(cat "$T/shared_modules/deep/file")"

has "a failing baseline skips" "skipped - the PR's tests already fail before any mutation (exit 1)" \
    "$(bash "$M" --worktree "$R" --base "$BASE" --test 'false {files}')"
start=$(date +%s)
out=$(bash "$M" --worktree "$R" --base "$BASE" --test 'sleep 30; true {files}' --budget 2)
has "a hanging baseline skips at the budget" "skipped - the PR's tests did not finish within the 2s budget" "$out"
assert "and returns promptly" yes "$([ $(( $(date +%s) - start )) -lt 15 ] && echo yes || echo no)"
bash "$M" --worktree "$R" --base "$BASE" --test "sleep 271 & echo \$! > '$T/runner.pid'; wait; true {files}" > "$T/term.out" &
pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(g worktree list | wc -l | tr -d ' ')" -gt 1 ] && break; sleep 0.5; done
sleep 1; kill -TERM "$pid"; wait "$pid"
has "SIGTERM stops the run and says so" "mutation: stopped - terminated" "$(cat "$T/term.out")"
# SIGKILL lands asynchronously, so give the killed test runner a moment to exit
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$(cat "$T/runner.pid")" 2>/dev/null || break; sleep 0.2; done
assert "SIGTERM kills the running tests" gone "$(kill -0 "$(cat "$T/runner.pid")" 2>/dev/null && echo running || echo gone)"
assert "SIGTERM removes the scratch worktree" 1 "$(g worktree list | wc -l | tr -d ' ')"
has "a failing setup skips" "skipped - setup failed" \
    "$(bash "$M" --worktree "$R" --base "$BASE" --test "$CMD" --setup 'echo no shared modules; exit 3')"
has "a test command without a placeholder skips" "skipped - the test command has no {files} or {dirs} placeholder" \
    "$(bash "$M" --worktree "$R" --base "$BASE" --test 'python3 -m pytest')"
has "a PR that changes no tests skips" "skipped - the PR changes no test files" \
    "$(bash "$M" --worktree "$R" --base HEAD --test "$CMD")"
has "an unknown base skips" "skipped - base 0123abcd is not in the repo" \
    "$(bash "$M" --worktree "$R" --base 0123abcd --test "$CMD")"
has "a directory outside git skips" "is not a git worktree" \
    "$(bash "$M" --worktree "$T/tmp" --base "$BASE" --test "$CMD")"
assert "nothing is left behind after all runs" "1|" "$(g worktree list | wc -l | tr -d ' ')|$(ls "$TMPDIR")"

echo ""
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
