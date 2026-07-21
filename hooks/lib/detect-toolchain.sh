#!/usr/bin/env bash
# Detects the repo's actual toolchain (P7) and writes .claude/workflow/toolchain.json.
# Run by /bootstrap-project and /adopt-project; safe to re-run any time.
#
# Output schema (consumed by the hooks via common.sh):
# {
#   "detected_at":  ISO timestamp,
#   "detected_from": git commit the detection ran against,
#   "stacks":       ["node", "python", ...],
#   "commands":     { project-wide: test, lint, typecheck, audit, secrets },
#   "file_commands": { "<ext>": { per-file: lint, format, typecheck } },
#   "gaps":         [ human-readable sentences: what is missing + a concrete fix ]
# }
#
# Rules:
# - Only commands that were actually found on this machine / in this repo are
#   written. A missing category becomes a "gaps" entry, never a guess (P7).
# - file_commands only get tools that genuinely accept a single file argument.
#   Project-wide-only tools (tsc, go vet, clippy) go in "commands" and run at
#   /validate-phase time, not on every edit.
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
OUT="$ROOT/.claude/workflow/toolchain.json"
mkdir -p "$(dirname "$OUT")"
cd "$ROOT"

have() { command -v "$1" >/dev/null 2>&1; }

# Minimal JSON string escaper: backslash and double-quote (covers all current
# inputs; extend to control chars only if a value ever contains them).
json_escape() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }

# pkg_script <name> — 0 if package.json defines a real script with that name
pkg_script() {
  [ -f package.json ] || return 1
  local val
  if have jq; then
    val="$(jq -r ".scripts[\"$1\"] // empty" package.json)"
  elif have python3; then
    val="$(python3 -c "import json;print(json.load(open('package.json')).get('scripts',{}).get('$1',''))")"
  else
    grep -q "\"$1\"[[:space:]]*:" package.json && val="unknown" || val=""
  fi
  [ -n "$val" ] && [[ "$val" != *"no test specified"* ]]
}

pkg_dep() { # pkg_dep <name> — 0 if package.json mentions the dependency
  [ -f package.json ] && grep -q "\"$1\"" package.json
}

STACKS=()
GAPS=()
CMD_TEST="" CMD_LINT="" CMD_TYPECHECK="" CMD_AUDIT="" CMD_SECRETS=""
FILE_BLOCKS=""   # accumulated JSON fragments for file_commands

append() { # append <varname> <command> — joins multi-stack commands with &&
  local cur; cur="$(eval "printf '%s' \"\$$1\"")"
  if [ -z "$cur" ]; then eval "$1=\"\$2\""; else eval "$1=\"\$cur && \$2\""; fi
}

gap() { GAPS+=("$1"); }

# file_block <lint> <format> <typecheck> <ext...>
file_block() {
  local lint="$1" format="$2" typecheck="$3"; shift 3
  local ext body="" first=1
  [ -n "$lint" ]      && body="$body\"lint\": \"$lint\""
  [ -n "$format" ]    && { [ -n "$body" ] && body="$body, "; body="$body\"format\": \"$format\""; }
  [ -n "$typecheck" ] && { [ -n "$body" ] && body="$body, "; body="$body\"typecheck\": \"$typecheck\""; }
  [ -n "$body" ] || return 0
  for ext in "$@"; do
    [ -n "$FILE_BLOCKS" ] && FILE_BLOCKS="$FILE_BLOCKS,
"
    FILE_BLOCKS="$FILE_BLOCKS    \"$ext\": { $body }"
  done
}

# ---------- Node ----------
if [ -f package.json ]; then
  STACKS+=("node")
  RUNNER="npm"
  [ -f pnpm-lock.yaml ] && RUNNER="pnpm"
  [ -f yarn.lock ] && RUNNER="yarn"
  { [ -f bun.lockb ] || [ -f bun.lock ]; } && RUNNER="bun"

  if pkg_script test; then append CMD_TEST "$RUNNER test"
  elif pkg_dep vitest; then append CMD_TEST "npx vitest run"
  elif pkg_dep jest; then append CMD_TEST "npx jest --ci"
  else gap "test (node): no test script or known runner in package.json. Fix: add a \"test\" script, or install vitest/jest."
  fi

  NODE_LINT="" NODE_FMT="" NODE_TC=""
  if pkg_dep eslint || ls eslint.config.* .eslintrc* >/dev/null 2>&1; then
    NODE_LINT="npx eslint {file}"
    append CMD_LINT "npx eslint ."
  else
    gap "lint (node): no eslint found. Fix: npm i -D eslint && npx eslint --init."
  fi
  if pkg_dep prettier || ls .prettierrc* prettier.config.* >/dev/null 2>&1; then
    NODE_FMT="npx prettier --write {file}"
  else
    gap "format (node): no prettier found. Fix: npm i -D prettier."
  fi
  if [ -f tsconfig.json ]; then
    append CMD_TYPECHECK "npx tsc --noEmit"
  fi
  file_block "$NODE_LINT" "$NODE_FMT" "$NODE_TC" js jsx mjs cjs ts tsx

  case "$RUNNER" in
    npm)  append CMD_AUDIT "npm audit --audit-level=high" ;;
    pnpm) append CMD_AUDIT "pnpm audit --audit-level high" ;;
    yarn) append CMD_AUDIT "yarn npm audit" ;;
    bun)  gap "audit (node): bun has no audit command. Fix: run npx better-npm-audit or osv-scanner in CI." ;;
  esac
fi

# ---------- Python ----------
if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ] || ls requirements*.txt >/dev/null 2>&1; then
  STACKS+=("python")

  if have pytest; then append CMD_TEST "pytest -q"
  else gap "test (python): pytest not on PATH. Fix: pip install pytest (or add your runner to toolchain.json)."
  fi

  PY_LINT="" PY_FMT="" PY_TC=""
  if have ruff; then
    PY_LINT="ruff check {file}"; PY_FMT="ruff format {file}"
    append CMD_LINT "ruff check ."
  elif have flake8; then
    PY_LINT="flake8 {file}"; append CMD_LINT "flake8 ."
    have black && PY_FMT="black -q {file}"
  else
    gap "lint/format (python): neither ruff nor flake8 on PATH. Fix: pip install ruff (covers both)."
  fi
  if have mypy; then PY_TC="mypy --no-error-summary {file}"; append CMD_TYPECHECK "mypy ."
  elif have pyright; then PY_TC="pyright {file}"; append CMD_TYPECHECK "pyright"
  else gap "typecheck (python): neither mypy nor pyright on PATH. Fix: pip install mypy."
  fi
  file_block "$PY_LINT" "$PY_FMT" "$PY_TC" py

  if have pip-audit; then append CMD_AUDIT "pip-audit"
  else gap "audit (python): pip-audit not on PATH. Fix: pip install pip-audit."
  fi
fi

# ---------- Go ----------
if [ -f go.mod ] && have go; then
  STACKS+=("go")
  append CMD_TEST "go test ./..."
  append CMD_TYPECHECK "go build ./..."
  if have golangci-lint; then append CMD_LINT "golangci-lint run"
  else append CMD_LINT "go vet ./..."
  fi
  file_block "" "gofmt -w {file}" "" go
  if have govulncheck; then append CMD_AUDIT "govulncheck ./..."
  else gap "audit (go): govulncheck not on PATH. Fix: go install golang.org/x/vuln/cmd/govulncheck@latest."
  fi
fi

# ---------- Rust ----------
if [ -f Cargo.toml ] && have cargo; then
  STACKS+=("rust")
  append CMD_TEST "cargo test --quiet"
  append CMD_TYPECHECK "cargo check --quiet"
  append CMD_LINT "cargo clippy --quiet -- -D warnings"
  have rustfmt && file_block "" "rustfmt {file}" "" rs
  if cargo audit --version >/dev/null 2>&1; then append CMD_AUDIT "cargo audit"
  else gap "audit (rust): cargo-audit not installed. Fix: cargo install cargo-audit."
  fi
fi

# ---------- Makefile fallback for still-empty categories ----------
if [ -f Makefile ]; then
  [ -z "$CMD_TEST" ] && grep -qE '^test:' Makefile && CMD_TEST="make test"
  [ -z "$CMD_LINT" ] && grep -qE '^lint:' Makefile && CMD_LINT="make lint"
fi

# ---------- Secrets scanning (stack-independent) ----------
if have gitleaks; then
  CMD_SECRETS="gitleaks protect --staged --no-banner --redact"
else
  gap "secrets: gitleaks not on PATH — pre-commit hook falls back to builtin grep patterns (weaker). Fix: install gitleaks (https://github.com/gitleaks/gitleaks)."
fi

[ ${#STACKS[@]} -eq 0 ] && gap "stack: no known stack marker found (package.json / pyproject.toml / go.mod / Cargo.toml / Makefile). Fill .claude/workflow/toolchain.json commands by hand."

# ---------- Emit JSON ----------
DETECTED_FROM="$(git rev-parse --short HEAD 2>/dev/null || echo 'no-commits')"
{
  echo "{"
  echo "  \"detected_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"detected_from\": \"$DETECTED_FROM\","
  printf '  "stacks": ['
  first=1; for s in ${STACKS[@]+"${STACKS[@]}"}; do
    [ $first -eq 0 ] && printf ', '; printf '"%s"' "$(json_escape "$s")"; first=0
  done
  echo "],"
  echo "  \"commands\": {"
  sep=""
  for pair in "test:$CMD_TEST" "lint:$CMD_LINT" "typecheck:$CMD_TYPECHECK" "audit:$CMD_AUDIT" "secrets:$CMD_SECRETS"; do
    key="${pair%%:*}"; val="${pair#*:}"
    [ -n "$val" ] || continue
    printf '%s    "%s": "%s"' "$sep" "$key" "$(json_escape "$val")"; sep=",
"
  done
  echo ""
  echo "  },"
  echo "  \"file_commands\": {"
  [ -n "$FILE_BLOCKS" ] && echo "$FILE_BLOCKS"
  echo "  },"
  printf '  "gaps": ['
  first=1; for g in ${GAPS[@]+"${GAPS[@]}"}; do
    [ $first -eq 0 ] && printf ','; printf '\n    "%s"' "$(json_escape "$g")"; first=0
  done
  [ $first -eq 0 ] && printf '\n  '
  echo "]"
  echo "}"
} >"$OUT"

# Validate our own output if a JSON parser exists.
if have jq; then jq . "$OUT" >/dev/null || { echo "detect-toolchain: emitted invalid JSON at $OUT" >&2; exit 1; }
elif have python3; then python3 -m json.tool "$OUT" >/dev/null || { echo "detect-toolchain: emitted invalid JSON at $OUT" >&2; exit 1; }
fi

echo "toolchain written to $OUT"
echo "stacks: ${STACKS[*]:-none}"
if [ ${#GAPS[@]} -gt 0 ]; then
  echo "gaps (${#GAPS[@]}):"
  printf '  - %s\n' "${GAPS[@]}"
else
  echo "gaps: none"
fi
