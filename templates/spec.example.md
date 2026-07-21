# Phase 06-rate-limit-middleware — enforce limits in middleware, return 429

<!-- Example of an expanded spec for the taskboard project. Note how the
     Context pointers make the phase self-contained (P5), and how every
     acceptance criterion is a runnable command (P3). -->

## Goal

Requests carrying an API key that has exceeded its per-minute request budget receive
`429 Too Many Requests` with `RateLimit-Limit`, `RateLimit-Remaining` and
`RateLimit-Reset` headers; requests under budget pass through unchanged and also carry
the headers. The middleware sits after auth (needs the resolved key) and before routing,
per ADR-0004. Uses the fixed-window counter store built in phase 05.

## Context pointers

- `docs/adr/0004-rate-limit-middleware-sqlite.md` — the decision this phase implements; do not re-litigate storage choice
- `docs/phases/05-rate-counter-store/notes.md` — 05 renamed the accessor to `hitAndCount()` (deviation from its spec) and documents its return shape `{count, resetAt}`
- `src/db/rate-counters.js` — the store API this middleware calls (built in 05)
- `src/middleware/auth.js` — how a resolved key lands on `req.apiKey`; this middleware mounts right after it
- `src/middleware/error.js` — AppError → HTTP mapping; 429 goes through it like every other error
- `src/app.js` — middleware mount order lives here; this phase edits it
- `test/middleware/auth.test.js` — the existing middleware test pattern to mirror (real stack, in-memory db via `test/helpers/db.js`)

## Plan

1. Add `RateLimitError` (extends AppError, code `RATE_LIMITED`, status 429) — touches `src/lib/app-error.js`
2. Write the middleware: read `req.apiKey`, call `hitAndCount(key, window)`, attach RateLimit headers, throw `RateLimitError` when `count > limit` (global default limit from config for now — per-key limits are phase 07) — touches `src/middleware/rate-limit.js` (new)
3. Mount after auth, before routes — touches `src/app.js`
4. Map `RATE_LIMITED` to include headers on the error response — touches `src/middleware/error.js`
5. Integration tests per acceptance criteria — touches `test/middleware/rate-limit.test.js` (new)

## Acceptance criteria

```
node --test test/middleware/rate-limit.test.js   # expect: exit 0; covers 200-under-limit, 429-over-limit, headers on both paths, window reset
node --test test/                                # expect: exit 0 (nothing else broke)
npx eslint src/middleware/rate-limit.js src/app.js src/lib/app-error.js src/middleware/error.js   # expect: exit 0
grep -rn "rate-counters" src/routes/             # expect: exit 1, no matches — routes never touch counters directly (ADR-0004: only the middleware does)
```

## Out of scope

- Per-key custom limits — phase 07-per-key-limits
- Audit rows for breaches — phase 08-audit-limit-events
- Retry-After header nuances / draft-RFC full compliance — no phase; not wanted (internal API, headers above suffice)
