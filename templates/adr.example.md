# ADR-0004: Rate limiting is enforced in middleware, keyed by API key, with counters in SQLite

- Status: accepted
- Date: 2026-07-21

## Context

R4 requires per-key rate limiting. The deployment is a single VM (hard constraint in
requirements.md), and ADR-0002 (reconstructed) records SQLite as the only datastore.
Introducing Redis for counters would add the first new infrastructure service to the
deployment, contradicting the no-new-services freeze.

## Decision

Enforce rate limits in an Express middleware placed after authentication (it needs the
resolved API key), before routing. Counters live in a `rate_counters` table in the
existing SQLite database using fixed 60-second windows. Limits are configured per key in
the `api_keys` table with a global default. This adds no new layer: middleware lives with
the other middleware in `src/middleware/`, counter access goes through `src/db/` like all
other SQL (no boundaries.rules change).

## Consequences

Easier: one datastore, one deployment artifact, limits administrable through the existing
key-management path. Harder: fixed windows allow up to 2× burst at window edges (accepted
— R4 is about abuse, not precision), and SQLite write contention caps throughput far
above current peak but below "web scale" (accepted; single-company tool). Revisit only if
the VM constraint falls. Rejected: Redis token bucket (new service, freeze), in-process
memory counters (lost on restart, wrong across future multi-process deployment).
