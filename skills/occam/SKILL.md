---
name: occam
description: Review the changes thoroughly - bugs, drift (leftover old logic, stale docs/tests/callers), simplifications, and whether the diff is the minimal change for the goal. Runs on your local uncommitted work by default (or a commit / the whole branch) in a fresh-context reviewer, so the author's reasoning can't wave its own work through. Read-only.
trigger: /occam
allowed-tools: Read, Grep, Glob, Agent, Bash(git diff:*), Bash(git show:*), Bash(git log:*), Bash(git status:*), Bash(git ls-files:*), Bash(git rev-parse:*), Bash(git merge-base:*), Bash(git symbolic-ref:*), Bash(git remote:*)
---

# /occam - review your own change before it ships

The review you'd otherwise type by hand: *"review the changes thoroughly - any issues, drifts, simplifications?"* - done by a reviewer that didn't write the code. Occam's razor is the stance: the best change is the smallest one that fully reaches the goal, with nothing broken and nothing left behind.

## Usage

```
/occam                     # local work: tracked changes vs HEAD + untracked files (default)
/occam <goal>              # same, with the goal stated (skips the goal question)
/occam --staged            # only what's staged
/occam --last              # the last commit
/occam --branch            # everything on this branch vs its base
```

## Step 1 - Scope and goal (main context)

- **Scope commands** for the chosen mode - resolve them to literal commands now, since the reviewer runs them in its own shell:

  | Mode | Commands |
  |---|---|
  | default | `git diff HEAD` + `git ls-files --others --exclude-standard` (read each untracked file in full - they are not in the diff) |
  | `--staged` | `git diff --cached` |
  | `--last` | `git show HEAD` |
  | `--branch` | `git diff <merge-base sha>..HEAD`, with the sha resolved here from `git merge-base HEAD <remote>/<base>`. `<remote>` = the remote this branch will be merged into (the org/upstream repo - `git remote -v` shows which URL that is); with several candidates, ask. Never the first remote listed - in multi-fork repos that is often a colleague's fork. `<base>` = `git symbolic-ref refs/remotes/<remote>/HEAD`, else `main`/`master` |

  Run them once: empty scope → "nothing to review" and stop.
- **Goal** is the yardstick for scope creep and for "goal not met". `--last`/`--branch`: the commit messages. Local work: the stated `<goal>`, else the user's request from this conversation in one line. If neither exists, **ask in one line** - never infer the goal from the diff, because a goal reverse-engineered from a bloated diff silently absorbs the bloat.
- Note the repo's `CLAUDE.md` (+ `.claude/CLAUDE.md`) path - its conventions are the bar for the convention check.

## Step 2 - Fresh-context review (one `Agent`)

Spawn one `general-purpose` `Agent`. Its prompt is: the goal line, the repo path, the literal scope commands from Step 1, the `CLAUDE.md` path, and the reviewer brief below - **nothing else** (no summary of your reasoning, no hints about where it's weak; that is the bias the fresh context exists to avoid - commands are facts, not reasoning).

> *You review a change you did not write, as a skeptical senior reviewing a junior's PR: assume it does too much and breaks something until the code shows otherwise. Read-only - never edit, stage, commit or run mutating commands.*
>
> *Run the scope commands you were given (and read every untracked file they list in full), then read each changed file in full where a hunk's correctness depends on its surroundings. Check four things:*
> 1. *Bugs - wrong logic, unhandled error paths, edge inputs (empty, None, huge, unicode, concurrent), broken contracts. For every changed function signature or behavior, grep its callers across the whole repo and check each still works.*
> 2. *Drift - what the change left behind: old logic still reachable next to the new, comments/docstrings/README/CHEATSHEET/tests that still describe the old behavior, renamed things still referenced by their old name, a migration applied in one place but not its siblings.*
> 3. *Simplification and minimality - drive-by refactors, format churn, speculative flags or features, an abstraction with one caller, a wrapper that adds nothing, an existing helper the change re-implemented, debug prints, commented-out code, stray TODOs.*
> 4. *Goal and conventions - does it fully do what the goal says, no more and no less? Violations of the repo's CLAUDE.md.*
>
> *Rules: every finding cites `file:line` and the evidence (the grep or the lines that prove it). "Unused", "one caller", "dead", "never reached" need a whole-repo grep shown - one negative grep with the wrong scope or a missed alias is not proof; if you can't settle it, say "unverified" instead of asserting. Skip what a linter or formatter owns. No findings in a category is a valid answer - never manufacture one to look useful.*
>
> *Return: `Verdict: Clean ✓ | Fix first ⚠️ | Trim ✂️` (Fix first = any bug or goal gap; Trim = only simplification/drift/convention items), then findings grouped Bug / Drift / Simplify / Goal-Convention, each `file:line - what is wrong - evidence - the fix`, then one line naming what is already solid.*

## Step 3 - Surface and stop

- Show the reviewer's verdict and findings **verbatim** under `## occam - <mode> (<N files, +A −D>)` with `Goal: <one line>` first. In the default mode, count untracked files' lines as additions (`git diff --stat` leaves them out).
- If you (the author) disagree with a finding, reply under a separate `## Author's reply` heading with your own evidence - never quietly drop or soften a reviewer finding.
- **Stop there.** occam reports; applying fixes is a separate request. Editing code inside an occam run is WRONG.

## Completion contract

A run is complete only when the output shows:
1. The mode, the file count and the goal line.
2. The verdict (Clean / Fix first / Trim).
3. Every finding with `file:line` + its evidence, or "Clean ✓" with what was checked.
4. Any author disagreement in its own `## Author's reply` block, never merged into the reviewer's text.

## Guard rails

- **Read-only** - by instruction (no hook backs it): the reviewer and occam never edit, stage, commit or push.
- **Fresh context is the point.** Reviewing in the author's context reproduces the author's blind spots; always delegate Step 2.
- **"Clean ✓" is a pass.** Over-flagging is the failure mode on a good diff.
- **Whole PR review with lenses is `/aristarchus`** (it needs a PR URL); occam is the fast pre-push pass on work that may not even be committed yet.
