---
description: Run a phase's acceptance gates and the closure test; flip status to done only on a clean pass
argument-hint: <phase-id>
---

# /validate-phase

**Purpose:** the deterministic gate at the end of a phase (P3). Generation may be
wrong; this step is where wrong is caught. Only a clean pass may set `done` — a phase
marked `done` is load-bearing for every phase that depends on it.

**Arguments:** `$1` — the phase id. Required.

**Preconditions:** `docs/phases/$1/spec.md` and `notes.md` exist; PHASES.md status is `in-progress`. Missing notes.md means `/implement-phase` skipped its mandatory final step — go back and write it first; validation validates the record as well as the code.

**Reads:** `docs/phases/$1/spec.md` + `notes.md`, `.claude/workflow/toolchain.json` (via `scripts/check.sh`), `docs/phases/PHASES.md`.
**Writes:** `docs/phases/$1/notes.md` (validation record appended), `docs/phases/PHASES.md` (status → `done` on pass only; → `pending` when the iteration-3+ escape below fires, which is the one time this command moves a phase backwards).

**The phase's file set and diff** — defined once here, used by steps 3, 5 and 6. Default:
the working tree — `git status --porcelain` and `git diff` (run `git add -N` first so files
new in this phase diff as something rather than nothing) — unioned with the files the
spec's Plan names. **If `notes.md` records a `- base: <ref>` line** under Outcome (written
by `/implement-phase --implemented`; the literal `working tree` means the default applies),
use `git diff <ref>` and `git diff --name-only <ref>` instead, same union — the ref against
the **working tree**, never `<ref>..HEAD`, which shows only what was committed and hides
hand-written work still sitting uncommitted (`git add -N` first here too, for the same
reason as above).
**Subtract the files the package installed**, unless the spec's Plan names one: every path
listed in `.claude/workflow/installed`. A `chore(belay):` commit lands package-owned files in
the tree, and once one falls between the base ref and now, no ref exists that keeps the phase's
history in and the package's out — so the diff carries files the phase never wrote, step 6 asks
the spec to account for them, and its prescribed fix would have the spec claim this phase wrote
`docs/templates/spec.md`. The manifest is exactly the set `install.sh` wrote (see
`docs/adr/0001-ownership-is-decided-by-the-install-manifest.md`); if it is absent, say so on
the `upstream:` line rather than treating everything as phase work.

**Subtract what `notes.md` declares not this phase's**: every `- not-ours: <path> — <who
changed it, and why>` line under Outcome, unless the spec's Plan names that path. Same shape
as the manifest — a path in the diff the phase did not write — for the change the manifest
cannot name: an operator amending `CLAUDE.md`, a constraint or an ADR while the phase is open.
Whoever made the change writes the line, or the session that finds it after asking the
operator; never infer it from the diff. A path the Plan names cannot be declared: one file's
hunks cannot be split by author, so the spec accounts for it as it does today.

**Check the file set before using it.** If it is empty, or holds nothing beyond the files the
Plan names, stop and say so — do not run the gates over it. A phase that changed nothing is
not what that looks like; a measurement that did not happen is. The usual cause is a
`- base: working tree` line that was true when `/implement-phase` wrote it and expired when
the work was committed, which is ordinary and expected: a phase closes with its work
committed. Name that as the likely cause and ask for the real ref (P7 — a check that examined
nothing says so).

Never fall back to the Plan alone: the file the Plan never named is exactly what step 6
exists to catch, so a diff that cannot show it turns three gates into no-ops that report
`pass`.

## Steps

1. **Acceptance criteria.** Run every command in the spec's Acceptance criteria section,
   in order, exactly as written. Record each command's pass/fail. They are executable by
   construction (P3) — if one turns out not to be runnable, that is itself a failure:
   fix the criterion in spec.md and note the fix in notes.md.

2. **Project-wide gates.** Run `scripts/check.sh` and record its output and exit code.
   It runs `test`, `lint` and `typecheck` in their project-wide forms — this catches
   breakage *outside* the phase's own files that the per-file edit gate cannot see. Do
   not run those commands yourself: the script is the same one a human and CI call, and
   running them by hand is how the two paths drift apart. For any category the script
   reports as a `workflow gap:`, print that warning verbatim in the report — an unchecked
   category is stated, never silent (P7).

3. **Boundary sweep.** Run `scripts/check.sh --files <every source file in the phase's
   file set>` (the file set is defined above). This is the same gate the edit path runs,
   re-run as a batch in case any edit bypassed it.
   A sweep comes back clean for three different reasons and only one of them is "no
   violations", so check the other two against `.claude/workflow/boundaries.rules` before
   reporting `clean` (P7):
   - **No active `deny` line** — `grep -qE '^deny[[:space:]]'` finds nothing. The rules
     cannot flag anything, whatever the files are. Report `not swept: no active deny rules`.
   - **No file in the set under a declared layer** — `awk '$1=="layer" {print $3}'` gives the
     prefixes; none of them prefixes any file in the phase's file set. The rules are live and
     this phase touched nothing they cover, which is the normal state of a phase that only
     adds tests, scripts or docs. Report `not swept: no file in the set is under a declared
     layer`.
   The gate is silent about both by design (see its header) — the report must not be. Either
   is a stated gap, not a failure: neither sends the phase back to `/implement-phase`, because
   no code change can add a `deny` rule or move a phase's files under a layer. Rules left
   inert until the humans decide the layering is a supported state (`/adopt-project`,
   "codebase too inconsistent to infer layering"), a test-only phase is ordinary, and a phase
   must be able to close in both.
   **Corporate mode** (`.claude/workflow/corporate` exists): also verify no belay state
   path appears in `git status --porcelain` — no line matching
   `^\?\? (\.belay/|CLAUDE\.local\.md|docs/(product|adr|phases|index|security|templates)/|docs/(constraints|adoption-report)\.md|scripts/build-index\.sh)`
   (run `git status --porcelain -uall | grep -E '<that regex>'`; empty output = clean).
   A hit at an un-prefixed path means state was written to the old canonical location
   (move it under `.belay/`); a hit on `.belay/` or `CLAUDE.local.md` means the exclude
   block broke (re-run `install.sh --corporate`). Either way the validation FAILS until
   the status is clean of belay paths.

4. **Index freshness.** Run `scripts/build-index.sh --check`; if stale, run
   `scripts/build-index.sh` so the next phase plans against reality.

5. **Independent spec review.** Only once 1–4 are clean — never review code the cheap gates
   already reject. Dispatch ONE subagent with exactly three inputs: `CLAUDE.md`
   (`CLAUDE.local.md` in corporate mode), `docs/phases/$1/spec.md`, and the phase's diff
   restricted to step 3's file set (defined above — that definition is what makes this work
   on code the operator already committed). Nothing else —
   not `notes.md`, not the dependency notes, not your summary. **Say in the prompt which paths
   you withheld** — `notes.md` always, plus whatever the manifest and `not-ours` subtractions removed — and
   that their absence is not a finding. The file set contains `notes.md` by construction (both
   this command and `/implement-phase` write it), so withholding it silently leaves the
   reviewer holding a spec whose Plan says the phase writes that file and a diff that does
   not: it can only report `contradicts`, a verdict no code change can clear, on every spec
   the shipped template produces. Naming what is withheld costs the starvation nothing — the
   reviewer still cannot read those files, it just stops reading their absence as evidence.
   Starve it deliberately: the
   instinct to be helpful destroys the property under test, because a reviewer who knows what
   you meant cannot see that the spec never said it. Ask for two verdicts only:
   - **contradicts** — a hunk conflicts with the spec's Goal, Plan, Acceptance criteria or
     Out of scope; cite spec line + hunk. This gate FAILS. The reviewer can see the conflict,
     not which side is stale — classify it before routing (see the routing below).
   - **undecidable** — it cannot tell from the spec alone whether a hunk is right, and names
     what was missing. Spec failure, not code failure: feed it to step 6.
   Anything else — naming, structure, "I'd have done it differently" — is taste: append it to
   notes.md under `For later phases`, never block on it. The gate stays deterministic (P3)
   because the reviewer may only compare the diff to the spec, never to its own preferences.
   **No subagent available** (Cursor's `.cursor/commands/`, or any client without Task-style
   dispatch): have the operator run the same three-input review in a fresh session and paste
   the verdict, or record `skipped: no subagent` below. Skipping does not block `done`, but
   the closure test is then self-declared again — that is stated, never silent (P7).

6. **Closure test (P5).** Check the record, not just the code:
   - notes.md has all four sections (Outcome, Deviations, Debt, For later phases), none blank — `None` is an entry, blank is a violation.
   - **Exempt: the files this workflow writes itself** — `docs/phases/$1/spec.md`, `docs/phases/$1/notes.md`, `docs/phases/PHASES.md` and `docs/index/`. Every command here amends them by design, and this one prescribes a `spec.md` amendment as the fix for an `undecidable` verdict — so a phase that goes round the loop once carries its own spec in its diff from then on. Counting those as escaped scope fails the phase for obeying its own instructions. The exemption is those four paths and nothing else: any other file in the diff — an ADR, a config, a scene or prefab authored by hand — is judged by the next bullet. The shipped `CLAUDE.md` states the same four paths, and that duplication is deliberate: step 5's reviewer receives `CLAUDE.md`, `spec.md` and the diff — never this file — so an exemption written only here reaches the closure test and not the reviewer, which returns it as `undecidable` on every phase forever. Do not tidy either copy away.
   - Every *other* file in the phase's file set is reachable from the spec's Context pointers or Plan. A file changed but never named in the spec = the phase escaped its scope: closure test FAILED. Record it in notes.md Deviations, flag it in your report, and name it in the spec's Plan before re-running — the spec has to describe the change that actually happened.
   - **A quantified claim owes its set.** If the spec's Goal or Acceptance criteria say
     "every X", "each Y", "all N of Z", the spec must name the members — a list or a table.
     Unenumerated, the claim is not vague, it is *undecidable*: step 5's reviewer gets the
     spec and the diff, so it cannot compute a set the spec never states, and `undecidable`
     is the only verdict available to it. Worse, the finding regenerates — each round closes
     the instances its diff touched and the unnamed remainder comes back under whichever
     verdict fits next. Missing enumeration = missing pointer: closure test FAILED, same
     routing as any other. A Goal that quantifies over nothing owes nothing.
   - An `undecidable` finding from step 5 IS a missing pointer, found from outside your own head: closure test FAILED; record what the reviewer could not resolve in notes.md Deviations.
   - If notes.md Deviations reports missing pointers, mark the closure test FAILED even if the code passes — the *next* phase pays for it; the operator must know the cuts are drifting.

## Mandatory final step (P6)

Append to `docs/phases/$1/notes.md`:

```
## Validation — <date>
- criteria: <n> passed / <n> failed
- project gates: test <pass|fail|gap>, lint <...>, typecheck <...>
- boundary sweep: <clean | not swept: no active deny rules | not swept: no file in the set is under a declared layer | violations listed above>
- independent review: <clean | contradicts (code-side|spec-side): <what> — <evidence> | undecidable: <what was missing> | skipped: no subagent>
- closure test: <pass|fail: reason>
- findings: <n> — failed criteria + failed project-gate categories + boundary violations + review findings (each contradicts and each undecidable) + closure-test failures no review finding already counts; 0 on a pass
- upstream: <none | <package file(s)> — /belay-feedback recommended>
- not-ours: <none | <path(s)> subtracted>
- verdict: <done | returned to implementation | returned to implementation (escape not taken: converging <n → … → n>) | escaped to /expand-phase: spec re-expanded>
```

On full pass: PHASES.md status → `done`. On any failure: status stays `in-progress`;
report exactly which gate failed with its output — that error text is the input for the
next iteration. Where that iteration happens depends on what failed: steps 1–4 and a
code-side `contradicts` go back to `/implement-phase $1` (the code is wrong); a closure-test
failure, an `undecidable` verdict or a spec-side `contradicts` is fixed in `spec.md` plus a notes.md Deviations entry
and re-validated from here (the record is wrong). **An amendment owes reconciliation**: name
the other statements in the spec that assert the same fact, and fix or delete them in the same
edit, listing in that Deviations entry which you checked. Nothing else will — the reviewer
sees the spec and the diff, and a statement the amendment just invalidated is in the spec but
not in the diff, so it surfaces only when some later round's diff happens to touch it. Deleting
a statement the amendment leaves unfounded is a legitimate outcome and often the right one;
rewording it is how the next round's finding gets written. **And check what founds the
sentences the amendment itself adds**: after writing a fix, ask what each new claim rests on,
and if the answer is "the fix I just wrote", delete it. A fix written to close a finding tends
to introduce a claim with nothing behind it, which the next round returns as a finding of its
own — measured repeatedly, in one phase as its dominant failure mode across four rounds. Say which of the two you are handing
back, or the next session guesses.

**Classify every `contradicts` before routing it.** The reviewer holds the spec and the diff,
so it sees that they disagree and cannot see which one is stale; you hold the tree and its
history. *Code-side*: the spec states what was intended and the hunk departs from it.
*Spec-side*: the hunk is a deliberate change the spec failed to follow — a Deviations entry
records it, `git log -S '<spec phrase>'` shows the sentence predates the change, or the
code's own rationale argues against the sentence. Put the side and that evidence on the
report line. No evidence either way → ask the operator; never default to either side. A
spec-side finding is never closed by changing code: the reviewer is satisfied by either
edit, and only one of them is true.

**Both routes fix this project. Neither asks what caused the finding.** If the file that
misbehaved is one `.claude/workflow/installed` names — the manifest of everything
`install.sh` wrote: the hooks, the commands, `scripts/build-index.sh`, `docs/templates/` —
the cause is the package and the fix above is a workaround. Apply it anyway so the phase can
close, name the file on the `upstream:` line, and tell the operator to run
`/belay-feedback`. This never blocks: `done` is decided by the gates. It is stated so it
cannot be silent (P7) — a package defect patched into one project's `spec.md` is a defect
the next project rediscovers from zero. Ownership decides this, not who fixes it: a wrong
command in `toolchain.json` is yours; a command that routes a finding wrongly is not. If the
manifest is absent — an install old enough to predate it, never re-run — say so on the
`upstream:` line instead of reading its silence as "nothing upstream", and tell the
operator to re-run `install.sh`. Every criterion here reads the file from disk, so none
of it depends on any of this being committed.

## Failure modes

- **Gate failure** → not an exception, the designed loop: hand the failing command + output to `/implement-phase $1`, which fixes and returns here. Expected convergence is 1–2 iterations because failures are machine-detectable (P3). **From iteration 3 against the current spec** — count the `## Validation` sections in notes.md that follow the most recent `escaped to /expand-phase` verdict, or all of them if there is none, this round's included — read their `- findings:` lines in order. If every count is strictly below the one before it, the loop is converging: do not escape. Leave the status `in-progress`, write the verdict as `returned to implementation (escape not taken: converging <n → … → n>)`, and tell the operator that re-expanding anyway is theirs to decide. A strictly falling count of whole numbers reaches zero within as many rounds as its first value, so this cannot iterate forever. Otherwise — any count equal to or above the one before it, or any counted round with no `- findings:` line, as every record written before that line existed has none — the spec is wrong: stop and say so, and route it. A wrong *spec* is re-expanded: **set the status to `pending` yourself** and hand the operator `/expand-phase $1`. Do not leave that flip to them — `/expand-phase` refuses any other status, so a route nobody performs is a route that ends in a bounce, and the phase iterates a sixth time instead (P9). Say in the report that you moved it. A wrong *cut* is re-planned (`/plan-feature`, which supersedes the row). The count resets at that verdict because the escape's own output is a new spec: a lifetime count would put every phase that ever escaped permanently in escape territory, demanding a re-expansion of a spec written one round ago that is converging. The trend only ever relaxes the escape, never tightens it: whatever fired on the round count alone still fires, except a run whose findings fall every round. That run is not a spec nobody believes, and re-expanding it swaps a converging spec for new claims the next round has to audit. Iterating a fourth time against a spec nobody believes is the failure this escape exists to stop.
- **The code was written by a human** (`/implement-phase --implemented`) → nothing here changes: every gate above judges the code and the record, not the author. If anything the independent review is *stronger*, because the reviewer cannot be told what the human meant — but it is also the first gate this code meets at all, since the edit-time hooks only see edits made through the agent. Read step 2's and step 3's output as new information, not as a re-check.
- **Review verdicts split by consequence** — `contradicts` goes where its classification says: code-side into the loop above, spec-side to `spec.md` like an `undecidable`; `undecidable` is a spec bug, so the fix is a pointer in spec.md (with the Deviations entry that any spec amendment requires), never a code change to satisfy the reviewer.
- **Everything passes but the closure test** → still a failure: status stays `in-progress`. The code may well be right; the *record* isn't, and the next phase is what pays for that. It is also the cheapest failure here to clear, so clear it rather than arguing with it: name the stray file in the spec's Plan, or add the pointer the reviewer could not resolve, then write the Deviations entry that any spec amendment requires and re-run. A phase marked `done` asserts that a cold session can rebuild its context from the spec — that is exactly what the closure test measures, so `done` on a failed closure test would make the word mean nothing.

## Handoff

Pass → `/expand-phase <next>` (the next pending phase whose dependencies are all done).
Fail → `/implement-phase $1` with this validation report — unless every failure routes to the spec (closure test, `undecidable`, spec-side `contradicts`): then amend `spec.md` and re-run `/validate-phase $1`.
