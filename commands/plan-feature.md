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
- If you were sent here to re-cut an existing feature's phases rather than to plan a new feature, skip to "Re-cutting a phase whose premise died" below; steps 1–5 still apply, step 6 does not.
- If you were sent here to schedule a fix for a phase that is already `done` — a `needs a row:` entry in some phase's notes, or an operator naming a defect in a `done` phase's code — skip to "Scheduling a fix to a phase already done" below; steps 1–6 do not apply. The cut was right, so there is no feature to scope and nothing to interview for.

**Reads:** `CLAUDE.md`, `docs/constraints.md`, `docs/adr/` (titles + status lines of all; full text of any ADR the feature might touch), `docs/index/_overview.md` (plus the specific module sections the feature will touch), `docs/phases/PHASES.md`, and `docs/product/requirements.md` **if present** (bootstrapped projects have one; adopted projects do not — its absence is normal, not a precondition failure).
**Writes:** `docs/phases/PHASES.md` (appended feature section + rows).

## Steps

1. **Freshness.** Run `scripts/build-index.sh --check`. If stale, run
   `scripts/build-index.sh` first — planning against a stale index produces phases that
   name files that don't exist.

2. **Understand the request.** Restate the feature in two sentences: what changes for the
   user, and what explicitly does not (scope edge). If `$ARGUMENTS` is thin or the
   restatement has a gap, interview the operator — one round of questions, then re-state,
   and again — until two things are closed: the **scope edge** (the nearest thing a reader
   would assume is included and isn't) and the **non-goals** (what this feature will not do,
   even later). Both are mandatory because both are load-bearing downstream: step 6 writes
   them into the feature section's opening blurb, and `/expand-phase` reads that blurb to
   fill each spec's "Out of scope" section — an answer left open here becomes a guess an
   eager implementer acts on three phases later. Stop when a further answer would not move a
   phase boundary — this is the index, not the spec (P4); detail that only sharpens
   implementation belongs to `/expand-phase`. Do not open a second document for any of it:
   the blurb and the rows both live in `docs/phases/PHASES.md`, and a separate file
   describing the same feature is a second source of truth (P6). If nobody answers (headless
   `claude -p`), take the "too vague" failure mode below — never invent the answers.

3. **Conflict detection.** Read every ADR whose topic the feature touches, plus the
   constraints, plus `docs/product/requirements.md` where it exists. Requirements are
   checked in both directions: a feature that serves a stated capability cites its id in the
   rows it produces (`R4`), and a feature that lands on a recorded **non-goal** is a conflict
   like any other — the non-goals section is not decoration, it is the answer to an interview
   somebody already ran. If the feature contradicts a recorded decision (e.g. it wants an event
   queue and ADR-0003 says "no async infrastructure"), STOP and surface the conflict:
   quote the ADR, state the contradiction, and give the operator the two options —
   change the feature, or write a superseding ADR first. That ADR is a *new* file in
   `docs/adr/` from `docs/templates/adr.md`, next sequential number, status `accepted`; the
   ADR it replaces gets status `superseded` with a pointer to it, never an edit in place —
   the old rationale is the record of why the project used to think otherwise. Never plan
   around a recorded decision silently; that is how ADRs die.

   A **non-goal** conflict resolves differently: non-goals are not ADRs, so there is nothing
   to supersede. The operator either drops the feature or strikes the non-goal from
   `docs/product/requirements.md` — an amendment that template reserves for operator
   decision, so it is theirs to make, not yours. Either way it happens before any row is
   written, and you say which one they chose.

4. **Locate the change.** From the index, list the modules the feature touches and the
   dependency edges between them. This tells you the phase *order*: a phase can only
   depend on information that exists when it starts.

5. **Cut phases.** Slice the feature so that each phase passes the closure test (P5): a
   session reading only `CLAUDE.md` + that phase's directory must be able to complete
   it. Practical size: one phase = one coherent change to 1–3 modules, completable in a
   single session. If a phase needs "and also remember the thing from phase 2", the cut
   is wrong — either merge them or move the shared knowledge into the spec at expansion
   time via a pointer.

6. **Write the feature section.** Append to `docs/phases/PHASES.md` under a feature heading,
   in the shape of `docs/templates/PHASES.md`:
   - **First the blurb**, above the table: the two sentences step 2 converged on — what
     changes for the user, and the scope edge plus non-goals. This is the only place that
     survives the session, and it is what a later `/expand-phase` reads to know what the
     feature deliberately excludes. Two sentences, not a section.
   - **Then the rows:** next sequential ids (`NN-slug`), one-line goal, `depends` column
     naming phase ids (`-` for none), a coarse acceptance criterion (one sentence; it
     becomes executable at expansion), status `pending`. Dependencies are edges, not an
     ordering — two phases with no edge between them are explicitly parallelizable.

## Re-cutting a phase whose premise died

`/expand-phase`, `/implement-phase` and `/validate-phase` all have a path that ends "that
is a re-plan, not an implementation detail" — a dependency's deviation invalidated a later
phase's goal, or three failed validations proved the cut itself was wrong. This is where
those land, and the rule is the ADR rule: **supersede, never edit.**

1. The wrong row keeps its id and gets status `superseded by <new-ids>`. Do not edit its
   goal, do not delete it, do not renumber anything — it is the record of why the plan used
   to look like that, and its phase directory (spec + notes) stays on disk as the evidence
   of what was learned.
2. Cut the replacement phases from what is now known — steps 4 and 5 above, unchanged —
   and append them as new ids with status `pending`. Each one's goal line names the id it
   replaces.
3. Any row that listed the superseded id in `depends` now names the replacements instead.
   That edit is allowed and mandatory: a `depends` pointing at a superseded row can never
   be satisfied, since nothing will ever mark it `done`.
4. Say in your output what was superseded and why, in one line. The operator asked for a
   feature, not a re-plan, so the re-plan has to be visible.

No interview here unless the scope edge itself moved: the feature's blurb already
converged. If it *did* move, this is a new feature section, not a re-cut.

## Scheduling a fix to a phase already done

`/implement-phase` sends here a defect found in code a `done` phase delivered, when the phase
being implemented survives it (a `needs a row:` entry in that phase's notes). The cut was right
and the code is wrong, so this is neither a re-cut nor an edit:

1. Leave the `done` row exactly as it is. `superseded by` would record the cut as wrong, and
   only `/validate-phase` writes `done`.
2. Append one row to the same feature section: the next id, goal `fix <done-id>: <what is
   wrong>`, `depends: -`, a coarse acceptance criterion that fails today, status `pending`.
3. No interview: the scope edge did not move.

## Mandatory final step (P6)

Re-read the appended PHASES.md section and verify: the blurb is there and names both the
scope edge and the non-goals (a blurb that only restates the goal did not survive the
interview — write it properly now, or step 2 wasn't finished); every row parses; every
`depends` reference names an existing phase id; no dependency cycles (walk the edges).
Print the blurb and the new rows as your output, plus any conflict you surfaced in step 3
and how it was resolved.

## Failure modes

- **Feature conflicts with an ADR** (step 3) → stop before writing anything. The resolution (superseding ADR or changed scope) must be on disk before phases are indexed.
- **Feature too vague to cut phases** → write zero rows; return the 2–3 questions whose answers unblock planning. A wrong phase index is worse than none.
- **Dependency cycle in your own cut** → re-cut; cycles always mean two phases are really one.

## Handoff

`/expand-phase <id>` for the first new phase whose dependencies are all `done` (or that has none).
