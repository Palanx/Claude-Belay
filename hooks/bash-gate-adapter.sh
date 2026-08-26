#!/usr/bin/env bash
# Adapter: Claude Code PreToolUse (matcher Bash) -> the staged-content gate.
#
# This is command policy: it inspects the Bash command an agent is about to run
# and decides whether the commit gate applies. That question only exists for a
# hook — a human, a git hook and CI all call pre-commit-security.sh directly,
# with no command string in sight.
#
# Exit 2 BLOCKS the command and returns stderr to Claude (verified behavior for
# PreToolUse). Every other Bash command passes through at zero cost.
set -u
. "$(dirname "$0")/lib/common.sh"
hook_init

CMD="$(json_get .tool_input.command)" || {
  # No jq/python3: cannot inspect the command. A security gate must not pass
  # what it can't read — if it looks like a commit, fail closed.
  case "$HOOK_INPUT" in
    *commit*)
      echo "COMMIT BLOCKED: no jq or python3 on PATH to parse the hook input," \
           "so staged changes could not be scanned for secrets." >&2
      echo "Install jq or python3, then commit again." >&2
      exit 2 ;;
    *clean*)
      if [ -f "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/workflow/corporate" ]; then
        echo "BLOCKED: cannot parse the command (no jq/python3) and it mentions 'clean'" \
             "in a corporate-mode repo, where git clean -x/-X would erase the belay state." >&2
        exit 2
      fi
      exit 0 ;;
    *) exit 0 ;;
  esac
}
[ -n "$CMD" ] || CMD="$(json_get .command)"   # Cursor payload shape (via cursor-adapter.sh)

# --- corporate: git clean -x/-X guard ---------------------------------------
# In corporate mode every belay path is untracked-and-excluded, so `git clean`
# with -x (untracked+ignored) or -X (ignored only) deletes the entire workflow
# state (.belay/, CLAUDE.local.md, wiring). Block it. `--exclude=` is safe and
# does not match the short-flag pattern.
if [ -f "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/workflow/corporate" ] \
   && printf '%s' "$CMD" | grep -qE '(^|[^[:alnum:]._-])git([[:space:]]+[^[:space:]]+)*[[:space:]]+clean([[:space:]]|$)' \
   && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])-[A-Za-z]*[xX]'; then
  {
    echo "BLOCKED: git clean with -x/-X in a corporate-mode install."
    echo "The belay workflow state (.belay/, CLAUDE.local.md, .claude/ wiring) is"
    echo "untracked and git-excluded — clean -x/-X would delete it all."
    echo "Run git clean without -x/-X, or uninstall first using the manifest in"
    echo ".git/info/exclude (the '# >>> claude-belay' block)."
  } >&2
  exit 2
fi

# `git` as a word, then a `commit` subcommand, allowing option tokens between
# (catches `git -C dir commit`, `git --git-dir=… commit`). Over-matching is
# safe: an extra scan only blocks if a secret is actually staged.
if printf '%s' "$CMD" | grep -qE '(^|[^[:alnum:]._-])git([[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'; then
  exec "$(dirname "$0")/pre-commit-security.sh"
fi
exit 0
