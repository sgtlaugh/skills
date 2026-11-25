# Changing a skill

- A wording change (trim, reformat, new rule, examples table, effort bump) ships only after an A/B shows it helps - most measured so far regressed or changed nothing (forge's reader-first spec layout is the exception)
- A mechanical bug fix (wrong path, broken parse, missed case) ships without an A/B - these have helped every time
- humanize's github-voice: an overview recipe (evidence in a `text` block, "So"/"And" openers), a "what's allowed" list and length-by-stakes all lost or tied a blinded judge over 3 rounds and 36 drafts (11/2026) - a prescribed connective reads formulaic, so voice comes from examples in voice.md
- A/B runs are headless (`claude -p --output-format stream-json`), at least 3 per arm, with pass rules written down before the first run
- The baseline arm runs the same day as the variant; an older baseline is stale, results drift between days, sometimes within one day: when a variant loses an item, run a fresh control of the original in the same hour before blaming the variant
- Read the transcripts of a scorer's misses before trusting its numbers - a grep-based scorer miscounts
- Retiring a skill needs two checks first: transcripts show no runtime loads of it, and a grep of every repo that references it (sandbox skill lists included) comes back clean
- A second kind of work goes in a separate agent: every gadfly variant that put the simplify review into the deep review's own instructions lost deep findings
- A skill's core procedure lives in its own SKILL.md, or in another skill loaded with the Skill tool, never in a file it Reads: skill content arrives as instructions, a Read as a tool result, which Claude follows with more skepticism (Anthropic's guardrail docs), and every gadfly variant built that way lost deep findings
- Rubric items are observable outcomes with no escape clause: "fails unless it gives a reason" lets the judge pass any output that gives one
- When a helper costs the main pass a little, strengthen the main pass with one narrow rule instead of reshaping the helper: gadfly's simplify reviewer cost about 0.5 deep findings per run in every shape, and one rule (check code snippets in the spec) won it back
