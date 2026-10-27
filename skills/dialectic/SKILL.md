---
name: dialectic
description: Decide between options - argue each side to win (independent + grounded), cross-examine, then synthesize a recommendation with the condition that flips it. For real design/architecture decisions. Structured opposition, not both-sides slop. Output is the axis + the deciding question, not a flat verdict.
trigger: /dialectic
allowed-tools: Read, Write, Grep, Glob, Bash(git rev-parse:*), Bash(git log:*), Bash(git show:*), Bash(grep:*), Bash(find:*), Bash(pandoc:*), Bash(date:*), WebFetch, Agent, AskUserQuestion
---

# /dialectic - argue both sides, then decide

Thesis vs antithesis → synthesis. For a real decision between **two or more options**. dialectic argues each option **to win** (not to be fair), grounds each in real code/cost, **cross-examines** them against each other, then an **independent judge** synthesizes. The output is **not "X wins"** - it's the real axis of disagreement, a recommendation, and **the condition that flips it.**

**Honest ceiling - trust the map, not the verdict.** A decision *aid*, not an oracle. The **reliable** outputs are the **axis**, the **frame-dependency**, and the **deciding question** - those are structural and hold up. The **recommendation is a tentative lean, a hypothesis to pressure-test** - it inherits the one-pass ceiling: a single advocate round won't reach a deep counter that iterative human probing would (proven - a run can crown the side whose pivot claim its own evidence refutes). So a confident-looking verdict is a **starting point, never the decision**. If it's a call you'll engage deeply anyway, your own iterative reasoning may beat dialectic; reach for it to *map the trade-off fast + name the deciding question*, not to be told the answer.

**Why the structure (not just "compare these").** Asking one context to compare options yields lazy both-sides-ism: a hedgy paragraph each, the obvious pick, no teeth. dialectic fixes that with **structural separation** - independent advocates who must win, a rebuttal round that collapses weak claims, and a judge who didn't advocate.

## Usage

```
/dialectic <option A> vs <option B>                 # decide between options
/dialectic <a question with the options embedded>
/dialectic <design-doc-path> --options "A, B[, C]"  # ground the debate in a doc
/dialectic <...> --criteria "maintenance, cost, risk"   # pin what matters (else inferred + stated)
```
It grounds in the repo like gadfly - a decision about real code must **cite** real code.

## Phase 0 - Frame

- **Extract the options (≥2).** Parse them from the input. If fewer than two *real* options are present, propose 2-3 and **confirm via `AskUserQuestion`** - never debate one option against a strawman.
- **Pin the decision criteria.** From `--criteria`, else infer and **state them** (cost · long-run maintenance · risk · time-to-ship · reversibility · the stated goal). Echo: `Deciding: A | B | … on: <criteria>`. The judge scores against these, so they must be explicit.
- **Surface the frame - what's already decided (the dependency web).** A decision rarely stands alone: it sits under **settled upstream choices that bound it.** A decision is *downstream* when its best answer **flips depending on an as-yet-unsettled one** (e.g. picking a cache strategy before the consistency requirement is fixed). State the upstream constraints you're assuming, drawn from the input/doc/grounding, and echo `Frame (assumed settled): <constraints>`. **If a load-bearing upstream choice is unstated AND unclear, ask** (`AskUserQuestion`) before debating - arguing downstream of an unresolved fork yields a confident-wrong answer (each side silently assumes a different upstream and talks past the other). Non-interactive → state the assumed frame explicitly and proceed. (The advocate-declares + judge frame-check below are the backstop if this guess is wrong - including for a dependency you didn't know existed.)
- **Ingest a doc if given** (`Read`; `.docx` → `pandoc -f docx -t gfm`) as shared context for all advocates.
- **Ground the terrain** (like gadfly Phase 2, lightweight): find + confirm the repo(s) the decision touches (`find` over `$PWD`/`$WORKSPACE` (your clones dir, if exported)/`$HOME/Github`; stamp `git rev-parse --short HEAD`), read the hotspots the decision hinges on, note cross-service deps. The advocates need real facts to cite, not vibes. Greenfield → state "no code to ground against."

## Phase 1 - Advocates (independent, parallel, win-don't-hedge)

Spawn **one `Agent` per option, fresh context, in parallel.** Each agent's brief:
> *"Build the STRONGEST possible case FOR `<option>`. You are an advocate, not a judge - your job is to WIN. Hedging ('it depends', 'both are fine') = failing. **Ground every claim** - cite `path:line`, a cost number, or an authoritative doc; mark anything you can't ground as `[assumed]`. An ungrounded case is forfeit. Return: the case, the criteria it's strongest on, the cost it's willing to pay, **and the upstream assumptions your case rests on** (e.g. 'assumes single-region', 'assumes the upstream fork resolved as X') - so a hidden frame-mismatch between the sides surfaces."*

- **Independent = each advocate writes WITHOUT seeing the others** (no anchoring - that's the whole point of separate contexts).
- Give each the **same** grounded terrain + criteria from Phase 0.
- An advocate that returns a balanced "here are the trade-offs" has **failed** - send it back or note it; you need the *partisan* best case, because the judge supplies the balance later.

## Phase 2 - Cross-examination

Now each case meets its opponents. Either spawn a rebuttal agent per option (sees the *other* cases) or run one cross-exam pass over all. For **each** option, attack the opposing cases:
- **Verify the load-bearing claim (check the pivot - don't just argue).** Identify the ONE claim each verdict hangs on, and **check it against the grounded evidence** (grep / read / cite), confirm or **refute** it - never merely counter-assert. **A decisive claim that fails verification collapses that case.** (The miss this prevents: a case wins on a pivot like *"X is impossible / can't do Y"* while evidence **already in scope** shows X exists - the cross-exam must catch when a verdict's own grounding undercuts its load-bearing claim, not just trade rhetoric.)
- Where does it **break**? Which claim is **ungrounded or overstated**? What **cost did it hide**? What does its strongest argument *assume* that may not hold?
- **Attack the grounded case as written, not a strawman.** A rebuttal with no concrete break is dropped (no manufactured attacks - same bar as the advocates).

Output per option: what **survived** cross-exam, and what **broke** under it. This is where shallow arguments die - the surviving points are the real ones.

## Phase 3 - Judge (independent synthesis)

A **fresh `Agent` that did NOT advocate** reads both cases + the cross-exam and produces the synthesis. **Required outputs (all of them):**
- **Frame-dependency check (FIRST - it gates whether a winner can even be named).** Do the cases rest on **different upstream assumptions** (from each advocate's declared assumptions), or does the recommendation **flip under a plausible upstream choice**? If yes, the decision is **conditional on that upstream fork** - the verdict is *"resolve `<upstream fork>` first - under `<X>` → A, under `<Y>` → C,"* **NOT** a forced winner. (This is the strongest flip-condition: the whole debate hinges on a prior, unsettled decision. Surfacing it - even one the user didn't know bound them - is the most valuable output, not a failure to decide.) Only when the frame is settled do you proceed to a winner.
- **Axis** - the single real disagreement underneath (the fork). One line.
- **Per option:** *wins on `<criteria>` · breaks on `<criteria>`* - judged **after** cross-exam (a point that broke doesn't count as a win).
- **Recommendation + flip-condition** - `<X> UNLESS <condition>`. A recommendation with **no flip-condition is incomplete** - name the condition under which the other option wins, or justify why none exists. (This conditional is the whole value: not "pick A" but "A unless sorting a playlist by when each song was added to it is a confirmed V1 need.")
- **Deciding question** - the one thing that, once answered, settles it.
- **No forced winner, no manufactured balance:** if one option is clearly better, say so decisively; if genuinely close, say so + name what tilts it; if **both are bad**, say *"neither"* + why. Never split 50/50 to seem fair, never invent a winner to seem decisive.

## Output

Save a fresh report to `~/.claude/reports/dialectic/<slug>.dialectic.<ts>.md` (expanded to an **absolute** path; `<ts>=$(date +%Y%m%d-%H%M%S)`; the Write tool creates the directory) - never inside a repo, where it would sit as an untracked file. Print the absolute path, never a bare filename. Always a new file.

The file holds: criteria · each grounded case · the cross-exam (survived/broke) · the synthesis. **Chat echo is compact:**
- `Deciding: A | B on: <criteria>` + `Frame: <assumed settled upstream>`
- **Axis:** `<the real fork>`
- a one-line `wins/breaks` per option
- **Recommendation:** `<X> UNLESS <flip-condition>` - **or, if frame-dependent:** `Resolve <upstream fork> first - under X→A, under Y→C` (this replaces the winner)
- **Deciding question:** `<the one that settles it>`
- `Full report → <absolute path>` + `(adds: each grounded case · cross-exam breaks · per-criterion scoring - not in this summary)`

**Never `cat`/re-print the report** - the file is written, the echo has the signal; re-printing re-pollutes context and double-renders. The pointer ends the run.

## Completion contract
A run is complete only when the saved report contains **all** of these - missing any = incomplete:
1. **Criteria + the assumed frame** - both stated: the criteria, and the settled upstream constraints the debate runs under (Phase 0).
2. **≥2 grounded cases** - each partisan, each claim cited `path:line`/cost/doc or marked `[assumed]`, **each declaring its upstream assumptions** (Phase 1).
3. **Cross-exam** - what survived / what broke, per option (Phase 2).
4. **Synthesis** - frame-dependency check · axis · per-option wins/breaks · recommendation **+ flip-condition** · deciding question (Phase 3).
5. **Saved file** - `<slug>.dialectic.<ts>.md`, fresh.

## Guard rails
- **Advocates win, the judge balances.** A partisan case is the *input*; an advocate that hedges has failed. The fairness comes from the *structure* (two strong cases + an independent judge), not from each agent being wishy-washy.
- **Cite or it doesn't count.** Every claim grounds in `path:line` / a cost / an authoritative doc, or it's `[assumed]`. An ungrounded case is forfeit - this is what separates dialectic from two confident essays.
- **The judge is independent and names the flip-condition.** It didn't write either case; its recommendation always ships the condition under which it reverses (or a justified "none").
- **No forced winner, no manufactured balance.** Decisive when one option is better; "neither" when both are bad; "close, and here's the tilt" when genuinely tied. Never fake symmetry, never invent a verdict.
- **Don't answer a decision that hinges on an unresolved upstream one.** If the advocates assume different frames, or the answer flips on a prior choice, surface *that* fork ("settle `<upstream>` first") instead of papering over it with an implicit assumption. A confident answer to a frame-ambiguous question is the worst output - it looks decided but is only valid under a guess.
- **Decision aid, not oracle.** dialectic surfaces the trade-off + the deciding question; the human/product decides. Design choices have no mechanical truth.
- **Read-only on inputs.** It reads the question, the doc, and the code; it writes exactly one report per run. Never edits source, never posts anywhere.
