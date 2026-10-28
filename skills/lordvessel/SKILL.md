---
name: lordvessel
description: Review a JIRA ticket against the work done for it - every requirement traced to a linked PR and a SHA-pinned file:line or marked not addressed, plus unanswered questions, unresolved review threads, CI state, contradictions between ticket and code, and a ready-to-post status note. Read-only. --fast skips the darkmoon verification.
trigger: /lordvessel
allowed-tools: Read, Grep, Glob, Skill, Bash(gh api:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh search:*), Bash(jq:*), Bash(bash ~/.claude/skills/humanize/voice-gate.sh:*)
---

# /lordvessel - place every requirement, or name the one missing

The Lordvessel only opens when every Lord Soul is placed. A ticket is done the same way: each requirement placed in code you can link to, and the empty slots named. lordvessel reads the ticket, its comments and every linked PR, and reports what is covered, what is not, and what is still waiting on someone.

## Usage

```
/lordvessel PROJ-1234          # by ticket ID
/lordvessel <jira-url>         # by URL
/lordvessel PROJ-1234 --fast   # skip Step 6 (darkmoon verification)
```

The GitHub org comes from `~/.config/claude-skills/services.md` (`GitHub org`); PR URLs carry their own owner and repo.

## Output contract - the review is NOT done until it shows

1. **Header** - key, title, status, assignee, and every PR found with its state (`open`/`draft`/`merged`/`closed`) and where it was found (`dev-status`, `search` or both), plus the count per source (`dev-status: 0, search: 6`).
2. **Coverage table** - one row per requirement from Step 2: `R<n>`, the requirement verbatim, `Covered` / `Covered (pre-existing)` / `Partial` / `Not addressed` / `Dropped` / `Can't-determine`, the test level (`endpoint test` / `unit test only` / `no test`), and the evidence (Step 4's rules).
3. **Unanswered questions** - each with who asked, where (link) and when; or `none found`.
4. **Unresolved review threads** - per PR: `path:line`, who opened it, its first line (trimmed to ~120 characters), `outdated` when it is, and its link; or `none`.
5. **CI** - per open PR, the head SHA's rollup state and the names of failing checks; or `no open PRs`.
6. **Contradictions** - each with both sides cited; or `none found`.
7. **Verification line** - `Verified: N claims via darkmoon - U upheld, W weak, C can't-determine, R refuted` or `skipped (--fast)`.
8. **Status note** (Step 7) and the gate's result for it.

## Process

### Step 1 - Intake (one message)

Run in parallel:
- `/jira` **Get Ticket** (description, comments, parent, links) and its **Linked PRs** lookup.
- Every spec or design doc the description links (Confluence via `/jira confluence <url>`) and the ticket it was split from or belongs to (`parent`, `issuelinks`) - a requirement like "Option B from the tech spec" can't be judged without the spec.
- `gh search prs --owner <github-org> "<KEY>" --json url,state,title,isDraft` - dev-status misses PRs whose branch and title don't carry the key the way the integration expects, and a search catches them.

Union the two lists by URL. dev-status often succeeds and returns nothing while the search finds every PR - report both counts; neither source alone is trusted. A failed dev-status call (`curl: (N)`) leaves the search result as the only source - say so in the header; it is not "no PRs". A closed, unmerged PR is listed but is never evidence for coverage. No PRs from either source → the coverage table is all `Not addressed`, and the status note says no work is linked.

### Step 2 - Requirements

Number every requirement `R1..Rn`, quoted verbatim:
- An **Acceptance Criteria** section, or any checklist, numbered or bulleted list in the description - one row per item, untagged. Two items are never merged into one row.
- **Scope changes in comments** - a later comment that adds, drops or changes a requirement becomes its own row, tagged with author and date. A dropped requirement stays in the table as `Dropped (<who>, <date>)`.
- **Scope narrowed by a linked spec** (an MVP section that excludes it) → `Dropped (spec: "<quoted line>")` only when the ticket links that spec; otherwise `Partial`, and the mismatch goes in the status note as a question.
- **No explicit criteria** → derive them from the description, tag each `(derived)`, and say in the header that the ticket has no acceptance criteria. That gap belongs in the status note.

### Step 3 - Fetch each PR

Per PR, one GraphQL read and the diff:
```bash
gh api graphql -F query=@$HOME/.claude/skills/lordvessel/pr.graphql -F owner=<owner> -F name=<repo> -F number=<n> > /tmp/lordvessel-<repo>-<n>.json
gh pr diff <n> --repo <owner>/<repo>
```
The query returns body, head, base and merge SHAs, conversation comments, reviews, review threads (with `isResolved`, `isOutdated`) and the head commit's check rollup. Unresolved threads and CI come straight from it:
```bash
jq -r '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)
  | "\(.path):\(.line // .originalLine)\t\(.comments.nodes[0].author.login)\t\(if .isOutdated then "outdated" else "" end)\t\(.comments.nodes[0].body | split("\n")[0] | .[0:120])\t\(.comments.nodes[0].url)"' /tmp/lordvessel-<repo>-<n>.json
jq -r '.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup
  | "\(.state)\t" + ([.contexts.nodes[] | select((.conclusion // .state) | IN("FAILURE","ERROR","TIMED_OUT","CANCELLED")) | .name // .context] | join(", "))' /tmp/lordvessel-<repo>-<n>.json
```
Check the size first with `gh pr view <n> --repo <owner>/<repo> --json additions,deletions`. Over ~3000 changed lines → skip `gh pr diff`; list the files with `gh api "repos/<owner>/<repo>/pulls/<n>/files" --paginate --jq '.[].filename'` and read each one Step 4 needs at the head SHA with `gh api -H "Accept: application/vnd.github.raw" "repos/<owner>/<repo>/contents/<path>?ref=<headRefOid>"`.

### Step 4 - Trace coverage

For each requirement, find the change that implements it:
- **Covered** needs a permalink to the implementing line - `https://github.com/<owner>/<repo>/blob/<sha>/<path>#L<n>` - pinned to the merge commit (`mergeCommit.oid`) for a merged PR, the head SHA (`headRefOid`) for an open one. When a later PR changed the same line, cite the later PR's commit: that is the code that ships. Plus the test level: `endpoint test`, `unit test only` (with its permalink) or `no test`. `Covered` without a permalink is WRONG.
- **Partial** names the missing piece next to the permalink of what is there.
- **Not addressed** lists what was searched (terms, PRs, files). It is a claim about every PR found, so it is valid only after every PR's diff was read.
- **Already satisfied** by code outside the diff → `Covered (pre-existing)` with a permalink at the base SHA.
- **Can't-determine** names what would settle it (a PR that failed to fetch, behavior that only runtime shows).

### Step 5 - Questions and contradictions

**Unanswered question:** a comment containing `?` (ticket comment, PR conversation, review body or review thread) with no later reply from a different person in the same place. Strip URLs before looking for `?` (a link's `?query` is not a question), and skip bot authors (a login ending in `[bot]`, Copilot, CI). A resolved thread counts as answered. Rhetorical asides don't count. Give the asker, link and date.

**Contradiction:** two sources that cannot both hold, each cited:
- the ticket requires X, the code does Y;
- a comment changed scope and the code follows the old version;
- the PR description claims a change the diff doesn't contain.

### Step 6 - Verify (skipped with --fast)

Invoke `/darkmoon --claims` (always with `--claims`) with every `Covered` and `Partial` row and every contradiction, each as *"In `<permalink>`, <what the code does>, which satisfies R<n>: <requirement>."* Integrate the verdicts:
- **Refuted** → `Not addressed`, or `Partial` when part survives.
- **Weak** → `Partial`, with the skeptic's counter as the missing piece.
- **Can't-determine** → keep the status, add the skeptic's open question to the row.
- **Upheld** → mark `(verified)`.

### Step 7 - Status note

Draft a note for the ticket or the PR, in the voice of `~/.claude/skills/humanize/references/github-voice.md` (read it first):
- First line: where the work stands - `<covered> of <N> requirements covered`, and one of: ready for review, blocked, waiting on someone, or done with items still open.
- Then only what is open, as a list: each not-addressed or partial requirement, each contradiction, each unanswered question (who it waits on), unresolved threads, failing CI. Each item carries its link. Five or fewer unresolved threads on a PR are listed one by one; more become one line per PR with the count and the PR link.
- Nothing else: no praise, no restating covered work, no darkmoon detail.

Write it to a file and run the gate:
```bash
bash ~/.claude/skills/humanize/voice-gate.sh --max-chars 1000 <file>
```
Every violation is fixed and the gate re-run until it prints `voice-gate: clean`. Show the note and `voice-gate: clean`. A note shown without a clean gate run is WRONG.

Show it and stop. Posting is a separate, explicit user request: `/jira comment` for the ticket (its yes rule applies), or the user posts on GitHub.

## Rules

- **READ ONLY.** No comments, transitions, reviews, approvals or label changes, on Jira or GitHub. The `gh api` grant is for reads; GraphQL goes through the query file, never a mutation. That is an instruction, not a sandbox: `Bash(gh api:*)` can POST, so back it with `permissions.deny` rules for `gh api` `-X`/`--method`/`--field`/`--raw-field`/`--input` and a hook that blocks `-f`/`-F` REST writes and GraphQL mutations.
- **Evidence or Can't-determine.** Every status, question and thread carries its link. A row with no evidence is `Can't-determine`, never a guess.
- **Every PR, every requirement.** A requirement missing from the table, or a PR found but not read, makes the review incomplete; say which, never silently drop it.
