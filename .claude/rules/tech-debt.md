---
paths:
  - commands/validate-phase.md
  - commands/implement-phase.md
  - commands/plan-feature.md
  - templates/spec.md
  - templates/notes.md
  - commands/expand-phase.md
  - docs/adr/0005-a-defect-in-a-done-phase-gets-a-new-row.md
  - docs/adr/0006-the-validation-loop-deletes-before-it-adds.md
  - docs/adr/0007-the-reviewer-sees-what-was-decided-and-the-loop-ends-on-recurrence.md
---

# Tech debt

## Phase-workflow fixes shipped without a live run (reviewed 2026-10-01)

Files: `commands/validate-phase.md`, `commands/implement-phase.md`, `commands/plan-feature.md`,
`commands/expand-phase.md`, `templates/spec.md`, `templates/notes.md`, `docs/adr/0005-*.md`,
`docs/adr/0006-*.md`, `docs/adr/0007-*.md`

Thirteen commits change how the phase commands route findings: `fe6d9da`, `f449dd2`, `1502fdf`,
`da3af97`, `fd81d40`, `471dda6`, `6c68885`, `9a61992`, `cdcf9ff`, `e71f341`, `f87994c`,
`c4b6c01`, `722caf2`. They close every open entry in
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

Later phases on `2c25f10` confirmed two more. Reviewer conflicts were tagged
`code-side` or `spec-side` with evidence and routed accordingly, and a spec-side one was
closed by deleting sentences before adding pointers (`f449dd2`, `471dda6`). Rounds that
failed only on spec-bound routes wrote `returned to spec`, and a mixed round wrote
`returned to implementation` (`9a61992`). One of those phases reached a third round twice.
Both times its counts did not fall, so the escape fired and the count reset at the escape
verdict, as written.

A later phase on `c4b6c01` confirmed three more. The reviewer used the Deviations as evidence
and never questioned whether an amendment was authorised (`cdcf9ff`). It returned `unstated`
items (7 and 10), which the review line carried and `- findings:` did not count (`e71f341`).
In round 3 a key repeated from round 2, and the escape set the status to `pending` itself
(`f87994c`). The two findings behind that key differed in detail but shared a cause, so the
escape was right. Even so, the coarse key had already collided in round 2, where it had no
effect. That `belay-debt:` in `/validate-phase` is real; take its upgrade path once a
collision joins two findings with no shared cause.

Fix: observe each case below in a phase that produces it for its own reasons, and send
anything that diverges back through `/belay-feedback`. Never stage one in a consumer: an
edit made to test belay lands in that project's history for no reason of its own, and a
record line such as `- not-ours: …` proves the field exists, not that the behaviour behind
it works.
- Per-step status text (`fe6d9da`): `/implement-phase`'s final step updates the Plan's
  per-step status text and names what it flipped. Needs a spec that uses status markers.
  The scaffold fix's spec used none, so it took the "if the spec uses it" branch.
- `not-ours` (`1502fdf`): the declared paths leave the reviewer's file set and the record
  names them. Needs the operator to have edited a project-owned file (`CLAUDE.md`, an ADR)
  while the phase is open, for that project's own reasons.
- Round cap (`f87994c`, `c4b6c01`): with no recurring key, round 3 stops and offers
  close / re-expand / re-cut, close only with steps 1–4 clean, and names
  `commands/validate-phase.md` on the `upstream:` line. Needs a phase that reaches a third
  round with no key repeated.
- Quantified Plan claim (`722caf2`): `/expand-phase`'s closure self-test makes a Plan step that
  quantifies over an unenumerated set ("every number the doc states has a source") name its
  members, or cuts it back, before validation sees it. Needs a re-expansion of a spec that
  carries such a step.

Delete each case once it has been observed, and the entry with the last one.
