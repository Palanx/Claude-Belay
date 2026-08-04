---
description: Expand one phase-index row into a full spec, just-in-time, incorporating what earlier phases revealed
argument-hint: <phase-id>
---

# /expand-phase

**Purpose:** turn a shallow index entry into an implementable spec — immediately before
implementation, never earlier (P4). This is where knowledge from completed phases flows
into the plan: the spec is written *after* the phases it depends on have revealed reality.

**Arguments:** `$1` — the phase id (e.g. `03-rate-limit-store`). Required.

**Preconditions (check in order, stop on first failure):**
1. Phase `$1` exists in `docs/phases/PHASES.md` with status `pending`. (`expanded`/`in-progress` → it's already past this step; `done` → nothing to do; `blocked` → `/implement-phase` resumes it, not this command; `superseded by <ids>` → this cut was replaced, expand one of those ids instead.)
2. Every phase in its `depends` column has status `done`. If not, name the unmet dependencies *and what each one needs*, because the three ways to be un-`done` need different people: `pending`/`expanded`/`in-progress` needs the pipeline to reach it, `blocked: <reason>` needs the operator to answer that reason, and `superseded by <ids>` means this phase's `depends` is stale — it must be repointed at the replacement ids (a `/plan-feature` re-cut step, see that command). Expanding on top of unfinished dependencies produces a spec built on guesses, which is the exact failure P4 exists to prevent.

**Reads:** `CLAUDE.md`, `docs/phases/PHASES.md`, for each dependency: `docs/phases/<dep>/spec.md` and **especially** `notes.md` (deviations and debt recorded there are the ground truth the original plan lacked), `docs/constraints.md`, the `docs/index/` sections for the modules this phase touches, any ADRs the phase touches.
**Writes:** `docs/phases/$1/spec.md`, `docs/phases/PHASES.md` (status → `expanded`).

## Steps

1. **Absorb what changed.** Read the `notes.md` of every dependency phase. List every
   deviation and piece of debt that affects this phase. If a dependency's deviation
   invalidates this phase's one-line goal, STOP — that is a re-plan, not an expansion.
   Tell the operator which phases need re-cutting and why, and hand it to `/plan-feature`
   ("Re-cutting a phase whose premise died"): the wrong row gets `superseded by <ids>` and
   the replacements are appended. Do not fix it here by quietly writing a spec for a
   different goal than the row states — the index has to stay true.

2. **Scope the reading.** From the index, list the exact files this phase will read or
   modify. These become the spec's Context pointers.

3. **Write the spec** at `docs/phases/$1/spec.md` from `docs/templates/spec.md`:
   - **Goal** — the index one-liner, expanded to a paragraph of *observable behavior*.
   - **Context pointers** — every file a fresh session must read, with one line on why. This section is what makes the closure test (P5) pass.
   - **Plan** — ordered steps, each naming the files it touches.
   - **Acceptance criteria** — executable commands with expected outcomes (P3). Every criterion is a command a machine can run; "works correctly" is not a criterion. Include the toolchain's project-wide gates (test/lint/typecheck from `.claude/workflow/toolchain.json`) plus phase-specific commands.
   - **Out of scope** — what an eager implementer would wrongly include.

4. **Closure self-test (P5).** Re-read the spec pretending you know nothing but
   `CLAUDE.md` + this directory. Every file it tells you to touch: reachable from a
   Context pointer? Every term: defined in the spec or in a pointed-to file? Fix the spec
   until yes — a pointer you add now costs one line; the same knowledge missing at
   implementation time costs a blind repo search.

5. **Update status** in `docs/phases/PHASES.md`: `pending` → `expanded`.

## Mandatory final step (P6)

The spec and the status update ARE the disk outcome — verify both are written, then print
the spec's acceptance-criteria section verbatim so the operator sees exactly what "done"
will mean before implementation starts.

## Failure modes

- **Dependency notes reveal the plan is wrong** (step 1) → stop, report, hand back to `/plan-feature` scope. Do not "fix it in the spec" — the index must stay truthful.
- **Can't write an executable acceptance criterion for the goal** → the goal is not testable as cut; split the phase or sharpen the goal in PHASES.md first (that edit is allowed — the index stays shallow but must stay true).

## Handoff

`/implement-phase $1`.
