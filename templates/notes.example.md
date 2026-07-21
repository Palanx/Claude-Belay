# Phase 05-rate-counter-store — notes

<!-- Example of a filled-in notes.md (taskboard). Note how the Deviations
     entry here is exactly what phase 06's spec later pointed to — this is
     P4/P6 working: the plan learned from the implementation. -->

## Outcome

`rate_counters` table (migration `src/db/migrations/007-rate-counters.sql`) and accessor
`src/db/rate-counters.js` exporting `hitAndCount(key, windowSeconds)` → `{count,
resetAt}`. Increment is a single `INSERT ... ON CONFLICT ... UPDATE ... RETURNING`
statement, so concurrent hits from multiple processes count correctly. Expired windows
are lazily deleted on access (no background job). Tests in
`test/db/rate-counters.test.js` including a 50-parallel-hits atomicity test.

## Deviations

- Spec named the accessor `increment()` returning a bare count. Renamed to `hitAndCount()` returning `{count, resetAt}` — the middleware (06) will need the reset time for the `RateLimit-Reset` header, and computing it twice invites clock-skew bugs. Spec amended in place; this entry is the record.

## Debt

- Lazy deletion means dead windows linger until a key is seen again — table grows with abandoned keys. Ceiling: irrelevant below ~10⁵ keys. Upgrade path: `DELETE FROM rate_counters WHERE reset_at < now` in the existing nightly maintenance script (`scripts/vacuum.sh`).

## For later phases

- `hitAndCount` return shape is `{count, resetAt}` (epoch seconds) → 06-rate-limit-middleware builds headers from it; do not re-query.
- SQLite `busy_timeout` was already set globally in `src/db/index.js` (found during the atomicity test) → 06 needs no extra retry logic on contention.
- The `api_keys` table has no `rate_limit` column yet → 07-per-key-limits adds it; global default should live in config until then.

## Validation — 2026-07-21

- criteria: 4 passed / 0 failed
- project gates: test pass, lint pass, typecheck gap (no typechecker configured — reported)
- boundary sweep: clean
- closure test: pass
- verdict: done
