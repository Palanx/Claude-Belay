# Constraints — taskboard

<!-- Example of a filled-in constraints.md for the adopted "taskboard" project.
     Produced by /adopt-project; conventions cite real files as evidence. -->

## Layering

| Layer | Directory | May depend on |
|---|---|---|
| routes | `src/routes/` | services |
| services | `src/services/` | db |
| db | `src/db/` | nothing internal |

Dependency rule: requests flow routes → services → db and never skip or reverse a step.
Routes contain no business logic and never touch the database directly; db modules never
import from services or routes. Enforced by `.claude/workflow/boundaries.rules`
(`deny routes -> db`, `deny db -> services`, `deny db -> routes`,
`deny services -> routes`).

## Invariants

- No secrets in the repo; configuration comes from environment variables read only in `src/config.js` — enforced by: pre-commit-security hook + `config.js` being the single `process.env` reader (review only).
- Every mutation writes an audit row in the same transaction as the change — enforced by: review only (services construct audit rows; see `src/services/tasks.js`).
- All handlers validate input at the route boundary before calling services — enforced by: review only; validator middleware pattern, see `src/routes/boards.js`.

## Observed conventions

- Modules export a plain object of async functions; no classes — example: `src/services/boards.js`
- Errors: services throw `AppError(code, message, httpStatus)`; the single translation to HTTP happens in `src/middleware/error.js`. Routes never try/catch — example: `src/routes/tasks.js`
- SQL lives only in `src/db/*.js` as tagged-template queries via the shared `q` helper; no ORM — example: `src/db/tasks.js`
- Tests mirror source paths: `src/services/tasks.js` → `test/services/tasks.test.js`, node:test runner, no mocking library (hand-rolled fakes) — example: `test/services/boards.test.js`

## Error handling

Services throw typed `AppError`s (`src/lib/app-error.js`); `src/middleware/error.js` is
the only place mapping them to HTTP responses. Unknown errors become 500 with a logged
correlation id, never a leaked stack trace.

## Testing

`node --test test/` runs everything. Every acceptance criterion in a phase spec has at
least one automated test; route tests go through the real middleware stack with an
in-memory SQLite database (`test/helpers/db.js`).
