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
`templates/spec.md`, `templates/notes.md`, `docs/adr/0005-*.md`, `docs/adr/0006-*.md`,
`tests/corporate-smoke.sh`

Eight commits change how the phase commands route findings: `fe6d9da`, `f449dd2`, `1502fdf`,
`da3af97`, `fd81d40`, `471dda6`, `6c68885`, `9a61992`. They close every open entry in
`~/.claude-belay/feedback/`. `tests/corporate-smoke.sh` covers them only as documentation
asserts: each one checks that a sentence exists, and each was seen to fail before its fix.
Only a live run shows whether a session actually behaves the way the prose says.

The consumer's fix to its `done` scaffold phase ran end to end on `6c68885` and passed
validation in one round. It confirmed these behaviours: `/plan-feature fix <done-id>: …`
scheduled one `depends: -` row and left the `done` row untouched (`da3af97`, `6c68885`),
the spec stated conclusions (`471dda6`), and the validation record carried `- findings:`
and `- spec size:` (`fd81d40`, `471dda6`). Nothing breaks today because every remaining
behaviour sits on a branch that a run passing in one round, with nothing to contradict, never
reaches. The risk is the first phase that reaches one of them.

Fix: observe each case below in a phase that produces it for its own reasons, and send
anything that diverges back through `/belay-feedback`. Never stage one in a consumer: an
edit made to test belay lands in that project's history for no reason of its own, and a
record line such as `- not-ours: …` proves the field exists, not that the behaviour behind
it works.
- Per-step status text (`fe6d9da`): `/implement-phase`'s final step updates the Plan's
  per-step status text and names what it flipped. Needs a spec that uses status markers.
  The scaffold fix's spec used none, so it took the "if the spec uses it" branch.
- Convergence (`fd81d40`): at iteration 3+, findings that fall every round do not escape,
  and the verdict reads `escape not taken: converging …`. Needs a phase that reaches a third
  round.
- `contradicts` routing (`f449dd2`, `471dda6`): a finding tagged `(code-side|spec-side)`
  with evidence, and a spec-side finding closed by deleting before adding. Needs a reviewer
  conflict, and the spec-side branch needs one where the spec is the stale side.
- `not-ours` (`1502fdf`): the declared paths leave the reviewer's file set and the record
  names them. Needs the operator to have edited a project-owned file (`CLAUDE.md`, an ADR)
  while the phase is open, for that project's own reasons.
- Spec-bound verdict (`9a61992`): a round whose every failure routes to the spec writes
  `verdict: returned to spec` and hands back a spec amendment, not `/implement-phase`.
  Needs a phase that fails only on the closure test, an `undecidable`, or a spec-side
  `contradicts`.
- Spec-bound convergence (`9a61992`): at iteration 3+, a spec-bound round whose findings
  fall every round writes `returned to spec (escape not taken: converging …)`. Needs a
  phase that reaches a third round on spec-side failures.

Delete each case once it has been observed, and the entry with the last one.
