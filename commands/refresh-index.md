---
description: Rebuild the repo index and re-detect the toolchain; detect and report doc/code drift
argument-hint: (no arguments)
---

# /refresh-index

**Purpose:** keep the on-disk state honest when the code moved without the workflow —
the recovery path for "the operator ignored the workflow for a few commits" (that's
allowed; the workflow must absorb it, not punish it).

**Arguments:** none.

**Preconditions:** git repo with workflow state installed.

**Reads:** git history, `docs/index/_overview.md` (stamp), `.claude/workflow/toolchain.json`, `docs/phases/PHASES.md`.
**Writes:** `docs/index/` (rebuilt), `.claude/workflow/toolchain.json` (re-detected when stale), drift report to stdout (and to `docs/phases/PHASES.md` status column if phases are affected).

## Steps

1. **Index.** Run `scripts/build-index.sh --check`; if stale, `scripts/build-index.sh`.
   Diff the regenerated `_overview.md` against the previous version (git diff): new
   modules, removed modules, changed dependency edges. These diffs are the drift signal —
   read them, don't just regenerate.

2. **Toolchain.** If any manifest/config file (package.json, pyproject.toml, go.mod,
   Cargo.toml, lockfiles, linter configs) changed since `toolchain.json`'s
   `detected_from` commit (`git diff --name-only <detected_from> HEAD`), re-run
   `.claude/hooks/lib/detect-toolchain.sh` and report newly appeared or resolved gaps.

3. **Phase-table reconciliation.** For each phase that is neither `done` nor
   `superseded by <ids>` in PHASES.md (both are terminal — nothing will run them again),
   check whether the files its spec names were modified by commits the workflow didn't make
   (commits since the phase's last notes entry). If yes, flag it: the spec may describe a
   world that no longer exists. Recommend per phase: re-run `/expand-phase` (set the status
   back to `pending` — cheap, specs are disposable by design) or, if untouched, leave as is.
   Where the *goal* rather than the spec is now wrong, that is a re-cut, not a refresh —
   name it and hand it to `/plan-feature`, which supersedes the row.

4. **Boundary spot-check.** Run the boundary rules over files changed since the index
   stamp (same grep the hook uses). Manual commits bypassed the edit hook; violations
   land in the drift report rather than blocking anything after the fact.

## Mandatory final step (P6)

The rebuilt index and toolchain file are the durable outcome; the drift report is the
readable one. Print: index delta (modules/edges added/removed), toolchain changes, phases
flagged in step 3 with the recommended action, boundary findings. If nothing drifted, say
exactly that in one line. Offer a commit of the regenerated files
(`chore: refresh repo index`).

## Failure modes

- **Massive drift** (index diff touches most modules — e.g. a big refactor landed) → constraints and boundary rules may describe the old architecture. Recommend `/adopt-project`, which has a re-adoption path for exactly this ("Re-adopting an already-adopted project"): it re-derives the observations and reports contradictions, and is forbidden from rewriting an accepted ADR or a confirmed constraint. Do not auto-rewrite constraints here; that needs operator eyes.
- **PHASES.md hand-edited into an unparseable state** → repair the table structure (columns, status vocabulary), preserving every row's content; report what was repaired.

## Handoff

Depends on findings: clean → none; flagged phases → `/expand-phase <id>`; massive drift → operator decision on re-adoption.
