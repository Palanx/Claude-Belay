#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash).
# When the command about to run is a `git commit`, scan the STAGED changes for
# secrets and (if dependency files are staged) run the dependency audit.
# Exit 2 BLOCKS the commit and returns stderr to Claude (verified behavior for
# PreToolUse). All other Bash commands pass through untouched at zero cost.
#
# False-positive escape hatch: add a regex per line to
# .claude/workflow/secret-allowlist (matched lines are ignored). That file is
# reviewable in git — the bypass leaves a trace.
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
    *) exit 0 ;;
  esac
}
# `git` as a word, then a `commit` subcommand, allowing option tokens between
# (catches `git -C dir commit`, `git --git-dir=… commit`). Over-matching is
# safe: an extra scan only blocks if a secret is actually staged.
if ! printf '%s' "$CMD" | grep -qE '(^|[^[:alnum:]._-])git([[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'; then
  exit 0
fi

cd "$ROOT" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# --- 0. Protected-branch guard (opt-in) -------------------------------------
# One anchored regex per line in .claude/workflow/protected-branches blocks
# direct commits on matching branches. No file = no check, zero cost.
PROT="$ROOT/.claude/workflow/protected-branches"
BRANCH="$(git branch --show-current 2>/dev/null)"
if [ -f "$PROT" ] && [ -n "$BRANCH" ] \
   && printf '%s' "$BRANCH" | grep -qEf <(grep -vE '^[[:space:]]*(#|$)' "$PROT"); then
  {
    echo "COMMIT BLOCKED: branch '$BRANCH' is protected (.claude/workflow/protected-branches)."
    echo "Create a working branch first: git switch -c <name>"
  } >&2
  exit 2
fi

errs=""

# --- 1. Secret scan on staged content -------------------------------------
SECRETS_CMD="$(tc_cmd secrets)"
if [ -n "$SECRETS_CMD" ]; then
  if ! out="$(bash -c "$SECRETS_CMD" 2>&1)"; then
    errs="$errs
--- secret scan failed ($SECRETS_CMD) ---
$out"
  fi
else
  # Builtin fallback: high-signal secret shapes in staged ADDED lines only.
  PATTERNS='-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|(api[_-]?key|secret|passwd|password|token)["'"'"':= ]+["'"'"']?[A-Za-z0-9_/+=-]{16,}'
  hits="$(git diff --cached --unified=0 | grep -E '^\+[^+]' | grep -EIn -e "$PATTERNS" || true)"
  ALLOW="$ROOT/.claude/workflow/secret-allowlist"
  if [ -n "$hits" ] && [ -f "$ALLOW" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vEf "$ALLOW" || true)"
  fi
  if [ -n "$hits" ]; then
    errs="$errs
--- possible secrets in staged changes (builtin scanner) ---
$hits"
  fi
fi

# --- 2. Dependency audit, only when dependency files are staged ------------
if git diff --cached --name-only \
   | grep -qE '(^|/)(package(-lock)?\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?|requirements[^/]*\.txt|pyproject\.toml|poetry\.lock|uv\.lock|Cargo\.(toml|lock)|go\.(mod|sum)|Gemfile(\.lock)?|composer\.(json|lock))$'; then
  AUDIT_CMD="$(tc_cmd audit)"
  if [ -n "$AUDIT_CMD" ]; then
    if ! out="$(bash -c "$AUDIT_CMD" 2>&1)"; then
      errs="$errs
--- dependency audit failed ($AUDIT_CMD) ---
$out"
    fi
  else
    gap_warn "audit" "staged dependency changes"
  fi
fi

if [ -n "$errs" ]; then
  {
    echo "COMMIT BLOCKED by pre-commit security gate."
    echo "$errs"
    echo ""
    echo "To proceed:"
    echo "  - Real secret: remove it from the staged changes, move it to the environment"
    echo "    or your secret store, then stage and commit again."
    echo "  - Vulnerable dependency: upgrade it, or record an accepted-risk ADR in docs/adr/"
    echo "    and tell the operator — do not bypass silently."
    echo "  - False positive (builtin scanner only): add a matching regex line to"
    echo "    .claude/workflow/secret-allowlist and commit that file too."
  } >&2
  exit 2
fi
exit 0
