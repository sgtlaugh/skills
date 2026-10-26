---
name: forge
description: Turn a PRD into a grounded tech-spec draft - ingest the WHY, ground in the code it lands in, surface the design forks for you to decide, then draft a spec structured to survive review. Pairs with gadfly (the critic) - forge authors, gadfly tempers. A grounded draft, not a finished spec.
trigger: /forge
allowed-tools: Read, Write, Grep, Glob, Bash(curl:*), Bash(jq:*), Bash(pandoc:*), Bash(cat:*), Bash(grep:*), Bash(find:*), Bash(head:*), Bash(stat:*), Bash(mktemp:*), Bash(git rev-parse:*), Bash(git -C:*), Bash(git log:*), Bash(git show:*), Bash(date:*), WebFetch, Agent, AskUserQuestion
---

# /forge - author a spec from a PRD, then temper it

A blacksmith's forge: raw PRD in, drafted, **stressed by gadfly**, hardened spec out. forge writes the first grounded draft of a tech spec from a product requirements doc - and (default) hands it to **gadfly** for an independent adversarial pass, then self-corrects once.

**Honest ceiling - read this.** Generation has no oracle. An LLM will draft *plausible-but-wrong* architecture confidently, and a spec gets **built**. forge is safe only because (a) it **grounds every design claim in real code** (or flags it `[assumed]`), (b) it **never decides a genuine product fork** - it asks you, and (c) the **gadfly temper pass is the real critic** (forge can't honestly judge its own draft). Even then the output is **"survives gadfly," not "correct"** - it inherits gadfly's blind spots (e.g. second-order collision edges). Treat forge's spec as a strong *grounded first draft pre-hardened against one review round*, never a finished spec. The human makes the calls; forge does the legwork.

**Pairs with gadfly.** forge authors (this skill); `gadfly` critiques. The loop is `forge → gadfly → revise`. If you already have a human draft, skip forge and just run gadfly.

## Usage

```
/forge <prd-path>            # local PRD: .md / .txt / .pdf / .docx
/forge <prd-url|page-id>     # Confluence PRD
/forge <prd> --repo <hint>   # hint the repo(s) the feature lands in (else forge discovers)
/forge <prd> --no-temper     # draft only - skip the gadfly temper pass (cheap, faster)
```
For jury-grade confidence, don't bolt it onto forge - run `/jury gadfly <forge-output> --prd <prd>` **yourself** on the finished draft (the pass-check below reminds you). That's a cleaner, fresh-context grade than nesting jury inside the run.

Cost: a full run is ingest + ground + draft + a gadfly pass + revise ≈ **2-3x a gadfly run** (one measured full run: $5.35; gadfly alone has measured $1.3-4.8, so expect roughly $5-15). `--no-temper` is far cheaper (no gadfly). Worth it against the eng-weeks a wrong spec burns.

## Phase 0 - Ingest the PRD

Resolve the input to **PRD text + a version stamp**, recording what you could not read. This is **identical to gadfly's Phase 0** - Confluence (jira skill's Atlassian auth, fetch `body.export_view` + version + attachments) or local file (`.md/.txt/.pdf` Read directly; `.docx` via `pandoc -f docx -t gfm`), stamp = version or file mtime. **Read diagrams with vision** (download image attachments + Read) - a PRD's mockups/flows are prime spec material. Flag only the genuinely-unreadable as `Not analyzed`. (See the gadfly skill's Phase 0 for the exact curl/pandoc/diagram steps.)

The PRD is the **WHY**. forge's job is to author the **HOW** that satisfies it.

## Phase 1 - Ground the terrain and frame the decisions ("plumb")

The judgment-heavy phase. Goal: a grounded picture of where the feature lands + the **decisions only a human can make**, surfaced as questions - *before* a single line of spec is drafted.

### Step 1 - Extract PRD requirements
Pull every requirement, **classify each** `[Stated]`/`[Inferred]`/`[Missing]` (EARS-light where falsifiable), and include **NFRs** (scale / latency / consistency / availability) - a PRD that omits them yields an open question, not a guessed number. (Same discipline as gadfly Phase 1.)

### Step 1b - Hunt the PRD's load-bearing semantic fork (don't adopt its phrasing as settled)
A PRD's wording often **implies** a heavyweight design choice without naming it as a decision - and the costliest mistake is **silently adopting that implied branch.** Scan the PRD - especially **permission / visibility / access** language - for the **load-bearing either/or the whole design turns on.** Classic example: *"members see a song only in playlists they can open"* reads as either **navigation** (organize-only; you see it if you already have access to the song) **OR grant** (playlist access *confers* song visibility) - two radically different builds, and the grant branch is usually **far** more expensive (per-entity permission replication, graph fan-out). **Name that fork explicitly and make it Fork #1 in Step 4.** Never treat the PRD's phrasing as the decision already made - if the PRD leans one way, that's a *default to confirm*, not a settled fact. (This is gadfly's Phase-1b "name the core semantic fork" discipline; skipping it is how forge ends up building the heavy model the PRD's words implied, without ever offering you the cheap branch.)

### Step 2 - Ground in the code (lightweight - gadfly re-grounds rigorously later)
Find + **confirm** the repo(s) the feature touches (`--repo` hint, else `find` over `$PWD`/`$WORKSPACE` (your clones dir, if exported)/`$HOME/Github`; confirm before deep-reading; stamp `git rev-parse --short HEAD`). Read each repo's `CLAUDE.md` + the **hotspots** the feature lands in (the table/model it writes, the query/API it changes) in full. Note the **cross-service** dependencies (an external permissions/auth service, a queue consumer, a search indexer) - per gadfly Step 2b, never conclude on another service from your side alone; if a design choice hinges on it and its repo isn't readable, mark it **Can't-determine (cross-service)**.
- **Vantage check (state it up front).** Do this PRD's **core decisions** (data model, permissions, storage) live in the repo you're in, or somewhere else? If you're in a repo that only **mirrors** the real model (e.g. a frontend repo whose data model is owned server-side), **say so immediately** and name the owning repo. Then either **discover + ground that repo** (`find` the workspace - it's usually local) when it's central to the decisions, or tell the user *"the data-model decisions live in `<repo>` - re-run with `--repo <repo>`, or I'll draft `<this-layer>`-only."* **Don't draft a confident data-model design from a repo that can't see the stores that decide it.**
- **Comparable feature discovery.** Before deep-reading the hotspots, search the same product for features that solve a similar problem (an existing audit log, activity feed, change history, versioning system, notification log). Most features aren't novel within their own platform. If a comparable feature exists, study its data model, UI patterns, pagination strategy, retention policy, transaction model, and the decisions it already made. Document what the new feature should match and where it should diverge. This grounds design choices in proven patterns rather than first-principles invention, and pre-answers the "why didn't you do it like X?" reviewer question.
- **Frontend surface check.** When the spec includes UI work, verify which frontend codebase owns the target surface. Check for active migrations between frontend frameworks (e.g. a legacy SPA vs a newer micro-frontend). Look for existing components in the newer codebase that solve adjacent problems - the UI patterns may already be ported. An assumption about where the UI lives is often stale in products with multiple frontend layers.
- **Production data sampling.** When the design makes quantitative assumptions (row size, event volume, field sizes, storage growth), validate against production data before committing. Estimate first, sample second, design third. Use whatever read-only data skill or tool the session has (a log-search or index-query skill, a DB read replica) to measure actual values. If none can run, the number stays an estimate - tag it `[assumed]` in the draft; presenting an unmeasured size as measured is WRONG. Wrong size estimates cascade into wrong retention, partitioning, and infrastructure decisions.
- **Cite or flag.** Every claim about current code carries `path:line`, or it is `Can't-determine`. This grounding feeds the draft; the gadfly temper pass is the rigor backstop, so forge's grounding is for *material*, not the final word.

### Step 3 - Name the core model + alternatives (per store)
Name how the design would represent its **central entity/relationship in EVERY store** it touches - primary DB **and** each secondary store (OpenSearch, Mongo, Redis/cache, a permissions/graph store; a secondary store may live in another service). Name **≥1 structurally-different alternative** (e.g. *a field on the item* vs *its own doc/row/first-class entity*), not a tweak. The hard modeling decision usually hides in a SECONDARY store, not the DB. (Same machinery as gadfly's core-model step - here it's *design input*, not critique.) **Judge the candidate models with the deep-module lens** (`/fathom`): prefer the one whose interface is **deep** (more behavior, smaller surface) and whose seam has something actually varying across it; for a genuinely open interface choice, `/fathom --twice` to design it a few ways and compare on depth/locality/seam.

**Simple-first validation.** For every design choice (pagination strategy, enforcement mechanism, schema column, data format), explicitly name the simpler alternative and justify the added complexity. If the justification is weaker than "the simple version breaks under a realistic V1 scenario," take the simple version. This catches: cursor pagination when offset works, DB triggers when ORM guards suffice, extra columns that duplicate info already in another field, pre-defined schemas for systems that don't exist yet. A comparable feature that uses the simpler approach is strong evidence the complexity isn't needed.

### Step 4 - Enumerate the design FORKS, then HALT and ask
List the **genuine decisions** the PRD + code under-determine - the per-store model choice, a **semantic fork** (an either/or that changes the whole design - e.g. does an action just *organize* or also *grant access/permissions*?), what to defer, a **scope boundary** (does it apply to containers/groups? bulk? recursively? can it cycle?). For **each fork, lay out the options + trade-offs neutrally** - do **not** pick.

**This is the line that keeps forge honest: it never auto-decides architecture.**

**Ground-or-flag applies to *recommendations*, not just draft claims.** Stamp **"Recommended"** on a fork option **only if you grounded its trade-offs in the store/repo that actually decides it.** If a fork hinges on a repo you haven't grounded (the vantage check above), present the options **without** a confident recommendation and flag it: *"owned by `<repo>` - not grounded from here; re-run with `--repo <repo>` or treat as a `<backend>`-owned open question."* A confident "Recommended" you can't ground is the same bluff as an ungrounded claim in the draft - it just hides in a question instead of a sentence.

**First, order the forks by dependency** - which fork's answer *changes the options of, or eliminates,* another (e.g. an *organize-vs-grant* fork is upstream of a *storage-model* fork: pick "organize-only" and the per-permission storage option collapses). **The PRD-implied semantic fork from Step 1b is almost always the upstream root - ask it FIRST**; its answer often collapses half the downstream forks (and half the spec). Then:
- **Independent forks → batch them** in one `AskUserQuestion` (≤4), **recommended option first** (labelled + one-line rationale + the trade-off it accepts). Efficient when answers don't interact.
- **Coupled forks → walk them as a dependency-ordered dialogue, one at a time** (NOT one batch - a batch can't model "Q2's options depend on Q1's answer"). Ask the **upstream** fork first; then **re-derive the downstream fork from that answer** - its options may collapse, change, or vanish - and tell the user *why* before asking it:
  > *"Navigation-only it is. That changes the next decision: with no per-playlist permission to store, a playlist list on the song doc is now viable, and a separate membership doc only earns its cost if you need to filter or sort on the membership itself (added-by, added-at, position). So - is that a V1 need?"*
  Each answer reshapes the next question. This surfaces the coupling live instead of asking a downstream fork in a frame the user already invalidated.
- **Non-interactive (no human)** → resolve in dependency order anyway (upstream first, re-derive downstream), pick the recommended option at each, **record each as `[assumed]`**, add to residual open-questions. Never silently bake an un-asked fork into the spec.

### Step 1-4 output (before drafting)
```
## forge - Plan (<PRD title> @ <stamp>)
Goal: <one line> | Repos: <repo @ sha> | Not analyzed: <unread, or none>
Comparable feature: <name + repo, or "none found"> | What to match: <key patterns> | Where to diverge: <key differences>
Requirements: <count Stated/Inferred/Missing; NFR gaps as open questions>
Core model: <central entity> | per-store: DB <…> · ES <…> · <other> <…> | alternative(s): <structurally-different option(s)>
Forks (you decide): <each fork + options + trade-off> → asked via AskUserQuestion (or [assumed] if non-interactive)
```

## Phase 2 - Draft the spec (author)

Using the grounded facts + the human's fork decisions, write a spec **structured to survive gadfly's lenses** - i.e. pre-answer what gadfly attacks. **Every design claim is tagged**: `[grounded: path:line]` (rests on code you read) or `[assumed]` (a decision/guess - these are also the open-questions). A claim you can neither ground nor get decided becomes an **open question**, never a bare assertion. Tags certify *premises*, not that the design is right - don't let them fake rigor.

Spec sections (omit one only with a stated reason):
1. **Goal & scope** - what it does, and the explicit non-goals / deferred items.
2. **Requirements** - functional + NFR, from Phase 1 (carry the `[Stated|Inferred|Missing]` tags).
3. **Design** - the **chosen per-store model + WHY**, and the **rejected alternative(s) + why not** (so reviewers see the fork was weighed, not assumed). Cite grounding.
4. **Data model** - schema / fields / indices per store, grounded against what exists.
5. **API / query changes** - the endpoints/queries touched, grounded `path:line`.
6. **Lifecycle & edges** - create / move / delete / soft-delete+restore / cascade, and concurrency / cross-entity effects. Where a hard edge isn't resolved, say so (an open question, not a fake "handled").
7. **Failure modes** - what breaks in prod, blast radius, per seam.
8. **Scale** - arithmetic against the PRD's NFR numbers; numbers missing → flag, don't invent.
9. **Cross-service impact** - what other services this design's data/edges touch, grounded or `Can't-determine`.
10. **Open questions** - the forks left to the human + every `[assumed]` + every unresolved edge. **Resolve before deferring:** a question listed as "open" that is answerable by a grep, schema read, or UI inspection is a DEFECT. Before listing any question, run the investigation: grep the code, check the schema, read the existing UI components, query production data. Only "needs human decision" is valid when the answer genuinely requires product or organizational input that code inspection cannot provide. An uninvestigated unknown in the open-questions section wastes reviewer cycles and signals shallow grounding.

### YAGNI pass (after drafting, before save)
Walk every element in the draft and challenge it: **"Does the system/feature/infra this depends on exist today? Is there a V1 consumer?"** Cut anything whose justification starts with "when X ships," "for future flexibility," or "in case we need." Specific targets:
- **Deferred event types / schema definitions** for features that have zero code in the codebase - replace with a one-liner noting extensibility, not 50 lines of phantom schemas
- **Columns/fields** that duplicate information already in another field (e.g. a `type` column when the `id` value already encodes the type)
- **Infrastructure** (retention policies, purge jobs, partitioning strategies) for problems that don't exist at V1 scale - note the trigger point for adding them later instead
- **Pre-built abstractions** (interfaces, config layers, feature registries) with only one implementation

The YAGNI pass is a self-check, not a quality gate. Record what was cut in the draft (e.g. `YAGNI: removed 3 speculative webhook event types and an unused audit column`) so reviewers see the pass ran.

**Save** a fresh, self-contained draft to `~/.claude/reports/forge/<slug>.forge.<ts>.md` (expanded to an **absolute** path; `<ts>=$(date +%Y%m%d-%H%M%S)`; the Write tool creates the directory) - never inside a repo, where it would sit as an untracked file. Always print the absolute path so it's clickable/locatable, never a bare relative filename. Always a new file, never overwrite a prior run.

### After drafting
- **`--no-temper`** → stop here: emit the compact echo (below) + the file pointer. The draft is unhardened - say so, and recommend a `/gadfly` pass before anyone builds it.
- **Default** → proceed to **Phase 3** (the temper loop).

### Chat echo (compact - mirror gadfly's rules: never `cat`/re-print the file)
- one-line **Goal** + chosen **core model**
- the **forks** and how each was resolved (asked → answer, or `[assumed]`)
- the count of **open questions / `[assumed]` claims**
- `Draft → <absolute path>` + `(adds: full design · per-store model · lifecycle · failure modes · open questions - not in this summary)`

## Phase 3 - Temper (hand the draft to gadfly, fresh context)

The draft's author cannot honestly critique it (a self-judge rationalizes its own choices). So the critic must be **independent**: spawn a **subagent (`Agent`) that runs the real `gadfly` skill** on the draft, in its own fresh context.

```
Agent task: "Use the gadfly skill on `<the .forge.<ts>.md draft path>` with `--prd <original PRD path/url>`.
Run it fully - every phase. Return its complete output verbatim (the ranked findings + open questions)."
```
- **It must be the actual gadfly skill** (harness-loaded), not a re-described critique - a pasted imitation runs shallower. The subagent invokes gadfly via its own Skill tool.
- gadfly self-fans for grounding; **nested under this Agent it can't spawn its own subagents and will ground inline/serially** (its SKILL handles this) - slower, still full-fidelity. Accept it.
- gadfly re-grounds from scratch (it caps delegated citations at `med` and re-verifies) - that's the point: an *independent* opinion, not forge's grounding rubber-stamped. The re-ground cost is the price of a real critic.
- **Want jury-grade (union of N)?** Don't nest it here - run `/jury gadfly <forge-output> --prd <prd> --n 3 --headless` yourself on the finished draft (the pass-check recommends exactly this). A fresh, user-launched jury is cleaner and more trustworthy than one buried inside forge's own run.

Capture gadfly's findings (Sinks / Blocker / Handle, each with its `[SPEC]`/`[PRD]` tag + verify-by). These drive the single revise pass.

## Phase 4 - Revise ONCE (bounded - no second loop)

Walk each gadfly finding and act by **kind**, not severity:
- **Mechanical / grounding / coverage flaw** (a missing failure mode, an uncovered PRD requirement, a wrong/uncited grounding claim, an unhandled lifecycle edge, a scale gap) → **auto-fix in the draft.** Re-ground any code claim you change (`path:line`).
- **A genuine product/architecture FORK** gadfly surfaces (it found a decision you didn't ask, or your fork answer has a consequence the human must weigh) → **do NOT auto-resolve. HALT → `AskUserQuestion`** (recommended-first), then apply the answer.
- **Ambiguous kind - could be a mechanical fix OR a design call → ASK, don't auto-categorize.** The trap is forge *deciding the category itself* and auto-fixing something that was actually a judgment call (or deferring something fixable). When you're not sure whether a finding is "just patch it" or "a decision the human owns," **err toward `AskUserQuestion`** - one short question settles it, and a wrong auto-categorization silently bakes forge's guess into the spec. (Don't ask on the *clearly* mechanical ones - that's fatigue; ask only when the kind is genuinely unclear.)
- **A finding you cannot resolve in one pass** (needs data you don't have, a cross-service unknown, a `[PRD]` contradiction only product can settle) → **leave it as an explicit residual** (next phase). Do not fake a fix.

**One pass only.** Do not re-temper in a loop - a second author-fix-author cycle just polishes forge's own assumptions and runs cost away. The remaining findings are residuals, reported honestly - they are the agenda, not a failure.

## Phase 5 - Emit: tempered spec + honest residuals + pass-check

Update the saved `<slug>.forge.<ts>.md` with the revised spec, and append a **Temper report**:
```
## Temper report (gadfly @ <draft stamp>)
Fixed: <gadfly findings auto-corrected in this draft - one line each>
Forks resolved this pass: <fork → human answer, or [assumed]>
UNRESOLVED residuals: <gadfly finding → why not fixed (needs data / cross-service Can't-determine / [PRD] contradiction / depth-edge) - one line each>
Open questions for the human: <the forks + assumptions + unresolved edges that gate building>
```
- **Report residuals honestly - never hide an unfixed gadfly finding.** A Sinks/Blocker forge could not resolve stays visible; it is the most important output.
- **Pass-check (recommend, never self-certify):** end with - *"This draft survived one gadfly pass with N residuals. Before building, run a FRESH `/gadfly <this file> --prd <prd>` (or `/jury gadfly … --n 3 --headless`) - target: 0 unaddressed Sinks/Blockers."* forge does not grade itself; an independent fresh run is the bar.
- **Honest ceiling restated:** *"survives gadfly ≠ correct."* If gadfly's known blind spots apply (e.g. a second-order interaction edge - two features that collide only when exercised together), surface it as an explicit open question, **not** a silent "handled."

### Chat echo (compact)
- one-line **Goal** + chosen **core model**
- **Temper:** `<X fixed · Y residuals · Z open questions>`
- the single **most important unresolved residual** (the thing most likely to sink the design)
- `Spec → <absolute path>` + `(adds: full design · per-store model · lifecycle · failure modes · temper report · open questions)`
- the **pass-check** line (run a fresh gadfly)

Never `cat`/re-print the file (same reason as gadfly: it re-injects ~hundreds of lines, triple-renders). The pointer ends the run.

## Completion contract
A run is complete only when the saved file contains **all** of these - missing any = incomplete:
1. **Plan** - requirements (tagged), grounded repos+SHAs, comparable feature analysis (match + diverge, or "none found" with evidence of search), core model per-store + alternative, the forks (asked or `[assumed]`).
2. **Spec** - the 10 sections, every design claim tagged `[grounded: path:line]` or `[assumed]`. YAGNI pass applied (no phantom schemas, no unused columns, no premature infrastructure).
3. **Temper report** (unless `--no-temper`) - fixed / forks-resolved / **unresolved residuals** / open questions.
4. **Pass-check line** recommending a fresh independent gadfly/jury run.
5. **Saved file** - `<slug>.forge.<ts>.md`, fresh (never an overwrite).

## Guard rails
- **forge authors a DRAFT, not a verdict.** Output is "a grounded, gadfly-tempered first draft," never "the spec is correct." State the ceiling; the human owns the design.
- **Never auto-decide a genuine fork.** Product/architecture forks halt → `AskUserQuestion` (in Phase 1 and again if gadfly surfaces one in Phase 4); non-interactive picks are recorded `[assumed]` + listed as open questions. Silently baking an un-asked fork into the spec is the cardinal sin.
- **The critic is independent.** gadfly runs in a fresh `Agent` context - forge never self-critiques (a self-judge clears its own work).
- **One temper pass.** Auto-fix mechanical findings, halt on forks, leave the rest as honest residuals. Never loop author↔fix - it polishes assumptions and runs cost away.
- **Ground or flag every design claim.** `[grounded: path:line]` or `[assumed]`; ungroundable → open question. A tag certifies the premise, not the design.
- **Report residuals honestly.** An unfixed gadfly Sinks/Blocker stays visible - it is the agenda, not a failure to bury.
- **Read-only on inputs.** forge reads the PRD + the code; never edits them, never posts back to Confluence. It writes exactly one thing per run: the spec artifact (`<slug>.forge.<ts>.md`).
- **Don't out-scope the PRD.** Draft what the PRD asks (+ the forks it forces); flag gold-plating as a non-goal, don't invent features.
