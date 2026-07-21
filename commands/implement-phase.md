---
description: Execute one expanded phase against its spec; ends by writing notes and status to disk
argument-hint: <phase-id>
---

# /implement-phase

**Purpose:** do the work of exactly one phase, inside the enforcement rails, and leave a
truthful written record. The session that runs this command should need nothing beyond
`CLAUDE.md` and the phase directory (P5) — needing more is a spec bug worth recording.

**Arguments:** `$1` — the phase id. Required.

**Preconditions:**
- `docs/phases/$1/spec.md` exists and PHASES.md status is `expanded` (or `in-progress` — resuming after an interrupted session is normal; read `notes.md` first to see how far it got).
- If status is `pending`: stop, run `/expand-phase $1` first.

**Reads:** `CLAUDE.md`, `docs/phases/$1/spec.md` (+ `notes.md` if resuming), every file in the spec's Context pointers. Nothing else unless the spec proves insufficient — and if it does, that goes in the notes (see failure modes).
**Writes:** the source files named in the spec's Plan, `docs/phases/$1/notes.md`, `docs/phases/PHASES.md` (status transitions).

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
   - Deviation stays inside this phase's scope (different function shape, extra helper, a file the spec missed) → do Y, and record it immediately in `notes.md` under `## Deviations`: what the spec said, what was done, why.
   - Deviation changes this phase's goal or another phase's premise → STOP. Record the finding in `notes.md`, set status `blocked` with a one-line reason in PHASES.md, and report to the operator. That decision is a re-plan, not an implementation detail.

5. **Run all acceptance criteria** from the spec, in order, once the plan is complete.
   Fix failures and re-run until clean or genuinely blocked.

## Mandatory final step (P6) — never skip, even when blocked

Write `docs/phases/$1/notes.md` from `docs/templates/notes.md`:
- **Outcome** — what exists now that didn't before (files, behaviors).
- **Deviations** — every one, or explicitly `None`.
- **Debt** — shortcuts taken and their upgrade path (include any `ponytail:`-style deliberate ceilings).
- **For later phases** — anything discovered that changes what a future phase should know. `/expand-phase` reads this section first; it is the channel through which reality reaches the plan.

Update PHASES.md status: stays `in-progress` (validation flips it to `done`), or
`blocked: <reason>`. Then report: outcome summary, acceptance status, deviations.

## Failure modes

- **Spec insufficient** (needed files outside the Context pointers) → finish the phase if you can, but record the missing pointers in notes.md under Deviations — `/validate-phase` treats that as a closure-test failure to feed back into how the next phases get cut.
- **Acceptance criterion impossible to satisfy as written** → the criterion is wrong or the goal is: amend spec.md *with a note in notes.md saying so*, or block. Never delete a criterion silently.
- **Session dies mid-phase** → next session resumes from `in-progress` status + partial notes; that is the designed recovery path, which is why steps 1 and P6 are non-negotiable.

## Handoff

`/validate-phase $1`.
