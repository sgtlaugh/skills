# Service catalog

Facts about your systems, read by the ops skills (sentry, triage, firewatch) from
`~/.config/claude-skills/services.md` - `install.sh` copies this template there; fill it in.
No secrets here - tokens live in `~/.config/claude-skills/credentials.json`.
A skill that needs a value missing from this file asks; it never guesses a host, repo or org.

## Global

| Key | Value |
|---|---|
| GitHub org | acme |
| Clones dir | `$WORKSPACE` (the directory holding your local clones) |
| Log search skill | `/my-logs` (a skill that searches your production logs), or `none` |
| Data lookup skill | `/my-data` (a skill that reads live record state), or `none` |
| Spread tags (Sentry) | tags that answer "one customer or everyone?", e.g. `tenant_id`, `user`, `region` |
| Deploy SHA when a Sentry release is null | where to find the deployed commit, e.g. a log field or a deploy dashboard |

## Services

Frames: **repo-relative** = Sentry frame paths are source paths; **compiled** = build output without source maps - locate code by function name, never by the frame line.

| Sentry project(s) | Repo | Log service | Frames | Notes |
|---|---|---|---|---|
| `owl-api` | `owl-api` | `owl-api` | repo-relative | Python - Sentry `release` is null |
| `owl-web` | `owl-web` | none (browser) | minified bundles; trust in-app frames only | |
| `owl-gateway` | `owl-gateway` | `gateway` | compiled - strip `/app/`; locate by function name | |
| none | `owl-cron` | `owl-cron` | | no Sentry project |

## Alerts

Read by `/firewatch`. Known patterns specific to your systems, checked after the skill's generic patterns: a pattern here with the same name as one of the skill's adds to it, any other is new. Each runs the skill's Common flow first.

| Key | Value |
|---|---|
| Incident channel (L1/L2) | `#incidents` |
| On-call guide | link to your on-call runbook |
| Jira project for alert tickets | `OWL` for app services, `OPS` for infra |
| Jira label for alert tickets | `oncall` |
| Typical cascade | owl-api 500 → owl-gateway 502 |

### Owl Feed Lag Critical
- `/my-logs owl-api "feed lag" last 1h`
- Ask whether a backfill is running - it starves the feed consumer

## Jenkins

| Key | Value |
|---|---|
| Base URL | https://jenkins.acme.example |
| Job naming | `<repo>-<purpose>` |
| What a failing job blocks | `<repo>-deploy` blocks deploys; `<repo>-pr` blocks one PR |
| Single-branch jobs | `-deploy`, `-nightly` |
| Infra job owner | `OPS` |

## Datadog

| Key | Value |
|---|---|
| Env tag | `env:prod` |

| Service | APM service(s) | Metric |
|---------|----------------|--------|
| owl-api | `owl-api` | `trace.flask.request` |
| owl-gateway | `owl-gateway` | `trace.express.request` |

## Opsgenie

Who else shares the alert stream, e.g. "company-wide - other teams' alerts dominate, always filter by the alert's own text".

## Health check

Queries for `/firewatch check all services`: one top-errors query per service (index, group-by field, error filter), the exact-count query for any aggregation, the log host and auth rule, and a scope line naming what the scan does NOT search.
