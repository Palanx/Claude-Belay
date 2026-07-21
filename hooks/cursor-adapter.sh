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
#   beforeShellExecution -> pre-commit-security.sh (exit 2 => permission deny)
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
# Adapter lives at <root>/.claude/hooks/ — derive the root from that; Cursor
# does not set CLAUDE_PROJECT_DIR and may not run hooks from the project root.
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
    printf '%s' "$HOOK_INPUT" | "$DIR/post-edit-gate.sh" || true
    printf '%s' "$HOOK_INPUT" | "$DIR/boundary-check.sh" || true
    exit 0 ;;
  beforeShellExecution)
    if err="$(printf '%s' "$HOOK_INPUT" | "$DIR/pre-commit-security.sh" 2>&1 >/dev/null)"; then
      emit allow ""
    else
      emit deny "$err"
    fi ;;
  *) exit 0 ;;
esac
