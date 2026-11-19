# Changing a skill

- A wording change (trim, reformat, new rule, examples table, effort bump) ships only after an A/B shows it helps - most measured so far regressed or changed nothing (forge's reader-first spec layout is the exception)
- A mechanical bug fix (wrong path, broken parse, missed case) ships without an A/B - these have helped every time
- A/B runs are headless (`claude -p --output-format stream-json`), at least 3 per arm, with pass rules written down before the first run
- The baseline arm runs the same day as the variant; an older baseline is stale, results drift between days, sometimes within one day: when a variant loses an item, run a fresh control of the original in the same hour before blaming the variant
- Read the transcripts of a scorer's misses before trusting its numbers - a grep-based scorer miscounts
- Retiring a skill needs two checks first: transcripts show no runtime loads of it, and a grep of every repo that references it (sandbox skill lists included) comes back clean
- New review work goes in a separate agent, not the existing pass: every gadfly variant that added checks to the same context lost findings its existing checks used to catch
- A skill runs shallower as a subagent, and when a parallel agent's result lands mid-run; keep depth-critical work top-level and start helpers after it finishes
- Rubric items are observable outcomes with no escape clause: "fails unless it gives a reason" lets the judge pass any output that gives one
