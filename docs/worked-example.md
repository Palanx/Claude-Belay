# Worked example — adopting `taskboard` and shipping per-key rate limiting

One non-trivial feature, end to end, through the **adopted-project** path: adoption,
planning, phase index, expansion of the first phase, implementation with a gate failure
and its recovery, and validation. Every artifact is shown as it exists on disk at that
step. The blank templates for each document live in `docs/templates/`; this walkthrough
is those templates in motion.

The project: **taskboard**, a real-shaped little codebase — a Node/Express JSON API for
shared task lists, SQLite storage, ~3k lines, written by two people over a year, no
architecture docs, decent tests. One prior feature (audit retention, phases 01–04) has
already run through the workflow, so this feature's phases start at 05.

---

## 0. Starting point

```
taskboard/
├── package.json            # express, better-sqlite3; scripts: test, lint
├── src/
│   ├── app.js              # express app, middleware mount order
│   ├── server.js           # entry point
│   ├── config.js           # the single process.env reader
│   ├── lib/app-error.js
│   ├── middleware/{auth.js,error.js}
│   ├── routes/{boards.js,tasks.js,keys.js}
│   ├── services/{boards.js,tasks.js,keys.js,audit.js}
│   └── db/{index.js,boards.js,tasks.js,keys.js,audit.js,migrations/}
└── test/                   # mirrors src/, node:test runner
```

The operator runs `./install.sh ~/code/taskboard`, opens Claude Code, and types
`/adopt-project`.

## 1. Adoption

The command detects the toolchain, builds the index, reads the code, and writes the
project state. What lands on disk:

**`.claude/workflow/toolchain.json`** (from `detect-toolchain.sh`, then verified by
actually running the test command):

```json
{
  "detected_at": "2026-07-14T09:12:41Z",
  "detected_from": "e41c9a2",
  "stacks": ["node"],
  "commands": {
    "test": "npm test",
    "lint": "npx eslint .",
    "audit": "npm audit --audit-level=high"
  },
  "file_commands": {
    "js": { "lint": "npx eslint {file}", "format": "npx prettier --write {file}" },
    "mjs": { "lint": "npx eslint {file}", "format": "npx prettier --write {file}" }
  },
  "gaps": [
    "typecheck (node): no tsconfig.json — plain JS project. Fix if wanted: adopt // @ts-check + npx tsc --checkJs, or leave as an accepted gap.",
    "secrets: gitleaks not on PATH — pre-commit hook falls back to builtin grep patterns (weaker). Fix: install gitleaks (https://github.com/gitleaks/gitleaks)."
  ]
}
```

**`.claude/workflow/boundaries.rules`** — encoding only edges the code already
respects (the survey found zero route→db imports, so the rule is safe to enforce):

```
layer routes src/routes/
layer services src/services/
layer db src/db/

deny routes -> db
deny services -> routes
deny db -> services
deny db -> routes
```

**`docs/constraints.md`** — layering table plus observed conventions, each citing a
real file as evidence. Full content: identical to `docs/templates/constraints.example.md`
(that example *is* this file).

**Reconstructed ADRs** in `docs/adr/` — e.g. `0002-sqlite-as-only-datastore.md`:

```markdown
# ADR-0002: SQLite is the only datastore

- Status: reconstructed
- Date: 2026-07-14

> Reconstructed from code during adoption — records what IS, not what was
> decided. Verify before relying on the rationale.

## Context
All persistence goes through better-sqlite3 in src/db/; there is no other storage
client in the dependency tree, and deploy.sh ships a single VM container.

## Decision
All persistent state lives in the single SQLite database file; access only through
src/db/ modules.

## Consequences
Single-artifact deploys, transactions across all state. Ceiling: single-writer
concurrency. Rationale for choosing it over Postgres: unknown.
```

**`docs/adoption-report.md`** — the three mandatory sections:

```markdown
# Adoption report — taskboard (2026-07-14, commit e41c9a2)

## Contradictions
- Error handling: src/routes/keys.js:41-58 catches errors inline and writes its own
  JSON; every other route lets middleware/error.js translate. One of the two is wrong.
- src/services/audit.js reads process.env.RETENTION_DAYS directly, bypassing
  src/config.js which everything else uses.

## Decisions needed
- D1: keys.js inline error handling — migrate to the middleware pattern, or is there a
  reason keys are special? (Observed everywhere else: middleware pattern.)
- D2: Should ops scripts share one API key or get individual keys? (Blocks any
  key-management work; surfaced from requirements gap, no evidence in code.)

## Toolchain gaps
- typecheck: none configured (plain JS). Options: // @ts-check + tsc --checkJs, or accept.
- secrets: gitleaks not installed; builtin grep fallback active. Recommend installing.
```

Plus: `docs/index/` (generated), `docs/phases/PHASES.md` (empty table), and `CLAUDE.md`
from the adopted scaffold — layering summary filled in, pointer table verbatim, ~55 lines
(under the 150-line cap).

The operator answers D1 ("migrate keys.js — no reason it's special") and installs
gitleaks. D1's answer becomes a debt note picked up in the next planning pass.

## 2. `/plan-feature per-API-key rate limiting so one abusive consumer can't degrade the API for others`

The command checks index freshness, then reads constraints + ADR titles and pulls the
full text of ADR-0002 (datastore) because rate limiting needs counters. **Conflict
surfaced** (step 3 of the command):

> The obvious implementation (Redis token bucket) conflicts with ADR-0002 (SQLite is
> the only datastore) and the requirements freeze on new services. Options:
> (a) supersede ADR-0002 and introduce Redis, or (b) counters in SQLite, accepting
> fixed-window imprecision. Recommend (b): the feature is anti-abuse, not billing.

Operator picks (b); the decision is recorded **before any phases are written** as
`docs/adr/0004-rate-limit-middleware-sqlite.md` — full content: see
`docs/templates/adr.example.md` (that example is this ADR).

Then the phase rows land in **`docs/phases/PHASES.md`**:

```markdown
## Feature: per-key rate limiting  (2026-07-21)

Abusive API consumers get HTTP 429 per R4, keyed by API key, without affecting other
keys. Not included: quota reporting endpoints, per-route limits, admin UI — see
ADR-0004 for the middleware + SQLite decision this plan implements.

| id | goal | depends | acceptance (coarse) | status |
|----|------|---------|---------------------|--------|
| 05-rate-counter-store | fixed-window counter table + db accessor with atomic increment | - | counter increments atomically under concurrent calls; window rolls over | pending |
| 06-rate-limit-middleware | middleware returns 429 over limit, sets RateLimit headers | 05-rate-counter-store | integration test: 429 on limit breach, 200 under limit, headers present | pending |
| 07-per-key-limits | per-key overrides in api_keys table, fall back to global default | 06-rate-limit-middleware | key with custom limit enforced at that limit; others at default | pending |
| 08-audit-limit-events | limit breaches recorded to the audit trail (R2) | 05-rate-counter-store | breach produces queryable audit row | pending |
```

Note what did **not** happen: no specs. 06 depends on the exact API shape 05 will end up
with, and 05 hasn't run. Writing 06's spec now would be planning against a guess (P4).
Also note the edges: 08 depends only on 05, so 07 and 08 are explicitly parallelizable.

## 3. `/expand-phase 05-rate-counter-store`

Preconditions pass (status `pending`, no dependencies). No prior notes to absorb — this
is the feature's first phase. The spec lands at
**`docs/phases/05-rate-counter-store/spec.md`**:

```markdown
# Phase 05-rate-counter-store — fixed-window counters with atomic increment

## Goal

A `rate_counters` table and a db-layer accessor such that concurrent callers hitting
the same key in the same 60s window each observe a strictly increasing count, and a
call in a later window observes a fresh count with the correct window reset time.
This is the storage half of ADR-0004; no HTTP-visible behavior changes in this phase.

## Context pointers

- `docs/adr/0004-rate-limit-middleware-sqlite.md` — the decision; fixed windows are chosen, do not build a token bucket
- `src/db/index.js` — db bootstrap, migration runner, the shared `q` helper all db modules use
- `src/db/audit.js` — the reference shape for a db module (see constraints §conventions)
- `src/db/migrations/` — numbering scheme; next free number is 007
- `test/db/audit.test.js` — the db-test pattern with in-memory SQLite (test/helpers/db.js)
- `docs/constraints.md` — layering: this phase stays entirely in the db layer

## Plan

1. Migration `007-rate-counters.sql`: table `rate_counters(key TEXT, window_start INTEGER, count INTEGER, PRIMARY KEY (key, window_start))` — touches `src/db/migrations/007-rate-counters.sql`
2. Accessor module exporting `increment(key, windowSeconds)` → count — touches `src/db/rate-counters.js` (new)
3. Lazy cleanup of expired windows on access — touches `src/db/rate-counters.js`
4. Tests incl. concurrency (50 parallel increments → count 50) and window rollover — touches `test/db/rate-counters.test.js` (new)

## Acceptance criteria

```
node --test test/db/rate-counters.test.js   # expect: exit 0; includes 50-parallel-increment atomicity case and rollover case
node --test test/                           # expect: exit 0
npx eslint src/db/rate-counters.js test/db/rate-counters.test.js   # expect: exit 0
grep -rn "rate_counters" src/routes/ src/services/ src/middleware/  # expect: exit 1, no matches — nothing above db touches the table yet
```

## Out of scope

- The middleware and 429s — phase 06
- Per-key limit configuration — phase 07
- Background cleanup job — not wanted; lazy cleanup unless proven insufficient
```

`PHASES.md` row 05: `pending` → `expanded`.

## 4. `/implement-phase 05-rate-counter-store`

Status → `in-progress` **first** (step 1 of the command), then the work.

**Gate failure #1 — post-edit hook (caught in seconds).** The first version of
`src/db/rate-counters.js` used an unused import and a `==` comparison. The instant the
file was written, the `PostToolUse` hook ran `npx eslint` on it and returned:

```
POST-EDIT GATE FAILED: src/db/rate-counters.js
Fix every issue below in this file now, before continuing with the task.
The same checks re-run automatically on your next edit.
--- lint failed ---
src/db/rate-counters.js
  3:7   error  'config' is defined but never used   no-unused-vars
 21:15  error  Expected '===' and instead saw '=='  eqeqeq
```

The session fixed both lines immediately; the next edit passed clean. Cost of the wrong
output: one iteration, machine-detected (P3). No human involved.

**Gate failure #2 — acceptance criterion catches a real bug.** The first implementation
of `increment()` was a read-modify-write:

```js
const row = q.get(`SELECT count FROM rate_counters WHERE key=? AND window_start=?`, ...);
q.run(`UPDATE rate_counters SET count=? ...`, row.count + 1, ...);
```

Unit-looking tests passed. The spec's **atomicity criterion** did not:

```
$ node --test test/db/rate-counters.test.js
✖ 50 parallel increments yield count=50   (got 41)
```

Nine increments lost to interleaving — exactly the "concurrent edits must not lose
writes" failure class R1 exists to prevent, now reproduced deterministically by a
command written at expansion time. Recovery: replace the pair with a single upsert,

```js
const row = q.get(
  `INSERT INTO rate_counters (key, window_start, count) VALUES (?, ?, 1)
   ON CONFLICT(key, window_start) DO UPDATE SET count = count + 1
   RETURNING count, window_start`, key, windowStart);
```

and while there, the session realized the middleware (06) will need the window reset
time for its `RateLimit-Reset` header — returning only a bare count would force 06 to
recompute it and invite skew bugs. The accessor became
`hitAndCount(key, windowSeconds)` → `{count, resetAt}`. That is a **deviation from the
spec** (which named `increment()` returning a count), handled per the repair protocol:
in-scope deviation → do it, amend the spec, record it.

**The mandatory final write (P6)** — `docs/phases/05-rate-counter-store/notes.md`,
recording the outcome, the deviation, the debt, and the discoveries for later phases.
Full content: `docs/templates/notes.example.md` (that example is this file, including
the `hitAndCount` deviation entry that phase 06's spec will later point straight at).

## 5. `/validate-phase 05-rate-counter-store`

```
1. Acceptance criteria (from spec.md, run verbatim):
   node --test test/db/rate-counters.test.js        PASS (11 tests)
   node --test test/                                PASS (74 tests)
   npx eslint src/db/rate-counters.js test/...      PASS
   grep -rn "rate_counters" src/routes/ ...         PASS (no matches)
2. Project gates (toolchain.json):
   test: PASS   lint: PASS
   typecheck: GAP — "typecheck (node): no tsconfig.json ..." (reported, not silent)
3. Boundary sweep over touched files:                clean
4. scripts/build-index.sh --check: STALE (new module file) → rebuilt; docs/index/src-db.md
   now lists rate-counters.js and its symbols
5. Closure test:
   - notes.md: all four sections present, none blank        PASS
   - files changed (git diff) vs spec plan/pointers: 007-rate-counters.sql,
     rate-counters.js, rate-counters.test.js — all named in the plan   PASS
   - deviations report no missing pointers                  PASS
Verdict: done
```

The validation record is appended to `notes.md` (visible at the bottom of
`docs/templates/notes.example.md`), and `PHASES.md` flips 05 to `done` — the only
command allowed to write that word.

## 6. The payoff — expanding phase 06 in a cold session

Days later, a **fresh session with zero memory of the above** runs
`/expand-phase 06-rate-limit-middleware`. Its first mandated read is
`05-rate-counter-store/notes.md` §For later phases, so its spec is written against
reality — `hitAndCount()` and its `{count, resetAt}` shape, the already-configured
`busy_timeout`, the missing `rate_limit` column deferred to 07 — none of which existed
when the feature was planned. The resulting spec is
`docs/templates/spec.example.md`, whose Context pointers line reads:

> `docs/phases/05-rate-counter-store/notes.md` — 05 renamed the accessor to
> `hitAndCount()` (deviation from its spec) and documents its return shape

That line is the whole system in miniature: implementation truth flowed to disk (P6),
the just-in-time spec absorbed it (P4), the phase carries everything a cold session
needs (P5), and at no point did any of it depend on a session remembering anything.
