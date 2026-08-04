#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|Write).
# Runs format + lint + (file-scoped) typecheck on the file that was just edited.
#
# PostToolUse cannot block — the edit has already happened. Exit 2 sends stderr
# back to Claude, which fixes the file in the same turn. That is the design
# (P3): wrong output is caught cheaply and immediately, not prevented.
# Project-wide gates (full test suite, tsc, clippy) run in /validate-phase.
set -u
. "$(dirname "$0")/lib/common.sh"
hook_init

# No jq/python3: common.sh has already said so on stderr, but exiting 0 here
# would leave the gate silently not-run, which is the one thing P7 forbids —
# and pre-commit-security.sh fails closed on the identical condition. Exit 2 so
# the message actually reaches Claude instead of dying in an ignored stream.
FILE="$(json_get .tool_input.file_path)" || {
  echo "POST-EDIT GATE DID NOT RUN: no jq or python3 on PATH to read the hook input, so the file you just edited was NOT formatted, linted or typechecked. Install jq or python3." >&2
  exit 2
}
[ -n "$FILE" ] || FILE="$(json_get .file_path)"   # Cursor payload shape (via cursor-adapter.sh)
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0

case "$FILE" in
  "$ROOT"/*) REL="${FILE#"$ROOT"/}" ;;
  *) REL="$FILE" ;;
esac

# Corporate containment: state lives under .belay/, but an agent can
# hallucinate the old canonical path (docs/phases/... instead of
# .belay/docs/...), which every gate below exempts. Catch it at write time.
# Tracked files at these paths are the company's own docs — those pass.
if [ -f "$ROOT/.claude/workflow/corporate" ]; then
  # [x] brackets keep these globs invisible to the corporate-install sed, which
  # would otherwise rewrite them to .belay/... and invert the check's meaning.
  case "$REL" in
    docs/[p]roduct/*|docs/[a]dr/*|docs/[p]hases/*|docs/[i]ndex/*|docs/[s]ecurity/*|docs/[t]emplates/*|docs/[c]onstraints.md|docs/[a]doption-report.md|scripts/[b]uild-index.sh)
      if ! git -C "$ROOT" ls-files --error-unmatch "$REL" >/dev/null 2>&1; then
        {
          echo "WRONG PATH (corporate mode): $REL"
          echo "Belay state lives under .belay/ in this repo (.belay/docs/..., .belay/scripts/...)."
          echo "Move the file there and update any reference to the old path."
        } >&2
        exit 2
      fi ;;
  esac
fi

# Docs, workflow config, and data files are not source — not gated.
# Second line: engine asset text (Unity YAML, Godot resources) — editor-authored,
# out of scope by design, and would otherwise gap_warn on every touch.
case "$REL" in
  .claude/*|.belay/*|docs/*|*.md|*.txt|*.json|*.yml|*.yaml|*.toml|*.lock|*.csv) exit 0 ;;
  *.meta|*.unity|*.prefab|*.asset|*.mat|*.anim|*.controller|*.asmdef|*.tscn|*.tres|*.import|*.uproject|*.uplugin) exit 0 ;;
esac

# Engine-owned / third-party trees declared by detection are not gated either.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$REL" in "$p"*) exit 0 ;; esac
done < <(tc_exempt_prefixes)

ext="${FILE##*.}"
FMT="$(tc_file_cmd "$ext" format)"
LINT="$(tc_file_cmd "$ext" lint)"
TC="$(tc_file_cmd "$ext" typecheck)"

if [ -z "$FMT$LINT$TC" ]; then
  # Source file with no configured per-file tools: say so once, loudly (P7).
  gap_warn "lint/format for .$ext files" "$REL"
  exit 0
fi

fails=""
run_gate() { # run_gate <label> <template>
  local label="$1" tmpl="$2" out
  [ -n "$tmpl" ] || return 0
  if ! out="$(cd "$ROOT" && run_on_file "$tmpl" "$FILE" 2>&1)"; then
    fails="$fails
--- $label failed ---
$out"
  fi
}

# Every formatter detection writes in place (prettier --write, ruff format,
# gofmt -w, rustfmt, clang-format -i, csharpier, gdformat), so a successful
# format silently leaves the file on disk different from what was just written.
# The next Edit then matches its old_string against stale content and fails on
# whitespace. Cheap to detect, so detect it (P3) instead of letting it surprise
# somebody three steps later.
sum_of() { # sum_of <file> — content digest, or empty if no hasher exists
  if command -v shasum >/dev/null 2>&1; then shasum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v sha1sum >/dev/null 2>&1; then sha1sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v cksum >/dev/null 2>&1; then cksum <"$1" 2>/dev/null
  fi
}
before="$(sum_of "$FILE")"
run_gate "format" "$FMT"
after="$(sum_of "$FILE")"
reformatted=0
[ -n "$before" ] && [ "$before" != "$after" ] && reformatted=1

run_gate "lint" "$LINT"
run_gate "typecheck" "$TC"

if [ -n "$fails" ]; then
  {
    echo "POST-EDIT GATE FAILED: $REL"
    echo "Fix every issue below in this file now, before continuing with the task."
    echo "The same checks re-run automatically on your next edit."
    [ "$reformatted" -eq 1 ] && echo "NOTE: the formatter also rewrote this file — re-read it before editing, or your next edit will not match."
    echo "$fails"
  } >&2
  exit 2
fi

if [ "$reformatted" -eq 1 ]; then
  {
    echo "REFORMATTED ON DISK: $REL"
    echo "\`$FMT\` rewrote the file after your edit — what is on disk is not what you wrote."
    echo "Re-read it before your next edit to it, or the edit will fail to match."
    echo "Nothing is wrong: lint and typecheck passed. This is the only notice you get."
  } >&2
  exit 2
fi
exit 0
