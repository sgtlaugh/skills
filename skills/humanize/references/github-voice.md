# GitHub voice

How a review comment, PR reply or ticket status note reads when a person wrote it. Any skill that drafts text for GitHub follows this file, and the draft passes `voice-gate.sh` before anyone posts it. The gate checks the mechanical rules; the shape and tone below are on the writer.

## Shape

One or two short paragraphs, a blank line between them. An inline comment is usually 150-400 characters of prose; the gate stops it at 600 (code blocks don't count).

1. **The fact first,** with a SHA-pinned permalink and identifiers in backticks.
2. **Then why it matters,** as a question or a soft suggestion: "Should we...?", "Can we...?", "Wondering if it would be simpler to...".

When proposing an alternative, name what it costs. Calibrate instead of asserting: "That might be fine for X, but...", "Fine by me, just flagging...".

Lists only for real enumerations (two questions, three files). Never for a single point split into fragments.

## Lead-ins

- `**Minor nit:**` on a nit, and only on a nit.
- No other labels: no severity tags (`[critical]`, `**Warning:**`), no headings, no emojis.

## Code

- Fences always carry a language: `python`, `bash`, `diff`, or `text` for plain output.
- Over 15 lines goes inside `<details><summary>What it shows</summary>` ... `</details>`.
- A `suggestion` block only for a fix of 3 lines or fewer that the author can accept with one click. Anything bigger is a description plus a permalink.
- Permalinks pin a commit SHA (`/blob/4f2a9c1/...`), never a branch: a branch link points at different code next week.

## Approvals and status

- An approval says "Looks good!" plus what was checked, and admits what wasn't: "I did not test locally, but the retry path looks right."
- A status note leads with where the work stands, then what is open. No praise, no recap of what the reader already knows.

## Examples (invented)

**Bug, with the trade-off:**

> `refresh_moon_cache` holds the lock across the HTTP call ([here](https://github.com/acme/owl/blob/4f2a9c1/owl/moon.py#L88)), so a slow upstream stalls every reader.
>
> Can we fetch first and take the lock only for the swap? We'd occasionally fetch twice on a cold start, which seems cheaper than the stall.

**Question about intent:**

> In which cases do we need to keep expired sightings? Wondering if it would be simpler to drop them at write time and skip the filter in `list_sightings` altogether.

**Nit:**

> **Minor nit:** `owl_count` is never read after the loop.

**Small fix as a suggestion:**

> Why not the simpler check?
>
> ```suggestion
> return "night" in shift.tags
> ```

**Approval:**

> Looks good! Ran the migration against a copy of the 05/23/2002 snapshot and the counts match. I did not test the rollback.

## Not this

> 🚀 **Great work!** This PR significantly enhances the robustness of the caching layer. However, it's worth noting that there are a few areas for improvement:
>
> ## Issues
> - **[Critical]** The lock is held too long.

Every line of that trips the gate or the banned list, and none of it tells the author what to change.
