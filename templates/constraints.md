# Constraints — {{PROJECT_NAME}}

<!-- Standing rules: things that are true for EVERY feature, indefinitely,
     until an ADR changes them.
     Boundary with other files (keep it sharp — blurring it inflates the
     per-session tax):
       - One-time decision with rationale  -> docs/adr/
       - True in every session AND needed before reading anything else -> CLAUDE.md
       - Standing rule a session consults when relevant -> HERE.
     Rules coming from a methodology/architecture skill are recorded here in
     self-contained form: the project has the prose, not the skill. Never
     "follow <skill-name>" — a session without that skill must still be able
     to comply. -->

## Layering

<!-- The table is the human-readable form; .claude/workflow/boundaries.rules is
     the enforced form. Change BOTH, and only via an ADR. -->

| Layer | Directory | May depend on |
|---|---|---|
| {{name}} | `{{prefix/}}` | {{layers or "nothing"}} |

Dependency rule: {{one sentence, e.g. "dependencies point inward: entry layers may
depend on domain, never the reverse; infrastructure is reached only through interfaces
the domain owns."}}

## Invariants

<!-- Rules with no expiry. Each one either has a hook/CI check enforcing it, or
     names why it can't be machine-checked (those are the ones to re-verify in
     /validate-phase). -->

- {{invariant}} — enforced by: {{hook name / toolchain command / "review only"}}

## Observed conventions

<!-- Adopted projects: extracted from the code by /adopt-project, each with a
     real reference file. Bootstrapped projects: written as chosen, examples
     added as the first phases land. Following these beats any abstract ideal —
     inconsistency costs more than imperfection.
     Findings live here too: an expensive, verified fact about how the code IS —
     where the obvious reading is wrong — is not a decision, so it never becomes
     an ADR. Same shape as a convention plus the date it was last checked against
     its file. That date and that file make staleness derivable with no tooling
     of its own: `git log --since="<date> 00:00" -- <file>` answers whether the
     ground moved. The 00:00 is load-bearing: git fills a missing time with the
     current one, so a bare date hides everything committed that same day.
     A finding lives in exactly ONE place. If this project keeps path-scoped rule
     files (.claude/rules/*.md with `paths:`, .cursor/rules/*.mdc with `globs:`),
     a domain-scoped finding belongs there instead — they attach while the code is
     being edited, which is when it matters, and this file is read whole and read
     late. Then it is named in CLAUDE.md's pointer table, not copied here: a
     command planning a feature has to be able to reach it. -->

- {{convention}} — example: `{{path/to/real/file}}`
- {{finding: what the obvious reading would be, and why it is wrong}} — verified {{YYYY-MM-DD}}: `{{path/to/real/file}}`

## Error handling

- {{project-wide error shape and where errors are translated, e.g. "domain throws typed errors; the HTTP layer maps them to status codes in one place"}}

## Testing

- {{where tests live, naming, what must be tested per phase, e.g. "tests mirror source paths under tests/; every acceptance criterion has at least one automated check"}}
