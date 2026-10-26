---
name: darkmoon
description: Summon an independent, grounded skeptic to challenge the author's last response. A fresh-context agent reads the response + verifies against the real code/transcript, then upholds, refutes (evidence-grade), or marks can't-determine - per claim. Grounded, never manufactured; argument-counters never masquerade as proof.
trigger: /darkmoon
allowed-tools: Read, Grep, Glob, Bash(bash ~/.claude/skills/darkmoon/extract-qa.sh:*), Bash(grep:*), Bash(jq:*), Bash(git log:*), Bash(git show:*), Bash(git diff:*), Bash(git blame:*), Bash(git status:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh search:*), WebFetch, WebSearch, Agent, SendMessage
---

# /darkmoon - invade the last answer, judge it on evidence

Blade of the Darkmoon: an invader summoned to **judge a transgression.** Here the transgression is *a possibly-wrong answer the author just gave.* darkmoon spawns an **independent, fresh-context skeptic** that tries to break the author's last response - but it can only **refute with grounded evidence** (a mechanical check, else Can't-determine), upholds what survives, and never manufactures a counter to look useful.

**Why it exists.** The author cannot honestly grade its own last answer (a self-judge rationalizes - the same reason an author can't critique its own draft). darkmoon is the external check on *the author itself*: confident-wrong answers (a misread `grep`, an over-stated claim, a recommendation resting on an un-grounded premise) get caught by someone who didn't write them.

**Honest ceiling.** One skeptic, grounded but fallible - "Upheld by darkmoon" **reduces** confident-wrong, it doesn't **eliminate** it (one run can miss; for high-stakes, run several passes in fresh processes and union the findings - separate processes keep each skeptic independent). And darkmoon can itself misread - so it falsifier-checks its **own** counters before emitting them. It is a sharp second opinion, not an oracle.

## Usage

```
/darkmoon              # challenge the author's whole last response
/darkmoon <claim>      # challenge one specific claim/topic from it (cheaper, sharper)
/darkmoon --context N  # also include the N prior exchanges (for a long multi-turn thread the answer rests on)
/darkmoon --claims <claims>  # verify a caller's pre-formatted claims, no transcript (for skills like aristarchus)
```
Plain text after `/darkmoon` is ALWAYS a focus topic inside the last response - never treated as standalone claims. Only `--claims` skips the transcript; everything after `--claims` is the claims, so it ignores `--context` and focus text.

## Prerequisites

- `install.sh` links all four pieces: this skill, `extract-qa.sh`, the `darkmoon-skeptic` agent, and the `darkmoon-readonly.sh` hook. Without the agent, darkmoon falls back to a weaker general-purpose skeptic (see Spawning the skeptic).
- `jq` on `PATH`. `$CLAUDE_CODE_SESSION_ID` (set by Claude Code) locates the current transcript.

## Independence - structural where it can be

darkmoon is invoked *by* the author, in the author's session - so its independence cannot rely on the author packaging the challenge fairly. The structural guarantees:
- **The skeptic runs in a FRESH `Agent` context** - it does not inherit the author's reasoning, only the target's location + the means to verify it.
- **The skeptic reads the target response verbatim, not the author's interpretation of it.** The orchestrator **pre-extracts the Q+A pair with `extract-qa.sh`** and passes the verbatim text - mechanical, not a summary. The author does **not** re-type, paraphrase, or summarize its own answer (that reintroduces self-spin). The Q+A pair = the last substantive user question (50+ chars) **before this `/darkmoon` invocation** + every assistant turn after it, with shorter follow-up user turns kept inline.
- **Including the question does NOT cost independence.** The question is the *user's*, not the author's reasoning - it tells the skeptic what was *asked* (so it can check the answer addressed it), without anchoring it to the author's conclusions. Only prior *assistant* turns would anchor - which is why `--context N` is opt-in, not default.
- **It grounds against ground truth itself** - the real **code/files** + the transcript - never the author's summary.
- **Independence requires a genuinely fresh context.** If darkmoon cannot spawn the skeptic `Agent` (e.g. it's running nested as a Task subagent), independence is **compromised** - say so and recommend re-running standalone, or as several fresh-process passes whose findings you union. Do **not** silently self-grade.

## Efficiency - the transcript is an INDEX, not the payload

**Never ingest the whole transcript** (a long session is 500k-800k+ tokens - ~$7+ just to read, and drowns the signal). Instead:
- **Get the transcript path** - `extract-qa.sh` resolves the **exact** current-session transcript from `$CLAUDE_CODE_SESSION_ID` (a neutral pointer - see Independence above for why that's safe) and pulls the **Q+A pair** (defined under Independence above) out verbatim. Never fall back to "newest `.jsonl`" - with several sessions open it picks the wrong one; if the script can't resolve the session, say so rather than guess.
- **`--context N`** (opt-in) additionally pulls the **N exchanges before the target** - use only when the answer genuinely rests on a multi-turn thread (a long design discussion); it adds anchoring exposure + cost, so it is **not** the default.
- Selective transcript `grep` and grounding against the code are the skeptic's job (its agent file) - the orchestrator does neither. Bounded: a focused challenge of a few claims ≈ a focused grounded check ($1-3), not a whole-session ingest.

## Spawning the skeptic

The skeptic's method, verdict rules and output format live in **one** place: the `darkmoon-skeptic` agent (`~/.claude/agents/darkmoon-skeptic.md`, its system prompt). The orchestrator never restates, summarizes or edits the method - it passes only the input below.

**`--claims` mode** (another skill verifying its own output before it reaches the transcript, e.g. aristarchus mid-review): **skip transcript extraction entirely.** The prompt is `Claims mode:` + the claims verbatim, numbered. The ledger returns to the calling skill; there is no `## Author's reply to darkmoon` block - the caller integrates the verdicts.

**`/darkmoon <claim>`** (focus): extract as below; the prompt is `Focus: <claim>` + the script output.

**Otherwise, extract from the transcript.** Run the extraction script - do NOT improvise shell commands:
```bash
bash ~/.claude/skills/darkmoon/extract-qa.sh                    # current session, via $CLAUDE_CODE_SESSION_ID
bash ~/.claude/skills/darkmoon/extract-qa.sh --context N        # with prior exchanges
bash ~/.claude/skills/darkmoon/extract-qa.sh <transcript.jsonl> # explicit path (another session)
```
This outputs `=== QUESTION ===` and `=== ANSWER ===` sections with the verbatim text (follow-up user turns labelled `[User follow-up]` inside ANSWER). With `--context N`, also outputs `=== CONTEXT (N prior exchanges) ===`. The script classifies turns via `jq -R` + `fromjson` (structured parsing, not string grep) and skips previous darkmoon execution blocks so their judgments don't pollute the target.

**Spawn one `Agent` with `subagent_type: darkmoon-skeptic`.** The prompt is the mode line (if any) + the script output (its first line, `Transcript: <path>`, is a neutral pointer) or the claims, verbatim - nothing else: no framing, no hints about where the answer is weak, no method recap. If `darkmoon-skeptic` is not an available agent type (not installed), spawn a `general-purpose` Agent whose prompt starts with `Read ~/.claude/agents/darkmoon-skeptic.md and follow it exactly as your instructions.` + the same input, and tell the user to run `install.sh`. That fallback agent also has `Edit`/`Write`, so read-only is weaker on that path.

## Output - surfacing the ledger

The skeptic returns the ledger (Headline, table with row 0 = frame check, Verdict counts, Coverage). If any of those is missing, re-prompt the skeptic once via `SendMessage` to add it; if it's still missing, surface the ledger as-is and name the gap - never fill it in yourself.

- **Two distinct voices - never blur them.** The ledger is the **skeptic's** verdict (the independent agent) - surface it **verbatim** under its own `## 🌑 darkmoon - judgment` heading (the 🌑 marks the skeptic's voice). The author's response is a **separate, clearly-labelled block**: `## Author's reply to darkmoon` (no moon - it's the challenged party, not the skeptic). The reader must always know who is speaking - a **concession is the *challenged author* admitting fault, NOT the skeptic softening its own verdict** (that distinction is the whole point; collapsing them makes it read like darkmoon conceding to itself).
- **Under that reply heading, the author is BOUND to address each `Refuted`/`Weak` row** - concede it, or counter with its *own* fresh evidence (`grep`/cite). **No defensive hand-waving, no reflexive dismissal.** The challenge is defeated if the challenged party gets to wave it away.
- **When any row is `Refuted` or `Weak`, the reply ends with `**Revised answer:**`** - the corrected bottom line in full, standalone (what to do / comment / conclude now), so the user never has to ask "so what's the answer?". Patch notes against the old answer are not a revised answer. All rows `Upheld`/`Can't-determine` → one line: `Answer stands.`

## Completion contract
A run is complete only when:
1. The ledger has **row 0 (frame check)** AND at least one row marked `(unstated)` - or Coverage states no unstated assumption was found.
2. Each carries a **verdict** (Refuted/Upheld/Weak/Can't-determine) **with its evidence or counter shown** - no bare assertions; each `Refuted` is code/fact, evidence-grade, and falsifier-checked (no argument labelled `Refuted`).
3. A **Headline** (the one finding that most changes the next move) leads the output, and a **Coverage** line states what was NOT examined.
4. The ledger is **surfaced raw** under its own heading; the author **addresses each Refuted/Weak row** in a separate `## Author's reply to darkmoon` block (concede or counter-with-evidence), ending with `**Revised answer:**` (any Refuted/Weak) or `Answer stands.` (none).

**`--claims` mode replaces 1 and 4:** every passed claim has exactly one ledger row (none dropped, none added), and the ledger is returned to the caller. 2 and 3 still apply.

## Guard rails
- **Independence is structural where it can be** - fresh `Agent` context, verbatim input, method in a checked-in agent file. The one remaining soft spot is the orchestrator writing the prompt, which is why it may pass only the mode line + verbatim input.
- **Efficient** - target response + selective transcript `grep` + ground against code; never ingest the whole transcript.
- **Surface raw + bind the reply** - the ledger goes to the user unfiltered; the author must concede-or-counter each break, not dismiss it. (`--claims` mode: the ledger goes to the caller, whose own rules integrate it.)
- **A clean ledger is NOT a clearance.** "Upheld" is per-claim; absence of a refutation means *not checked there*, not *correct*. Always state Coverage (what wasn't examined); never let "darkmoon found nothing" read as "the answer is sound."
- **One skeptic ≠ certainty.** Upheld reduces, doesn't eliminate, confident-wrong; for high-stakes, run several fresh-process passes and union them (separate processes = real independence per pass).
- **Read-only.** darkmoon reads the response, the code, the transcript; it never edits, commits, or posts. It judges; it does not change. (The orchestrator's `git`/`gh` grants are scoped to read subcommands. The skeptic agent has no `Edit`/`Write`, and its `Bash` is gated by the `darkmoon-readonly.sh` `PreToolUse` hook in its frontmatter - an allowlist tripwire, not a sandbox; its known gaps are listed in the hook's header comment. The general-purpose fallback has no hook.)
