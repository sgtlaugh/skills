---
name: gadfly
description: Interrogate a tech spec or architecture doc before it gets built - extract requirements, gate the blocking gaps, ground the design in the code it touches, stress-test through four adversarial lenses, while a parallel reviewer looks for what to cut and what reads unclearly. `--prd` checks whether the HOW satisfies the WHY. Hypotheses to check, not verdicts.
allowed-tools: Read, Write, Grep, Glob, Bash(curl:*), Bash(printf:*), Bash(echo:*), Bash(command:*), Bash(jq:*), Bash(pandoc:*), Bash(cat:*), Bash(grep:*), Bash(find:*), Bash(head:*), Bash(stat:*), Bash(mktemp:*), Bash(git rev-parse:*), Bash(cd:*), Bash(date:*), WebFetch, AskUserQuestion, Agent
---

# /gadfly - deep review here, simplify review alongside

gadfly runs two reviewers on a spec and merges them into one report:
- **The deep review** - requirements, grounding in the code, four adversarial lenses. You run it yourself, in this session: `~/.claude/skills/gadfly/references/deep-review.md`.
- **The simplify review** - what the spec could drop (features the product already has, special cases with no requirement behind them) and what reads unclearly. A separate agent runs it once the deep review is done: `~/.claude/skills/gadfly/references/simplify-reviewer.md`.

They stay separate on purpose. Benchmarked on two specs, every attempt to fold the simplify work into the deep review's own instructions cut its deep findings, and running the deep review inside a subagent made it shallower.

## Usage

```
/gadfly <confluence-url>      # fetch + interrogate a Confluence spec
/gadfly <page-id>             # bare Confluence page id
/gadfly <file-path>           # local spec: .md / .txt / .pdf / .docx
/gadfly <spec> --prd <prd>    # also cross-check against a PRD (WHY-vs-HOW); prd = path or url
/gadfly <spec> --no-simplify  # deep review only (cheaper)
```

A drafted solution is a spec too: run `/gadfly` on your own design (a new schema, a permission model), refine, repeat.

## Step 1 - Run the deep review

Read `references/deep-review.md` in full and follow it from Phase 0 to the end, exactly as written, as a normal gadfly run: every phase, its report file, its chat echo. When the spec came from Confluence, also save the converted text into the work dir Phase 0 created, so the simplify reviewer reads the same snapshot.

## Step 2 - Run the simplify reviewer

Start it only after the deep review's report is saved: a reviewer running alongside lets its result arrive mid-review, and in benchmarks that cost the deep review findings. Launch it with one `Agent` call and wait for its result. The agent's prompt is exactly this, with the inputs filled in, plus any `Repos (confirmed): ...` line and any "no human available" instruction from your own prompt:
```
Read ~/.claude/skills/gadfly/references/simplify-reviewer.md and follow it exactly.
Spec: <spec path>. PRD: <prd path or "none">.
```
Don't read `simplify-reviewer.md` yourself.

Skip this step, and note `Simplify: skipped - <reason>` for Step 3, when `--no-simplify` is given or the `Agent` tool isn't available (for example when gadfly itself runs as a subagent).

## Step 3 - Merge, then finish

Don't end your turn until the simplify reviewer has returned; ending the turn early ends a headless run with no merged report.

Then write one **new** file: `~/.claude/reports/gadfly/<spec-slug>.gadfly-merged.<ts>.md` (`<ts>` from `date +%Y%m%d-%H%M%S`):
1. The deep review's report, verbatim.
2. One line under its verdict line: `**Simplify:** <top 1-2 cuts, or "nothing to cut" | skipped - reason | failed - reason>`.
3. The simplify reviewer's `## Simplify` table and `## Readability` bullets, inserted right after the findings section (before `## Core model`). Drop a row or bullet only when a deep finding already raises the same point, and say so in one line: `Also in finding #N: <row>`. Never move them into the findings table or re-rank them. If the reviewer failed or returned no file, write `Simplify: failed - <reason>` there and don't fill the gap yourself.

**Chat echo** - print this and stop (it replaces the deep review's echo as the last thing you print):
```
gadfly: <spec title> - <verdict>
Steelman: <one line>
<the findings table>
Simplify: <top 1-2 cuts, one line each | nothing to cut | skipped - reason>
Readability: <count> issues
Top question: <the single most important open question>

Full report → <absolute path of the merged report>
  (adds per-finding trigger, evidence, falsifier and verify-by; simplify and readability; core model per store; cleared lenses; requirements; grounding)
```

## Completion contract
Done only when:
1. The deep review's report is saved and meets its own completion contract (`deep-review.md`, "Completion contract").
2. The merged report exists with the deep report verbatim, the `**Simplify:**` line, and the Simplify and Readability sections (or the skipped/failed line).
3. The chat echo's `Full report →` line points at the merged report.

## Guard rails
- **Read-only on inputs.** gadfly reads the spec and the code and writes only its reports and the simplify reviewer's file. This is an instruction, not a grant boundary: `curl`, `Write`, `find` and `Agent` are granted for fetch, reports, repo lookup and the simplify reviewer, and could write.
- **Don't invent the design.** If the spec is too vague to review, the questions are the deliverable.
