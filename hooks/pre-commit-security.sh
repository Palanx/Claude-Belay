#!/usr/bin/env bash
# Gate: staged-content policy for a commit.
#
#   pre-commit-security.sh
#
# Takes no arguments and reads no stdin. Protected-branch guard, corporate
# containment, secret scan of the staged changes, and the dependency audit when
# dependency files are staged. Exit 2 means: do not let this commit happen.
#
# Deciding *whether* a given command is a commit is not this file's job — that
# is bash-gate-adapter.sh, which is one caller. scripts/check.sh --staged and
# the git pre-commit hook are the others, and neither has a command string to
# offer. One gate, many callers.
#
# False-positive escape hatch: add a regex per line to
# .claude/workflow/secret-allowlist (matched lines are ignored). That file is
# reviewable in git — the bypass leaves a trace.
set -u
. "$(dirname "$0")/lib/common.sh"
tc_init

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

# --- 0b. Corporate containment: no belay state may reach git ----------------
# Belay state is exclude-hidden; if a belay-canonical path shows up in status,
# either an agent wrote to the old canonical location (docs/... instead of
# .belay/docs/...) or the exclude block broke. Both must stop a commit.
if [ -f "$ROOT/.claude/workflow/corporate" ]; then
  leaks="$(git status --porcelain -uall | grep -E \
    '^\?\? (\.belay/|CLAUDE\.local\.md|docs/(product|adr|phases|index|security|templates)/|docs/(constraints|adoption-report)\.md|scripts/build-index\.sh)' || true)"
  if [ -n "$leaks" ]; then
    {
      echo "COMMIT BLOCKED: belay workflow state is visible to git in a corporate-mode repo:"
      echo "$leaks"
      echo "If the path starts with docs/ or scripts/, an agent wrote to the old canonical"
      echo "location — move it under .belay/ (state lives in .belay/docs/, .belay/scripts/)."
      echo "If it starts with .belay/ or is CLAUDE.local.md, the exclude block in"
      echo ".git/info/exclude is broken — re-run install.sh --corporate to restore it."
    } >&2
    exit 2
  fi
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
