# Cheatsheet

Usage patterns by workflow. Every skill's full flags live in its `SKILL.md`.

- [Before you push](#before-you-push)
- [Checking claims](#checking-claims)
- [Building and debugging](#building-and-debugging)
- [Specs and decisions](#specs-and-decisions)
- [Production](#production)
- [About skills themselves](#about-skills-themselves)
- [Habits that work](#habits-that-work)

## Before you push

**`/occam`** - review your own change in a fresh context

    /occam                        # local work: changes vs HEAD + untracked files
    /occam <goal>                 # same, judged against the stated goal
    /occam --staged               # only what's staged
    /occam --last                 # the last commit
    /occam --branch               # the whole branch vs its merge target

**`/aristarchus`** - deep PR review

    /aristarchus <PR-URL>         # all 5 lenses + darkmoon verification
    /aristarchus <PR-URL> --fast  # quick pass, no agent steps

**`/nicepr`** - PR title and description

    /nicepr                       # preview locally
    /nicepr --create              # push + open the PR
    /nicepr --create --draft      # same, as a draft
    /nicepr --update              # regenerate for the existing PR
    /nicepr --humanize --concise  # strip AI patterns and cut length

## Checking claims

**`/darkmoon`** - challenge the last response

    /darkmoon                     # every load-bearing claim in it
    /darkmoon <topic>             # only claims about that topic
    /darkmoon --context 3         # include 3 earlier exchanges
    /darkmoon --claims <claim>    # settle one claim against the code, no transcript
    /darkmoon --claims <list>     # numbered list or a pasted evidence block: one verdict each

**`/solaire`** - grounded research, before answering

    /solaire <question>           # answer under seven fixed checks

## Building and debugging

**`/bonfire`** - test-first build loop

    /bonfire <feature>            # red → green → refactor, one behavior at a time

**`/duck`** - Socratic rubber duck

    /duck <bug description>       # questions you to the answer
    /duck <file or ticket>        # starts from the code or the ticket
    /duck --quack                 # drops the act, proves the cause with a repro

**`/fathom`** - deep-module design lens

    /fathom <module>                   # deep vs shallow, and how to deepen it
    /fathom --twice <design question>  # design the interface several ways, compare

## Specs and decisions

**`/gadfly`** - interrogate a spec before it gets built

    /gadfly <confluence-url>      # fetch + attack
    /gadfly <file.md>             # a local spec (md, txt, pdf, docx)
    /gadfly <spec> --prd <prd>    # check the HOW against the WHY

**`/forge`** - PRD to a grounded spec draft

    /forge <prd>                  # draft, you decide the forks, gadfly critiques
    /forge <prd> --repo <hint>    # point it at the repo(s) the feature lands in
    /forge <prd> --no-temper      # draft only, skip the gadfly pass

**`/dialectic`** - decide between options

    /dialectic <question>                       # argue, cross-examine, judge
    /dialectic <doc> --options "A, B"           # ground the debate in a doc
    /dialectic <...> --criteria "cost, risk"    # pin what the judge scores

## Production

**`/firewatch`** - investigate an alert

    /firewatch <alert text>       # severity, known patterns, logs, APM, report
    /firewatch Opsgenie alert #<tinyId>
    /firewatch check all services # breadth scan from your catalog's queries

**`/sentry`** - Sentry issues (read-only)

    /sentry OWL-API-511           # deep-dive: trace at the release, breadcrumbs, who is hit
    /sentry top owl-api 7d        # unresolved by event volume
    /sentry new 24h               # first seen in the window
    /sentry search "cannot be refunded" 90d
    /sentry fixed OWL-API-511 edce648713   # did that deploy stop it?

**`/triage`** - ticket to a proven root cause

    /triage <TICKET-ID>           # evidence ledger, darkmoon check, ticket note
    /triage <TICKET-ID> --fast    # same, skip the darkmoon pass

**`/jira`** - tickets and Confluence

    /jira PROJ-123                # ticket details
    /jira search "auth timeout"   # free text → JQL
    /jira create PROJ             # new ticket
    /jira comment PROJ-123        # add a comment
    /jira confluence <page-url>   # page as readable text

## About skills themselves

**`/kiln`** - lint a skill

    /kiln <skill>                 # static review: binding, contracts, stale refs
    /kiln <skill> --fire          # also generate adversarial test cases

**`/jury`** - run a skill N times, merge the results

    /jury <skill> <args> --n 3              # 3 runs, frequency table
    /jury <skill> <args> --n 3 --headless   # separate processes, for skills that spawn agents

**`/velka`** - habits across your sessions

    /velka                        # since the last run
    /velka --all                  # full history
    /velka --since 2026-08-20     # from a date
    /velka --candidates           # what you keep asking for vs the skills you have
    /velka --explain              # add what each habit means and what to do

**`/humanize`** - strip AI patterns from text

    /humanize                     # rewrite for a human voice
    /humanize --concise           # rewrite + cut about half

## Habits that work

- **Review, then describe.** `/occam` before committing, `/nicepr --create` to open the PR.
- **Doubt the confident answer.** When a response sounds too sure, `/darkmoon` it.
- **Spec loop.** `/forge` drafts, `/gadfly` attacks, you decide, repeat until no blockers remain.
- **High stakes, more runs.** `/jury aristarchus <PR> --n 3 --headless` shows which findings were consistent and which were luck.
- **After editing a skill,** `/kiln` it before you commit. Don't you dare go hollow.
