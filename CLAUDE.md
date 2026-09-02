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
and `scripts/(build-index|check).sh`). A path name outside that list, written
into a command or template, stays canonical in a corporate install and points at
a location that mode does not have — silently. `tests/corporate-smoke.sh:73`
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

## Gates take argv; adapters parse payloads

The enforcement layer has one contract, and it is load-bearing: **a gate takes
file paths and returns an exit code.** It parses no JSON and reads no stdin.
Anything that speaks an agent's payload is an *adapter* whose only job is to
translate one call.

That is why `scripts/check.sh` can run every gate without fabricating a fake
`{"tool_name":"Edit",...}` payload, and why the git hook and CI need no
belay-specific glue. Adding a gate that parses a payload re-establishes the
agent as the owner and forces every other caller to impersonate it.

- New gate → argv, exit code, stderr. Wire it into `scripts/check.sh`.
- Needs to fire on an agent action → add it to the relevant adapter
  (`edit-gate-adapter.sh`, `bash-gate-adapter.sh`, `cursor-adapter.sh`).
- The fail-closed contract for a missing JSON parser lives in the adapters, the
  only files that can hit it. A gate has nothing to fail closed about.

## What the installer may write into a target repo

Belay may write **untracked, per-clone** files that affect only the operator who
ran the installer. `.git/hooks/pre-commit` under `--git-hook` is the one case,
and it is opt-in for exactly that reason.

It may never write a **tracked** file that changes behaviour for the rest of the
team — which is what rules out generating `.github/workflows/*`, however
convenient. Corporate mode enforces the stricter form of this for every file and
the installer checks it; in normal mode there is no check, so this rule is the
only thing standing between a helpful feature and a commit somebody did not ask
for.

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

- Bash **4 or newer**, `set -euo pipefail`, must work on macOS and Linux. Stock
  macOS ships bash 3.2 and belay does not target it: 3.2 cannot even parse
  `install.sh` (an apostrophe in a comment inside `$( )` opens a quote there).
  Do not contort the source to accommodate it — the CI macOS job installs a
  modern bash, which is where that problem belongs. Hooks fail **closed** with
  no JSON parser available — never exit 0 as if they had run.
- Deliberate shortcuts are marked `belay-debt:` with the ceiling and the upgrade
  path. Not `TODO`.
- **A decision lands in the artifact it constrains, never in the commit message.**
  Nobody greps the history before editing a file. A decision about one file goes in that
  file, beside what it constrains — that is why every gate header carries its rationale.
  A decision that constrains **more than one file** has no such home: write it as an ADR in
  `docs/adr/`, using this package's own `templates/adr.md`. The threshold is exactly that
  question, and the half worth writing is the rejected alternative — the commit message
  keeps the choice and loses the reasons it beat the others.
- **When a decision creates a fact two files must share, its assert is part of the
  decision** — not of the bugfix that finds them disagreeing later. Every documentation
  assert in the suite was written reactively, after a contradiction had already shipped.
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
| The design principles P1–P9 | `README.md` § Design principles |
| Why a cross-file decision was taken, and what it beat | `docs/adr/` (this package's own, not a target's) |
| Running the gates by hand (categories, `--files`, `--staged`) | `scripts/check.sh --help`, `README.md` § The enforcement layer |
| Escape hatch when detection misses a stack | `README.md` § When your stack isn't detected |
