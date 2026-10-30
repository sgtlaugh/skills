---
name: nicepr
description: Generate short, human PR titles and descriptions from branch diff and JIRA context
trigger: /nicepr
allowed-tools: Read, Write, Edit, Skill, Bash(git log:*), Bash(git diff:*), Bash(git branch:*), Bash(git remote:*), Bash(git symbolic-ref:*), Bash(git rev-parse:*), Bash(git merge-base:*), Bash(git merge-tree:*), Bash(git fetch:*), Bash(git push:*), Bash(gh api:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(gh pr edit:*), Bash(gh pr checkout:*), Bash(jq:*), Bash(cat:*), Bash(sed:*), Bash(grep:*), Bash(head:*)
---

# /nicepr - Generate PR Description

Generate a clean PR title + description from current branch changes and JIRA context.

## Usage

```
/nicepr                                # generate PR description (local only)
/nicepr --humanize                     # generate + strip AI patterns via humanize skill
/nicepr --humanize --concise           # same + cut length ~50%
/nicepr --create                       # push branch + create PR on GitHub
/nicepr --create --draft               # push branch + create draft PR
/nicepr --create --reviewers acme/backend  # create + assign reviewers (users or org/team); default: work.json "reviewers", none on a draft
/nicepr --update                       # regenerate description for existing PR
```

## Step 0 - Gather Context

Run detection steps separately - if a step fails, handle it before continuing. Don't chain dependent steps.

**Step 0a: Branch, user, and remotes**
```bash
BRANCH=$(git branch --show-current) && GH_USER=$(gh api user --jq .login 2>/dev/null) && git remote -v
```

**Step 0b: Detect fork and upstream remotes**

From `git remote -v` output:
- **Fork remote**: remote name matching `$GH_USER` (your GitHub login, e.g. `octocat`)
- **Upstream remote**: the org repo. Detect in priority order:
  1. If fork remote exists, query `gh api "repos/$FORK_REPO" --jq '.parent.full_name'` for parent, match to a remote
  2. If `origin` exists AND points to an org repo (not a personal fork), use it
  3. Look for an org-named remote or `upstream` in `git remote -v` output

Do NOT assume `origin` exists. Do NOT error out if `origin` is missing - detect upstream from other remotes.

Record the detected values as literals. Shell variables do not persist between Bash calls, so every later command block (Step 0c onward) starts by re-declaring the ones it uses:
```bash
BRANCH=<branch> GH_USER=<login> FORK_REMOTE=<fork remote name, empty if none> FORK_REPO=<owner/repo from the fork URL> UPSTREAM=<upstream remote name> ORG_REPO=<owner/repo from the upstream URL>
```

**Step 0c: Base branch and diff**
```bash
# Detect base branch - check symbolic HEAD, fallback to main/master
BASE=$(git symbolic-ref refs/remotes/$UPSTREAM/HEAD 2>/dev/null | sed "s@^refs/remotes/$UPSTREAM/@@")
if [ -z "$BASE" ]; then
  git rev-parse --verify $UPSTREAM/main &>/dev/null && BASE=main || BASE=master
fi

# Fetch base to ensure it's current
git fetch $UPSTREAM $BASE 2>&1

# All changes on this branch vs base
git log $UPSTREAM/$BASE..HEAD --format="%s%n%b"
git diff --stat $UPSTREAM/$BASE...HEAD
git diff $UPSTREAM/$BASE...HEAD
```

Record the detected `BASE` as a literal alongside the Step 0b values.

Always read full diff - needed for accurate What changed bullets. For very large diffs (500+ lines), focus on the most impactful changes and summarize the rest.

Extract JIRA ticket ID from branch name (pattern `[A-Z]+-\d+`). If found, invoke the `/jira` skill to fetch the ticket (e.g., `/jira PROJ-1234`) for summary, description, and linked issues. Treat any of these as a failed fetch: stderr contains `unset in the credentials file`, `Could not open file` or any `curl: (N)`, empty output, `.errorMessages` in the response, or no `.fields.summary`. On a failed fetch, skip JIRA and generate from commits only - stopping to ask for credentials or editing the credentials file is NOT valid.

## Step 1 - Generate PR Title

Format: `<TICKET-ID>: <Short Title Case Description>`

- Under 70 characters, **Title Case** (capitalize significant words - not articles/prepositions like "a", "the", "in", "of")
- Imperative mood for titles ("Fix", "Add", "Remove")
- Ticket ID from branch name (e.g., `PROJ-1234` from `PROJ-1234-add-csv-export`)
- No ticket ID in branch? Just the description
- Example: `PROJ-1234: Add CSV Export to the Reports Page`

## Step 2 - Generate PR Body

Short, clean, scannable. Write like a human talking to a teammate, not a report.

### Template

```markdown
**Ticket:** <JIRA_URL>/browse/<TICKET-ID>
<!-- omit Ticket line entirely if no ticket -->

### Why

<Optional **Root Cause:** one-line summary, first, when the cause differs from the symptom. Must stay one line. If it needs a paragraph, it's the Why section itself, not a lead-in.>
<1-2 sentences: the problem or need, sized with real numbers. Not what the code does - why it needs to change.>

### Changes

- Verb-led bullet per logical change.

- One fact per bullet. Short, direct.

- Code snippets when they clarify a decision.

- Blank line between bullets when each bullet has substantial text (more than a short phrase). For short, one-line bullets, no blank line needed.

### Related Issues  (optional - only when there are linked Sentry/JIRA/GitHub references)

**Sentry issues:**
- [ISSUE-ID](url) - N events, description

**JIRA:**
- [TICKET-ID](url) - description

**GitHub:**
- Reference with #number for auto status icons

### ✅ QA Steps
- [ ] <Step 1>
- [ ] <Step 2>
```

Adapt to PR size:
- **Most PRs**: Why + Changes, plus QA only when a reviewer has a manual check to run before merge (see QA quality).
- **Large PRs**: use the large-PR house style below (badges, emoji sections, callouts, tables, mermaid) when each piece earns its space.
- **Risk or open questions**: add only when genuinely needed.
- **Reproduction**: skip when QA steps already cover it. Only add as a separate section when repro steps are complex and distinct from QA.

### Writing style

Follow the persona in the user's CLAUDE.md if it defines one; either way: direct, evidence-first, no filler. Write like a human engineer, not an AI. The #1 rule: if it sounds like AI wrote it, rewrite it.

Humor is welcome when it fits naturally - a witty commit reference, a self-deprecating note about a gnarly fix, a short quip in the Why section. Never forced, never unprofessional. If you have to try to be funny, skip it.

**Sentence rules:**
- Short sentences. Max ~15 words. Fragments OK.
- Imperative mood - "Fix N+1 query" not "Fixed" or "Fixes"
- One fact per bullet. If a bullet needs two sentences, split it.
- Be specific: "Fix N+1 query in add_items loop" not "Optimize database performance"

**Kill these (AI tells):**
- "This PR introduces/ensures/implements/adds support for". Just state what changed.
- Parenthetical asides like "(this is context)". If it matters, say it directly. If not, cut it.
- "Additionally", "Furthermore", "Moreover". Start with the verb.
- Corporate words: "leverage", "utilize", "robust", "comprehensive", "streamline", "facilitate"
- Needless bold. Bold section headers, not random words mid-sentence.
- Passive voice when active works. "the query was optimized" → "optimize the query"
- Em dashes and dashes as sentence joiners. Use periods. Two short sentences beat one long dashed sentence.
- Parentheses. Rewrite as a separate sentence or drop entirely.

**No private details - the PR is visible to the whole org and sometimes beyond:**
- Customer org IDs, org/customer names, customer domains or emails, user IDs, request IDs from customer traffic → describe generically ("a large customer org", "one tenant's domain").
- Local branch names, local paths, your machine's setup → omit; only the PR's own branch and repo paths belong.

**When bold IS right:**
- Section headers (`### Why`)
- Bold lead-ins with colon (`**Root Cause:**`, `**Fork-safe cleanup:** explicitly close...`) - for key labels in prose sections
- Never bold for emphasis mid-sentence

### Visual formatting

PR descriptions should look clean on GitHub:

**Always use:**
- Code snippets with language tags (` ```python `, ` ```bash `) for commands, config, code patterns
- `- [ ]` checkboxes for QA items. A QA line without `[ ]` is WRONG.
- GitHub permalinks for code/file references. Link to the specific commit on the branch, not a line that will drift: `[file.py:42](https://github.com/org/repo/blob/<commit-sha>/path/to/file.py#L42)`

**Use when they earn their space (large/complex PRs):**
- `> [!NOTE]` / `> [!TIP]` / `> [!CAUTION]` callout blocks for important context
- `<details><summary>Click to expand</summary>...</details>` for long output, benchmarks, logs
- Tables for structured comparisons (before/after, benchmarks, field mappings)
- Mermaid diagrams for architecture or flow changes
- Reference related issues with `#number` - GitHub auto-shows status icons (green = closed, purple = open)

**Never:**
- Walls of text. Max 3 sentences per block, then break into bullets.
- A one-commit fix with badges and diagrams. Keep it proportional.

### QA quality

**Include QA only when a reviewer can do something before merge** - hit an endpoint, click a UI flow, run a migration against a copy. Pure refactors, test-only, CI, docs and config-only PRs get no QA section; a padded QA list is WRONG.

Each QA item names a concrete action + expected result. "Verify it works" is NOT a QA item. Never include running tests as a QA step - tests are covered by CI. Never include post-deploy items ("watch Sentry after release", "monitor error rate") - those aren't reviewer actions.

### Bullet granularity

What changed bullets should roughly match commit granularity. 3 commits = ~3 bullets, not 8 bullets expanding every file touched. The diff shows file-level details; bullets tell the story.

### House style - focused PRs (most PRs: a fix, a hardening, a feature slice)

- **Why leads with the cause and a hard number.** When the cause differs from the symptom, open with the one-line `**Root Cause:**` naming the mechanism and the limit or error: "CSV export runs inside the request and hits the 30-second gateway timeout." Then 1-2 sentences sizing it with real figures - counts, ratios, worst case: "Exports stream ~4,000 rows a second. Anything over ~120k rows fails; the largest tenant has 2.1M." Numbers beat adjectives.
- **Each Changes bullet is one sentence: verb → mechanism → visible effect.** "Move CSV export to a background job that emails a link, so 2M-row exports finish." Identifiers in backticks. A tracked-issue reference is the one allowed second sentence: `Fixes [ISSUE-ID](url).`
- **Related Issues say how each one relates,** not just that it exists. Group by source with bold sub-heads (**Sentry issues:**, **JIRA:**, **GitHub:**); each item is link - impact (event count) - where (function/endpoint) - symptom. Name the relation: same problem with a different fix, related but not covered here, or "Supersedes #N - that one retries; this one removes the cause".
- **QA always covers the triggering input and the behavior that must stay unchanged:** "Export a 2M-row report - a link arrives, no 504." and "Export a 50-row report - same file as before." Add a step per variant surface - another view, mode or entry point - when the change reaches it.

### House style - large PRs (new scripts, pipelines, migrations, performance work)

- **Headline metrics as badges** under the title when a number deserves the headline: `![speedup](https://img.shields.io/badge/speedup-21x-brightgreen)`.
- **Emoji h3 sections, `---` between them:** 📑 Ticket, 🚀 Overview, 📖 Description, 🔄 Pipeline, 🔧 Features, 📝 Usage, 📊 Performance - only the ones that earn their space.
- **Overview** is one sentence with the headline number in backticks, then `> [!NOTE]` with the before → after in production terms ("nightly backfill: 9 hours → 25 minutes").
- **Description** states the strategy in one sentence, then numbered steps with bold lead-ins. Side changes get one line each with their commit SHA.
- **Limitations** get a `> [!CAUTION]` one-liner plus a `<details>` block holding a `Field | Reason` table of what's not covered and why.
- **Flow** is a mermaid flowchart with one subgraph per stage, soft fills, no yellow.
- **Usage** is one bash block with one commented command per mode; operational caveats go in `> [!TIP]`.
- **Performance** is an `Instance | Size | Before | After | Speedup` table (speedup in bold), plus how it was measured and a link to the baseline run.

Public example of the plain Why/Changes voice: [Codex PR #31837](https://github.com/openai/codex/pull/31837) - verb-led bullets, zero filler.

### Before/after example

**Bad (AI-generated):**
```
## Overview

This PR introduces comprehensive improvements to the upload flow by ensuring
that file storage is properly delegated to the archive service. Additionally,
it implements robust error handling for the S3 copy operation, which was previously
not handled (causing silent failures in production). The changes also update the
related test suite to cover the new edge cases.
```

**Good (human):**
```
### Why

`copy_upload_to_archive` silently swallowed S3 copy failures.
Uploads succeeded but files never reached the archive.

### Changes

- Add retry + error propagation to `copy_upload_to_archive`
- Raise `ArchiveCopyError` on exhausted retries instead of logging and continuing
- Cover the retry and failure paths in `test_archive_tasks.py`
```

### Self-check (run before presenting)

Re-read the body one last time. For each sentence ask: "Would a senior engineer write this, or does it sound like AI?" Rewrite anything that fails. Specifically check:
- Any sentence starting with "This PR"
- Any parenthetical aside
- Any bold that isn't a section header or lead-in
- Any sentence over ~15 words

### Completion contract

The PR body is NOT done until:
1. **Why** section exists with 1-2 sentences plus the optional one-line Root Cause (not a restated diff) - in the large-PR shape, 🚀 Overview fills this role
2. **Changes** has verb-led bullets (not prose paragraphs) - in the large-PR shape, 📖 Description's numbered steps fill this role
3. **✅ QA Steps**, when present, has `- [ ]` checkboxes with concrete pre-merge actions; absent when there's no manual check (see QA quality)
4. Zero sentences start with "This PR introduces/ensures/implements"
5. Zero parenthetical asides
6. No walls of text (max 3 sentences per block)
7. Bullet spacing: blank lines between bullets when each has substantial text; no blank lines for short one-liners
8. Zero private details - no customer org IDs/names/domains, user IDs, or local branch names/paths

## Step 2b - Humanize (only with --humanize)

After generating the PR body, invoke the `/humanize` skill on the body text (pass `--concise` through when nicepr got `--concise`). This strips any remaining AI patterns (rule-of-three lists, contrast framing, self-narration, synonym cycling) that slipped through the writing rules. The humanized version replaces the original body before presenting.

## Step 3 - Present for Review

**Save the body to a per-repo, per-branch file.** Steps 4 and 5 post this exact file, so what the user approves is what reaches GitHub. The name carries both because parallel sessions would overwrite a shared path, and one ticket's branch name often exists in several repos. Record `BODY_FILE` as a literal alongside the Step 0 values:
```bash
BODY_FILE=/tmp/pr-body-<repo name from ORG_REPO>-<branch, with / replaced by ->.md
cat <<'EOF' > "$BODY_FILE"
<body>
EOF
```
After every edit the user requests, re-save the file before showing the new preview - posting a body that differs from the last preview is WRONG.

**Display:** Output the title and body as **direct text** in your response. Do NOT wrap in a code fence - the body contains inner code blocks that would break nesting. Do NOT use the Read tool for display (Read output collapses in the UI and the user won't see it). `BODY_FILE` is the fallback the user can `cat` if output is collapsed.

Show the title separately above the body. Ask: "Look good? Edit anything?"

Wait for user feedback before proceeding. Without `--create`/`--draft`, the run ends at the approved preview - "looks good" approves the text, it does NOT ask for a PR.

**Hard rules for preview:**
- QA items MUST use `- [ ]` checkbox syntax. A QA item without `- [ ]` is WRONG. Self-check before showing.
- When present, the QA section MUST be a `###` heading (`### ✅ QA Steps`), not inline or unstyled.
- The COMPLETE body must be shown every time the user asks to see it. Never show partial.
- Do NOT use the Read tool or `cat` via Bash to display the body. Output it as direct text.

## Step 4 - Create PR (only with --create / --draft, or when the user explicitly says to create the PR)

Creating a PR because the preview was approved, without `--create`/`--draft` or an explicit "create the PR", is WRONG.

Re-declare the Step 0 values (`BRANCH`, `FORK_REMOTE`, `GH_USER`, `UPSTREAM`, `ORG_REPO`, `BASE`) and `BODY_FILE` at the top of each command block - they do not survive between Bash calls.

Error if `FORK_REMOTE` is empty - never push to `origin` or upstream.

Before pushing, check for merge conflicts with base. Three-argument `merge-tree` prints conflict markers with a leading `+` (`+<<<<<<< .our`), so the pattern allows it:
```bash
git merge-tree $(git merge-base $UPSTREAM/$BASE HEAD) $UPSTREAM/$BASE HEAD | grep -qE '^\+?<<<<<<<'
```
If conflicts found, warn: "Branch has merge conflicts with $BASE. PR will show conflicts." Let user decide whether to proceed.

```bash
git push -u $FORK_REMOTE $BRANCH

gh pr create --repo $ORG_REPO --base $BASE --head $GH_USER:$BRANCH \
  --title "<title>" --body-file "$BODY_FILE"
```

`--draft` implies `--create`. If `--draft`: add `--draft`. If `--reviewers`: add `--reviewer <teams-or-users>`.

**Default reviewers.** Without `--reviewers` and without `--draft`, read the reviewer list from the local work settings file, and leave yourself out (GitHub refuses a review request from the PR's author):
```bash
jq -r --arg me <GH_USER login> '.reviewers // [] | if type == "string" then split(",") else . end | map(select(type == "string") | gsub("\\s"; "") | select(. != "" and ascii_downcase != ($me | ascii_downcase))) | join(",")' ~/.config/claude-skills/work.json
```
Non-empty output → add `--reviewer <output>` and name the reviewers in the reply. Empty output, or `Could not open file` (no work.json) → no reviewer flag. Any other jq error (the file is not valid JSON) → no reviewer flag, and say in the reply that `work.json` could not be read. A draft gets no default reviewers: they are asked for when the PR is marked ready, outside this skill.

## Step 5 - Update PR (only with --update)

Re-declare the Step 0 values (`BRANCH`, `FORK_REMOTE`, `ORG_REPO`) and `BODY_FILE` at the top of each command block - they do not survive between Bash calls.

```bash
gh pr view $BRANCH --repo $ORG_REPO --json number,title,body,url
```

If no PR found, error out. Push new commits first if any unpushed, then run Steps 0-2. Treat existing description as baseline - preserve manual edits, merge new changes in. Save the new body with the Step 3 save block, show the diff, confirm before updating.

```bash
git push $FORK_REMOTE $BRANCH

gh pr edit $BRANCH --repo $ORG_REPO --title "<new-title>" --body-file "$BODY_FILE"
```

## Guard Rails

- **Preview first.** Always show title + body before creating. Never auto-create.
- **Never push to upstream or origin.** Always push to fork remote.
- **Never force push.** If push fails, show error and ask.
- **No empty PRs.** If no commits ahead of base, error out.
- **JIRA link format.** Always `<JIRA_URL>/browse/<ID>`, where `JIRA_URL` is the `jiraBaseUrl` the `/jira` skill resolves in its Setup - never a guessed or hardcoded site.
- **QA items always use checkboxes** (the section itself is conditional - see QA quality). Every QA item uses `- [ ]`. A QA line starting with `- ` without `[ ]` is WRONG - the whole point is a clickable checklist on GitHub. Self-check: scan the QA section for bare `- ` before presenting.
- **No nested code fences in preview.** Output the body as direct text. Never wrap the body in a ```markdown fence when it contains inner code blocks - the inner ``` closes the outer fence and corrupts everything after it.
