# ADR-0001: Ownership of a file is decided by the install manifest, not by a path list

- Status: accepted
- Date: 2026-09-02

## Context

`/validate-phase` now attributes a finding to the package when the misbehaving file is one
the package installed, so it needs a rule for "is this file ours or the project's". The
obvious answer is a prefix list — `.claude/hooks/`, `.claude/commands/`, `scripts/build-index.sh`,
`docs/templates/` — written into the command. That list already exists twice, in
`README.md` § *What to customize vs leave alone* and in the operator's head, and a third
copy inside a command that ships into every project is a third thing to keep in sync.

`.claude/workflow/` is the trap: it holds `boundaries.rules`, `toolchain.json` and
`toolchain.manual.json`, all project-owned, next to `installed` and `belay-version`, which
are ours. A prefix rule at that directory blames the package for a project's own bad
`toolchain.json` command — the exact misattribution the feature exists to prevent.

## Decision

A file belongs to the package if `.claude/workflow/installed` lists it. `install.sh` calls
`record()` only inside `copy_into`, so the manifest is exactly the set of files the package
wrote and nothing else: `boundaries.rules` is created separately (install.sh, "project-owned
files") and never recorded; `toolchain.json` is written by detection; `CLAUDE.md` by the
entry commands. The manifest lives at the same path in both modes, is untracked in a normal
install, and is read with `grep` — no git, so it works on uncommitted state.

When the manifest is absent — an install old enough to predate it, never re-run — say so
rather than reading its silence as "nothing upstream".

## Consequences

The rule is self-maintaining: a file the package starts or stops shipping changes ownership
with no edit here. It is also load-bearing in a way nothing else was, so two asserts pin it
(`installed manifest excludes project-owned files`, `…holds the package files attribution
points at`) — if someone adds a `record()` call for a project-owned file, attribution starts
lying and the suite says so.

Rejected — a prefix list in the command: drifts against the README's list, and gets
`.claude/workflow/` wrong. Rejected — reading the README's project-owned section at runtime:
a command installed into a project cannot see the package's README. Rejected — deciding by
who applies the fix: the fix is always local; that is what makes the laundering possible.
