---
name: litmus
description: Verify one specific claim against the actual code - Confirmed / Refuted / Can't-determine, backed by cited deterministic evidence (grep, AST, command output; or an authoritative doc for version/API/deprecation facts), never an eyeball trace or training-memory guess. Settles findings from reviews, PR comments, or agent assertions.
trigger: /litmus
allowed-tools: Bash(grep:*), Bash(rg:*), Bash(git rev-parse:*), Bash(git remote:*), Bash(git log:*), Bash(git show:*), Bash(git diff:*), Bash(git blame:*), Bash(gh api:*), Read, WebFetch, WebSearch
---

# /litmus - claim verifier (settle it against the code)

Takes a **specific claim** (or a list of them) and checks each against the real code with a **mechanical** check whose output it shows. Replaces "I'm 95% sure" eyeball-tracing with `grep`/AST/command evidence. Externalizes aristarchus's Confirmed-vs-Inferred gate as a standalone tool.

## Usage

```
/litmus <the claim to verify>
/litmus <paste a list, or a triage's Evidence / Root-Cause block>   # verifies each claim separately
```

Examples of claims worth verifying - a aristarchus `Critical`, a jury `⚑ contested` / singleton row, a human PR comment, an agent's confident assertion, or a whole triage's evidence list:

```
/litmus upload_thumbnail never catches ImageTooLargeError
/litmus can_user_edit_document has only one caller
/litmus the new --dry-run flag is never read after being parsed
```

## Step 1 - Parse the claim(s)

- If the input holds **multiple claims** (a list, or a triage's `Evidence` / `Root Cause` block - often already tagged `[Confirmed]`/`[Inferred]`), extract each as its own proposition and **number them**. Existing tags are the *author's* assertion, not evidence - re-verify from scratch. Then run Steps 2-3 **independently per claim**; one claim's verdict never leans on another's.
- Restate each claim in one line as a **falsifiable proposition** - "X never catches Y", "Z has N callers", "this branch is unreachable". Echo it back so the user can correct a misread before you spend a check on the wrong thing.
- **Classify it:**
  - **Structural** (reachability, callers, import surface, where an exception is raised, dead code, type flow, "defined but unused", call-graph paths) → litmus's strong suit; proceed.
  - **Behavioral / runtime** (deadlock, race condition, OOM-under-load, timing, "this is slow", anything needing execution semantics) → litmus **cannot settle this structurally.** Say so up front and **stop** with `Can't-determine (behavioral)` rather than dressing up a guess as proof. (A static check can't decide whether two subprocesses deadlock; don't pretend.)
  - **Data / operational** (live row/asset counts, "no errors in logs", env or index state) → deterministic, but not in the *code*. litmus is a **code** verifier - return `Can't-determine` and **point at the kind of tool that settles it**: a log search for log claims, an index/asset query (e.g. an OpenSearch count) for data claims. Name a concrete skill only as an example if one fits the repo. Don't eyeball it as Confirmed, and don't pull those queries into litmus - that's scope creep into another tool's lane.
  - **External-factual** (a version/API removed-added-deprecated, a documented default - about the wider ecosystem, not this repo: "batch/v1beta1 removed in K8s 1.25") → verifiable, but against authoritative docs, not the code. Route to the web check (Step 2). **NOT** for fuzzy claims ("X is best practice", "Y is faster") - no authoritative deterministic source → decline like behavioral.

## Step 2 - Run the mechanical check (mandatory - no verdict without it)

Pick the cheapest deterministic check that decides the claim, **run it, and keep the output** - it's the evidence:

- **`grep`/`rg`** for symbols, callers, imports, string usage, `except`/`catch` clauses, flag reads. The workhorse.
- **AST / language tooling** when text search is ambiguous (overloaded names, scoping) - `ast.grep`-style or the repo's own tooling.
- **A command's output** when the claim is about behavior of a tool/config (`--help`, a config dump) and it's safe/read-only.
- **Authoritative web doc** - *external-factual claims only.* `WebFetch` the official doc / changelog / release-notes / spec (`WebSearch` to find it) and **quote the exact line.** **Authoritative sources ONLY** - a blog / StackOverflow / forum is NOT evidence (the eyeball-bluff one step removed); if that's all there is → `Can't-determine`. **Pin the version**: fetch the doc for the *claimed* version, quote it with version + date (deprecations move). **Never assert from training memory** - it's stale on versions; fetch or `Can't-determine`.

Rules that make the check trustworthy:
- **Search the whole relevant scope, not the diff.** Over-flagging happens when "one caller" / "unused" is judged from one file while the real usage lives elsewhere. Grep the repo (and cross-repo if the claim spans services).
- **One negative grep is not proof of absence** - confirm the symbol name, import alias, and re-export spelling are what you searched (e.g. the class may be imported under an alias, the caller may use `getattr`/reflection), **and that you searched the whole tree, not one subdir.** A monorepo with a legacy + active layer (e.g. `app/` vs `app_v2/`) hides a symbol from a too-narrow scope - absent from one path ≠ absent from the repo. Note dynamic-dispatch escape hatches you can't see.
- **Never substitute reasoning for the check.** If you didn't run a command, you don't have a verdict - that's the exact failure (confident agent, no grep) litmus exists to prevent.
- **Documented-behavior is the trap (external-factual).** A discrete fact (version removed/added, API deprecated) with a crisp authoritative entry is safe to confirm. A "behavior Y happens" claim is risky - confirm ONLY if the doc states it explicitly; never infer behavior from doc-silence → `Can't-determine`. And verify the claim **as stated**; if its relevance needs the repo's *own* version ("and so this repo is affected"), note "applies only if the repo targets ≥X - check `Chart.yaml`/CI", don't auto-re-derive it.

## Step 3 - Verdict

```
## litmus - <Confirmed ✓ | Refuted ✗ | Can't-determine ?>
Claim: <one-line falsifiable restatement>

Evidence:
$ <the command you ran>
<the decisive lines of output>

Reading: <what that output proves, 1-2 lines>
Confidence: <high | medium> - <the residual gap, if any (dynamic dispatch, reflection, scope not searched)>
```

- **Confirmed** - the check positively supports the claim. **Refuted** - the check contradicts it. **Can't-determine** - structurally undecidable, the check is ambiguous, behavioral, or data/operational; say which, and for the last two name the tool that *can* settle it. Don't bluff.
- **Confidence caps at `medium` when a dynamic escape hatch exists** (reflection, `getattr`, string-built calls, runtime registration) - structural search can't see those. Be honest about the ceiling; an overconfident verdict is the thing this skill is meant to kill. **External-factual (web) verdicts also cap at `medium`** - fetched docs carry misread / staleness / version risk that a local grep doesn't.
- **Cite locatably.** A code `file:line` in the evidence → render as a **GitHub permalink pinned to the verified SHA**: `https://github.com/<owner>/<repo>/blob/<sha>/<path>#L<n>`. Resolve `<owner>/<repo>` via `gh api repos/<remote-owner>/<remote-repo> --jq '.source.full_name // .full_name'` (maps a **fork → its canonical upstream** so the link works from a fork/worktree). Read `<remote-owner>/<remote-repo>` off `git remote -v` and try the remotes in turn until one call succeeds - there may be no `origin`, and a deleted or private colleague fork returns 404; `<sha>` = `git rev-parse HEAD`. **Confirm the sha is on the upstream** (`gh api repos/<owner>/<repo>/commits/<sha>` → 200) *before* linking; a 404 (unpushed local commit) or no GitHub remote → plain `path:line`, never a broken/fabricated URL. An external-factual verdict → cite the **authoritative doc URL** + the quoted line. Keep the `$ command` + output too - that's the reproducible proof; the link is the locator.
- Keep it to the claim. Don't review the surrounding code (that's aristarchus) or judge minimality (that's occam).
- **Multiple claims:** emit one verdict block per claim, in order, then a closing summary table - `# | claim | verdict` - so a long evidence list is scannable at a glance. Don't merge the claims into a single conclusion.

## Guard Rails

- **No verdict without shown evidence.** A claim "checked" by reasoning alone is not checked - paste the command and its output or return `Can't-determine`.
- **One verdict per claim - never blend.** A list is fine (verify each in its own evidence block); what's forbidden is collapsing several claims into one fuzzy conclusion.
- **Decline behavioral claims** rather than guessing - structural verifier, honest about its boundary.
- **Read-only.** litmus searches and reads; it never edits, stages, or runs mutating commands.
