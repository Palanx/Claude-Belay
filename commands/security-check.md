---
description: Advisory security review of a scope — the reasoning companion to the enforced pre-commit gate
argument-hint: [path or module to review; defaults to files changed since last review]
---

# /security-check

**Purpose:** the *advisory* half of the security posture (P2 in reverse: the hook enforces
the mechanical checks deterministically; this command does the judgment the hook can't —
authz logic, trust boundaries, injection surfaces). It never gates; it reports.

**Arguments:** `$ARGUMENTS` — a path or module name. If empty: everything changed since the last report in `docs/security/` (or the whole repo if none exists).

**Preconditions:** `.claude/workflow/toolchain.json` exists (run the entry-point command first if not).

**Reads:** the scoped source files, `docs/index/` sections for the scope, `docs/constraints.md`, previous reports in `docs/security/`.
**Writes:** `docs/security/review-<YYYY-MM-DD>.md`.

## Steps

1. **Mechanical sweep first.** Run the toolchain `secrets` command over the scope (or the
   builtin patterns from the pre-commit hook against the working tree) and the `audit`
   command. Their findings go in the report — this catches anything that slipped in
   outside a Claude-driven commit (manual commits bypass the PreToolUse hook).

2. **Trust-boundary review.** For each entry point in the scope (from the index): where
   does external input arrive, and is it validated *at* the boundary? Flag any handler
   that passes raw input inward.

3. **AuthZ review.** For each route/command/operation in scope: who may call it, where is
   that checked, and can the check be bypassed by calling an inner layer directly?
   Cross-reference the boundary rules — a layering violation is often a security bypass.

4. **Secret handling.** How does the scope read credentials (env, file, hardcoded)? Flag
   anything that logs, serializes, or returns secret material.

5. **Injection surfaces.** String-built SQL/shell/HTML paths in scope; flag those not
   using the platform's parameterized/escaped form.

## Mandatory final step (P6)

Write `docs/security/review-<date>.md`: scope, date, commit hash, findings as a table
(severity · file:line · issue · concrete fix), and an explicit "checked, found clean"
list — recording what was *examined* matters as much as what was found, so the next
review knows where this one stopped. Print the findings table. If any finding is
severity-high: recommend the fix become an immediate phase (`/plan-feature`), and say so
in the report.

## Failure modes

- **Scope too large to review honestly in one session** → narrow to the highest-risk modules (entry points first), and write the unreviewed remainder into the report as explicitly unreviewed. A partial honest report beats a complete shallow one.
- **No secrets/audit tooling** (gaps in toolchain.json) → run the builtin patterns, and repeat the gap warning + fix in the report.

## Handoff

High-severity findings → `/plan-feature <fix>`. Otherwise none; this command is a leaf.
