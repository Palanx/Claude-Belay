---
description: Record a bug or improvement discovered in a Belay hook/command so the package repo can fix it
argument-hint: <one line on what misbehaved> (optional — asked for if omitted)
---

# /belay-feedback

**Purpose:** the return channel to the workflow package. Hooks and commands here are
copies installed by the package's `install.sh`; when one misfires (false positive, wrong
tool command, unhandled case) or a workflow step causes friction, the discovery dies with
this session unless it is recorded where the package repo can see it. This command writes
that record — with the concrete data needed to reproduce the issue.

**Arguments:** optional one-line description of what misbehaved; if absent, ask.

**Preconditions:** none.

**Reads:** `.claude/workflow/belay-version`, plus whatever reproduces the issue (hook stderr already in this conversation, offending file paths/lines, `toolchain.json` or `boundaries.rules` excerpts).
**Writes:** appends one entry to `~/.claude-belay/feedback/<repo-basename>.md` (create the directory and file if missing).

## Steps

1. **Name the component** — the path inside the package: one of `hooks/*.sh`,
   `hooks/lib/*.sh`, `commands/*.md`, `scripts/build-index.sh`, `install.sh`, or a
   template. If the problem is actually this project's config (e.g. a wrong command in
   `toolchain.json`), fix the project file instead — no entry.

2. **Gather the evidence verbatim.** The actual stderr the hook printed, the exact file
   and lines that triggered it, the relevant config excerpt. A paraphrase is not
   reproducible — the session that fixes this sees only the entry, never this
   conversation.

3. **Read the package version** from `.claude/workflow/belay-version` (`unknown` if the
   file is absent).

4. **Append the entry** (blank line before it):

   ```markdown
   ## <YYYY-MM-DD> — <repo basename> — <belay-version line>
   status: open
   component: <path within the package>
   what happened: <observed behavior>
   expected: <what should have happened>
   data:
   <verbatim evidence from step 2, fenced if multi-line>
   proposed fix: <if known, else omit the line>
   ```

## Mandatory final step (P6)

Confirm to the operator: which file the entry was appended to and which component it
names. Remind them the fix lands in the package repo (a Claude session there lists open
entries at startup) and reaches this project on its next `install.sh` run.

## Failure modes

- **`$HOME` not writable (sandbox)** → print the full entry in the conversation and tell the operator to paste it into `~/.claude-belay/feedback/` themselves.

## Handoff

None — the package repo's own session-start hook picks the entry up.
