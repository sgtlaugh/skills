---
name: forge
description: Turn a PRD into a grounded tech-spec draft - ingest the WHY, ground in the code it lands in, surface the design forks for you to decide, then draft a spec structured to survive review. Pairs with gadfly (the critic) - forge authors, gadfly tempers. A grounded draft, not a finished spec.
trigger: /forge
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(curl:*), Bash(printf:*), Bash(echo:*), Bash(jq:*), Bash(pandoc:*), Bash(cat:*), Bash(grep:*), Bash(find:*), Bash(head:*), Bash(stat:*), Bash(mktemp:*), Bash(git rev-parse:*), Bash(cd:*), Bash(date:*), WebFetch, Agent, AskUserQuestion, Skill
---

# /forge - author a spec from a PRD, then temper it

A blacksmith's forge: raw PRD in, drafted, stressed by gadfly, hardened spec out. forge writes the first grounded draft of a tech spec from a product requirements doc, hands it to **gadfly** for an independent adversarial pass, then revises once.

An LLM drafts plausible-but-wrong architecture confidently, and a spec gets built. forge is safe only because it grounds every design claim in code (or tags it `[assumed]`), never decides a product fork for you, and lets gadfly - not itself - be the critic. The result is "survived one gadfly pass", never "correct". If you already have a human draft, skip forge and run gadfly.

## Usage

```
/forge <prd-path>            # local PRD: .md / .txt / .pdf / .docx
/forge <prd-url|page-id>     # Confluence PRD
/forge <prd> --repo <hint>   # the repo(s) the feature lands in (else forge discovers)
/forge <prd> --no-temper     # draft only - skip the gadfly temper pass
```

Cost: ingest + ground + draft + a gadfly pass + revise, roughly 1.5-2x a gadfly run (measured $5.4-6.6 with the temper pass; gadfly alone $2.2-4.6). `--no-temper` skips gadfly. For a union of several critiques, run `/jury gadfly <forge-output> --prd <prd>` yourself on the finished draft.

## Who answers the forks

Forks go to a human through `AskUserQuestion`. **When no human can answer** - a headless `claude -p` run, a subagent, a prompt that says so, or `AskUserQuestion` is unavailable or errors - never stop on a question: take the recommended option, tag it `[assumed]`, list it as an open question, and keep going to the saved draft. Printing questions as text and ending the turn leaves the user with no draft.

## Phase 0 - Ingest the PRD

Resolve the input to **PRD text + a version stamp**, recording what you could not read. Follow gadfly's Phase 0 (`~/.claude/skills/gadfly/SKILL.md`, "Phase 0 - Ingest the spec") step for step: Confluence fetch with the credentials preamble on every call, `.docx` via `pandoc -f docx -t gfm`, stamp = version or file mtime, diagrams downloaded and read with vision. List only what you genuinely couldn't parse as `Not analyzed`.

The PRD is the **WHY**. forge authors the **HOW** that satisfies it.

## Phase 1 - Ground the terrain and frame the decisions

Goal: a grounded picture of where the feature lands, plus the decisions only a human can make - before any spec is drafted.

### Step 1 - Extract PRD requirements
Tag each requirement `[Stated]`/`[Inferred]`/`[Missing]`, shall-statements where they sharpen it. Include NFRs (scale, latency, consistency, availability); a PRD that omits them yields open questions, not guessed numbers.

### Step 1b - Find the PRD's load-bearing semantic fork
PRD wording often implies a heavyweight design choice without naming it, and silently adopting that branch is the costliest mistake. Scan especially permission / visibility / access language for the either/or the whole design turns on. Example: *"members see a song only in playlists they can open"* reads as **navigation** (you see it if you already have access to the song) **or grant** (playlist access confers song visibility) - two different builds, and grant is usually far more expensive. Name it as Fork #1. If the PRD leans one way, that is a default to confirm, not a decision. (gadfly's Phase 1 Step 1b does the same check from the critic's side.)

### Step 2 - Ground in the code
Find and confirm the repo(s) (`--repo` hint, else `find` over `$PWD`, `$WORKSPACE` and `$HOME/Github`); stamp each with `cd <path> && git rev-parse --short HEAD`. Read each repo's `CLAUDE.md` and the hotspots the feature lands in (the model it writes, the query or API it changes) in full. **Ground inline, yourself** - a subagent hands back summaries, and the facts that decide a fork (a second caller in another repo, a filter applied once at the top of a file) sit in the code it didn't show you.

- **Vantage.** Do the core decisions (data model, permissions, storage) live in the repo you're in? If it only mirrors a model owned elsewhere, say so up front and ground the owning repo, or draft only this layer and say why. Don't design a data model from a repo that can't see the stores that decide it.
- **Comparable feature.** Search the product for a feature that solves a similar problem (an existing membership, collection, history or sharing mechanism). Study its data model and the decisions it already made, and record what the new feature should match and where it should diverge. **If extending that feature could satisfy the PRD, "extend `<feature>`" is a fork option in Step 4**, next to building new - with what the extension can't cover.
- **UI surface** (UI work only). Which frontend owns the surface, and is a migration between frontends in flight? An assumption about where the UI lives is often stale.
- **Numbers.** When the design rests on a size or volume (rows, events, field sizes, growth), measure it with a read-only data skill or tool if the session has one. If none can run, the number is `[assumed]`; presenting an unmeasured size as measured misleads every decision downstream.
- **Cross-service.** Never conclude what another service does from this repo's side; ground its repo, or mark it **Can't-determine (cross-service)**.
- **Cite or flag.** Every claim about current code carries `path:line` or `Can't-determine`. A claim that a list is complete ("the only callers are...", "every consumer of X") takes a search across every confirmed repo, every layer (`v1/` and `v2/`, legacy and rewrite) - one grep in one repo is not proof.

### Step 3 - Core model per store, and the simplest version that works
Name how the design represents its central entity/relationship in **every store** it touches: the primary DB and each secondary store (search index, cache, a permissions/graph store, another service's copy). The hard modeling decision usually hides in a secondary store. Name at least one structurally different alternative (a field on the item vs its own row/doc/entity), not a tweak. Prefer the model with the smaller interface and more behavior behind it.

For each design choice (pagination, enforcement mechanism, schema column, data format), name the simpler alternative and take it unless it breaks under a realistic V1 scenario. A comparable feature that uses the simpler approach is strong evidence.

### Step 4 - Enumerate the forks, then ask
List the genuine decisions the PRD and code leave open: the semantic fork from Step 1b, extend-vs-build from Step 2, the per-store model, what to defer, scope boundaries (containers? bulk? recursive? cycles?). Lay out each fork's options and trade-offs neutrally.

Mark an option **Recommended** only if you grounded its trade-offs in the repo that decides it; a fork that hinges on an ungrounded repo gets options without a recommendation, flagged as such.

Order forks by dependency - the semantic fork is almost always upstream and collapses half the rest. Then:
- **Independent forks:** one `AskUserQuestion` (≤4), recommended option first with its rationale and the trade-off it accepts.
- **Coupled forks:** ask the upstream one first, re-derive the downstream options from the answer, and tell the user why before asking:
  > *"Navigation-only it is. That changes the next decision: with no per-playlist permission to store, a playlist list on the song doc is now viable, and a separate membership doc only earns its cost if you need to filter on added-by or position. Is that a V1 need?"*
- **No human:** resolve in the same dependency order with the recommended option at each step, tag each `[assumed]` (see "Who answers the forks").

## Phase 2 - Draft the spec

Write a spec that pre-answers what gadfly attacks. **Every design claim is tagged** `[grounded: path:line]` or `[assumed]`; a claim you can neither ground nor get decided becomes an open question. Tags certify premises, not that the design is right.

Spec sections (omit one only with a stated reason):
1. **Goal & scope** - what it does, non-goals, deferred items.
2. **Requirements** - functional + NFR, with their tags.
3. **Design** - the chosen per-store model and why, the rejected alternatives and why not.
4. **Data model** - schema, fields, indices per store, grounded against what exists.
5. **API / query changes** - endpoints and queries touched, with `path:line`.
6. **Lifecycle & edges** - create / move / delete / soft-delete + restore / cascade, concurrency, cross-entity effects. An unresolved edge is an open question, not "handled".
7. **Failure modes** - what breaks in prod, blast radius per seam.
8. **Scale** - arithmetic against the NFR numbers; missing numbers are flagged, never invented.
9. **Cross-service impact** - grounded or `Can't-determine`.
10. **Open questions** - forks left to the human, every `[assumed]`, every unresolved edge. Investigate before listing: a question a grep, schema read or UI inspection can answer gets answered, not listed. Only questions that need product or organizational input belong here.

**Cut what has no V1 consumer** before saving: schemas for features with no code yet, columns that duplicate another field, infrastructure for problems V1 scale doesn't have (note the trigger instead), abstractions with one implementation. Record it: `YAGNI: <what was cut>` or `YAGNI: nothing cut`.

**Save** a new file at `~/.claude/reports/forge/<slug>.forge.<ts>.md` (absolute path; `<ts>` from running `date +%Y%m%d-%H%M%S`; never inside a repo; never overwrite a prior run), in the layout under "Report". `--no-temper` → stop after saving: print the chat echo, say the draft is unhardened, recommend `/gadfly`.

## Phase 3 - Temper (gadfly in a fresh context)

The author can't honestly critique its own draft, so the critic runs as a **subagent (`Agent`) that invokes the real gadfly skill** - isolated context is the point here:
```
Agent task: "Use the gadfly skill on `<the .forge.<ts>.md path>` with `--prd <original PRD path/url>`.
Repos (confirmed): <name> at <abs path> @ <sha>, one per repo you grounded.
Run it fully - every phase. Return its complete output verbatim (the ranked findings + open questions)."
```
- It must be the harness-loaded gadfly skill, not a re-described critique - a pasted imitation runs shallower.
- Pass the confirmed repos: gadfly can't ask you to confirm them from inside an Agent.
- gadfly re-grounds from scratch; that independence is what the extra cost buys.

## Phase 4 - Revise once

Start after the gadfly result arrives. If it errors or returns no Sinks / Blocker / Handle structure, write `Temper: failed - <reason>` and stop; never substitute a self-critique.

Act on each finding by **kind**, not severity:
- **Adds missing coverage without changing a chosen option** (a failure mode, an uncovered requirement, a wrong or uncited code claim, a lifecycle edge, a scale gap) → fix it in the draft; re-ground any code claim you change.
- **Changes a chosen option** (model, store, schema, semantics) or surfaces a decision nobody asked → it's a fork: ask (or, with no human, keep the current choice, record the finding as a residual, and add it to the open questions).
- **Unclear which** → treat it as a fork; a wrong auto-fix silently bakes forge's guess into the spec.
- **Can't resolve in one pass** (needs data, a cross-service unknown, a `[PRD]` contradiction only product can settle) → residual. Never fake a fix.

One pass only: a second author-fix loop polishes forge's own assumptions and runs cost away.

## Report

The saved file, updated after Phase 4:

```markdown
# <feature> - tech spec draft (forge)
<PRD stamp> · repos: <repo @ sha, ...> · temper: <N fixed, N residuals | skipped (--no-temper) | failed: reason>

## Decisions for you
| # | Fork | Chosen | How | Why it matters |
|---|---|---|---|---|
| 1 | <grant vs navigation> | <option> | asked / [assumed] | <what flips if the other option wins> |

**Unresolved from gadfly:** <Sinks/Blockers forge could not fix, one line each - or "none">

## Plan
Goal · vantage · comparable feature (match / diverge / extend option) · UI surface · requirement counts · core model per store + alternative · Not analyzed

## Spec
<sections 1-10>
YAGNI: <...>

## Temper report
Fixed: <finding → change, one line each>
Residuals: <finding → why not fixed>

Next: this draft survived one gadfly pass with <N> residuals. Before building, run a fresh `/gadfly <this file> --prd <prd>` (or `/jury gadfly ...`) - target: 0 unaddressed Sinks/Blockers.
```

**Chat echo** - print this and stop; never `cat` the file back:
```
forge: <feature> - <N> decisions for you, <N> [assumed] · temper <N fixed, N residuals>
Root fork: <fork> → <choice> (<asked | [assumed]>)
Biggest residual: <the one most likely to sink the design>
Draft → <absolute path>
  (adds the decisions table, plan, 10-section spec, temper report)
Next: run a fresh /gadfly on the draft before building.
```

## Completion contract
Done only when the saved file has all of these; for one that can't exist, say why:
1. The **Decisions for you** table - every fork with its choice and asked/`[assumed]` - and the unresolved-from-gadfly line.
2. The Plan with repos + SHAs, the comparable-feature result (or "none found" with what was searched), and the core model per store with an alternative.
3. The 10 spec sections, every design claim tagged `[grounded: path:line]` or `[assumed]`, and the `YAGNI:` line.
4. The temper report (unless `--no-temper`) and the "Next: run a fresh /gadfly" line.

## Guard rails
- **Read-only on inputs.** forge reads the PRD and the code and writes only its draft file; it never edits them or posts to Confluence. This is an instruction, not a grant boundary: `curl`, `Write`, `Edit` and `find` are granted for fetch, draft and repo lookup, and could write.
- **Don't out-scope the PRD.** Draft what it asks plus the forks it forces; flag gold-plating as a non-goal.
