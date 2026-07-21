---
description: Turn a feature request into a scoped plan and phase index entries, consistent with recorded constraints and ADRs
argument-hint: <feature description>
---

# /plan-feature

**Purpose:** convert a feature request into new rows in the phase index. Works
identically on bootstrapped and adopted projects (P8). Produces the *index* only —
one-line goals, dependencies, coarse acceptance — never deep specs (P4).

**Arguments:** `$ARGUMENTS` — the feature description. Required; if empty, ask for it and stop.

**Preconditions:**
- Project state exists: `docs/constraints.md` and `docs/phases/PHASES.md` present. If not, stop and name the missing entry point (`/bootstrap-project` or `/adopt-project`).
- No phase for a *different* feature is `in-progress` (check the PHASES.md table). If one is, warn the operator — interleaving features is allowed but must be their explicit call.

**Reads:** `CLAUDE.md`, `docs/constraints.md`, `docs/adr/` (titles + status lines of all; full text of any ADR the feature might touch), `docs/index/_overview.md` (plus the specific module sections the feature will touch), `docs/phases/PHASES.md`.
**Writes:** `docs/phases/PHASES.md` (appended feature section + rows).

## Steps

1. **Freshness.** Run `scripts/build-index.sh --check`. If stale, run
   `scripts/build-index.sh` first — planning against a stale index produces phases that
   name files that don't exist.

2. **Understand the request.** Restate the feature in two sentences: what changes for the
   user, and what explicitly does not (scope edge). If the request is ambiguous on
   something that changes the phase structure, ask the operator now, not during
   implementation.

3. **Conflict detection.** Read every ADR whose topic the feature touches, plus the
   constraints. If the feature contradicts a recorded decision (e.g. it wants an event
   queue and ADR-0003 says "no async infrastructure"), STOP and surface the conflict:
   quote the ADR, state the contradiction, and give the operator the two options —
   change the feature, or write a superseding ADR first. Never plan around a recorded
   decision silently; that is how ADRs die.

4. **Locate the change.** From the index, list the modules the feature touches and the
   dependency edges between them. This tells you the phase *order*: a phase can only
   depend on information that exists when it starts.

5. **Cut phases.** Slice the feature so that each phase passes the closure test (P5): a
   session reading only `CLAUDE.md` + that phase's directory must be able to complete
   it. Practical size: one phase = one coherent change to 1–3 modules, completable in a
   single session. If a phase needs "and also remember the thing from phase 2", the cut
   is wrong — either merge them or move the shared knowledge into the spec at expansion
   time via a pointer.

6. **Write the index rows.** Append to `docs/phases/PHASES.md` under a feature heading:
   next sequential ids (`NN-slug`), one-line goal, `depends` column naming phase ids
   (`-` for none), a coarse acceptance criterion (one sentence; it becomes executable at
   expansion), status `pending`. Dependencies are edges, not an ordering — two phases
   with no edge between them are explicitly parallelizable.

## Mandatory final step (P6)

Re-read the appended PHASES.md section and verify: every row parses, every `depends`
reference names an existing phase id, no dependency cycles (walk the edges). Print the new
rows as your output, plus any conflict you surfaced in step 3 and how it was resolved.

## Failure modes

- **Feature conflicts with an ADR** (step 3) → stop before writing anything. The resolution (superseding ADR or changed scope) must be on disk before phases are indexed.
- **Feature too vague to cut phases** → write zero rows; return the 2–3 questions whose answers unblock planning. A wrong phase index is worse than none.
- **Dependency cycle in your own cut** → re-cut; cycles always mean two phases are really one.

## Handoff

`/expand-phase <id>` for the first new phase whose dependencies are all `done` (or that has none).
