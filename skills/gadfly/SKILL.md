---
name: gadfly
description: Interrogate a tech spec or architecture doc before it gets built - extract requirements, gate the blocking gaps, ground the design in the code it touches, stress-test through four adversarial lenses. `--prd` checks whether the HOW satisfies the WHY. Hypotheses to check, not verdicts.
allowed-tools: Read, Write, Grep, Glob, Bash(curl:*), Bash(printf:*), Bash(echo:*), Bash(command:*), Bash(jq:*), Bash(pandoc:*), Bash(cat:*), Bash(grep:*), Bash(find:*), Bash(head:*), Bash(stat:*), Bash(mktemp:*), Bash(git rev-parse:*), Bash(cd:*), Bash(date:*), WebFetch, AskUserQuestion
---

# /gadfly - sting the design awake

Socrates called himself Athens' gadfly: the fly that stings a complacent horse into motion. This skill questions a **tech spec / architecture doc** until its weak points show, before the team builds the wrong thing.

Spec review has no mechanical oracle, and a wrong architectural criticism sends a team chasing a flaw that isn't there. So every finding is a **hypothesis with a confidence and a check that settles it**, never a verdict.

Flow: **Phase 0** ingest → **Phase 1** requirements gate → **Phase 2** ground in the code → **Phase 3** attack → report. `--prd` adds a WHY-vs-HOW coverage check.

## Usage

```
/gadfly <confluence-url>      # fetch + interrogate a Confluence spec
/gadfly <page-id>             # bare Confluence page id
/gadfly <file-path>           # local spec: .md / .txt / .pdf / .docx
/gadfly <spec> --prd <prd>    # also cross-check against a PRD (WHY-vs-HOW); prd = path or url
```

A drafted solution is a spec too: run `/gadfly` on your own design (a new schema, a permission model), refine, repeat.

## Phase 0 - Ingest the spec

Resolve the input to **spec text + a version stamp**, and record what you could NOT read. Never silently skip content.

### Confluence (URL or bare page id)

Shell state does not persist between tool calls - prepend these lines to EVERY bash call that hits Confluence (the page fetch AND each diagram download):
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
  | jq -r 'if .results == null then "ATTACHMENT FETCH FAILED: \(.message // "no results field")" elif (.results|length)>0 then (.results[] | "ATTACHMENT: \(.title) [\(.metadata.mediaType)] \(._links.download)") else "no attachments" end'
```
**If the fetch fails** - empty `PAGE_ID`, any `curl: (N)` on stderr, or the JSON carries `.message` / no `.id` (401/403/404) - **report it and stop.** Don't review a half-fetched or empty page. Tiny links (`/wiki/x/..`) carry no numeric id: resolve the redirect (the jira skill's tiny-link step) or ask for the page id.

**Stamp** = `version.number (when)`. The review is a snapshot of that revision.

### Local file
- `.md` / `.txt` / `.pdf` → Read directly.
- `.docx` → `pandoc -f docx -t gfm <file>`. No pandoc → say so, ask for an `.md`/`.pdf` export.
- **Stamp** = file path + mtime (`stat -c '%y' <file> 2>/dev/null || stat -f '%Sm' <file>`, GNU then BSD).

### Diagrams - read them
Specs put the schema and architecture in diagrams. **Download every image attachment and `Read` it** (Read does vision on png/jpg), into the work dir the fetch printed (a literal path - `$G` does not survive between calls):
```bash
curl -sS --fail-with-body -L "$JIRA_URL/wiki<download-link>" -H "Authorization: Basic $JIRA_B64" -o <work dir from the fetch>/att_<safe-name>
```
Fold what each diagram shows (an ER diagram's tables, a sequence diagram's flow) into your understanding of the spec. A failed download (any `curl: (N)`) is unread - never `Read` the error page as the diagram. List under **Not analyzed** only what you genuinely couldn't parse (drawio/vsdx/sketch source, external links, a failed download):
> **Not analyzed:** `<names>`. The design may live in these - paste or describe them.

### PRD (optional - `--prd <path|url>`)
Ingest the PRD the same way, diagrams and stamp included, as a parallel tool call in the same message as the spec. The **spec is the HOW**, the **PRD is the WHY**. Without `--prd`, skip all PRD logic.

## Phase 1 - Requirements gate

Goal: a falsifiable requirements list, or the questions that block one.

### Step 1 - Extract before asking
Read the whole spec first; never ask what it already answers. Pull out every requirement and tag it:
- **[Stated]** - written in the spec.
- **[Inferred]** - the spec implies it but doesn't say it. Cite the passage it comes from.
- **[Missing]** - load-bearing and unanswered.

Use a shall-statement where it sharpens the requirement (`When <trigger>, the system shall <action> within <measure>`), plain bullets otherwise. Falsifiability is the point, not the grammar.

**Non-functional requirements are mandatory**: scale (rate / volume / growth), latency / throughput, consistency model, availability, failure tolerance. A missing NFR is a finding. An [Inferred] number must cite its source in the spec, or say *"no basis in spec - assumed from <convention>"*.

Record the **spec type**: greenfield (net-new) or change-to-existing (touches a running system).

### Step 1b - PRD coverage (only with `--prd`)
**PRD internal coherence first (emit every run).** Check the PRD's requirements against each other for contradictions (e.g. *"every user sees the same view"* vs *"visibility is scoped per group"*). Emit `PRD internal conflicts: <list> | none`, and when the design hinges on it, **name the core semantic fork** - the one either/or the product must resolve. A contradiction is a `[PRD]` finding.

The PRD is a claim, not an oracle. Map the spec onto each PRD requirement and judge the gap without auto-blaming the spec:

| Outcome | Meaning | Finding? |
|---|---|---|
| Covered | spec delivers it (cite where) | no |
| Gap `[SPEC]` | PRD ask is reasonable, spec is silent | yes, against the spec |
| Deviation, justified | spec differs with a stated reason | only if the reason is weak |
| Deviation, unjustified | spec differs silently | yes, `[SPEC]` |
| PRD-questionable `[PRD]` | the ask is infeasible, contradictory, over-scoped or vague | yes, against the PRD |
| Scope-creep | spec exceeds the PRD | low-severity flag |

Steelman both sides and quote both. Frame gaps as questions ("unmet, or a justified deviation? confirm with product"). Lodge a `[PRD]` finding only with a concrete reason (a contradiction, an infeasibility grounded in code or scale, a clear over-scope), never product taste. Don't double-count a gap already raised in Step 2.

### Step 2 - Gaps are findings; block only when forced
Most gaps are findings the spec should have covered. Record them and move on.

**Hard-block only when the review is impossible**: no goal or problem statement, or zero scale numbers when the design's whole risk is scale. Ask via `AskUserQuestion`: concrete options with the recommended one first, at most 4 per round, a prerequisite question in its own round. Reject vague answers ("make it fast" → "p99 < 200ms?"). No human available → state the assumption, record it as a finding, proceed.

`BLOCKED` → print the requirements and the questions, then stop. When answered, fold the answers in and continue. `READY` → Phase 2.

## Phase 2 - Ground the design in the code

The design is unbuilt, so there is nothing to verify yet. Ground the **existing systems it lands in**, so the attack rests on facts. Greenfield → write *"net-new - no code to ground against"* and skip to Step 4.

### Step 1 - Find and confirm the repos
A caller (forge) may pass `Repos (confirmed): <name> at <abs path> @ <sha>`: use those and skip the search for them. Otherwise list the repos the design touches, each [Stated] or [Inferred], and locate them:
```bash
# $WORKSPACE = the directory holding your clones, when exported
for root in "$PWD" ${WORKSPACE:+"$WORKSPACE"} "$HOME/Github"; do
  find "$root" -maxdepth 3 -type d -iname "REPO" 2>/dev/null
done
```
Confirm the paths with the user before reading. Not found or ambiguous → ask. No human available → use an unambiguous match; otherwise mark the repo *not grounded* and move on. Never guess a repo.

Also list services the design's correctness depends on without editing them (an auth service, a queue consumer, a search indexer). They are grounding targets when a finding hinges on their behaviour (Step 2b).

Stamp each repo: `cd <path> && git rev-parse --short HEAD`.

### Step 2 - Read the hotspots in full
For each repo:
- Read its `CLAUDE.md` first.
- Find the **hotspots**: the files the design writes, changes or depends on (the model it writes, the query it changes, the function it modifies).
- **Read each hotspot file in full**, batched as parallel tool calls. The facts that decide whether a finding is real sit in the surroundings: a filter applied once at the top of a class, a base class, a shared validator. A function with no permission check is not a hole when the whole file reads through a scoped query.
- Follow what correctness depends on (a global filter, a base class, a shared util), bounded by relevance to the design. A few files deep, not the whole repo. When unsure, read it.
### Step 2b - Cross the service boundary
When a finding hinges on what **another service** does with the data, never conclude from this repo's side alone. Locate that service's repo (same `find`) and read the function that consumes or computes the data. Repo unavailable → mark it **Can't-determine (cross-service)** for the human.

### Step 3 - Check the spec's claims about current code
Specs describe the code they change ("X has no check today", "the 4 call sites", "nothing else sends Y"). Verify each claim with a fresh search, not just the files you have read. A claim that a list is complete or that something is absent ("the 4 call sites", "no other caller") takes the full absence search (Phase 3, rule 2) across every confirmed repo. A false premise is a finding: the design is built on a wrong picture of the system.

### Step 4 - Grounding output
```
## Grounding
Repos: <repo> (<path> @ <short-sha>) [Stated|Inferred]
Seams:
- <seam> - <current behaviour> `path:line`
- <seam> - Can't-determine - <not found in scope | runtime behaviour>
Spec premises: <claim about current code> - <holds | false: what the code does `path:line`>
Cross-service: <service → what its code does with the data `repo path:line` | Can't-determine (cross-service) | none>
Fit: <does the design respect the invariants you read (global filters, conventions) or fight them?>
Not grounded: <seam/repo, or none>
```

## Phase 3 - The attack

### Steelman first
State in 1-2 lines what the design gets right and why the approach is reasonable. If you can't, you haven't understood it - re-read.

### Core model - per store
Before the lenses, name how the design represents its central entity/relationship in **every store it touches**: the primary DB and each derived store (search index, cache, a permissions/graph store, another service's copy). Each store's constraints differ: a DB row model is flexible; a search index is one doc per hit with no joins; a graph pays per traversal; a cache needs invalidation. **The hard modeling decision usually hides in a secondary store**, sometimes in another service (Step 2b). Check cross-store sync too: fan-out on denormalized data, cascade on delete/restore, consistency windows.

Does the model hold under all features at once (permissions + move + search + multiple actors)? A leak is a model finding, often Sinks/Blocker.

**Emit every run:** `Alternative model considered: <a structurally different representation, e.g. a field on the item vs its own row> - <why the design's choice wins or loses> | none viable because <reason>`. Never invent a strawman to fill the line.

### The four lenses
Run all four against the design and its core model. Each lens lands a concrete finding **or** clears the design with a cited reason (*"resilient because <X> `path:line`"*). A clean lens is a valid result; never manufacture findings.

1. **Failure** - what breaks in prod? Per seam: it fails, partially fails, retries double-write, a dependency is down, the migration half-applies, a credential expires mid-operation (what signs each token or presigned URL, and does the signed thing outlive its signer - temporary role credentials, rotated keys?). What's the blast radius?
2. **Scale** - does it hold at the Phase 1 numbers? **Show the arithmetic.** No numbers anywhere → that absence is the finding.
3. **Complexity / fit** - more complex than the problem needs, hard to reverse, or fighting an invariant you read in grounding? Name the simpler path if one exists.
   - **Prior art** (emit it or "no known analog"). If mature products solved this pattern (multi-location references, soft delete, sharing, undo), `WebFetch` an authoritative source on how and **why** they did it, then check whether their reason applies to our constraints - borrow the reasoning, not the conclusion. Cite the source, and keep observable behaviour apart from guessed internals. Never assert prior art from memory: fetch it or skip it. Diverging from the established pattern without a reason that holds here is a finding.
4. **Edge cases & lifecycle** - for each dimension, play out a concrete adversarial scenario, then emit a finding or *"cleared - <reason>"*. Clear only after the scenario fails to break it; never skip a dimension.
   - **Inputs:** empty / huge / concurrent / duplicate / out-of-order / null, at named spec points.
   - **Lifecycle** of each new entity/relationship: create / move / delete / soft-delete + restore / cascade - to the thing *and* to whatever references it. (Move into a place that already references it? Restore - what reappears?)
   - **Scope boundary:** adjacent capabilities the design implies but doesn't address (bulk, recursive, containers, cycles).
   - **Concurrency:** two actors on the same entity at once.
   - **Cross-entity:** when the source changes, what happens to derived data?

### Every finding
- **Quote the spec** - the § it attacks. No spec citation → drop it.
- **Trigger → consequence**, concrete: *"§3 fan-out: 10k orgs × hourly = 240k jobs/day on one worker → backlog by week 2"*, not *"scalability concern"*.
- **Rank:** `Sinks` (the design fails its own goal) / `Blocker` (must fix before launch) / `Handle` (fix in flight).
- **Drop it** if it attacks a strawman, is vague, or is generic advice you'd give any spec.

### Verify before you rank
A well-formatted citation can still be wrong, and a correct citation can still carry a wrong interpretation. For every code claim:
1. **Cite or drop.** A claim about current code ships `path:line` from a read or grep, or it is `Can't-determine` (static reading can't decide a race or a deadlock).
2. **Absence takes a full search.** "X doesn't exist / is never called" needs the exact name searched across the whole repo and every layer (`v1/` and `v2/`, legacy and rewrite), plus aliases and re-exports. One negative grep is not proof.
3. **Falsifier for each Sinks/Blocker.** Write *"false if <X>"* and check X. "No permission check" is false if permissions are applied elsewhere; "race" is false if a lock exists; "missing validation" is false if validated upstream.
4. **Re-run each Sinks/Blocker citation yourself**, grepping the exact symbol that does the harm, not a supporting one. A citation that doesn't reproduce gets the full absence search (2) before you drop it: a careless drop turns a real Sink into a silent miss.

**Confidence tracks the weakest link**, usually the interpretive leap, not the citation. Cap at `med` when any of these holds:
- the evidence isn't shown (no grep output, line read, or fetched doc)
- the falsifier wasn't checked (make the falsifier the verify-by)
- an absence claim didn't get the full search
- dynamic dispatch can hide the truth (reflection, runtime registration, config-driven dispatch)
- it's a `[PRD]` finding or rests on prior art

## Report

Write one **new** file per run: `~/.claude/reports/gadfly/<spec-slug>.gadfly.<ts>.md`, with `<ts>` from running `date +%Y%m%d-%H%M%S` now, as an absolute path (Write creates the directory). Never overwrite or update a prior report - a second run is an independent opinion. Never write inside the reviewed repo; never post to Confluence.

```markdown
# gadfly: <spec title>
<spec stamp> · <type> · repos: <repo @ sha, ...> · PRD: <stamp | none>

**Verdict:** <Not ready - N Sinks, N Blockers | Ready with fixes - N Blockers | Holds - no Sinks or Blockers>
**Steelman:** <what the design gets right, 1-2 lines>

| # | Sev | Finding | § | Conf |
|---|---|---|---|---|
| 1 | Sinks | <title> | 3.4 | high |

## Findings

### 1. [Sinks] <title> - §<ref> [SPEC|PRD]
**Trigger:** <concrete scenario> → <consequence>
**Evidence:** <spec quote · `path:line` + what it shows · the arithmetic>
**False if:** <falsifier> - <checked: result | unchecked> (Sinks/Blocker only)
**Confidence:** <high|med|low> · **Verify by:** <the check that settles it>
**Direction:** <one line on what the spec should decide or change - not a redesign>

## Core model
<per store: how the design represents the entity>
Alternative model considered: <...>

## Cleared
- <lens or dimension> - <cited reason it held>

## Open questions
1. <question the author must answer before building>

## PRD coverage (only with --prd)
PRD internal conflicts: <list | none> · Core fork: <...>
| PRD requirement | Outcome | Note |

## Requirements
<Phase 1 list, tagged [Stated|Inferred|Missing]>

## Grounding
<Phase 2 Step 4 block>

Not analyzed: <diagrams/attachments | none>
```

Order findings Sinks → Blocker → Handle. The `[SPEC|PRD]` tag and the PRD section appear only with `--prd`. No real findings → the verdict is *Holds* and Cleared carries the cited reasons; don't invent nits.

**Chat echo** - print this and stop:
```
gadfly: <spec title> - <verdict>
Steelman: <one line>
<the findings table from the report>
Alternative model: <one line>
PRD fork: <one line> (only with --prd)
Top question: <the single most important open question>

Full report → <absolute path>
  (adds per-finding trigger, evidence, falsifier and verify-by; core model per store; cleared lenses; requirements; grounding)
```
Never `cat` or re-print the report after saving: it pushes ~250 lines back into context for nothing. The user opens the file.

For a Sinks/Blocker resting on a contestable code claim, add one line recommending `/darkmoon --claims <claim>` before the team acts on it.

## Completion contract
The run is done only when the saved report has all of these; for one that can't exist, say why (e.g. *"no --prd given"*):
1. A verdict line and the findings table.
2. One block per finding with confidence + verify-by, and a checked-or-unchecked falsifier on each Sinks/Blocker - or the *Holds* verdict with cited Cleared reasons.
3. The core model per store and the `Alternative model considered` line.
4. Requirements tagged [Stated|Inferred|Missing]; with `--prd`, the internal-conflicts line and the coverage table.
5. Grounding with repo + SHA, spec premises checked, every code claim carrying `path:line` or `Can't-determine`.

## Guard rails
- **Read-only on inputs.** gadfly reads the spec and the code and writes only its report. This is an instruction, not a grant boundary: `curl`, `Write` and `find` are granted for fetch, report and repo lookup, and could write.
- **Don't invent the design.** If the spec is too vague to review, the questions are the deliverable.
