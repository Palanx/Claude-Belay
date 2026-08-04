# Phase index — {{PROJECT_NAME}}

<!-- The single source of truth for execution state. Machine-parsed (grep/awk)
     and human-read after compaction — keep the table format EXACT.

     Status vocabulary (only these six, lowercase):
       pending      indexed, not yet expanded
       expanded     spec.md written, not started
       in-progress  implementation started (also: failed validation, being fixed)
       blocked: <reason>   needs an operator decision — reason is mandatory.
                    Cleared by the operator answering it; /implement-phase then
                    resumes the phase and sets it back to in-progress.
       superseded by <ids>   this cut turned out wrong; the ids that replace it
                    are appended as new rows by /plan-feature. A terminal
                    status: the row stays for the record, nothing runs it.
       done         validation passed; only /validate-phase writes this

     Rules:
       - `depends` lists phase ids, comma-separated, or `-`. These are edges,
         not an ordering: rows with no path between them may run in parallel.
       - Acceptance here is the coarse, one-line form; the executable form
         lives in the phase's spec.md once expanded.
       - Rows are append-only per feature section; never renumber ids. A cut
         that proves wrong is superseded, never edited or deleted — same
         discipline as an ADR, and for the same reason: the old row is the
         record of why the plan used to look like that. -->

## Feature: {{feature name}}  ({{/plan-feature date}})

{{Two sentences: what changes for the user, and the scope edge — what this
feature deliberately does not include.}}

| id | goal | depends | acceptance (coarse) | status |
|----|------|---------|---------------------|--------|
| {{NN-slug}} | {{one line}} | {{ids or -}} | {{one line}} | pending |
