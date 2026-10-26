---
name: firewatch
description: Investigate production alerts - assess severity, search logs, trace errors, and create JIRA tickets
trigger: /firewatch
allowed-tools: Read, Grep, Glob, Skill, Bash(curl -sS:*), Bash(gh search:*), Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(git log:*), Bash(git show:*), Bash(git blame:*), Bash(find:*), Bash(jq:*), Bash(grep:*), Bash(tail:*), Bash(head:*), Bash(date +%s)
---

# /firewatch - Production Alert Investigation

Investigate production alerts end-to-end: assess severity, match known patterns, search logs, trace through code, and optionally create a JIRA ticket.

## Usage

```
/firewatch <paste alert text or description>
/firewatch 500s spike on <service>
/firewatch Opsgenie alert #<tinyId>
/firewatch check all services
```

## Service catalog

Read `~/.config/claude-skills/services.md` **before Step 1** - every step depends on it. Its sections:
- **Global** - GitHub org, clones dir, *Log search skill* (`<log-skill>` below), spread tags
- **Services** - per service: repo, Sentry project(s) (`none` = no Sentry project), log service, notes on service boundaries
- **Alerts** - incident channel, on-call guide, Jira project + label for alert tickets, typical cascade, and known patterns specific to these systems
- **Jenkins**, **Datadog**, **Opsgenie** - base URL and job naming, env tag and service-to-APM-metric table, alert-stream notes
- **Health check** - the queries for `check all services`

Assessing severity or matching patterns without it is WRONG - known patterns and service boundaries live there. A value the catalog lacks is asked for or marked inferred, never guessed. *Log search skill* `none` → log steps are `Can't-determine: no log skill configured`.

## Process

### Step 1 - Parse Alert & Assess Severity

Extract from the alert text:
- **Service name** - matched against the catalog's Services table
- **Error type** (500s, timeout, failed job, high error volume, etc.)
- **Request ID / trace ID** if present
- **Opsgenie alert ID** (tinyId like `#123456`) if present - fetch it (**Opsgenie** section) for priority, occurrence count and the Datadog monitor behind it
- **Time** of the alert

**Severity assessment:**
- **L1/L2 (Urgent)** - customer-facing outage, sustained 500s, complete service failure. Tell user immediately: "This looks like an L1/L2. Post in <the catalog's incident channel> while I investigate."
- **L3 (Important)** - elevated error rates, intermittent failures, single-customer impact. Investigate and ticket.
- **L4 (Monitor)** - sporadic errors, known flaky behavior, no customer impact. Check if it self-resolves.

### Step 2 - Match Known Alert Patterns

Check if the alert matches a known pattern - the ones below, then the catalog's **Alerts** patterns. If yes, follow its runbook. If no, proceed to Step 3 (general investigation).

---

**Common flow** (run for every pattern unless noted):
1. Fire these in **parallel** (single message, one tool call each):
   - `<log-skill> <log-service> errors last 1h`
   - `<log-skill> <log-service> top-errors last 1h`
   - `gh pr list --repo <github-org>/<repo> --state merged --limit 5`
   - `/sentry top <sentry-project> 1h` - for each Sentry project the service maps to (catalog Services); skip if none
   - Datadog APM 5xx + p95 latency + top failing endpoints for the service (**Datadog APM** section below). Skip ONLY when the section's all-tags lookup shows no `service:` tag for it - "not in the catalog's table" is not a valid skip
   - Opsgenie history for the alert's monitor - has it fired before, how did it close? (**Opsgenie** section). Skip ONLY when the alert text has no tinyId and no `[Datadog]` monitor title to search on
2. Quantify: 10 errors or 10,000? Count determines priority. Logs, Sentry and APM count different things (log lines vs grouped exceptions vs HTTP responses) - report each, never add them.
3. Check adjacent services - errors cascade (the catalog's *Typical cascade*, e.g. backend 500 → BFF 500). Depends on the parallel query results above, so runs AFTER.

Then apply pattern-specific steps:

#### 500s Spike
- Common flow covers it. Focus on cascade direction - which service errored first?
- APM's top endpoints by 5xx name the failing route directly; compare the last hour against the hour before (**Datadog APM**) to confirm it's a spike, not baseline.

#### Sentry New Issue
- `/sentry <issue-url or SHORT-ID>` first - it returns the real stack trace, `firstRelease` (the deploy that introduced it), `request_id`, and the 24h trend. Don't work from the alert text alone.
- `request_id` tagged → `<log-skill> trace <request_id>`; else search logs for the exception text (use `last 24h`)
- Use the deep-dive's Source location (located at the release SHA), not HEAD
- Check for duplicates in both systems: `/sentry search "<exception value fragment>" 90d` (a resolved match that recurs = regression) and `/jira` JQL `text ~ "<SHORT-ID>" OR (labels = Sentry AND text ~ "<error class>")`

#### Sentry High Error Volume
- `/sentry <SHORT-ID>` (no SHORT-ID in the alert → the top row of the Common flow's `/sentry top`) - `trend24h` peak hour vs total says spike or steady baseline. Baseline: that issue's count in `/sentry top <sentry-project> 7d` ÷ 7; not in the rows → rerun with a higher limit (max 100), else `Can't-determine`
- A browser project (catalog log service `none (browser)`) has no server logs - search the backend the request hit
- If client error references API call, search the backend service handling that endpoint
- Check if error correlates with specific endpoint, user, or org - the deep-dive's `transaction`/`url` tags name the endpoint

#### Failed Jenkins Jobs
CI/CD, not production. The job decides the stakes - the catalog's **Jenkins** section says what each job suffix blocks and how jobs are named.

Shell state does not persist between tool calls. Prepend this to EVERY bash call that hits Jenkins, with the catalog's Jenkins base URL written in literally:
```bash
C=${CLAUDE_SKILLS_CREDENTIALS:-$HOME/.config/claude-skills/credentials.json}
JENKINS_AUTH=$(jq -r 'if .jenkinsUser and .jenkinsApiToken then "\(.jenkinsUser):\(.jenkinsApiToken)" else error("jenkinsUser/jenkinsApiToken unset in the credentials file") end' "$C") || exit 1
J=<Jenkins base URL>
```
Pass `-g` whenever the URL has `tree=` - its `[]{}` are curl glob syntax otherwise (`curl: (3) bad range in URL`).

1. **History - the flaky verdict comes from here, not from one build:**
   ```bash
   curl -sS --fail-with-body -g -u "$JENKINS_AUTH" "$J/job/<job>/api/json?tree=builds[number,result,timestamp,actions[causes[shortDescription],parameters[name,value],lastBuiltRevision[SHA1]]]{0,8}" \
     | jq -r '.builds[] | [.number, (.result // "RUNNING"), (.timestamp/1000|todate),
         ([.actions[]?.parameters?[]? | select(.name=="ghprbActualCommit") | .value[:10]][0] // [.actions[]?.lastBuiltRevision?.SHA1? | select(.)][0][:10] // "-"),
         ([.actions[]?.causes?[]?.shortDescription] | join("; ") | .[:80])] | @tsv'
   ```
   For PR jobs, group rows by PR first - every PR has its own SHA, so unrelated PRs failing is not a pattern. Then apply the first matching row:

   | Pattern in the history | Verdict |
   |---|---|
   | Same commit SHA both passes and fails | **Flaky** |
   | Same SHA fails every time, including "Started by Naginator" auto-retries | **Deterministic** - the commit or its dependencies |
   | A single-branch job (catalog's *Single-branch jobs*) fails across several different SHAs | **Broken job/environment** (base image, registry, credentials) - not one commit's fault |
   | Fewer than 2 finished builds on any one SHA, or none of the above | **Can't-determine** - widen `{0,8}` to `{0,20}`; still unclear → report the gap, don't pick a verdict |
2. **Failure evidence** - most jobs publish no test report (`/testReport/api/json` → 404), so the console is the evidence:
   ```bash
   curl -sS --fail-with-body -u "$JENKINS_AUTH" "$J/job/<job>/<number>/consoleText" \
     | grep -nE '^ERROR|ERROR:|FAILED|Error:|Traceback|AssertionError|exit code|returned a non-zero|npm ERR|failed to solve' | tail -15
   ```
   Then read 30 lines from the first real hit (`<line>` = its number) for the cause, in a new call with the preamble:
   ```bash
   curl -sS --fail-with-body -u "$JENKINS_AUTH" "$J/job/<job>/<number>/consoleText" | tail -n +<line> | head -30
   ```
   Console text contains author emails - quote the error lines only.
3. **PR builds** (GitHub Pull Request Builder) carry `ghprbPullId`, `ghprbPullLink`, `ghprbActualCommit`, `ghprbPullAuthorLogin` in their parameters. Check the diff for test-breaking changes: `gh pr diff <ghprbPullId> --repo <github-org>/<repo>`.
4. **Act on the verdict:** flaky → ticket naming the job + builds; deterministic → put the PR author (`ghprbPullAuthorLogin`, or the "Started by GitHub push by <user>" cause) under **Requires Human** to notify; broken environment → ticket to the job owner (catalog's *Infra job owner* for infra jobs); Can't-determine → report the history you saw.

**Jenkins is read-only here** - GET only. Never `POST` to `/build`, `/rebuild`, `/stop` or `/doDelete`; re-running a job is a human action.

#### Datadog APM (5xx, latency, monitors)
Request-level numbers logs can't give: 5xx rate, p95 latency, which endpoint. Prepend to EVERY bash call that hits Datadog:
```bash
C=${CLAUDE_SKILLS_CREDENTIALS:-$HOME/.config/claude-skills/credentials.json}
DD_PAT=$(jq -r '.datadogPAT // error("datadogPAT unset in the credentials file")' "$C") || exit 1
DD_SITE=$(jq -r '.datadogSite // error("datadogSite unset in the credentials file")' "$C") || exit 1
D="https://api.$DD_SITE"
```
Auth is the PAT as a Bearer token.

The catalog's **Datadog** section maps each service to its APM service(s) and metric, and names the env tag. Other services: `curl -sS --fail-with-body "$D/api/v2/metrics/trace.<flask|express|fastapi>.request/all-tags" -H "Authorization: Bearer $DD_PAT" | jq '.data.attributes.tags'` lists the `service:` tags.

One call, last hour (substitute metric, APM service and env tag - shown for `trace.flask.request`, `service:<apm-service>`, `env:<env>`):
```bash
now=$(date +%s); from=$((now-3600))
for q in 'sum:trace.flask.request.hits{service:<apm-service>,env:<env>}.as_count()' \
         'sum:trace.flask.request.errors{service:<apm-service>,env:<env>}.as_count()' \
         'p95:trace.flask.request{service:<apm-service>,env:<env>}' \
         'top(sum:trace.flask.request.errors{service:<apm-service>,env:<env>} by {resource_name}.as_count(), 5, "sum", "desc")' \
         'top(p95:trace.flask.request{service:<apm-service>,env:<env>} by {resource_name}, 5, "max", "desc")'; do
  curl -sS --fail-with-body -G "$D/api/v1/query" -H "Authorization: Bearer $DD_PAT" \
    --data-urlencode "from=$from" --data-urlencode "to=$now" --data-urlencode "query=$q" \
    | jq -c --arg q "$q" '{q: $q, status: (.status // "FAILED"), error: (.error // .errors),
        series: [.series[]? | {scope, sum: ([.pointlist[][1] // 0] | add), max: ([.pointlist[][1] // 0] | max)}]}'
done
```
- **`.errors` = 5xx responses** (verified equal to `hits.by_http_status{http.status_class:5xx}` on flask and express). Report `sum` for hits/errors.
- **p95 is in seconds.** Read `max` (worst point in the window); `sum` of a latency series is meaningless.
- **Empty `series` counts as zero ONLY when `status` is `ok` AND the `.hits` row for the same service is non-empty** (counters are sparse). `status` not `ok` (auth failure, bad query) or empty `.hits` (wrong metric family or service tag) → `Can't-determine`, never "0 5xx".
- **Spike or baseline:** rerun the same block for the previous hour with its first line replaced by `now=$(($(date +%s)-3600)); from=$((now-3600))` and compare (a fresh call has no `$now` from the first run).

Monitors already firing for the service:
```bash
curl -sS --fail-with-body -G "$D/api/v1/monitor/search" -H "Authorization: Bearer $DD_PAT" --data-urlencode "query=<service> status:alert" \
  | jq -r '"total=\(.metadata.total_count)", (.monitors[] | "\(.status)\t\(.name[:90])\thttps://'"$DD_SITE"'/monitors/\(.id)")'
```
One monitor by id (e.g. from an Opsgenie alert's `eventUrl`) - its `query` says exactly what threshold fired:
```bash
curl -sS --fail-with-body "$D/api/v1/monitor/<id>" -H "Authorization: Bearer $DD_PAT" | jq '{id, name, overall_state, query}'
```
Datadog is read-only here - GET only; never mute, resolve or edit monitors.

#### Opsgenie (alert detail + history)
Filter by the alert's own text - a shared alert stream is dominated by other teams' alerts (the catalog's **Opsgenie** section says whose). Prepend to EVERY bash call that hits Opsgenie:
```bash
C=${CLAUDE_SKILLS_CREDENTIALS:-$HOME/.config/claude-skills/credentials.json}
OG_KEY=$(jq -r '.opsgenieApiKey // error("opsgenieApiKey unset in the credentials file")' "$C") || exit 1
O=$(jq -r '.opsgenieApiBase // "https://api.opsgenie.com"' "$C")
```
Alert detail by tinyId:
```bash
curl -sS --fail-with-body "$O/v2/alerts/<tinyId>?identifierType=tiny" -H "Authorization: GenieKey $OG_KEY" \
  | jq '.data | {tinyId, message, priority, status, acknowledged, count, createdAt, lastOccurredAt, source, eventUrl: .details["Event Url"]}'
```
`count` = how many times this alert re-fired before closing. `eventUrl` holds the Datadog monitor id (`.../monitors/<id>`) - query it via **Datadog APM**. The `description` field carries the monitor's runbook text with credential placeholders - summarize it, never paste it.

History - has this monitor fired before? Each trigger gets a fresh alias, so match a distinctive fragment of the message instead (pick one with no `"`, `$` or backticks):
```bash
SINCE=$(jq -rn 'now - 30*86400 | strftime("%d-%m-%Y")')
curl -sS --fail-with-body -G "$O/v2/alerts" -H "Authorization: GenieKey $OG_KEY" \
  --data-urlencode "query=message: \"<distinctive fragment>\" AND createdAt > $SINCE" \
  --data-urlencode "limit=20" --data-urlencode "sort=createdAt" --data-urlencode "order=desc" \
  | jq -r '.data[] | [.tinyId, .priority, .status, .count, .createdAt[:16], .message[:90]] | @tsv'
```
Total over the window (the list caps at `limit`; recompute `SINCE` - it does not survive from the history call):
```bash
SINCE=$(jq -rn 'now - 30*86400 | strftime("%d-%m-%Y")')
curl -sS --fail-with-body -G "$O/v2/alerts/count" -H "Authorization: GenieKey $OG_KEY" \
  --data-urlencode "query=message: \"<distinctive fragment>\" AND createdAt > $SINCE" | jq '.data.count'
```
Dates must be `dd-MM-yyyy`; the `jq` date works on Linux and macOS. Verdict from the 30-day total, first match wins:

| History | Verdict |
|---------|---------|
| total ≥ 5 and every listed row `closed` | **Flapping monitor** - L4 unless Step 1 already set L1-L3 |
| total = 1 (only this alert) | **First firing** - treat as new |
| anything else | Report the total; Step 1 severity stands |

A read-only key gets `403` ("not granted with configuration access") on on-call schedules, so "who is on call" stays under Requires Human. Opsgenie is read-only here: never acknowledge, close, assign or add notes.

---

### Step 3 - General Investigation

If no known pattern matches, use the general approach:

1. **Search errors**: `<log-skill> <log-service> errors last 1h`
2. **Check error rate**: `<log-skill> <log-service> top-errors last 1h` - is this a spike or baseline noise?
3. **Search specific error text**: `<log-skill> <log-service> "<key phrase from alert>"`
4. **Check Sentry + APM**: Datadog 5xx/p95/top endpoints for the service (**Datadog APM**); `/sentry top <sentry-project> 1h` for grouped exceptions; `/sentry search "<key phrase>" 24h` when the alert names an error. Then `/sentry <SHORT-ID>` on the top matching row for its stack trace and `request_id`.
5. **Trace request**: if request_id available (alert or Sentry deep-dive), `<log-skill> trace <id>`
6. **Check adjacent services**: errors often originate in a different service than where they manifest
7. **Trace through code**: search the catalog's clones dir for the error path, check error handlers

### Step 4 - Sanity Check

Before reporting, categorize every claim:
- **Confirmed** - directly observed in logs, code, or error output
- **Inferred** - logically follows from confirmed facts but not directly observed
- **Speculative** - plausible but unverified

Then gut check:
- Does the root cause explain ALL the symptoms, or just some?
- Could this be a symptom of something deeper (e.g., 500s caused by DB saturation, not app code)?
- Is the error rate actually elevated, or is this normal baseline noise? Compare: `<log-skill> <log-service> errors last 2h` and split first vs second hour mentally.
- Am I sure about the service boundary? Check the catalog's service notes (e.g. a server-side BFF's logs are not browser errors)

If uncertain, say so in the report. Wrong diagnosis during L1 costs more than "I don't know yet."

### Step 5 - Assess & Report

Present findings:

```
## Alert: <brief description>

**Severity: L1/L2/L3/L4**
**Status: Active / Resolved / Intermittent**

### What's happening
<2-3 sentences>

### Timeline
<When did it start? Getting worse, stable, or improving? Based on log timestamps.>

### Error Rate
<X errors in last hour, trending up/down/stable. Compare against previous hour if possible.>

### Root Cause (if identified)
- [Confirmed] <fact from logs/code>
- [Inferred] <logical conclusion from confirmed facts>
- [Speculative] <plausible but unverified>
Confidence: <X>%

### Affected Services
<list>

### Recommended Action
- [ ] <immediate action>
- [ ] <follow-up action>
- [ ] <ticket to create>

### Requires Human (if any)
<Actions Claude cannot perform: restart pods, check who is on call in Opsgenie, acknowledge/close Opsgenie alerts, post in the incident channel, mute/resolve Datadog monitors, resolve/assign Sentry issues, re-run Jenkins jobs, etc.>
```

**Completion contract - the report is NOT done until it contains:**
- Error count with source - an exact count from the log skill (aggregation sums are distribution-only, never the headline count)
- Severity with justification (L1-L4 + why)
- Every factual claim tagged `[Confirmed]`, `[Inferred]`, or `[Speculative]`
- Scope disclosure (what was searched, what was NOT)
- If "healthy" / "no errors": confirm the stream is live (newest doc timestamp), not stale
- If Sentry was queried: Sentry counts labeled in-period vs lifetime, with the SHORT-ID + permalink of each issue cited
- If Datadog was queried: APM 5xx and hit counts with the query and window, p95 as `max` in seconds, firing monitors' links (or `total=0` shown), both windows' 5xx sums if you call spike vs baseline, and failed/empty-`.hits` queries reported as `Can't-determine`
- If Opsgenie was checked: the history total with the query and window, and the flapping/first-firing/neither verdict; plus tinyId, priority and `count` when a tinyId was extracted
- If Jenkins was checked: the flaky/deterministic/broken/Can't-determine verdict backed by the build numbers + SHAs from the history, and the console error line

### Step 6 - Create JIRA Ticket (if needed)

Only if user confirms. Use `/jira` to create a ticket:
- **Board**: the catalog's *Jira project for alert tickets* for the service
- **Type**: Bug
- **Priority**: match severity (L1/L2 → the project's top two, L3 → middle, L4 → lowest), using the names and ranking from `/jira`'s priority-scheme lookup (its createmeta call lists the scheme unordered - rank by the level number in each name) - schemes vary per project, so never assume "Normal"/"Low" exist
- **Summary**: `<Service>: <error description>`
- **Description**: include error details, log snippets, affected timeframe
- **Labels**: the catalog's *Jira label for alert tickets*

For Sentry-originated alerts, check for existing duplicate tickets before creating, and put the Sentry SHORT-ID + permalink in the ticket description - tickets without it can't be matched back to Sentry later.

## Quick Health Check

When invoked with `check all services`, run the catalog's **Health check** queries directly as raw **curl** - not through the log skill. This is a breadth scan - counts + top buckets per service, not a deep investigation. No Health check section → say so and stop.

**Step 1 - Parallel top-error queries.** Issue every query the section lists as a **separate Bash tool call in ONE message** - Claude Code runs independent tool calls in parallel. Do NOT use shell backgrounding (`&` + `wait`). Never MCP log tools - they return full documents that bloat context.

**URL quoting (a `curl: URL using bad/illegal format` error means you violated this):**
- Wildcard index patterns (`*-k8s`) → **single-quote the full URL**.
- Write the full literal URL in every call - a base-URL variable carried over from another call is empty in a fresh shell.

**Step 2 - Exact counts.** For services whose top-error query is an aggregation, issue the parallel exact-count queries the section names (aggregation sums are distribution-only, not headline counts). Same quoting rules.

**Step 3 - Present as a table** with columns: Service, Error Count, Top Error, Status (✓ normal / ⚠ moderate / ⚠ elevated). Add the section's scope line (what was NOT searched). If a service shows ⚠ elevated, recommend `<log-skill> <log-service> errors last 1h` or `/firewatch <service>` for deep investigation.

## Rules

- **READ ONLY by default.** Do not create JIRA tickets, modify code, or take any action without explicit user confirmation.
- **Any `curl: (N)` on stderr means the request failed** - 22 = HTTP error (every curl here uses `--fail-with-body`), 6/7 = host unreachable (e.g. off VPN). Report the HTTP error and the body - an empty grep or jq result after a failed call is `Can't-determine`, never "no errors" or "0".
- **Severity first.** Always assess severity before deep-diving. L1/L2 needs immediate human action - tell the user fast, investigate in parallel.
- **Full on-call guide:** the catalog's *On-call guide* link.
