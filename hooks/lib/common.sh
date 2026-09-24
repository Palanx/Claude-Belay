#!/usr/bin/env bash
# Shared helpers for workflow hooks. Sourced by the hook scripts, never executed.
#
# Contract:
#   source common.sh; hook_init          (hooks: adds $HOOK_INPUT and json_get)
#   source common.sh; tc_init            (CLI callers: everything except those two)
# then these are available:
#   $ROOT        project root ($CLAUDE_PROJECT_DIR, falling back to $PWD)
#   $TOOLCHAIN   path to .claude/workflow/toolchain.json (may not exist)
#   $MANUAL      path to .claude/workflow/toolchain.manual.json (may not exist)
#   $HOOK_INPUT  raw stdin JSON from Claude Code
#   json_get, json_file_get, tc_cmd, tc_file_cmd, tc_exempt_prefixes, gap_warn, run_on_file
#   is_cfamily, cpp_lines, layer_hits   (boundary matching; see their comments)
#
# JSON parsing needs jq or python3. Every machine that runs Claude Code has a
# shell; nearly every one has python3; most have jq. If neither exists the hook
# says so loudly instead of pretending to have checked anything.

set -u

# tc_init — resolve project paths only. Safe for CLI callers: reads no stdin.
tc_init() {
  ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
  TOOLCHAIN="$ROOT/.claude/workflow/toolchain.json"
  # Project-owned half of the toolchain. detect-toolchain.sh rewrites
  # toolchain.json wholesale on every re-detection, so anything hand-added there
  # is lost at the next /refresh-index. The detector never opens this file — it
  # cannot clobber what it does not read — and every accessor below prefers it.
  MANUAL="$ROOT/.claude/workflow/toolchain.manual.json"
}

hook_init() {
  tc_init
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
# (test | typecheck | audit | secrets). Manual wins over detected. Empty if
# unconfigured in both.
tc_cmd() {
  local v=""
  # Each read is guarded: json_file_get redirects from the path, so an absent
  # file would be a shell error on stderr, not an empty string.
  [ -f "$MANUAL" ] && v="$(json_file_get "$MANUAL" ".commands.$1")"
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  [ -f "$TOOLCHAIN" ] || return 0
  json_file_get "$TOOLCHAIN" ".commands.$1"
}

# tc_file_cmd <ext> <category> — per-file command template for a file extension
# (lint | format | typecheck). May contain {file}. Manual wins over detected.
# Empty if unconfigured in both.
tc_file_cmd() {
  local v=""
  [ -f "$MANUAL" ] && v="$(json_file_get "$MANUAL" ".file_commands.$1.$2")"
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  [ -f "$TOOLCHAIN" ] || return 0
  json_file_get "$TOOLCHAIN" ".file_commands.$1.$2"
}

# tc_exempt_prefixes — newline-separated path prefixes from the "exempt" arrays
# (engine-owned / third-party trees the edit gates must skip).
# Unlike the command accessors this APPENDS rather than overrides: exempt is a
# list, and a project adding one tree never means dropping the detected ones.
tc_exempt_prefixes() {
  _exempt_from "$TOOLCHAIN"
  _exempt_from "$MANUAL"
}

_exempt_from() { # _exempt_from <json-file>
  [ -f "$1" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.exempt // [])[]' "$1" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$1" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for p in data.get("exempt", []):
    print(p)
PY
  fi
}

# gap_warn <category> <what was not checked>
# The loud version of skipping: the operator and the agent both see exactly
# which gate did not run and why. Never skip silently (P7).
gap_warn() {
  echo "workflow gap: no '$1' tool configured — $2 was NOT checked. Fix: run /adopt-project (re-detect), or add the command to .claude/workflow/toolchain.manual.json — the project-owned file re-detection never overwrites." >&2
}

# run_on_file "<template>" <file> — runs a toolchain command against one file.
# If the template contains {file} it is substituted (quoted); otherwise the
# file path is appended as the last argument.
run_on_file() {
  local tmpl="$1" file="$2"
  if [[ "$tmpl" == *"{file}"* ]]; then
    bash -c "${tmpl//\{file\}/\"\$1\"}" _ "$file"
  else
    bash -c "$tmpl \"\$1\"" _ "$file"
  fi
}

# --- boundary matching, shared by boundary-check.sh and include-check.sh ------

# is_cfamily <file> — true for the extensions cpp_lines may preprocess. Everything else
# is read raw: in Python, shell or Ruby `# if 0` is an ordinary comment, and treating it
# as a conditional would skip to an `#endif` that never comes and exempt the rest.
is_cfamily() {
  case "$1" in
    *.c|*.h|*.cc|*.cpp|*.cxx|*.c++|*.hpp|*.hh|*.hxx|*.h++|*.inl|*.ipp|*.tpp|*.ixx|*.cppm|*.m|*.mm) return 0 ;;
    *) return 1 ;;
  esac
}

# cpp_lines <file> — a C-family file as the preprocessor would hand it to an include
# scan, one `N:text` per logical line (N = its first physical line): `\` continuations
# joined, `#if 0` regions dropped (nesting counted, `#else`/`#elif` at depth 1 ends one),
# and `#include NAME` expanded when NAME is `#define`d to "…" or <…> earlier in the same
# file. Not a preprocessor: no other conditional is evaluated, and a macro defined in
# another header stays unexpanded.
cpp_lines() {
  awk '
    buf == "" { start = NR }
    /\\$/ { buf = buf substr($0, 1, length($0) - 1); next }
    {
      line = buf $0; buf = ""
      if (dead) {
        if (line ~ /^[ \t]*#[ \t]*if(def|ndef)?([^A-Za-z0-9_]|$)/) dead++
        else if (line ~ /^[ \t]*#[ \t]*endif/) dead--
        else if (dead == 1 && line ~ /^[ \t]*#[ \t]*el(se|if)/) dead = 0
        next
      }
      if (line ~ /^[ \t]*#[ \t]*if[ \t]+0([^0-9A-Za-z_]|$)/) { dead = 1; next }
      if (line ~ /^[ \t]*#[ \t]*define[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+["<]/) {
        d = line; sub(/^[ \t]*#[ \t]*define[ \t]+/, "", d)
        name = d; sub(/[ \t].*/, "", name)
        val = d; sub(/^[A-Za-z_][A-Za-z0-9_]*[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
        mac[name] = val
      } else if (line ~ /^[ \t]*#[ \t]*include(_next)?[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*$/) {
        name = line; sub(/^[ \t]*#[ \t]*include(_next)?[ \t]+/, "", name); sub(/[ \t]+$/, "", name)
        if (name in mac) line = "#include " mac[name]
      }
      print start ":" line
    }
    END { if (buf != "") print start ":" buf }
  ' "$1" 2>/dev/null
}

# Import-ish lines, matched after the `N:` prefix every source line carries here.
BOUNDARY_IMPORT_RE='^[0-9]+:[[:space:]]*((import|export|from|require|include|use|using)[[:space:](]|#[[:space:]]*include(_next)?[[:space:]"<])|require\(|import\('

# layer_hits <file> <layer-prefix> — the file's import-ish lines that name that layer: its
# full prefix, or its directory name bounded by a path separator, quote or `<` (matches
# ../infra/x, src/infra/x, <infra/x.h>); in C-family files also a C++20 module import
# whose first component is the directory name (`import infra.db;`). Prints N:text lines.
layer_hits() {
  local f="$1" tprefix="$2" tdir mod="" lines
  tdir="$(basename "$tprefix")"
  if is_cfamily "$f"; then
    lines="$(cpp_lines "$f")"
    mod="|^[0-9]+:[[:space:]]*(export[[:space:]]+)?import[[:space:]]+$tdir[.;]"
  else
    lines="$(grep -n '' "$f" 2>/dev/null)"
  fi
  printf '%s\n' "$lines" | grep -E "$BOUNDARY_IMPORT_RE" \
    | grep -E "$tprefix|[/\"'<[:space:]]$tdir/$mod" || true
}
