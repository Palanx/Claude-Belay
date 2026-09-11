---
description: Execute one expanded phase against its spec; ends by writing notes and status to disk
argument-hint: <phase-id> [--implemented]
---

# /implement-phase

**Purpose:** do the work of exactly one phase, inside the enforcement rails, and leave a
truthful written record. The session that runs this command should need nothing beyond
`CLAUDE.md` and the phase directory (P5) — needing more is a spec bug worth recording.
Two ways in: the agent does the work (the steps below), or the operator already did it by
hand and this command records it (`--implemented`). The implementing changes; the record
never does.

**Arguments:** `$1` — the phase id. Required. `$2` — `--implemented`, optional: the code
already exists because a human wrote it, so skip implementation and go straight to the
record (see **Human-implemented mode** below). Cursor appends arguments as text instead of
substituting them, so read the id and the flag out of the prompt.

**Preconditions:**
- `docs/phases/$1/spec.md` exists and PHASES.md status is `expanded` (or `in-progress` — resuming after an interrupted session is normal; read `notes.md` first to see how far it got).
- If status is `pending`: stop, run `/expand-phase $1` first.
- If status is `blocked: <reason>`: this command is what resumes it. Read `notes.md` and the reason first, and confirm with the operator that the reason is actually resolved — the status says a *human decision* was owed. Once confirmed, set the status to `in-progress` (step 1) and record the resolution in `notes.md` under `## Deviations`. If the reason is still open, stop and repeat it; do not quietly implement past it.
- If status is `superseded by <ids>`: nothing to do here — this cut was replaced. Work on one of the ids named instead.

**Reads:** `CLAUDE.md`, `docs/phases/$1/spec.md` (+ `notes.md` if resuming), every file in the spec's Context pointers. Nothing else unless the spec proves insufficient — and if it does, that goes in the notes (see failure modes).
**Writes:** the source files named in the spec's Plan (none in `--implemented` mode), `docs/phases/$1/notes.md`, `docs/phases/PHASES.md` (status transitions).

## Steps

1. **Mark started.** Set status to `in-progress` in PHASES.md *before* touching source.
   If this session dies mid-phase, the table must show it (a compaction-surviving,
   machine-checkable trace of where work stopped).

2. **Read the spec fully**, then its Context pointers. Do not skim: the pointers were
   chosen so you don't have to search.

3. **Implement in the spec's Plan order.** After each step, run the nearest acceptance
   criterion that covers it — do not batch all verification to the end; a failure found
   three steps late costs three steps of rework (P3: converge in small loops).
   The post-edit and boundary hooks fire on every edit; when one reports a failure, fix
   it *now*, before the next step.

4. **On deviation** — the spec says X, reality demands Y:
   - Deviation stays inside this phase's scope (different function shape, extra helper, a file the spec missed) → do Y, and record it immediately in `notes.md` under `## Deviations`: what the spec said, what was done, why. If the deviation amends a statement in the spec, reconcile the other statements that assert the same fact in the same edit and say which you checked — see `/validate-phase`'s routing for why nothing else will.
   - Deviation changes this phase's goal or another phase's premise → STOP. Record the finding in `notes.md`, set status `blocked` with a one-line reason in PHASES.md, and report to the operator. That decision is a re-plan, not an implementation detail: it goes to `/plan-feature` ("Re-cutting a phase whose premise died"), which supersedes the affected rows and appends replacements. If the operator instead resolves the reason without a re-cut, this command resumes the phase (see preconditions).

5. **Generalise before fixing.** For every finding handed back by `/validate-phase`, decide
   first whether it is a bug or one instance of a property violated somewhere else. If it is
   an instance: name the property, enumerate every place it must hold, check them all, and fix
   them in this round. Record the enumeration in `notes.md` — what was checked, not only what
   was wrong — so the next round can see the scope instead of rediscovering it.
   This is the only step that can do it. Step 5's reviewer is starved to `CLAUDE.md`, one spec
   and one diff on purpose, so it can only ever report the instance it was shown; you hold the
   whole tree. Skipping it does not lose a round, it multiplies them: convergence in 1–2
   iterations is this loop's stated assumption and it holds only while a finding is a bug — an
   unenumerated property costs one round per instance, and the iteration-3+ escape fires long
   after that bill is paid.

6. **Run all acceptance criteria** from the spec, in order, once the plan is complete.
   Fix failures and re-run until clean or genuinely blocked.

## Human-implemented mode (`--implemented`)

The operator wrote this phase's code by hand. That is normal wherever the toolchain is not
reachable from a shell — Editor-bound test runners, GUI-authored assets, scenes and
prefabs — and it is why this mode exists: every gate in `/validate-phase` is already
agnostic about *who* wrote the code, but its precondition needs a `notes.md`, and this
command is the only thing that writes one. Without this branch a human-implemented phase
can never reach `done`, and the operator's only options are to lie (run the full command
over work that already exists) or abandon the row.

Preconditions are unchanged, including the rejection of `pending`: no spec means nothing
to validate the work against — run `/expand-phase $1` first, then this.

1. **Mark started** — step 1 above, unchanged.

2. **Do not touch source.** Steps 3–6 are skipped whole: do not re-run the plan, do not
   "fix" what the human wrote, do not run the acceptance criteria. Those belong to
   `/validate-phase`; running them here duplicates the gate and invites editing code until
   the gate is happy, which is the one thing this mode must not do.

3. **Interview the operator** for the four `notes.md` sections. Ask — never infer. You did
   not see the work happen, and a plausible Outcome reconstructed from the diff is exactly
   the fabrication P6 exists to prevent:
   - **Outcome** — what exists now that didn't before.
   - **Deviations** — the load-bearing one: what the spec said versus what was actually
     built, plus every file touched that the spec's Context pointers and Plan never named.
     The closure test will check that second half anyway; hearing it from the implementer
     is cheaper than the reviewer finding it.
   - **Debt** — shortcuts with a known ceiling and their upgrade path, including every
     `belay-debt:` comment left in the source.
   - **For later phases** — anything discovered that changes a future phase's premise.
   `None` is a valid answer to any of them; blank is not.

4. **Record the base ref.** Ask which commit the phase started from and write it as a
   `- base: <ref>` line under `## Outcome`; if the work is still uncommitted, write
   `- base: working tree`. This is not bookkeeping. `/validate-phase` derives its file set
   and its review diff from the working tree, so work the operator already committed
   presents an empty diff and would pass the boundary sweep, the independent review and
   the closure test having examined nothing.

5. **Say that no hook has run on this code.** The post-edit gate and the boundary check
   fire on edits made *through* the agent, so hand-written code arrives at validation
   ungated. `/validate-phase` steps 2 and 3 re-run both as a batch — that is the "in case
   any edit path bypassed it" case — but tell the operator plainly that validation is the
   first gate this code meets, not the second.

Then continue to the mandatory final step below: write `notes.md`, leave the status
`in-progress`, hand off to `/validate-phase $1`. Identical to the agent path, because from
here on nothing depends on who typed the code.

## Mandatory final step (P6) — never skip, even when blocked

Write `docs/phases/$1/notes.md` from `docs/templates/notes.md`:
- **Outcome** — what exists now that didn't before (files, behaviors).
- **Deviations** — every one, or explicitly `None`.
- **Debt** — shortcuts taken and their upgrade path. A deliberate ceiling left in the source is marked there with a `belay-debt:` comment naming the limit and what triggers the upgrade (`# belay-debt: global lock, per-account locks if throughput matters`); list those here too, so the ledger is one `grep -rn 'belay-debt:'` away.
- **For later phases** — anything discovered that changes what a future phase should know. `/expand-phase` reads this section first; it is the channel through which reality reaches the plan.

Update PHASES.md status: stays `in-progress` (validation flips it to `done`), or
`blocked: <reason>`. Then report: outcome summary, acceptance status, deviations.

## Failure modes

- **Spec insufficient** (needed files outside the Context pointers) → finish the phase if you can, but record the missing pointers in notes.md under Deviations — `/validate-phase` treats that as a closure-test failure to feed back into how the next phases get cut.
- **Acceptance criterion impossible to satisfy as written** → the criterion is wrong or the goal is: amend spec.md *with a note in notes.md saying so*, or block. Never delete a criterion silently.
- **`--implemented` and the operator can't answer a notes section** → do not invent it. Write what is known, leave the phase `in-progress`, and say which section is missing. A fabricated `notes.md` is worse than a missing one: the next phase reads it as ground truth.
- **Session dies mid-phase** → next session resumes from `in-progress` status + partial notes; that is the designed recovery path, which is why steps 1 and P6 are non-negotiable.

## Handoff

`/validate-phase $1`.
