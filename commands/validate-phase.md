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

**Reads:** `docs/phases/$1/spec.md` + `notes.md`, `.claude/workflow/toolchain.json` (via `scripts/check.sh`), `docs/phases/PHASES.md`.
**Writes:** `docs/phases/$1/notes.md` (validation record appended), `docs/phases/PHASES.md` (status → `done` on pass only).

**The phase's file set and diff** — defined once here, used by steps 3, 5 and 6. Default:
the working tree — `git status --porcelain` and `git diff` (run `git add -N` first so files
new in this phase diff as something rather than nothing) — unioned with the files the
spec's Plan names. **If `notes.md` records a `- base: <ref>` line** under Outcome (written
by `/implement-phase --implemented`; the literal `working tree` means the default applies),
use `git diff <ref>..HEAD` and `git diff --name-only <ref>..HEAD` instead, same union.
Never fall back to the Plan alone: the file the Plan never named is exactly what step 6
exists to catch, so a diff that cannot show it turns three gates into no-ops that report
`pass`.

## Steps

1. **Acceptance criteria.** Run every command in the spec's Acceptance criteria section,
   in order, exactly as written. Record each command's pass/fail. They are executable by
   construction (P3) — if one turns out not to be runnable, that is itself a failure:
   fix the criterion in spec.md and note the fix in notes.md.

2. **Project-wide gates.** Run `scripts/check.sh` and record its output and exit code.
   It runs `test`, `lint` and `typecheck` in their project-wide forms — this catches
   breakage *outside* the phase's own files that the per-file edit gate cannot see. Do
   not run those commands yourself: the script is the same one a human and CI call, and
   running them by hand is how the two paths drift apart. For any category the script
   reports as a `workflow gap:`, print that warning verbatim in the report — an unchecked
   category is stated, never silent (P7).

3. **Boundary sweep.** Run `scripts/check.sh --files <every source file in the phase's
   file set>` (the file set is defined above). This is the same gate the edit path runs,
   re-run as a batch in case any edit bypassed it.
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
   (`CLAUDE.local.md` in corporate mode), `docs/phases/$1/spec.md`, and the phase's diff
   restricted to step 3's file set (defined above — that definition is what makes this work
   on code the operator already committed). Nothing else —
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
   - **Exempt: the files this workflow writes itself** — `docs/phases/$1/spec.md`, `docs/phases/$1/notes.md`, `docs/phases/PHASES.md` and `docs/index/`. Every command here amends them by design, and this one prescribes a `spec.md` amendment as the fix for an `undecidable` verdict — so a phase that goes round the loop once carries its own spec in its diff from then on. Counting those as escaped scope fails the phase for obeying its own instructions. Drift is a source file the spec never named.
   - Every *other* file in the phase's file set is reachable from the spec's Context pointers or Plan. A file changed but never named in the spec = the phase escaped its scope: closure test FAILED. Record it in notes.md Deviations, flag it in your report, and name it in the spec's Plan before re-running — the spec has to describe the change that actually happened.
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
next iteration. Where that iteration happens depends on what failed: steps 1–4 and a
`contradicts` verdict go back to `/implement-phase $1` (the code is wrong); a closure-test
failure or an `undecidable` verdict is fixed in `spec.md` plus a notes.md Deviations entry
and re-validated from here (the record is wrong). Say which of the two you are handing
back, or the next session guesses.

## Failure modes

- **Gate failure** → not an exception, the designed loop: hand the failing command + output to `/implement-phase $1`, which fixes and returns here. Expected convergence is 1–2 iterations because failures are machine-detectable (P3); if you're on iteration 3+, the spec is wrong — stop and say so, and route it: a wrong *spec* is re-expanded (status back to `pending`, `/expand-phase $1`), a wrong *cut* is re-planned (`/plan-feature`, which supersedes the row). Iterating a fourth time against a spec nobody believes is the failure this escape exists to stop.
- **The code was written by a human** (`/implement-phase --implemented`) → nothing here changes: every gate above judges the code and the record, not the author. If anything the independent review is *stronger*, because the reviewer cannot be told what the human meant — but it is also the first gate this code meets at all, since the edit-time hooks only see edits made through the agent. Read step 2's and step 3's output as new information, not as a re-check.
- **Review verdicts split by consequence** — `contradicts` is a code bug (the loop above); `undecidable` is a spec bug, so the fix is a pointer in spec.md (with the Deviations entry that any spec amendment requires), never a code change to satisfy the reviewer.
- **Everything passes but the closure test** → still a failure: status stays `in-progress`. The code may well be right; the *record* isn't, and the next phase is what pays for that. It is also the cheapest failure here to clear, so clear it rather than arguing with it: name the stray file in the spec's Plan, or add the pointer the reviewer could not resolve, then write the Deviations entry that any spec amendment requires and re-run. A phase marked `done` asserts that a cold session can rebuild its context from the spec — that is exactly what the closure test measures, so `done` on a failed closure test would make the word mean nothing.

## Handoff

Pass → `/expand-phase <next>` (the next pending phase whose dependencies are all done).
Fail → `/implement-phase $1` with this validation report.
