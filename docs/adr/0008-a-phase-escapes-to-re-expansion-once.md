# ADR-0008: A phase escapes to re-expansion on its own once

- Status: accepted
- Date: 2026-10-07

## Context

ADR-0007 escapes to `/expand-phase` whenever a finding key recurs from the third round, and resets
the round count at every escape. Nothing counts the escapes themselves, so a phase whose
re-expansion does not close the doubt escapes again, and again: the only exit is a round in which
the reviewer finds nothing. In one consuming phase that took nine rounds and two escapes, with every
criterion and project gate passing since the first. Almost every finding was an `undecidable` with
no settling criterion, against a document for the operator that the Plan made the reviewer audit
sentence by sentence. The second re-expansion grew the spec by a third, and the same key came back
one round later.

## Decision

The first recurrence still escapes on its own. From then on, a recurring key in a phase whose
`notes.md` already holds an `escaped to /expand-phase` verdict, for any reason, goes to the round
cap instead: the operator chooses close (only with steps 1–4 clean), re-expand or re-cut, and the
`upstream:` line names `commands/validate-phase.md`. This amends ADR-0007's consequence "The loop
always ends": it ends after at most one automatic re-expansion, then by an operator decision.

## Consequences

The loop is bounded by construction, not by the reviewer running out of things to say. A second
re-expansion is still available; it is the operator's choice, not a route. A phase that two
re-expansions would have converged now costs one operator decision more. A recurrence after an
escape reaches the package as feedback, since it says the review produced doubts that a rewritten
spec did not close.

Rejected: a budget of N > 1 automatic escapes. The observed second escape changed nothing, and each
one costs a full re-expansion before anyone is asked.
Rejected: a round cap over the phase's lifetime. ADR-0007 already rejected it: it puts a spec written
one round ago at the cap.
Rejected: fix the coarse key first. The observed recurrences shared a cause, so the escapes were
right; what failed was re-expansion converging, which a finer key does not change.
Rejected: invert the review to passes over finite sets. The rule generating those findings lived in
the spec, and a spec-to-diff pass audits it the same way.
