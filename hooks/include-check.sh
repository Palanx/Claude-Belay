#!/usr/bin/env bash
# Gate: transitive include check on one C-family file.
#
#   include-check.sh <file>
#
# boundary-check.sh judges the lines of the file it is handed, so it cannot see
# src/core/x.cpp reach a denied layer through src/common/y.h — a header that sits in
# no declared layer and is therefore judged by nothing. This gate follows the chain.
# Takes a path, returns an exit code — no payload, no stdin.
#
# Wired into scripts/check.sh only (--files, --staged, and so /validate-phase's
# boundary sweep), never into the edit adapters: it reads files other than its
# argument, and an edit-time gate that walks the include graph on every keystroke
# costs more than the edit it guards. The per-edit layer check stays boundary-check.sh.
#
# Both ends of a chain are caught:
#   - a file in a layer: follow its includes breadth-first through headers in no
#     layer; any such header whose lines name a layer this file's layer is denied is a
#     violation. A header inside a layer ends the walk — its own rules judge it.
#   - a file in no layer (the header an edit actually touched): find the layered
#     C-family files that include it by basename, and run the first case on each.
#
# An include resolves to the first existing file among: the including file's
# directory, the repo root, and the parent of each declared layer prefix (so
# "common/y.h" from src/core/ finds src/common/y.h). Anything else — a system header,
# a path only a -I flag reaches — is not followed. The layer-name match on each header
# is boundary-check.sh's own (layer_hits in lib/common.sh).
#
# Exit codes: the same contract as boundary-check.sh.
#   2  forbidden dependency reached; stderr carries the rule and the chain.
#   0  everything else, including: no boundaries.rules, not a C-family file, no chain.
#   No other code is produced, and none may be added: scripts/check.sh treats any
#   non-zero as a violation.
set -u
. "$(dirname "$0")/lib/common.sh"
tc_init

RULES="$ROOT/.claude/workflow/boundaries.rules"
[ -f "$RULES" ] || exit 0
FILE="${1:-}"
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
is_cfamily "$FILE" || exit 0

# Physical paths throughout: `../` in an include and a symlinked /tmp would otherwise
# give one file two names and defeat both the visited set and the layer match.
ROOTP="$(cd "$ROOT" && pwd -P)"
norm() { local d; d="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 1; echo "$d/$(basename "$1")"; }
rel() { case "$1" in "$ROOTP"/*) echo "${1#"$ROOTP"/}" ;; *) echo "$1" ;; esac; }

LAYERS=()   # "name prefix"
while read -r _ name prefix; do [ -n "$prefix" ] && LAYERS+=("$name $prefix"); done \
  < <(grep -E '^layer[[:space:]]' "$RULES")
[ ${#LAYERS[@]} -gt 0 ] || exit 0

layer_of() { # longest matching prefix wins, as in boundary-check.sh
  local r="$1" best="" len=0 l
  for l in "${LAYERS[@]}"; do
    case "$r" in "${l#* }"*) [ ${#l} -gt "$len" ] && { best="${l%% *}"; len=${#l}; } ;; esac
  done
  echo "$best"
}
layer_prefix() { local l; for l in "${LAYERS[@]}"; do [ "${l%% *}" = "$1" ] && { echo "${l#* }"; return; }; done; }

ROOTS=("$ROOTP")
for l in "${LAYERS[@]}"; do
  p="$(dirname "${l#* }")"; [ "$p" = . ] || ROOTS+=("$ROOTP/$p")
done

resolve() { # resolve <target> <including file> — physical path, or nothing
  local base
  for base in "$(dirname "$2")" "${ROOTS[@]}"; do
    [ -f "$base/$1" ] && { norm "$base/$1"; return; }
  done
}
includes_of() { # "N target" per include line
  cpp_lines "$1" | sed -nE 's/^([0-9]+):[[:space:]]*#[[:space:]]*include(_next)?[[:space:]]*["<]([^">]+)[">].*/\1 \3/p'
}

violations=""
forward() { # forward <physical path of a layered file>
  local start="$1" from denied=() to cur chain n t r h tp
  from="$(layer_of "$(rel "$start")")"
  while read -r _ f arrow to; do
    [ "$arrow" = "->" ] && [ "$f" = "$from" ] && tp="$(layer_prefix "$to")" && [ -n "$tp" ] \
      && denied+=("$to $tp")
  done < <(grep -E '^deny[[:space:]]' "$RULES")
  [ ${#denied[@]} -gt 0 ] || return 0

  local -A seen=(["$start"]=1)
  local queue=("$start|$(rel "$start")")
  while [ ${#queue[@]} -gt 0 ]; do
    cur="${queue[0]%%|*}" chain="${queue[0]#*|}"; queue=("${queue[@]:1}")
    while read -r n t; do
      r="$(resolve "$t" "$cur")"
      [ -n "$r" ] && [ -z "${seen[$r]:-}" ] || continue
      seen[$r]=1
      [ -z "$(layer_of "$(rel "$r")")" ] || continue
      for to in "${denied[@]}"; do
        h="$(layer_hits "$r" "${to#* }")"
        [ -n "$h" ] && violations="$violations
Rule violated: deny $from -> ${to%% *}   ($(rel "$start") is in layer '$from')
  chain: $chain:$n -> $(rel "$r")
$(printf '%s\n' "$h" | sed "s#^#  $(rel "$r"):#")"
      done
      queue+=("$r|$chain:$n -> $(rel "$r")")
    done < <(includes_of "$cur")
  done
}

SELF="$(norm "$FILE")"
if [ -n "$(layer_of "$(rel "$SELF")")" ]; then
  forward "$SELF"
else
  base="$(basename "$SELF")"; base_re="${base//./\\.}"
  for l in "${LAYERS[@]}"; do
    [ -d "$ROOTP/${l#* }" ] || continue
    while IFS= read -r c; do
      is_cfamily "$c" && forward "$(norm "$c")"
    done < <(grep -rlE "#[[:space:]]*include.*[\"</]$base_re[\">]" "$ROOTP/${l#* }" 2>/dev/null)
  done
fi

if [ -n "$violations" ]; then
  {
    echo "BOUNDARY VIOLATION (transitive include): $(rel "$SELF")"
    echo "$violations"
    echo ""
    echo "A header in no declared layer carries this dependency, so the layered file"
    echo "depends on the denied layer without naming it. Do ONE of:"
    echo "  1. Remove the include from the chain, or route it through the allowed layer."
    echo "  2. Declare the header's directory as a layer in .claude/workflow/boundaries.rules"
    echo "     (a rules change requires a new ADR in docs/adr/, never a silent edit)."
  } >&2
  exit 2
fi
exit 0
