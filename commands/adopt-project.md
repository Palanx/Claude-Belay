---
description: Existing-codebase entry point — infer stack, layering, conventions and decisions from the code; produce workflow state and a gap report
argument-hint: (no arguments)
---

# /adopt-project

**Purpose:** bring an existing codebase into workflow state by *observing* it, not
idealizing it. The code as it is wins over any abstract ideal: existing conventions
become rules, because violating them is worse than following an imperfect pattern.
After this command the project is in the same state a bootstrapped project would be (P8).

**Arguments:** none.

**Preconditions:**
- Working directory is a git repo with at least one commit. Otherwise this is `/bootstrap-project`.
- Workflow package installed. `docs/constraints.md` must not already exist (if it does, the project is already adopted — the operator probably wants `/refresh-index`).

**Reads:** the codebase (via `git ls-files`, manifests, configs, existing docs/READMEs), `docs/templates/*`.
**Writes:** `.claude/workflow/toolchain.json`, `.claude/workflow/boundaries.rules`, `docs/constraints.md`, `docs/adr/0001-*.md` … (reconstructed), `docs/adoption-report.md`, `docs/phases/PHASES.md` (empty table), `docs/index/`, `CLAUDE.md`.

## Steps

1. **Toolchain (P7).** Run `.claude/hooks/lib/detect-toolchain.sh`. Then verify its output
   against reality: run the detected test command once; if it fails out of the box, record
   that in the adoption report (a broken test suite is a finding, not a blocker). Report
   every gap with its concrete fix.

2. **Structure survey.** Run `scripts/build-index.sh`, then read
   `docs/index/_overview.md`. From the module list and dependency edges, infer the
   *de facto* layering: which directories act as entry points, which as domain/services,
   which as infrastructure. Name the layers after what the directories are actually
   called, not textbook names.

3. **Existing documentation audit.** Find READMEs, docs/, wikis-in-repo, ADRs, comments
   that claim architecture. For each: current, stale (contradicted by the code), or
   aspirational (never implemented). List all three categories in the adoption report —
   stale docs are actively harmful and the operator must decide to fix or delete them.

4. **Convention extraction.** Read a representative sample per module (largest files +
   most-imported files from the index). Extract the implicit conventions actually
   followed: naming, error handling shape, test file layout and naming, logging, how
   configuration is read. Each becomes a rule in `docs/constraints.md` under
   "Observed conventions", each with one real file as its example.

5. **Reconstructed ADRs.** For each significant decision visible in the code (framework
   choice, database, layering, sync/async style, auth approach), write an ADR from the
   template with status **`reconstructed`** and this header line:
   `> Reconstructed from code during adoption — records what IS, not what was decided. Verify before relying on the rationale.`
   Never invent rationale; where the reason isn't visible, write "rationale unknown".

6. **Boundary rules.** Write `.claude/workflow/boundaries.rules` encoding the layering
   *as observed* — only `deny` edges the code already respects. Where the code is
   inconsistent (some files cross a layer, most don't), do NOT invent a rule; put the
   contradiction in the gap report instead. A rule the codebase already violates would
   make the boundary hook cry wolf on every edit.

7. **Gap report.** Write `docs/adoption-report.md` with exactly three sections:
   - **Contradictions** — where the code disagrees with itself (two error-handling styles, duplicated modules, layering violations). Facts with file references, no fixes.
   - **Decisions needed** — one line per human decision, each phrased as a question with the options observed in the code.
   - **Toolchain gaps** — from step 1, with proposed fixes.

8. **Constraints + phase table.** Write `docs/constraints.md` (layering from step 2,
   conventions from step 4). Write `docs/phases/PHASES.md` from the template with an
   empty phase table — phases come from `/plan-feature`.

9. **CLAUDE.md.** Copy `docs/templates/CLAUDE.adopted.md` to `CLAUDE.md`, fill the
   placeholders. If a `CLAUDE.md` already exists, merge: keep its project-specific rules
   that survive the P1 test ("true in every session?"), move the rest into
   `docs/constraints.md`, and add the pointer table. Under 150 lines, always.

## Mandatory final step (P6)

Verify the written state: `docs/adoption-report.md`, `docs/constraints.md`,
`docs/phases/PHASES.md`, `CLAUDE.md` (< 150 lines), `.claude/workflow/toolchain.json`,
`.claude/workflow/boundaries.rules`, `docs/index/_overview.md` all exist. Print the
"Decisions needed" section of the adoption report verbatim as your final output — those
questions are the handoff. Offer one commit: `chore: adopt project into workflow`.

## Failure modes

- **Codebase too inconsistent to infer layering** → write `boundaries.rules` with layers but zero `deny` lines, and make "choose the layering" the first entry in Decisions needed. The boundary hook is inert until the humans decide; that is honest.
- **No tests / no lint anywhere** → toolchain gaps name concrete options per stack (from detect-toolchain's output). Do not install tools unprompted.

## Handoff

Operator answers the "Decisions needed" questions (answers become real ADRs superseding
the reconstructed ones where relevant). Then `/plan-feature <description>` for the first
piece of work.
