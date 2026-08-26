# Phase {{id}} — {{title}}

<!-- Written by /expand-phase, immediately before implementation, never earlier
     (P4). Amendable during implementation ONLY together with a Deviations
     entry in notes.md.
     Closure test (P5): a session — or a person — reading CLAUDE.md + this
     directory + the files pointed to below must be able to complete the
     phase. If either would need anything else, add the pointer or re-cut the
     phase.
     This file is the plan for both readers. Do NOT generate a separate
     human-readable plan document beside it: /validate-phase judges the work
     against THIS spec, so a second document drifts from it and one of the two
     is lying. A rendering, if one is wanted anyway, is disposable,
     regenerable and never authoritative. -->

## Goal

{{The index one-liner expanded to a paragraph of observable behavior. What
exists/works after this phase that didn't before.}}

## Context pointers

<!-- Every file a fresh session must read, one line of why per file. This
     section is what makes the closure test pass. -->

- `{{path}}` — {{why: what it teaches or where the change lands}}
- `docs/phases/{{dep-id}}/notes.md` — {{what the dependency revealed that this phase uses}}

## Plan

<!-- Ordered. Each step names the files it touches AND the check that proves
     it landed: a runnable command, or an observable state where no command
     exists ("the prefab opens with no missing-script warning"). A step
     boundary with a passing check is a point where the repo is left working —
     which is what lets a human stop between any two steps, and what makes an
     agent converge in small loops (P3) instead of batching failure to the
     end. If a step has no check, it is two steps or it is not a step. -->

1. {{step}} — touches `{{path}}` — check: `{{command}}` → {{expected}}
2. {{step}} — touches `{{path}}` — check: {{observable state}}

## Acceptance criteria

<!-- EXECUTABLE commands with expected outcomes (P3). "Works correctly" is not
     a criterion. Include phase-specific checks AND the project-wide gates.
     /validate-phase runs these verbatim, in order. -->

```
{{command}}                                   # expect: {{observable outcome / exit 0}}
{{command}}                                   # expect: {{...}}
```

## Out of scope

<!-- What an eager implementer would wrongly include. Name the phase that owns
     each item, if one exists. -->

- {{excluded thing}} — belongs to {{phase id / "no phase; not wanted"}}
