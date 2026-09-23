# ADR-0005: A defect in a done phase's code gets a new row, not a note

- Status: accepted
- Date: 2026-09-22

## Context

`/implement-phase` judges a defect the session finds by the current phase's Goal: if the Goal
is left false, it is fixed this round; if the Goal survives, it goes to `For later phases`
with an owner. That section is a channel into planning, not a work item — `/expand-phase`
reads it only when it expands a phase that depends on this one. A defect in code that a
`done` phase already delivered usually has no later row that will touch it, so the entry is
written, nothing reads it back, and the fix is never scheduled. The deferral is legitimate;
writing it where no trigger reads it is not.

## Decision

Write the deferral as `needs a row: <done-id> — <what is wrong>` in `For later phases` and
tell the operator to run `/plan-feature`. `/plan-feature` ("Scheduling a fix to a phase
already done") appends one row to the same feature section: the next id, goal
`fix <done-id>: <what is wrong>`, `depends: -`, status `pending`. It does not touch the
`done` row. The only mechanism in the workflow that produces work somebody runs is a row,
so the defect becomes one.

## Consequences

A defect found at a phase boundary now ends up as work somebody runs, and the record of the
original cut stays accurate. The cost is one `/plan-feature` run the operator has to start;
`/implement-phase` does not append rows itself, because `/plan-feature`'s final step is what
validates ids and `depends` edges.

Rejected — reopening the `done` row: only `/validate-phase` writes `done`, and every row that
depends on it treats that status as a guarantee. Rejected — `superseded by`: that records
the cut as wrong, and here the cut was right and its code is wrong. Rejected — leaving it in
`For later phases`: nothing reads that section unless a dependent phase expands.
