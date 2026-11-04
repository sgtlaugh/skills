---
name: niceticket
description: Write a short, well-formatted Jira bug ticket - a Title Case title and a body that says what breaks, for whom and how often, with only the sections the facts support (steps, expected vs actual, cause, fix, acceptance criteria), code links as permalinks. From a bug report, a Sentry issue, logs or an investigation's facts. Drafts only; /jira creates it.
allowed-tools: Read, Grep, Glob, Skill, Bash(git log:*), Bash(git rev-parse:*), Bash(git branch -r --contains:*), Bash(gh api:*)
---

# /niceticket - Write a Jira Ticket

Turn what is known about a bug into a ticket a teammate, a PM or QA can act on in a minute. The counterpart of `/nicepr`: that one describes a change, this one describes a problem.

## Usage

```
/niceticket <what you have>          # a pasted report, a Sentry issue URL or ID, log lines, a Slack thread
/niceticket                          # from the conversation so far
```

It drafts only: it reads (`gh api` GETs, git history, `/sentry`) and writes nothing anywhere. Create the ticket with `/jira` once you have read it; creating or editing a ticket, or any `gh api` call with `-X`, `--method`, `-f` or `-F`, from here is WRONG.

A caller (a script that already investigated) may pass the facts in the prompt: the cause, its evidence, the repo and the commit the code was read at, the PR. Then use only those facts, fetch nothing, and say nothing they don't support.

## Step 1 - Gather the facts

- A Sentry issue: invoke `/sentry` for its title, event count, first and last seen, and the stack frames that point at code.
- Logs or a pasted report: take the symptom, when it happens, how often, and who sees it.
- Code: find the lines that matter and the commit they were read at (`git rev-parse <remote>/<default branch>` on a fetched remote, or the commit the caller gave). Before linking it, confirm the commit is on the remote: `gh api repos/<org>/<repo>/commits/<sha> --jq .sha` prints it, or `git branch -r --contains <sha>` lists a remote branch. A commit only on your machine gives links that 404; with no commit you can confirm, name the file and line in backticks with no link.

Every number in the ticket (events, users, dates) comes from a source you read. With no source, leave the number out; an invented or rounded-up figure is WRONG.

## Step 2 - Title

Title Case, under 80 characters, the symptom as a reader meets it, no ticket key:

- Good: `Invoice History Returns 500 for Another Team's Invoice`
- Bad: `Fix getInvoiceVersions error mapping` (a fix, not a problem), `500 error` (says nothing)

## Step 3 - Body

Short by default: a reader should get the problem from the first two lines. Every line earns its place.

**Always: the summary, first, with no heading.** One or two sentences: what breaks, for whom, how often, with the Sentry issue or log query linked.

**Then only the sections the facts support**, each a `###` heading with at most three short bullets, in this order:

| Section | Include when |
|---|---|
| `### Steps to reproduce` | You know the steps; numbered |
| `### Expected vs actual` | The right behaviour isn't obvious from the summary |
| `### Cause` | The cause is known: one to three bullets, each pointing at the code |
| `### Fix` | A fix exists or is clear: what it changes, and its PR |
| `### Acceptance criteria` | There is something to check once it's fixed (the request returns 404; no new events after the deploy) |

A section with nothing real to say is left out; a heading over filler is WRONG.

### Writing rules

- Plain words. The summary is for anyone; name an internal component only with what it does ("the billing service", not "ledgerd"). No "Let's", no "we", no narration of what was investigated.
- One fact per bullet. No parenthetical asides, no em dashes, no bold inside sentences.
- No private data: no customer, org, user or content ids, emails, request ids or customer names - describe them ("an invoice from another team"). A truncated id is still an id.
- Facts only from the sources. A guess is said as one ("likely", with what would confirm it), or left out.

### Links and code

- Code links are permalinks pinned to a commit SHA that exists on the remote: `https://github.com/<org>/<repo>/blob/<sha>/<path>#L<line>`. A link to a branch name drifts and is WRONG.
- Link text is short and plain: `[content.ts:367](<permalink>)`, the file name and line. Never code formatting inside link text, never a bare URL in a sentence.
- Sentry issues, PRs, log queries and other tickets are links too: `[BILLING-API-4HF](<url>)`, `[#812](<url>)`.
- Code only when it says what words can't (the failing request, the exact error): a fenced block with its language, at most ten lines. Identifiers in a sentence go in backticks.

## Step 4 - Self-check, then show it

Before showing the draft, re-read it against this list and fix every miss:

1. The title is Title Case, under 80 characters, a symptom.
2. The first lines say what breaks, for whom and how often, with a link to the source.
3. Every section present has something real; none is filler.
4. Every code link is a permalink at a commit SHA; link text is `file:line` with no backticks; no bare URLs.
5. Every number has a source; no private ids or names.
6. Code, if any, is fenced with a language and ten lines or fewer.
7. No sentence over about 20 words, no "Let's", no em dash.

Show the title, then the body as Markdown, directly in the reply (not in a code fence: the body has its own). Ask whether to change anything. `/jira` creates it once you say so; it converts the Markdown for Jira.

## Example

Title: `Invoice History Returns 500 for Another Team's Invoice`

Opening an invoice's history while switched to a different team returns a 500 and pages the on-call: [BILLING-API-4HF](https://sentry.io/organizations/acme/issues/4021/), 54 events in a year.

### Expected vs actual
- Expected: 404, the invoice isn't in your current team.
- Actual: 500.

### Cause
- The history endpoint looks the invoice up in your current team: [invoices.ts:367](https://github.com/acme/billing-api/blob/3f9c2d17a8e4b6015c2e9d4f7a1b0c8e5d6f2a91/src/services/invoices.ts#L367).
- The ledger service answers 400, and [ledger.ts:185](https://github.com/acme/billing-api/blob/3f9c2d17a8e4b6015c2e9d4f7a1b0c8e5d6f2a91/src/services/ledger.ts#L185) passes it on as a 500.

### Fix
- [#812](https://github.com/acme/billing-api/pull/812) turns a 400 or 404 from those lookups into a 404.

### Acceptance criteria
- Asking for another team's invoice returns 404.
- No new BILLING-API-4HF events after the deploy.
