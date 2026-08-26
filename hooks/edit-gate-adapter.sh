#!/usr/bin/env bash
# Adapter: Claude Code PostToolUse (matcher Edit|Write) -> the file gates.
#
# The gates take a path and return an exit code; this translates one agent
# payload into that call. It is the only file in the enforcement layer that
# parses JSON, which is why the fail-closed contract lives here and not in the
# gates any more.
#
# PostToolUse cannot block — the edit already happened. Exit 2 returns stderr to
# Claude, which fixes the file in the same turn (P3).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib/common.sh"
hook_init

# No jq/python3: exiting 0 would leave the gates silently not-run, the one thing
# P7 forbids. Exit 2 so the message reaches Claude instead of dying in an
# ignored stream.
FILE="$(json_get .tool_input.file_path)" || {
  echo "EDIT GATES DID NOT RUN: no jq or python3 on PATH to read the hook input, so the file you just edited was NOT formatted, linted, typechecked or checked against boundaries.rules. Install jq or python3." >&2
  exit 2
}
[ -n "$FILE" ] || FILE="$(json_get .file_path)"   # Cursor payload shape
[ -n "$FILE" ] || exit 0

# Run both, collect both: a file can fail lint and cross a layer boundary at the
# same time, and reporting only the first would hide the second until the next
# edit.
status=0
for gate in post-edit-gate boundary-check; do
  "$DIR/$gate.sh" "$FILE" || status=2
done
exit "$status"
