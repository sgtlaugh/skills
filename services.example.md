# Service catalog

Facts about your systems, read by the ops skills (sentry, sentry-fix, triage, firewatch, aristarchus) from
`~/.config/claude-skills/services.md` - `install.sh` copies this template there; fill it in.
No secrets here - tokens live in `~/.config/claude-skills/credentials.json`.
A skill that needs a value missing from this file asks; it never guesses a host, repo or org.
A value still reading `<your ...>` is unfilled and counts as missing, and a table row that starts with one is an example to replace, not a fact.

## Global

| Key | Value |
|---|---|
| GitHub org | `<your GitHub org, e.g. acme>` |
| Clones dir | `<your clones dir, e.g. $WORKSPACE (export it in your shell profile)>` |
| Log search skill | `<your log search skill, e.g. /my-logs, or none>` |
| Data lookup skill | `<your skill that reads live record state, e.g. /my-data, or none>` |
| Spread tags (Sentry) | `<your Sentry tags that answer "one customer or everyone?", e.g. tenant_id, user, region>` |
| Deploy SHA when a Sentry release is null | `<your source of the deployed commit, e.g. a log field or a deploy dashboard>` |

## Services

Frames: **repo-relative** = Sentry frame paths are source paths; **compiled** = build output without source maps - locate code by function name, never by the frame line.

| Sentry project(s) | Repo | Log service | Frames | Notes |
|---|---|---|---|---|
| `<your Sentry project, e.g. owl-api>` | `owl-api` | `owl-api` | repo-relative | Python - Sentry `release` is null |
| `<your Sentry project, e.g. owl-web>` | `owl-web` | none (browser) | minified bundles; trust in-app frames only | |
| `<your Sentry project, e.g. owl-gateway>` | `owl-gateway` | `gateway` | compiled - strip `/app/`; locate by function name | |
| `<your project, or none, e.g. none>` | `owl-cron` | `owl-cron` | | no Sentry project |

## Alerts

Read by `/firewatch`. Known patterns specific to your systems, checked after the skill's generic patterns: a pattern here with the same name as one of the skill's adds to it, any other is new. Each runs the skill's Common flow first.

| Key | Value |
|---|---|
| Incident channel (L1/L2) | `<your incident channel, e.g. #incidents>` |
| On-call guide | `<your on-call runbook link>` |
| Jira project for alert tickets | `<your Jira project(s), e.g. OWL for app services, OPS for infra>` |
| Jira label for alert tickets | `<your label, e.g. oncall>` |
| Typical cascade | `<your usual failure chain, e.g. owl-api 500 → owl-gateway 502>` |

### <your alert name, e.g. Owl Feed Lag Critical>
- `/my-logs owl-api "feed lag" last 1h`
- Ask whether a backfill is running - it starves the feed consumer

## Fixes

Read by `/sentry` (noise and reporting patterns, for its Classify step), `/sentry-fix` (all of it) and `/aristarchus` (the repo table, for its mutation check): how to run each repo's tests, plus noise and reporting patterns specific to your projects.

| Key | Value |
|---|---|
| Branch prefix | `<your fix branch prefix, e.g. fix>` |
| Deliberate error-tracking function | `<your function that reports to Sentry on purpose and continues, e.g. reportError, or none>` |
| Project noise patterns | `<your product errors that are never code bugs, e.g. "owl-web: Viewer is on a different domain (embedded viewer on a customer page)">` |

Test commands run from the repo root. `{files}` is the test files to run and `{dirs}` their directories. Worktree setup runs once in a fresh worktree, before any test - for the untracked files a clone lacks.

| Repo | Test command | Worktree setup | Prerequisites and how to start them |
|---|---|---|---|
| `<your repo, e.g. owl-api>` | `pytest -q {files}` | none | Postgres on `localhost:5432`: `docker run -d --rm --name owl-pg -p 5432:5432 postgres:16` |
| `<your repo, e.g. owl-gateway>` | `npm test -- {dirs}` | `ln -s $WORKSPACE/owl-gateway/node_modules node_modules` | none |

## Jenkins

| Key | Value |
|---|---|
| Base URL | `<your Jenkins URL, e.g. https://jenkins.acme.example>` |
| Job naming | `<your job naming, e.g. <repo>-<purpose>>` |
| What a failing job blocks | `<your jobs that block work, e.g. <repo>-deploy blocks deploys; <repo>-pr blocks one PR>` |
| Single-branch jobs | `<your single-branch job suffixes, e.g. -deploy, -nightly>` |
| Infra job owner | `<your infra team, e.g. OPS>` |

## Datadog

| Key | Value |
|---|---|
| Env tag | `<your env tag, e.g. env:prod>` |

| Service | APM service(s) | Metric |
|---------|----------------|--------|
| `<your service, e.g. owl-api>` | `owl-api` | `trace.flask.request` |
| `<your service, e.g. owl-gateway>` | `owl-gateway` | `trace.express.request` |

## Opsgenie

`<your note on who else shares the alert stream, e.g. "company-wide - other teams' alerts dominate, always filter by the alert's own text">`

## Health check

`<your queries>` for `/firewatch check all services`: one top-errors query per service (index, group-by field, error filter), the exact-count query for any aggregation, the log host and auth rule, and a scope line naming what the scan does NOT search.
