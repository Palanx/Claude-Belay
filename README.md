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
| P8 | One pipeline, two entry points | `/bootstrap-project` and `/adopt-project` converge on identical state |

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
├── commands/*.md                  # the eight slash commands
├── hooks/                         # post-edit-gate, boundary-check, pre-commit-security (+ lib/)
├── settings.json                  # hook wiring (PostToolUse Edit|Write, PreToolUse Bash)
└── workflow/
    ├── toolchain.json             # detected commands per category + explicit gaps (generated)
    ├── boundaries.rules           # layer + deny lines (executable form of the dependency rule)
    └── secret-allowlist           # optional: regexes to ignore in the builtin secret scan
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

### What to customize vs leave alone

**Customize (project-owned):** `.claude/workflow/boundaries.rules` (via the entry
command + ADRs), `.claude/workflow/toolchain.json` (only to add commands detection
missed), `CLAUDE.md`, everything under `docs/` except `docs/index/` and
`docs/templates/`.

**Leave alone (package-owned, overwritten on re-install):** `.claude/hooks/*`,
`.claude/commands/*`, `scripts/build-index.sh`, `docs/templates/*`, `docs/index/*`
(generated). If a hook misbehaves, fix it in the package and re-run `install.sh`, or
you'll lose the fix at the next upgrade.

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

# 5. Index builds and self-reports freshness
scripts/build-index.sh                                   # expect: "index written: docs/index (...)"
scripts/build-index.sh --check                           # expect: "index fresh (<hash>)"

# 6. Commands are visible
claude                                                    # then type /  — expect the eight workflow commands listed
```

Step 4's exit=2 is the whole point of the package: a wrong action was cheaply,
deterministically caught. If any step's expectation fails, the install is broken — do
not proceed to real work.

## The enforcement layer

| Hook | Event (verified against docs) | What it does |
|---|---|---|
| `post-edit-gate.sh` | `PostToolUse`, matcher `Edit\|Write` | format + lint + file-scoped typecheck on the touched file; failures return to Claude via stderr/exit 2 for same-turn fixing (PostToolUse cannot block — by design the edit gate is a feedback loop, the blocking gates are below) |
| `boundary-check.sh` | `PostToolUse`, matcher `Edit\|Write` | grep-heuristic check of `boundaries.rules` deny edges on the touched file |
| `pre-commit-security.sh` | `PreToolUse`, matcher `Bash` | on `git commit`: secret scan of staged changes (gitleaks or builtin patterns) + dependency audit when dependency files are staged; **exit 2 blocks the commit** |

The two toolchain hooks (`post-edit-gate.sh`, `pre-commit-security.sh`) read
`.claude/workflow/toolchain.json` and never skip silently: a missing tool
category produces a loud `workflow gap:` line naming the fix (P7).

**CI note (out of scope, one line):** mirror `pre-commit-security.sh` and the
project-wide toolchain commands in CI — hooks only guard actions taken through Claude
Code; manual commits and pushes need the same checks server-side.

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
