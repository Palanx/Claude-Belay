#!/usr/bin/env bash
# Shared helpers for workflow hooks. Sourced by the hook scripts, never executed.
#
# Contract:
#   source common.sh; hook_init
# then these are available:
#   $ROOT        project root ($CLAUDE_PROJECT_DIR, falling back to $PWD)
#   $TOOLCHAIN   path to .claude/workflow/toolchain.json (may not exist)
#   $HOOK_INPUT  raw stdin JSON from Claude Code
#   json_get, json_file_get, tc_cmd, tc_file_cmd, gap_warn, run_on_file
#
# JSON parsing needs jq or python3. Every machine that runs Claude Code has a
# shell; nearly every one has python3; most have jq. If neither exists the hook
# says so loudly instead of pretending to have checked anything.

set -u

hook_init() {
  ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
  TOOLCHAIN="$ROOT/.claude/workflow/toolchain.json"
  HOOK_INPUT="$(cat)"
}

# _json_read <dot.path>  — reads JSON on stdin, prints the value at path
# (empty if absent). Scalars print raw; objects/arrays print as JSON.
_json_read() {
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1 // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$1" <<'PY'
import json, sys
path = sys.argv[1].lstrip('.')
try:
    obj = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for key in path.split('.'):
    if isinstance(obj, dict) and key in obj:
        obj = obj[key]
    else:
        sys.exit(0)
if isinstance(obj, (dict, list)):
    print(json.dumps(obj))
elif obj is not None:
    print(obj)
PY
  else
    echo "workflow hook error: need jq or python3 on PATH to parse hook input — nothing was checked" >&2
    return 1
  fi
}

# json_get <dot.path> — value from $HOOK_INPUT (e.g. json_get .tool_input.file_path)
json_get() {
  printf '%s' "$HOOK_INPUT" | _json_read "$1"
}

# json_file_get <file> <dot.path>
json_file_get() {
  _json_read "$2" <"$1"
}

# tc_cmd <category> — project-wide command for a toolchain category
# (test | typecheck | audit | secrets). Empty if unconfigured.
tc_cmd() {
  [ -f "$TOOLCHAIN" ] || return 0
  json_file_get "$TOOLCHAIN" ".commands.$1"
}

# tc_file_cmd <ext> <category> — per-file command template for a file extension
# (lint | format | typecheck). May contain {file}. Empty if unconfigured.
tc_file_cmd() {
  [ -f "$TOOLCHAIN" ] || return 0
  json_file_get "$TOOLCHAIN" ".file_commands.$1.$2"
}

# gap_warn <category> <what was not checked>
# The loud version of skipping: the operator and the agent both see exactly
# which gate did not run and why. Never skip silently (P7).
gap_warn() {
  echo "workflow gap: no '$1' tool configured — $2 was NOT checked. Fix: run /adopt-project (re-detect) or add the command to .claude/workflow/toolchain.json." >&2
}

# run_on_file "<template>" <file> — runs a toolchain command against one file.
# If the template contains {file} it is substituted (quoted); otherwise the
# file path is appended as the last argument.
run_on_file() {
  local tmpl="$1" file="$2"
  if [[ "$tmpl" == *"{file}"* ]]; then
    bash -c "${tmpl//\{file\}/\"$file\"}"
  else
    bash -c "$tmpl \"\$1\"" _ "$file"
  fi
}
