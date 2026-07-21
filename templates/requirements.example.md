# Requirements — taskboard

<!-- Example of a filled-in requirements.md, for the fictional "taskboard"
     project used across all workflow examples. -->

## Purpose

A small HTTP API for shared task lists, used by internal tools at a ~40-person company.
It replaces a shared spreadsheet that breaks weekly under concurrent edits and has no
change history.

## Users

- Internal web dashboard (primary consumer, ~30 requests/min peak).
- Ops scripts that create tasks from monitoring alerts (bursty, unauthenticated today — see OPEN below).

## Capabilities

- **R1** — CRUD for boards and tasks over JSON HTTP; concurrent edits must not lose writes (last-write-wins is acceptable, silent loss is not — responses carry the revision applied).
- **R2** — Every mutation is recorded in an audit trail queryable per board (`who, what, when`), retained 90 days.
- **R3** — API keys per consumer; a key can be revoked without redeploying.
- **R4** — Abusive consumers can be rate-limited per key without affecting others.

## Non-goals

- No user-facing UI — the dashboard team owns that; we ship the API only.
- No real-time push (websockets/SSE) — consumers poll; revisit only if the dashboard team measures polling as a real cost.
- No multi-tenancy beyond API keys — single company, single database.

## Hard constraints

- Must run on the existing single-VM Docker host; no new cloud services this quarter (finance freeze).
- P99 read latency under 200 ms at the stated peak load.

## Open questions

- OPEN: do the ops scripts get their own API keys, or a shared "system" key? (Answer owner: ops lead. Blocks the key-issuance phase.)
