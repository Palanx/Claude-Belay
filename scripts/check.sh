#!/usr/bin/env bash
# Run belay's gates from a plain shell. No agent, no hook payload.
#
#   check.sh [category...]     project-wide gates; default: test lint typecheck
#   check.sh --files <f>...    per-file gates over the listed files
#   check.sh --staged          per-file gates over staged files + the commit gate
#
# Every mode runs everything it was asked for and reports at the end: a person
# running this wants the full list, not the first failure. Exit 1 if anything
# failed. A category with no configured command is a loud gap, not a failure
# (P7) — see toolchain.manual.json to fill one in.
#
# Not set -e: it would abort at the first failing gate and hide the rest.
set -uo pipefail

# Before anything else: --help must work outside an install, which is where
# somebody is most likely to be asking what this does.
case "${1:-}" in --help|-h) sed -n '3,6p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;; esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "check: not inside a git repository" >&2; exit 1; }
# Resolved from the git root, not from $0: in a corporate install this script
# lives at .belay/scripts/, so $(dirname $0)/.. is .belay/, not the repo root.
LIB="$ROOT/.claude/hooks/lib/common.sh"
[ -f "$LIB" ] || { echo "check: belay is not installed here ($LIB missing)" >&2; exit 1; }
. "$LIB"
export CLAUDE_PROJECT_DIR="$ROOT"
tc_init

MODE=categories
case "${1:-}" in
  --files)  MODE=files;  shift ;;
  --staged) MODE=staged; shift ;;
esac

failed=""
fail() { failed="$failed $1"; }

sum_of() { # sum_of <file> — content digest, or empty if no hasher exists
  [ -f "$1" ] || return 0
  if command -v shasum >/dev/null 2>&1; then shasum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v sha1sum >/dev/null 2>&1; then sha1sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v cksum >/dev/null 2>&1; then cksum <"$1" 2>/dev/null
  fi
}

run_categories() {
  local cats="$*" cat cmd out
  [ -n "$cats" ] || cats="test lint typecheck"
  for cat in $cats; do
    cmd="$(tc_cmd "$cat")"
    if [ -z "$cmd" ]; then gap_warn "$cat" "the project"; continue; fi
    echo "== $cat: $cmd"
    if out="$(cd "$ROOT" && bash -c "$cmd" 2>&1)"; then
      echo "   PASS"
    else
      echo "   FAIL"
      printf '%s\n' "$out" | sed 's/^/   /'
      fail "$cat"
    fi
  done
}

# The gates take a path and return an exit code, so this is a direct call — no
# payload is constructed anywhere in this script. That is the whole point of the
# gate/adapter split: callers adapt to the gate, never the reverse.
gate_files() {
  local f abs out gated=0 skipped=""
  for f in "$@"; do
    case "$f" in /*) abs="$f" ;; *) abs="$ROOT/$f" ;; esac
    # Skipping a path that is not a file is fine; skipping it in silence is not. Skip every
    # argument and the run still prints "all gates passed", so a clean sweep and a sweep of
    # nothing are indistinguishable (P7). One caller reached this with an unquoted "$FILES"
    # under a shell that does not word-split, which arrives as a single nonexistent path.
    if [ ! -f "$abs" ]; then skipped="$skipped $f"; continue; fi
    gated=$((gated + 1))
    for g in post-edit-gate boundary-check; do
      # Pass the gate's own stderr through: it already distinguishes a real
      # failure (POST-EDIT GATE FAILED) from a formatter that merely rewrote the
      # file (REFORMATTED ON DISK), and --staged depends on that distinction.
      if ! out="$("$ROOT/.claude/hooks/$g.sh" "$abs" 2>&1)"; then
        printf '%s\n' "$out"
        fail "${f#"$ROOT"/}"
      fi
    done
  done
  [ -n "$skipped" ] && echo "check: not a file, skipped:$skipped" >&2
  # Reported through fail(), not a return code: the script's exit status comes from $failed,
  # so returning non-zero here would still print "all gates passed" — which is the defect.
  if [ $# -gt 0 ] && [ "$gated" -eq 0 ]; then
    echo "check: gated 0 of $# argument(s) — nothing was checked, so this is not a pass" >&2
    fail "nothing-checked"
  fi
}

case "$MODE" in
  categories) run_categories "$@" ;;
  files)
    [ $# -gt 0 ] || { echo "check: --files needs at least one path" >&2; exit 1; }
    gate_files "$@" ;;
  staged)
    # --diff-filter=ACM drops deletions: gating a path that no longer exists is
    # noise at best.
    #
    # Known limitation: the gates read the WORKTREE copy, not the staged blob. A
    # file staged and then edited further is gated in its worktree form. Closing
    # that means checking the index out into a temp tree — a lot of machinery for
    # a local convenience hook, when CI gates the pushed tree anyway.
    staged_list=()
    while IFS= read -r f; do [ -n "$f" ] && staged_list+=("$f"); done \
      < <(git -C "$ROOT" diff --cached --name-only --diff-filter=ACM)

    # Every detected formatter rewrites in place, so a successful format leaves
    # the worktree different from what is staged — the commit would capture the
    # unformatted blob. Digest before and after to catch it.
    declare -a before_sums=()
    for f in ${staged_list[@]+"${staged_list[@]}"}; do
      before_sums+=("$(sum_of "$ROOT/$f")")
    done

    [ ${#staged_list[@]} -eq 0 ] || gate_files ${staged_list[@]+"${staged_list[@]}"}

    rewritten=""
    i=0
    for f in ${staged_list[@]+"${staged_list[@]}"}; do
      after="$(sum_of "$ROOT/$f")"
      [ -n "${before_sums[$i]}" ] && [ "${before_sums[$i]}" != "$after" ] && rewritten="$rewritten $f"
      i=$((i+1))
    done

    if ! out="$("$ROOT/.claude/hooks/pre-commit-security.sh" 2>&1)"; then
      printf '%s\n' "$out"
      fail "staged-content"
    fi

    if [ -n "$rewritten" ]; then
      {
        echo "COMMIT BLOCKED: the formatter rewrote staged files, so what you staged is not"
        echo "what is on disk:"
        for f in $rewritten; do echo "  $f"; done
        echo "Stage them and commit again:  git add$rewritten && git commit"
      } >&2
      exit 1
    fi ;;
esac

if [ -n "$failed" ]; then
  echo "check: FAILED —$failed" >&2
  exit 1
fi
echo "check: all gates passed"
