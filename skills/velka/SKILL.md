---
name: velka
trigger: /velka
description: Surface cross-session workflow habits from your Claude Code history. velka digests your past session transcripts (mechanically, no LLM) and reports recurring patterns - edit-thrash, skills you keep skipping, fine-grained committing, token churn, repeated tool-sequences worth forging into a skill. Reports only what the transcripts mechanically prove; inference beyond the footprint is flagged low-confidence, never asserted.
allowed-tools: Read, Bash(bash ~/.claude/skills/velka/collect.sh:*), Bash(jq:*), Bash(cat:*), Bash(date:*), Bash(ls:*), Bash(find:*)
---

# /velka - observe the cycle, name the recurring sin

Velka, Goddess of Sin: she *observes and records transgressions* across the whole cycle. Sibling to `darkmoon` (which judges **one** answer) - velka watches **many sessions** and names the habit you keep repeating. The "sin" here is a workflow inefficiency: a file you thrash, a tool you keep skipping, a 3-step dance you redo by hand every time.

**Why it exists.** Inside a single session you already lived it - telling you "you edited `auth.ts` 12 times today" is no news. What you *cannot* see is the pattern **across** sessions: that you thrash frontend files every time, that you've run `litmus` in 8 of 441 sessions, that the same grep→read→edit dance recurs and should be a skill. velka aggregates the mechanical footprints your transcripts leave and surfaces the cross-session habit.

**Honest ceiling - read this.**
- **velka sees ONLY what ran through Claude Code's tools.** Tests in your IDE/terminal/CI, edits in vim, commits from another shell - **invisible.** A "you never test" finding means "no test command ran *through Claude*," NOT "you don't test." This caveat is **mandatory** on any testing/coverage finding (see Guard rails) - omitting it is a false accusation.
- **Mechanical footprints only.** velka proves *what happened* (counts, files, tools). It does **not** prove *what you should have done* - "you should've used litmus" is an inference the transcript can't ground. Those are **low-confidence flags for your review**, never asserted findings.
- **The value is cross-session.** A single-session run is low-value (you lived it). Default to the full window; warn if the window is one session.

## Usage
```
/velka                       # habits since your last velka run (or all history on first run)
/velka --all                 # the whole corpus, ignore the last-run marker
/velka --since 2026-06-01    # sessions on/after a date
/velka --project <path>      # only sessions whose cwd matches this path
/velka --advice              # ALSO emit the speculative tier (off by default - see below)
/velka --explain             # add a "what it means / what to do" column (teaching mode)
/velka --candidates          # ALSO cross-check session intents vs skill catalog → adoption gaps + new-skill candidates (LLM tier)
```

## Phase 0 - Refresh the digests (cheap, cached)
Run the collector - it (re)digests only new/changed sessions (mtime-cached), excludes subagent transcripts, dedupes streaming duplicates:
```
bash ~/.claude/skills/velka/collect.sh
```
Digests land in `~/.claude/velka/digests/*.json` (one compact record per session). If the dir is empty after this (no history, or scripts missing), say so and stop - do not invent findings.

## Phase 1 - Pick the window (and state it)
- **Default:** sessions with `.start` >= the timestamp in `~/.claude/velka/last-run` (if absent → all history, note "first run").
- `--all` ignores the marker; `--since <date>` / `--project <path>` filter explicitly.
- **State the window in the output** (N sessions, date range, project filter). A finding is meaningless without the slice it came from.
- **If the window is a single session, warn:** "single-session window - velka is built for cross-session habits; run `--all` for the real signal."

**Canonical window/count command (use this; do NOT improvise `ls "$D"/*.json` - older zsh errs `no matches found: /*.json`).** It is glob-free (find feeds jq via stdin):
```
D="$HOME/.claude/velka/digests"
find "$D" -name '*.json' -exec cat {} + | jq -s '{n:length, earliest:(map(.start // empty)|sort|first), latest:(map(.end // empty)|sort|last)}'
```
The Phase 2 detector blocks below use `"$D"/*.json` directly (works on current Claude Code). **If any errors with `no matches found`, swap that block's `"$D"/*.json` for `$(find "$D" -name '*.json')`** - same files, no shell glob.

## Phase 2 - The mechanical detectors (groundable; each ships its number)
Run these over the windowed digests. **Every row carries its evidence (counts + the sessions/files behind it) or it is not emitted.**

**Apply the window - the blocks below read ALL digests as written.** Unless the window is `--all`, feed each detector the windowed stream instead of `"$D"/*.json` (keep the detector's own jq program unchanged): `find "$D" -name '*.json' -exec cat {} + | jq -c --arg m "<window start, ISO>" --arg p "<--project path, or empty>" 'select((.start // "") >= $m and ((.project // "") | startswith($p)))' | jq -rs '<detector program>'`. A report whose stated window or project filter disagrees with the digests it counted is WRONG.

**Shell note (zsh-safe - the bugs that bit v1):** every detector block below is its own Bash call and shell state does not persist between calls, so start EACH block with `D="$HOME/.claude/velka/digests"` - unset, `"$D"/*.json` becomes `/*.json`. Use `$HOME`, **NOT** `~` - a tilde inside a variable plus an unquoted glob expands empty under zsh, giving `/*.json: no matches`) and always **quote** the glob: `"$D"/*.json`.

**Only emit detectors GROUNDABLE from the digest schema. Do NOT improvise jq against fields that don't exist** (that crashes with "Cannot iterate over null"). The digest has exactly: `bash.{total,git_commit,git_revert,test_run,grep}`, `skill_tooluse[]`, `slash[]`, `tools{}`, `files_edited{}`, `files_read{}`, `tokens{}`, `tool_seq[]` (tool names), `cmd_seq[]` (normalized bash command-heads - **vestigial**: kept for possible future use, but `--candidates` no longer mines it, command-dance mining was proven useless), `first_prompt` (first 2-3 substantive human messages joined with ` | ` = intent signal for `--candidates`; covers slash-start sessions where turn-1 is skill text, not the goal), `assistant_msgs`, `user_str/arr`, `start/end`, `id`, `project`. There is **no** raw-bash-command list and **no** gh-subcommand count.

- **Edit-thrash** (cleanest signal - a file edited many times = churn = design unclear before coding):
  ```
  jq -rs 'map({id:.id[0:8],proj:(.project|split("/")|last),worst:(.files_edited|to_entries|max_by(.value))})
    | map(select(.worst.value>=10))|sort_by(-.worst.value)|.[0:10][]
    | "\(.worst.value)x  \(.worst.key|split("/")|last)\t(\(.proj), \(.id))"' "$D"/*.json
  ```
- **Skipped-fleet-tool** (LOW-CONFIDENCE flag, not a finding - the footprint is real, the "should have" is not). Two groundable ones (litmus, occam); **aristarchus is NOT groundable** (no gh-subcommand count in the digest - do not emit it until the digester captures gh subcommands):
  ```
  jq -rs '[ (map(select(.bash.grep>=15 and ((.skill_tooluse+.slash)|index("litmus")|not)))|length),
            (map(select(.bash.grep>=15))|length) ] | "litmus: \(.[0])/\(.[1]) heavy-grep sessions used none"' "$D"/*.json
  jq -rs '[ (map(select(.bash.git_commit>0 and ((.skill_tooluse+.slash)|index("occam")|not)))|length),
            (map(select(.bash.git_commit>0))|length) ] | "occam: \(.[0])/\(.[1]) commit sessions used none"' "$D"/*.json
  ```
- **Commit granularity** (fine-grained committing - many commits/session):
  ```
  jq -rs 'map(select(.bash.git_commit>=5)|{id:.id[0:8],n:.bash.git_commit,proj:(.project|split("/")|last)})
    | sort_by(-.n)|.[0:8][] | "\(.n) commits\t(\(.proj), \(.id))"' "$D"/*.json
  ```
- **Testing presence** (ALWAYS attach the blind-spot caveat):
  ```
  jq -rs '{ran:(map(select(.bash.test_run>0))|length),total:length}|"\(.ran)/\(.total) sessions ran a test cmd"' "$D"/*.json
  ```
- **Token churn** (top sessions re-reading context):
  ```
  jq -rs 'map({id:.id[0:8],proj:(.project|split("/")|last),cr:(.tokens.cache_read // 0)})|sort_by(-.cr)|.[0:5][]
    | "\(.cr) cache_read\t(\(.proj), \(.id))"' "$D"/*.json
  ```
- **Skill usage / dead skills** (which fleet skills you actually use vs built-and-skip). Skills used **≤2x in the whole window** are dead-weight candidates - low-confidence: prune or start adopting. The fleet is read from the installed skills, so it never goes stale:
  ```
  D="$HOME/.claude/velka/digests"; FLEET=$(ls "$HOME/.claude/skills")
  find "$D" -name '*.json' -exec cat {} + | jq -rs --arg f "$FLEET" '($f|split("\n")|map(select(length>0))) as $fleet | ([.[]|.skill_tooluse + .slash]|add) as $u | $fleet | map(. as $s | {s:$s,n:($u|map(select(.==$s))|length)}) | sort_by(.n) | .[] | "\(.n)x  \(.s)"'
  ```
  **Before calling any skill dead, cross-check typed history** - old transcripts get pruned, so digests undercount (this detector once reported a skill at 0 that history showed at 5 runs). For each ≤2x skill, count its typed invocations **inside the same window** (`.timestamp` is epoch milliseconds; use `0` for `--all`) and report the larger number:
  ```
  jq -s --arg s "/<skill>" --argjson since "$(jq -rn '"<window start as YYYY-MM-DDTHH:MM:SSZ>" | fromdateiso8601')000" '[.[] | objects | select(((.display // "") | startswith($s)) and (.timestamp // 0) >= $since)] | length' "$HOME/.claude/history.jsonl"
  ```
- **Cross-session file hotspots** (a file edited across MANY sessions = a churn magnet / refactor candidate - higher-value than within-session thrash):
  ```
  find "$D" -name '*.json' -exec cat {} + | jq -rs '[.[]|(.files_edited|keys[])]|group_by(.)|map({f:.[0],s:length})|map(select(.s>=5))|sort_by(-.s)|.[0:10][]|"\(.s) sessions  \(.f|split("/")|last)"'
  ```
- **Project distribution** (where effort actually goes - sessions/edits/tokens per repo; e.g. many sessions + near-zero edits = an investigation-heavy repo):
  ```
  find "$D" -name '*.json' -exec cat {} + | jq -rs 'group_by(.project)|map({p:(.[0].project|split("/")|last),sess:length,edits:(map(.tools.Edit//0)|add),cr:(map(.tokens.cache_read//0)|add)})|sort_by(-.sess)|.[0:8][]|"\(.sess) sess · \(.edits) edits · \(.cr) cache_read  \(.p)"'
  ```
- **Intent ↔ skill cross-check** (`--candidates` only - the LLM tier; velka *reasons over intents* here, unlike the mechanical detectors above). This replaces the old command-dance miner, which was **empirically proven useless** (recurring `cmd_seq` n-grams were ~100% skill-internal plumbing - API skills running `curl>jq` - or universal `git add>commit`; the genuinely forge-worthy patterns are *semantic intents*, not command strings, so no n-gram over commands can see them). Instead, cross-check each session's **intent** against the **skill catalog**:
  1. **Adoption gaps** - a recurring intent an EXISTING skill covers, done by hand (skill never invoked). "Covered-by" is an LLM judgment; **"not-used" is mechanical fact** (`skill_tooluse`/`slash`) - that half anchors the row.
  2. **New-skill candidates** - a recurring intent NO existing skill covers → forge one.

  Method:
  a. Read the LIVE skill catalog (so matching is grounded in what actually exists, incl. skills not in this repo):
  ```
  for d in ~/.claude/skills/*/; do n=$(basename "$d"); desc=$(sed -n 's/^description: //p' "$d/SKILL.md" 2>/dev/null | head -1); echo "$n :: ${desc:0:100}"; done
  ```
  b. Pull intent + used-skills per session:
  ```
  find "$D" -name '*.json' -exec cat {} + | jq -rs '.[] | select((.first_prompt//"")|length>0) | {p:.first_prompt, used:(.skill_tooluse+.slash), proj:(.project|split("/")|last)}'
  ```
  c. Classify each intent: which catalog skill (if any) covers it + was it used; cluster similar intents.
  d. Emit two tables, each row grounded in **counts + 2-3 real example intents**:
     - **Adoption gaps**: skill X · N sessions did this intent · used in only M · example prompts. (Exclude slash-invocation sessions - those trivially "used" the skill; not a gap.)
     - **New candidates**: proposed skill theme · N sessions · example prompts.

  **Honest caveats (state them):** intent-match is a fuzzy JUDGMENT - label confidence, never assert a gap without showing the prompts behind it; `first_prompt` holds only the first 2-3 human messages, so later intent drift is missed; this tier costs an LLM pass over ~all sessions (opt-in by design). If nothing recurs, say "no adoption gap or new-skill pattern stands out" - do not manufacture one.

## Phase 3 - Rank and lead
Rank habits by **impact = frequency × cost** (how often it recurs × how much it wastes). **Lead with the single highest-leverage habit as a Headline** - a reader skims the table and misses the one that matters.

## Phase 4 - Speculative tier (OFF unless `--advice`)
Only with `--advice`: a short list of judgment-level suggestions (prompt style, workflow restructuring). **Each labelled `argument, not measured`.** Default-suppressed - the mechanical counts carry the report; speculative advice with no footprint is the fortune-cookie failure this skill exists to avoid.

## Phase 5 - Emit + update marker
Surface the ledger, then write the marker so the next default run is incremental:
```
date -u +%Y-%m-%dT%H:%M:%SZ > ~/.claude/velka/last-run
```
(Skip the marker write on `--all`/`--since`/`--project` - those are explicit ad-hoc windows, not "since last time.")

## Output - the habit ledger (surfaced RAW to the user)
```
## 🜨 velka - the cycle's recurring sins
Window: <N sessions · <date range> · project=<all|path>>

**Headline:** <the ONE habit most worth fixing, with its number - or "no recurring inefficiency stands out">

| habit | evidence (counts · sessions/files) | confidence | suggested fix |
|-------|-----------------------------------|-----------|---------------|
| edit-thrash | page.tsx 123x (storefront, 3f9c2e1a) | high | plan/dialectic the design before editing |
| skipped litmus | 34/36 heavy-grep sessions, 0 litmus | low (candidate) | consider /litmus for claim-checks |
| testing | 3/441 sessions ran a test cmd | see caveat | (may run outside Claude) |

Coverage: analyzed <N> sessions (<range>). velka sees ONLY tools run through Claude Code - tests/edits/commits outside it are invisible. Mechanical footprints only; low-confidence rows are candidates for your review, not verdicts.

How to read: each row is a *signal*, not a verdict - you decide if it's waste or fine for your workflow (e.g. per-phase commits and incremental frontend edits often look like "thrash"/"storm" but aren't). **Pick ONE** to act on; ignore rows that cost you nothing. The value is the **trend** - re-run periodically and watch whether a habit you targeted actually moved. (`--explain` adds a what-it-means/what-to-do column.)
```
**`--explain` mode:** add a column (or a sub-line per row) covering: *what it means* (the behavior behind the number), *is it actually a problem* (name when it's benign - don't assume every row is waste), and *the concrete action* (incl. "ignore - fine"). Default runs omit this (keeps the ledger tight); `--explain` is the teaching view.

## Completion contract
A run is complete only when:
1. The digests were **refreshed** (`collect.sh` ran) and the **window is stated** (N sessions + range + any project filter).
2. Every habit row **ships its number** (counts + the sessions/files behind it); no bare assertions.
3. **Inference-beyond-footprint rows are marked low-confidence** ("candidate"), never stated as fact.
4. Any **testing/coverage finding carries the "only sees Claude-run tools" caveat.**
5. A **Headline** (top habit) leads; a **Coverage** line states the window + the blind spot.
6. The speculative tier appears **only** under `--advice`, each item labelled `argument, not measured`.
7. The last-run marker is updated (default window only).

## Guard rails
- **Ground or omit - never manufacture.** A habit row without its count is not emitted. A clean corpus → say "no recurring inefficiency stands out," do NOT invent one.
- **Footprint ≠ judgment.** velka proves what happened, not what you should have done. Skipped-tool / "should test more" rows are **low-confidence candidates**, explicitly your-call - never asserted.
- **The blind-spot caveat is mandatory** on testing/coverage findings: velka sees only tools run *through Claude Code*; IDE/CI/other-shell activity is invisible. Stating "you don't test" without it is a false accusation.
- **Cross-session by default.** Single-session windows are low-value (you lived it); warn and recommend `--all`.
- **Speculative is OFF by default.** Mechanical counts carry the report; `--advice` gates the judgment tier, every item labelled `argument, not measured`.
- **Read-only on your code (instruction-enforced, NOT structural).** velka reads transcripts and writes ONLY its own cache (`~/.claude/velka/` digests + last-run marker); it never edits your code, commits, or touches the repo. Be honest about the enforcement: the `allowed-tools` grant is narrowed to `collect.sh` + `jq`/`cat`/`ls`/`date` (arbitrary `bash` is NOT pre-approved, so an unexpected shell command prompts - the tripwire). But any `Bash` grant can in principle write via redirection - this is a **prompt-level boundary, not a hard guarantee.** For a hard backstop, add a `deny` rule in `settings.json`. Do not claim velka "physically cannot" alter code.
- **Efficient.** Digests are mtime-cached - only changed sessions re-parse. Never re-ingest raw transcripts in the analyzer; read the digests.
