---
description: Existing-codebase entry point — infer stack, layering, conventions and decisions from the code; produce workflow state and a gap report
argument-hint: (no arguments)
---

# /adopt-project

**Purpose:** bring an existing codebase into workflow state by *observing* it, not
idealizing it. The code as it is wins over any abstract ideal: existing conventions
become rules, because violating them is worse than following an imperfect pattern.
After this command the project is in the same state a bootstrapped project would be (P8).

**Arguments:** none.

**Preconditions:**
- Working directory is a git repo with at least one commit. Otherwise this is `/bootstrap-project`.
- Workflow package installed. State comes from the marker line in `docs/adoption-report.md`:

| On disk | Do |
|---|---|
| no `docs/adoption-report.md` | fresh run — start at step 1 |
| `<!-- belay-adoption: in-progress -->` | **resume** — see below |
| `<!-- belay-adoption: complete -->`, or the file exists with no marker (adopted by an older version) | already adopted — stop, the operator probably wants `/refresh-index` |
| already adopted **and** the operator explicitly asks to re-adopt (usually sent here by `/refresh-index` after a refactor big enough that the recorded architecture no longer matches) | **re-adopt as an update** — see below |

**Reads:** the codebase (via `git ls-files`, manifests, configs, existing docs/READMEs), `docs/templates/*`, `docs/adoption-report.md` (when resuming).
**Writes:** `.claude/workflow/toolchain.json`, `.claude/workflow/boundaries.rules`, `docs/constraints.md`, `docs/adr/0001-*.md` … (reconstructed), `docs/adoption-report.md`, `docs/phases/PHASES.md` (empty table), `docs/index/`, `CLAUDE.md`.

## Resume

<!-- belay-debt: the resume path is verified by inspection only — no real
     interrupted run on a large repo yet. Test it by adopting a big codebase,
     interrupting during step 4, and re-running in a fresh session: the log's
     surveyed/pending line and docs/constraints.md must together be enough to
     continue without re-reading a surveyed module. -->

Adopting a large repo does not fit in one session, so this command is written to be
re-run: `docs/adoption-report.md` is the *running log*, not the final output. It is
created at step 1 and every step appends to it as it goes (P6 applies inside this
command, not only at its end).

Resuming: read the log's `## Progress` checklist, skip every step already `[x]`, and
continue at the first unchecked one. For step 4 that means only the modules listed as
`pending:` — never re-read a module already listed as `surveyed:`. Say in one line where
you resumed from before doing anything else.

Running out of context or quota mid-run is expected, not a failure: the log is current
after every step, so stopping cleanly and telling the operator to re-run
`/adopt-project` in a fresh session is the correct exit.

## Re-adopting an already-adopted project

`/refresh-index` sends work here when the index diff shows a refactor big enough that
`docs/constraints.md` and `boundaries.rules` may describe the old architecture. This is an
**update, not a fresh adoption** — the difference is what you are allowed to overwrite:

- **Never rewrite** an ADR with status `accepted`, or a constraint the operator confirmed.
  Those are decisions, and a decision is only replaced by a superseding ADR (step 5's rule,
  applied to yourself). A `reconstructed` ADR that the code now contradicts is *also* not
  edited: it becomes a line in Decisions needed.
- **Do re-derive** what is observation rather than decision: the toolchain (step 1), the
  index and the de facto layering (step 2), and the conventions of modules whose files
  actually changed (step 4 — only those; a module the refactor did not touch is still
  surveyed).
- **Append, never replace**, in the report. Reset the marker to `in-progress`, say in one
  line that this is a re-adoption and what triggered it, and add a dated
  `## Re-adoption <YYYY-MM-DD>` heading under which the new contradictions and decisions
  land. The original adoption's findings stay where they are — the operator answered some of
  them, and deleting the question loses the answer's context.
- Where the new survey contradicts a written constraint, that is a **contradiction to
  report**, not a correction to make. The code wins over the docs eventually, but which one
  moves is the operator's call, and doing it silently would rewrite rules other sessions are
  being judged by.

Everything else — the step order, the per-module write-and-move-on discipline, the resume
behaviour — is unchanged.

## Steps

1. **Open the log, then toolchain (P7).** Before anything else, write
   `docs/adoption-report.md` with the marker `<!-- belay-adoption: in-progress -->` on
   line 2 and this skeleton — the later steps fill it in:

   ```markdown
   # Adoption report — <project>

   <!-- belay-adoption: in-progress -->

   ## Progress
   - [ ] 1 toolchain
   - [ ] 2 structure survey (layering → constraints.md)
   - [ ] 3 doc audit
   - [ ] 4 conventions — surveyed: none · pending: <fill from the index in step 2>
   - [ ] 5 reconstructed ADRs
   - [ ] 6 boundary rules
   - [ ] 7 decisions needed
   - [ ] 8 constraints + phase table
   - [ ] 9 CLAUDE.md (+ AGENTS.md)

   ## Contradictions

   ## Decisions needed

   ## Toolchain gaps
   ```

   Then run `.claude/hooks/lib/detect-toolchain.sh` and verify its output against
   reality: run the detected test command once; if it fails out of the box, that is a
   finding, not a blocker. Append every gap with its concrete fix under **Toolchain
   gaps**, tick step 1.

2. **Structure survey.** Run `scripts/build-index.sh`, then read
   `docs/index/_overview.md`. From the module list and dependency edges, infer the
   *de facto* layering: which directories act as entry points, which as domain/services,
   which as infrastructure. Name the layers after what the directories are actually
   called, not textbook names. Write `docs/constraints.md` now, from
   `docs/templates/constraints.md`, with `§Layering` filled — the rest of its sections
   stay as template placeholders until step 8. Fill step 4's `pending:` list in the log
   with the module names from the index.

3. **Existing documentation audit.** Find READMEs, docs/, wikis-in-repo, ADRs, comments
   that claim architecture. For each: current, stale (contradicted by the code), or
   aspirational (never implemented). Append all three categories under
   **Contradictions** as you find them — stale docs are actively harmful and the
   operator must decide to fix or delete them.

4. **Convention extraction — one module at a time.** For each module in the log's
   `pending:` list: read a representative sample (largest files + most-imported files
   from that module's index page), extract the implicit conventions actually followed
   (naming, error handling shape, test file layout and naming, logging, how
   configuration is read), then **append them to `docs/constraints.md` under "Observed
   conventions"** — each with one real file as its example — and move that module from
   `pending:` to `surveyed:` in the log before starting the next one.

   Write and move on: never hold more than one module's file contents at a time, and
   never carry findings across modules to write them "at the end". The peak context of
   this command is one module, and what has been written is what survives.

   Methodology or architecture skills active in this session are a second source, subordinate
   to the code. Where such a skill states a rule the code **already follows**, transcribe it
   like any other convention — self-contained prose, never the skill's name, with a real file
   as its example (the skill is not installed in this repo, and the next session may not have
   it). Where it **contradicts** the observed convention, the code wins: that rule does not
   enter constraints.md, it becomes a line in step 7's "Decisions needed", phrased as a
   question. Adopting it later is an ADR; changing the existing code to match is a phase via
   `/plan-feature`, never a fix in passing. Show the operator the drafted skill-derived lines
   for confirmation once, when the last module is surveyed — a rule nobody ratified would bind
   every future session to one person's preference. Conventions read straight off the code
   need no confirmation; they get written per module as above.

   **When the harvest cannot happen, say so.** If no methodology skills are active in this
   session (a teammate's machine, Cursor via `.cursor/commands/`, headless `claude -p`), or
   if there is no operator to confirm, do not leave the absence invisible — a resumed session
   reads the file, not this conversation. Write one line at the top of `docs/constraints.md` recording that no
   house rules were harvested, and what closes the gap later: state the rule here in
   self-contained prose, and add an ADR for any rule that constrains future work. Never
   "follow skill X" — the next reader may not have it (P7: a gap is stated, never silent).

5. **Reconstructed ADRs.** For each significant decision visible in the code (framework
   choice, database, layering, sync/async style, auth approach), write its ADR file the
   moment the decision is identified — one file per decision, next sequential number
   from what is already in `docs/adr/`, so an interrupted step 5 resumes on its own.
   Use the template with status **`reconstructed`** and this header line:
   `> Reconstructed from code during adoption — records what IS, not what was decided. Verify before relying on the rationale.`
   Never invent rationale; where the reason isn't visible, write "rationale unknown".

6. **Boundary rules.** Write `.claude/workflow/boundaries.rules` encoding the layering
   *as observed* — only `deny` edges the code already respects. Where the code is
   inconsistent (some files cross a layer, most don't), do NOT invent a rule; put the
   contradiction in the gap report instead. A rule the codebase already violates would
   make the boundary hook cry wolf on every edit.

7. **Gap report.** The log already carries **Contradictions** (step 3, plus anything
   steps 4–6 turned up) and **Toolchain gaps** (step 1). Fill the remaining section:
   - **Decisions needed** — one line per human decision, each phrased as a question with the options observed in the code. **Open this section with the routing line, written into the file** (not just followed by you): an answer typed here changes nothing until it becomes a *new* ADR in `docs/adr/` from `docs/templates/adr.md`, next sequential number, status `accepted`; where it settles something a step 5 ADR only reconstructed, that ADR gets status `superseded` with a pointer to the new one, never an edit in place. The session that answers these questions arrives days later and reads `CLAUDE.md` plus this file — if the routing lives only in your head, the answer dies on disk while the reconstructed ADR keeps binding.

   Then re-read Contradictions and Toolchain gaps as written: sections appended across
   several sessions duplicate and contradict. Merge duplicates, drop what a later step
   resolved.

   **What this step does not do: invent requirements.** `docs/product/requirements.md` is
   `/bootstrap-project`'s output, and adoption never writes one — code shows you *what* a
   system does, never *why it was wanted*, and a reconstructed capability list would be a
   guess wearing an id. If the project's purpose is written down nowhere, say so here and
   name the fix: the operator writes it from `docs/templates/requirements.md`, once, by
   hand. Nothing in the pipeline requires it (`/plan-feature` reads it only if present),
   but without it a feature can never be checked against a stated non-goal.

8. **Constraints + phase table.** Finish `docs/constraints.md` — `§Layering` (step 2) and
   `§Observed conventions` (step 4) are already there; fill the remaining sections
   (Invariants, Error handling, Testing) and remove any leftover template placeholder.
   Write `docs/phases/PHASES.md` from the template with an empty phase table — phases
   come from `/plan-feature`.

9. **CLAUDE.md (+ AGENTS.md).** One rule for agent docs: **`CLAUDE.md` is the real file,
   `AGENTS.md` is a symlink to it or absent, and every agent doc that existed before is
   merge input.** Run this first, verbatim, before reasoning about the merge — the
   backup is write-once so re-running `/adopt-project` preserves the true pre-belay
   original, not a copy of what belay wrote last time:

   ```sh
   mkdir -p .claude/workflow
   for f in CLAUDE.md AGENTS.md; do
     if [ -f "$f" ] && [ ! -L "$f" ] && [ ! -e ".claude/workflow/$f.pre-belay" ]; then
       cp "$f" ".claude/workflow/$f.pre-belay"
     fi
   done
   ```

   Nothing to back up is a success, not a failure — the block exits 0 either way.

   Then copy `docs/templates/CLAUDE.adopted.md` to `CLAUDE.md` and fill the placeholders.

   **Pick the workflow variant.** The template ships both the pipeline sections and a
   commented LIGHTWEIGHT pair. Ask the operator once, in one sentence — will they hand whole
   features to the agent (pipeline), or keep driving the repo themselves and use Claude for
   advice, planning and small changes (lightweight)? Write the matching pair, delete the
   other with its comment markers, and for lightweight also drop the phase rows from the
   pointer table. Adopted repos are frequently the lightweight case and corporate installs
   almost always are, so if nobody answers, look at what you just surveyed: an active repo
   with many hands is lightweight, a repo the operator owns alone can take the pipeline. Say
   which you chose and why. Never ship both — a session that reads a mandate the operator
   opted out of will follow it.

   Whatever real files existed — `CLAUDE.md`, `AGENTS.md`, or both — are all merge input:
   keep the project-specific rules that survive the P1 test ("true in every session?"),
   move the rest into `docs/constraints.md`, add the pointer table, and state a rule that
   appeared in both docs once. Where the two contradict each other, the code wins and the
   disagreement goes under Contradictions in the adoption report. Under 150 lines, always.
   Finally, if `AGENTS.md` was a regular file, make it point at the merged doc — and say
   so in your output, it is a tracked file changing shape:

   ```sh
   if [ -f AGENTS.md ] && [ ! -L AGENTS.md ]; then rm AGENTS.md && ln -s CLAUDE.md AGENTS.md; fi
   ```

   **Corporate mode** (`.claude/workflow/corporate` exists): never create, modify, move or
   merge *pre-existing* `CLAUDE.md`, `AGENTS.md`, or `.cursor/rules/*` files — those belong
   to the company. The one exception is belay's own `.cursor/rules/belay.mdc`, which you
   create. Skip the backup and symlink steps above entirely: nothing is overwritten, so
   there is nothing to back up — which also means **the `CLAUDE.md`/`AGENTS.md` symlink
   invariant does not hold here**, though the rest of this command is written assuming it
   does. Write the filled template to `CLAUDE.local.md` instead (Claude Code auto-loads it
   alongside `CLAUDE.md`). Read every existing agent doc first — both `CLAUDE.md` and
   `AGENTS.md`, resolving symlinks so you don't read the same file twice — so
   `CLAUDE.local.md` complements them without repeating them; where they contradict what
   the code shows, record that under Contradictions in the adoption report — never edit
   them. If `.cursor/commands/` exists, also write `.cursor/rules/belay.mdc` (frontmatter
   `alwaysApply: true`) carrying the same pointer table.

   **Bridge `AGENTS.md`, since the symlink is skipped.** Claude Code reads `CLAUDE.md`, not
   `AGENTS.md`, so without the symlink a session never sees the company's rules at all —
   the failure this bridge exists to prevent. An import does the same job and touches
   nothing the company owns. If

   ```sh
   [ -e AGENTS.md ] && ! [ AGENTS.md -ef CLAUDE.md ]   # -ef: already-bridged is a no-op
   ```

   then the **first line** of the `CLAUDE.local.md` you write is `@AGENTS.md`, then a blank
   line, then the filled template — and add one line to its session reading rule naming
   `AGENTS.md` as the company's authoritative document, already loaded by that import.
   Every other mention of it stays backticked: import parsing skips code spans, so a bare
   `@AGENTS.md` anywhere else is a second import. The path resolves inside the working
   directory, so it raises no external-import approval dialog.

   The carrier itself is empirical, not documented: Cursor loads `CLAUDE.local.md` (fresh
   Cursor chat, verified 2026-08-19) but does not document doing so. If it ever stops
   loading, re-test — do not "fix" it by moving the content elsewhere.

## Mandatory final step (P6)

Verify the written state: `docs/adoption-report.md`, `docs/constraints.md`,
`docs/phases/PHASES.md`, `CLAUDE.md` (< 150 lines), `.claude/workflow/toolchain.json`,
`.claude/workflow/boundaries.rules`, `docs/index/_overview.md` all exist. Confirm exactly
one workflow variant survived step 9 — `grep -c 'LIGHTWEIGHT\|PIPELINE PROJECT'` over the
file you actually wrote must print `0`; a hit means a template comment (and probably both
variants) is still there, which the line count is too generous to catch. Only once that
passes, flip the log's marker to `<!-- belay-adoption: complete -->` — the marker means
"verified", not "the steps ran", and it is what stops the next `/adopt-project` from
re-adopting. Print the
"Decisions needed" section of the adoption report verbatim as your final output — those
questions are the handoff. Offer one commit: `chore: adopt project into workflow`.
Corporate mode: verify `CLAUDE.local.md` (< 150 lines) instead of `CLAUDE.md` — that is
also the file the variant grep must run against, since grepping the company's `CLAUDE.md`
passes vacuously. If `AGENTS.md` exists, `head -1 CLAUDE.local.md` must print `@AGENTS.md`;
without it the session never sees the company's rules. Skip the commit offer — the
workflow state is deliberately invisible to git.

## Failure modes

- **Codebase too inconsistent to infer layering** → write `boundaries.rules` with layers but zero `deny` lines, and make "choose the layering" the first entry in Decisions needed. The boundary hook is inert until the humans decide; that is honest.
- **No tests / no lint anywhere** → toolchain gaps name concrete options per stack (from detect-toolchain's output). Do not install tools unprompted.
- **Context or quota runs out mid-run** (the normal case on a large repo) → stop cleanly: the log is current after every step, so there is nothing to salvage. Tell the operator to re-run `/adopt-project` in a fresh session, and which step it will resume at. Never rush the remaining modules to "finish" — a shallow survey written to disk outlives the session that wrote it.
- **Log says `in-progress` but the checked steps' outputs are missing** (log hand-edited, or a write was interrupted) → trust the files, not the checklist: untick any step whose output does not exist, say so, and redo it.

## Handoff

Operator answers the "Decisions needed" questions (answers become real ADRs superseding
the reconstructed ones where relevant). Then `/plan-feature <description>` for the first
piece of work.
