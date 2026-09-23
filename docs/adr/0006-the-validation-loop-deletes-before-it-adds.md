# ADR-0006: The validation loop deletes before it adds

- Status: accepted
- Date: 2026-09-23

## Context

`/validate-phase` step 5's reviewer audits `spec.md` whole; step 6 exempts the spec from
reachability, not from review. Every spec-side finding (an `undecidable`, a closure-test
failure, a spec-side `contradicts`) was closed by amending `spec.md`, and in practice that meant
adding prose. Each added sentence became a permanent claim about the tree that later rounds
audit, and the only thing that ever took one out was `/expand-phase`, reached by failing three
times. So the loop had a growth term and no decay term. Measured in a consuming project, the
findings per round stopped falling while the code stayed frozen, and every one of them was
about a document the phase writes.

The defect was concentrated in one kind of sentence: the justification, not the conclusion. A
conclusion is usually verified before it is written. The "because" that follows it is written
from memory, is more specific, and goes false first. Deletion had already worked where it was
tried, but the command offered it as a permission buried inside the reconciliation rule,
while everything around it pushed toward adding.

## Decision

Deleting is the default remedy for a spec-side finding. If the finding is about a sentence,
delete the sentence or cut it back to its conclusion; add a sentence only when the finding is a
hunk the spec never covers and no existing sentence can carry the pointer. Reconciliation
covers the statements an amendment makes redundant as well as the ones it contradicts. Every
validation record carries `spec size` with its delta since the previous round, so growth shows
in `notes.md` in the round it happens. `templates/spec.md` asks for conclusions without their
reasoning, and reasoning worth keeping goes in `notes.md`, which the reviewer never reads.

## Consequences

A spec can now shrink without being re-expanded, and an operator can see the loop turning on
itself round by round instead of recovering it from the history. The costs are one more line in
the record and terser specs. A reader who wants the "why" has to open `notes.md`.

Rejected: only accounting for what an amendment makes redundant. That adds bookkeeping and
shrinks nothing, so it survives only as a clause of reconciliation. Rejected: bounding the
reviewer's findings to the round's diff. The phase diff runs against the base ref, a spec
written inside the phase is wholly in it, and a per-round bound needs a per-round ref the
workflow does not record, plus a fourth reviewer input that breaks step 5's contract.
Rejected: a size cap on the spec. Any number is arbitrary across projects, so the record makes
growth visible and leaves the call to the operator.
