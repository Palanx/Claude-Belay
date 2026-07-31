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
     inconsistency costs more than imperfection. -->

- {{convention}} — example: `{{path/to/real/file}}`

## Error handling

- {{project-wide error shape and where errors are translated, e.g. "domain throws typed errors; the HTTP layer maps them to status codes in one place"}}

## Testing

- {{where tests live, naming, what must be tested per phase, e.g. "tests mirror source paths under tests/; every acceptance criterion has at least one automated check"}}
