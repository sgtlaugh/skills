# GitHub voice

How a review comment, PR reply or ticket status note reads when a person wrote it. Any skill that drafts text for GitHub follows this file, and the draft passes `voice-gate.sh` before anyone posts it. The gate checks the mechanical rules; the shape and tone below are on the writer.

## Shape

One or two short paragraphs, a blank line between them. An inline comment is usually 150-400 characters of prose; the gate stops it at 600 (code blocks don't count).

1. **The consequence first,** in plain words: what goes wrong and when. Identifiers in backticks, every file reference a link.
2. **Then the evidence.** One fact per sentence. When it takes two or more hops (this calls that, which also runs there), give the hops as a short list instead of a chain of clauses.
3. **Then the ask,** as a question or a soft suggestion: "Should we...?", "Can we...?", "Wondering if it would be simpler to...".

When proposing an alternative, name what it costs. Calibrate instead of asserting: "That might be fine for X, but...", "Fine by me, just flagging...".

**Short paragraphs, or bullets.** A paragraph runs a few short sentences, about 320 characters at most; the gate flags longer ones. When a comment carries two or more parallel facts - the hops of a call chain, several files, a list of cases - they go in bullets, one fact each, instead of one long paragraph. A single point is never split into bullet fragments.

**One review says each thing once.** The summary gives the overall concern in a sentence or two; the comments carry the detail. A summary that restates a comment is cut.

## Sounding like a person

A template is what gives automated review away: every comment opening the same way, every one ending on the same kind of question. Vary it the way a person does.

- **Openings differ** across one review: a fact, a question, "Wondering if...", "Not sure why...", "Looks like...". The gate stops two comments from opening the same way.
- **One interjection at most, and only when it means something:** "Hmm," for a real doubt, "Ah," when a chain of cause clicks, "Oh," for a surprising effect. Used everywhere, they become the new tell. Never "Well," as an opener: it reads as talking down.
- **Calibrated, not hedged:** "unless I'm missing something", "might be fine for X, but...". One per comment, not stacked.
- **Endings vary** too: a question, a soft suggestion, or just the fact when the fix is obvious.

## Lead-ins

- `**Minor nit:**` on a nit, and only on a nit.
- No other labels: no severity tags (`[critical]`, `**Warning:**`), no headings, no emojis.

## Code

- Fences always carry a language: `python`, `bash`, `diff`, or `text` for plain output.
- Over 15 lines goes inside `<details><summary>What it shows</summary>` ... `</details>`.
- A `suggestion` block only for a fix of 3 lines or fewer that the author can accept with one click. Anything bigger is a description plus a permalink.
- Permalinks pin a commit SHA (`/blob/4f2a9c1/...`), never a branch: a branch link points at different code next week.

## References

- **A file and line is a link** to the blob at the reviewed commit: ``[`moon.py:88`](https://github.com/acme/owl/blob/4f2a9c1/owl/moon.py#L88)``. A bare `moon.py:88` makes the reader go find it.
- **A PR or issue in another repo** is `owner/repo#N` (`acme/nest-config#16394`). GitHub autolinks only that form; `nest-config#16394` stays plain text. In the same repo, `#N` is enough.

## Approvals and status

- An approval says "Looks good!" plus what was checked, and admits what wasn't: "I did not test locally, but the retry path looks right."
- A status note leads with where the work stands, then what is open. No praise, no recap of what the reader already knows.

## Examples (invented)

**Bug, with the trade-off:**

> `refresh_moon_cache` holds the lock across the HTTP call ([here](https://github.com/acme/owl/blob/4f2a9c1/owl/moon.py#L88)), so a slow upstream stalls every reader.
>
> Can we fetch first and take the lock only for the swap? We'd occasionally fetch twice on a cold start, which seems cheaper than the stall.

**A finding that crosses files, as hops:**

> Ah, this lets `purge_expired_sightings` run twice at once.
>
> - Every nest delete enqueues it ([`nest.py:128`](https://github.com/acme/owl/blob/4f2a9c1/owl/nest.py#L128)).
> - This PR routes those messages to the `sightings` queue, where acme/nest-config#16394 starts a worker.
> - The nightly CronJob runs the same purge ([`purge.py:16`](https://github.com/acme/owl/blob/4f2a9c1/scripts/purge.py#L16)).
>
> Is the purge safe to run concurrently? If not, can we drop the enqueue now that the CronJob owns cleanup?

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
