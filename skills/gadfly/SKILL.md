---
name: gadfly
description: Interrogate a tech spec or architecture doc before it gets built - extract requirements, gate the blocking gaps, ground the design in the code it touches, stress-test through four adversarial lenses, while a parallel reviewer looks for what to cut and what reads unclearly. `--prd` checks whether the HOW satisfies the WHY. Hypotheses to check, not verdicts.
allowed-tools: Read, Write, Bash(date:*), Agent, Skill
---

# /gadfly - deep review plus a simplify review

gadfly runs two reviewers on a spec and merges their reports:
- **The deep review** - requirements, grounding in the code, four adversarial lenses. It's the `gadfly-deep` skill, which you load with the `Skill` tool and run yourself, in this session.
- **The simplify review** - what the spec could drop (features the product already has, special cases with no requirement behind them) and what reads unclearly. A background agent runs it from `~/.claude/skills/gadfly/references/simplify-reviewer.md`.

They stay separate, and the deep review is loaded as a skill rather than read as a file, because both measured better: in benchmarks, folding the simplify work into the deep review, or reading the deep review from a file, cut its deep findings. Anthropic's docs say Claude treats instructions in tool results (such as a file read) with more skepticism than skill content.

## Usage

```
/gadfly <confluence-url>      # fetch + interrogate a Confluence spec
/gadfly <page-id>             # bare Confluence page id
/gadfly <file-path>           # local spec: .md / .txt / .pdf / .docx
/gadfly <spec> --prd <prd>    # also cross-check against a PRD (WHY-vs-HOW); prd = path or url
/gadfly <spec> --no-simplify  # deep review only (cheaper)
```

## Step 1 - Start the simplify reviewer

Launch it with one `Agent` call; it runs in the background and its result arrives as a notification. The agent's prompt is exactly this, with the inputs filled in, plus any `Repos (confirmed): ...` line and any "no human available" instruction from your own prompt:
```
Read ~/.claude/skills/gadfly/references/simplify-reviewer.md and follow it exactly.
Spec: <spec as given>. PRD: <prd as given, or "none">.
```
Don't read `simplify-reviewer.md` yourself.

Skip this step, and note `Simplify: skipped - <reason>` for Step 3, when `--no-simplify` is given or the `Agent` tool isn't available (for example when gadfly itself runs as a subagent).

## Step 2 - Run the deep review

Invoke the `gadfly-deep` skill with the `Skill` tool, passing the same arguments you got (minus `--no-simplify`) plus any `Repos (confirmed): ...` line and "no human available" instruction. Then follow it fully in this session, exactly as a normal run: every phase, its report file, its chat echo. Ignore the simplify reviewer while you work.

## Step 3 - Merge, then finish

Don't end your turn until the deep review's report is saved and the simplify reviewer has returned; if it's still running, wait for its notification. Ending the turn early ends a headless run with no merged report.

Then write one **new** file: `~/.claude/reports/gadfly/<spec-slug>.gadfly-merged.<ts>.md` (`<ts>` from `date +%Y%m%d-%H%M%S`):
1. The deep review's report, verbatim.
2. One line under its verdict line: `**Simplify:** <top 1-2 cuts, or "nothing to cut" | failed - reason>`.
3. The simplify reviewer's `## Simplify` table and `## Readability` bullets, inserted right after the findings section (before `## Core model`). Drop a row or bullet only when a deep finding already raises the same point, and say so in one line: `Also in finding #N: <row>`. Never move them into the findings table or re-rank them. If the reviewer failed or returned no file, write `Simplify: failed - <reason>` there and don't fill the gap yourself.

With `Simplify: skipped`, the deep review's own report is the final report: skip the merged file and finish with the deep review's chat echo plus one line, `Simplify: skipped - <reason>`.

**Chat echo** - print this and stop (it replaces the deep review's echo as the last thing you print):
```
gadfly: <spec title> - <verdict>
Steelman: <one line>
<the findings table>
Simplify: <top 1-2 cuts, one line each | nothing to cut>
Readability: <count> issues
Top question: <the single most important open question>

Full report → <absolute path of the merged report>
  (adds per-finding trigger, evidence, falsifier and verify-by; simplify and readability; core model per store; cleared lenses; requirements; grounding)
```

## Completion contract
Done only when:
1. The deep review's report is saved and meets `gadfly-deep`'s own completion contract.
2. Unless the simplify review was skipped: the merged report exists with the deep report verbatim, the `**Simplify:**` line, and the Simplify and Readability sections (or the failed line).
3. The chat echo's `Full report →` line points at the final report.

## Guard rails
- **Read-only on inputs.** gadfly reads the spec and the code and writes only its reports and the simplify reviewer's file. This is an instruction, not a grant boundary: `Write`, `Agent` and the grants `gadfly-deep` declares could write.
- **Don't invent the design.** If the spec is too vague to review, the questions are the deliverable.
