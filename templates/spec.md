# Phase {{id}} — {{title}}

<!-- Written by /expand-phase, immediately before implementation, never earlier
     (P4). Amendable during implementation ONLY together with a Deviations
     entry in notes.md.
     Closure test (P5): a session reading CLAUDE.md + this directory + the
     files pointed to below must be able to complete the phase. If it would
     need anything else, add the pointer or re-cut the phase. -->

## Goal

{{The index one-liner expanded to a paragraph of observable behavior. What
exists/works after this phase that didn't before.}}

## Context pointers

<!-- Every file a fresh session must read, one line of why per file. This
     section is what makes the closure test pass. -->

- `{{path}}` — {{why: what it teaches or where the change lands}}
- `docs/phases/{{dep-id}}/notes.md` — {{what the dependency revealed that this phase uses}}

## Plan

<!-- Ordered. Each step names the files it touches. -->

1. {{step}} — touches `{{path}}`
2. {{step}} — touches `{{path}}`

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
