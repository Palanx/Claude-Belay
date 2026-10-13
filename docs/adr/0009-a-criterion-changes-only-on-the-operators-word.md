# ADR-0009: A criterion changes what it asserts only on the operator's word

- Status: accepted
- Date: 2026-10-13

## Context

An acceptance criterion can run and fail because it is stale, not because the code is wrong:
it asserts something the spec, an ADR or a Deviations entry has since contradicted. A consuming
project hit this in round 1 of `/validate-phase`. That command routed every step-1 failure to
`/implement-phase`, whose failure modes let the agent amend the criterion itself with a note.
So the session that diagnosed the failure could not route it, and the session that could route
it needed nobody's agreement to turn a red criterion green by editing it. No later gate checks
that edit: the step-5 reviewer treats Deviations as authorised and never asks who authorised them.

## Decision

In both `/validate-phase` step 1 and `/implement-phase`'s failure modes, a criterion that runs
and fails is the code's failure by default. It is the criterion's only on recorded evidence the
agent can cite. Then the agent classifies it `criterion-side`, proposes the amendment and stops.
On the operator's yes it amends `spec.md` and writes the Deviations entry
`operator amended criterion: <old> → <new> — <evidence>`, and `/validate-phase` routes the
failure to the spec. With no answer, the failure stays the code's. A fix that only makes a
criterion runnable, with the same expected outcome, stays the agent's.

## Consequences

The agent can no longer close a failing criterion by rewriting it, and a criterion that really is
stale costs one operator answer instead of a round-trip through `/implement-phase`. Both commands
gain a stop, so a non-interactive session does not route a stale criterion to the spec at all. A
`criterion-side` call depends on how the agent reads the evidence. The operator's answer is the
only check on it, so the proposal has to cite that evidence, not argue it.

Rejected: let the agent amend with the evidence recorded in Deviations. Nothing questions a
Deviations entry after it is written, so the evidence is never checked.
Rejected: change only `/validate-phase`. The agent could still route through `/implement-phase`
and amend the criterion there.
