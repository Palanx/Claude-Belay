# ADR-0004: A freshness check prefers a false stale to a false fresh

- Status: accepted
- Date: 2026-09-02

## Context

`scripts/build-index.sh --check` compared the index's stamp against `git rev-parse HEAD` and
nothing else. HEAD does not move during a phase, so the check short-circuited to "fresh"
for the entire window `/validate-phase` step 4 runs in — the step whose whole job is to stop
the next phase planning against a stale map. It reported `pass` over an index that had
drifted arbitrarily far from the files on disk.

The index is generated from the working tree (`git ls-files -co`), so the working tree, not
HEAD, is what it drifts from.

## Decision

`--check` compares the working tree as well as the stamp, and where the two possible errors
conflict, it errs toward stale. The asymmetry is the whole argument: **a false stale costs
one rebuild; a false fresh costs a phase planned against numbers that are wrong.** All three
callers (`/plan-feature`, `/validate-phase`, `/refresh-index`) respond to stale by
rebuilding and none of them block, so the cheap error really is cheap.

Dirty source files are compared by mtime against `_overview.md`, falling back to the line
count the index already records when mtime cannot see the edit. A path gone from disk is
asked of the index instead — a deletion stays in `git status` until it is committed, so
judging it by mtime would report stale forever, including right after the rebuild that
fixed it.

## Consequences

The check now fires during a phase, which is when it is useful and also when the rebuild is
paid — that raised the frequency of `build-index.sh`'s cost enough to be worth fixing
separately, and it was: the edge scan no longer spawns processes.

A stale verdict must always clear. That constraint killed the obvious one-line version and
shaped the deletion branch; it is the same shape as ADR-0003's "a stated gap is not a
failure" — a check the operator cannot turn green is a check they learn to ignore.

The residual ceiling is marked `belay-debt:` in the script: an edit landing in the same
clock tick as the build *and* leaving the line count unchanged still reads as fresh.

Rejected — "any dirty source file is stale": correct but never clears while the tree is
dirty, which is the whole phase. Rejected — hashing every source file's contents into a
second stamp line: closes the gap completely at the cost of reading every source file, in a
check that exists to avoid exactly that. Rejected — having `/validate-phase` rebuild
unconditionally: fixes one caller and leaves the script lying to the other two and to the
operator.
