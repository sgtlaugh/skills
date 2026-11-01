---
name: triage
description: Triage a JIRA ticket - a bug to a proven root cause (Sentry, logs, live data, code at the deployed SHA, competing causes decided by running their checks), or a question ticket to a short answer per ask. Bottom line first, load-bearing claims verified by darkmoon, facts only a person can see asked for before answering, and a ready-to-post ticket note. --fast skips the verification pass.
trigger: /triage
allowed-tools: Read, Grep, Glob, Skill, Bash(git log:*), Bash(git blame:*), Bash(git show:*), Bash(git rev-parse:*), Bash(git -C:*), Bash(gh search:*), Bash(gh api:*), Bash(find:*), Bash(grep:*), Bash(ls:*), Bash(date:*), Bash(wc:*)
---

# /triage - JIRA Ticket Triage

Investigate a JIRA ticket end-to-end and answer what it asks: a bug gets a proven root cause, a question gets an answer per ask. Either way the reader sees the answer first, and the evidence after.

## Usage

```
/triage PROJ-1234             # triage by ticket ID
/triage <jira-url>            # triage by URL
/triage PROJ-1234 --fast      # skip the independent verification pass (Step 5) for a quick look
```

**Service catalog:** read `~/.config/claude-skills/services.md` in Step 1 - it names the log search skill, the data lookup skill, the GitHub org, and per service its repo, Sentry project, log service and notes (compiled frames, which frontend is which). Tracing without it is guessing; a value it lacks is asked for or marked inferred, never invented.

## Output contract - the triage is NOT done until it shows

The order is fixed: the answer first, the evidence last ("bottom line up front"). Everything above `Details` fits on one screen: **at most 15 lines before the ticket note** - count them before showing; more is WRONG, and the excess moves under Details. A table cell holds at most 15 words; anything longer is a bullet, since a long cell wraps into an unreadable block in a terminal.

**Both shapes, top to bottom:**
1. **Head** - the shape's head block (bug: TL;DR + verdict; question: the ask + the answer table), Step 6.
2. **Needs you** - facts only a person can get (Step 4's gate) and decisions that are yours (policy, owner, priority). `none` when empty.
3. **Ticket note** (Step 7), passing its word count.
4. **Details** - the rest, below a `### Details` heading: the evidence ledger (every Step 4 source as `checked: <result>`, `not applicable` or `unavailable: <reason>`), the verification line (`Verified: N claims via darkmoon - U upheld, W weak, C can't-determine, R refuted` or `skipped (--fast)`), and the open questions. Details is the last section: nothing follows it.

**Bug shape adds, under Details:** trigger and root cause as two lines (root cause with a SHA-pinned permalink), competing causes with each deciding check and its result, introduced-by (commit, PR, ticket, reviewed or not - or `not a regression` / `not determined`), the emitting service with its evidence (Step 1c), and a reproduction hint (or `none describable`).

**Question shape adds, under Details:** per ask, the evidence behind its answer (permalink, doc link, command and output).

## Process

### Step 1 - Intake

Run these independent reads **in one message**: the service catalog, and the ticket via the `/jira` skill with its comments (its Get Ticket fields include linked issues and the parent; also run its **Linked PRs** lookup - an earlier fix attempt is evidence). Extract:
- **Error message** (summary, description, Sentry links)
- **Service hints** (which service/component is mentioned)
- **Stack trace** (file paths, line numbers, function names)
- **Time context** (when reported, when last occurred, any deadline)
- **The asks** - every question still open: who asked it, of whom, and when. An ask answered later in the thread is not open.
- **Linked work** - linked tickets and PRs, with their state

**Pick the shape** and say which in one line:
- **Bug** - the ticket reports something broken: an error, a stack trace, a Sentry link, a wrong result. Run every step.
- **Question** - the ticket asks how something works, whether it is supported, or what to do, with no failure to explain. Steps 1b, 1c and 2 run only for an ask that is about an error; Step 3 grounds each ask in the code instead of tracing a stack. Root cause, competing causes, introduced-by and a reproduction hint do not apply - forcing them onto a question is WRONG.

A ticket that reports a failure AND carries open asks gets the question head, since the asks are what someone is waiting on: the failure's cause is answered as one of the asks, every step still runs, and the bug-shape fields (trigger, root cause, introduced-by, reproduction hint) go under Details.

Summarize the ticket in 3-4 lines before proceeding: for a question, the ask in one line first - who needs what, by when, and why.

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
5. **Check recent changes** - `git -C "$WORKSPACE/<repo>" log --oneline -10 -- <relevant-files>` for recent modifications. With a Sentry `firstRelease`, list the commits leading up to that deploy: `git -C "$WORKSPACE/<repo>" log --oneline -15 <firstRelease> -- <relevant-files>`. SHA not local → `gh api "repos/<github-org>/<repo>/commits?sha=<firstRelease>&path=<file>&per_page=15"` (GitHub org from the catalog) - never `git fetch`. When `firstRelease` is null or the Sentry status is resolved, always run `git log --grep="<error-name>"` for prior fixes - could be a regression.
6. **Check git blame** - `git -C "$WORKSPACE/<repo>" blame <file> -L <start>,<end>` on suspicious lines (error handlers, status code mappings) to understand when and why they were written
7. **Check recent related work** - merged PRs from the last ~14 days that touch the same files or mention the error, across the org: `gh search prs --owner <github-org> --merged --merged-at ">$(date -d '14 days ago' +%F 2>/dev/null || date -v-14d +%F)" "<error fragment or function>"` (the `-v` form is macOS), plus the ticket's linked PRs from Step 1. A fix for a sibling error landed yesterday is either the cause, the fix, or a pattern to copy - say which.
8. **Introduced by (regressions)** - find the commit that introduced the faulty line (`git log -S '<code fragment>' -- <file>`, or blame), then its PR and review state: `gh api "repos/<github-org>/<repo>/commits/<sha>/pulls" --jq '.[0] | {number, title, merged_at}'` and `gh api "repos/<github-org>/<repo>/pulls/<number>/reviews" --jq '[.[].state]'`. Report the commit, PR, ticket key in its title, and whether it was approved - or that it went in with no PR.

Use `grep -r` and `find` broadly across `$WORKSPACE`, not just the current project. Bugs cross service boundaries. Step 3 is done when you have the throwing file:line at the analyzed SHA, the call chain to the service boundary, and the error handler on that path read; for a question, when each ask has the file:line, doc page or command output that answers it. A missing item goes to Open Questions.

**Do NOT checkout, fetch, pull, or modify any repo.** (Backstop: `Bash(git -C:*)`, `Bash(find:*)` and `Bash(gh api:*)` are prefix grants that would also let a checkout, fetch, commit, file deletion or an API write through, so this rule holds by instruction only unless your Claude Code settings deny them: `git -C` with `checkout`, `fetch`, `commit` or `push`, `find` with `-delete`, `-exec` or `-execdir`, and `gh api` with `-X`, `--method`, `-f`, `-F`, `--field` or `--input`.) With a Sentry release SHA from Step 1b, that SHA is the truth - read files with `git show <sha>:<path>`. Without one, analyze whatever branch is currently checked out and pin to its `git rev-parse HEAD`, which must exist on the remote. If a repo is not on master/main, note it in the triage output (e.g., "Analyzed on branch `feature-x`, 3 commits ahead of master"). **And: the code that threw in prod may be a different deployed SHA than HEAD** - the error-time code is the truth, so if the analyzed code doesn't fit the symptom, suspect deployed≠HEAD and note it (don't trust HEAD as what ran).


### Step 4 - Decide

**Evidence ledger first.** Before concluding, every source below must end as `checked: <result>`, `not applicable` or `unavailable: <reason>` - the ticket and its linked work, Sentry, logs, live record state (when the ticket names a record), code at the deployed SHA, other local repos and config under `$WORKSPACE` (infrastructure, configuration and deployment repos hold what the service code doesn't: secrets handling, routes, DNS, env), recent changes and recent related work. Leaving a source the session can reach unchecked is WRONG - and so is stating something a local repo could settle without opening it.

**A fact only a person can see is asked for, not guessed.** When the check that decides an answer needs access this session doesn't have - a vendor dashboard (Cloudflare, AWS console), a customer's DNS or account, an admin screen - ask for that one fact under Needs you, with the exact place to look (`dash.cloudflare.com > <zone> > SSL/TLS > Custom Hostnames > <hostname>: Status and Certificate columns`). Finish the other asks in the same run. Until the user replies with the fact, the answer that depends on it is not in the ticket note, is never labelled proven, and sits under Needs you. Inferring it from docs and outside probes and presenting that as the answer is WRONG: an inference that flips once the person looks costs more trust than the minute it takes them to look.

**Bug shape - rank competing causes (don't anchor).** List the **2-3 most plausible candidates**, ranked - each **falsifiable**, with the *one check that distinguishes it* from the others. Anchoring on the first plausible trace and then self-confirming it is triage's main failure mode. Lead with the top, but name the live alternate(s).

**Run the deciding checks.** For each candidate (bug) or each answer (question), run its deciding check if the session can - a log query, a grep at the deployed SHA, a data lookup, a Sentry tag, a doc page. A runnable deciding check left unrun is NOT a valid stop: "90% sure" with the 100% check one command away is the hedge this step exists to remove. A check you can't run here goes through the person-only gate above.

**Bug shape - separate trigger from root cause.** `Trigger:` is what the user or system did that surfaced it; `Root cause:` is why the code allows it. A fix that only blocks the trigger leaves the bug - name both.

Before writing the output, explicitly categorize every claim:

- **Confirmed**: directly observed in logs, code, error output, or a check you ran
- **Inferred**: logically follows from confirmed facts but not directly observed
- **Speculative**: plausible but unverified

**Claims about people.** "X said Y", "X's answer was wrong", "this contradicts what X told the customer" is a claim like any other: it needs X's words quoted with the date and where they were written, and it goes to darkmoon in Step 5. Without the quote it is dropped. Saying a colleague was wrong in the ticket note is never the default - it goes there only when the user asks for it.

Start reviewing your findings neutrally from another perspective now. If the root cause (bug) or an answer (question) is Speculative, go back to Step 3. A second pass still Speculative -> `Can't-determine` for that item.

Bug shape, sanity check:
- **Can I name a red-capable repro this cause predicts** - one request/command/test that would go red on exactly this bug and green once fixed? If I can't even *describe* one, it's a hypothesis, not a confirmed cause - **cap the confidence** accordingly.
- Does the root cause explain ALL the symptoms, or just some?
- Could this be a symptom of something deeper (e.g., 500s caused by DB saturation, not app code)?
- Is the error rate actually elevated, or is this normal baseline noise?
- Am I sure about the service boundary? Check the catalog's service notes - a server-side BFF's logs are not browser errors, and two frontends can show the same symptom.

**Falsify the top cause or answer:** state *"this is wrong if `<X>`"* and check `<X>` - a targeted disproof of the *specific* claim, not just the general review above.

**Confidence comes with its path to certainty:** `To reach certainty: <the one check>` - and if that check is runnable here, run it now instead of reporting the gap.

### Step 5 - Independent Verification (skipped with `--fast`)

A conclusion checked only by the context that formed it is self-confirmed. Use the `Skill` tool to invoke **`/darkmoon --claims`** (always pass the `--claims` flag - without it darkmoon reads the transcript instead) with the 3-6 claims the answer rests on, each verifiable: *"In `<repo path:line @ sha>`, <what is true>. Consequence: <what it causes>."* Include every claim about a person (Step 4), with its quote and source.

Integrate the verdicts:
- **Refuted** → drop the claim. If it was the root cause, the trigger or an answer, return to Step 4 with the next candidate - once; after that, report `Can't-determine` with what is still open.
- **Weak** → downgrade to Inferred and add the skeptic's counter to the evidence.
- **Can't-determine** → keep as Inferred, plus what would settle it.
- **Upheld** → mark `(verified)`.

A check darkmoon can't re-run (a live `dig` or `curl`, a dashboard read the user gave you) is labelled `self-run, not independently verified` with the command and its output shown - never `(verified)`. Re-state the confidence after verification. A `Confirmed` verdict needs its root cause Upheld.

### Step 6 - Output

Write the head for the shape, then Needs you, then the ticket note, then Details - the contract's order. Every code/method/file link is a GitHub permalink pinned to a commit SHA (`https://github.com/<org>/<repo>/blob/<sha>/<path>#L<n>` - the SHA actually read: the Sentry release SHA when known, else `git rev-parse HEAD` of the analyzed checkout, which must exist on the remote); a branch-name link (`/blob/master/`) rots and is WRONG. Snippets go in fenced code blocks with a language tag.

Words: plain ones. A term the reader would have to look up gets replaced or said in plain words. No process notes ("one slip to flag", "I ran X earlier") above Details.

**Bug head:**

```
## Triage: <TICKET-ID> - <Title>

- Broke: <one plain line>
- Why: <one plain line>
- Fix: <one plain line>

Verdict: <Confirmed | Likely | Can't-determine> · <X>% · to reach certainty: <the one check> - ran it: <result> | can't run here: <reason>

Needs you: <facts only a person can get, with where to look; your decisions> | none

Ticket note (draft, not posted, <N> words):
> <Step 7>

### Details
Trigger: <what surfaced it>
Root cause: <why the code allows it - permalink>
Introduced by: <commit + PR + ticket, approved or not> | not a regression | not determined
Emitting service: <service> - <evidence>
Competing causes:
1. <top cause> - deciding check: <check> → <result>
2. <alternate> - deciding check: <check> → <result> - why less likely
Evidence:
- [Confirmed] <fact> / [Inferred] <conclusion>
- Sentry: <SHORT-ID + permalink, lifetime events/users, last seen, 24h trend, firstRelease> | no Sentry issue found (searched: <query>) | Sentry unavailable
| Source | Result |
|---|---|
| Ticket + linked work | checked: <...> |
| Sentry | checked: <...> / unavailable: <reason> |
| Logs | checked: <...> / unavailable: <reason> |
| Live record state | checked: <...> / not applicable / unavailable: <reason> |
| Code at deployed SHA | checked: <sha> (deployed / HEAD of <branch>, deployed unknown) |
| Other local repos + config | checked: <...> / not applicable |
| Recent changes + related PRs | checked: <...> |
Call chain: <service-a> → <service-b>, with endpoints/functions per hop
Recommendations: <fix aimed at the root cause, file and change>
Reproduction hint: <one line> | none describable
Verified: <N claims via darkmoon - U upheld, W weak, C can't-determine, R refuted> | skipped (--fast)
Open questions: <what you couldn't verify>
```

**Question head:**

```
## Triage: <TICKET-ID> - <Title>

The ask: <who needs what, by when, and why - one line>

| Ask | Answer | Sure? |
|---|---|---|
| <ask, 15 words max> | <answer, 15 words max> | <proven: source / likely / can't tell yet> |

Needs you: <facts only a person can get, with where to look; your decisions> | none

Ticket note (draft, not posted, <N> words):
> <Step 7>

### Details
Per ask: <the evidence - permalink, doc link, or command and output; self-run checks labelled>
<the evidence ledger table, as in the bug shape>
Verified: <...> | skipped (--fast)
Open questions: <...>
```

### Step 7 - Ticket Note (always)

The note is what a teammate reads on the ticket, written to the person who asked:
- **Written as the user:** the note goes out under the user's name. Find who that is (`/jira`'s own-accountId call) and match it to the ticket's comment authors: the user's earlier comments are "my answer on 6 Oct", never "<the user's name>'s answer".
- **Addressed and tagged:** open with the asker's name; name the owner when the ticket needs one; cc only people the note asks something of or answers. Posting with `/jira comment` turns each name into a real @-mention (its Mentions section).
- **Bug:** lead with the verdict word - `Confirmed` -> the root cause; `Likely` -> the cause labelled Likely plus the one open check; `Can't-determine` -> what would settle it. Then impact (Sentry counts / error rate) and the fix location.
- **Question:** one numbered line per ask, the answer first. An ask waiting on Needs you says so in one line ("waiting on the dashboard status") instead of guessing.
- **No:** alternate causes, speculation, the debugging story, process notes, or corrections of a colleague the user didn't ask for.
- **SHA-pinned permalinks** for every code reference (same rule as Step 6).
- **At most 120 words** (plus 25 per ask beyond 4). Count with `wc -w` on the drafted text and put the count in the heading; over the cap, cut and count again - showing a note over its cap is WRONG.

Show it and stop. Posting it is a separate, explicit user request (then use `/jira comment`) - this skill stays READ ONLY.

## Rules

- **NEVER fake confidence.** If you're not sure, say "I don't know" with what you'd need to verify.
- **Correct yourself once, in one line.** When new evidence overturns an answer you gave, say which line changed and why, then give the corrected answer - no running commentary across turns.
- **READ ONLY** (prefix grants scoped as in Step 3's backstop) Do not modify any code, write comments in JIRA, resolve or assign Sentry issues, or anything except for fetching, thinking and analyzing.
- **Search broadly.** Don't assume the bug is in one service. Cross-service bugs are common.
- **Check error handlers.** Error transformation (wrapping, re-throwing, status code mapping) is the #1 source of misleading errors.
- **Time matters.** Ticket filed 3 months ago? Current logs may not reflect the original bug. Say so.
- **Don't over-scope.** Triage identifies the problem and points to the fix. It doesn't implement the fix.
