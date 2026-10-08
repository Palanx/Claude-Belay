---
paths:
  - commands/validate-phase.md
  - commands/implement-phase.md
  - commands/plan-feature.md
  - templates/spec.md
  - scripts/check.sh
  - hooks/lib/common.sh
  - hooks/lib/detect-toolchain.sh
  - templates/notes.md
  - commands/expand-phase.md
  - docs/adr/0005-a-defect-in-a-done-phase-gets-a-new-row.md
  - docs/adr/0006-the-validation-loop-deletes-before-it-adds.md
  - docs/adr/0007-the-reviewer-sees-what-was-decided-and-the-loop-ends-on-recurrence.md
---

# Tech debt

## Phase-workflow fixes shipped without a live run (reviewed 2026-10-08)

Files: `commands/validate-phase.md`, `commands/implement-phase.md`, `commands/plan-feature.md`,
`commands/expand-phase.md`, `templates/spec.md`, `templates/notes.md`, `docs/adr/0005-*.md`,
`docs/adr/0006-*.md`, `docs/adr/0007-*.md`

Sixteen commits change how the phase commands route findings: `fe6d9da`, `f449dd2`, `1502fdf`,
`da3af97`, `fd81d40`, `471dda6`, `6c68885`, `9a61992`, `cdcf9ff`, `e71f341`, `f87994c`,
`c4b6c01`, `722caf2`, `4fafb3c`, `7025e5b`, `e8202f7`. They close every entry in
`~/.claude-belay/feedback/` but the two 2026-10-08 ones on `/expand-phase`, still open.
`tests/corporate-smoke.sh` covers them only as documentation asserts: each one checks that a
sentence exists, and each was seen to fail before its fix.
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

A later phase on `073e35c` confirmed the escape cap (`4fafb3c`). It escaped once in round 3.
Its key recurred in the third round after the re-expansion, and the command offered close /
re-expand / re-cut instead of setting `pending` and named `commands/validate-phase.md` on
`upstream:`. The operator closed with the open findings recorded as Deviations. The same
phase diverged on two others, both reported through `/belay-feedback`: the re-expansion wrote an unenumerated "every
place the guide says…" Plan claim that `/expand-phase`'s closure self-test (`722caf2`) let
through and validation step 6 caught; and the gate carry-over (`7025e5b`) could not fire,
because the step-4 index rebuild changed the tree after the step-2 fingerprint and the guard
grep matched package-installed files.

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
- Gate carry-over (`7025e5b`, `e8202f7`): a round whose tree fingerprint matches the previous passing round
  records `(carried over)` and skips `scripts/check.sh`. Needs a project where no tracked
  non-Markdown file names `spec.md`, `notes.md` or `docs/phases`, and a round that only amends
  the spec.

Delete each case once it has been observed, and the entry with the last one.

## Prose documents audited sentence by sentence do not converge (reviewed 2026-10-07)

Files: `commands/validate-phase.md` (step 5, step 6 "A quantified claim owes its set"),
`commands/expand-phase.md` (step 6 Closure self-test), `templates/spec.md` (`## Plan` comment)

When a phase's diff includes a non-executable document for the operator (a bench or setup guide)
and the spec binds it with a sourcing rule ("every number, command and output the guide states is
in this list"), the step-5 reviewer audits it sentence by sentence. Each fresh reviewer reads the
rule more strictly than the last: claims outside the list, then paraphrases, then a list row's
exact wording. Almost every one of those findings is an `undecidable` with no settling criterion.
Closing the set (`722caf2`) bounded the claims, not the ways a sentence can paraphrase them. In
one consumer phase this took 11 rounds and 3 re-expansions, with every criterion and project gate
passing from the first re-expansion on. The spec grew from 17 KB to 31 KB, and the operator closed
the phase with one open finding whose content was correct. Running the review over finite sets
instead of hunk by hunk would not address this: the rule lives in the spec, so a spec-to-diff pass
audits it the same way.

Nothing loops today because `4fafb3c` bounds it: after one automatic re-expansion, a recurring key
goes to the operator, who can close with every code gate clean. The cost is a decision per
phase that ships such a document, after two or three wasted rounds.

Fix, cheapest first:
- `/expand-phase` refuses a sourcing rule over a prose document and narrows it to the commands and
  expected outputs an acceptance criterion executes or greps. It costs review of the prose itself:
  a wrong number in a sentence no criterion reads goes unchecked. That class once caught a real
  wrong figure an operator would have followed.
- The reviewer reports an `undecidable` with no settling criterion against a non-executable
  document as taste and does not count it. It needs a mechanical way to tell a document from code
  (extension, or a path the spec declares), and the same unchecked-prose cost.
- Make the guide executable: one criterion per command it lists. That is per-project tooling, and
  it often needs hardware a fresh clone does not have.

Where it was found: validation of a consumer phase, while measuring whether the review should run
over finite sets. That measurement excludes phases like this one: they test this problem, not that.

## Every test runs as one category, at every gate (reviewed 2026-10-08)

Files: `hooks/lib/detect-toolchain.sh`, `hooks/lib/common.sh`, `scripts/check.sh`,
`commands/validate-phase.md`, `commands/implement-phase.md`

`toolchain.json` has one `test` command per project, and every caller runs all of it: each Plan
step whose check calls the suite, every `/validate-phase` round's step 2, and CI. Nothing
distinguishes a fast unit test from an expensive tier, such as a mutation suite that regenerates
and runs every mutant on every call. One consumer has exactly that tier, and its phases call the
suite several times per step and once per validation round, so the cost multiplies with the round
count.

Nothing breaks: this costs time, not correctness. `7025e5b` removes the re-run when a round
changed nothing a gate can read. The owner of an expensive tier can make it incremental itself,
for example with a per-mutant cache keyed on content, without belay knowing.

Fix, cheapest first:
- Document the project-side pattern in the README: an expensive tier caches its own results
  keyed on its inputs and runs whole only in CI. No schema change. It relies on each project
  doing it right.
- Add a category for the expensive tier, with a rule for when it runs (once per validation
  round, never in a Plan step check). That is a schema change in three places: the emitter in
  `detect-toolchain.sh`, the accessor in `common.sh`, and every consumer (`check.sh`,
  `/validate-phase`, `/implement-phase`, CI). It also needs a definition of "expensive" that
  detection can apply, or the tier is always hand-declared in `toolchain.manual.json`.

Take the second only when a second project needs a separate tier. With one project, the first
fix and that project's own cache cover it.

