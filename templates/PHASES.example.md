# Phase index — taskboard

<!-- Example: state as it looks mid-feature. 05 passed validation, 06 is being
     implemented, 07 waits on 06, 08 is independent of 07 (edge-parallel). -->

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
