# Claude Belay

[![test](https://github.com/Palanx/Claude-Belay/actions/workflows/test.yml/badge.svg)](https://github.com/Palanx/Claude-Belay/actions/workflows/test.yml)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-workflow%20package-D97757?logo=anthropic&logoColor=white)](https://claude.com/claude-code)
[![Shell](https://img.shields.io/badge/shell-bash%20%E2%89%A5%204-4EAA25?logo=gnubash&logoColor=white)](install.sh)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)](#installing)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](https://github.com/Palanx/Claude-Belay/pulls)

> Belay (climbing): the rope system that catches a fall after inches instead of meters.

An installable workflow package for Claude Code: slash commands, enforcement hooks,
document templates and a `CLAUDE.md` scaffold that turn ad-hoc AI-assisted development
into a repeatable, gated pipeline. The agent still climbs; the gates catch every slip
cheaply and deterministically. Stack-agnostic; installs into a brand-new repo or an
existing codebase.

## Why it exists

Multi-session agent work fails in predictable ways: sessions start cold and anything not
on disk is lost; long sessions degrade and compaction destroys detail; prose rules get
ignored as context grows; up-front deep plans for late stages are wrong because they
depend on information that doesn't exist yet; and without a scoping mechanism every
session reads too much or too little. Every mechanism in this package targets one of
those failures.

## Design principles (the short form)

| # | Principle | Mechanism here |
|---|---|---|
| P1 | `CLAUDE.md` is a per-session tax | <150-line scaffolds; everything else behind a pointer table |
| P2 | Hooks enforce; markdown advises | lint/typecheck, secrets, and layering are executable gates |
| P3 | Determinism lives in the gate | executable acceptance criteria; hooks feed failures straight back |
| P4 | Two resolutions of planning | `PHASES.md` index up front; `spec.md` just-in-time per phase |
| P5 | Phase closure test | `CLAUDE.md` + phase dir must suffice; checked in `/validate-phase` |
| P6 | Filesystem is the only durable channel | every command ends by writing notes/status to disk |
| P7 | A check that examined nothing says so | never `pass` by vacuity: `detect-toolchain.sh` writes a `gaps` entry instead of guessing a command, `gap_warn` names the category it could not run, `--check` reports stale rather than fresh on a tree it has not compared, and a boundary sweep over inert rules reports `not swept`, not `clean` |
| P8 | One pipeline, two entry points | `/bootstrap-project` and `/adopt-project` converge on the same *pipeline* state — every command downstream reads the same files either way (the two differ only in what only one of them can know: requirements vs an adoption report) |
| P9 | Every gate result has a reachable remedy | a result names what fixes it *and* someone who can apply it — routing a finding to `/implement-phase` when no code change can clear it (an undecided layering, a spec the command itself mandated) is the bug; a verdict the operator cannot turn green is one they learn to ignore |

## The pipeline

```
/bootstrap-project ─┐
                    ├─→ shared state ─→ /plan-feature ─→ /expand-phase ─→ /implement-phase ─→ /validate-phase ─┐
/adopt-project ─────┘        ↑                                ↑                                                │
                             └── /refresh-index (drift)       └────────────── fail: fix loop ──────────────────┘
/security-check — advisory, any time
```

State layout in an installed project:

```
CLAUDE.md                          # <150 lines, pointer table — the only always-loaded file
.claude/
├── commands/*.md                  # the nine slash commands
├── hooks/                         # post-edit-gate, boundary-check, pre-commit-security (+ lib/, cursor-adapter)
├── settings.json                  # hook wiring (PostToolUse Edit|Write, PreToolUse Bash)
└── workflow/
    ├── toolchain.json             # detected commands per category + explicit gaps (generated)
    ├── toolchain.manual.json      # optional: your commands, wins over detection, never regenerated
    ├── boundaries.rules           # layer + deny lines (executable form of the dependency rule)
    ├── belay-version              # package commit this install came from (stamped by install.sh)
    ├── secret-allowlist           # optional: regexes to ignore in the builtin secret scan
    └── protected-branches         # optional: branch regexes where direct commits are blocked
docs/
├── product/requirements.md        # what & why (bootstrap) 
├── constraints.md                 # standing rules: layering, invariants, observed conventions
├── adoption-report.md             # adopt only: contradictions + decisions needed
├── adr/NNNN-*.md                  # immutable decisions; superseded, never edited
├── phases/PHASES.md               # phase index: id, goal, depends edges, status
├── phases/<id>/{spec.md,notes.md} # just-in-time spec + mandatory outcome record
├── index/                         # generated repo map: _overview.md + one file per module
├── security/                      # /security-check reports
└── templates/                     # blank + example for every document above
scripts/build-index.sh             # index generator (--check for staleness)
scripts/check.sh                   # gate runner: categories, --files, --staged
```

Corporate mode (`--corporate`): the `docs/` and `scripts/` trees above live under
`.belay/`, the pointer doc is `CLAUDE.local.md` instead of `CLAUDE.md`, hook wiring is
`.claude/settings.local.json`, and all of it is hidden from git via `.git/info/exclude`.

**Everything below writes paths in their canonical form** (`docs/…`, `scripts/…`,
`CLAUDE.md`). In a corporate install the installed copies of the commands and templates
are rewritten to the `.belay/` form at install time, so the agent always follows the
right paths — only paths *you* type by hand need translating. Where a difference is more
than a prefix, the section says so.

## Installing

**Requires bash 4 or newer**, plus `git` and `jq` (or `python3`). Stock macOS ships bash
3.2, which cannot run the installer — `brew install bash` and make sure it comes first on
`PATH`. Linux distributions have shipped bash 4+ for over a decade.

### Into a new (empty or nearly-empty) repo

```
git init my-project           # if not already a repo
./install.sh my-project
cd my-project && claude
> /bootstrap-project <paste or point to your requirements>
```

### Into an existing codebase

```
./install.sh /path/to/repo
cd /path/to/repo && claude
> /adopt-project
```

Then answer the "Decisions needed" section of `docs/adoption-report.md` — those answers
become real ADRs — and start with `/plan-feature <first change>`.

A large repo will not be adopted in one session, and that is fine: `/adopt-project`
writes `docs/adoption-report.md` as it goes (progress checklist + findings) and
`docs/constraints.md` module by module. When context or quota runs out, re-run
`/adopt-project` in a fresh session — it reads the log and resumes at the first
unfinished step, re-reading nothing it already surveyed.

### Into a corporate / shared repo (no-touch mode)

```
./install.sh /path/to/repo --corporate      # add --cursor for Cursor wiring too
cd /path/to/repo && claude
> /adopt-project
```

Then, as in any adoption, answer the "Decisions needed" section of the adoption report —
here `.belay/docs/adoption-report.md` — and start with `/plan-feature <first change>`.
Re-running `/adopt-project` in a fresh session resumes where it stopped, same as above.

For repos where you may run agents but may not modify the company's agent docs or
commit workflow files. Two guarantees, both checked by the installer itself:

- **No tracked file is ever modified.** `CLAUDE.md`, `AGENTS.md` and `.cursor/rules/*`
  are never touched — `/adopt-project` writes its pointer doc to `CLAUDE.local.md`
  (auto-loaded by Claude Code alongside `CLAUDE.md`) and, under `--cursor`, to
  `.cursor/rules/belay.mdc`; the `AGENTS.md` symlink is skipped, and no `.pre-belay`
  backup is written because nothing is overwritten. A tracked
  `.claude/settings.json` is never merged (wiring goes to `.claude/settings.local.json`),
  and a tracked `.cursor/hooks.json` or any tracked file colliding with an installed one
  is skipped with manual-merge instructions.
- **Nothing installed appears in `git status`.** Workflow state lives under `.belay/`
  (the `docs/` + `scripts/` tree relocates there), and every installed path is listed in
  a marked block in `.git/info/exclude`. The installer fails loudly if `git status`
  changed at all between start and finish.

Excluded files are invisible to `git ls-files`, so the repo index never picks up
workflow files either — git containment and index hygiene are the same mechanism.

The block has two sections, because containment and uninstall want opposite grains.
**Containment** excludes `/.claude/` and `/.cursor/` whole: those directories hold no
tracked files, so a single unlisted file under one of them makes git collapse the lot to
`?? .claude/` and expose the entire tree. Excluding them wholesale is safe for the
company — exclude rules never apply to *tracked* paths, so their versioned
`.claude/settings.json` keeps reporting its changes exactly as before; only new untracked
files there become invisible, and `git add` still warns if you try to stage one.

**Uninstall:** the second section lists every installed path one by one. Delete exactly
those, then the block — never the two directories from the first section, which also hold
company files. One exception, marked in place: a path preceded by `# merged:` existed
before belay and was only merged into (a `.claude/settings.local.json` or
`.cursor/hooks.json` you already had) — leave those. Belay decides created-vs-merged on
the first install and carries the verdict forward in the manifest, so a re-install never
mistakes its own file for yours. The company repo never knew.

**Both mode switches are refused.** Re-running `install.sh` without `--corporate` on a
corporate install would write `docs/` into the repo; running it *with* `--corporate` on a
normal install would leave two state trees and flip the mode marker while failing its own
no-touch check. Either way the install stops before writing, and names the manual route.
`CLAUDE.local.md` is deprecated upstream but still auto-loaded; if it ever stops loading,
import the `.belay/docs/` state from your user-level memory file instead.

**Verify the pointer docs actually load — once per environment.** After the first
`/adopt-project`, run `/context` in Claude Code and confirm `CLAUDE.local.md` is listed
among the loaded context; under `--cursor`, confirm `.cursor/rules/belay.mdc` shows as
an active rule in Cursor's settings. If either stops loading (a client update dropping
`CLAUDE.local.md` support is the realistic risk), everything keeps *running* but the
agent silently loses the pointer to the workflow state — nothing else will tell you.

Smoke test: run `tests/corporate-smoke.sh` from the package repo. It builds a hostile
scratch repo (tracked `CLAUDE.md`, tracked `.claude/settings.json` and `docs/`, a tracked
homonymous command, a pre-existing `settings.local.json`), installs with
`--corporate --cursor`, and asserts the no-touch guarantees, path rewriting, idempotence,
both mode guards, tracked-file skips, orphan reaping, the created-vs-merged manifest
marking, agent-doc canonicalization, the install registry, plus a normal-mode regression.
Despite the name it covers the whole package: the index generator (paths with spaces,
source-free repos), toolchain gap detection, and the edit gates (a formatter that rewrites
the file must say so; both gates must fail closed with no JSON parser).

Three asserts are **documentation consistency** rather than behaviour — the status
vocabulary must match across the files that define it, every `§Section` a command or
template points at must exist in `constraints.md`, and both entry commands must handle the
`CLAUDE.md` workflow variants. That class of bug ("two files say different things") is what
an audit finds and no behavioural test can, so it fails the suite instead.

### Cursor CLI / IDE

```
./install.sh /path/to/repo --cursor
```

Installs everything above **plus** Cursor wiring, so the same repo works from Claude
Code and from Cursor (`cursor-agent` or the IDE):

- The nine commands are copied to `.cursor/commands/` — same slash commands, same
  markdown. Cursor doesn't substitute `$ARGUMENTS`/`$1`; it appends the argument text
  to the prompt, which the commands' own "Arguments:" sections already make clear.
- `.cursor/hooks.json` routes `afterFileEdit` and `beforeShellExecution` through
  `.claude/hooks/cursor-adapter.sh`, which runs the same three hooks. The commit
  security gate blocks for real (`permission: deny`); the post-edit gates are advisory
  only, because Cursor ignores `afterFileEdit` output — the fix-it-same-turn loop is
  weaker there, and `/validate-phase` remains the hard gate.
- `AGENTS.md` is symlinked to `CLAUDE.md` (Cursor reads `AGENTS.md`), so there is one
  source of truth for both agents. See below for what happens when the repo already has
  agent docs. **Corporate mode does neither:** `AGENTS.md` is a company file, so no
  symlink is created — the entry command writes an `@AGENTS.md` import at the top of
  `CLAUDE.local.md` instead, and the Cursor pointer is `.cursor/rules/belay.mdc`, also
  written by the entry command — see "Existing CLAUDE.md / AGENTS.md" below.

### Gating your own commits too (`--git-hook`)

```
./install.sh /path/to/repo --git-hook
```

Every gate belay installs is an **agent** gate. `pre-commit-security.sh` is wired as a
`PreToolUse` hook, so it sees the Bash commands the agent runs and nothing else — a
person typing `git commit` in a terminal is not covered by any of it. That surprises
people who plant a test secret, commit it by hand, and watch it sail through.

`--git-hook` writes `.git/hooks/pre-commit`, a locator that execs
`scripts/check.sh --staged`. That runs the file gates over every staged file and then the
commit gate — the same scripts the agent path runs, not a parallel implementation. Opt-in
on purpose: it is the only part of the install that changes what happens when *you*
commit, so a re-install never starts blocking you silently.

Because the file gates run formatters, a formatter that rewrites a staged file **blocks
the commit**: what you staged is no longer what is on disk. Re-stage and commit again —
the message names the files.

- **Never clobbers someone else's.** If a `pre-commit` hook exists that belay did not
  write, it is left byte-identical and the single line to append is printed instead.
  Belay's *own* hook is refreshed on re-install, which is how a change to what it runs
  reaches a repo that is already installed.
- **Honours `core.hooksPath`**, so husky/lefthook repos get it in the directory git
  actually runs.
- **Fails open.** If `.claude/hooks/` disappears, the hook exits 0 — uninstalling belay
  must never brick every commit in the repo, so a leftover hook is harmless.
- `git commit --no-verify` skips it, and `.git/hooks/` is per-clone: this covers *you*,
  not the team. Team-wide, unbypassable coverage is a CI job, not a local hook.

### Existing CLAUDE.md / AGENTS.md

One rule, six states: **`CLAUDE.md` is the real file, `AGENTS.md` is a symlink to it or
absent, and every agent doc that existed before is merge input with a write-once backup
in `.claude/workflow/<name>.pre-belay`.** It applies in every normal install, with or
without `--cursor` — if `AGENTS.md` exists, something reads it (Codex, Copilot, the
Cursor IDE); `--cursor` only decides whether the symlink is *created* when nothing was
there. The installer never rewrites either file (the merge needs an entry command); the
work happens in `/adopt-project` step 9 / `/bootstrap-project` step 8.

| Before install | After the entry command |
|---|---|
| neither | `CLAUDE.md` real; `AGENTS.md` symlink if `--cursor` |
| only `CLAUDE.md` | backed up, merged in place |
| only `AGENTS.md` (real file) | backed up, folded into a real `CLAUDE.md`; `AGENTS.md` → symlink |
| both real, divergent | both backed up, both merge input, one `CLAUDE.md`; `AGENTS.md` → symlink |
| `AGENTS.md -> CLAUDE.md` already | unchanged shape; `CLAUDE.md` backed up and merged |
| `CLAUDE.md -> AGENTS.md` (reversed) | **install refuses** — writing `CLAUDE.md` would clobber the symlink's target; resolve it, then re-run |

Backups are write-once, so re-running `/adopt-project` keeps the true pre-belay original
rather than a copy of what belay wrote last time. They live under `.claude/workflow/`, so
they land in the adoption commit — the pre-adoption doc stays as history.

**Corporate mode never does any of this.** `CLAUDE.md` and `AGENTS.md` are read-only
input in all six states: nothing is created, modified, moved, or backed up (there is
nothing to back up — belay writes `CLAUDE.local.md`).

Dropping the symlink would drop the *company's* rules on the floor: Claude Code reads
`CLAUDE.md`, not `AGENTS.md`, so on an `AGENTS.md`-only repo a session would see neither
file. The substitute is an import, not a symlink — when `AGENTS.md` exists and isn't
already the same file as `CLAUDE.md`, the entry command makes `@AGENTS.md` the first line
of `CLAUDE.local.md`. Claude Code expands it at launch, the path resolves inside the
working directory so there is no external-import prompt, and `CLAUDE.local.md` is
git-excluded, so no company-owned file is touched.

Known gap, by design: a corporate install *without* `--cursor` on a repo that does use
Cursor gets no `.cursor/rules/belay.mdc`, so Cursor only sees the company's `AGENTS.md` and
never learns about the workflow — pass `--cursor` if that repo is driven from Cursor.

All state (`.claude/workflow/`, `docs/`) is shared — sessions from either agent
converge on the same files (P6/P8). Cursor's hooks are beta; if an event name or
payload field changes upstream, only `cursor-adapter.sh` needs updating.

**If Cursor hooks stop firing at all**, check the command path first, before the payload:
`.cursor/hooks.json` names the adapter relatively (`./.claude/hooks/cursor-adapter.sh`),
Cursor's documented form, resolved against the project root by Cursor itself. The adapter
derives the project root from its own location rather than from `$PWD`, so it survives
being *executed* from elsewhere — but nothing it does can compensate for a command that was
never resolved. Symptom: no hook output anywhere, in contrast to a payload change, which
shows up as hooks running but seeing no file path.

### Updating an installed project

```
cd <this repo> && git pull
./install.sh /path/to/repo          # repeat the flags it was installed with
```

Re-installing is the upgrade: commands, hooks, templates, the index script and belay's
hook wiring are replaced with the current package; project state (`CLAUDE.md`, `docs/`,
`boundaries.rules`, `toolchain.json`) is untouched.

Re-installing also *removes* package-owned files the package no longer ships, in both
modes. `install.sh` records every path it writes in `.claude/workflow/installed` and
compares it against the previous run's copy, so a command or hook deleted upstream is
deleted from the target — never anything the repo tracks, and never `.cursor/` files when
the re-install omitted `--cursor`. A dropped *hook* was already harmless (its wiring is
dropped, so nothing ran it); a dropped *command* was not — it stayed a live slash command
forever. In corporate mode the same reap keeps the uninstall manifest honest and stops an
orphan un-hiding the directory it lives in.

That file doubles as the **uninstall list for a normal install**: delete the paths it names,
then `.claude/workflow/` and belay's hook entries in `.claude/settings.json`. A
`--git-hook` install also leaves `.git/hooks/pre-commit` behind — it is outside the
working tree, so no manifest lists it, and it fails open once `.claude/hooks/` is gone.
Delete it for tidiness, not for correctness.

Knowing *which* projects are behind is the package's job, not the project's. `install.sh`
records every target in `~/.claude-belay/installs`, and opening a Claude session in this
repo lists the installs whose `.claude/workflow/belay-version` stamp is older than HEAD
(SessionStart hook → `scripts/installs-stale.sh`, silent when everything is current; run
it by hand any time). Nothing new runs inside the consuming projects: the package may not
exist on that machine, an update applied mid-session would mutate the gates the session is
being judged by (P3), and corporate installs must stay no-touch.

Same single-machine caveat as the feedback loop — the registry lives under `$HOME`. Paths
that no longer hold an install are skipped silently; the registry is never pruned, so
delete lines by hand if it gets noisy.

### What to customize vs leave alone

**Customize (project-owned):** `.claude/workflow/boundaries.rules` (via the entry
command + ADRs), `.claude/workflow/toolchain.manual.json` (commands detection missed
or got wrong), `CLAUDE.md`, everything under `docs/` except `docs/index/` and
`docs/templates/`.

**Leave alone (package-owned, overwritten on re-install):** `.claude/hooks/*`,
`.claude/commands/*`, `scripts/build-index.sh`, `docs/templates/*`, `docs/index/*`
(generated), and belay's own hook entries in `.claude/settings.json`. If a hook
misbehaves, fix it in the package and re-run `install.sh`, or you'll lose the fix at the
next upgrade.

`.claude/workflow/toolchain.json` belongs in that second list for a different reason:
the installer never touches it, but **detection rewrites it whole** — `/refresh-index`
re-runs `detect-toolchain.sh`, which emits the file from scratch. A command added there
by hand survives until the next re-detection and then vanishes without a word. Put it in
`toolchain.manual.json` instead; nothing in the package writes that file.

Hook *wiring* is package-owned as well: on every re-install, any entry whose command
points into `.claude/hooks/` is dropped and replaced by the package's current wiring —
which is how a hook added upstream reaches a project that is already installed, and how
wiring for a hook deleted upstream disappears. Every other entry in the file is
preserved, so your own hooks are safe **as long as their scripts do not live in
`.claude/hooks/`**. This step needs `jq`; without it the wiring is left alone and the
installer says so, naming the hooks that are missing.

Corporate mode: same split, relocated — project-owned becomes `CLAUDE.local.md` and
everything under `.belay/docs/` except `.belay/docs/templates/` and `.belay/docs/index/`;
package-owned adds `.belay/scripts/build-index.sh`.

### When your stack isn't detected

`detect-toolchain.sh` recognises seven stacks by marker file (`package.json`,
`pyproject.toml`, `go.mod`, `Cargo.toml`, `ProjectSettings/ProjectVersion.txt`,
`project.godot`, `*.uproject`) and, inside each, a closed list of tools. It is a pool,
not a search: a stack or a linter it has never heard of produces a `gaps` entry, not a
guess. Three rungs, stop at the first that holds.

**1. A `Makefile` with `test:` / `lint:` targets.** Already covered — detection falls
back to `make test` / `make lint` for any category still empty, whatever the stack. The
cheapest fix for an unrecognised stack is often a two-line Makefile.

**2. `.claude/workflow/toolchain.manual.json`.** Same keys as the generated file, and
only the ones you need. Commands here win over detected ones; `exempt` is appended to
what detection found, not substituted for it.

```json
{
  "commands":      { "test": "mix test", "lint": "mix credo --strict" },
  "file_commands": { "ex": { "format": "mix format {file}" } },
  "exempt":        ["priv/static/"]
}
```

`commands` are project-wide and run at `/validate-phase`. `file_commands` run on every
edit, so they must accept a single file — `{file}` is substituted, or the path is
appended if the template has no placeholder. Nothing in the package writes this file:
it survives `/refresh-index` and re-installing belay.

**3. Upstream it.** Once the same stack shows up in a second project, a detection block
belongs in the package rather than in two manual files that will drift. `CLAUDE.md` in
[the belay repo](https://github.com/Palanx/Claude-Belay) has the recipe and the real
cost of each case.

### Methodology (skills and house rules)

This package has no opinion on TDD, SOLID, or any other method — it supplies gates and
state, you supply the method. If you carry your own engineering or architecture rules as
Claude Code skills, those live in *your* home directory, so a project that depends on them
is depending on a channel the repo can't see. `/expand-phase` would write a spec whose Plan
assumes them, and the next session — a teammate, another machine, Cursor — would implement
against that spec without them. That breaks the closure test (P5) and P6 in the same move.

So the entry commands harvest them once: `/bootstrap-project` and `/adopt-project` read the
methodology skills active in the session, draft the rules that apply to *this* project, show
you the draft, and write what you confirm into `docs/constraints.md`, ADRs, and
`.claude/workflow/boundaries.rules`. Always as self-contained prose, never as a skill name —
the repo keeps the rule, not the dependency. Greenfield takes them as the convention source
(there's no code to observe yet); an adopted project lets the code win, and a skill rule that
contradicts the observed convention becomes a question in `docs/adoption-report.md` instead.

**When you add a skill later**, nothing fires automatically and nothing should — it's a rare
event, not a workflow step. Say it in session once ("I added skill X; what in it applies
here?"), then:

1. Every rule that changes how this project is built gets an **ADR** (`docs/adr/`, status
   `accepted`). If it replaces an earlier decision, the old ADR is marked superseded — never
   edited.
2. Its standing form goes to `docs/constraints.md`, in the section it belongs to.
3. If it's a layer edge, it also goes to `.claude/workflow/boundaries.rules` — which already
   requires that superseding ADR, per the shipped `CLAUDE.md`.
4. If it can be a command with an exit code, it becomes an acceptance criterion in the next
   `spec.md`, or an invariant naming its `enforced by`. A rule that is neither a deny edge
   nor a checkable command is a preference, not a constraint — write it down as such.
5. Existing code that violates the new rule does **not** get fixed in passing: that's a phase
   via `/plan-feature`, or a recorded contradiction. Same rule adoption already follows.

**A finding is a fourth thing, and it is not a rule.** An expensive, verified fact about how
the code *is* — where the obvious reading is wrong, and establishing it cost real work — goes
to `docs/constraints.md` `§Observed conventions` with its reference file and the date it was
checked. It never becomes an ADR: an ADR carries a `status` and is immutable, a finding has
neither and stops being true the moment someone edits the code. Findings filed as ADRs corrupt
`/plan-feature`, which reads ADR titles and status lines to decide what constrains a feature —
a directory mixing decisions with facts can no longer answer "what binds me". Nor is it tech
debt: debt is a defect left in place on purpose, and belongs to whatever debt log the project
keeps.

Wherever it lands, it lands **once**. A project that keeps path-scoped rule files
(`.claude/rules/*.md` with `paths:`, `.cursor/rules/*.mdc` with `globs:`) has a better home
for a domain-scoped finding than `constraints.md` does — those attach while the matching code
is being edited, which is the only moment the fact is worth anything, and `constraints.md` is
read whole and read late. Put it there and give it a pointer-table row in `CLAUDE.md`, so a
session planning a feature can still reach it; never a copy in both. Authoring those files is
method, so by the paragraphs above it is yours, not the package's — belay says which category
the fact is, that it lands once, and what it must not become.

### Verifying the install (smoke test)

Run from the target repo root — every step states its expected outcome:

```bash
# 1. Hook syntax + wiring
# Corporate installs wire settings.local.json instead of settings.json; both are checked.
bash -n .claude/hooks/*.sh .claude/hooks/lib/*.sh        # expect: silence
SET=.claude/settings$([ -e .claude/workflow/corporate ] && echo .local).json
jq . "$SET" >/dev/null && echo wiring-ok                 # expect: wiring-ok

# 2. Toolchain detection runs and reports honestly
.claude/hooks/lib/detect-toolchain.sh                    # expect: "toolchain written ...", stacks + gaps listed

# 3. Post-edit gate fires (simulated hook call — same stdin Claude Code sends)
echo '{"tool_name":"Edit","tool_input":{"file_path":"'$PWD'/README.md"}}' \
  | .claude/hooks/post-edit-gate.sh; echo "exit=$?"      # expect: exit=0 (docs are exempt)

# 4. Security gate blocks a planted secret
git checkout -b smoke-test 2>/dev/null || git switch -c smoke-test
echo 'aws_key = "AKIAIOSFODNN7EXAMPLE"' > smoke.txt && git add smoke.txt
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
  | .claude/hooks/pre-commit-security.sh; echo "exit=$?" # expect: COMMIT BLOCKED ... exit=2
git rm -f --cached smoke.txt && rm -f smoke.txt

# 4b. Protected-branch guard blocks a commit on a listed branch (opt-in feature)
echo '^smoke-test$' > .claude/workflow/protected-branches
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
  | .claude/hooks/pre-commit-security.sh; echo "exit=$?" # expect: COMMIT BLOCKED ... exit=2
rm .claude/workflow/protected-branches

# 5. Index builds and self-reports freshness (corporate: .belay/scripts/, .belay/docs/index)
BI=$([ -e .claude/workflow/corporate ] && echo .belay/)scripts/build-index.sh
"$BI"                                                    # expect: "index written: ... /index (...)"
"$BI" --check                                            # expect: "index fresh (<hash>)"

# 6. Gate runner works from a plain shell (no agent involved)
CK=$([ -e .claude/workflow/corporate ] && echo .belay/)scripts/check.sh
"$CK"                                                    # expect: per-category PASS lines, or "workflow gap:" for unconfigured ones

# 7. Commands are visible
claude                                                    # then type /  — expect the nine workflow commands listed
```

Step 4's exit=2 is the whole point of the package: a wrong action was cheaply,
deterministically caught. If any step's expectation fails, the install is broken — do
not proceed to real work.

## The commands

| Command | Purpose | Writes |
|---|---|---|
| `/bootstrap-project [requirements]` | Greenfield entry point — interviews until the requirements actually close, then turns them into project state | `requirements.md`, `constraints.md`, ADR-0001+, `PHASES.md`, `boundaries.rules`, `toolchain.json`, `CLAUDE.md`, `docs/index/` |
| `/adopt-project` | Existing-codebase entry point — infer stack, layering, conventions and decisions from the code. Resumable: re-run it after a session runs out of context and it continues where it stopped | same as bootstrap, plus `adoption-report.md` (progress log + contradictions + decisions needed); ADRs are marked `reconstructed` |
| `/plan-feature <description>` | Feature request → rows in the phase index. Converges on the scope edge and non-goals first, and records them. Stops if the feature contradicts a recorded ADR | `docs/phases/PHASES.md` (feature section: blurb + rows, status `pending`) |
| `/expand-phase <phase-id>` | One index row → a full spec, written *just in time*, absorbing what the dependency phases revealed | `docs/phases/<id>/spec.md`; status → `expanded` |
| `/implement-phase <phase-id> [--implemented]` | Do exactly that phase against its spec, inside the hooks. `--implemented`: the operator wrote the code by hand — skip implementation, interview for the record, so the phase can still be validated | the source files in the spec's Plan (none with `--implemented`), the Plan's step-status text in `spec.md` when the project keeps one, `docs/phases/<id>/notes.md`; status → `in-progress` |
| `/validate-phase <phase-id>` | Run the spec's acceptance criteria, the project-wide gates, an independent review by a subagent that sees only the spec and the diff, and the closure test | validation record appended to `notes.md`; status → `done` **only** on a clean pass |
| `/refresh-index` | Rebuild the repo index, re-detect the toolchain, report doc/code drift | `docs/index/`, `toolchain.json` |
| `/security-check [path]` | Advisory security review — the reasoning companion to the enforced commit gate | `docs/security/review-<date>.md` |
| `/belay-feedback <what misbehaved>` | Send a gate/command bug back to this package with verbatim repro data | `~/.claude-belay/feedback/<project>.md` |

The loop: `/plan-feature` **once per feature**, then `/expand-phase → /implement-phase →
/validate-phase` **per phase** until every row is `done`. A failed validation is not an
exception — it hands the failing command's output back to `/implement-phase`, which fixes
and returns. Each command's own file (`.claude/commands/*.md`) states its preconditions,
what it reads, and its failure modes.

Three of the behaviours above are borrowed from the [Superpowers](https://github.com/obra/superpowers)
plugin, adapted to run inside gates rather than as advice:

- **Converge before structuring.** `/plan-feature` and `/bootstrap-project` interview until
  the scope edge and non-goals are actually closed, not merely answered. The exit condition
  is closure — "nothing out of scope", or a capability nobody can state an acceptance
  criterion for, is an unanswered question wearing a section heading.
- **The answers have to land.** `/plan-feature` writes the converged scope into the feature
  section's blurb, which is what `/expand-phase` reads to fill a spec's "Out of scope". A
  conclusion that stays in the session is a conclusion the next session re-derives or gets
  wrong (P6).
- **Review by an agent that did not do the work.** `/validate-phase` dispatches one subagent
  with the spec and the diff and nothing else — deliberately starved, because a reviewer who
  knows what you meant cannot see that the spec never said it. It returns two verdicts:
  *contradicts* (a conflict; the running session decides which side is stale — code back to
  `/implement-phase`, spec amended like an *undecidable*) and *undecidable* (spec bug, the
  closure test fails). Taste is not a verdict; it goes to notes, never blocks, so the gate
  stays deterministic (P3).

**Read this next:** [`docs/worked-example.md`](docs/worked-example.md) — one non-trivial
feature end to end on a real Node/SQLite codebase: adoption, an ADR conflict surfaced
during planning, the phase index, a spec, a hook failure and its recovery, and validation.
Every artifact is shown as it lands on disk.

## Lightweight mode (hand-driven projects)

The full phase pipeline assumes the agent implements whole features across sessions. If
you drive the project by hand and only ask Claude for advice, planning, and small
changes, skip the pipeline and keep the safety net:

```
./install.sh /path/to/repo        # same install, no separate mode
cd /path/to/repo && claude
> /adopt-project                  # (or /bootstrap-project on a new repo) — builds index, constraints, toolchain
```

Say so when the entry command asks which way you'll work: it writes the **lightweight
variant** of `CLAUDE.md` instead of the pipeline one — same file, same pointer table, minus
the phase sections. That matters because `CLAUDE.md` is loaded every session, so a
hand-driven project carrying pipeline instructions tells every session to run a workflow
you opted out of. Switching later is editing that one section; the pipeline stays installed
regardless.

Then:

**Use:** the hooks (they gate a 3-line edit the same as a phase, and the commit guard
also catches your own manual commits made through Claude), `docs/index/` + `CLAUDE.md`
(cheap correct context for "what do you think of X" sessions), `docs/constraints.md` and
ADRs (record the decisions you make by hand so Claude stops proposing against them, and the
findings a session paid for under `§Observed conventions`, so the next session doesn't pay
again), and `/security-check` whenever.

**Skip:** `/plan-feature → /expand-phase → /implement-phase → /validate-phase`. For
small asks, plain prompts are enough — the hooks still fire. The pipeline stays
installed; pick it up the day you hand over a full feature.

**Not the same as `--implemented`.** Lightweight mode opts out of the pipeline;
`/implement-phase <id> --implemented` stays *inside* it for a phase whose code a human
wrote — the spec, the gates and `done` all still apply, only the typing was manual. Use it
when the pipeline is right but the work isn't reachable from a shell (Editor-bound test
runners, GUI-authored assets) or simply had to be done by hand. Common in corporate repos,
where much of the code is human-written; without it such a phase can never reach `done`,
because `notes.md` — `/validate-phase`'s precondition — has exactly one writer.

**Working from a written plan.** A human implementing a phase reads a spec written for a
cold session: dense, pointer-based, verification batched at the end. Expanding it into
numbered steps to execute over days is reasonable, under one rule — the spec stays the
authority. `/validate-phase` judges the diff against `spec.md`, never against a derived
plan, so the derivation runs one way and the plan is disposable: when reality diverges,
amend the spec and regenerate the plan whole rather than patching the plan to match. A
half-regenerated plan is the second, drifting document `docs/templates/spec.md` already
tells you not to create.

The byproduct is the useful part. Anything the plan had to invent to be executable — a
file it went looking for, an ordering constraint, a check the spec never stated — is a
missing Context pointer. Found here it is nearly free: the phase is still `expanded`,
nothing has been built against the old spec and no `notes.md` exists yet, so the fix is an
edit and a regenerated plan. The same gap found later arrives as an `undecidable` verdict
in `/validate-phase` step 5, and by then the amendment travels with the `notes.md`
Deviations entry that every mid-implementation spec change requires — the rule is in
[`commands/implement-phase.md`](commands/implement-phase.md), with the closure-test side in
[`commands/validate-phase.md`](commands/validate-phase.md). Pedagogy is not a gap: how a
person physically performs a step belongs in the plan and nowhere else, and moving it into
the spec only bloats the starved reviewer's input.

Nothing here ships with the package and nothing looks for it. One implementation is the
`planning` skill in [Palanx/Claude-Configs](https://github.com/Palanx/Claude-Configs);
like any skill it lives in a home directory, so *Methodology* above applies — it is yours,
not the repo's.

**One obligation:** the index only maintains itself when Claude edits. Since most
changes are yours, run `/refresh-index` (or `scripts/build-index.sh --check` — under
`.belay/scripts/` in a corporate install — to test staleness) after hand-made changes of
any substance, or sessions will plan against a stale map.

Corporate installs (`--corporate`) compose naturally with this mode — safety net +
index without the pipeline is the common corporate case.

## The enforcement layer

**One contract:** a gate takes file paths and returns an exit code. It parses no payload
and reads no stdin. Adapters translate an agent's hook payload into that call — they are
the only files here that touch JSON. So the agent, you, the git hook and CI all run the
same script for the same reason, and there is no per-caller variant to keep in sync.

| Gate | What it does |
|---|---|
| `post-edit-gate.sh <file>` | runs whatever `toolchain.json` has for that file's extension — format, lint, and a file-scoped typecheck *where one exists* (several stacks have none: Node/TS typechecks project-wide only, Unity and Unreal not at all — `gaps` names each). Exit 2 returns the failure on stderr |
| `boundary-check.sh <file>` | grep-heuristic check of `boundaries.rules` deny edges on that file. Exit 2 returns the violation on stderr; exit 0 means no violation **or** no rule covering the file — including the fresh-install state where the rules file is still commented out |
| `pre-commit-security.sh` | no arguments: protected-branch guard (opt-in via `.claude/workflow/protected-branches`, one anchored regex per line) + secret scan of staged changes (gitleaks or builtin patterns) + dependency audit when dependency files are staged. **Exit 2 means do not let this commit happen.** Corporate mode: also blocks commits while any belay state path shows in `git status` |

| Adapter | Event | Calls |
|---|---|---|
| `edit-gate-adapter.sh` | `PostToolUse`, matcher `Edit\|Write` | both file gates on the edited path. PostToolUse cannot block — the edit already happened — so exit 2 returns stderr to Claude for same-turn fixing, which is the design (P3) |
| `bash-gate-adapter.sh` | `PreToolUse`, matcher `Bash` | decides whether the command is a `git commit` and, if so, runs the commit gate; **exit 2 blocks it**. Corporate mode: also blocks `git clean -x/-X`, which would erase the git-excluded belay state |
| `cursor-adapter.sh` | Cursor `afterFileEdit` / `beforeShellExecution` | the same two paths, mapped onto Cursor's permission protocol |

**Running them yourself — `scripts/check.sh`:**

```bash
scripts/check.sh                    # project-wide: test, lint, typecheck
scripts/check.sh lint audit         # only these categories
scripts/check.sh --files src/a.ts   # the file gates, on paths you name
scripts/check.sh --staged           # the file gates on staged files + the commit gate
```

Categories come from `toolchain.json`, so `check.sh` and `/validate-phase` run the same
commands by construction. `--staged` is what the `--git-hook` pre-commit hook executes.
Exit 1 if anything failed; an unconfigured category is a loud `workflow gap:` line, not a
failure.

The toolchain-driven gates read `.claude/workflow/toolchain.json`, with
`.claude/workflow/toolchain.manual.json` consulted first where it exists, and never skip
silently: a missing tool category produces a loud `workflow gap:` line naming the fix (P7).

**CI: belay does not write one, in any mode.** Most of a CI file is not belay's —
runner, triggers, caching, matrix, secrets, your existing jobs — and `check.sh` is one
line of it. Write your own job and call it:

```yaml
- run: ./scripts/check.sh          # .belay/scripts/check.sh in a corporate install
```

Local hooks are per-clone and `--no-verify` skips them. CI is the layer that actually
holds for everyone.

## Feedback loop (consuming project → package)

Hooks and commands are copies; a bug or friction point found while *using* them in a
project dies with that session unless it travels back here. The return channel:

1. In the consuming project, when a gate misfires or a workflow step grates, run
   `/belay-feedback` (the shipped `CLAUDE.md` tells Claude to offer it proactively). It
   appends a structured entry — component, package version, **verbatim** repro data
   (hook stderr, offending lines, config excerpts) — to
   `~/.claude-belay/feedback/<project>.md`.
   `/validate-phase` also names an upstream cause on its own report line when the
   misbehaving file is one the install manifest lists — the phase still closes on its
   workaround; the entry is what stops the next project rediscovering it.
2. `install.sh` stamps `.claude/workflow/belay-version` into every target, so each entry
   names the exact package commit it observed.
3. Opening a Claude session in *this* repo lists all open entries automatically
   (SessionStart hook → `scripts/feedback-pending.sh`) with pointers to the repro data —
   the fixing session starts loaded.
4. Fix here, flip the entry to `status: resolved (<commit>)`, re-run `install.sh` in the
   consumers — the same SessionStart lists which of them are still on the old commit
   (see [Updating an installed project](#updating-an-installed-project)).

Single-machine by design (the store is under `$HOME`); if feedback must cross machines,
file it as an issue on this repo instead.

## The repo index (`docs/index/`)

Generated markdown, one file per module plus `_overview.md` (module table, heuristic
dependency edges, entry points), stamped with the commit it was built at.
Regenerate: `scripts/build-index.sh` (or `/refresh-index`). Staleness:
`scripts/build-index.sh --check` — run automatically by `/plan-feature`,
`/validate-phase`, `/refresh-index`. It compares the working tree as well as the commit
stamp: uncommitted source edits count as stale, because HEAD does not move during a phase
and a commit-only check reports a drifting index as fresh. Corporate: `.belay/scripts/build-index.sh`, output
in `.belay/docs/index/`.

Format reasoning: markdown-per-module was chosen over a single JSON/SQLite artifact
because the three consumers are a session loading *one section* (P1), a human reviewing
a diff, and git storing it. Traded away: machine-precise symbol/reference data (symbols
come from universal-ctags when installed, else a declaration-keyword grep). The index's
job is to let a session *locate* the right files without blind search — precision beyond
that would cost regeneration speed and diff noise without changing any decision.

## Non-goals

- Not CI/CD. Belay never writes a CI file into a project, in any mode: most of such a
  file is not belay's, and `scripts/check.sh` is one line of it. Call it from your own
  job — see the enforcement layer above.
- Not tied to any language, framework, or cloud.
- Not project management — `PHASES.md` tracks execution state, never people or dates.

**Deliberately not built: a command that turns a decision into an ADR.** Two places hand the
operator a question and then stop — `/adopt-project`'s "Decisions needed" and `/plan-feature`'s
ADR conflict. Both now name where the answer lands (a new ADR, next number, status `accepted`,
superseding rather than editing), and the adoption report carries that routing in the file
itself so the session that answers reads it. Nothing automates the write. That is on purpose:
it happens a handful of times per project, the `adr.md` template already exists, and the
shipped `CLAUDE.md` already says decisions that constrain the future get an ADR — so telling
the agent works. A `/decide` command would be an abstraction with two call sites and no gate
behind it. If the practice proves otherwise, the evidence will be answered questions sitting
in `adoption-report.md` with no matching ADR; that is the signal to build it, not before.

## License

MIT — see [`LICENSE`](LICENSE).

Worth stating explicitly because of how this package is used: `install.sh` **copies**
package-owned files into your repository — `.claude/hooks/`, `.claude/commands/`,
`docs/templates/`, `scripts/build-index.sh`, and the Cursor mirrors under `.cursor/`
(all relocated under `.belay/` in a corporate install). Those copies carry MIT with them
into whatever repository they land in, including a private or corporate one. Re-run the
installer and they are replaced; the license on them does not change.

Everything the copies then *produce* is yours and is not covered by this license: your
`CLAUDE.md`, `docs/product/`, ADRs, phase specs and notes, `constraints.md`,
`boundaries.rules`, `toolchain.json`, the generated index. The split is not a judgment
call — `.claude/workflow/installed` records every path the installer wrote, so that file
is the exact list of what arrived under MIT. Anything not in it, belay did not put there.
