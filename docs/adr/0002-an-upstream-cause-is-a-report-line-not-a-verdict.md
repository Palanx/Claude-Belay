# ADR-0002: An upstream cause is a report line, not a review verdict

- Status: accepted
- Date: 2026-09-02

## Context

`/validate-phase` step 5 had two verdicts and the routing paragraph two destinations, both
inside the project: `contradicts` sent the finding to the code, `undecidable` to `spec.md`.
A defect whose cause was the package arrived as `undecidable`, got patched into that
project's spec prose, and the next project rediscovered it from zero. The reporting project
saw three of five blocking findings trace to package-owned files, so the category is not
rare.

The obvious fix is a third verdict, `upstream`, alongside the other two.

## Decision

Attribution is a line in the mandatory report block, not a verdict:

```
- upstream: <none | <package file(s)> — /belay-feedback recommended>
```

It never blocks; `done` is decided by the gates. The session applies the project-local fix
so the phase can close, names the file, and tells the operator to run `/belay-feedback`.

A third verdict is not merely unnecessary, it is unproducible. The step-5 reviewer is
starved on purpose — it sees `CLAUDE.md`, `spec.md` and the diff, and nothing else — so it
has no way to know whether a cause lives in a file the package installed. Attribution is
work for the session, which can read the manifest (see [ADR-0001](0001-ownership-is-decided-by-the-install-manifest.md)).

## Consequences

`README.md`'s "It returns two verdicts" stays true, and the starved-reviewer property
(P3) is untouched. The precedent is `workflow gap:`: stated, never silent, never blocking.

The remaining hole is human: the operator still has to run `/belay-feedback`. That is why
the trigger in both `CLAUDE.*.md` templates was widened at the same time — it said "misfires",
which a command behaving exactly as documented never resembles, and that is precisely the
defect class this route exists to catch.

Rejected — a third verdict: the reviewer cannot emit it, and a verdict that never blocks is
not a verdict. Rejected — blocking on it: the phase would be held hostage to a package fix
that lands on someone else's clock.
