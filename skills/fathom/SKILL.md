---
name: fathom
trigger: /fathom
description: Shared vocabulary + lens for designing deep modules - a lot of behavior behind a small interface, at a clean seam, testable through that interface. Invoke on a module/file to get a deep-vs-shallow verdict + concrete deepening suggestions, or with --twice to design an interface several ways and compare. Other skills (aristarchus, forge) cite this for consistent design language. Read-only.
allowed-tools: Read, Grep, Glob, Bash(grep:*), Bash(git log:*), Bash(git show:*), Bash(git diff:*), Agent
---

# /fathom - design (and judge) deep modules

A **deep module** = a lot of behavior behind a **small interface**, at a clean **seam**, testable **through** that interface. Use this language and these principles wherever code is designed, reviewed, or restructured. Aim: leverage for callers, locality for maintainers, testability for everyone. (Ousterhout, *A Philosophy of Software Design*; seams from Michael Feathers.)

**What this is.** Two things: (1) a **shared vocabulary** other skills cite for consistent design language, and (2) an **actionable lens** - point it at code and it returns a deep/shallow verdict + deepening suggestions, or `--twice` to generate and compare interface designs. It judges *design shape*, not correctness or diff minimality (those are `occam` for local work, `aristarchus` for a PR, `darkmoon --claims` for one claim).

## Usage
```
/fathom <module|file|symbol>   # judge it: deep or shallow? + how to deepen
/fathom --twice <design question>   # design the interface 2-3 radically different ways, compare on depth/locality/seam
```

## Glossary (use these exact terms - consistency is the point)
- **Module** - anything with an interface + an implementation (function, class, package, service-slice). Scale-agnostic. *Avoid* "component/unit/service."
- **Interface** - *everything a caller must know to use it correctly*: signature **+** invariants, ordering, error modes, required config, perf characteristics. *Avoid* "API/signature" (too narrow - type surface only).
- **Implementation** - the body inside.
- **Depth** - leverage at the interface: behavior a caller/test gets per unit of interface they must learn. **Deep** = much behavior, small interface. **Shallow** = interface nearly as complex as the implementation.
- **Seam** *(Feathers)* - a place you can alter behavior *without editing there*; the location the interface lives. Where to put it is its own decision. *Avoid* "boundary" (overloaded by DDD).
- **Adapter** - a concrete thing satisfying an interface at a seam (a real DB repo; an in-memory fake). Names a *role*, not substance.
- **Leverage** - callers' payoff from depth (capability per unit learned). **Locality** - maintainers' payoff (change/bugs/knowledge concentrate in one place).

## The principles (the teeth)
- **The deletion test.** Imagine deleting the module. Complexity *vanishes* → it was a pass-through (shallow; cut or merge it). Complexity *reappears across N callers* → it earned its keep (deep).
- **The interface is the test surface.** Callers and tests cross the *same* seam. If you need to test *past* the interface, the module is the wrong shape.
- **One adapter = a hypothetical seam; two = a real one.** Don't introduce a seam (or an interface, or a "strategy") unless something actually varies across it. (Sibling of `occam` - don't build the abstraction one caller needs.)
- **Depth is a property of the INTERFACE, not the implementation.** A deep module can be internally many small swappable parts - they just aren't in its interface. Depth ≠ implementation line-count (that rewards padding); depth = leverage.

## Designing for testability (a deep interface makes tests natural)
- **Accept dependencies, don't create them** (`processOrder(order, gateway)` not `new StripeGateway()` inside) - so tests pass a fake at the seam.
- **Return results, don't mutate** (`calculateDiscount(cart) -> Discount` not `applyDiscount(cart): void`) - pure is trivially testable.
- **Small surface** - fewer methods + simpler params = fewer tests, simpler setup.

## Step 1 - Judge the target (default mode)
Read the module/file. For each module in scope, assess:
1. **Deep or shallow?** Size of the interface (everything a caller must know) vs behavior behind it. Show the count: "interface = N methods + M load-bearing facts; implementation = <what it hides>."
2. **Deletion test** - state what happens if deleted (vanishes → shallow; reappears across callers → deep). Name the callers.
3. **Seam check** - is there a seam here, and does anything actually vary across it (≥2 adapters)? A 1-adapter seam is speculative - flag it.
4. **Testability** - can it be tested through its interface (deps injected, results returned)? If you'd have to reach past the interface, say so.

## Step 2 - Suggest deepening (only where it pays)
For each shallow module, propose the **deeper shape**: the smaller interface + what moves behind it. Be concrete (the method list, the params dropped). **Don't deepen what's already deep, and don't add a seam with one adapter** - over-abstraction is the opposite failure (defer to `occam`'s instinct). If everything is already deep, say "already deep ✓" - don't manufacture refactors.

## `--twice` - design the interface several ways, then compare
For a *design question* ("how should the notification service's interface look?"), spin up **parallel independent `Agent`s** - each briefed **read-only: return an interface design proposal, do NOT edit/write code** - each designing the interface a **radically different** way (e.g. one deep facade; one explicit-steps; one data-oriented). Then compare them on **depth · locality · seam placement · testability** and recommend - grafting the best of the runners-up. (This is design-it-twice; it overlaps `dialectic` but is specialized for *interface* design with the deep-module criteria.) If you can't spawn `Agent`s (nested), say so and design the alternatives inline (less independent).

## Output contract
- **Default:** per module in scope - **deep/shallow verdict** with the interface-vs-behavior evidence, the **deletion-test** result, a **seam/adapter** count, and (for shallow ones) a **concrete deeper interface**. Lead with the shallowest / highest-leverage fix. If all deep → "already deep ✓," stop.
- **`--twice`:** ≥2 distinct interface designs, a **comparison on depth/locality/seam/testability**, and a recommendation + the flip-condition.
- Use the **glossary terms exactly**; that consistency is what lets other skills build on this.

## Guard rails
- **A lens, not a law.** Deep/shallow is a design heuristic - judgment, not mechanical proof. State it as such; don't dress an opinion as a verdict (that's the `darkmoon` line).
- **Don't over-abstract.** "One adapter = hypothetical seam" + the deletion test exist to STOP speculative interfaces. Deepening a shallow module is good; adding a seam nothing varies across is the mirror-image mistake. When unsure, fewer seams.
- **Not correctness, not minimality.** Shape only. Bugs and diff minimality → `occam` (local work) / `aristarchus` (a PR) / `darkmoon --claims` (one claim).
- **Read-only.** Reads and judges; never edits, commits, or restructures the code itself. It proposes; the human applies.
