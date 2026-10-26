---
name: jury
description: Run another skill N times in parallel and merge the outputs into a frequency ledger - surfaces non-determinism and unions findings across runs. For high-stakes reviews and experiments.
trigger: /jury
allowed-tools: Agent, Skill, Read, Write, Glob, Bash(mkdir:*), Bash(mktemp:*), Bash(date:*), Bash(seq:*), Bash(claude -p:*), Bash(jq:*), Bash(ps:*), Bash(ls:*)
---

# /jury - Repeat a skill N times, merge into a ledger

Runs a target skill N times concurrently in **independent** contexts, then merges the per-run findings into one comparison table: rows = deduped findings, cells = each run's severity, plus an **`X/M` frequency** column (M = full-fidelity runs). Surfaces recall variance and unions what any single run would miss. Best for skills that emit discrete, file-anchored findings (e.g. a code-review skill).

## Usage

```
/jury <skill-name> <its-args> [--n N]   # default N=3, min 2, cap 6
/jury <skill-name> <its-args> --headless # jurors as root processes (for targets that self-fan-out)
/jury --merge <runs-dir>                # re-merge saved raws, no re-run
```

`<skill-name>` is **whatever skill you want repeated** - read it from the input, never assume a particular one. It's a skill name + its args, not a nested slash-command (a leading slash is just stripped). The harness only ran `/jury`; everything after is text for this skill to act on by fanning out (Step 3), never by invoking the target in this session.

## Step 1 - Parse

- `--merge <dir>` → skip Steps 2-4; go straight to Step 5 reading the raws in `<dir>`.
- Otherwise: **the target name is the first non-flag token after `/jury`, copied verbatim from the input.** Do NOT replace it with any skill named elsewhere in this document - copy exactly what was typed (`code-review` stays `code-review`, `triage` stays `triage`). Everything after the name is its args, except `--n N` (default 3, min 2, cap 6) and `--headless` (jury's own flags, not the target's). **Echo `target=<the verbatim token> | args=<…> | N=<n>`; if it doesn't match the input, re-read the input** - a wrong target wastes the whole fan-out.
- **Strip write/mutating flags from the target's args** (any `--submit`/`--post`-style flag). Fan-out is **read-only**: running a mutating skill N times would multiply side effects (N duplicate PR comments, N tickets). The human acts once, on the merged result.
- Identify the target skill name (strip a leading slash if present) and confirm it exists - check `~/.claude/skills/<name>/SKILL.md`, and if that dir isn't found, match it against an **available skill's registered name** (the dir can differ from the name, e.g. `code-review` lives in `team-code-review/`). Each fan-out agent will **invoke** this skill itself - **do not invoke it in this (orchestrator) session**, and do NOT paste its file content into the agents (pasted-as-text runs shallower than the harness-loaded skill - agents skip steps and reason less deeply).
- **`--headless`** (default off): run jurors as independent **root processes** instead of Task subagents (Step 3). **Self-fanning targets need it.** Grep the target's `SKILL.md` for `subagent` / `Agent` / `fan out` / `parallel` - if it spawns its own subagents, a Task subagent **can't nest** and the target degrades (grounds shallower or serially). Flag this and **suggest `--headless`** before fanning out; don't silently run a degraded sample.

## Step 2 - Cost gate (confirm before fan-out)

Estimate `N × the target's per-run cost + ~$1-2 merge`, as a rough range, then wait for an explicit `y`.

**You can't know the target's per-run cost pre-flight - it varies widely, so treat any estimate as a loose FLOOR, not a ceiling.** A light review-type run ≈ **$1-2**; a log/multi-repo-heavy run (anything that reads logs or traverses several repos) ≈ **$5-6 and several minutes** each - so N=3 spans ~$5 to ~$20+ (one observed heavy run: 3× ≈ $18). For an unfamiliar target, bias the range **high**, say "could exceed this," and run **N=2 first** to calibrate its real per-run cost before scaling up. The displayed session cost may also exclude separately-billed subagents.

## Step 3 - Fan out (parallel, independent)

Spawn N subagents in parallel. Each agent's task is to **invoke the `<target>` skill itself** (via the Skill tool) with the parsed args and return its output - e.g. *"Use the `<target>` skill with `<args>`. Run the skill fully - execute every step, don't shortcut. Return its complete output verbatim."* (Substitute the actual target name from Step 1, not a skill from this doc.)

- **Invoke the real skill, don't reproduce it.** Harness-loaded = full fidelity (all steps run, incl. existing-comments + deep reasoning). A pasted copy runs shallower - that's the fidelity bug this avoids.
- Independent context = independent sample.
- If the subagent reports it cannot invoke the skill, that's a finding - stop and report it (the fan-out mechanism depends on it).

**`--headless` mode (self-fanning targets).** The default (subagents) is lighter, cached, and MCP-present - right for the common target that does *not* spawn its own subagents. A target that **itself** fans out degrades as a subagent (no nesting). For those, run each juror as a **root process** instead:
```bash
mkdir -p ~/.claude/jury-runs; D=$(mktemp -d ~/.claude/jury-runs/"$(date +%Y%m%d-%H%M%S)"-XXXX); echo "$D"
for i in $(seq 1 N); do
  claude -p "/<target> <args>" --dangerously-skip-permissions --output-format json > "$D/run-$i.json" 2>"$D/run-$i.err" &
done
wait
```
Each root process loads the target via the harness (full fidelity) and **can fan out fully**. Pull `.result` from each `run-$i.json` for the merge - these ARE the saved raws (Step 4 already satisfied). Heavier than subagents (N cold starts, no shared cache, and headless may lack interactively-authenticated MCP servers), so use it **only** when the target self-fans.

**Don't misread an in-flight run as a crash (this WILL bite you).** `--output-format json` writes the **whole blob atomically at the end** - so mid-run the `run-$i.json` is **0 bytes**, and that means *still running*, NEVER crashed. Rules:
- **Run the launch + `wait` as ONE blocking foreground call** (not `run_in_background`). The bash tool then returns only when every juror has exited - no polling, no guessing. A heavy target (e.g. gadfly ≈ 7 min) means this call blocks for minutes; that's expected - let it.
- **Judge done-ness by the process, not the file** - `wait` returning (or the PID gone from `ps`) is the done signal. Empty json + live PID = working. Do **not** declare a crash, and do **not** launch a diagnostic "test run" (it wastes a full target run's cost), from a 0-byte file alone.
- **Run the cost-rollup `jq` ONLY after `wait` returns.** On empty files it yields `null` - if you see `null`, you ran it too early; the runs aren't done.
- **`otelHeadersHelper failed … Permission denied` in `run-$i.err` is a BENIGN telemetry warning, not a failure.** It appears even in successful runs. Diagnose failure from the JSON (`.is_error==true`, missing `.result`, or empty json *after* the PID exited) - never from stderr noise.

**Cost rollup (headless only).** These jurors are separate processes - their spend is **not** in this session's meter, so surface it explicitly from the JSON. This is a new Bash call, so `$D` from the launch is gone - use the directory the launch printed:
```bash
jq -s '{total_cost_usd:(map(.total_cost_usd)|add), input_tokens:(map(.usage.input_tokens)|add), output_tokens:(map(.usage.output_tokens)|add), turns:(map(.num_turns)|add), runs:length}' <dir printed at launch>/run-*.json
```
Report the totals in the Step 6 overview. (Subagent mode can't roll this up reliably - sub-agent billing may be separate and unreported; that's a reason headless gives you cost visibility the default doesn't.)

Notes:
- If the target creates **git worktrees** (e.g. `/aristarchus` reviews every PR in one), it must name them uniquely or parallel runs collide; also watch for shared-`.git` lock contention under concurrency - if runs fail with git-lock errors, drop that flag and fan out in the lighter mode.
- If some agents fail, proceed with the survivors; record `launched N, M succeeded`.

## Step 4 - Save raw outputs (persistent)

Capture each run's output from its **completion notification** (the returned agent result) - don't rely on `Task Output` by ID for background agents; it may not resolve. Write each run verbatim to `<run dir>/run-<i>.md`, creating the run dir once with `mkdir -p ~/.claude/jury-runs && mktemp -d ~/.claude/jury-runs/"$(date +%Y%m%d-%H%M%S)"-XXXX` (the random suffix keeps two juries started in the same second apart; use the printed path literally afterwards). This is the **audit trail + re-merge cache** - re-run the merge later with `/jury --merge <dir>`. Print the directory path in the output.

## Step 5 - Merge into a ledger

**Fidelity gate (first).** Each run must look like a *complete* output before it earns full trust. Detect shallow runs by **structural comparison across runs** (no target-specific knowledge): a run missing sections/markers that the *majority* of runs share ran shallow - it skipped steps. (For aristarchus those happen to be the `Conventions:` + `Existing comments:` header fields, but derive the markers from what the runs themselves share - don't hardcode per target.) Mark a shallow run `⚠ low-fidelity`: list its findings in a separate flagged block, exclude it from the frequency/unanimous counts, and note it in the overview. If most runs are low-fidelity, **stop and report** - the fan-out isn't faithful. If the runs are structurally uniform, the gate passes (note "fidelity: uniform").

1. **Extract** from each run: the discrete findings (however the target formats them - for `/aristarchus`: severity-tagged findings, lens findings included, each keeping its location + severity) **and the run's overall verdict/recommendation** (needed for the distribution in Step 6). Skip the rest of the prose/praise unless asked.
2. **Cluster** equivalent findings into rows. Use `file:line` as a **fuzzy** signal (same file, lines within a few of each other) + semantic equivalence - NOT an exact key (the same finding lands at slightly different lines across runs). **When unsure, keep rows separate** - over-splitting only adds rows a human can eyeball; wrong-merging hides a distinct finding.
3. **Normalize** each cell to a canonical vocabulary: `critical` / `warning` / `nit` / `absent`, each tagged `· Confirmed` or `· Inferred`. Map every run's wording onto this scale so cells are comparable. If a run *raised then withdrew/refuted* a finding, mark its cell `withdrawn` (not a severity) - don't show it as a live `warning`.
4. **Frequency**: count how many runs raised each row, **out of the full-fidelity count M** (low-fidelity runs excluded by the gate), shown as `X/M`. The denominator M is the same for every row, so sorting by count = sorting by ratio.
5. **Completeness check (do NOT skip - this is the merge's completion criterion).** Re-scan every `run-<i>.md`: **each finding in each raw must map to a ledger row.** If any is unaccounted for, add it (as a singleton row, flagged for scrutiny). A finding present in a raw but absent from the table is a merge failure - and a dropped finding defeats the entire point of the tool. The merge is done only when zero raw findings are unrepresented.

## Step 6 - Output

1. **Overview** (derive it *from* the finished table, so it can't contradict it): N launched / M full-fidelity, total findings, unanimous vs singleton counts, verdict spread. In `--headless`, also report the **total cost + tokens** from the rollup (Step 3) - the jurors' spend isn't in this session's meter, so it must be surfaced here. **Get the counts by literally counting table rows** - unanimous = rows at `M/M`, singletons = rows at `1/M` - and cross-check against the table before writing; the numbers must match the rows (a frequency tag varying in severity, e.g. nit/warning, is still unanimous if present in every run).
2. **Comparison table**: `Finding | Location | Freq | Run 1 … Run N` with normalized cells. Sort by frequency desc, then severity. **One finding = exactly one row** - never split into sub-rows. If runs assign different severities, just show each in its own cell; if runs *disagree on validity* (one says `warning`, another judged it a non-issue), tag the row `⚑ contested` and surface it in stability flags - that disagreement is signal, not a formatting problem. Give the most specific `Location` (file:line, or the file(s) for cross-cutting/infra findings - avoid vague slashes).
3. **Recommendation block** - do NOT synthesize a single verdict:
   - **Verdict distribution** (e.g. `Comment ×3 | Request changes ×1`).
   - **Union of all blocking/critical findings** across runs (so a rare-but-real catch isn't averaged away).
   - **Stability flags**: which findings were unanimous (trust) vs **singletons (1/M) - flag for human scrutiny** (rare real catch or one-off hallucination - highest value/risk), vs **`⚑ contested`** rows where runs disagree on validity - verify these manually, the disagreement means one side traced it and the other didn't.

## Guard Rails

- **Fan-out is read-only** - strip mutating flags (`--submit`, etc.); never run a write-mode skill N times. `jury` itself writes only the runs directory.
- **Always confirm cost** before fanning out.
- **Never collapse to one verdict** - the value is catching what one run missed; show distribution + union.
- **Proceed on partial failure**; report `launched N, M succeeded`.
- Best on review-type skills (discrete, file-anchored findings). For skills without a natural anchor, clustering is fuzzier - lean harder on keep-separate.
- `~/.claude/jury-runs/` grows with each run (small markdown) - prune old timestamps occasionally.
- **`--headless` only for self-fanning targets.** Default subagents are lighter/cached/MCP-present for everything else; reach for headless when nesting would degrade the target, not by default.
- **Fan out in the depth you'd actually trust.** Union recall only rescues *randomly*-missed findings; N runs of a shallow mode (diff-only) share the same blind spots, so the union misses what that mode can't see. For high-stakes, fan out in the same mode you'd use for a single serious review (for `/aristarchus`: the default mode with lenses, never `--fast`) - don't union cheap-but-shallow runs and mistake the long table for thoroughness.
