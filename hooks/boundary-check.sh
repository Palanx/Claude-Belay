#!/usr/bin/env bash
# Gate: architectural boundary check on one file.
#
#   boundary-check.sh <file>
#
# Flags import-ish lines that reference a layer this file's own layer is
# forbidden from depending on. Takes a path, returns an exit code — no payload,
# no stdin. See post-edit-gate.sh for the gate/adapter split.
#
# Rules file: .claude/workflow/boundaries.rules
#   layer <name> <dir-prefix>/     (e.g.  layer domain src/domain/)
#   deny <from-layer> -> <to-layer>
#
# belay-debt: grep heuristic, not AST resolution. It matches import/require/use/
# include lines that mention the denied layer's directory name or full prefix.
# Catches the realistic violations (direct path imports); aliased or dynamic
# imports can slip through — mirror the rule in CI with a real resolver if that
# matters to you. Upgrade path: dependency-cruiser (js), import-linter (py).
#
# Exit codes:
#   2  forbidden dependency found; stderr carries the rule and the offending lines.
#   0  everything else — one verdict for two situations a caller cannot tell apart:
#      checked and clean, or no rule reached the file (no boundaries.rules, no path
#      argument, path is not a file, or the file sits under no declared `layer`
#      prefix). The last is the normal state of a fresh install: install.sh writes
#      the rules file fully commented out, so nothing is layered until
#      /bootstrap-project or /adopt-project fills it in. That silence is deliberate —
#      post-edit-gate.sh passes docs and engine assets the same way; out of scope by
#      configuration is not a gap, and a per-file warning would fire on every edit.
#   No other code is produced, and none may be added: edit-gate-adapter.sh and
#   scripts/check.sh treat any non-zero as a violation, so a third code would reach
#   the operator as a layering breach.
set -u
. "$(dirname "$0")/lib/common.sh"
tc_init

RULES="$ROOT/.claude/workflow/boundaries.rules"
[ -f "$RULES" ] || exit 0

FILE="${1:-}"
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
case "$FILE" in
  "$ROOT"/*) REL="${FILE#"$ROOT"/}" ;;
  *) REL="$FILE" ;;
esac

# Which layer does the edited file live in? Longest matching prefix wins.
FROM="" FROM_LEN=0
while read -r _ name prefix; do
  [ -n "$prefix" ] || continue
  case "$REL" in
    "$prefix"*)
      if [ ${#prefix} -gt $FROM_LEN ]; then FROM="$name"; FROM_LEN=${#prefix}; fi ;;
  esac
done < <(grep -E '^layer[[:space:]]' "$RULES")
[ -n "$FROM" ] || exit 0

layer_prefix() { awk -v n="$1" '$1=="layer" && $2==n {print $3; exit}' "$RULES"; }

IMPORT_RE='^[[:space:]]*(import|export|from|require|include|use|using|#include)[[:space:](]|require\(|import\('

violations=""
while read -r _ from arrow to; do
  [ "$arrow" = "->" ] && [ "$from" = "$FROM" ] || continue
  tprefix="$(layer_prefix "$to")"
  [ -n "$tprefix" ] || continue
  tdir="$(basename "$tprefix")"
  # Import line mentioning the denied layer: its full prefix, or its directory
  # name bounded by a path separator or quote (matches ../infra/x, src/infra/x).
  hits="$(grep -nE "$IMPORT_RE" "$FILE" 2>/dev/null \
    | grep -E "$tprefix|[/\"'[:space:]]$tdir/" || true)"
  if [ -n "$hits" ]; then
    violations="$violations
Rule violated: deny $from -> $to   ($REL is in layer '$from')
$hits"
  fi
done < <(grep -E '^deny[[:space:]]' "$RULES")

if [ -n "$violations" ]; then
  {
    echo "BOUNDARY VIOLATION: $REL"
    echo "$violations"
    echo ""
    echo "This dependency direction is forbidden by .claude/workflow/boundaries.rules."
    echo "Do ONE of:"
    echo "  1. Route the call through the allowed layer (see docs/constraints.md for the layering)."
    echo "  2. If the rule itself is wrong, stop and tell the operator — changing"
    echo "     boundaries.rules requires a new ADR in docs/adr/, never a silent edit."
  } >&2
  exit 2
fi
exit 0
