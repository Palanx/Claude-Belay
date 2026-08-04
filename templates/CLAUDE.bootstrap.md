# {{PROJECT_NAME}}

{{ONE_LINE_PURPOSE}}

Greenfield project run under the phase workflow. Every rule here is true in *every*
session; everything session-specific lives on disk behind the pointer table. Keep this
file under 150 lines — a line added here is a tax on every future session.

## How work happens here

One pipeline: `/plan-feature` → `/expand-phase <id>` → `/implement-phase <id>` →
`/validate-phase <id>` → repeat. Phase state lives in `docs/phases/PHASES.md`
(vocabulary: `pending | expanded | in-progress | blocked | superseded by <ids> | done`) —
trust the table, not memory. Never expand a phase whose dependencies aren't `done`. Never
mark `done` yourself; only `/validate-phase` does. A cut that turns out wrong is
superseded by new rows, never edited or deleted — same rule as an ADR.

## Session reading rule

Read `CLAUDE.md` (this file) + the current phase's directory
(`docs/phases/<id>/spec.md`, `notes.md`) + the files the spec points to. Nothing else
unless the spec proves insufficient — and then record the gap in the phase's `notes.md`.
For orientation beyond the phase, load ONE section of `docs/index/`, not the whole thing.

## Architecture

Layers and allowed dependency direction (full detail in `docs/constraints.md`;
machine-enforced by `.claude/workflow/boundaries.rules`):

{{LAYERING_SUMMARY — e.g. "routes → services → domain; infra is called only via
interfaces owned by domain. Nothing imports upward."}}

Enforcement is real, and its exact reach is recorded, not assumed: the hooks run whatever
`.claude/workflow/toolchain.json` configures for the file you touched, and print a loud
`workflow gap:` line naming any category that has no tool. Read that file's `gaps` to know
what is *not* checked here — some stacks have no per-file typecheck at all. Commits with
secrets are blocked in every project. When a hook reports a failure, fix it before doing
anything else — the error text tells you how. Changing a boundary rule requires a
superseding ADR, never a silent edit.

## Conventions

- Commits: Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`), one phase's work per commit where practical.
- Every command that does work ends by writing its outcome to disk (notes, status). A session's undocumented knowledge is lost knowledge.
- Decisions that constrain the future get an ADR in `docs/adr/` before the code lands.
- If a Belay hook or command misfires (false positive, wrong tool command, unhandled case) or a workflow step causes friction, say so and offer `/belay-feedback` — the only channel back to the workflow package.

## Pointer table — where everything else lives

| What you need | Where it is |
|---|---|
| What we're building & why | `docs/product/requirements.md` |
| Standing rules & invariants | `docs/constraints.md` |
| Past decisions & rationale | `docs/adr/` (newest number wins; superseded ADRs say so) |
| Phase index & status | `docs/phases/PHASES.md` |
| Current phase spec / notes | `docs/phases/<id>/spec.md`, `docs/phases/<id>/notes.md` |
| Repo map & module symbols | `docs/index/_overview.md`, then one `docs/index/<module>.md` |
| Test/lint/typecheck commands | `.claude/workflow/toolchain.json` |
| Layer boundary rules | `.claude/workflow/boundaries.rules` |
| Security review reports | `docs/security/` |
| Workflow templates | `docs/templates/` |
