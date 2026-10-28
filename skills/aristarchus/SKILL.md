---
name: aristarchus
description: Deep GitHub PR review - JIRA context, stack-aware traps, severity-tagged findings, 5 independent review lenses, darkmoon verification. Use --fast to skip the agent steps (research, lenses, tracing, cross-repo check, verification).
trigger: /aristarchus
allowed-tools: Read, Grep, Glob, Skill, Agent, EnterWorktree, ExitWorktree, Bash(gh pr view:*), Bash(gh pr checkout:*), Bash(gh api repos/*), Bash(gh pr diff:*), Bash(gh auth status), Bash(git fetch:*), Bash(git diff:*), Bash(git cat-file:*), Bash(git checkout --detach:*), Bash(git remote -v), Bash(jq:*), Bash(date:*), Bash(printenv WORKSPACE), Bash(cd:*), Bash(grep:*), Bash(cut:*), Bash(ls:*), Bash(bash ~/.claude/skills/aristarchus/parse-findings.sh:*)
---

# /aristarchus - GitHub PR Code Review

Analyze PR diffs file-by-file, produce a structured review with categorized findings. Uses `gh` for all GitHub interaction.

## Usage

```
/aristarchus <github-pr-url>          # full review: all 5 lenses + darkmoon verification
/aristarchus <url> --fast             # quick pass - see Step 1 for what it skips
```

**Lenses** (always run unless `--fast`): saboteur, simplifier, reader, security, operator. See Step 6a for briefs.

## Prerequisites

- **`$WORKSPACE`** is exported, pointing at the directory holding your local clones. Every review checks out the PR in a worktree of `$WORKSPACE/<repo>`; Step 6c reads the infra/config repo(s) there. `$WORKSPACE` unset → stop and ask the user to export it; guessing a clones directory is WRONG.
- **`gh auth status`** passes.
- **Skills:** `/darkmoon` (with the `darkmoon-skeptic` agent) and `/fathom`. `/jira` is optional - without JIRA credentials the review continues with no ticket context.

## Step 1 - Parse Input

Record the start time: `date +%s` via Bash. This is used in Step 9 to show total elapsed time.

Run `printenv WORKSPACE`. If empty, **stop** and tell the user to `export WORKSPACE=<dir containing their clones>` - an unset value makes `$WORKSPACE/<repo>` resolve to `/<repo>`, and the "repo missing" error would blame the wrong cause.

- No args → ask for a PR URL.
- Strip `--` flags before processing. `--fast` skips Steps 3b, 6a, 6b, 6c, and 8 (config research, lenses, library tracing, cross-repo check, darkmoon). Default (no flag) runs all of them.

## Step 2 - PR Metadata and JIRA Context

Fetch metadata first (one call), then extract JIRA from it:
```bash
gh pr view <url> --json title,body,author,baseRefName,headRefName,additions,deletions,changedFiles,commits,reviewRequests,statusCheckRollup,labels
```
Read the title/body, each commit message to understand intent. **A mismatch between stated intent and actual changes is itself a finding.** When the PR body makes verifiable claims about the code's behavior (ordering, flow, error handling), spot-check each against the actual code. Claims about production data or incidents are unverifiable from code - note them as accepted context, not confirmed facts.

Extract a ticket ID (`[A-Z]+-\d+`) from `headRefName` + `title`. If found, fetch it with the **`/jira` skill** (`/jira <TICKET-ID>`) - don't hand-roll auth. Capture summary, description, acceptance criteria, comments, and **linked issues** (`issuelinks`, outside `/jira`'s default fields). This is the *why* behind the change. Keep essentials only; don't retain raw JSON. If none found or it fails, continue - the header's `JIRA` field records which.

**Ticket supplied by the caller.** When the invocation includes a `Ticket context:` block, use it as the fetched ticket and skip `/jira`. pr-watch fetches the ticket outside the review session so the Jira token never reaches it; the block carries the same fields listed above. The header's `JIRA` field reads `<ID> supplied`.

## Step 3 - Worktree Setup

Repo name from the URL (e.g. `owl-api`). If `$WORKSPACE/<repo>` is missing, **stop with an error** - tell the user to clone the repo. Do NOT fall back to diff-only.

`cd "$WORKSPACE/<repo>"` → use `EnterWorktree` (NOT raw `git worktree add`) with a **unique name** (`pr-<number>-review-<short-nonce>`) so parallel reviews of the same PR don't collide → checkout the PR head **detached** (avoids "branch already checked out" collisions and fork-remote issues - a clone may have no `origin`):
```bash
gh pr checkout <url> --detach \
  || { up=$(git remote -v | grep -m1 '<owner>/<repo>' | cut -f1); git fetch "$up" pull/<number>/head && git checkout --detach FETCH_HEAD; }
```
All later file reads use worktree paths. After review, `ExitWorktree` with `action: "remove", discard_changes: true` - the checkout is read-only and disposable, and its commits are the PR's own (already on the remote), so the harness "unsaved work" guard would otherwise block removal.

**Unless `--fast`:** run Steps 4, 5, and 7 HERE as their parallel batch - the lens base context needs the diff and conventions, and Step 3b scans the diff. Then run Step 3b (if applicable), then launch Step 6a lens agents, Step 6b library tracer, and Step 6c cross-repo checker per their respective instructions, before starting Step 6. With `--fast`, Steps 4, 5, and 7 run in their normal place.

## Step 3b - Config Change Research (skipped with --fast)

Detect whether the diff touches configuration or infrastructure settings. Do not skip based on your reading of the PR body.

**Detection:** scan the changed file paths and diff content for:
- File paths containing `config`, `settings`, `mapping`, `index_config`, `schema`, `.env`, `.yml`, `.yaml`, `.toml`, `.ini`, `.conf` - excluding `.github/` (CI workflows aren't runtime settings)
- Diff lines changing values in dict/object literals with keys like `dynamic`, `replication`, `timeout`, `cache`, `ttl`, `retry`, `batch_size`, `max_`, `min_`, `policy`, `strategy`, `threshold`
- Any value changed from one named option to another (e.g., `true` → `strict`, `warn` → `error`, `async` → `sync`)

**If detected:** spawn one `Agent` and wait for its result before launching the lenses (they need its output) to research the setting. The agent's prompt:

> *"Search the web for the tradeoffs of [specific setting/value]. Use these exact queries:*
> 1. *`[technology] [setting] vs alternatives tradeoffs comparison`*
> 2. *`[technology] [setting] [chosen value] vs [other values] when to use which`*
>
> *Produce a comparison table of ALL documented options for this setting with columns: Option | Behavior on [relevant edge case] | When to use | Risk. Cite sources. Do NOT recommend one option - present the facts for a human to decide."*

Step 3b is complete when the research agent returns a comparison table with **≥2 options** and **≥1 cited source**. If the agent fails or returns no table, note `config research: failed` in the review header and proceed without - do not block the review.

The research output (the comparison table + sources) is stored and passed verbatim to ALL debiased lens agents as additional context under the heading **"Config research (from official docs):"**.

**If not detected:** skip this step. Most PRs are business logic and don't need it.

## Step 4 - Load Repo Conventions

**Steps 4, 5, and 7 are independent - fire all three as parallel tool calls in ONE message.** Step 6 runs after all three complete. Without `--fast` they already ran in Step 3 - don't refetch.

The target repo's own `CLAUDE.md` is **authoritative** - it documents the team's conventions and gotchas and overrides the generic traps below. Read `./CLAUDE.md` and `./.claude/CLAUDE.md` from the worktree. A change that violates a documented convention is a finding. If repo rules contradict anything here, the repo wins. **Record what you loaded** (file + rough rule count, or "none found") for the output header - this makes the step verifiable. When a convention applies to this diff, don't just check compliance - trace the risk it prevents. A convention like "schema migrations in a separate PR" exists because manual deployment steps are required. Compliance (separate PR ✓) doesn't mean the risk is mitigated - the deployment step can still be missed. Ask: could this change trigger the risk this convention was written to prevent, even while technically complying?

## Step 5 - Diff and File List

Read the diff from the worktree, not from `gh`: `gh pr view --json files` silently stops at 100 files and `gh pr diff` fails above 300. (`gh pr diff` stays for reading a companion PR in another repo, e.g. in Step 6c.) Get the base once, then write its SHA literally into each command (shell variables don't survive between Bash calls):
```bash
gh pr view <url> --json baseRefOid,baseRefName --jq '"\(.baseRefOid) \(.baseRefName)"'
git cat-file -e <baseRefOid>^{commit} 2>/dev/null || git fetch "$(git remote -v | grep -m1 '<owner>/<repo>' | cut -f1)" <baseRefName>
git diff --name-only <baseRefOid>...HEAD
git diff <baseRefOid>...HEAD
```
The three-dot diff is what GitHub shows: the PR's changes since it branched, not unrelated commits on the base.

Filter out lock files, compiled (`*.min.js`, `dist/**`, `build/**`), generated (`__generated__/**`); report the count. **Do NOT filter migrations** (irreversible, bug-prone). Review **highest-risk files first** (auth, migrations, payments, core models).

**Budget tiers by file count:**
- **≤20 files**: review all.
- **21-50 files**: review all, batch by directory (5-8 files per batch). Don't carry raw diff forward between batches.
- **>50 files**: review all top-risk files (auth, migrations, payments, core models, services). Sample remainder by directory. **Log what was skipped** (file count + directory names) - silent truncation is invalid.

## Step 6 - Analyze Changes

**Stack traps** - codebase-specific gotchas a capable model won't infer from the diff. Apply only the traps whose language or framework appears in the diff; the list below comes from Python and TypeScript stacks, so a repo on another stack adds its own in its `CLAUDE.md`. A finding's **location** must be a `file:line` in this diff - a finding about code this diff does not change carries the `pre-existing` flag and keeps its severity (see Severity below). Files outside the diff (scripts, callers, configs) are valid **evidence** for a finding but not its location. Skip anything `CLAUDE.md` (Step 4) or the linter already owns.

- **Concurrency**: read-modify-write on shared state without a lock/OCC - TOCTOU. Retried/redelivered work that isn't idempotent - Celery `acks_late`, a queue consumer with no dedup or exactly-once guard.
- **Multi-tenancy**: cross-org leaks where route auth middleware doesn't run - Celery jobs, queue consumers, admin/open-api routes. Confirm org filtering.
- **Migrations**: schema/OpenSearch-mapping change must deploy before dependent code; backfills idempotent and reversible.
- **Cross-service**: API or event-schema (RabbitMQ) contract changes, shared model/enum changes - confirm consumers won't break.
- **SQLAlchemy**: `.first()` silently returns `None` (use `.one()`/`.one_or_none()`); lazy relationship in a loop = N+1 (`joinedload`/`selectinload`); a Celery task that never closes its session holds it open and blocks migrations.
- **Cost model changes**: when a function's *implementation* changes in a way that affects per-call cost - cached → uncached, relationship → per-call query, O(1) → O(n), in-memory → network, batch → per-item - trace callers to check for **amplification**. A function that's called once is fine; the same function called 12 times via `@property` chains, in a loop, or during serialization turns a small cost increase into a latency regression. The diff won't show the callers (they didn't change) - grep for them. Real example: replacing a cached SQLAlchemy relationship read with a per-call `db.session.query()` looked like an optimization in the diff, but the function was called about a dozen times per request via `@property` accessors in a different file, turning one cached query into a dozen uncached ones.
- **Mongoose**: `aggregate()`/`bulkWrite` bypass soft-delete plugin hooks - filter `deleted` manually; never build a query from user-controlled keys/operators (`$where`, raw filters) - NoSQL injection.
- **Async JS**: `async` callback to `Array.forEach`/`map`/`filter` runs unawaited - errors swallowed (the `no-misused-promises` lint rule flags it - check whether it is on).
- **Types**: index access is really `T | undefined` (unless `noUncheckedIndexedAccess` is on); external payloads (`http.get<T>()`, `JSON.parse`, queue messages) are unvalidated - verify the shape.
- **React**: stale closure in a `setInterval`/subscription; fetch in an effect with no cancellation lets a slow response overwrite a newer one.
- **Idempotent initializers**: when the diff changes configuration consumed by a create-if-not-exists pattern (`indices.create(ignore=400)`, `CREATE TABLE IF NOT EXISTS`, `ON CONFLICT DO NOTHING`, `get_or_create`), the change will NOT apply to existing instances - only new ones. Flag as deployment risk: what happens if the manual sync/migration step is missed? Trace the deployment path: is the update applied automatically on deploy, or does it require a manual script? If manual, what's the failure mode when it's forgotten? Also check any tests that validate this config - a test creating a fresh instance from the config dict does NOT verify the live instance matches. A test comparing code-vs-code (Python dict to Python dict) doesn't protect against code-vs-live-system drift. If the JIRA ticket describes a past incident with specific affected fields/components, replay it: walk through each failure item and simulate whether this PR's change would have made the outcome better, worse, or the same - a fix that makes the original incident's failure mode harsher is a finding.

For each file (or batch):
1. Read the diff hunk, then the source ±20 lines around it (`offset`/`limit`). **Batch multiple file reads as parallel tool calls in one message** - don't read file 1, wait, read file 2, wait. The harness runs them concurrently.
2. **Caller tracing** - trace callers when: (a) a function's **signature** changes (parameters, return type), (b) a function's **cost model** changes (caching behavior, query pattern, complexity class - see "Cost model changes" trap above), (c) the function is a **shared utility or public API**, or (d) the diff adds a **new function called from a file under `processors/`, `consumers/`, `workers/`, `tasks/`, `handlers/`, `subscribers/`, `listeners/`, `jobs/`, `commands/`, or `cron/`** (these are bulk-invocation entry points). For signature/API changes, trace **one** level (grep the name, read 2-3 top callers). For cost model changes, trace **two** levels and specifically check for amplification patterns: is the function called in a loop, via `@property`/getter chains, during serialization/`to_dict()`, or N times per request? Call-count × cost-delta = the actual regression. For new functions called from event/queue processors: grep the repo's `scripts/` directory and any batch/migration scripts for references to the **module or class** containing the new function - these scripts are indirect callers that won't show up in a function-name grep but determine the function's real-world invocation volume.
3. **Test coverage (do this for every changed file - don't skip):** map changed functions/branches → does a test exercise each? Note what's covered and call out each new/changed branch or early-return with no test. CI green ≠ covered - a new untested branch passes CI silently. For conditional fields (fields only emitted under certain data conditions), check whether test fixtures exercise the condition that triggers emission - simple fixtures with default data may pass while production data triggers unmapped/untested paths. Also ask: what does this test NOT protect against? A test comparing code-vs-code (e.g., translator output vs config dict) doesn't protect against code-vs-live-system drift.
4. Beyond the traps, apply judgment across bugs, security, perf, design, refactor, tests, naming, cross-service. If the prompt names a focus, weight to it but don't ignore the rest.
   - **For `Design` findings, use the deep-module lens** (`/fathom`): is the changed module deep or shallow (interface size vs behavior)? does a new interface/seam have ≥2 things varying across it, or is it speculative? would it pass the deletion test? Name shape findings in that vocabulary (deep/shallow/seam) - but they cap at `warning` per the severity rule, never `critical`.
   - **For `Necessity` findings - does each behavioral change in this diff need to exist?**
     - **Redundant mechanisms**: if the PR introduces 2+ mechanisms to achieve the same goal, flag the redundancy. Ask: "If mechanism A exists, does mechanism B add value beyond what A already provides?" A fix that works through two independent paths is suspicious - one path is usually sufficient and the other adds complexity for marginal benefit.
     - **Reliance on chance**: does a mechanism depend on an event that isn't guaranteed to occur (re-deliveries, retries, cache invalidation, eventual consistency) when a deterministic alternative exists in the same PR? Flag "hope and pray" fixes where correctness depends on operational luck.
     - **Unjustified complexity**: did the diff introduce conditional skipping or mode-dependent behavior that makes the reader ask "why?" If the justification isn't obvious from the code or comments, it's a smell worth flagging.
     - Necessity findings cap at `warning`.

**Tag every finding** with one of `Bug|Security|Perf|Design|Simplicity|Necessity|Refactor|Tests|Naming|Cross-service` at an exact `file:line`. The tag is the `<Tag>` field of the Step 9 header; `Confirmed`/`Inferred` and any source (`source:library`, `source:cross-repo`, `lens:<name>`) go in the finding's verification line, never the header.

**Confirmed vs Inferred:** `Confirmed` means you verified *every link* in the chain in the code/docs AND showed the evidence (the grep output, the line read, the doc cited). **A finding without its shown evidence caps at Inferred, never Confirmed** - if you didn't show the verification, it's not verified regardless of how obvious it seems. If the finding rests on *assumed* behavior of a library, OS, runtime, or tool (pipe buffers, subprocess/threading semantics, framework internals) that you have **not** verified, it's `Inferred` - say what you'd need to check to confirm it. **Exception:** if Step 6b (library source tracing) ran and the agent traced the execution path through the unpacked library source with cited `file:line` evidence, the finding may be `Confirmed` - the library source IS the verification.

**Stack-trap confirmation rule:** A stack-trap pattern match is `Inferred` until you read ±10 lines around the match and verify the consequence is real. Pattern-match alone is NOT `Confirmed` - the pattern may be guarded on the next line. When the finding depends on library/framework behavior (e.g., "health_check_interval doesn't cover BRPOP", "control.ping uses pub/sub not the task queue"), it stays `Inferred` unless Step 6b traced the library source and confirmed the mechanism. Stating what the library does without reading its source is an assumption, not evidence.

**Severity** is what goes wrong if the finding is ignored - never how sure you are (that is Confirmed/Inferred and darkmoon's verdict):

| Severity | Means | Examples |
|---|---|---|
| `critical` | Data loss, security breach, outage, corruption, or breaks prod/build/tests - nothing else | auth check skipped on a new endpoint; lock held across a network call on a hot path; migration that drops a column still read |
| `warning` | Wrong behavior on a reachable path, or a risk the author should fix: a race, a missing guard, a deploy hazard, a failure-mode regression, changed logic with no test, a design or perf problem with a concrete cost | two jobs can run the same cleanup at once; retry on 4xx; new branch untested; a business rule enforced in one of two places |
| `nit` | No behavior change: naming, style, comments, an optional refactor | rename for clarity; extract a helper; a docstring that repeats the code |

A finding that changes behavior is never a `nit`, however small. One exception the other way: a comment or docstring that misstates what the code or a library does is a `warning` - it misleads the next person who trusts it. **A Critical must be `Confirmed`** (verified mechanism) - an `Inferred` finding caps at `warning`, however bad it would be if true. Unsure between critical and warning → warning. Design and necessity findings cap at `warning`.

**Pre-existing is a flag, not a severity.** A finding on a line this diff does not change keeps its severity and gets the `pre-existing` flag in its header. It is still reported - a serious bug the PR's context exposes stays serious - but listed last within its severity.

## Step 6a - Independent Review Lenses (skipped with --fast)

Five independent review perspectives the main review may miss. **This is discovery, not verification** - verification happens in Step 8.

**Timing:** Step 3b (config research) runs first if applicable - launch it and wait for its result, because the lens agents need its output. Then lens agents are launched in background. They run in parallel with the main analysis. After Step 6 completes, wait for all agent notifications - do NOT poll, sleep, read task output files, or use TaskOutput. These calls will fail because background agents use the Agent notification system, not the Task system. The system delivers notifications automatically as `task-notification` messages. **Do NOT emit the final review until ALL lens agent notifications have arrived.** If you write output before lens results arrive, you cannot integrate them - this defeats the purpose of running lenses. Wait.

**Independence is structural.** Spawn one `Agent` instance per lens (using the `Agent` tool, NOT Explore - Explore is read-only search, not analysis) - each runs in a fresh context with NO access to the main review's findings or each other's. A single model wearing multiple hats in the same context shares confirmation bias; separate agents don't.

**Context bifurcation - not all lenses get the same context.** PR descriptions anchor LLM reviewers, reducing issue detection by 16-93% ([research](https://arxiv.org/abs/2603.18740)). Prompt-based debiasing ("verify these claims", "don't accept at face value") does not work - the anchor is in the context. The fix is structural: withhold the anchor from lenses that must reason about consequences from code, not from the author's story.

Each agent receives the **base context**: the diff, the changed file paths, the repo `CLAUDE.md` conventions, and the JIRA ticket summary (one line - just the ticket title, NOT the full description). Each agent reads the full source of every changed file (bugs live in new-vs-existing-code interaction, not just within the diff).

**Anchored lenses** (Simplifier, Reader) ALSO receive the PR body + commit messages. They need author intent to judge clarity and complexity justification.

**Debiased lenses** (Saboteur, Operator, Security) do NOT receive the PR body, commit messages, or JIRA description. They must form their own assessment of what the code does and whether it's correct from the diff and surrounding code alone. If Step 3b produced config research results, include them verbatim under the heading `Config research (from official docs):` in the debiased lens prompts.

**Agent brief templates (prepend to the agent's prompt, before the lens-specific brief):**

*Anchored lenses (Simplifier, Reader):*
> *"You are a read-only reviewer. Do NOT run tests, build commands, or execute code - analyze by reading source and grepping only. The PR author claims the following intent and design rationale:"*
>
> Followed by the PR title, body, and commit message subjects.

*Debiased lenses (Saboteur, Operator, Security):*
> *"You are a read-only reviewer. Do NOT run tests, build commands, or execute code - analyze by reading source and grepping only. You have intentionally NOT been given the PR description, commit messages, or author's rationale. Assess this code change purely on its own merits by reading the diff and the surrounding code. Form your own understanding of what changed and why before evaluating whether it's correct. Do not seek out or infer the author's intent - your value is in the independent assessment.*
>
> *If you receive a 'Config research (from official docs)' section below, it contains web-sourced documentation about the configuration settings changed in this diff. Use this research as your primary source of truth for evaluating the change - it overrides any assumptions you have about which option is 'better.' Present the documented alternatives in your findings and let the reviewer decide which fits their system."*

**Available lenses (briefs are fixed, not softenable):**

1. **Saboteur** (`saboteur`) - *"You are a production incident investigator. For each changed function: what's the worst input? What if the external call fails/times out? What if this runs twice, concurrently, or never? What if neither branch is correct? When the diff changes a system's failure mode (e.g., silent degradation → hard rejection, or vice versa), flag it as a warning. Before concluding, investigate the domain impact: grep the codebase to understand what user-facing feature the changed component powers, what happens to end users when the new failure mode triggers, and whether retries/alerts/fallbacks exist. Trace data origins: if the changed code path receives data from external sources (user uploads, API responses, third-party feeds), check whether the field set is fully controlled - a blocklist/exclude pattern lets novel external fields through, and tightened validation (e.g., strict schema) would reject them. Name consequences at BOTH levels: (a) infrastructure ('write rejected') AND (b) user-facing ('user loses access to the feature this powers'). Do not resolve which failure mode is better - present both sides and let the reviewer decide. If config research is provided, cross-reference the documented risks with the actual codebase impact you found. Hunt: races, resource leaks, swallowed errors, silent data corruption, failure mode regressions. When you identify a failure mode (e.g., CrashLoopBackOff, deadlock, queue backup), trace what the failed component DOES - grep for what it schedules, consumes, or serves, and name the specific downstream operations that stop. If nothing real breaks, say so - do not manufacture concerns. End with `reviewed_paths:` and every file you read in full or grepped."*

2. **Simplifier** (`simplifier`) - *"You are reviewing this diff for unnecessary complexity. For each new function, class, task, or abstraction: (a) Does it have a single call site? If so, does the indirection earn its keep - what behavior does it add that the caller couldn't do inline? (b) Trace the full downstream call chain to the actual work (I/O, mutation). Flag any layer that only forwards args or wraps a single call. Can the caller skip it and talk to a deeper layer directly? (c) Could the same goal be achieved with fewer moving parts - a parameter on an existing function, inlining into an existing scope, removing a branch the general case already covers? For each finding, show the simpler alternative - don't just say 'this is complex', show what the code looks like without the extra layer. If the approach is already minimal, say so."*

3. **Reader** (`reader`) - *"You are a developer joining this team next month. For each changed function: could you modify it in 6 months with no context? Hunt: unclear names, logic spanning 3+ files with no docs, magic values, god-functions, implicit knowledge only the author has, tests that assert implementation details instead of behavior. If the code is clear, say so."*

4. **Security Auditor** (`security`) - *"You are a penetration tester reviewing this change. Go deeper than OWASP basics: privilege escalation, IDOR, trust-boundary crossings, authz gaps on new endpoints, data exposure in logs/error responses, timing side-channels. Skip injection and hardcoded secrets (the linter catches those). If nothing real is exploitable, say so."*

5. **Operator** (`operator`) - *"You are an SRE who will be paged when this code breaks at 3am. For each changed function: what scripts, batch jobs, cron tasks, or bulk operations in this repo could trigger it? Grep the `scripts/` directory and any migration/backfill files for references to the module, class, or entry point being changed. If you find bulk callers, reason about the actual scale they operate at - does this code create write storms, hold locks, consume unbounded resources, or compound with concurrent invocations when those callers run? Are there operational knobs (throttling, batch size, feature flags) to control the blast radius? If nothing breaks at scale, say so - do not manufacture concerns."*

**After all lenses complete:**
- Merge findings. Deduplicate by `file:line`: 2+ lenses on the same location become one finding that names every lens that raised it. Agreement is evidence, not impact - it does not raise the severity.
- Each lens finding goes into the output format of Step 9 like any other, `Inferred` until Step 8's darkmoon verification upgrades it; its verification line names the lens (`*Inferred - raised by the saboteur lens; ...*`).
- **Lens severity is a floor.** The main review may promote a lens finding (nit → warning) but may NOT demote one. The main review is anchored by the PR body; debiased lenses are not. A debiased lens flagging a warning that the main review wants to downgrade is the system working as designed - the anchoring is exactly what the lens was meant to counteract. The floor binds the main review only: Step 8 darkmoon verdicts override it, since darkmoon is independent of the anchor.
- A lens that returned no findings is noted in the output: *"<Lens>: no findings."*
- The Saboteur's `reviewed_paths:` line is kept verbatim under its lens entry, so the reader sees what it did not read.

Output as **Independent Review Lenses** section after findings.

## Step 6b - Library Source Tracing (skipped with --fast)

When the diff changes how a framework or library is used - not just business logic - the review's findings often rest on *assumed* library behavior that no one verified. This step downloads and unpacks the library at the exact pinned version and traces the actual execution path through its source.

**Timing:** Launch as a background `Agent` alongside the Step 6a lenses (from Step 3, once the diff is loaded). Wait for its notification before writing the final review, same as lenses.

**Detection - when to trigger:** Scan the diff for ANY of:
- **Framework config dicts** - keys consumed by a library, not by repo code (e.g., `BROKER_TRANSPORT_OPTIONS`, `DATABASES`, `CACHES`, `LOGGING`, `REST_FRAMEWORK`, `ELASTICSEARCH_DSL`, ORM `Meta` class attributes)
- **Library method calls not defined in this repo** - `app.control.ping()`, `db.session.execute()`, `index.create()`, `s3.put_object()` - grep the repo for the method definition; if absent, the behavior lives in the library
- **Comments claiming library behavior** - "kombu does X", "redis-py calls Y", "SQLAlchemy will Z" - claims that can only be verified by reading the library source

If none detected, skip this step. Most business-logic PRs don't need it.

**Version extraction:** Parse the pinned version from the PR's own lockfile (in the worktree, not local - after `EnterWorktree` the working directory IS the worktree, so the paths are relative):
```bash
# Python - the optional [...] matches extras pins like requests[socks]==2.31.0
grep -m1 -iE "^<package>(\[[^]]*\])?==" ./requirements.txt | cut -d= -f3 | cut -d' ' -f1
# Node - .packages is lockfile v2/v3, .dependencies is v1
jq -r --arg p "<package>" '(.packages["node_modules/" + $p].version) // (.dependencies[$p].version) // empty' ./package-lock.json
```
If no lockfile or no pin found, note `library tracing: version unknown, skipped` and proceed without.

**Getting the source:** download and unpack, never install. Python: the wheel (or source tarball) from PyPI's JSON API. Node: `npm pack`, which runs no scripts for a registry package. Installing a source package executes its build code, and the version comes from the PR under review. The agent handles this internally - aristarchus's own `allowed-tools` does not need expanding because `Agent` subagents have full tool access.

**Agent prompt (spawn one background `Agent`, NOT Explore):**

> *"You are a library source tracer. Your job is to verify what a library ACTUALLY does, not what the code comments or PR description CLAIM it does.*
>
> *Setup - download and unpack the library source at the exact pinned version. Shell variables do not survive between Bash calls: run `mktemp` once, note the printed path, and write that literal path into every later command (download, grep, cleanup) in place of `$tmpdir`:*
> ```bash
> tmpdir=$(mktemp -d /tmp/aristarchus-lib-trace-XXXXXX) && echo "$tmpdir"
> # Python - download and unpack only; never pip install (installing a source package runs its build code, and the PR picks the version)
> url=$(curl -sS --fail-with-body "https://pypi.org/pypi/<package>/<version>/json" | jq -r '([.urls[] | select(.packagetype=="bdist_wheel")][0].url) // ([.urls[] | select(.packagetype=="sdist")][0].url)')
> curl -sSL --fail-with-body "$url" -o "$tmpdir/pkg" && { python3 -m zipfile -e "$tmpdir/pkg" "$tmpdir/src" 2>/dev/null || tar -xzf "$tmpdir/pkg" -C "$tmpdir"; }
> # Node - source lands in $tmpdir/package
> npm pack "<package>@<version>" --pack-destination "$tmpdir" && tar -xzf "$tmpdir"/*.tgz -C "$tmpdir"
> ```
>
> *For each claim or config change in the diff, trace the execution path through the unpacked source:*
> 1. *Grep the unpacked source for the config key, method name, or class referenced in the diff*
> 2. *Follow function calls UP TO 2 hops deep. If the chain is deeper, report what you found and what the next hop would need to check*
>
> *For each claim, report:*
> - *What the diff/comment CLAIMS the library does*
> - *What the library source ACTUALLY does (cite unpacked-source `file:line`)*
> - *Whether they match, and if not, what the consequence is*
>
> *After tracing, clean up (literal path from setup - an empty `$tmpdir` here deletes nothing):*
> ```bash
> rm -rf /tmp/aristarchus-lib-trace-<suffix from setup>
> ```
>
> *If the download fails (private package, network error), report `library tracing: <package> unavailable` and stop - do not guess.*

Pass the agent: the diff, the changed file paths, and the specific claims/config keys to trace. Include the worktree path so it can read the changed files.

**After the agent completes:**
- Merge findings into the main review. Each is `Confirmed` with `source:library` in its verification line - these are evidence-grade because the agent read the actual source.
- Library-traced findings that contradict a diff comment are `warning` minimum (a comment lying about library behavior misleads future maintainers).
- If the agent found no contradictions, note in the output: *"Library source tracing: no contradictions found in `<packages>`."*
- If the agent failed (download error, network), note: *"Library source tracing: skipped (`<reason>`)."*

## Step 6c - Cross-Repo Check (skipped with --fast)

When the diff touches infra files (`charts/`, `deploy/`, `workers/`, `tasks/`, k8s manifests), grep the infra/config repo(s) that deploy this code for references to changed components. This catches deployment mismatches invisible from the PR's repo alone (e.g., worker command structures, playbook assumptions, alerting rules).

**Which repos:** the ones the target repo's `CLAUDE.md` names; else the `$WORKSPACE` repos whose name contains `config`, `infra`, `deploy`, `ops`, `terraform` or `helm` (`ls "$WORKSPACE"`).

**Timing:** Background `Agent`, launched alongside 6a/6b. If no such repo exists on disk, skip and note: *"Cross-repo check: no infra/config repo found, skipped."*

**Agent prompt:**

> *"Grep `<infra repo path(s)>` (ansible playbooks, scripts, terraform, helm values, alerting rules) for references to the components changed in this diff. Focus on:*
> 1. *Worker/service command structures - do flags, subcommands, and arguments match what the diff assumes?*
> 2. *Alerting rules that monitor the changed component*
> 3. *Scripts or playbooks that reference the changed module or entry point*
>
> *For each mismatch, cite `repo/path:line` and state what breaks. If no mismatches, say so."*

Each finding is `Confirmed` with `source:cross-repo` in its verification line. Deployment mismatches are `warning` minimum.

## Step 7 - Existing Comments

Fetch existing feedback so you don't repeat it - inline comments, review bodies, and conversation comments (bots often post summaries in the latter two). Write the owner and repo from the PR URL literally: `gh` fills `{owner}/{repo}` from the current directory's remote, which in a fork clone is the fork, not the PR's repo.
```bash
gh api repos/<owner>/<repo>/pulls/{number}/comments --paginate --jq '.[] | {path, line, body}'
gh api repos/<owner>/<repo>/pulls/{number}/reviews --paginate --jq '.[] | select(.body != "") | {user: .user.login, body}'
gh api repos/<owner>/<repo>/issues/{number}/comments --paginate --jq '.[] | {user: .user.login, body}'
```
`--paginate` is required - without it GitHub returns only the first 30. Each command prints one JSON object per line; the fetched count is the total line count across all three, not an eyeballed estimate. Drop any finding already raised by a human or bot; note the count skipped. **Done when the header's `Existing comments` field is filled** (count fetched + how many of your findings it deduped) - that field is this step's proof-of-execution, so it can't be silently skipped.

## Step 8 - Independent Verification (skipped with --fast)

**Why this exists.** A reviewer cannot honestly grade its own findings - the same reasoning that produced the finding will rationalize it when asked to self-check. Verification runs in a **fresh, independent context** (darkmoon) that sees the findings + code but not the reviewer's reasoning chain.

**Before writing output, use the `Skill` tool to invoke `/darkmoon --claims`** (NOT an Explore agent - Explore is for search, not verification; its skeptic reports back asynchronously, so wait for that result before integrating any verdict) with the findings formatted as verifiable claims. Each finding becomes a claim:
> "In `file.py:42`, [what's wrong]. Consequence: [what breaks]."

**Always pass findings after the `--claims` flag** - without it darkmoon treats the text as a focus topic and extracts from the transcript (the review answer isn't in the transcript yet when darkmoon runs). Darkmoon runs in the worktree so it can verify against the actual source.

**Integrate verdicts:**
- **Refuted** → drop the finding from the findings list; it survives only as a count in the header's **Verified** line.
- **Upheld** → keep as-is. End its verification line with `(verified)`.
- **Weak** → keep its severity (Weak is about the evidence, not the impact), add the skeptic's counter to the finding body, and end the verification line with `(weak)`. A Weak `nit` is dropped and counted under refuted in the **Verified** line.
- **Can't-determine** → keep, but cap at `warning`, note what would settle it, and end the verification line with `(unresolved)`.

**A Critical that darkmoon marks Weak or Can't-determine is downgraded to Warning.** Only Upheld findings may be Critical in verified output.

**Completion contract:** verification is done when every finding has a darkmoon verdict integrated. A finding with no verdict when verification is active is a bug in the review process.

**Quality rules (always apply, verified or not):**
- **Confirm you actually loaded the repo `CLAUDE.md` (Step 4) and existing comments (Step 7).** If not, do it now - they change findings.
- A finding on a line this diff does not change gets the `pre-existing` flag in its header and keeps its severity (see Severity in Step 6).
- Substance over cosmetics: one real null-deref/auth gap beats ten style notes.
- State what's *wrong* and its consequence, not what the diff changed. No hedging.
- If you decided something isn't a bug, delete it entirely - no withdrawn findings in the output.
- Don't claim test coverage is adequate unless each changed branch has a test.

## Step 9 - Output

**Terminal-first formatting.** Output renders in a monospace terminal, not GitHub. Use **bold** for emphasis (renders in terminal), `---` for separators. Do NOT use `##`/`###` headings (render as literal `##` in terminal). Use markdown tables ONLY when all columns are short and similar width (≤3 columns, values under ~20 chars) - wide/uneven tables render broken in terminal; use bullet lists instead.

**The format is a contract.** `references/output-example.md` is a complete review in this format; `parse-findings.sh` checks it, and tools such as pr-watch read findings through it. Follow the example's finding headers, summary list and verification lines exactly.

**Order:** header, `---`, "What this PR does", findings summary, `---`, detailed findings **grouped by severity** (criticals first, then warnings, then nits; pre-existing findings last within their severity), `---`, Independent Review Lenses (if run), `---`, Library Source Tracing (if run), `---`, Cross-Repo Analysis (if run), `---`, Summary. Omit empty sections.

Header (5 lines + `---`):
```
**Review: PR #<n> - <title>**
**Author**: @user | **Base**: <base> <- <branch> | **Files**: N changed (+A, -D)
**CI**: passing|failing|pending | **Reviewers**: names (parse `reviewRequests`: `__typename: User` → login, `__typename: Team` → name)
**Filtered**: N files skipped (N sampled) | **Conventions**: <CLAUDE.md source> (N rules)|none | **Existing comments**: N fetched (M deduped) | **JIRA**: <ID> fetched|<ID> supplied|none found|failed
**Verified**: N claims via darkmoon - U upheld, W weak, C can't-determine, R refuted (dropped, including Weak nits) | skipped (--fast)
---
```
The **Verified** counts come from Step 8's ledger and must sum to N, with a Weak nit (dropped from the findings) counted under refuted, so the `weak` count equals the findings marked `(weak)`; a review that ran Step 8 without this line is incomplete - the user should see verification happened without re-running `/darkmoon`.
**What this PR does** - 1 sentence from YOUR reading of the diff, describing what the code changes actually do. Do NOT paraphrase the PR body - if your sentence resembles it, you're echoing. The PR body explains *why*; this sentence states *what changed* mechanically.

**Findings summary** - two lines per finding, numbered like the detailed findings and severity-grouped. Every detailed finding has a line here and nothing else does. This is the at-a-glance triage list:
```
🛑  #1  file.py:42
    Null pointer dereference on empty user input

⚠️  #2  indexing.py:128
    update_by_query unbounded - one large tenant can match millions of docs

✏️  #3  test_file.py:42 (pre-existing)
    Bare == without assert - dead assertion
```

**Detailed findings** - each finding is self-contained. Separated by `---`. The header is always `<emoji>  **#N · <severity> · <Tag> · <path:line>**`, with ` · pre-existing` before the closing `**` for a finding outside this diff. The severity word is what tools read; the emoji is for people and must match it: 🛑 critical, ⚠️ warning, ✏️ nit.

Critical and warning findings:
```
⚠️  **#2 · warning · Bug · file.py:42**

**Problem:** One-line statement of what's wrong.
**Impact:** One-line statement of why it matters.

**Fix:**

\```python
# suggested fix code
\```

*Confirmed - [evidence: what was verified and how].* (verified)
```

Nits:
```
✏️  **#3 · nit · Naming · file.py:120**

One-line suggestion.

*Confirmed - [evidence].* (verified)
```

Rules:
- **Severity order.** Group by severity: criticals (🛑), then warnings (⚠️), then nits (✏️). Within each group, sort by file order, with pre-existing findings last.
- **Problem/Impact split.** Every warning and critical separates the problem (what's wrong) from the impact (why it matters). Keep each to one line.
- **Fix included.** Every warning and critical includes a concrete code suggestion. Nits may omit it if the fix is obvious.
- **Inline comparisons.** When a finding compares options, flows, or behaviors: use a markdown table ONLY if ≤3 columns with short values. Otherwise use a bullet list:
  `- **Option A:** deterministic, no cost on old events`
  `- **Option B:** relies on re-delivery, full ES write on every old event`
- **Verification note.** The last line of each finding, never the header: `*Confirmed - [evidence].*` or `*Inferred - [what would confirm it].*`. When verification ran, the line ends with darkmoon's verdict in parentheses: `(verified)` for Upheld, `(weak)` for Weak, `(unresolved)` for Can't-determine.

**Finding synthesis** - before writing the summary, check whether 2+ findings undermine the same safety claim. If so, synthesize into one higher-order argument (e.g., "deployment gap + test checks code-vs-code only + conditional fields untested = claimed protection is illusory"). A synthesis that changes the recommendation is a finding in itself.

**Summary** - 2-3 sentences, then the verdict block:

```
**Recommendation:** ✅ Approve | 💬 Comment | ❌ Request Changes
**Reason:** One line - the driver(s) behind the recommendation.
**Confidence:** High/Medium/Low - one clause why (e.g. "traced the call chain + verified" vs "no caller tracing").
```

Pick one: ✅ Approve (nothing material), 💬 Comment (warnings/nits), ❌ Request Changes (any `critical`). After the verdict block, add a `---` separator (blank line before it so markdown renders the rule), then the elapsed time on the next line: run `date +%s` and subtract the Step 1 start time - display as `**Time taken**: Xm Ys`.

**Check the format before printing.** Pass the full draft review to the checker on stdin and fix every problem it prints, then re-run it until it prints `parse-findings: ok`:
```bash
bash ~/.claude/skills/aristarchus/parse-findings.sh --check <<'REVIEW'
<the draft review>
REVIEW
```
It checks each finding header, that the emoji matches the severity word, that the summary list and the detailed findings carry the same numbers, and that the `(verified)`/`(weak)` counts match the **Verified** line. Printing a review that fails the check is WRONG: tools read findings through it, and a malformed review posts nothing or the wrong thing.

**Completion contract - the review is NOT done until:**
1. Every finding has `file:line` + severity + `Confirmed`/`Inferred` note
2. Conventions field shows what was loaded (or "none found")
3. Existing comments field is filled - count fetched + deduped
4. Summary includes Confidence + Recommendation
5. Summary states **what was NOT examined** (e.g., "scripts/ not grepped", "sampled 30 of 55 files") - a clean review with unstated scope gives false confidence
6. Library source tracing status is noted - ran (packages + finding count), skipped (reason), or N/A (no library calls detected)
7. Cross-repo analysis status is noted - ran (repos checked + finding count), skipped (reason), or N/A (no related repos configured)
8. JIRA field is filled - ticket fetched, supplied, none found, or failed
9. `parse-findings.sh --check` printed `parse-findings: ok` on the final review

## Guard Rails

- **Read-only by instruction.** aristarchus never modifies the reviewed codebase, never posts comments, never approves or requests changes. It produces a review in the terminal - the user decides what to do with it. Note: `Bash(gh api repos/*)` is granted for reading PR comments and would match `gh api repos/... -X POST` - add `permissions.deny` rules to your Claude Code settings to block gh writes (`gh api` with `-X`/`--method`/`--field`/`--raw-field`/`--input`, `gh pr review`, `gh pr comment`; short `-f`/`-F` stay allowed so GraphQL reads work) even under `--dangerously-skip-permissions`. Without those deny rules the guarantee is prompt-only.
- **Always use `EnterWorktree`** - never raw `git worktree add`. The worktree is disposable and read-only.
- **`gh` auth required** - if `gh auth status` fails, stop and tell the user to run `gh auth login`.
- **Always clean up the worktree** via `ExitWorktree`, even if interrupted.
