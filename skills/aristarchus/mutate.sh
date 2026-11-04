#!/usr/bin/env bash
# Mutation check for aristarchus Step 6d: flip the conditions a PR adds, one at a time, and run the
# PR's tests. A mutant the tests stay green on marks a condition no test pins down.
#
# usage: mutate.sh --worktree <dir> --base <sha> --test '<cmd with {files} or {dirs}>'
#                  [--setup '<cmd>'] [--max 12] [--budget 480]
#
# --budget is a hard deadline in seconds for the whole run, setup included; keep it under the caller's
# own timeout so cleanup always runs.
#
# Never edits <dir>: mutants run in a scratch worktree of its HEAD, removed on exit. Always exits 0
# and prints one `mutation:` summary line - a check that can't run reports why and never blocks a review.
#
# Runs from /tmp: a pyenv shim inside a repo whose .python-version names an uninstalled Python fails.
export MUTATE_CALLER_PWD="$PWD"
cd /tmp && exec python3 -I - "$@" <<'PY'
import argparse, os, re, shutil, signal, subprocess, sys, tempfile, time

TEST_RE = re.compile(r'(^|/)(TEST|tests?|__tests__)/|\.(spec|test)\.[cm]?[jt]sx?$|(^|/)test_[^/]*\.py$|_test\.py$')
SOURCE_RE = re.compile(r'\.(py|[cm]?[jt]sx?)$')
OPS_JS = [(r'&&', '||'), (r'\|\|', '&&'), (r'!==', '==='), (r'===', '!=='),
          (r'\breturn true\b', 'return false'), (r'\breturn false\b', 'return true'),
          (r'(?<![!=])!(?=[A-Za-z_$(])', '')]
OPS_PY = [(r' and ', ' or '), (r' or ', ' and '), (r'!=', '=='), (r'(?<![=!<>])==(?!=)', '!='),
          (r'\breturn True\b', 'return False'), (r'\breturn False\b', 'return True'), (r'\bnot ', ''),
          (r'<=', '>'), (r'>=', '<')]
SKIP_LINE = ('//', '#', '*', '/*', 'import ', 'from ', 'export {', 'require(')
# Flipping text inside a string literal never changes logic, so those matches are skipped - and with them
# any condition inside a template literal's ${} or an f-string's {}, a gap left to the lenses.
STRING_RE = re.compile(r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"|`(?:\\.|[^`\\])*`")

p = argparse.ArgumentParser(prog='mutate.sh')
p.add_argument('--worktree', required=True)
p.add_argument('--base', required=True)
p.add_argument('--test', required=True)
p.add_argument('--setup', default='')
p.add_argument('--max', type=int, default=12)
p.add_argument('--budget', type=int, default=480)
a = p.parse_args()
t0 = time.time()
deadline = t0 + a.budget


def done(msg, lines=()):
    print(f'mutation: {msg} | {int(time.time() - t0)}s')
    for line in lines:
        print(line)
    sys.exit(0)


def git(*args, cwd):
    return subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True, stdin=subprocess.DEVNULL)


def added_lines(wt):
    out = git('diff', '-U0', '--no-color', '--no-ext-diff', f'{a.base}...HEAD', cwd=wt).stdout
    res, f, n = [], None, 0
    for line in out.split('\n'):
        if line.startswith('+++ '):
            f = line[6:] if line.startswith('+++ b/') else None
        elif line.startswith('@@'):
            n = int(re.search(r'\+(\d+)', line).group(1))
        elif line.startswith('+') and f:
            res.append((f, n, line[1:]))
            n += 1
    return res


running = []


def run(cmd, wt, timeout):
    # Own process group, so a timeout kills the test runner's children too (docker, mocha workers).
    env = dict(os.environ, PWD=wt)
    proc = subprocess.Popen(cmd, shell=True, cwd=wt, env=env, stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    running[:] = [proc]
    try:
        out = proc.communicate(timeout=timeout)[0]
        return proc.returncode, out.decode(errors='replace')
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        return None, ''
    finally:
        running.clear()


worktree = os.path.abspath(os.path.join(os.environ.get('MUTATE_CALLER_PWD', '/'), a.worktree))
if git('rev-parse', '--git-dir', cwd=worktree).returncode:
    done(f'skipped - {worktree} is not a git worktree')
if git('cat-file', '-e', f'{a.base}^{{commit}}', cwd=worktree).returncode:
    done(f'skipped - base {a.base} is not in the repo (fetch it first)')
if '{files}' not in a.test and '{dirs}' not in a.test:
    done('skipped - the test command has no {files} or {dirs} placeholder')

changed = git('diff', '--name-only', '--no-renames', '--diff-filter=AM', f'{a.base}...HEAD', cwd=worktree).stdout.split()
tests = sorted(f for f in changed if TEST_RE.search(f) and SOURCE_RE.search(f))
if not tests:
    done('skipped - the PR changes no test files, so there are no tests to run its mutants against')
targets = sorted({os.path.dirname(f) + '/' for f in tests}) if '{dirs}' in a.test else tests
test_cmd = a.test.replace('{files}', ' '.join(targets)).replace('{dirs}', ' '.join(targets))

mutants = []
for f, n, text in added_lines(worktree):
    if TEST_RE.search(f) or not SOURCE_RE.search(f) or text.strip().startswith(SKIP_LINE):
        continue
    strings = [m.span() for m in STRING_RE.finditer(text)]
    for pat, rep in (OPS_PY if f.endswith('.py') else OPS_JS):
        for m in re.finditer(pat, text):
            if not any(a0 <= m.start() < a1 for a0, a1 in strings):
                mutants.append((f, n, text, m.start(), m.end(), rep))
if not mutants:
    done('skipped - the PR adds no conditions to mutate')
capped = len(mutants) - a.max
mutants = mutants[:a.max]

scratch = tempfile.mkdtemp(prefix='aristarchus-mutate-')
wt = os.path.join(scratch, 'wt')


def cleanup(*_):
    for proc in running:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    git('worktree', 'remove', '--force', wt, cwd=worktree)
    shutil.rmtree(scratch, ignore_errors=True)
    git('worktree', 'prune', cwd=worktree)


signal.signal(signal.SIGTERM, lambda *_: (cleanup(), done('stopped - terminated')))
try:
    if git('worktree', 'add', '--detach', wt, 'HEAD', cwd=worktree).returncode:
        done('skipped - could not create the scratch worktree')
    if a.setup:
        code, out = run(a.setup, wt, max(1, min(120, deadline - time.time())))
        if code != 0:
            done(f'skipped - setup failed: {out.strip()[-200:]}')
    start = time.time()
    code, out = run(test_cmd, wt, max(1, deadline - start))
    base_secs = time.time() - start
    if code is None:
        done(f'skipped - the PR\'s tests did not finish within the {a.budget}s budget | tests: {" ".join(targets)}')
    if code != 0:
        tail = ' / '.join(l.strip() for l in out.strip().split('\n')[-3:])[:300]
        done(f'skipped - the PR\'s tests already fail before any mutation (exit {code}): {tail} | tests: {" ".join(targets)}')

    results = []
    for f, n, text, s, e, rep in mutants:
        left = deadline - time.time()
        # A mutant run takes about as long as the baseline; one that runs far longer is stuck in a loop the
        # mutation created, which counts as caught.
        if left < base_secs:
            results.append('not run')
            continue
        cap = min(left, 3 * base_secs + 30)
        path = os.path.join(wt, f)
        orig = open(path, encoding='utf-8').read()
        lines = orig.split('\n')
        if n > len(lines) or lines[n - 1] != text:
            results.append('not run')
            continue
        lines[n - 1] = text[:s] + rep + text[e:]
        open(path, 'w', encoding='utf-8').write('\n'.join(lines))
        try:
            code, _ = run(test_cmd, wt, cap)
        finally:
            open(path, 'w', encoding='utf-8').write(orig)
        results.append(('timed out' if cap < left else 'not run') if code is None else 'killed' if code else 'SURVIVED')

    counts = {k: results.count(k) for k in ('killed', 'SURVIVED', 'timed out', 'not run')}
    summary = f'{len(results)} mutant{"" if len(results) == 1 else "s"}: {counts["killed"]} killed, {counts["SURVIVED"]} survived'
    for k in ('timed out', 'not run'):
        if counts[k]:
            summary += f', {counts[k]} {k}' + (' (time budget)' if k == 'not run' else '')
    if capped > 0:
        summary += f', {capped} more over the --max {a.max} cap'
    survivors = [f'SURVIVED {f}:{n} `{text[s:e].strip()}` -> `{rep.strip() or "(removed)"}` | {text.strip()[:140]}'
                 for (f, n, text, s, e, rep), r in zip(mutants, results) if r == 'SURVIVED']
    done(f'{summary} | tests: {" ".join(targets)} | baseline {int(base_secs)}s', survivors)
finally:
    cleanup()
PY
