# ADR-0003: A gate is silent when a file is out of its scope, loud when it is in scope with no tool

- Status: accepted
- Date: 2026-09-02

## Context

Gates exit 0 for two very different reasons, and a consuming project's wrapper could not
tell them apart. `boundary-check.sh` exits 0 with no output when there is no rules file,
when the path is not a file, and when the file sits under no declared `layer` prefix — the
last being every file in a fresh install, since `install.sh` writes `boundaries.rules` fully
commented out. `post-edit-gate.sh` also exits 0 silently for docs, markdown, engine assets
and declared-exempt trees, but calls `gap_warn` for a source file with no configured
per-file tools.

Reading the two scripts side by side, the difference looked arbitrary. It is not, and
nothing said so.

## Decision

The line is *why* nothing was checked:

- **Out of scope by configuration** — no rules, no layer, a docs file, an engine asset, an
  exempt tree. The project decided this file is not gated. Exit 0, silently.
- **In scope with no tool** — a source file the project does gate, for which no command is
  configured. `gap_warn` on stderr, then exit 0. Never silent (P7).

Exit codes stay `0` and `2` and no third code may be added: `edit-gate-adapter.sh`,
`scripts/check.sh` and `cursor-adapter.sh` all fold any non-zero into "violation", so a
third code would reach the operator as a layering breach. `boundary-check.sh`'s header now
states this, because a wrapper built on the old header invented a three-way contract that
happened to be right.

## Consequences

A gate's silence is meaningful and documented, so a wrapper can rely on it. The cost is
that the *report* one level up must not inherit the silence: `/validate-phase` used to say
`boundary sweep: clean` over an inert rules file, which is a claim about work that never
happened. It now distinguishes `not swept: no active deny rules`, and that verdict is a
stated gap, not a failure — no code change can add a `deny` rule, and `/adopt-project`
leaves the rules inert on purpose where the layering is still a human decision
(see [ADR-0004](0004-a-freshness-check-prefers-a-false-stale.md) for the same asymmetry
applied to freshness).

Rejected — `gap_warn` on every unlayered file: fires on every edit in a repo whose layering
is undecided, which is the state the package itself ships. Rejected — a third exit code for
"did not run": breaks all three callers.
