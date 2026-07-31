---
description: Greenfield entry point — turn requirements into project state (requirements, constraints, ADRs, phase index, hooks wiring)
argument-hint: [requirements text, or a path to a requirements document]
---

# /bootstrap-project

**Purpose:** initialize a brand-new project into workflow state. After this command the
repo has everything `/plan-feature` and `/expand-phase` need; greenfield and adopted
projects are indistinguishable from here on (P8).

**Arguments:** `$ARGUMENTS` — requirements as prose, or a path to a document. If empty,
elicit requirements interactively (step 2).

**Preconditions:**
- The workflow package is installed (`.claude/hooks/`, `.claude/commands/`, templates under `docs/templates/`). If not, stop and tell the operator to run `install.sh` first.
- `docs/product/requirements.md` does not already exist. If it does, stop: this project is already bootstrapped — the operator wants `/plan-feature`.

**Reads:** `$ARGUMENTS` (or the referenced document), `docs/templates/*`.
**Writes:** `docs/product/requirements.md`, `docs/constraints.md`, `docs/adr/0001-*.md` (+ more ADRs as decided), `docs/phases/PHASES.md`, `.claude/workflow/boundaries.rules`, `.claude/workflow/toolchain.json`, `CLAUDE.md`, `docs/index/`.

## Steps

1. **Ensure a git repo exists.** `git rev-parse --git-dir` — if not a repo, run `git init`.

2. **Requirements.** If `$ARGUMENTS` is empty or vague, interview the operator: what is
   being built, for whom, the 3–5 capabilities that matter, explicit non-goals, and any
   hard constraints (compliance, latency, platform). Write
   `docs/product/requirements.md` using `docs/templates/requirements.md` as the shape.
   Non-goals are mandatory — an empty non-goals section means the interview isn't done.

3. **Architecture decisions.** Propose to the operator: stack, architecture style, and the
   layering (names + directory prefixes + allowed dependency directions). Keep it to the
   decisions that are expensive to reverse. Methodology or architecture skills active in
   this session are a valid input to the proposal — greenfield has no code to observe, so
   they are the only convention source there is. A rule adopted from one is an ADR like any
   other, with its rationale written out; "the skill says so" is not a rationale. For each
   accepted decision write an ADR in `docs/adr/` from `docs/templates/adr.md`, numbered from
   `0001`, status `accepted`.

4. **Constraints.** Write `docs/constraints.md` from the template: the layering table, the
   dependency rule, and the invariants that hold for every feature. Constraints are
   *standing rules*; one-time decisions belong in the ADRs (see the template header).
   Transcribe the standing rules from any active methodology skills into the section that
   fits (Invariants / Error handling / Testing / Observed conventions), and show the
   operator the drafted lines for confirmation before writing. Write them **self-contained,
   never by skill name** — the skill lives in one operator's home directory; the next
   session to read this file may not have it (P5/P6). A rule expressible as a command with
   an exit code goes in as an invariant with that command as its `enforced by`; a rule about
   layer edges goes to `boundaries.rules` in step 5.

5. **Boundary rules.** Translate the layering into `.claude/workflow/boundaries.rules`
   (`layer` and `deny` lines — see `docs/templates/boundaries.rules`). This is the
   executable form of the dependency rule (P2): the prose in constraints.md explains it,
   the hook enforces it.

6. **Toolchain.** Scaffold the minimal project skeleton for the chosen stack (manifest,
   test runner config — nothing more), then run
   `.claude/hooks/lib/detect-toolchain.sh`. Read the printed gaps aloud to the operator
   with the proposed fix for each; install what they approve and re-run until the gaps
   list is intentional.

7. **Phase index.** Break the requirements into phases and write
   `docs/phases/PHASES.md` from the template. Index entries only — id, one-line goal,
   dependencies, coarse acceptance criterion, status `pending` (P4). Do NOT write specs;
   deep specs for later phases would be built on information that doesn't exist yet.

8. **CLAUDE.md.** Copy `docs/templates/CLAUDE.bootstrap.md` to `CLAUDE.md` and fill the
   placeholders (project name, one-line purpose, layering summary). It must stay under
   150 lines (P1) — everything else is reached through its pointer table.
   **Corporate mode** (`.claude/workflow/corporate` exists): never create or modify
   `CLAUDE.md`, `AGENTS.md`, or `.cursor/rules/*` — those belong to the company. Write
   the filled template to `CLAUDE.local.md` instead (Claude Code auto-loads it alongside
   `CLAUDE.md`), complementing any existing agent docs without repeating them. If
   `.cursor/commands/` exists, also write `.cursor/rules/belay.mdc` (frontmatter
   `alwaysApply: true`) carrying the same pointer table.

9. **Index.** Run `scripts/build-index.sh` (it will be small; that's fine).

## Mandatory final step (P6)

Everything this command produced is already on disk — verify it: list the files written,
re-read `docs/phases/PHASES.md` to confirm the table parses (every row has id, goal,
depends, acceptance, status), and confirm `CLAUDE.md` is under 150 lines
(`wc -l CLAUDE.md`). Then offer the operator a single commit of the bootstrap state
(commit message: `chore: bootstrap workflow state`). Corporate mode: check
`CLAUDE.local.md` instead, and skip the commit offer — the workflow state is
deliberately invisible to git.

## Failure modes

- **Operator can't answer requirements questions** → write what is known, mark open items as `OPEN:` lines in requirements.md, and say plainly which phases cannot be indexed until they're resolved.
- **Toolchain gaps the operator declines to fix** → leave them in `toolchain.json` `gaps`; the hooks will warn on every relevant edit. That is by design — do not silence it.

## Handoff

`/expand-phase <first-id>` for the first pending phase with no unmet dependencies.
