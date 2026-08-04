# Phase index — taskboard

<!-- Example: state as it looks mid-feature. 05 passed validation, 06 is being
     implemented, 07 waits on 06, 08 is independent of 07 (edge-parallel). 09 shows
     a cut that proved wrong once 05 landed: the row keeps its id and its goal
     untouched, gets `superseded by`, and the replacement is appended as 10 — the
     old row is the record of why the plan used to look like that. -->

## Feature: per-key rate limiting  (2026-07-21)

Abusive API consumers get HTTP 429 per R4, keyed by API key, without affecting other
keys. Not included: quota reporting endpoints, per-route limits, admin UI — see
ADR-0004 for the middleware + SQLite decision this plan implements.

| id | goal | depends | acceptance (coarse) | status |
|----|------|---------|---------------------|--------|
| 05-rate-counter-store | fixed-window counter table + db accessor with atomic increment | - | counter increments atomically under concurrent calls; window rolls over | done |
| 06-rate-limit-middleware | middleware returns 429 over limit, sets RateLimit headers | 05-rate-counter-store | integration test: 429 on limit breach, 200 under limit, headers present | in-progress |
| 07-per-key-limits | per-key overrides in api_keys table, fall back to global default | 06-rate-limit-middleware | key with custom limit enforced at that limit; others at default | pending |
| 08-audit-limit-events | limit breaches recorded to the audit trail (R2) | 05-rate-counter-store | breach produces queryable audit row | pending |
| 09-limits-config-file | global default limits read from config/limits.json at boot | - | changing the file changes the enforced default after restart | superseded by 10-limits-config-table |
| 10-limits-config-table | replaces 09: global default limits read from the settings table, not a file — 05's notes showed the counters already need a db round-trip per request | 05-rate-counter-store | changing the row changes the enforced default with no restart | pending |
