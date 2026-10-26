---
name: triage
description: Triage a JIRA ticket to a proven root cause - ticket, Sentry, logs, live data and the code at the deployed SHA, competing causes decided by running their checks, load-bearing claims independently verified by darkmoon, and a ready-to-post ticket note. --fast skips the verification pass.
trigger: /triage
allowed-tools: Read, Grep, Glob, Skill, Bash(git log:*), Bash(git blame:*), Bash(git show:*), Bash(git grep:*), Bash(git cat-file:*), Bash(git rev-parse:*), Bash(git -C:*), Bash(gh search:*), Bash(gh api:*), Bash(find:*), Bash(grep:*), Bash(ls:*), Bash(date:*)
---

# /triage - JIRA Ticket Triage

Investigate a JIRA ticket end-to-end: fetch context, search logs, trace through code, decide between competing causes by running the checks that separate them, verify the conclusion independently, and produce a triage note plus a short ticket comment.

## Usage

```
/triage PROJ-1234             # triage by ticket ID
/triage <jira-url>            # triage by URL
/triage PROJ-1234 --fast      # skip the independent verification pass (Step 5) for a quick look
```

**Service catalog:** read `~/.config/claude-skills/services.md` in Step 1 - it names the log search skill, the data lookup skill, the GitHub org, and per service its repo, Sentry project, log service and notes (compiled frames, which frontend is which). Tracing without it is guessing; a value it lacks is asked for or marked inferred, never invented.

## Output contract - the triage is NOT done until it shows

1. **TL;DR** - three plain-language lines: what broke, why, the fix.
2. **Verdict and confidence** - `Confirmed` / `Likely` / `Can't-determine`, a confidence %, and `To reach certainty: <the one check> - ran it: <result>` or `- can't run here: <reason>`.
3. **Trigger and root cause** as two separate lines (Step 4), each with a SHA-pinned permalink.
4. **Evidence ledger** - every source from Step 4's list, each `checked: <result>` or `unavailable: <reason>`.
5. **Competing causes** - the top cause plus the alternates, each with its deciding check and that check's result.
6. **Verification line** - `Verified: N claims via darkmoon - U upheld, W weak, C can't-determine, R refuted` or `skipped (--fast)`.
7. **Introduced by** - the commit, its PR and ticket, and whether the PR was reviewed (regressions), or `not a regression` / `not determined`.
8. **Ticket note** (Step 7).

## Process

### Step 1 - Intake

Run these independent reads **in one message**: the service catalog, and the ticket via the `/jira` skill (its Get Ticket fields include linked issues and the parent; also run its **Linked PRs** lookup - an earlier fix attempt is evidence). Extract:
- **Error message** (summary, description, Sentry links)
- **Service hints** (which service/component is mentioned)
- **Stack trace** (file paths, line numbers, function names)
- **Time context** (when reported, when last occurred)
- **Reporter comments** (often contain reproduction steps or additional context)
- **Linked work** - linked tickets and PRs, with their state

Summarize ticket in 3-4 lines before proceeding.

### Step 1b - Fetch the Sentry Issue

Tickets often carry only a pasted error message - the Sentry issue holds the real stack trace, the deployed release, and the request_id.

- **Ticket links a Sentry issue** (permalink or SHORT-ID like `API-511`) → `/sentry <id>`.
- **No link** → `/sentry search "<exception value fragment>" 90d`. Free text is fuzzy: a row is a candidate only when its `type` and `value` both match the ticket, not the title alone. Run `/sentry <SHORT-ID>` on the candidate and confirm against its `exception` block - search rows carry window-scoped counts and no release or request_id. Note the match's `status`: resolved but recurring = regression. No confirmed match → record "no Sentry issue found (searched: <query>)" and continue.
- **Sentry unavailable** (credentials unset, `401`) → record "Sentry unavailable" in Evidence and continue to Step 2.

From the deep-dive (never from search rows), carry forward:
- **Still happening?** `lastSeen` + 24h trend. Last seen months ago = the bug may be fixed or dormant - say so.
- **Impact:** lifetime count + users.
- **`firstRelease`** - the deploy that introduced it; your regression suspect for Step 3. `null` (Python services) → no regression suspect from Sentry.
- **`request_id`** for Step 2, **`release`** (deployed SHA) for Step 3.
- **Event time** - the latest event's `dateCreated` (and `lastSeen`): the log window for Step 2.
- A ticket that says a fix already shipped → `/sentry fixed <id> <release>` tells you whether that deploy actually stopped it.

### Step 1c - Where did it throw? (gate)

Name the service that emitted the error **with evidence** before tracing any code: the Sentry project, the log service where the error appears, or the client bundle in the frames. Read the catalog's notes for look-alikes - two frontends with the same symptom, a server-side BFF whose logs are not browser errors. No evidence → list the candidate services and confirm one in Step 2 first. Tracing a service you have not confirmed is WRONG - it is how a bug in one frontend gets "fixed" in another.

### Step 2 - Search Production Logs

Use the catalog's **Log search skill** (`none` → note "logs unavailable: no log skill configured" and go to Step 3). Strategy:

1. **Identify services** from ticket context (error source, mentioned services, stack trace paths)
2. **Search errors** in identified services - with a Sentry event time from Step 1b, window around it (e.g. 1h either side of `dateCreated`); without one, start with `last 24h` and widen. A Sentry event days old searched over the default `last 24h` returns nothing - that empty result is a window error, not "no logs"
3. **Search specific error text** from ticket (exception class, error message substring)
4. **Run top-errors** if high error volume - identify dominant patterns
5. **Trace request** if request_id/trace_id available in the ticket or the Sentry event (Step 1b) - pass the event's window to the log skill's trace (log tools default to a recent window like `last 24h`)
6. **Check error rate** - use count or top-errors to estimate frequency (e.g., "~3,000 errors/hr" vs "2 in last 24h"). This determines impact scope and priority.

7. **Check live record state** if the ticket names a specific record (an ID or GUID of an asset, version, collection, user...) - use the catalog's **Data lookup skill** to read its current state (indexed? right owner? right type? fields intact?). `none` → list the record IDs under Open Questions.

Record what you find AND what you don't find. Absence of evidence matters.

If the log skill fails (unreachable host, VPN down, auth error), skip to Step 3 and note "logs unavailable: <reason>" in the triage output.

### Step 3 - Trace Through Code

Search `$WORKSPACE` for the code path. Run `ls "$WORKSPACE"` first to see available repos if unfamiliar.

1. **Start from the error** - find the exact file:line from stack trace or Sentry. With a Sentry release SHA, read the code **at that SHA** (sentry's Hand off section) - for a project the catalog marks **compiled**, frame lines point at the wrong source line; locate by function name.
2. **Trace the call chain** - follow function calls upstream and downstream
3. **Find the boundary** - where does the request cross service boundaries? (API calls, message queues, shared DBs)
4. **Check error handling** - how are errors caught, transformed, propagated? This is often where bugs hide (e.g. 404 wrapped as 500)
5. **Check recent changes** - `git -C "$WORKSPACE/<repo>" log --oneline -10 -- <relevant-files>` for recent modifications. With a Sentry `firstRelease`, list the commits leading up to that deploy: `git -C "$WORKSPACE/<repo>" log --oneline -15 <firstRelease> -- <relevant-files>`. SHA not local → `gh api "repos/<github-org>/<repo>/commits?sha=<firstRelease>&path=<file>&per_page=15"` (GitHub org from the catalog) - never `git fetch`. If the bug looks like it should've been caught already, check `git log --grep="<error-name>"` for prior fixes - could be a regression.
6. **Check git blame** - `git -C "$WORKSPACE/<repo>" blame <file> -L <start>,<end>` on suspicious lines (error handlers, status code mappings) to understand when and why they were written
7. **Check recent related work** - merged PRs from the last ~14 days that touch the same files or mention the error, across the org: `gh search prs --owner <github-org> --merged --merged-at ">$(date -d '14 days ago' +%F 2>/dev/null || date -v-14d +%F)" "<error fragment or function>"` (the `-v` form is macOS), plus the ticket's linked PRs from Step 1. A fix for a sibling error landed yesterday is either the cause, the fix, or a pattern to copy - say which.
8. **Introduced by (regressions)** - find the commit that introduced the faulty line (`git log -S '<code fragment>' -- <file>`, or blame), then its PR and review state: `gh api "repos/<github-org>/<repo>/commits/<sha>/pulls" --jq '.[0] | {number, title, merged_at}'` and `gh api "repos/<github-org>/<repo>/pulls/<number>/reviews" --jq '[.[].state]'`. Report the commit, PR, ticket key in its title, and whether it was approved - or that it went in with no PR.

Use `grep -r` and `find` broadly across `$WORKSPACE`, not just the current project. Bugs cross service boundaries. This step is crucial, take your time and be thorough.

**Do NOT checkout, fetch, pull, or modify any repo.** With a Sentry release SHA from Step 1b, that SHA is the truth - read files with `git show <sha>:<path>`. Without one, analyze whatever branch is currently checked out. If a repo is not on master/main, note it in the triage output (e.g., "Analyzed on branch `feature-x`, 3 commits ahead of master"). **And: the code that threw in prod may be a different deployed SHA than HEAD** - the error-time code is the truth, so if the analyzed code doesn't fit the symptom, suspect deployed≠HEAD and note it (don't trust HEAD as what ran).

### Step 4 - Decide Between Causes

**Evidence ledger first.** Before concluding, every source below must end as `checked: <result>` or `unavailable: <reason>` - the ticket and its linked work, Sentry, logs, live record state (when the ticket names a record), code at the deployed SHA, recent changes and recent related work. Leaving a source the session can reach unchecked is WRONG - the conclusion is only as good as the evidence it never looked at.

**Rank competing causes (don't anchor).** List the **2-3 most plausible candidates**, ranked - each **falsifiable**, with the *one check that distinguishes it* from the others. Anchoring on the first plausible trace and then self-confirming it is triage's main failure mode. Lead the note with the top, but name the live alternate(s).

**Run the deciding checks.** For each candidate, run its distinguishing check if the session can - a log query, a grep at the deployed SHA, a data lookup, a Sentry tag or breadcrumb. A runnable deciding check left unrun is NOT a valid stop: "90% sure" with the 100% check one command away is the hedge this step exists to remove. A check you can't run here → say why, and who or what can run it.

**Separate trigger from root cause.** `Trigger:` is what the user or system did that surfaced it; `Root cause:` is why the code allows it. A fix that only blocks the trigger leaves the bug - name both.

Be very thorough and critical, start reviewing your findings neutrally from another perspective now. If more than 50% of your root cause analysis is speculative, go back to step 3 and gather more evidence. If you can't get confirmation, say so honestly.

Before writing the triage note, explicitly categorize every claim:

- **Confirmed**: directly observed in logs, code, or error output
- **Inferred**: logically follows from confirmed facts but not directly observed
- **Speculative**: plausible but unverified

Then sanity check:
- **Can I name a red-capable repro this cause predicts** - one request/command/test that would go red on exactly this bug and green once fixed? If I can't even *describe* one, it's a hypothesis, not a confirmed cause - **cap the confidence** accordingly (the Reproduction Hint below isn't decoration; it's the test of whether you actually understand the cause).
- Does the root cause explain ALL the symptoms, or just some?
- Could this be a symptom of something deeper (e.g., 500s caused by DB saturation, not app code)?
- Is the error rate actually elevated, or is this normal baseline noise?
- Am I sure about the service boundary? Check the catalog's service notes - e.g. a server-side BFF's logs are not browser errors, and two frontends can show the same symptom - could be wrong

**Falsifier the top cause:** state *"this is wrong if `<X>`"* and check `<X>` - a targeted disproof of the *specific* cause, not just the general review above.

**Confidence comes with its path to certainty:** `To reach certainty: <the one check>` - and if that check is runnable here, run it now (see "Run the deciding checks") instead of reporting the gap.

### Step 5 - Independent Verification (skipped with `--fast`)

A conclusion checked only by the context that formed it is self-confirmed. Use the `Skill` tool to invoke **`/darkmoon --claims`** (always pass the `--claims` flag - without it darkmoon reads the transcript instead) with the root cause and the 3-5 claims it rests on, each as a verifiable claim: *"In `<repo path:line @ sha>`, <what is true>. Consequence: <what it causes>."*

Integrate the verdicts:
- **Refuted** → drop the claim. If it was the root cause or the trigger, return to Step 4 with the next candidate - once; after that, report `Can't-determine` with what is still open.
- **Weak** → downgrade to Inferred and add the skeptic's counter to the evidence.
- **Can't-determine** → keep as Inferred, plus what would settle it.
- **Upheld** → mark `(verified)`.

Re-state the confidence after verification. A `Confirmed` verdict needs its root cause Upheld.

### Step 6 - Output Triage Note

Include all necessary details, but make it concise. Every code/method/file link is a GitHub permalink pinned to a commit SHA (`https://github.com/<org>/<repo>/blob/<sha>/<path>#L<n>` - the Sentry release SHA when known, else the current `master`/`main` SHA from `git rev-parse`); a branch-name link (`/blob/master/`) rots and is WRONG. When sharing code snippets, make sure to format it with code blocks properly.

Format:

```
## Triage: <TICKET-ID> - <Title>

**TL;DR**
- Broke: <one plain line>
- Why: <one plain line>
- Fix: <one plain line>

**Verdict: <Confirmed | Likely | Can't-determine> · Confidence: <X>%**
To reach certainty: <the one check> - ran it: <result> | can't run here: <reason>
Verified: <N claims via darkmoon - U upheld, W weak, C can't-determine, R refuted> | skipped (--fast)

### Root Cause
Trigger: <what surfaced it>
Root cause: <why the code allows it - file:line permalinks>
Introduced by: <commit + PR + ticket, approved or not> | not a regression | not determined

### Competing Causes
1. <top cause> - deciding check: <check> → <result>
2. <alternate> - deciding check: <check> → <result> - why less likely

### Evidence
- [Confirmed] <fact from logs/code>
- [Inferred] <logical conclusion from confirmed facts>
- [Confirmed] Sentry: <SHORT-ID + permalink, lifetime events/users, last seen, 24h total/peak, firstRelease> - or "no Sentry issue found (searched: <query>)" / "Sentry unavailable"

| Source | Result |
|---|---|
| Ticket + linked work | checked: <...> |
| Sentry | checked: <...> / unavailable: <reason> |
| Logs | checked: <...> / unavailable: <reason> |
| Live record state | checked: <...> / not applicable / unavailable: <reason> |
| Code at deployed SHA | checked: <sha> |
| Recent changes + related PRs | checked: <...> |

### Affected Services
<list of services involved, helps ops/oncall scope the impact>

### Call Chain
<service-a> → <service-b> → <service-c>
<with specific endpoints/functions at each hop>

### Recommendations
1. <Fix with specific file and what to change - aimed at the root cause, not only the trigger>
2. <Secondary fix if applicable>

### Reproduction Hint
<One-liner on how to reproduce, e.g., "Hit GET /api/orders/{nonexistent-id} with a valid user token">

### Open Questions
- <Anything you couldn't verify>

### Debugging Walkthrough (only if confidence >= 80%)
<One paragraph explaining the key debugging technique that cracked this. Focus on the reusable insight, not the specific bug. E.g., "The 500 looked like a backend crash, but checking error transformation middleware revealed all upstream errors were wrapped as InternalServerError. Always check error handlers when status codes don't match the actual error.">
```

### Step 7 - Ticket Note (always)

After the triage note, draft a short comment for the Jira ticket - what a teammate reads, not the full analysis:
- **Facts only:** Confirmed root cause (or `Can't-determine` + what would settle it), impact (Sentry counts / error rate), the fix location. No alternate causes, no speculation, no debugging walkthrough.
- **SHA-pinned permalinks** for every code reference (same rule as Step 6).
- **5-10 lines**, plain hyphens, no headings beyond one bold lead-in per item.

Show it and stop. Posting it is a separate, explicit user request (then use `/jira comment`) - this skill stays READ ONLY.

## Rules

- **NEVER fake confidence.** If you're not sure, say "I don't know" with what you'd need to verify.
- **READ ONLY** Do not modify any codes, write comments in JIRA, resolve or assign Sentry issues, or anything except for fetching, thinking and analyzing.
- **Search broadly.** Don't assume the bug is in one service. Cross-service bugs are common.
- **Check error handlers.** Error transformation (wrapping, re-throwing, status code mapping) is the #1 source of misleading errors.
- **Time matters.** Ticket filed 3 months ago? Current logs may not reflect the original bug. Say so.
- **Don't over-scope.** Triage identifies the problem and points to the fix. It doesn't implement the fix.
