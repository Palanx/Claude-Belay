# Claude Belay

[![Claude Code](https://img.shields.io/badge/Claude%20Code-workflow%20package-D97757?logo=anthropic&logoColor=white)](https://claude.com/claude-code)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](install.sh)
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
| P7 | Detect, don't assume, the toolchain | `detect-toolchain.sh` writes `toolchain.json`; gaps are loud |
| P8 | One pipeline, two entry points | `/bootstrap-project` and `/adopt-project` converge on the same *pipeline* state — every command downstream reads the same files either way (the two differ only in what only one of them can know: requirements vs an adoption report) |

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
```

Corporate mode (`--corporate`): the `docs/` and `scripts/` trees above live under
`.belay/`, the pointer doc is `CLAUDE.local.md` instead of `CLAUDE.md`, hook wiring is
`.claude/settings.local.json`, and all of it is hidden from git via `.git/info/exclude`.

## Installing

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
  agent docs.

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
nothing to back up — belay writes `CLAUDE.local.md`). Known gap, by design: a corporate
install *without* `--cursor` on a repo that does use Cursor gets no `.cursor/rules/belay.mdc`,
so Cursor only sees the company's `AGENTS.md` and never learns about the workflow — pass
`--cursor` if that repo is driven from Cursor.

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
then `.claude/workflow/` and belay's hook entries in `.claude/settings.json`.

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
command + ADRs), `.claude/workflow/toolchain.json` (only to add commands detection
missed), `CLAUDE.md`, everything under `docs/` except `docs/index/` and
`docs/templates/`.

**Leave alone (package-owned, overwritten on re-install):** `.claude/hooks/*`,
`.claude/commands/*`, `scripts/build-index.sh`, `docs/templates/*`, `docs/index/*`
(generated), and belay's own hook entries in `.claude/settings.json`. If a hook
misbehaves, fix it in the package and re-run `install.sh`, or you'll lose the fix at the
next upgrade.

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

### Verifying the install (smoke test)

Run from the target repo root — every step states its expected outcome:

```bash
# 1. Hook syntax + wiring
bash -n .claude/hooks/*.sh .claude/hooks/lib/*.sh        # expect: silence
jq . .claude/settings.json >/dev/null && echo wiring-ok  # expect: wiring-ok

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

# 5. Index builds and self-reports freshness
scripts/build-index.sh                                   # expect: "index written: docs/index (...)"
scripts/build-index.sh --check                           # expect: "index fresh (<hash>)"

# 6. Commands are visible
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
| `/implement-phase <phase-id>` | Do exactly that phase against its spec, inside the hooks | the source files in the spec's Plan, `docs/phases/<id>/notes.md`; status → `in-progress` |
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
  *contradicts* (code bug, back to `/implement-phase`) and *undecidable* (spec bug, the
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
ADRs (record the decisions you make by hand so Claude stops proposing against them), and
`/security-check` whenever.

**Skip:** `/plan-feature → /expand-phase → /implement-phase → /validate-phase`. For
small asks, plain prompts are enough — the hooks still fire. The pipeline stays
installed; pick it up the day you hand over a full feature.

**One obligation:** the index only maintains itself when Claude edits. Since most
changes are yours, run `/refresh-index` (or `scripts/build-index.sh --check` to test
staleness) after hand-made changes of any substance, or sessions will plan against a
stale map.

Corporate installs (`--corporate`) compose naturally with this mode — safety net +
index without the pipeline is the common corporate case.

## The enforcement layer

| Hook | Event (verified against docs) | What it does |
|---|---|---|
| `post-edit-gate.sh` | `PostToolUse`, matcher `Edit\|Write` | runs whatever `toolchain.json` has for the touched file's extension — format, lint, and a file-scoped typecheck *where one exists* (several stacks have none: Node/TS typechecks project-wide only, Unity and Unreal not at all — `gaps` names each). Failures return to Claude via stderr/exit 2 for same-turn fixing (PostToolUse cannot block — by design the edit gate is a feedback loop, the blocking gates are below) |
| `boundary-check.sh` | `PostToolUse`, matcher `Edit\|Write` | grep-heuristic check of `boundaries.rules` deny edges on the touched file |
| `pre-commit-security.sh` | `PreToolUse`, matcher `Bash` | on `git commit`: protected-branch guard (opt-in via `.claude/workflow/protected-branches`, one anchored regex per line) + secret scan of staged changes (gitleaks or builtin patterns) + dependency audit when dependency files are staged; **exit 2 blocks the commit**. Corporate mode: also blocks `git clean -x/-X` (would erase the git-excluded belay state) and blocks commits while any belay state path shows in `git status` |

The two toolchain hooks (`post-edit-gate.sh`, `pre-commit-security.sh`) read
`.claude/workflow/toolchain.json` and never skip silently: a missing tool
category produces a loud `workflow gap:` line naming the fix (P7).

**CI note (out of scope, one line):** mirror `pre-commit-security.sh` and the
project-wide toolchain commands in CI — hooks only guard actions taken through Claude
Code; manual commits and pushes need the same checks server-side.

## Feedback loop (consuming project → package)

Hooks and commands are copies; a bug or friction point found while *using* them in a
project dies with that session unless it travels back here. The return channel:

1. In the consuming project, when a gate misfires or a workflow step grates, run
   `/belay-feedback` (the shipped `CLAUDE.md` tells Claude to offer it proactively). It
   appends a structured entry — component, package version, **verbatim** repro data
   (hook stderr, offending lines, config excerpts) — to
   `~/.claude-belay/feedback/<project>.md`.
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
`/validate-phase`, `/refresh-index`.

Format reasoning: markdown-per-module was chosen over a single JSON/SQLite artifact
because the three consumers are a session loading *one section* (P1), a human reviewing
a diff, and git storing it. Traded away: machine-precise symbol/reference data (symbols
come from universal-ctags when installed, else a declaration-keyword grep). The index's
job is to let a session *locate* the right files without blind search — precision beyond
that would cost regeneration speed and diff noise without changing any decision.

## Non-goals

- Not CI/CD — hooks are local gates (see the CI note above).
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
