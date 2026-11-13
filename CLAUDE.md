# Changing a skill

- A wording change (trim, reformat, new rule, examples table, effort bump) ships only after an A/B shows it helps - every one measured so far regressed or changed nothing
- A mechanical bug fix (wrong path, broken parse, missed case) ships without an A/B - these have helped every time
- A/B runs are headless (`claude -p --output-format stream-json`), at least 3 per arm, with pass rules written down before the first run
- The baseline arm runs the same day as the variant; an older baseline is stale, results drift between days
- Read the transcripts of a scorer's misses before trusting its numbers - a grep-based scorer miscounts
- Retiring a skill needs two checks first: transcripts show no runtime loads of it, and a grep of every repo that references it (sandbox skill lists included) comes back clean
