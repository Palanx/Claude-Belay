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

1. **Mechanical sweep first.** Two scans, and name in the report which one actually ran —
   "checked, found clean" is worth nothing if the reader can't tell what checked it.

   **Secrets.** Do *not* use `toolchain.json`'s `secrets` command here: it is
   `gitleaks protect --staged`, which reads the git index and ignores any path you give it,
   so it would report on staged changes while your report claims a scope. Use the
   working-tree form instead — `gitleaks detect --no-git --source <scope> --redact` when
   gitleaks is on PATH. If it isn't, fall back to the builtin patterns from
   `.claude/hooks/pre-commit-security.sh` (the `PATTERNS` variable) run over the scope's
   files, and say in the report that the weaker scanner was used — that is a finding about
   the project's tooling, not a footnote.

   **Dependencies.** The `audit` command from `toolchain.json` is project-wide and scope-free
   by nature; run it as-is.

   Both catch what slipped in outside a Claude-driven commit, since manual commits bypass
   the PreToolUse hook entirely.

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

Write `docs/security/review-<date>.md`: scope, date, commit hash, **which secret scanner
ran** (gitleaks or the builtin patterns — step 1), findings as a table
(severity · file:line · issue · concrete fix), and an explicit "checked, found clean"
list — recording what was *examined*, and with what, matters as much as what was found, so
the next review knows where this one stopped. Two reviews on the same date append to the
same file rather than overwriting it; the scope line distinguishes them. Print the findings
table. If any finding is
severity-high: recommend the fix become an immediate phase (`/plan-feature`), and say so
in the report.

## Failure modes

- **Scope too large to review honestly in one session** → narrow to the highest-risk modules (entry points first), and write the unreviewed remainder into the report as explicitly unreviewed. A partial honest report beats a complete shallow one.
- **No secrets/audit tooling** (gaps in toolchain.json) → run the builtin patterns over the scope, and repeat the gap warning + its fix verbatim in the report. A scope reviewed only by the grep fallback is a weaker review than one gitleaks saw; the report says which, so the next reviewer knows whether re-scanning is worth it (P7).

## Handoff

High-severity findings → `/plan-feature <fix>`. Otherwise none; this command is a leaf.
