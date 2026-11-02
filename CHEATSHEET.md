# Cheatsheet

Common usage by workflow. Every flag is in each skill's `SKILL.md`; what each skill is, in the [README](README.md#the-skills).

## Which skill?

| I want to... | Use |
|---|---|
| Check my change before I commit | `/occam` |
| Review someone's PR | `/aristarchus <PR-URL>` |
| Write the PR description | `/nicepr` |
| Know if that last answer is actually right | `/darkmoon` |
| Settle one claim against the code | `/darkmoon --claims <claim>` |
| Research something without bluffing | `/solaire <question>` |
| Build a feature test-first | `/bonfire <feature>` |
| Get unstuck on a bug, and learn why | `/duck <bug>` |
| Judge a module's design | `/fathom <module>` |
| Find holes in a spec before it's built | `/gadfly <spec>` |
| Turn a PRD into a spec | `/forge <prd>` |
| Pick between designs | `/dialectic <question>` |
| Handle an alert that just fired | `/firewatch <alert>` |
| Find why a ticket's bug happens, or answer what a ticket asks | `/triage <TICKET-ID>` |
| Check whether a ticket is really done | `/lordvessel <TICKET-ID>` |
| Check whether a deploy fixed a Sentry issue | `/sentry fixed <issue> <release>` |
| Read, create or comment on a Jira ticket | `/jira PROJ-123` |
| Lint a skill I just edited | `/kiln <skill>` |
| See if a skill's output is stable | `/jury <skill> <args>` |
| Find habits worth fixing in my sessions | `/velka` |
| Make text sound like a person wrote it | `/humanize` |

## Before you push

**`/occam`**

```text
/occam                                    # local work: changes vs HEAD + untracked files
/occam <goal>                             # same, judged against the stated goal
/occam --staged                           # only what's staged
/occam --last                             # the last commit
/occam --branch                           # the whole branch vs its merge target
```

**`/aristarchus`**

```text
/aristarchus <PR-URL>                     # all 5 lenses + darkmoon verification
/aristarchus <PR-URL> --fast              # quick pass, no agent steps
```

**`/nicepr`**

```text
/nicepr                                   # preview locally
/nicepr --create                          # push + open the PR
/nicepr --create --draft                  # same, as a draft
/nicepr --create --reviewers <who>        # ask these users or teams to review
/nicepr --update                          # regenerate for the existing PR
/nicepr --humanize --concise              # strip AI patterns and cut length
```

## Checking claims

**`/darkmoon`**

```text
/darkmoon                                 # every load-bearing claim in the last response
/darkmoon <topic>                         # only claims about that topic
/darkmoon --context 3                     # include 3 earlier exchanges
/darkmoon --claims <claim>                # settle one claim against the code, no transcript
/darkmoon --claims <list>                 # numbered list or pasted evidence: one verdict each
```

**`/solaire`**

```text
/solaire <question>                       # answer under seven fixed checks
```

## Building and debugging

**`/bonfire`**

```text
/bonfire <feature>                        # red → green → refactor, one behavior at a time
```

**`/duck`**

```text
/duck <bug description>                   # questions you to the answer
/duck <file or ticket>                    # starts from the code or the ticket
/duck --quack                             # drops the act, proves the cause with a repro
```

**`/fathom`**

```text
/fathom <module>                          # deep vs shallow, and how to deepen it
/fathom --twice <design question>         # design the interface several ways, compare
```

## Specs and decisions

**`/gadfly`**

```text
/gadfly <confluence-url>                  # fetch + attack
/gadfly <file.md>                         # a local spec (md, txt, pdf, docx)
/gadfly <spec> --prd <prd>                # check the HOW against the WHY
```

**`/forge`**

```text
/forge <prd-file>                         # local PRD (md, txt, pdf, docx)
/forge <confluence-url|id>                # Confluence PRD, by URL or page ID
/forge <prd> --repo <hint>                # the repo(s) the feature lands in
/forge <prd> --no-temper                  # draft only, skip the gadfly pass
```

**`/dialectic`**

```text
/dialectic <question>                     # argue, cross-examine, judge
/dialectic <doc> --options "A, B"         # ground the debate in a doc
/dialectic <...> --criteria "cost, risk"  # pin what the judge scores
```

## Production

**`/firewatch`**

```text
/firewatch <alert text>                   # severity, known patterns, logs, APM, report
/firewatch Opsgenie alert #<tinyId>       # an Opsgenie alert, by its tiny ID
/firewatch check all services             # breadth scan from your catalog's queries
```

**`/sentry`**

```text
/sentry OWL-API-511                       # deep-dive at the release: trace, breadcrumbs, who is hit
/sentry top owl-api 7d                    # unresolved by event volume
/sentry new 24h                           # first seen in the window
/sentry search "cannot be refunded" 90d   # free-text search
/sentry fixed OWL-API-511 edce648713      # did that deploy stop it?
```

**`/triage`**

```text
/triage <TICKET-ID>                       # answer first, then the ticket note, evidence last
/triage <jira-url>                        # same, by URL
/triage <TICKET-ID> --fast                # skip the darkmoon pass
```

**`/lordvessel`**

```text
/lordvessel <TICKET-ID>                   # each requirement vs code, extra code, threads, CI, note
/lordvessel <jira-url>                    # same, by URL
/lordvessel <TICKET-ID> --fast            # skip the darkmoon pass
```

**`/jira`**

```text
/jira PROJ-123                            # ticket details
/jira search "auth timeout"               # free text → JQL
/jira create PROJ                         # new ticket, after a preview and your yes
/jira comment PROJ-123                    # add a comment, same
/jira confluence <page-url>               # page as readable text
```

## About skills themselves

**`/kiln`**

```text
/kiln <skill>                             # static review: binding, contracts, stale refs
/kiln <skill> --fire                      # also generate adversarial test cases
```

**`/jury`**

```text
/jury <skill> <args>                      # 3 runs (the default), frequency table
/jury <skill> <args> --n 5                # more runs
/jury <skill> <args> --headless           # separate processes, for skills with agents
/jury --merge <runs-dir>                  # re-merge saved runs, no re-run
```

**`/velka`**

```text
/velka                                    # since the last run
/velka --all                              # full history
/velka --since 2026-08-20                 # from a date
/velka --project <path>                   # only sessions in that directory
/velka --candidates                       # what you keep asking for vs your skills
/velka --propose                          # CLAUDE.md edits from repeated pushback
/velka --explain                          # what each habit means and what to do
/velka --advice                           # also show speculative suggestions
```

**`/humanize`**

```text
/humanize                                 # rewrite your previous response
/humanize <text or file>                  # rewrite that (a file is printed, not edited)
/humanize --concise                       # any of the above, cut about half
```

## Cost and time

Take these with a grain of salt: a few runs each, and they swing with repo size and how deep the skill digs. A `-` was not recorded.

| Run | Model | Cost | Time | Measured |
|---|---|---|---|---|
| `/darkmoon --claims` (a few claims) | Opus 5.5 | $0.20-0.40 | under 1 min | Oct 2026 |
| `/firewatch check all services` | Opus 5.5 (1M) | about $0.30 | about 1 min | Oct 2026 |
| `/firewatch <alert>` | Opus 5.5 (1M) | $0.70-0.90 | about 3 min | Oct 2026 |
| `/triage <TICKET-ID>` | Opus 5.5 (1M) | $2.20-2.50 | about 8 min | Oct 2026 |
| `/aristarchus <PR-URL>` (full, headless) | Opus 5.5 (1M) | $3.05-3.39 | 4-7 min | Oct 2026 |
| `/lordvessel <TICKET-ID> --fast` | Opus 5.5 (1M) | - | 2-5 min | Oct 2026 |
| `/lordvessel <TICKET-ID>` | Opus 5.5 (1M) | - | about 9 min | Oct 2026 |
| `/gadfly <spec>` | Opus 4.6 (1M) | $1.30-5.60 | 5-10 min | June 2026 |
| `/forge <prd>` | - | $5-15 | about 14 min | June 2026 |
| `/jury <skill>` | the target's | N × the target | about one run (parallel) | - |

## Habits that work

- **Review, then describe.** `/occam` before committing, `/nicepr --create` to open the PR.
- **Doubt the confident answer.** When a response sounds too sure, `/darkmoon` it.
- **Spec loop.** `/forge` drafts, `/gadfly` attacks, you decide, repeat until no blockers remain.
- **High stakes, more runs.** `/jury aristarchus <PR> --headless` shows which findings were consistent and which were luck.
- **After editing a skill,** `/kiln` it before you commit. Don't you dare go hollow.
