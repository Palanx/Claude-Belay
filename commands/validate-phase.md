---
description: Run a phase's acceptance gates and the closure test; flip status to done only on a clean pass
argument-hint: <phase-id>
---

# /validate-phase

**Purpose:** the deterministic gate at the end of a phase (P3). Generation may be
wrong; this step is where wrong is caught. Only a clean pass may set `done` — a phase
marked `done` is load-bearing for every phase that depends on it.

**Arguments:** `$1` — the phase id. Required.

**Preconditions:** `docs/phases/$1/spec.md` and `notes.md` exist; PHASES.md status is `in-progress`. Missing notes.md means `/implement-phase` skipped its mandatory final step — go back and write it first; validation validates the record as well as the code.

**Reads:** `docs/phases/$1/spec.md` + `notes.md`, `.claude/workflow/toolchain.json`, `docs/phases/PHASES.md`.
**Writes:** `docs/phases/$1/notes.md` (validation record appended), `docs/phases/PHASES.md` (status → `done` on pass only).

## Steps

1. **Acceptance criteria.** Run every command in the spec's Acceptance criteria section,
   in order, exactly as written. Record each command's pass/fail. They are executable by
   construction (P3) — if one turns out not to be runnable, that is itself a failure:
   fix the criterion in spec.md and note the fix in notes.md.

2. **Project-wide gates.** From `toolchain.json` run `test`, `lint`, `typecheck` (the
   project-wide forms — this catches breakage *outside* the phase's own files that the
   per-file edit hook cannot see). For any category listed in `gaps`, print the gap
   warning verbatim: an unchecked category is stated, never silent (P7).

3. **Boundary sweep.** For every source file this phase touched (from the spec plan and
   git status/diff), verify no line violates `.claude/workflow/boundaries.rules` — the
   same check the edit hook does, re-run as a batch in case any edit path bypassed it.
   **Corporate mode** (`.claude/workflow/corporate` exists): also verify no belay state
   path appears in `git status --porcelain` — no line matching
   `^\?\? (\.belay/|CLAUDE\.local\.md|docs/(product|adr|phases|index|security|templates)/|docs/(constraints|adoption-report)\.md|scripts/build-index\.sh)`
   (run `git status --porcelain -uall | grep -E '<that regex>'`; empty output = clean).
   A hit at an un-prefixed path means state was written to the old canonical location
   (move it under `.belay/`); a hit on `.belay/` or `CLAUDE.local.md` means the exclude
   block broke (re-run `install.sh --corporate`). Either way the validation FAILS until
   the status is clean of belay paths.

4. **Index freshness.** Run `scripts/build-index.sh --check`; if stale, run
   `scripts/build-index.sh` so the next phase plans against reality.

5. **Independent spec review.** Only once 1–4 are clean — never review code the cheap gates
   already reject. Dispatch ONE subagent with exactly three inputs: `CLAUDE.md`
   (`CLAUDE.local.md` in corporate mode), `docs/phases/$1/spec.md`, and the diff over step 3's
   file set (`git add -N` first, or files new in this phase diff as nothing). Nothing else —
   not `notes.md`, not the dependency notes, not your summary. Starve it deliberately: the
   instinct to be helpful destroys the property under test, because a reviewer who knows what
   you meant cannot see that the spec never said it. Ask for two verdicts only:
   - **contradicts** — a hunk conflicts with the spec's Goal, Plan, Acceptance criteria or
     Out of scope; cite spec line + hunk. Implementation failure: this gate FAILS, back to
     `/implement-phase $1` with the finding — the same loop as any gate failure.
   - **undecidable** — it cannot tell from the spec alone whether a hunk is right, and names
     what was missing. Spec failure, not code failure: feed it to step 6.
   Anything else — naming, structure, "I'd have done it differently" — is taste: append it to
   notes.md under `For later phases`, never block on it. The gate stays deterministic (P3)
   because the reviewer may only compare the diff to the spec, never to its own preferences.
   **No subagent available** (Cursor's `.cursor/commands/`, or any client without Task-style
   dispatch): have the operator run the same three-input review in a fresh session and paste
   the verdict, or record `skipped: no subagent` below. Skipping does not block `done`, but
   the closure test is then self-declared again — that is stated, never silent (P7).

6. **Closure test (P5).** Check the record, not just the code:
   - notes.md has all four sections (Outcome, Deviations, Debt, For later phases), none blank — `None` is an entry, blank is a violation.
   - Every file modified (git diff) is reachable from the spec's Context pointers or Plan. A file changed but never named in the spec = the phase escaped its scope: record it in notes.md Deviations and flag it in your report.
   - An `undecidable` finding from step 5 IS a missing pointer, found from outside your own head: closure test FAILED; record what the reviewer could not resolve in notes.md Deviations.
   - If notes.md Deviations reports missing pointers, mark the closure test FAILED even if the code passes — the *next* phase pays for it; the operator must know the cuts are drifting.

## Mandatory final step (P6)

Append to `docs/phases/$1/notes.md`:

```
## Validation — <date>
- criteria: <n> passed / <n> failed
- project gates: test <pass|fail|gap>, lint <...>, typecheck <...>
- boundary sweep: <clean|violations listed above>
- independent review: <clean | contradicts: <what> | undecidable: <what was missing> | skipped: no subagent>
- closure test: <pass|fail: reason>
- verdict: <done | returned to implementation>
```

On full pass: PHASES.md status → `done`. On any failure: status stays `in-progress`;
report exactly which gate failed with its output — that error text is the input for the
next `/implement-phase` iteration.

## Failure modes

- **Gate failure** → not an exception, the designed loop: hand the failing command + output to `/implement-phase $1`, which fixes and returns here. Expected convergence is 1–2 iterations because failures are machine-detectable (P3); if you're on iteration 3+, the spec is wrong — stop and say so.
- **Review verdicts split by consequence** — `contradicts` is a code bug (the loop above); `undecidable` is a spec bug, so the fix is a pointer in spec.md (with the Deviations entry that any spec amendment requires), never a code change to satisfy the reviewer.
- **Everything passes but the closure test** → phase is functionally done but the process is leaking scope; still record `done` ONLY after the deviations are written and flagged to the operator.

## Handoff

Pass → `/expand-phase <next>` (the next pending phase whose dependencies are all done).
Fail → `/implement-phase $1` with this validation report.
