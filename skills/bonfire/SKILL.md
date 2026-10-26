---
name: bonfire
trigger: /bonfire
description: Test-first build loop (TDD) - write a failing test, SEE it fail for the right reason (red), write minimal code to pass (green), refactor only when green. One behavior at a time, vertical slices, tested through the public interface. For building a feature with >=2 behaviors or a bug fix that needs a regression guard. Writes the test AND the minimal impl, runs pytest each cycle. Python/pytest.
allowed-tools: Read, Write, Edit, Grep, Glob, AskUserQuestion, Bash(pytest:*), Bash(git log:*), Bash(git show:*), Bash(git diff:*)
---

# /bonfire - die, rest at the bonfire, venture again

The TDD loop *is* the Dark Souls loop: **red** (the flame's out - your test fails), **green** (🔥 bonfire lit - it passes), then venture on. You only **refactor at the bonfire** (when green). bonfire writes the failing test, proves it fails for the right reason, writes the minimal code to pass, and repeats - **one behavior at a time.**

**Why it exists.** "Write me some tests" gives you tests that pass *now* - but you never saw them **fail**, so you don't know they catch anything (a test with a broken fixture passes green and guards nothing). bonfire's whole value is the **red step**: a test proven to fail on the real behavior *before* the code exists is a test you can trust. Plus it stops the two classic failures - writing all tests up front against an imagined shape (crap tests), and gold-plating past what the current test needs.

**Honest ceiling - read this.** Red→green proves each test **catches its behavior** and the code is **minimal** - NOT that *untested* behaviors work, nor that the **design** is right (that's `/fathom`), nor that it's bug-free (that's `/aristarchus`/`/litmus`). You can't test everything; test the critical paths and **name what you skipped**. A lit bonfire means *this* test passes - not that the dark is gone.

## Usage
```
/bonfire <feature or bug to build, test-first>
```
bonfire writes BOTH the test and the minimal impl (you review). Python/pytest only.

## When to fire it (proportional - don't TDD a typo)
- **Use it:** a feature with **>=2 behaviors**, or a **bug fix** that deserves a regression guard (write the failing repro first).
- **Skip it:** a one-line/trivial change, pure exploration, config, or skill-authoring. Rigor scaled to the work.

## Phase 0 - Plan (proportional gate)
- Name the **public interface** the work needs (the function/method/endpoint callers use), and **list the behaviors** to test, **prioritized** - plus what you are **NOT** testing (you can't test everything).
- Read the repo's **`CLAUDE.md`** + the **existing tests** in the target area so test names + style match the project (not a separate glossary - use what the repo has).
- Identify deepening opportunities with **`/fathom`** (small interface, test *through* the seam, mock at seams not internals).
- **Gate (proportional):** for a multi-behavior **feature**, state the plan and **confirm with the user before writing tests** (`AskUserQuestion`, interface + behavior list). For a **single bug-fix-with-regression-test**, just proceed.

## Phase 1 - Tracer bullet (first behavior, end-to-end)
Write **ONE** test for the first/most-central behavior, through the **public interface**, asserting **observable behavior** (return value, persisted state, a call made/not made) - never internal/private state.
- **RED:** run just that test with the repo's test command - `pytest path::Test::test_name`, or the containerized form its `CLAUDE.md` documents (e.g. `docker exec <service> py.test path::test_name`). It **must fail** - and on the **asserted behavior**, shown in the output. If it fails on an **import/syntax/fixture error, that is a FAKE red** - fix the *test/setup*, not the code, until the failure is the real behavior. (A green you never earned through a real red is unverified.)
- **GREEN:** write the **minimal** code to pass *this* test - nothing for future tests (`occam`: no speculative features). Run → 🔥 green.

## Phase 2 - Incremental loop (one behavior at a time)
For each remaining behavior: **RED → GREEN**, one at a time.
- **Vertical slices only.** Writing the next test before the current one is green is an **invalid stop** - no "all tests, then all code" (horizontal slicing breeds tests of imagined behavior).
- Each test responds to what the last cycle taught you - that's why they're written one at a time, not in bulk.

## Phase 3 - Refactor (only at the bonfire)
**Only when all tests are green** (never while red): extract duplication, deepen modules (`/fathom`), apply judgment. **Re-run the tests after each refactor step** - they must stay green. A test that breaks on an internal refactor *with behavior unchanged* was testing implementation - rewrite it to the public interface.

## Output contract (show the work - a claim of "passes" without the red is invalid)
A bonfire run is complete only when:
1. The **plan** was stated: interface + prioritized behaviors + the **skip-list** (what's not tested).
2. **Each cycle shows: the test (behavior-named) → the RED run output (failing on the real behavior) → the minimal impl → the GREEN run output.** Red-then-green is shown, not asserted - "tests pass" without the prior red is not a valid bonfire cycle.
3. Behaviors were taken **one at a time** (no bulk-test-then-bulk-impl).
4. Refactor (if any) happened **green-only**, with tests re-run.
5. A **coverage line** names the behaviors tested vs deliberately skipped.

## Guard rails
- **Real red or it doesn't count.** A test must be seen failing **on its asserted behavior** before the impl exists; a failure from a setup/import error is a fake red - fix the test first. Skipping the red (test written after the code, or never run red) is the cardinal sin.
- **One behavior at a time.** Vertical tracer bullets, never horizontal (all tests up front = tests of imagined behavior).
- **Behavior through the public interface, never internals.** A test that breaks on a behavior-preserving refactor is testing implementation - rewrite it. Don't mock internal collaborators (mock at the seam - `/fathom`).
- **Minimal code to pass the current test.** No speculative features (`occam`). Refactor later, at the bonfire.
- **Refactor only when green.** Never restructure while a test is red.
- **Proportional.** Features/bug-fixes earn the full loop; trivial changes don't - don't make TDD into ceremony.
- **Writes code + tests, runs pytest; never commits/pushes.** You review and commit. (Run via the repo's documented test command / configured python per its `CLAUDE.md` - never bare `python` where a `.python-version` points at an uninstalled interpreter.)
- **Not correctness, not design.** Proves tests catch their behavior + minimal code; bugs in untested paths still ship (`/aristarchus`), design shape is `/fathom`'s job.
