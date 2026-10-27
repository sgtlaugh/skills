---
name: gadfly
description: Interrogate a tech spec or architecture doc before it gets built - extract requirements, gate the blocking gaps, ground the design in the code it touches, stress-test through four adversarial lenses. `--prd` checks whether the HOW satisfies the WHY. Hypotheses to check, not verdicts.
trigger: /gadfly
allowed-tools: Read, Write, Grep, Glob, Bash(curl:*), Bash(jq:*), Bash(pandoc:*), Bash(cat:*), Bash(grep:*), Bash(find:*), Bash(head:*), Bash(stat:*), Bash(mktemp:*), Bash(git rev-parse:*), Bash(git -C:*), Bash(git log:*), Bash(git show:*), Bash(date:*), WebFetch, Agent, AskUserQuestion
---

# /gadfly - sting the design awake

Socrates called himself Athens' gadfly: the small fly that stings a complacent horse into motion. This skill does that to a **tech spec / architecture doc** - questions it until its weak points show, *before* the team builds the wrong thing.

**Honest ceiling.** Spec review has no mechanical oracle. gadfly produces **hypotheses to check, not verdicts.** A wrong architectural criticism is expensive (sends a team chasing a flaw that isn't there). Treat the output as a sharp reviewer's worry list, and every finding ships a confidence + how-to-verify.

**Phases 0-3** (ingest → requirements gate → seam grounding → adversarial attack) + optional `--prd` WHY-vs-HOW coverage. Each phase earns its place: a spec whose requirements won't survive interrogation isn't ready to review, and grounding the seams is what keeps the attack honest instead of hallucinated.

## Usage

```
/gadfly <confluence-url>      # fetch + interrogate a Confluence spec
/gadfly <page-id>             # bare Confluence page id
/gadfly <file-path>           # local spec: .md / .txt / .pdf / .docx
/gadfly <spec> --prd <prd>   # also cross-check against a PRD (WHY-vs-HOW); prd = path or url
```

**Tip - review your own designs too, not just the original spec.** A proposed *solution* is itself a spec: once you've drafted an approach (a new schema, a permission model), run `/gadfly` on it. Most design flaws surface from interrogating the *solution*, not the brief - iterate design → `/gadfly` → refine.

## Phase 0 - Ingest the spec

Resolve the input to **spec text + a version stamp**, and record what you could NOT read. Never silently skip content.

### Confluence (URL or bare page id)

Same Atlassian auth as the jira skill. Shell state does not persist between tool calls - prepend these lines to EVERY bash call below that hits Confluence (the page fetch AND each diagram download):
```bash
C=${CLAUDE_SKILLS_CREDENTIALS:-$HOME/.config/claude-skills/credentials.json}
JIRA_URL=$(jq -r '.jiraBaseUrl // error("jiraBaseUrl unset in the credentials file")' "$C") || exit 1
JIRA_B64=$(jq -r 'if .jiraEmail and .jiraApiToken then "\(.jiraEmail):\(.jiraApiToken)" | @base64 else error("jiraEmail/jiraApiToken unset in the credentials file") end' "$C") || exit 1
```
Resolve the page id (URL `.../pages/<id>/...`, `pageId=<id>`, or a bare number), then fetch content + version + attachments:
```bash
PAGE="INPUT"
PAGE_ID=$(printf '%s' "$PAGE" | grep -oE 'pages/[0-9]+' | grep -oE '[0-9]+' | head -1)
[ -z "$PAGE_ID" ] && PAGE_ID=$(printf '%s' "$PAGE" | grep -oE 'pageId=[0-9]+' | grep -oE '[0-9]+' | head -1)
printf '%s' "$PAGE" | grep -qE '^[0-9]+$' && PAGE_ID="$PAGE"

# Private work dir: parallel runs on the same page (e.g. /jury gadfly) must not share files
G=$(mktemp -d /tmp/gadfly-XXXXXX) && echo "work dir: $G"
curl -sS --fail-with-body "$JIRA_URL/wiki/rest/api/content/$PAGE_ID?expand=body.export_view,version,space" \
  -H "Authorization: Basic $JIRA_B64" > "$G/page.json"
jq -r '"# \(.title)\nSpace \(.space.key) | Version \(.version.number) (\(.version.when)) | ID \(.id)"' "$G/page.json"
jq -r '.body.export_view.value' "$G/page.json" | { command -v pandoc >/dev/null && pandoc -f html -t gfm || cat; }
curl -sS --fail-with-body "$JIRA_URL/wiki/rest/api/content/$PAGE_ID/child/attachment" -H "Authorization: Basic $JIRA_B64" \
  | jq -r 'if (.results|length)>0 then (.results[] | "ATTACHMENT: \(.title) [\(.metadata.mediaType)] \(._links.download)") else "no attachments" end'
```
**If the fetch fails** - empty `PAGE_ID`, any `curl: (N)` on stderr, or the JSON carries `.message` / no `.id` (401/403/404) - **report it and stop.** A failed diagram download (any `curl: (N)`) means that attachment is unread - list it under **Not analyzed**, never `Read` the error page as the diagram. Don't review a half-fetched or empty page. Tiny links (`/wiki/x/..`) carry no numeric id; resolve the redirect (see the jira skill's tiny-link step) or ask for the page id.

**Version stamp** = `version.number (when)`. Record it - the review is a snapshot of that revision. (Full Confluence detail lives in the jira skill's Confluence section.)

### Local file
- `.md` / `.txt` / `.pdf` → Read directly (Read handles PDF).
- `.docx` → `pandoc -f docx -t gfm <file>`. No pandoc → say so, ask for an `.md`/`.pdf` export.
- **Stamp** = file path + mtime (`stat -c '%y' <file> 2>/dev/null || stat -f '%Sm' <file>`, GNU then BSD) - no version system.

### Diagrams - read them, don't punt (mandatory)
Specs put the schema / architecture in diagrams - often the most review-relevant content. **Download every image attachment and `Read` it (Read does vision on png/jpg)** - do not just list it. Save into the work dir the fetch printed (a literal path - `$G` does not survive between calls):
```bash
curl -sS --fail-with-body -L "$JIRA_URL/wiki<download-link>" -H "Authorization: Basic $JIRA_B64" -o <work dir from the fetch>/att_<safe-name>
```
Fold what the diagram shows (an ER diagram's tables/relations, a sequence/arch diagram's flow) into the spec understanding - it's prime material for schema/architecture findings, and lets you triangulate spec-prose ↔ diagram ↔ code.

**Only** flag as unread the attachments you genuinely can't parse (drawio/vsdx/sketch source, external links, a failed download):
> **Not analyzed:** `<names>`. The design may live in these - paste or describe them.

Never pretend a diagram was read - and equally, never punt one you could have read. (Lesson: didn't-read ≠ not-there.)

### PRD (optional - `--prd <path|url>`)
If `--prd` is given, ingest the PRD the same way (Confluence or local file) and **version-stamp it too.** Two docs now: the **spec = HOW**, the **PRD = WHY**. Diagram + stamp rules apply to both. The PRD feeds the coverage check in Phase 1. **Without `--prd`, skip all PRD logic - gadfly behaves exactly as before.**

**Parallel fetch:** spec and PRD are independent - fetch both as parallel tool calls in ONE message when `--prd` is given.

## Phase 1 - Requirements gate (the interrogation)

Goal: a concrete, falsifiable requirements list - **or** the questions that block one.

### Step 1 - Extract before asking
Read the whole spec first. **Explore before you ask** - never ask what the spec already answers. Pull out every requirement and **classify each**:
- **[Stated]** - written in the spec.
- **[Inferred]** - you concluded it; the spec implies but doesn't say. Mark for confirmation.
- **[Missing]** - load-bearing, not answered.

Write requirements **EARS-light**: use a falsifiable shall-statement where it sharpens the requirement (`When <trigger>, the system shall <action> within <measure>`), plain bullets otherwise. Don't force the ritual - falsifiability is the point, not the grammar.

**Must include Non-Functional Requirements** - they are the ammo a real review needs: scale (rate / volume / growth), latency / throughput, consistency model, availability / SLA, failure tolerance. A spec that omits them produces NFR **findings** (below), not silence. An **[Inferred]** NFR must **cite the spec passage it's inferred from** (or state *"no basis in spec - assumed from <existing-system convention>"*) - an inferred number with no cited basis is a bluff; name where it came from.

Also detect **spec type**: greenfield (net-new) vs change-to-existing (touches a running system). Record it - it changes what later phases ground against.

### Step 1b - PRD coverage (only if `--prd`)
**First, PRD internal coherence (required output).** Cross-compare the PRD's own requirements for **mutual contradiction** (e.g. *"every user sees the same view"* vs *"visibility is scoped per group"* - both can't hold at once). Emit **`PRD internal conflicts: <list> | none`**, and when the design hinges on it, **name the core semantic fork** the product must resolve (the one either/or the whole design turns on). A contradictory requirement is a `[PRD]` finding - the spec can't satisfy an incoherent ask, so this fires every run (often `none`).

The PRD is the **WHY**, but it is a **claim, not an oracle** - it can be infeasible, contradictory, over-scoped, or vague. Extract the PRD's requirements (EARS-light where falsifiable), map the spec (HOW) onto each, and **adjudicate the gap** - never auto-blame the spec:
- **Covered** - spec delivers it (cite where). ✓
- **Gap `[SPEC]`** - PRD reasonable, spec silent → finding against the spec.
- **Deviation, justified** - spec does it differently *with a stated reason* → note as a trade-off; sanity-check the reason. Not a finding unless the reason is weak.
- **Deviation, unjustified** - spec differs *silently* → finding `[SPEC]` (state the reason or close it).
- **PRD-questionable `[PRD]`** - the requirement itself is infeasible / contradicts another PRD req / over-scoped / vague → finding against the **PRD**; the spec's non-compliance may be *correct*.
- **Scope-creep** - spec exceeds the PRD → low-severity flag (possible gold-plating).

Rules: **steelman both** the PRD ask and the spec's approach before judging; **cite both** (quote the PRD requirement + the spec's coverage/deviation); most gaps resolve with a human, so **frame them as questions** ("unmet, or a justified deviation? confirm with product"). **No manufactured `[PRD]` pushback** - lodge one only with a concrete reason (a contradiction, an infeasibility grounded in code/scale, a clear over-scope), never "I'd design the product differently." **`[PRD]` findings cap at `med`** - judging the product ask is more subjective than checking coverage. **Don't double-count** a gap already raised as an internal spec gap (Step 2).

### Step 2 - Gaps are findings; block only when forced
Most missing/ambiguous items are **findings** - the spec *should* have specified them. Record them and move on. Do **not** turn every gap into a blocking question (that makes gadfly a nag).

**Hard-block ONLY when a gap makes the review impossible**, e.g.:
- no clear goal / problem statement → nothing to review against.
- zero scale numbers when the design's whole risk is scale → can't assess it.

For a hard-block, ask via `AskUserQuestion`:
- **Structured by default** - offer concrete options, the **recommended one first** (labelled), with a one-line rationale. Open-ended only when options can't be predetermined.
- **Reject vague** - "make it fast" is not an answer; ask for the number ("p99 < 200ms?").
- **Batch independent gaps** (≤4 per round). If one gap's answer changes another, ask the prerequisite first in its own round.
- Non-interactive (no human) → state the assumption explicitly, record it as a finding, proceed.

### Step 3 - Output
```
## gadfly - Requirements (<spec title> @ <version/stamp>)
Goal: <one line>
Type: <greenfield | change-to-existing>
Not analyzed: <unread diagrams/attachments, or "none">

Functional:
- [Stated] When <trigger>, the system shall <action>.
- [Inferred] The system shall <...> (from §<ref>) - confirm.

Non-functional:
- [Stated] scale <n> · latency <n> · consistency <model>
- [Missing] <NFR> - FINDING: spec doesn't specify.

Gaps (findings - spec should have specified):
- <gap> §<ref>

Gate: <READY to review | BLOCKED - N questions below>
```
- `BLOCKED` → ask the questions (Step 2), then stop. Don't proceed on a guess.
- `READY` → proceed to **Phase 2**.

## Phase 2 - Ground the design in the code (seams only)

Runs only when the gate is `READY`. Purpose: understand the **terrain the design lands in.** The design is unbuilt, so there is nothing to *verify* in code - you ground the **existing systems it touches** so the coming attack rests on facts, not guesses.

**Greenfield** (from the Phase 1 type) → no existing seams. State *"net-new - no code to ground against"* and skip to the summary.

### Step 1 - Discover & confirm the repos (mini-gate)
List the repos/services the design touches, each `[Stated]`/`[Inferred]`. Locate each locally:
```bash
# $WORKSPACE = the directory holding your clones, when exported
for root in "$PWD" ${WORKSPACE:+"$WORKSPACE"} "$HOME/Github"; do
  find "$root" -maxdepth 3 -type d -iname "REPO" 2>/dev/null
done
```
Present the found path(s) and **confirm before reading** - a deep-dive on the wrong repo is wasted work. Not found or ambiguous → ask the user for the path. Non-interactive (no human) → proceed with an **unambiguous** match; if ambiguous or absent, mark it *not grounded* and move on - never guess a repo. (The repo-confirm gate: cheap insurance against grounding the wrong code.)

Also list **services the design's correctness depends on even if it doesn't edit them** - an external auth/permissions service, a queue consumer, a search indexer. These are grounding targets too (Step 2b) when a finding will hinge on their behaviour.

**Stamp each confirmed repo's baseline:** `git -C <path> rev-parse --short HEAD`. The review is a snapshot of that commit - record it like the spec version (and it tells a later reader whether the grounding is stale).

### Step 2 - Read the hotspots thoroughly (calibrated - not a keyhole, not the whole repo)
For each confirmed repo:
- **Read its `CLAUDE.md` first** - conventions + architecture in one cheap read.
- Identify the **hotspots** - the files/modules the design most touches or depends on (the table/model it writes, the API/query it changes, the function it modifies). Rank by centrality to the design.
- **Read each hotspot file in full - not just the cited line.** Batch multiple file reads as parallel tool calls in one message - don't read file 1, wait, read file 2, wait. The invariants that decide whether a finding is real live in the *surroundings*: the builder that assembles a query, a filter applied once near the top, a base class, a shared validator. (Real miss: a permission filter applied globally at the top of a file made a "this function has no permission check" finding **false** - reading the whole file, not the one function, catches it.)
- **Follow the context the design's correctness depends on** - a hotspot that calls a global filter / inherits a base / uses a shared util: read that too. Bounded by *relevance to the design*, not exhaustiveness.
- **The bound:** a *few* hotspots, read *deep*. Not the seam line alone (the keyhole that ships false findings), not the whole repo (cost trap). When unsure whether surrounding context matters, read it - a cheap-but-wrong review costs more than a dearer-right one.

**Execution (fan-out + degrade).** With several repos, delegate grounding to **one subagent per top repo, in parallel** - the few the design most changes (typically ≤4; skim the rest). For 1-2 repos, ground inline - the subagent tax isn't worth it. **If you cannot spawn subagents - you're running nested (e.g. under `jury`) - ground inline yourself, serially. Never skip grounding to work around the limit.** Either way the assembler re-verifies top-severity citations itself (Phase 3) - a subagent's report is `[Inferred]` until reproduced.

### Step 2b - Cross the service boundary (follow the data)
A finding often hinges on what **another service** does with the data this design touches - e.g. *how service B computes a result from what service A sends it.* **Never conclude on another service's behaviour from your repo's side alone.** If a `Sinks`/`Blocker` would depend on it:
- **Locate that service's repo** (same `find` over the workspace roots) and **ground a hotspot there** - read the function that consumes/computes the thing.
- If its repo isn't available → mark the dependency **Can't-determine (cross-service)** and hand to the human; do **not** assume.

This is the recall fix: handing *every* cross-service question to darkmoon or a human misses what only reading the **other** service reveals (e.g. that its inheritance graph can't take the design's new shape). Ground it yourself when a top finding rests on it.

### Step 3 - Cite or drop
Every claim about how the current code works ships its evidence:
- **Run grep/read and cite `path:line`.** Never eyeball-trace.
- Can't ground it → write **Can't-determine** (not found in scope, or behavioral/runtime - a static read can't decide a race or deadlock). Don't bluff.
- **Confidence caps at medium** where a dynamic escape hatch hides the truth (reflection, runtime registration, config-driven dispatch).
- **Absence claims need the same rigor** - "X doesn't exist / no such method / unused / missing" is a claim, and **one negative grep is not proof.** Confirm the exact name, the **whole repo across every layer** (e.g. a legacy layer vs an active rewrite like `v1/` vs `v2/` - a symbol absent from one lives in the other), aliases, and re-exports before asserting absent; an unconfirmed absence caps at `med`, never `high`. (A confident-wrong "it's missing" sends the author to fix a non-problem.)

### Step 4 - Output
```
## gadfly - Grounding (<spec> @ <stamp>)
Repos: <repo> (<path> @ <short-sha>) [Stated|Inferred]

Seams (what the design touches, and what the code does there now):
- <seam> - <current behaviour> `path:line`. <high|med>
- <seam> - Can't-determine - <not found in scope | behavioral>

Not grounded: <seam/repo you couldn't read, or "none">

Cross-service dependencies: <service → grounded `repo@sha` (what its code does with the data) | or Can't-determine (cross-service) → hand to human. "none" if self-contained.>

Fit-to-architecture (change-to-existing): <does the design respect the existing invariants/patterns you read in full - global filters, established conventions - or fight them? Misfits are findings.>

Terrain for the attack:
<2-4 lines - the real constraints the design lands in, the facts Phase 3 will attack against>
```
Then proceed to **Phase 3**.

## Phase 3 - The attack (sting the design)

Runs after grounding. Attack the design through four lenses. Each lens is a **fixed question with a must-produce** - vague prompts ("consider scalability") don't fire; a fixed question with a required artifact does.

### Steelman first (fairness)
Before attacking, restate in 1-2 lines what the design gets **right** and why the approach is reasonable. A reviewer who only attacks is noise. Can't steelman it? You haven't understood it - re-read before you sting.

### Core model - name it per store, then the lenses attack it
Before the lenses, **name how the design represents its central entity/relationship in EVERY store it touches** - the primary DB (source of truth) **and** each derived/secondary store (OpenSearch, Mongo, Redis/cache, a permissions/graph store). Then stress-test the **modeling choice itself**, not just features:
- **Per store** - each store's constraints differ, so a model fine in one breaks in another: DB (rows/FKs - flexible); **OpenSearch** (one doc = one hit, no joins → e.g. a membership as a *field on the item* vs its *own doc*); **graph** (traversal/path cost → multi-parent explodes); **cache** (invalidation / TTL). **The hard modeling decision usually hides in a SECONDARY store, not the DB** (a secondary store may live in *another service* - ground it, Phase 2 Step 2b).
- **Cross-store sync** - denormalization fan-out, cascade on delete/restore, eventual-consistency windows between stores.
- The question: does the chosen representation **hold under all features at once** (permissions + moving + search + multi-actor), or does it leak? A leak here is a model finding (often `Sinks`/`Blocker`).
- **Required output (emit every run):** `Alternative model(s) considered: <e.g. membership as a field on the item vs its own doc / its own row / a first-class entity> | none viable because <reason>`. Name at least one *structurally different* representation than the one the design chose (not a tweak of it), then say why the design's choice wins or loses against it. *"None viable because <X>"* is a valid honest answer - never invent a strawman to fill the line. This is the line that catches a spec that quietly assumed one model (e.g. membership as a field on the item) without weighing the alternative (its own entity).

### The four lenses
Run all four against the design **and the core model named above.** Each must either land a concrete finding **or** explicitly clear the design with a cited reason (*"resilient because <X> `path:line`"*). **Never manufacture findings** - a lens that finds nothing real says so. A clean lens is a valid result, not a failure to look hard enough.

1. **Failure** - what breaks in prod? Per component/seam: it fails, partial failure, retries double-write, a dependency is down, network partition, the migration half-applies. What's the blast radius?
2. **Scale** - does it hold at the **Phase-1 NFR numbers**? **Show the arithmetic** against the stated scale (NFR targets, or facts like incident volumes). Exceeds a limit → finding. "Seems fine" with no math is not a finding. No scale numbers stated anywhere → that absence *is* the finding (scale unassessable - the spec must provide them), not silence.
3. **Complexity / fit** - more complex than the problem needs (overengineering, premature abstraction, a "just"-trap hiding real work)? Long-term debt / lock-in that's hard to reverse? Or does it **fight the existing architecture** - an invariant or pattern you read in grounding (a global filter, an established convention)? Ignoring an established invariant is debt/risk. Name the simpler or better-fitting path if one exists.
   - **Prior art (if a well-known analog exists - emit this or "no known analog").** Does the design implement a pattern mature products already solved (multi-location references, soft-delete, feeds, sharing, undo)? If so, **`WebFetch` an authoritative source** (engineering blog / official docs) for how e.g. Drive / Dropbox / Figma / a file-system does it **and WHY**, then **check whether their reason applies to our constraints** - **borrow the reasoning, not the conclusion** (their perm model/scale ≠ ours; the pattern transfers only if the *pressure* does). **Guards:** cite the source; **cap at `med`** (internal design is inferred from behaviour + writing, not ground truth); separate **observable behaviour** (higher) from **inferred internals** (lower); **never assert from memory** - fetch or skip. A design that **diverges from the established pattern without a reason that holds here** is a finding. (Why this earns its cost: prior art encodes the resolved answer to the exact edge-case pile - it can collapse a long rediscovery into one cited check.)
4. **Edge cases & lifecycle (stress-test each, don't just visit)** - for **each** dimension below, **play out a concrete adversarial sub-scenario**, then emit a finding **or** *"cleared - <reason>"*. **Clear only after a stress fails to break it** - "handled" / "looks fine" without a played-out scenario is the false-clear that misses real edges. Never force a finding (cleared is valid); never skip a dimension.
   - **Inputs:** empty / huge / concurrent / duplicate / out-of-order / null, at named spec points.
   - **Lifecycle** (per new entity/relationship): create / move / **delete** / **soft-delete + restore** / cascade - what happens to the thing *and* to whatever references it? (Stress *move*: destination already references it? another actor moved it? it moves back later? Stress *restore*: what reappears, and who created it?)
   - **Scope boundary:** enumerate the adjacent capabilities the design implies (e.g. does the operation also apply to a container/group? in bulk? recursively? can it form cycles?) and flag the ones the spec is **silent** on.
   - **Concurrency:** two actors on the same entity at once.
   - **Cross-entity:** when the source changes/moves, what happens to derived/denormalized data?

### Binding rules (every finding)
- **Quote the spec.** Cite the §/line the finding attacks. No spec citation → drop it (you're attacking your imagination, not the spec).
- **Concrete trigger → consequence.** *"§3 fan-out: 10k orgs × hourly = 240k jobs/day on one worker → backlog by week 2."* Not *"scalability concern."*
- **Code claims cite or drop** (the Phase-2 reflex): a claim about current code ships `path:line`, or it's Can't-determine.
- **Rank by impact:** `Sinks` (design fails its own goal) / `Blocker` (must fix before launch) / `Handle` (fix in-flight).
- **Confidence tracks the weakest link - usually the interpretive leap, not the citation.** A grounded local fact (`one line has no clause`) under a shaky system-wide inference (`all browsing changes`) is a *shaky* finding - rate it by the leap. **A finding without its shown evidence (grep output, line read, doc cited) caps at `med`, never `high`** - if you didn't show the verification, it's not verified. **+ how-to-verify** on each: the report is a hypothesis list, not a verdict; hand the reader the check that settles it.
- **Provenance cap.** A code claim citing a `path:line` *you* (the assembler) did not personally grep - e.g. a grounding subagent's report - caps at `med` until you re-run it. Delegated grounding is `[Inferred]` until reproduced.

### Self-check (run before emitting each finding - drop if any is true)
- Attacks a **strawman**, not the spec as written.
- **Vague** - no concrete trigger or no spec citation.
- **Uncited or unreproduced** code claim - no citation, or a citation that doesn't resolve when you re-run it.
- **Generic slop** - you'd raise it against *any* spec (a best-practice lecture, not a finding about THIS design).

### Refute your own finding (interpretation check - Sinks/Blocker)
A **correct citation can still carry a wrong interpretation** - the cited fact may not mean what the finding concludes once the wider system is accounted for (a line with no permission clause isn't a hole if permissions are applied globally elsewhere). Verifying the citation resolves is necessary but **not sufficient** - you must verify the *interpretation* too. Before emitting any `Sinks`/`Blocker`, **state its falsifier and check it**:
> *This finding is FALSE if `<X>`. Did I check `<X>`?*
- The falsifier is what would make the conclusion wrong: "no permission check here" → *false if permissions are applied elsewhere* → check the query builder. "missing validation" → *false if validated upstream*. "race condition" → *false if a lock exists*.
- **Couldn't check the falsifier → cap the finding at `med` and make the falsifier its `verify by`.** Never ship a `high` Sinks/Blocker whose falsifier you didn't test.
- One reflex, not a rule per category - it forces the look-elsewhere that thorough hotspot reading (Phase 2) should already have done, and catches what slipped.

### Re-verify before you escalate (Sinks/Blocker code-claims)
A top-severity finding earns its rank only if its evidence **reproduces.** Before emitting any `Sinks` or `Blocker` that rests on a code claim, **re-run the citation yourself** - re-grep / re-read the cited `path:line`. Do **not** trust a grounding subagent's report at face value: a parallel fan-out hands you claims you never ran.
- Citation resolves + the code says what you claimed → keep it at its confidence.
- Citation doesn't resolve → **before you drop it, clear the absence bar (Phase 2 Step 3)** - whole repo, every layer, aliases. **A careless drop turns a REAL finding into a false negative** - the costlier error (a true Sink, silently discarded). Only after a rigorous search is empty: re-ground, downgrade to `Can't-determine`, or drop. Never escalate on a citation you couldn't reproduce; never drop on a grep you didn't scope.
- **Re-grep the EXACT symbol the claim names** - the thing that allegedly does the harm, not a supporting one. *"destructive because `replace_order_items` calls `delete_line_items`"* → grep `def replace_order_items`; if **that** is absent the finding is dead, even though `delete_line_items` exists. Confirming a related symbol is a false pass.

This is cite-or-drop with teeth - it catches the dangerous case (a confident, well-formatted, *wrong* citation) that plain "cite or drop" misses when the citation merely *looks* present.

### Output
```
## gadfly - Review: <spec title> @ <stamp>
Type: <greenfield|change-to-existing> | Not analyzed: <diagrams, or none>

Steelman: <what the design gets right, 1-2 lines>

### [Sinks|Blocker|Handle] <finding title> - §<ref> `[SPEC|PRD]`
Trigger: <concrete scenario> -> <consequence>
Evidence: <spec/PRD quote / `path:line` / the arithmetic>
Confidence: <high|med|low> - verify by: <the check that settles it>

(... one block per finding, Sinks first, then Blocker, then Handle. The `[SPEC|PRD]` tag appears only with --prd ...)

PRD internal conflicts / core fork (only with --prd): <contradictions within the PRD itself + the semantic fork product must resolve, or "none">
PRD coverage (only with --prd): <table - PRD requirement | Covered / Gap / Deviation / PRD-questionable / Scope-creep | note>

Cleared: <lenses that found nothing real + the cited reason each held>
Open questions: <the few the author must answer before building>
```
- **No real findings → say so:** *"Holds against all four lenses - <cited reasons>."* Don't invent nits to look useful.
- **Save a fresh, self-contained report** to `~/.claude/reports/gadfly/<spec-slug>.gadfly.<ts>.md` (expanded to an **absolute** path; `<ts>=$(date +%Y%m%d-%H%M%S)`; the Write tool creates the directory). Never inside the reviewed repo - a report saved to the working directory leaves untracked files in the codebase under review. Always print the absolute path so it's clickable/locatable, never a bare relative filename. **Always a new file; never `Update` or overwrite a prior run's report.** Merging into an old report inherits its stale/false findings and masks run-to-run disagreement; a second run must be an *independent* opinion. The file holds Requirements (Phase 1) + Grounding summary with repo SHAs (Phase 2) + this Review; the chat echo is a compact scannable summary (next bullet), not the prose report. Never post back to Confluence.
- **Chat echo format - scannable, but carry the high-signal one-liners:**
  - a one-line **Steelman**
  - the **ranked table** sorted Sinks→Blocker→Handle, one line per finding (title only): `| Sev | Finding | §ref | Conf |` (with `--prd`, add a `Tag` column for `[SPEC]`/`[PRD]`)
  - the **core-model line** - `Alternative model(s) considered: <…> | none viable because <…>` (one line, high signal - it's the modeling fork)
  - with `--prd`, the **PRD fork** line (the semantic fork the product must resolve)
  - the single **most important open question**
  The per-finding detail (trigger / evidence / falsifier / verify-by / per-store model / PRD coverage table) lives in the **file** - don't reprint it in chat.
- **Point at the file as the fuller artifact, not a copy.** The saved-report pointer must make clear the file holds *more* than the chat summary - never a bare "saved: <path>" that reads like a duplicate:
  ```
  Full report → <absolute path>
    (adds: per-finding trigger / evidence / falsifier / verify-by · the per-store core model · the PRD coverage table - none of which is in the summary above)
  ```
- **Never `cat` / re-print the report after saving.** The file is written; the chat already has the compact echo. `cat`-ing the saved file re-injects all ~250 lines back into the conversation - it re-pollutes context, costs tokens twice, and triggers a redundant re-summary (the report ends up printed 2-3×). The pointer line is the end of the run: print it and **stop**. The user opens the file in their own editor/pager, outside the agent loop. Do not offer to open it inline.
- **With `--prd`:** tag each finding `[SPEC]` (fix the design) or `[PRD]` (revisit the product ask), include the PRD Coverage table, and stamp the PRD version next to the spec. `[PRD]` findings cap at `med`.
- **darkmoon handoff:** for any `Sinks`/`Blocker` resting on a contestable code claim, recommend `/darkmoon --claims <claim>` to settle it before the team acts on it. (manual)

## Completion contract
A run is complete only when the saved report contains **all** of these - missing any = incomplete, not done:
1. **Requirements** - the table with every item tagged `[Stated|Inferred|Missing]` (Phase 1); with `--prd`, the PRD internal-conflicts line + coverage table.
2. **Grounding** - the seam summary with **repo + SHA** stamped (Phase 2); each code claim carries `path:line` or `Can't-determine`.
3. **Core model** - the per-store representation **and** the `Alternative model(s) considered: … | none viable because …` line (Phase 3).
4. **Findings** - the ranked table, **each row carrying a confidence + a verify-by**; or the explicit *"holds against all four lenses"* if none.
5. **Saved file** - `<slug>.gadfly.<ts>.md`, a fresh file (never an overwrite).

This is one checklist to self-verify against, not three scattered templates. If any item is absent, the run isn't finished - produce it or state why it can't exist (e.g. *"no `--prd` given"*).

## Guard rails
- **Read-only on inputs.** gadfly reads the spec and the code; it never edits them and never posts back to Confluence. It writes exactly one thing: a fresh report artifact (`<slug>.gadfly.<ts>.md`) per run.
- **Hypotheses, not verdicts.** Design review has no mechanical oracle - a wrong criticism is expensive. Every finding ships confidence + how-to-verify; steelman before you sting; never manufacture findings.
- **Explore before asking.** A question the spec already answers is a wasted turn.
- **Gaps are findings, not always blockers.** Block only when the review is impossible without the answer.
- **Don't invent the design.** If the spec is too vague to review, the *questions* are the deliverable - say so, don't write the spec for them.
- **Stamp the spec version + the grounded repo SHAs. Read diagrams, don't punt them.** A reproducible snapshot review; flag only the artifacts you truly couldn't read.
- **Read hotspots thoroughly, not the whole repo.** Read the files the design centers on *in full* - invariants live in the surroundings (a global filter, a base class), and a keyhole read ships false findings. Follow context that decides correctness; the bound is few-files-deep, not the whole codebase. Cite every code claim (`path:line`) or write Can't-determine.
- **A correct citation ≠ a correct finding.** Verify the *interpretation*, not just the line: state each Sinks/Blocker's falsifier and check it; confidence tracks the interpretive leap, not the grep. Even then the finding is a hypothesis - the human is the last check.
- **PRD is a challengeable reference, not an oracle (`--prd`).** Adjudicate every gap - the spec's fault, a justified deviation, or the PRD's own flaw - and tag `[SPEC]`/`[PRD]` so the reader knows what to fix. `[PRD]` findings cap at `med`; never manufacture product-taste pushback.
