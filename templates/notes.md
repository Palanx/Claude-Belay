# Phase {{id}} — notes

<!-- Written by /implement-phase as its MANDATORY final step (P6), appended to
     by /validate-phase. This file is the only channel through which what
     implementation revealed reaches future sessions — an empty section is a
     protocol violation; `None` is a valid entry, blank is not. -->

## Outcome

<!-- /implement-phase --implemented also writes a `- base: <ref>` line here (the
     commit the phase started from, or `working tree`). /validate-phase reads it
     to build its diff, so committed work is still reviewable.
     A file changed mid-phase by someone other than this phase — the operator
     amending CLAUDE.md, say — gets a `- not-ours: <path> — <who, why>` line;
     /validate-phase subtracts it from the file set and names it in its report. -->

{{What exists now that didn't before: files created/changed, behavior added.
Written for a reader who saw none of the work happen.}}

## Deviations

<!-- Every place reality diverged from spec.md: what the spec said, what was
     done instead, why. Also: any file read/changed that the spec's pointers
     missed (that's a closure-test gap — name the missing pointer). -->

- {{deviation}} — or `None`

## Debt

<!-- Deliberate shortcuts with a known ceiling and their upgrade path. -->

- {{shortcut — ceiling — upgrade path}} — or `None`

## For later phases

<!-- Discoveries that change what a future phase should know. /expand-phase
     reads this section FIRST when expanding any phase that depends on this
     one. Name the phase id if you know it. -->

- {{finding → which phase cares}} — or `None`
