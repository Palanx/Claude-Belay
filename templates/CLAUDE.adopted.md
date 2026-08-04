# {{PROJECT_NAME}}

{{ONE_LINE_PURPOSE}}

Existing codebase adopted into the phase workflow on {{ADOPTION_DATE}}. The code as it
is outranks any ideal: follow the observed conventions in `docs/constraints.md` even
where you'd design differently — consistency beats theory in a living codebase. Every
rule in this file is true in *every* session; keep it under 150 lines.

## How work happens here

One pipeline: `/plan-feature` → `/expand-phase <id>` → `/implement-phase <id>` →
`/validate-phase <id>` → repeat. Phase state lives in `docs/phases/PHASES.md`
(vocabulary: `pending | expanded | in-progress | blocked | superseded by <ids> | done`) —
trust the table, not memory. Never expand a phase whose dependencies aren't `done`. Never
mark `done` yourself; only `/validate-phase` does. A cut that turns out wrong is
superseded by new rows, never edited or deleted — same rule as an ADR. If docs and code seem out of sync, run
`/refresh-index` before planning anything.

## Session reading rule

Read `CLAUDE.md` (this file) + the current phase's directory
(`docs/phases/<id>/spec.md`, `notes.md`) + the files the spec points to. Nothing else
unless the spec proves insufficient — and then record the gap in the phase's `notes.md`.
For orientation beyond the phase, load ONE section of `docs/index/`, not the whole thing.

## Architecture — as observed, not as wished

Layers as the code actually has them (detail in `docs/constraints.md`; enforced by
`.claude/workflow/boundaries.rules`):

{{LAYERING_SUMMARY — as inferred by /adopt-project}}

ADRs numbered from adoption are **reconstructed** — they record what IS, and their
rationale may be incomplete. A reconstructed ADR is still binding until superseded.
Known contradictions in the codebase live in `docs/adoption-report.md`; do not "fix"
them in passing — each needs an operator decision first.

Enforcement is real, and its exact reach is recorded, not assumed: the hooks run whatever
`.claude/workflow/toolchain.json` configures for the file you touched, and print a loud
`workflow gap:` line naming any category that has no tool. Read that file's `gaps` to know
what is *not* checked here — some stacks have no per-file typecheck at all. Commits with
secrets are blocked in every project. When a hook reports a failure, fix it before doing
anything else. Changing a boundary rule requires a superseding ADR, never a silent edit.

## Conventions

- Follow the observed conventions in `docs/constraints.md` §Observed conventions — each has a real file as its reference example.
- Commits: {{COMMIT_CONVENTION — as observed in git log, e.g. Conventional Commits}}.
- Every command that does work ends by writing its outcome to disk (notes, status).
- Decisions that constrain the future get an ADR in `docs/adr/` before the code lands.
- If a Belay hook or command misfires (false positive, wrong tool command, unhandled case) or a workflow step causes friction, say so and offer `/belay-feedback` — the only channel back to the workflow package.

## Pointer table — where everything else lives

| What you need | Where it is |
|---|---|
| Standing rules & observed conventions | `docs/constraints.md` |
| Adoption findings & open decisions | `docs/adoption-report.md` |
| Past decisions (incl. reconstructed) | `docs/adr/` (newest number wins; superseded ADRs say so) |
| Phase index & status | `docs/phases/PHASES.md` |
| Current phase spec / notes | `docs/phases/<id>/spec.md`, `docs/phases/<id>/notes.md` |
| Repo map & module symbols | `docs/index/_overview.md`, then one `docs/index/<module>.md` |
| Test/lint/typecheck commands | `.claude/workflow/toolchain.json` |
| Layer boundary rules | `.claude/workflow/boundaries.rules` |
| Security review reports | `docs/security/` |
| Workflow templates | `docs/templates/` |
