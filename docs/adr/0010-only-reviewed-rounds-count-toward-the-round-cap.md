# ADR-0010: Only reviewed rounds count toward the round cap

- Status: accepted
- Date: 2026-10-13

## Context

ADR-0007 escapes or stops at a firm cap "from the third round against one spec". The reason for
the cap is reviewer noise: each fresh step-5 reviewer samples a different true gap, so finding
counts oscillate without converging. A consuming project reached the cap after only two reviews,
because its first round failed on a step-1 criterion. That round never reached step 5 (it runs
only once steps 1–4 are clean), yet it counted.

## Decision

In `/validate-phase`, a round counts toward the iteration-3 escape and the round cap only if its
independent review ran. A `## Validation` section whose `- independent review:` line reads
`not run` is skipped, and the record template gains the value `not run: steps 1–4 failed` so
the line always says so. "Third round" in ADR-0007 and ADR-0008 means the third reviewed round
against one spec. The reset at an `escaped to /expand-phase` verdict is unchanged.

## Consequences

The cap fires only on the evidence it was designed for. A phase whose early rounds fail on cheap
gates gets the same three reviews as one that passes them at once. Records written before the
`not run` value existed are read by the prefix `not run`, so an improvised `not run — …` line
also counts as unreviewed. The cost is that a phase can now run more than three rounds in total
before the cap. Rounds that fail on steps 1–4 are machine-detectable and converge without a cap
(P3), and code that fails a gate can never be closed at the cap anyway.

Rejected: keep counting every round. That puts a phase at the cap on reviewer noise it never
sampled.
Rejected: count only rounds whose verdict is `returned to spec`. A mixed round had a review, and
its findings are exactly what recurrence compares.
