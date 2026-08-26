#!/usr/bin/env bash
# Cursor CLI hook adapter — wired by `install.sh --cursor` through .cursor/hooks.json.
# Cursor's hook events and payload differ from Claude Code's; the belay hooks
# accept both payload shapes, so this script only dispatches the event to the
# right hooks and maps their exit codes onto Cursor's permission protocol:
#
#   afterFileEdit        -> post-edit-gate.sh + boundary-check.sh
#                           (observational: Cursor ignores afterFileEdit output,
#                           so the fix-it-same-turn loop of Claude Code is weaker
#                           here — /validate-phase remains the hard gate)
#   beforeShellExecution -> bash-gate-adapter.sh (exit 2 => permission deny)
#
# belay-debt: this whole adapter is verified by inspection only — never run with
# Cursor actually installed, so the event names, the payload field names, the
# permission protocol and the relative command path in .cursor/hooks.json are all
# read off the docs rather than observed. Nothing in tests/corporate-smoke.sh can
# cover it; the suite only asserts the files land. Test it by installing with
# --cursor into a scratch repo, opening it in Cursor, then: (1) edit a source file
# with a lint error — the post-edit gate should run (its output may go nowhere,
# which is expected, see above); (2) stage a file containing AKIAIOSFODNN7EXAMPLE
# and have the agent run `git commit` — this must be DENIED. If (2) passes
# silently, the gate never ran: suspect the relative command path first (see the
# cwd note below), then the payload field names in json_get calls.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
# Adapter lives at <root>/.claude/hooks/, so the root is two levels up. Two
# separate things depend on cwd, and only one of them is ours:
#   - .cursor/hooks.json names this script relatively ("./.claude/hooks/..."),
#     which is Cursor's own documented form and is resolved against the project
#     root by Cursor. If hooks stop firing entirely after a Cursor update, that
#     resolution is the first thing to check — nothing here can compensate for a
#     command that never ran.
#   - The process cwd once we ARE running, which Cursor does not promise is the
#     root, and which the child hooks need for git and toolchain lookups. Hence
#     deriving it from $0 rather than trusting $PWD; Cursor also does not set
#     CLAUDE_PROJECT_DIR, which is what the belay hooks read.
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$DIR/../.." && pwd)}"
. "$DIR/lib/common.sh"
hook_init

EVENT="$(json_get .hook_event_name 2>/dev/null)" || EVENT=""
if [ -z "$EVENT" ]; then
  # No jq/python3 — substring dispatch; the child hooks fail closed themselves.
  case "$HOOK_INPUT" in
    *beforeShellExecution*) EVENT=beforeShellExecution ;;
    *afterFileEdit*)        EVENT=afterFileEdit ;;
  esac
fi

emit() { # emit <allow|deny> <message>
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg p "$1" --arg m "$2" \
      '{permission:$p} + (if $m == "" then {} else {agentMessage:$m, userMessage:$m} end)'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys;p,m=sys.argv[1:3];o={"permission":p};m and o.update(agentMessage=m,userMessage=m);print(json.dumps(o))' "$1" "$2"
  else
    printf '{"permission":"%s","agentMessage":"belay: install jq or python3 to see gate details"}\n' "$1"
  fi
}

case "$EVENT" in
  afterFileEdit)
    # The gates take a path. Extract it once here rather than re-parsing the
    # payload inside each one — see post-edit-gate.sh for the gate/adapter split.
    FILE="$(json_get .file_path 2>/dev/null)" || FILE=""
    [ -n "$FILE" ] || FILE="$(json_get .tool_input.file_path 2>/dev/null)" || FILE=""
    if [ -n "$FILE" ]; then
      "$DIR/post-edit-gate.sh" "$FILE" || true
      "$DIR/boundary-check.sh" "$FILE" || true
    fi
    exit 0 ;;
  beforeShellExecution)
    if err="$(printf '%s' "$HOOK_INPUT" | "$DIR/bash-gate-adapter.sh" 2>&1 >/dev/null)"; then
      emit allow ""
    else
      emit deny "$err"
    fi ;;
  *) exit 0 ;;
esac
