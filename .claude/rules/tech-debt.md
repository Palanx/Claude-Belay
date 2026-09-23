---
paths:
  - commands/validate-phase.md
  - commands/implement-phase.md
  - commands/plan-feature.md
  - templates/spec.md
  - templates/notes.md
  - docs/adr/0005-a-defect-in-a-done-phase-gets-a-new-row.md
  - docs/adr/0006-the-validation-loop-deletes-before-it-adds.md
---

# Tech debt

## Phase-workflow fixes shipped without a live run (reviewed 2026-09-23)

Files: `commands/validate-phase.md`, `commands/implement-phase.md`, `commands/plan-feature.md`,
`templates/spec.md`, `templates/notes.md`, `docs/adr/0005-*.md`, `docs/adr/0006-*.md`

Seven commits change how the phase commands route findings: `fe6d9da`, `f449dd2`, `1502fdf`,
`da3af97`, `fd81d40`, `471dda6`, `6c68885`. They close every open entry in
`~/.claude-belay/feedback/`. `tests/corporate-smoke.sh` covers them only as documentation
asserts: each one checks that a sentence exists, and each was seen to fail before its fix.
No agent session has run these commands since the change, so nobody knows yet whether a
session actually behaves the way the prose says.

Nothing breaks today because the one consuming install (see `scripts/installs-stale.sh`) is
on `6c68885` and has not started a phase since updating. The risk starts with its next
`/plan-feature`, `/expand-phase`, `/implement-phase` or `/validate-phase` run.

Fix: run the consumer's scheduled fix to its `done` scaffold phase end to end, and check
the behaviours below that its work actually exercises. That run is free because the work is
already owed, and it only covers these rows: the fix edits rule text, so it gives a reviewer
nothing to contradict. Anything that diverges goes back through `/belay-feedback`.

| Step in the consumer | Expected | Commit |
|---|---|---|
| `/plan-feature fix <done-id>: …` | Skips straight to "Scheduling a fix to a phase already done": no interview, no blurb, one `fix <done-id>: …` row with `depends: -` and `pending`, and the `done` row untouched | `da3af97`, `6c68885` |
| `/expand-phase <id>` | The spec states conclusions without their "because"; reasoning goes to `notes.md` | `471dda6` |
| `/implement-phase <id>` | The final step updates the Plan's per-step status text (if the spec uses it) and names what it flipped | `fe6d9da` |
| `/validate-phase <id>` | The record carries `- findings: <n>` and `- spec size: …` | `fd81d40`, `471dda6` |
| Iteration 3+, if reached | Findings that fall every round do not escape: the verdict reads `escape not taken: converging …` | `fd81d40` |

Observe these only when a phase with real code produces them. Never stage them in a
consumer: an edit made to test belay lands in that project's history for no reason of its
own, and a record line such as `- not-ours: …` proves the field exists, not that the
behaviour behind it works.
- `contradicts` routing (`f449dd2`, `471dda6`): a finding tagged `(code-side|spec-side)`
  with evidence, and a spec-side finding closed by deleting before adding. Needs a reviewer
  conflict, and the spec-side branch needs one where the spec is the stale side.
- `not-ours` (`1502fdf`): the declared paths leave the reviewer's file set and the record
  names them. Needs the operator to have edited a project-owned file (`CLAUDE.md`, an ADR)
  while the phase is open, for that project's own reasons.

Delete this entry once the table has been observed and each case above has shown up once.
