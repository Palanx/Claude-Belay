# ADR-0007: The reviewer sees what was decided, and the loop ends on recurrence or at a cap

- Status: accepted
- Date: 2026-10-06

## Context

`/validate-phase` step 5 withheld all of `notes.md`. The spec template allows an amendment only
together with a Deviations entry, and the command prescribes an amendment as the fix for every
spec-side finding. So a reviewer asked to judge an amended spec asked for proof it could never see,
no criterion settled the question, and the question counted as a finding. In one consuming phase,
about a quarter of nine rounds' review findings were defects. The rest were true in the tree and
merely unstated in the spec, and they counted the same. The iteration-3+ escape compared raw counts.
Because each fresh reviewer samples a different gap, the counts oscillated with no finding ever
recurring, and the escape re-expanded, twice, a spec whose code passed every criterion.

## Decision

Give the step-5 reviewer a fourth input: the `## Deviations` section of `notes.md`, verbatim. The
rest of `notes.md` stays withheld, and each Deviations entry is one decision ("spec said X; Y
instead, because Z"), never an argument. Split the reviewer's doubts into `undecidable` (it can say
how a hunk could be wrong and the spec does not settle it), which counts, and `unstated` (nothing in
the spec makes the hunk doubtful), which is recorded on the review line and never counts. From the
third round against one spec, escape to `/expand-phase` when a finding key (`§<spec section>
<file>`) recurs from an earlier round. Without recurrence, stop at a firm round cap and hand the
operator the choice: close with the open findings recorded in Deviations, re-expand, or re-cut.
Close is offered only when steps 1–4 passed and no code-side `contradicts` is open. This amends
ADR-0006's "notes.md, which the reviewer never reads" to "notes.md outside Deviations".

## Consequences

An amendment the workflow prescribed no longer produces a finding nobody can settle, and a phase
can close without its spec restating its diff. The loop always ends. It ends on its own when a doubt
comes back, and otherwise by an explicit operator decision, instead of a re-expansion forced by
noise. The costs: the reviewer sees one more section, so Deviations has to stay terse. `done` can
now mean "operator-closed with open findings", and the verdict says so. The key is coarse (section
plus file), so it can read two different findings as recurrence, or miss one that moved files. That
is marked `belay-debt:` in the command.

Rejected: duplicate the amendment authorisation into the shipped `CLAUDE.md`. It is one more fact two
files share, and the reviewer still could not check that the entry exists.
Rejected: tell the reviewer not to judge authorisation. Unauthorised amendments would pass silently.
Rejected: drop findings whose only missing input is a withheld path. That judges what the reviewer
lacked, the same imprecise match settled findings already carry.
Rejected: pass `notes.md` whole. Prior rounds and reasoning end the starvation that makes the review
worth running.
Rejected: keep the falling-count trend as a relaxation. With fresh reviewers it is almost never met,
so it is a branch nobody exercises.
Rejected: let the cap close a phase whose code fails a gate. `done` is load-bearing for every phase
that depends on it.
