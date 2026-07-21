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
#   "exempt":       [ path prefixes the edit gate must skip (engine/third-party) ],
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

# csharpier_cmd — per-file C# format template, empty if csharpier unavailable.
# dotnet format is not an option here: it loads an MSBuild workspace (multi-
# second, and absent on a fresh Unity clone). csharpier is workspace-free.
csharpier_cmd() {
  local base=""
  if have csharpier; then base="csharpier"
  elif have dotnet && dotnet csharpier --version >/dev/null 2>&1; then base="dotnet csharpier"
  fi
  [ -n "$base" ] || return 0
  # csharpier 1.0 renamed the CLI: `csharpier format <file>`; older takes the file directly.
  if $base format --version >/dev/null 2>&1; then echo "$base format {file}"
  else echo "$base {file}"
  fi
}

STACKS=()
GAPS=()
EXEMPT=()   # path prefixes the edit gates must never touch (engine/third-party)
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

# ---------- Unity ----------
# Only source-code gates: scenes/prefabs/assets are editor-authored and out of
# scope by design. Compile and tests live inside the Unity editor — the .csproj
# files are editor-generated, gitignored, and reference the local install, so
# dotnet build/test/format would fail on a fresh clone. Honest gaps instead.
if [ -f ProjectSettings/ProjectVersion.txt ]; then
  STACKS+=("unity")
  CS_FMT="$(csharpier_cmd)"
  if [ -n "$CS_FMT" ]; then file_block "" "$CS_FMT" "" cs
  else gap "format (unity): csharpier not found — the only workspace-free sub-second C# formatter. Fix: dotnet tool install -g csharpier."
  fi
  gap "lint/typecheck (unity): Roslyn needs the editor-generated workspace — no per-file check exists; compile errors surface in the Unity editor."
  gap "test (unity): Unity Test Framework is editor-bound. If wanted at /validate-phase, add to toolchain.json by hand: \"<UnityEditor> -batchmode -runTests -projectPath .\" (slow: minutes)."
  gap "audit (unity): UPM has no vulnerability audit tool — permanent gap, not fixable."
  EXEMPT+=("Assets/Plugins/" "Assets/TextMesh Pro/" "Library/" "Temp/" "obj/")
fi

# ---------- Godot ----------
if [ -f project.godot ]; then
  STACKS+=("godot")
  GD_FMT="" GD_LINT=""
  have gdformat && GD_FMT="gdformat {file}"
  if have gdlint; then GD_LINT="gdlint {file}"; append CMD_LINT "gdlint ."; fi
  file_block "$GD_LINT" "$GD_FMT" "" gd
  if [ -z "$GD_FMT$GD_LINT" ] \
     && find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' -print -quit 2>/dev/null | grep -q .; then
    gap "lint/format (gdscript): gdtoolkit not on PATH. Fix: pip install gdtoolkit (gives gdformat + gdlint)."
  fi
  # Godot 4 C# builds headlessly — the csproj is real and committed (unlike Unity).
  if grep -qs Godot.NET.Sdk ./*.csproj; then
    if have dotnet; then
      append CMD_TYPECHECK "dotnet build --nologo"
      CS_FMT="$(csharpier_cmd)"
      if [ -n "$CS_FMT" ]; then file_block "" "$CS_FMT" "" cs
      else gap "format (godot-c#): csharpier not found. Fix: dotnet tool install -g csharpier."
      fi
      if grep -rqs Microsoft.NET.Test.Sdk --include='*.csproj' .; then
        append CMD_TEST "dotnet test --nologo"
      else
        gap "test (godot): no dotnet test project found; gdUnit4/GUT tests run inside the Godot runtime — wire a headless command into toolchain.json by hand if wanted."
      fi
      # dotnet list exits 0 even with findings on most SDKs; awk supplies the exit code.
      append CMD_AUDIT "dotnet list package --vulnerable 2>&1 | awk '/has the following vulnerable packages/{f=1} {print} END{exit f}'"
    else
      gap "godot-c#: .csproj present but dotnet not on PATH. Fix: install the .NET SDK."
    fi
  fi
  EXEMPT+=("addons/" ".godot/")
fi

# ---------- Unreal ----------
# clang-format only, and only with a repo .clang-format: LLVM defaults vs Epic
# style would reformat every file. clang-tidy / builds / Automation tests need
# a per-machine engine install and UBT — deliberate non-goals for hooks.
if ls ./*.uproject >/dev/null 2>&1; then
  STACKS+=("unreal")
  if have clang-format && [ -f .clang-format ]; then
    file_block "" "clang-format -i {file}" "" cpp h hpp inl
  elif have clang-format; then
    gap "format (unreal): clang-format is installed but the repo has no .clang-format — LLVM defaults would reformat every file (Epic style is tabs/Allman). Fix: add a .clang-format, then re-detect."
  else
    gap "format (unreal): clang-format not on PATH. Fix: install clang-format and add an Epic-style .clang-format."
  fi
  gap "lint/typecheck (unreal): clang-tidy needs a UBT compile database and built .generated.h headers — not viable as an edit hook; deliberate non-goal."
  gap "test/build (unreal): UnrealBuildTool is engine-install-bound. If wanted at /validate-phase, add to toolchain.json by hand, e.g. \"<Engine>/Build/BatchFiles/Linux/Build.sh <Target>Editor Linux Development\" (slow: minutes)."
  gap "audit (unreal): no vulnerability audit exists for engine/Marketplace plugins — permanent gap."
  EXEMPT+=("Intermediate/" "Saved/" "Binaries/" "DerivedDataCache/" "Source/ThirdParty/")
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

[ ${#STACKS[@]} -eq 0 ] && gap "stack: no known stack marker found (package.json / pyproject.toml / go.mod / Cargo.toml / ProjectSettings/ProjectVersion.txt / project.godot / *.uproject / Makefile). Fill .claude/workflow/toolchain.json commands by hand."

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
  printf '  "exempt": ['
  first=1; for e in ${EXEMPT[@]+"${EXEMPT[@]}"}; do
    [ $first -eq 0 ] && printf ', '; printf '"%s"' "$(json_escape "$e")"; first=0
  done
  echo "],"
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
