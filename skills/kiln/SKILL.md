---
name: kiln
description: >
  Lint a skill - static review of an existing SKILL.md for the flaws that
  silently weaken it: advisory rules that won't bind, contradictions, stale
  refs, missing output contract, unanchored claims, dead content,
  premature-completion steps, frontmatter drift. Produces prioritized action
  items. Read-only; does NOT run the skill. Use after writing/editing a skill,
  or before adopting someone else's.
trigger: /kiln
allowed-tools: Read, Grep, Glob, Bash(grep:*), Bash(rg:*), Bash(find:*), Bash(ls:*)
argument-hint: "<skill name or path> [--fire], e.g. 'occam' or 'occam --fire'"
---

# /kiln - fire a skill, find the cracks (static lint)

Points at an existing skill and reports structural flaws + concrete fixes. It **reads; it never edits or runs the skill.**

**Scope (state this in the output): kiln checks STRUCTURE, not CORRECTNESS.** A clean pass means the skill is well-*built*, NOT that its output is *right* - only running it on real inputs proves that (firing != correct). Say so; don't let a clean lint read as "verified."

**Authoring reference** (how to write skills well - NOT re-taught here): mattpocock `writing-for-agents` (https://github.com/mattpocock/skills/tree/main/skills/productivity/writing-for-agents). kiln *checks for* the failure modes that guide names; for "how should I write this," point the user there.

## Step 1 - Locate & read
- **No target given -> ask which skill to lint; don't guess.**
- **`--fire` flag -> after the static checks, also run the adversarial test-generation pass (`--fire` section below). Generation only: kiln NEVER executes the skill.**
- Resolve target, in order: a **bare skill name** (`occam`) -> `~/.claude/skills/<name>/SKILL.md` (the installed path; resolves symlinked skills too) - this is the normal case; else a **dir** -> its `SKILL.md`; else a **`SKILL.md` path** directly. If a name doesn't resolve there, `find ~ -maxdepth 5 -path "*/<name>/SKILL.md"`; a plugin skill (`plugin:name`) lives under `~/.claude/plugins/`, so strip the prefix and `find ~/.claude/plugins -path "*/<name>/SKILL.md"`. `ls` the resolved dir for referenced files (reference docs, configs, sub-skills). Read `SKILL.md` in full + skim referenced files.
- Note the skill's own shape: frontmatter, command/step structure, whether it has an output contract.

## Step 2 - Run the checks
Grep where a pattern decides it; reason for the rest. Each finding needs a `line` + a concrete fix.

### A. Binding - vague rules don't change behavior (the #1 check)
The hardest-won truth: **advisory prose doesn't bind; concrete fixed-outcome rules do.** Find the weak ones:
```
grep -niE "try to|consider|if unclear|should( probably)?|when possible|ideally|aim to|attempt to|make sure( to)?|be careful" "<resolved SKILL.md>"
```
**Discard false positives first:** a hit inside a ``` ``` code fence (query DSL - OpenSearch bool `should`/`must`; example commands) or inside a regex/grep pattern string is **syntax/example, not an advisory rule** - skip it. (kiln's own check pattern + bool-query `should` trip this; don't self-flag.)

For each surviving hit: does it give the model a **fixed outcome**, or just nudge? A rule that *gates behavior on judgment* ("if unclear, escalate"; "try to be thorough") won't fire under pressure. **Fix shape:** rewrite to a fixed outcome - *"<giving up> is NOT a valid stop until you tried A, B, C"* / *"the headline is the exact <artifact>, never <tempting-wrong-value>"*. The give-up must be explicitly invalid; the desired result must be fixed.

### B. Output contract & anchoring
- **Missing output contract.** Grep for a presence-based "what the report MUST contain" / "completion criterion" section. **Absent -> top finding:** add one. A presence-based contract (the report MUST show X, Y, Z) is what makes a skill self-verifiable and cheap to test.
- **Unanchored claims.** Scan for rules that let the skill state a fact (count, `file:line`, root cause, "healthy", status) **without requiring the source artifact shown.** A claim with no cited evidence is where skills bluff. **Fix:** require each claim ship its artifact - *"show the query behind the count / the trace behind the file:line, or write Can't-determine; never fabricate."*

### C. Contradictions & stale references
```
grep -niE "above|below|step [0-9]|section" "<resolved SKILL.md>"
grep -nE "[Ss]ee (the )?[A-Z]" "<resolved SKILL.md>"   # case-sensitive: a capitalized name like "see Step 3", not "see the code"
```
- Each directional ref ("above"/"below"/"Step N"/"see X") must resolve to a section that still exists *in that direction*. Flag stale ones (common after a restructure - e.g. "Step 7" when sections were renamed).
- Cross-read the `MUST`/`ALWAYS`/`NEVER` rules for mutual conflict (real example: *"MUST use the excludes block"* vs *"overview uses an include-list"*). **Fix:** repoint refs to named sections; reconcile conflicts by scoping one or stating precedence.

### D. Matt's failure modes (with our cautions)
- **Premature completion** - a step whose completion criterion is vague ("investigate", "check it") lets the model stop early. Flag steps lacking a **checkable** criterion. (Make it checkable first; split only if needed.)
- **Duplication** - same rule in N places. **Caution:** distinguish *deliberate repeat-for-adherence* (a critical rule echoed in the contract AND the body - fine, often necessary) from *accidental drift* (two copies that can diverge on edit). Flag only drift-risk, not intentional reinforcement.
- **Sediment** - stale leftover layers from past edits (orphaned examples, refs to removed features/flags).
- **Sprawl** - too long. **CAUTION (do NOT flag length alone):** flag **dead content** (unreferenced, never-fires, pure restated-default) - NOT validated teeth. Specificity is function, not fat: a concrete deterrent + its example number IS the binding mechanism. Cutting it regresses behavior.
- **No-op** - a line the model "already obeys by default." **CAUTION - departs from Matt's "delete failing sentences":** you **cannot reliably judge a no-op statically.** A line that reads like rationale can be load-bearing teeth (a count rule's two-number example looked trimmable; cutting it regressed the count). **Flag as "candidate no-op - verify by running with/without before deleting", NEVER "delete".** For behavioral skills, prove it's inert empirically first.

### E. Frontmatter & description
- **Description** front-loads the leading word; one trigger per behavior-branch; no identity already restated in the body.
- **allowed-tools = pre-approve the expected tools; unexpected ones still prompt (a least-privilege tripwire).** In normal/interactive mode this is real value: list the tools the body actually uses (grep it) -> they run without friction, and anything UNLISTED falls to the ask-default -> you get **prompted -> you catch unexpected tool use.** Not a hard block (the tool isn't disabled, it just asks) - but the prompt IS the security signal. **Moot only under `--dangerously-skip-permissions`** (bypass pre-approves everything; only deny/ask rules survive). So: **missing allowed-tools on an interactive skill = should-fix** (friction + no tripwire); declare what the body uses; **over-broad lists mildly weaken the tripwire** (pre-approve only what's needed).
  - **Check both directions - and never say "drop X" without grepping for a pipeline.** (a) **Gap:** a tool the body uses but isn't listed prompts every run - and this **includes the dedicated `Grep`/`Glob`/`Read` the system prompt tells the model to *prefer* over bash `grep`/`find`/`cat`**; if the body greps/globs/reads, those dedicated tools should be granted (else the *preferred* tool is the one that prompts while the redundant bash variant is pre-approved - backwards). (b) **A bash variant is NOT droppable just because a dedicated tool "covers" it - if it runs inside a pipeline or loop** (`pandoc … | head`, `… | grep`, a `for … find` loop) the dedicated tool **can't** substitute inside a shell pipe. **Before recommending "drop `Bash(cat:*)`/`Bash(head:*)`/`Bash(grep:*)`, covered by Read/Grep", grep the body for that command in a pipe/loop; if it's there, KEEP it.** Only call a bash variant droppable when it's used standalone *and* a dedicated tool fully replaces it.
- **name / trigger consistent** with the file/dir and how it's invoked.

### F. Enforceability - a safety-critical rule needs a law, not just a wish
A prompt rule is a **request**, not a guarantee - the model can slip, especially on irreversible actions. For **safety-critical rules ONLY** - READ-ONLY, `never PUT/DELETE/PATCH`, `never commit/push/reset`, `never rm`, no prod-write/exfil - flag prompt-only enforcement and recommend a **hard backstop the model can't ignore:** a `deny` rule in `settings.json` (survives `--dangerously-skip-permissions` - the real boundary), a hook, or a test. kiln **can't see settings** -> *recommend + say "verify a deny/hook backstop exists"*, don't claim it's missing.
**Scope tightly: only irreversible/destructive/security rules.** Quality rules (count-anchor, ranking, scope-disclosure) are caught by the output contract + tests - a prompt-slip there isn't catastrophic, so **don't** flag those. ("Rules are requests; hooks/deny are laws" - back only the rules where a single slip is costly.)

**Claim-vs-grant contradiction (the one this check most often MISSES - always run it).** When a skill makes a safety **claim** (`read-only`, `never commit/push/reset`, `never post`, `never edit/write`), cross-check it against `allowed-tools` for a grant **capable of the forbidden action** - judge the grant by its CAPABILITY, not the skill's stated intent:
- `Bash(bash:*)` / `Bash(sh:*)` / a broad `Bash(*)` → **arbitrary** write/delete/sed-in-place (redirection + `rm` + `sed -i`). Defeats *any* read-only claim.
- `Bash(git:*)` → can `commit`/`push`/`reset` (defeats "never commit"). `Bash(gh:*)` → can post PRs/comments (defeats "never post"). `Write`/`Edit`/`NotebookEdit` → defeats "never edit/write".

If a claim and a grant capable of breaking it coexist → **must-fix contradiction: the claim is prompt-only, NOT structural.** Resolve one of two ways: **(a) scope the GRANT to read-only subcommands** (`Bash(git log:*)`/`Bash(git show:*)`/`Bash(git diff:*)` not `Bash(git:*)`; read-path `Bash(gh api:*)` not `Bash(gh:*)`), or **(b) scope the CLAIM** to what's true (e.g. "read-only on your repo; writes only its own output file") **+ recommend a `deny` backstop.** **The trap to name explicitly: do NOT certify a read-only claim as "structural / physically can't" just because `Write`/`Edit` are absent - `Bash` subsumes them.** A grant a read-only skill needs to *read* (`Bash(grep:*)`, `Bash(jq:*)`, `Bash(git log:*)`) is fine; the defect is a *capable* grant paired with an *un-scoped* claim.

## Step 3 - Output (action items)
```
## kiln - <skill> (<N findings>)
Scope: structure only - a clean pass != correct output (run it to verify behavior).

Must-fix:
- [Binding|Contract|Contradiction] `line` - <issue> -> <concrete fix>. <high|med confidence>

Should-fix:
- [Premature|Sediment|Frontmatter|Anchoring|Enforceability] `line` - <issue> -> <fix>.

Nits:
- [Wording|Duplication] `line` - <issue> -> <fix>.

Candidates (verify, don't blind-cut):
- [No-op?|Dead?] `line` - <why suspected> -> TEST with/without before trimming (specificity may be teeth).

Solid: <what's already well-built> ✓
```
- Severity by **impact**: binding / missing-contract / contradiction, including a claim-vs-grant contradiction (F) = **Must-fix** (these change whether the skill works). Premature-completion / sediment / frontmatter = Should-fix. Wording / sprawl = Nit. Suspected no-ops = Candidate (never auto-cut).
- **No findings -> say "Solid ✓" and stop. Do NOT manufacture nits** - a well-built skill is the success case.

## `--fire` - adversarial test generation (the grill; GENERATES, never runs)
A second pass after the static lint: **imagine the inputs that would break this skill**, so you can run them later. `--fire` does NOT execute the skill - it emits a list of candidate test cases. Cheap (one reasoning pass).

Method - generate the probes most likely to expose a REAL failure, **NOT one-per-discipline regression coverage.** Spend most of the budget on the dangerous frontier, few on regression. Ask *"what input makes this produce WRONG / INCOMPLETE / UNANCHORED / EMPTY output?"* - in priority order:
1. **"Looks fine, isn't" (MOST probes here)** - inputs where the skill emits *plausible-but-wrong* output, not an obvious failure: the answers a human would trust. The highest-value, hardest-to-catch probes.
2. **The skill's own named blind spots / handoffs** - wherever it says `Can't-determine`, "needs APM", "not log-solvable", "hypothesis", "out of scope" -> generate the input that lands there and check it scopes **honestly** (not false-confidence, not a false "healthy").
3. **Its hardest / non-deterministic mode** - the deepest path (cross-repo trace, multi-step root-cause). Probe whether it lands right, and flag *"this one likely needs jury, not a single run."*
4. **Static-lint gaps** - if a rule looked advisory/unanchored, an input that exploits it.
5. **Regression (FEWEST - one per solid discipline, only to catch regressions).** Don't pad the list with these: a probe a well-built skill obviously passes is low value.

**Don't cluster** - two probes on the same edge add little; spread across *distinct* failure modes. A short list of dangerous probes beats a long list of regression confirmers.

Emit each case as **plain markdown - NOT a fenced code block** (a fenced YAML block renders as hard-to-read syntax-highlighted cyan/red in the terminal). Use this shape per case:

**`<id>`** - invoke: `/<skill> <args>` *(use a real/seed input where live data is needed)*
- **targets:** <weakness/discipline it probes>
- **tricky:** <why this input stresses it>
- **expect:** <the correct behavior - the ASSERTION a runner checks>

**These are HYPOTHESES, not findings.** A probe that *should* break the skill usually doesn't until you RUN it - counter-examples are wrong more often than right. So `--fire` says *"verify these"*; it NEVER claims the skill fails. Generation stops here: run each probe by hand, or with `/jury <skill> <args>` for the non-deterministic ones. kiln does not run them.

## Guard rails
- **Read-only.** kiln reports; it never edits, deletes, or runs the target skill.
- **`--fire` generates test cases, it does NOT run them.** Running them is yours (by hand, or `/jury`). The boundary is hard: kiln analyzes (lint + generate), never executes.
- **One skill per run.** kiln lints a single target. To audit a whole collection, loop it in the shell - "all" is orchestration, not lint, and a per-skill tool composes cleanly with a future empirical (`--fire`) tier.
- **Mass-flag = convention, not defect.** If you're linting several skills and a finding repeats across most of them (e.g. they all omit `allowed-tools`), that's a **convention** - raise it once as a collection decision, don't ding each skill. (If you'd flag it everywhere, it's a preference, not a bug.)
- **Structure, not correctness.** Always scope the verdict this way - a clean lint is not a behavior guarantee. Verifying behavior is a separate, expensive step (run the skill on real inputs).
- **Don't flag teeth as bloat; suspected no-ops are TEST-not-DELETE.** Length and specificity are not defects; dead content is.
- **Cheap by design** - one read + grep. Never invoke the target skill (that's the empirical tier, out of scope here).
