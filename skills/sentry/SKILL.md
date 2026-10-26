---
name: sentry
description: >
  Query Sentry issues and events via the REST API (read-only). Use for a Sentry issue
  URL/short ID deep-dive (stack trace, deployed release, request_id, trend), top or new
  unresolved issues per project, searching Sentry for an error message or type
  (duplicate checks, ticket triage), and checking whether a deployed fix stopped an issue.
trigger: /sentry
allowed-tools: Read, Bash(curl:*), Bash(jq:*), Bash(tr:*), Bash(grep:*), Bash(ls:*), Bash(git show:*), Bash(git log:*), Bash(git grep:*), Bash(git cat-file:*), Bash(git -C:*), Bash(gh api:*)
argument-hint: "<issue-url|SHORT-ID> | top [project] [period] | new [period] | search \"<text>\" [period] | fixed <issue> <release>"
---

# /sentry - Sentry Issue Search

## Commands

| Input | Does | Handler |
|-------|------|---------|
| (no args) | ask what to look up | - |
| `<issue-url\|SHORT-ID\|numeric-id>` | one issue end-to-end | Issue Deep-Dive |
| `top [project] [period]` | unresolved issues by event volume | Top Issues |
| `new [period]` | issues first seen in the period | New Issues |
| `search "<text>" [period]` | issues matching a message or `error.type:<Type>` | Search |
| `fixed <issue> <release>` | did the deploy of `<release>` stop this issue? | Is It Fixed? |

Default period: `24h`. Accepted: `1h`, `6h`, `24h`, `7d`, `14d`, `30d`, `90d`. Rows: 10 by default; raise `limit` (max 100) when asked. All environments unless the user names one - then add `--data-urlencode "environment=<name>"`.

## Output contract - what the report MUST contain

For every required item: show the real artifact, OR write `Can't-determine` + the exact call that would settle it. Never fabricate a count, `file:line`, SHA, or request_id.

**Every query:**
- **Scope line** - period, projects (`all` unless filtered), environment, and the query string sent.
- **Counts labeled by window** - every number says whether it is in-period (`count`) or lifetime (`lifetime.count`). Never mix them in one column.
- **Issue identity** - `SHORT-ID` + permalink for every issue listed.

**Issue Deep-Dive also:**
- Lifetime count, users, first seen, last seen, status, handled/unhandled.
- Top exception: type, value, and the **in-app frames** as `path:line function` in Sentry's order (oldest call first, crash site last).
- `firstRelease` (regression suspect) and `lastRelease`, the latest event's release + environment, and the top releases by event count.
- `request_id` and `trace_id` from the latest event, or "not tagged".
- 24h hourly trend: total + peak hour.
- **Breadcrumbs:** the last meaningful steps before the crash, or "only telemetry (N filtered)".
- **Spread:** for each catalog spread tag, unique values and the top value's share - or "no spread tags in the catalog".
- **Source location** as `repo path:line @ <release>`, found at the release SHA. For a project the catalog marks **compiled**, say the frame line is compiled and give the source line you located.
- **Next steps block** (see Hand off) with the real `request_id`, log service and repo filled in from the catalog.

**Is It Fixed? also:** the release's `firstEvent`/`lastEvent`, this issue's event count on that release (0 when absent from the release list), the issue's pre-fix daily rate and the events expected since the release went live, and the verdict - `Fixed (evidence)` / `Not fixed` / `Too early` / `Can't-determine` - with the numbers that decide it.

**Empty result is a valid report** - state it with the scope line that proves where you looked.

---

*Mechanics - connection, endpoints, parsing.*

## Connection

Credentials live in a JSON file - `$CLAUDE_SKILLS_CREDENTIALS`, default `~/.config/claude-skills/credentials.json` - with `sentryAuthToken`, `sentryOrg` (the org slug) and optional `sentryApiBase` (default `https://sentry.io/api/0`; set it for self-hosted Sentry or another region). Repo, log-service and frame facts per project come from the service catalog, `~/.config/claude-skills/services.md` - a value the catalog lacks is asked for, never guessed.

Shell state does not persist between tool calls. Prepend this to EVERY bash call that hits the API:
```bash
C=${CLAUDE_SKILLS_CREDENTIALS:-$HOME/.config/claude-skills/credentials.json}
SENTRY_TOKEN=$(jq -r '.sentryAuthToken // error("sentryAuthToken unset in the credentials file")' "$C") || exit 1
SENTRY_ORG=$(jq -r '.sentryOrg // error("sentryOrg unset in the credentials file")' "$C") || exit 1
S="$(jq -r '.sentryApiBase // "https://sentry.io/api/0"' "$C")/organizations/$SENTRY_ORG"
```

Every request uses this shape - `--fail-with-body`, inline header, `-G` + `--data-urlencode` for parameters, control-char strip before jq. The pipe hides curl's exit code, so any `curl: (N)` on stderr is the failure signal (22 = HTTP error, 6/7 = host unreachable): report the HTTP error, and treat the jq output of that call (nulls, empty rows) as `Can't-determine`, never as data:
```bash
curl -sS --fail-with-body -G "$S/issues/" -H "Authorization: Bearer $SENTRY_TOKEN" \
  --data-urlencode "query=is:unresolved" --data-urlencode "project=-1" \
  --data-urlencode "statsPeriod=24h" --data-urlencode "limit=10" --data-urlencode "sort=freq" \
  | tr -d '\000-\010\013\014\016-\037' | jq '...'
```

**API rules (each one verified against a real org - violating any gives silently wrong results):**
- **Always send `project=-1`.** Without it the API returns only projects the token's user is a team member of (about half the unresolved issues were missing in one check). `query=project:<slug>` on a non-member project fails with "do not exist or are not actively selected" unless `project=-1` is also sent.
- **List counts are window-scoped.** In `/issues/` results, `count`, `userCount`, `firstSeen` and `lastSeen` cover only `statsPeriod`. Lifetime values live in `lifetime.count` / `lifetime.userCount` / `lifetime.firstSeen`. An issue from February shows `firstSeen` = start of the window. Use `lifetime.firstSeen` or the `firstSeen:-24h` query filter to decide "new".
- **`count` is a string** - use `(.count | tonumber)` before sorting or summing.
- **Page size is `limit`, not `per_page`** - `per_page` is ignored on `/issues/` and returns 100. Max 100; more needs the `Link` header cursor (`rel="next"; results="true"`).
- **Strip control characters before jq.** Event payloads can contain raw U+0000-U+001F, which jq rejects (`parse error: Invalid string: control characters ... must be escaped`). The `tr -d` in the request shape handles it.
- **Rate limit is 10 requests per window on `/issues/`.** A `429` means wait for `Retry-After` seconds; don't fire more than 5 issue calls in parallel.
- `401` = token invalid or expired → tell the user to refresh `sentryAuthToken` in the credentials file. Token scopes (from `GET /api/0/`): `alerts:read event:read member:read org:read project:read project:releases team:read`. Without `event:write` it cannot resolve, ignore, assign or comment on issues.

## Issue Deep-Dive

Resolve the input: a permalink `https://<org>.sentry.io/issues/<id>/`, a numeric id, or a short ID (`API-511`) - `/issues/<id-or-short-id>/` accepts all three.

Run these in **one** bash call (the last line once per *Spread tag* the catalog lists; none listed → drop it):
```bash
I=API-511
curl -sS --fail-with-body "$S/issues/$I/" -H "Authorization: Bearer $SENTRY_TOKEN" | tr -d '\000-\010\013\014\016-\037' \
  | jq '{id, shortId, title, permalink, status, level, isUnhandled, culprit, project: .project.slug,
         lifetimeCount: .count, users: .userCount, firstSeen, lastSeen,
         firstRelease: .firstRelease.version, lastRelease: .lastRelease.version,
         trend24h: (.stats["24h"] | {total: (map(.[1]) | add), peak: (max_by(.[1]) | {hour: (.[0] | todate), events: .[1]})})}'
curl -sS --fail-with-body "$S/issues/$I/events/latest/" -H "Authorization: Bearer $SENTRY_TOKEN" | tr -d '\000-\010\013\014\016-\037' \
  | jq 'def noise: ((.data.url // .message // "") | test(":812[56]/|/v0\\.[0-9]/traces|dogstatsd|/v1/(traces|metrics|logs)\\b|sentry_key=|/api/[0-9]+/(envelope|store)/"));
       [.entries[] | select(.type=="breadcrumbs") | .data.values[]] as $crumbs |
       {eventID, dateCreated,
         tags: ([.tags[] | select(.key | IN("release","environment","request_id","transaction","server_name","url")) | {(.key): .value}] | add),
         trace_id: .contexts.trace.trace_id,
         exception: [.entries[] | select(.type=="exception") | .data.values[] | {type, value, handled: .mechanism.handled,
                     frames: [.stacktrace.frames[]? | select(.inApp) | "\(.filename):\(.lineNo) \(.function)"]}],
         request: ([.entries[] | select(.type=="request") | .data | {method, url}][0]),
         breadcrumbs: {total: ($crumbs | length), telemetryFiltered: ($crumbs | map(select(noise)) | length),
           last: [$crumbs[] | select(noise | not) | {category, level,
                  msg: ((.message // ((.data.method // .data["http.method"] // "") + " " + ((.data.url // "") | sub("\\?.*$"; "")) + " " + ((.data.status_code // "") | tostring))) | .[0:120])}][-10:]}}'
curl -sS --fail-with-body "$S/issues/$I/tags/release/" -H "Authorization: Bearer $SENTRY_TOKEN" | tr -d '\000-\010\013\014\016-\037' \
  | jq '[.topValues[:5][] | {release: .value, events: .count, firstSeen, lastSeen}]'
curl -sS --fail-with-body "$S/issues/$I/tags/<spread-tag>/" -H "Authorization: Bearer $SENTRY_TOKEN" \
  | jq '.totalValues as $t | {tag: .key, unique: .uniqueValues, total: $t,
         top: [.topValues[:3][] | {value, count, sharePct: (if $t > 0 then (.count * 100 / $t | floor) else null end)}]}'
```
- **`firstRelease`** = the deploy where the issue first appeared - the regression suspect (`git log --oneline -15 <firstRelease> -- <files>` in the repo lists the commits leading up to it). **`lastRelease`** = the latest deploy still throwing it.
- The release tag list is the **top releases by event count only** - the current deploy can be missing from it (verified: `lastRelease` absent from `topValues`). Use it for "which deploys threw the most", never for "current release".
- The issue's `count`/`userCount`/`firstSeen` here are **lifetime** (detail endpoint, not the list). Use `/events/recommended/` instead of `latest` when the latest event lacks a stack trace.
- **Breadcrumbs** are what the app did just before the crash - read the `last` list bottom-up from the exception. Telemetry the SDK records about itself (APM agent traces/metrics, Sentry's own event uploads) is filtered out and only counted; URLs are shown without query strings, since those can carry keys and tokens. Server SDKs often record nothing but telemetry - `last: []` with `telemetryFiltered` = `total` means "no app breadcrumbs", say so. Browser breadcrumbs are usually the richest: the click, then the requests; an HTTP status `0` means the request never completed (network failure, abort or CORS), a strong lead when it sits right before the error.
- **Spread** answers "one customer or everyone?": per catalog spread tag, `unique` values and the top values' share of events. A top value at ≥50% means the issue is concentrated - name it as one user/tenant/stack, not a general outage; tiny `unique` with an even split (e.g. two stacks ~50/50) means it is not specific to one of them. **Values that identify a person** (emails, names - common in `user` tags) are production PII: report them masked as `user #1 (28%)`, never the raw value.

## Hand off

**Read the catalog's Services table first** (`~/.config/claude-skills/services.md`): it maps each Sentry project to its repo, log service and frame type, plus notes that change how to read it. Tracing without it is guessing; a project the catalog lacks → the slug usually matches a repo (`ls "$WORKSPACE"` to confirm) - say you inferred it.

Each deep-dive ends with these next steps, filled in:
- **Logs:** use the catalog's *Log search skill* (`none` → skip and say so). `request_id` tagged → trace it, with a window around the latest event's `dateCreated` (log tools default to a recent window, which misses an event days old). Not tagged → search the project's log service for the exception value over the issue's active period.
- **Code at the deployed SHA:** map the project to its repo (catalog). From that repo, confirm the release is a commit and read the code there:
  ```bash
  git -C "$WORKSPACE/<repo>" cat-file -t <release> && git -C "$WORKSPACE/<repo>" show <release>:<in-repo-path>
  ```
  Read the whole file once; don't slice it with `sed`. **SHA not local → go straight to the GitHub API** (don't `git fetch` - this skill never changes a checkout), with the catalog's *GitHub org*:
  ```bash
  gh api "repos/<github-org>/<repo>/contents/<in-repo-path>?ref=<release>" -H "Accept: application/vnd.github.raw"
  ```
  Release `null` (common for Python services) → find the deployed SHA where the catalog's *Deploy SHA when a Sentry release is null* row says, else `Can't-determine`.

`node_modules/`/`site-packages/` frames are library code: report the in-app frame **closest to the crash** (the last in-app frame) as the location. Strip the container path prefix the catalog names to get the in-repo path.

**Compiled frames** (the catalog says *compiled*: build output such as tsc `dist/` with no source maps uploaded): the compiler drops blank lines and may rename `.ts` to `.js`, so the frame's line drifts far from the source line - one verified case had the frame line over 500 lines away from the source line, in the same file at the same release. Reading the frame's line number at the release lands on the WRONG code. Locate by **function name** instead, then read that function:
```bash
git -C "$WORKSPACE/<repo>" grep -n -E 'function <name>\b|<name> = ' <release> -- <dir>
```
Error messages built from template literals don't grep verbatim (`` `Order ${id} cannot be refunded` ``) - grep a literal fragment (`cannot be refunded`). Report the location as `repo path:line @ <release>` using the **source** line you found, and say the frame line was compiled.

## Top Issues

Top Issues and New Issues need `PERIOD` (default `24h`) and optionally `PROJECT` (a slug). Like the Connection block, they do not survive between calls - put them right after the Connection lines in every call that uses them; an unset `PERIOD` sends an empty `statsPeriod`:
```bash
PERIOD=24h PROJECT=<slug, or leave empty for all projects>
```

```bash
curl -sS --fail-with-body -G "$S/issues/" -H "Authorization: Bearer $SENTRY_TOKEN" \
  --data-urlencode "query=is:unresolved${PROJECT:+ project:$PROJECT}" --data-urlencode "project=-1" \
  --data-urlencode "statsPeriod=$PERIOD" --data-urlencode "limit=10" --data-urlencode "sort=freq" \
  | tr -d '\000-\010\013\014\016-\037' \
  | jq -r '.[] | [.shortId, .count, .userCount, (.lifetime.firstSeen[:10]), .project.slug, .title[:80], .permalink] | @tsv'
```
Present a table: Short ID (linked to its permalink), Events (period), Users (period), First seen (lifetime), Project, Title. Mark an issue **NEW** only when `lifetime.firstSeen` falls inside the period.

Total matching issues = the `X-Hits` response header, not the row count. Fetch it with the **same query** in a separate call (headers on stdout would break jq):
```bash
curl -sS --fail-with-body -o /dev/null -D - -G "$S/issues/" -H "Authorization: Bearer $SENTRY_TOKEN" \
  --data-urlencode "query=is:unresolved${PROJECT:+ project:$PROJECT}" --data-urlencode "project=-1" --data-urlencode "statsPeriod=$PERIOD" --data-urlencode "limit=1" \
  | grep -i '^x-hits'
```

## New Issues

Same request with `query=is:unresolved firstSeen:-$PERIOD` and `sort=new`. `firstSeen:` filters on the true first-seen, so every row is genuinely new.

## Search

Free text matches title and message; quote multi-word phrases. Exact exception class: `error.type:<Type>`.
```bash
curl -sS --fail-with-body -G "$S/issues/" -H "Authorization: Bearer $SENTRY_TOKEN" \
  --data-urlencode 'query="cannot be refunded"' --data-urlencode "project=-1" --data-urlencode "statsPeriod=90d" --data-urlencode "limit=10" \
  | tr -d '\000-\010\013\014\016-\037' \
  | jq -r '.[] | [.shortId, .status, .count, .metadata.type, (.metadata.value // "")[:80], .project.slug, .permalink] | @tsv'
```
Swap the query for `error.type:TimeoutError` to match an exception class exactly. `metadata.type`/`metadata.value` are the exception type and message - compare those, not the title.
Search covers resolved issues too unless the query adds `is:unresolved`. Show `status` per row - for duplicate checks, a resolved issue that recurs is a regression, not a new bug. Free text is fuzzy: confirm a match by comparing the exception `type` + `value`, never the title alone.

## Is It Fixed?

Did the deploy of `<release>` stop this issue? `<release>` must be the version string exactly as Sentry records it - match the format of the issue's `lastRelease` (e.g. a 10-character SHA, not the full 40). Run all three in **one** call:
```bash
I=API-511 R=edce648713
curl -sS --fail-with-body "$S/issues/$I/" -H "Authorization: Bearer $SENTRY_TOKEN" | tr -d '\000-\010\013\014\016-\037' \
  | jq '{status, lastSeen, daily30d: [.stats["30d"][] | {day: (.[0] | todate[:10]), events: .[1]}]}'
curl -sS --fail-with-body "$S/releases/$R/" -H "Authorization: Bearer $SENTRY_TOKEN" \
  | jq '{version, dateCreated, firstEvent, lastEvent}'
curl -sS --fail-with-body "$S/issues/$I/tags/release/values/" -H "Authorization: Bearer $SENTRY_TOKEN" \
  | jq --arg r "$R" '{onRelease: ([.[] | select(.value == $r) | {count, firstSeen, lastSeen}][0] // "absent"),
                      oldestListed: (map(.lastSeen) | min),
                      otherReleases: [.[] | select(.value != $r) | {value, count, lastSeen}][0:5]}'
```
The release list holds this issue's **100 most recent releases** with exact per-release counts (verified; its `query=` filter is ignored). Don't count raw events instead - events past retention are gone, so an old release shows 0 there even when it threw hundreds.

Verdict, first match wins:
1. **`Can't-determine`** - the release call failed (`curl: (22)`: Sentry never saw that version - check the format), or the release is older than `oldestListed` - judged by `firstEvent`, or by `dateCreated` when `firstEvent` is null (an old release's events expire, so null there means "aged out", not "never ran"). Outside the list, absence proves nothing.
2. **`Too early`** - a recent release (`dateCreated` after `oldestListed`) whose `firstEvent` is null (not deployed or no traffic yet), or the events expected since it went live are under 5: expected = the issue's average daily count over the `daily30d` days before `firstEvent` × days since `firstEvent`. Say when it would reach 5.
3. **`Not fixed`** - `onRelease` has a count: show it with its first/last seen.
4. **`Fixed (evidence)`** - `onRelease` is absent, ~5+ events were expected, and the issue's `lastSeen` is before the release's `firstEvent`. Report "0 events on `<release>` where ~N were expected".
5. **`Rollout in progress`** - absent on `<release>`, but `otherReleases` show events after its `firstEvent`: older pods are still serving. Re-check once the rollout finishes.

## Rules

- **READ ONLY.** GET requests only - no resolve/ignore/assign/comment. Issue writes are blocked by the token's scopes; `curl` and `gh api` are GET-only by this rule (no `-X`, `-d`, `-f`).
- **Production data** - events carry user IDs, URLs, IPs. Summarize; don't dump raw events or `request.headers`/`user` objects.
- **`git`/`gh` read deployed code only** - `git show`/`git grep`/`git log`/`git cat-file`, `gh api .../contents`. No checkout, fetch, or writes (same rule as `/triage`).
