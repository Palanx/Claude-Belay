# Claude Belay

The workflow package itself — not a project that uses it. Nothing here is belay
state: there is no `docs/phases/`, no `toolchain.json`, no pipeline. `docs/` is
this package's own documentation. Files under `commands/`, `hooks/`,
`templates/`, `scripts/` and `settings/` never run in place; `install.sh` copies
them into a target repo, and that copy is what executes.

## The corporate path rewrite — read before adding any path

`install.sh:122-124` rewrites canonical paths into the `.belay/` form when
installing with `--corporate`, using a **closed alternation list**
(`docs/(product|adr|phases|index|security|templates|constraints.md|adoption-report.md)`
and `scripts/build-index.sh`). A path name outside that list, written into a
command or template, stays canonical in a corporate install and points at a
location that mode does not have — silently. `tests/corporate-smoke.sh:73`
checks the same list, so it will not catch a genuinely new name either.
Introducing one means editing the sed, the test's regex, and the README together.

## The gate

`tests/corporate-smoke.sh` is the whole package's test suite despite the name.
Run it before every commit. When adding an assert, verify it fails against the
commit before the fix — an assert that cannot fail is worse than none.

Four of its asserts are **documentation consistency**, not behaviour: the phase
status vocabulary must match across both `CLAUDE.*.md` templates and
`templates/PHASES.md`; every `§Section` referenced by any command or template
must exist in `templates/constraints.md`; both entry commands must handle the
`CLAUDE.md` workflow variants; and the file `gap_warn` tells an operator to edit
must be one the README lists as project-owned. Rewording a template can fail the suite. That is
the point — "two files say different things" is the bug class no behavioural
test sees.

## Extending toolchain detection

`hooks/lib/detect-toolchain.sh` is a **closed pool**, twice over: seven stack markers,
and inside each a fixed list of tools with fallback chains. Nothing about it is
open-ended, and that is deliberate — every dead end calls `gap()` with a concrete fix
rather than guessing a command that may not exist. A guessed command turns a gate into a
false failure, which is worse than a stated gap (P7).

It never reads `.claude/workflow/toolchain.manual.json`. It rewrites its own output
whole, so anything it opened it would eventually clobber; the merge lives in
`hooks/lib/common.sh`. Keep it that way — that separation *is* the fix for the bug where
hand-added commands vanished at the next `/refresh-index`.

| Case | Where | Cost |
|---|---|---|
| New tool, known stack | one `elif` in that stack's block | ~3 lines. The chain still has to end in `gap()` |
| New stack | a new `if [ -f <marker> ]` block | ~20 lines: marker, `STACKS+=`, project-wide commands, `file_block`, one `gap()` per category it cannot cover |
| New category | **schema change, three places** | the JSON emitter, the accessor in `common.sh`, and every consumer (`post-edit-gate.sh`, `/validate-phase`, CI) |

Two rules the existing blocks already follow:

- `file_commands` only takes tools that accept a single file argument. Project-wide-only
  tools (`tsc`, `go vet`, `clippy`) go in `commands` and run at `/validate-phase`.
- A stack whose real commands cannot run on a fresh clone gets honest gaps, not a
  command that will fail. Unity, Godot and Unreal are the precedent — read those blocks
  and their comments before adding a stack with an engine or an SDK behind it.

Before writing any of it, check the third rung first: a project with a `Makefile`
exposing `test:` / `lint:` is already covered by the fallback, and one that only needs a
command *here* needs `toolchain.manual.json`, not a package change. Upstream a detection
block when the same stack shows up in a second project.

## Examples are fictional and stay fictional

`docs/worked-example.md` and every `templates/*.example.md` are one coherent
invented project (`taskboard`: Node/Express + SQLite). They cross-reference each
other, so a change to one propagates. Never seed an example from a real
codebase — not a type name, not a method signature, not a measurement. Material
generalized from a private repo gets audited before it lands, examples included.

## Conventions

- Bash, `set -euo pipefail`, must work on macOS and Linux. Hooks fail **closed**
  with no JSON parser available — never exit 0 as if they had run.
- Deliberate shortcuts are marked `belay-debt:` with the ceiling and the upgrade
  path. Not `TODO`.
- Commits: Conventional Commits.
- `README.md` is the user-facing contract. A behaviour change it does not
  describe is unfinished work, not a follow-up.

## Pointer table

| What you need | Where it is |
|---|---|
| Everything user-facing: modes, flags, guarantees | `README.md` |
| What each command promises | `commands/<name>.md` (preconditions, reads, writes, failure modes) |
| Open bugs reported from consuming projects | `~/.claude-belay/feedback/` (listed at SessionStart) |
| Which installs are behind HEAD | `scripts/installs-stale.sh` (also at SessionStart) |
| The design principles P1–P8 | `README.md` § Design principles |
| Escape hatch when detection misses a stack | `README.md` § When your stack isn't detected |
