# Phase index — {{PROJECT_NAME}}

<!-- The single source of truth for execution state. Machine-parsed (grep/awk)
     and human-read after compaction — keep the table format EXACT.

     Status vocabulary (only these five, lowercase):
       pending      indexed, not yet expanded
       expanded     spec.md written, not started
       in-progress  implementation started (also: failed validation, being fixed)
       blocked: <reason>   needs an operator decision — reason is mandatory
       done         validation passed; only /validate-phase writes this

     Rules:
       - `depends` lists phase ids, comma-separated, or `-`. These are edges,
         not an ordering: rows with no path between them may run in parallel.
       - Acceptance here is the coarse, one-line form; the executable form
         lives in the phase's spec.md once expanded.
       - Rows are append-only per feature section; never renumber ids. -->

## Feature: {{feature name}}  ({{/plan-feature date}})

{{Two sentences: what changes for the user, and the scope edge — what this
feature deliberately does not include.}}

| id | goal | depends | acceptance (coarse) | status |
|----|------|---------|---------------------|--------|
| {{NN-slug}} | {{one line}} | {{ids or -}} | {{one line}} | pending |
