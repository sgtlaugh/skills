---
name: humanize
description: Strip AI patterns from text and rewrite it for a human voice. Use when text sounds AI-generated. For GitHub review comments, PR replies and status notes it also applies github-voice and runs voice-gate; --concise halves length.
allowed-tools: Read, Bash(bash ~/.claude/skills/humanize/voice-gate.sh:*)
---

# /humanize - strip the AI, keep the substance

Remove the patterns that mark text as AI-generated, then tighten for clarity.

## Usage

```
/humanize <text>          # rewrite the pasted text
/humanize                 # rewrite your previous response
/humanize <file>          # print a rewrite of the file (the file itself is not edited)
/humanize --concise ...   # any of the above, and cut length roughly in half
```

If the argument is an existing path, Read it; otherwise treat it as text.

## Workflow

### Step 1: Scan for tells

Read the input. Notice: em dashes, rule-of-three lists, "it's not X, it's Y" framing, boldface on every key term, self-narration ("this highlights"), copula avoidance ("serves as" instead of "is").

If the user gave instructions about voice, audience, or format, honor those alongside the rules below.

**Required format beats these style rules.** On another skill's output (e.g. `/nicepr --humanize`), keep the structure it requires - headings and their fixed emoji (`### ✅ QA Steps`), `**Lead-in:**` bold labels with a colon, Title Case titles, `- [ ]` checkboxes, code blocks, permalinks - and rewrite only the prose inside it. In PR text, nicepr's format requires bold lead-ins with a colon and Title Case PR titles; stripping those from a PR is WRONG. Outside PRs the banned list's bold and casing rules apply as written.

**Text headed for GitHub** (a review comment, PR reply or status note): also follow `references/github-voice.md`, and when `~/.config/claude-skills/voice.md` exists, Read it too: it is the user's own voice (their moves, real examples and caps on signature phrases). github-voice.md sets the shape; voice.md sets whose voice it is, so match the move from its examples, never their topic. Then pipe the rewrite into the gate on stdin (`bash ~/.claude/skills/humanize/voice-gate.sh <<'EOF'` ... `EOF`, so no file has to be written) and fix every line it prints until it prints `voice-gate: clean`. Review summaries and status notes over 600 chars need `--max-chars N`. The gate also accepts a JSON array of review comments (objects with a `"body"` string), checked per comment plus a 5-comment cap. A hit you believe is a false positive is reported verbatim with the reason, never silently skipped.

### Step 2: Apply the rules

Two passes:
- First pass: remove banned patterns (the cleanup)
- Second pass: tighten for clarity and directness

Read `references/banned-list.md` before the first pass: the completion contract checks against it.

### Step 2b: Concise mode (only with --concise)

Also cut length by ~50% after stripping patterns:
- Every paragraph that can be one sentence, make it one sentence, as long as that sentence has at most one dependent clause (the clause rule still applies)
- Every sentence that can lose a clause without losing meaning, cut the clause
- Collapse implementation details into a single bullet or `<details>` block
- If a table says it, don't also say it in prose above/below the table
- Target: the reader gets the full picture in under 2 minutes

### Step 3: Self-check

Walk the completion contract item by item; for the banned-phrases item, make one pass per section heading of banned-list.md.

### Step 4: Deliver

Output the rewritten text directly. No preamble ("here's the rewrite!"). If the user asked for a comparison, provide it after the text. For GitHub text, end with the gate's final output line after the rewrite.

---

## Hard rules

1. **No em dashes.** Use commas, periods, or restructure.
2. **No rule-of-three lists** of adjectives, slogans or rhetorical beats. Two items or four; three every time is the giveaway. A factual list (three files that changed) stays as long as it is.
3. **No contrast framing.** Never "It's not X, it's Y" or the escalation version. Just say what it is.
4. **No staccato bursts.** Don't string three+ short sentences for drama. Vary length.
5. **No rhetorical transition questions.** Delete "The catch?" "But here's the thing."
6. **No "let's" that announces instead of acting.** "Let's dive in", "let's break it down", "let's explore" sound like a YouTube intro. A "let's" that proposes a concrete step stays: "Let's do the actual run on Sunday", "let's merge this and open a follow-up".
7. **No fake naming.** Don't capitalize ordinary ideas into "The 5-Step Method."
8. **No self-narration.** Delete "this highlights," "the key takeaway is," "here's why that matters." If the point landed, narration is dead weight.

---

## Patterns to remove

### Phrases to delete

"It's worth noting that," "at the end of the day," "that being said," "first and foremost," "needless to say," "simply put," "the reality is," "let that sink in," "here's why this matters," "this highlights," "this underscores," "stands out as," "paves the way for," "bridges the gap," "raises the bar."

### Words to swap

**Verbs:** leverage - use; harness - use; unlock (figurative) - enable; delve - look at; navigate (figurative) - handle; underscore - show; foster - build; streamline - simplify; craft (figurative) - write or make; spearhead - lead; demystify - explain; utilize - use; facilitate - help; optimize - improve; augment - add to.

Skip a swap when the word is the precise technical term: implement an interface, optimize a query, a feature flag.

**Adjectives to cut:** seamless, robust, cutting-edge, innovative, transformative, comprehensive, holistic, dynamic, scalable, groundbreaking, pivotal, unprecedented.

**Transitions to cut:** moreover, furthermore, however (as opener), nevertheless, nonetheless, thus, hence, indeed, notably, additionally, consequently.

The complete list is `references/banned-list.md`, required reading per Step 2.

### Style fixes

- **Copula avoidance.** "serves as," "stands as," "functions as" - just use "is." "boasts," "features," "offers" - just use "has."
- **-ing phrase padding.** Cut "highlighting the importance of," "underscoring the need for," "reflecting a broader trend toward." Words without meaning.
- **Synonym cycling.** Don't call the same thing "the platform," "the system," "the solution," "the tool" in consecutive sentences. Pick one.
- **Boldface abuse.** Don't bold random words mid-sentence (full rule and the PR exceptions in `references/banned-list.md`).
- **Filler:** "in order to" - "to"; "due to the fact that" - "because"; "has the ability to" - "can"; "in the event that" - "if". Delete "it is important to note that" entirely.
- **Hedging.** One qualifier per claim. "It could potentially possibly be argued that the policy might have some effect" becomes "The policy may affect outcomes."

---

## Tighten for technical writing

After stripping patterns, apply these for technical/PR/doc contexts:

- **Be direct.** State what changed and why. Not "This PR introduces comprehensive improvements to the upload flow by ensuring that file storage is properly delegated" but "Delegate file storage to the archive service instead of writing to S3 directly."
- **Specifics over adjectives.** Not "significant performance improvement" but "8x speedup (40 min to 5 min)."
- **Cut throat-clearing.** If the first sentence of a section doesn't add information, delete it.
- **Split any sentence with two or more dependent clauses.** Long compound sentences with semicolons are the other AI tell. If splitting leaves three short sentences in a row, Hard rule 4 wins: merge two back.

---

## Example

**Before (AI-generated, a free-form PR description, not nicepr output):**

> ## Overview
>
> This PR introduces comprehensive improvements to the upload flow by ensuring
> that file storage is properly delegated to the archive service. Additionally,
> it implements robust error handling for the S3 copy operation, which was previously
> not handled (causing silent failures in production). The changes also update the
> related test suite to cover the new edge cases.

**After:**

> ## Why
>
> `copy_upload_to_archive` silently swallowed S3 copy failures.
> Uploads succeeded but files never reached the archive.
>
> ## What changed
>
> - Add retry + error propagation to `copy_upload_to_archive`
> - Raise `ArchiveCopyError` on exhausted retries instead of logging and continuing
> - Cover the retry and failure paths in `test_archive_tasks.py`

What changed: "comprehensive improvements" gone, "additionally" gone, "robust" gone, parenthetical aside gone, filler ("the changes also update") gone. What replaced it: the actual bug in one sentence, verb-led bullets for what changed.

---

## Completion contract

The output is NOT done until:
1. Zero em dashes remain
2. Zero rhetorical rule-of-three groupings (factual lists exempt, Hard rule 2)
3. Zero "This PR introduces/ensures/implements" openers
4. Zero self-narration ("this highlights," "here's why")
5. Zero copula avoidance ("serves as" instead of "is")
6. No surviving banned phrases from the reference list
7. The required structure from Step 1 is intact: headings and their fixed emoji, `**Lead-in:**` labels, Title Case PR titles, checkboxes, code blocks
8. No three short sentences in a row (Hard rule 4)
9. Each of Hard rules 1-8 holds, checked by number
10. Text headed for GitHub: the last gate run printed `voice-gate: clean`, or every hit it still prints is quoted as a false positive with its reason

## Reference files

- `references/banned-list.md` - full banned words, phrases, transitions, and emojis
- `references/github-voice.md` - shape, tone and examples for review comments, PR replies and status notes
- `voice-gate.sh` - mechanical check for text about to be posted on GitHub
