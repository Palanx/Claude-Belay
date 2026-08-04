#!/usr/bin/env bash
# Smoke test for install.sh --corporate, plus a normal-mode regression.
# Builds a hostile scratch repo (tracked CLAUDE.md, tracked .claude/settings.json
# and docs/, a tracked homonymous command, a pre-existing settings.local.json),
# installs, and asserts every corporate guarantee. Run from anywhere:
#   tests/corporate-smoke.sh
set -u
PKG="$(cd "$(dirname "$0")/.." && pwd)"
# Isolate from the user's git config — a global gitignore covering e.g.
# .claude/settings.local.json would change what the scratch repos see.
# XDG too: ~/.config/git/ignore applies even with GIT_CONFIG_GLOBAL unset.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
command -v jq >/dev/null 2>&1 || { echo "corporate-smoke: jq required (merge asserts)" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/xdg" && export XDG_CONFIG_HOME="$TMP/xdg"
# install.sh registers every install under $HOME — keep the real one clean.
mkdir -p "$TMP/home" && export HOME="$TMP/home"
CHECKS=0 FAILS=0
ok()  { CHECKS=$((CHECKS+1)); echo "  PASS: $1"; }
bad() { CHECKS=$((CHECKS+1)); FAILS=$((FAILS+1)); echo "  FAIL: $1"; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

gitq() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# =============================== corporate ===================================
echo "== corporate mode (hostile repo) =="
A="$TMP/corp"
mkdir -p "$A/.claude/commands" "$A/docs/adr"
printf '# Company agents doc\ncompany rules\n' >"$A/CLAUDE.md"
printf '{"permissions":{"allow":[]}}\n' >"$A/.claude/settings.json"
printf 'company docs\n' >"$A/docs/README.md"
printf 'company ADR\n' >"$A/docs/adr/001-company.md"
printf 'company homonymous command\n' >"$A/.claude/commands/plan-feature.md"
printf 'print("hi")\n' >"$A/main.py"
gitq "$A" init -q
gitq "$A" add -A
gitq "$A" commit -qm init
printf '{"belaytest":"keep"}\n' >"$A/.claude/settings.local.json"   # pre-existing, untracked

BEFORE="$(gitq "$A" status --porcelain)"
H_CLAUDE="$(git -C "$A" hash-object CLAUDE.md)"
H_SET="$(git -C "$A" hash-object .claude/settings.json)"
H_CMD="$(git -C "$A" hash-object .claude/commands/plan-feature.md)"

if "$PKG/install.sh" "$A" --corporate --cursor >"$TMP/install1.log" 2>&1; then
  ok "install --corporate --cursor exits 0"
else
  bad "install --corporate --cursor exits 0 (see $TMP/install1.log)"; sed 's/^/    /' "$TMP/install1.log"
fi

AFTER="$(gitq "$A" status --porcelain)"
NEW="$(comm -13 <(printf '%s\n' "$BEFORE" | sort) <(printf '%s\n' "$AFTER" | sort) | grep -v '^$' || true)"
GONE="$(comm -23 <(printf '%s\n' "$BEFORE" | sort) <(printf '%s\n' "$AFTER" | sort) | grep -v '^$' || true)"
check "git status: no new entries" test -z "$NEW"
check "git status: only settings.local.json line absorbed by exclude" \
  test "$GONE" = "?? .claude/settings.local.json"
check "CLAUDE.md byte-identical" test "$(git -C "$A" hash-object CLAUDE.md)" = "$H_CLAUDE"
check "tracked .claude/settings.json untouched" test "$(git -C "$A" hash-object .claude/settings.json)" = "$H_SET"
check "tracked homonymous command skipped" test "$(git -C "$A" hash-object .claude/commands/plan-feature.md)" = "$H_CMD"

# sed correctness on installed copies (commands + cursor commands, minus the
# skipped company homonym).
seddirs=("$A/.claude/commands" "$A/.cursor/commands")
unrewritten="$(grep -RhoE '(\.belay/)?(docs/(product|adr|phases|index|security|templates|constraints\.md|adoption-report\.md)|scripts/build-index\.sh)' "${seddirs[@]}" | grep -v '^\.belay/' || true)"
check "sed: no unrewritten docs/ or scripts/ references" test -z "$unrewritten"
check "sed: no double rewrite (.belay/.belay)" bash -c '! grep -Rq "\.belay/\.belay" "$1" "$2" "$3"' _ "${seddirs[@]}" "$A/.belay"
check "sed: build-index OUTDIR relocated" grep -q '\.belay/docs/index' "$A/.belay/scripts/build-index.sh"
check "sed: post-edit-gate containment globs survived rewrite" grep -q 'docs/\[p\]roduct' "$A/.claude/hooks/post-edit-gate.sh"

# settings.local.json merged, not clobbered
check "settings.local.json: custom key preserved" test "$(jq -r .belaytest "$A/.claude/settings.local.json")" = "keep"
check "settings.local.json: hook wiring merged in" grep -q 'post-edit-gate.sh' "$A/.claude/settings.local.json"

# idempotence
"$PKG/install.sh" "$A" --corporate --cursor >"$TMP/install2.log" 2>&1 \
  && ok "re-install --corporate exits 0" || bad "re-install --corporate exits 0"
EXC="$A/.git/info/exclude"
check "exclude block written exactly once" test "$(grep -c '^# >>> claude-belay' "$EXC")" = 1
NEW2="$(comm -13 <(printf '%s\n' "$BEFORE" | sort) <(gitq "$A" status --porcelain | sort) | grep -v '^$' || true)"
check "git status still clean after re-install" test -z "$NEW2"

# mode guard
if "$PKG/install.sh" "$A" >"$TMP/install3.log" 2>&1; then
  bad "re-run without --corporate is blocked"
else
  grep -q 're-run with --corporate' "$TMP/install3.log" \
    && ok "re-run without --corporate is blocked" || bad "re-run without --corporate: wrong error"
fi

# runtime: relocated index build keeps status clean
(cd "$A" && ./.belay/scripts/build-index.sh) >/dev/null 2>&1 \
  && ok "relocated build-index.sh runs" || bad "relocated build-index.sh runs"
check "index written under .belay/docs/index" test -f "$A/.belay/docs/index/_overview.md"
NEW3="$(comm -13 <(printf '%s\n' "$BEFORE" | sort) <(gitq "$A" status --porcelain | sort) | grep -v '^$' || true)"
check "git status clean after runtime writes" test -z "$NEW3"

# --- hook guards (corporate) ------------------------------------------------
hookrun() { # hookrun <hook> <json> — runs installed hook with payload, returns its exit
  printf '%s' "$2" | CLAUDE_PROJECT_DIR="$A" "$A/.claude/hooks/$1" >/dev/null 2>&1
}
hookrun pre-commit-security.sh '{"tool_input":{"command":"git clean -fdx"}}' \
  && bad "clean guard: git clean -fdx blocked" || ok "clean guard: git clean -fdx blocked"
hookrun pre-commit-security.sh '{"tool_input":{"command":"git clean -fd"}}' \
  && ok "clean guard: git clean -fd (no -x) passes" || bad "clean guard: git clean -fd (no -x) passes"
hookrun pre-commit-security.sh '{"tool_input":{"command":"git clean --exclude=foo -fd"}}' \
  && ok "clean guard: --exclude does not false-positive" || bad "clean guard: --exclude does not false-positive"

mkdir -p "$A/docs/phases" && printf 'stray\n' >"$A/docs/phases/stray.md"
hookrun pre-commit-security.sh '{"tool_input":{"command":"git commit -m x"}}' \
  && bad "containment: commit blocked while stray docs/phases file exists" \
  || ok "containment: commit blocked while stray docs/phases file exists"
hookrun post-edit-gate.sh "{\"tool_input\":{\"file_path\":\"$A/docs/phases/stray.md\"}}" \
  && bad "containment: post-edit-gate flags write to old canonical path" \
  || ok "containment: post-edit-gate flags write to old canonical path"
rm -rf "$A/docs/phases"
hookrun pre-commit-security.sh '{"tool_input":{"command":"git commit -m x"}}' \
  && ok "containment: commit passes once stray file removed" \
  || bad "containment: commit passes once stray file removed"
hookrun post-edit-gate.sh "{\"tool_input\":{\"file_path\":\"$A/docs/adr/001-company.md\"}}" \
  && ok "containment: tracked company docs/adr file passes" \
  || bad "containment: tracked company docs/adr file passes"
mkdir -p "$A/.belay/docs/phases" && printf 'legit\n' >"$A/.belay/docs/phases/notes.md"
hookrun post-edit-gate.sh "{\"tool_input\":{\"file_path\":\"$A/.belay/docs/phases/notes.md\"}}" \
  && ok "containment: .belay/docs write passes" || bad "containment: .belay/docs write passes"

# --- upstream collision warning (build-index.sh --check) ---------------------
printf 'pointer\n' >"$A/CLAUDE.local.md"
gitq "$A" add -f CLAUDE.local.md
gitq "$A" commit -qm "teammate commits a colliding path"
warn="$(cd "$A" && ./.belay/scripts/build-index.sh --check 2>&1 >/dev/null || true)"
printf '%s' "$warn" | grep -q 'WARNING: upstream' \
  && ok "collision check: warns when HEAD tracks an excluded path" \
  || bad "collision check: warns when HEAD tracks an excluded path"
gitq "$A" reset -q HEAD~1 && rm -f "$A/CLAUDE.local.md"
warn2="$(cd "$A" && ./.belay/scripts/build-index.sh --check 2>&1 >/dev/null || true)"
printf '%s' "$warn2" | grep -q 'WARNING: upstream' \
  && bad "collision check: silent when no collision" \
  || ok "collision check: silent when no collision"

# --- uninstall manifest: created vs merged ----------------------------------
# The header says "delete these paths"; a file belay only merged into must be
# marked, or the documented uninstall destroys the operator's own settings.
# $A had an untracked settings.local.json before the install (planted above).
check "manifest: pre-existing settings.local.json marked '# merged:'" \
  bash -c 'sed -n "/^# >>> claude-belay/,/^# <<< claude-belay/p" "$1/.git/info/exclude" \
           | grep -qxF "# merged: /.claude/settings.local.json"' _ "$A"

# --- orphan reaping ----------------------------------------------------------
# A command deleted upstream stays on disk and falls out of the regenerated
# manifest; because .claude/ holds no tracked files git collapses that to
# "?? .claude/", exposing the directory and failing the no-touch check.
echo "== corporate orphan reaping =="
F="$TMP/orphan"
mkdir -p "$F"
printf 'print("hi")\n' >"$F/main.py"
gitq "$F" init -q && gitq "$F" add -A && gitq "$F" commit -qm init
FBEFORE="$(gitq "$F" status --porcelain)"
mkdir -p "$TMP/pkgorph"
cp -R "$PKG/install.sh" "$PKG/hooks" "$PKG/commands" "$PKG/templates" "$PKG/scripts" "$PKG/settings" "$TMP/pkgorph/"
printf '# a command a later release drops\n' >"$TMP/pkgorph/commands/temp-thing.md"
"$TMP/pkgorph/install.sh" "$F" --corporate >"$TMP/install10.log" 2>&1 \
  && ok "install from a package with an extra command exits 0" \
  || { bad "install from a package with an extra command exits 0"; sed 's/^/    /' "$TMP/install10.log"; }
check "the soon-to-be orphan landed" test -f "$F/.claude/commands/temp-thing.md"
"$PKG/install.sh" "$F" --corporate >"$TMP/install11.log" 2>&1 \
  && ok "re-install after an upstream deletion exits 0" \
  || { bad "re-install after an upstream deletion exits 0"; sed 's/^/    /' "$TMP/install11.log"; }
check "orphaned command removed" test ! -e "$F/.claude/commands/temp-thing.md"
check "reaping is reported" grep -q 'removed .claude/commands/temp-thing.md' "$TMP/install11.log"
FNEW="$(comm -13 <(printf '%s\n' "$FBEFORE" | sort) <(gitq "$F" status --porcelain | sort) | grep -v '^$' || true)"
check "git status still clean after the reap" test -z "$FNEW"
check "manifest: belay-created settings.local.json NOT marked merged" \
  bash -c '! sed -n "/^# >>> claude-belay/,/^# <<< claude-belay/p" "$1/.git/info/exclude" \
           | grep -qxF "# merged: /.claude/settings.local.json"' _ "$F"

# A company that commits belay's copy owns it: reaping must never touch it.
"$TMP/pkgorph/install.sh" "$F" --corporate >/dev/null 2>&1
gitq "$F" add -f .claude/commands/temp-thing.md
gitq "$F" commit -qm "company adopts the command"
"$PKG/install.sh" "$F" --corporate >"$TMP/install12.log" 2>&1
check "a tracked belay-path copy is never reaped" test -f "$F/.claude/commands/temp-thing.md"
gitq "$F" rm -q -f --cached .claude/commands/temp-thing.md
gitq "$F" commit -qm "un-adopt"
rm -f "$F/.claude/commands/temp-thing.md"

# Dropping --cursor on a re-install spares the Cursor files, so the manifest
# must keep hiding them or containment breaks for a merely-omitted flag.
G="$TMP/cursor-flag"
mkdir -p "$G"
printf 'print("hi")\n' >"$G/main.py"
gitq "$G" init -q && gitq "$G" add -A && gitq "$G" commit -qm init
GBEFORE="$(gitq "$G" status --porcelain)"
"$PKG/install.sh" "$G" --corporate --cursor >/dev/null 2>&1
mkdir -p "$G/.cursor/rules" && printf 'pointer\n' >"$G/.cursor/rules/belay.mdc"
"$PKG/install.sh" "$G" --corporate >"$TMP/install13.log" 2>&1 \
  && ok "re-install without --cursor exits 0" \
  || { bad "re-install without --cursor exits 0"; sed 's/^/    /' "$TMP/install13.log"; }
check "cursor commands not reaped when --cursor is omitted" test -f "$G/.cursor/commands/plan-feature.md"
check "cursor pointer doc not reaped when --cursor is omitted" test -f "$G/.cursor/rules/belay.mdc"
GNEW="$(comm -13 <(printf '%s\n' "$GBEFORE" | sort) <(gitq "$G" status --porcelain | sort) | grep -v '^$' || true)"
check "git status clean after dropping --cursor" test -z "$GNEW"

# --- mode switch: normal -> corporate ---------------------------------------
# Refused before writing anything: docs/ is tracked, so corporate mode can
# neither relocate nor hide it, and the marker would flip while the no-touch
# check failed — leaving a repo no install could serve.
echo "== mode switch guard (normal -> corporate) =="
H="$TMP/mode-switch"
mkdir -p "$H"
printf 'print("hi")\n' >"$H/main.py"
gitq "$H" init -q && gitq "$H" add -A && gitq "$H" commit -qm init
"$PKG/install.sh" "$H" >/dev/null 2>&1
gitq "$H" add -A && gitq "$H" commit -qm "belay state"
if "$PKG/install.sh" "$H" --corporate >"$TMP/install14.log" 2>&1; then
  bad "--corporate over a normal install is refused"
else
  grep -q 'already has a normal (non-corporate) belay install' "$TMP/install14.log" \
    && ok "--corporate over a normal install is refused" \
    || { bad "--corporate over a normal install: wrong error"; sed 's/^/    /' "$TMP/install14.log"; }
fi
check "refused switch wrote no corporate marker" test ! -e "$H/.claude/workflow/corporate"
check "refused switch wrote no .belay/ tree" test ! -e "$H/.belay"
check "refused switch wrote no exclude block" \
  bash -c '! grep -q claude-belay "$1/.git/info/exclude" 2>/dev/null' _ "$H"
check "plain re-install still works after the refusal" "$PKG/install.sh" "$H"

# ============================ normal-mode regression =========================
echo "== normal mode (regression) =="
B="$TMP/normal"
mkdir -p "$B"
printf 'print("hi")\n' >"$B/main.py"
gitq "$B" init -q
gitq "$B" add -A
gitq "$B" commit -qm init

"$PKG/install.sh" "$B" --cursor >"$TMP/install4.log" 2>&1 \
  && ok "normal install --cursor exits 0" || bad "normal install --cursor exits 0"
check "classic layout: docs/templates/spec.md" test -f "$B/docs/templates/spec.md"
check "classic layout: scripts/build-index.sh" test -x "$B/scripts/build-index.sh"
check "classic layout: .claude/settings.json" test -f "$B/.claude/settings.json"
check "AGENTS.md symlink -> CLAUDE.md" test "$(readlink "$B/AGENTS.md")" = "CLAUDE.md"
check "no corporate artifacts: .belay/" test ! -e "$B/.belay"
check "no corporate artifacts: corporate marker" test ! -e "$B/.claude/workflow/corporate"
check "no corporate artifacts: settings.local.json" test ! -e "$B/.claude/settings.local.json"
check "no corporate artifacts: exclude block" bash -c '! grep -q claude-belay "$1/.git/info/exclude" 2>/dev/null' _ "$B"
check "commands keep canonical paths (no .belay rewrite)" \
  bash -c '! grep -q "\.belay/docs" "$1/.claude/commands/plan-feature.md"' _ "$B"

# ===================== hook wiring is package-owned ==========================
# A hook added upstream must reach an already-installed project on re-install,
# without duplicating what is there and without eating the project's own hooks.
echo "== hook wiring propagation =="
jq '.hooks.PostToolUse += [
      {"matcher":"Edit","hooks":[{"type":"command","command":"echo project-owned"}]},
      {"matcher":"Edit","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/removed-gate.sh"}]}
    ]' "$B/.claude/settings.json" >"$TMP/s.json" && mv "$TMP/s.json" "$B/.claude/settings.json"

# Package copy with one extra hook, standing in for a future release.
mkdir -p "$TMP/pkg"
cp -R "$PKG/install.sh" "$PKG/hooks" "$PKG/commands" "$PKG/templates" "$PKG/scripts" "$PKG/settings" "$TMP/pkg/"
printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/pkg/hooks/dummy-gate.sh"
chmod +x "$TMP/pkg/hooks/dummy-gate.sh"
jq '.hooks.SessionStart = [{"hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/dummy-gate.sh"}]}]' \
  "$TMP/pkg/settings/settings.json" >"$TMP/s.json" && mv "$TMP/s.json" "$TMP/pkg/settings/settings.json"

"$TMP/pkg/install.sh" "$B" >"$TMP/install5.log" 2>&1 \
  && ok "re-install from a newer package exits 0" || { bad "re-install from a newer package exits 0"; sed 's/^/    /' "$TMP/install5.log"; }
check "new hook on a new event reaches an existing install" \
  grep -q 'dummy-gate.sh' "$B/.claude/settings.json"
check "project's own hook entry survives the rewire" \
  grep -q 'project-owned' "$B/.claude/settings.json"
check "wiring of an upstream-deleted hook is dropped" \
  bash -c '! grep -q removed-gate.sh "$1/.claude/settings.json"' _ "$B"
check "no duplicate wiring after re-install" \
  test "$(grep -c 'post-edit-gate.sh' "$B/.claude/settings.json")" = 1

"$PKG/install.sh" "$B" >"$TMP/install6.log" 2>&1   # back to the real package
check "dummy wiring removed once upstream drops it" \
  bash -c '! grep -q dummy-gate.sh "$1/.claude/settings.json"' _ "$B"

# ====================== agent-doc canonicalization ===========================
# CLAUDE.md is the real file, AGENTS.md is a symlink to it or absent. The merge
# itself belongs to the entry command (an LLM), so only the installer's half is
# testable here: it must never clobber an existing agent doc, and must refuse
# the reversed symlink before writing anything.
echo "== agent docs (CLAUDE.md / AGENTS.md) =="

C="$TMP/agents-only"                       # only AGENTS.md, a real file
mkdir -p "$C"
printf '# old rules\n- use tabs\n' >"$C/AGENTS.md"
printf 'print("hi")\n' >"$C/main.py"
gitq "$C" init -q && gitq "$C" add -A && gitq "$C" commit -qm init
"$PKG/install.sh" "$C" --cursor >"$TMP/install7.log" 2>&1 \
  && ok "install with a real AGENTS.md exits 0" || bad "install with a real AGENTS.md exits 0"
check "existing AGENTS.md is left a real file (not symlinked over)" \
  bash -c 'test -f "$1/AGENTS.md" && test ! -L "$1/AGENTS.md"' _ "$C"
check "existing AGENTS.md content untouched by the installer" \
  grep -q 'use tabs' "$C/AGENTS.md"
check "installer announces the pending AGENTS.md merge" \
  grep -q 'AGENTS.md is a real file' "$TMP/install7.log"
check "no CLAUDE.md invented by the installer" test ! -e "$C/CLAUDE.md"

D="$TMP/reversed"                          # CLAUDE.md -> AGENTS.md: must refuse
mkdir -p "$D"
printf '# company rules\n' >"$D/AGENTS.md"
ln -s AGENTS.md "$D/CLAUDE.md"
printf 'print("hi")\n' >"$D/main.py"
gitq "$D" init -q && gitq "$D" add -A && gitq "$D" commit -qm init
"$PKG/install.sh" "$D" >"$TMP/install8.log" 2>&1 \
  && bad "reversed CLAUDE.md symlink is refused" || ok "reversed CLAUDE.md symlink is refused"
check "refusal explains the clobber risk" grep -q 'write' "$TMP/install8.log"
check "refused install wrote nothing" test ! -e "$D/.claude"
check "refused install left the tree clean" test -z "$(gitq "$D" status --porcelain)"

E="$TMP/corp-agents"                       # corporate: both docs are read-only
mkdir -p "$E"
printf '# company CLAUDE\n' >"$E/CLAUDE.md"
printf '# company AGENTS\n' >"$E/AGENTS.md"
printf 'print("hi")\n' >"$E/main.py"
gitq "$E" init -q && gitq "$E" add -A && gitq "$E" commit -qm init
"$PKG/install.sh" "$E" --corporate --cursor >"$TMP/install9.log" 2>&1 \
  && ok "corporate install over both agent docs exits 0" || bad "corporate install over both agent docs exits 0"
check "corporate: AGENTS.md still a real file, unchanged" \
  bash -c 'test ! -L "$1/AGENTS.md" && grep -q "company AGENTS" "$1/AGENTS.md"' _ "$E"
check "corporate: CLAUDE.md unchanged" grep -q 'company CLAUDE' "$E/CLAUDE.md"
check "corporate: no .pre-belay backups written" \
  bash -c '! ls "$1"/.claude/workflow/*.pre-belay >/dev/null 2>&1' _ "$E"

# ============================ install registry ===============================
echo "== install registry / stale report =="
REG="$HOME/.claude-belay/installs"
check "install registered" grep -qxF "$B" "$REG"
check "registered exactly once after repeated installs" test "$(grep -cxF "$B" "$REG")" = 1
check "corporate install registered too" grep -qxF "$A" "$REG"
check "stale report silent when every install is current" \
  bash -c 'test -z "$("$1/scripts/installs-stale.sh")"' _ "$PKG"
printf 'belay deadbee (installed 2020-01-01)\n' >"$B/.claude/workflow/belay-version"
check "stale report names the install left behind" \
  bash -c '"$1/scripts/installs-stale.sh" | grep -q "$2"' _ "$PKG" "$B"

# ============================ index generator ================================
# Both failure modes produced NO index at all, which is worse than a bad one:
# /plan-feature and /validate-phase gate on build-index.sh --check.
echo "== index generator =="
I="$TMP/index-edge"
mkdir -p "$I/Assets/TextMesh Pro" "$I/src"
# A space in a source path aborted the script: xargs split on it, and with
# `set -euo pipefail` a failed command substitution in an assignment exits.
# Unity ships this exact directory, which detect-toolchain.sh exempts by name.
printf 'class A{}\n' >"$I/Assets/TextMesh Pro/foo.cs"
printf 'def f(): pass\n' >"$I/src/a.py"
gitq "$I" init -q && gitq "$I" add -A && gitq "$I" commit -qm init
(cd "$I" && CLAUDE_PROJECT_DIR="$I" "$PKG/scripts/build-index.sh") >"$TMP/index1.log" 2>&1 \
  && ok "index builds with a space in a source path" \
  || { bad "index builds with a space in a source path"; sed 's/^/    /' "$TMP/index1.log"; }
check "index: overview written" test -f "$I/docs/index/_overview.md"
check "index: spaced file indexed" grep -q 'Assets/TextMesh Pro/foo.cs' "$I/docs/index/Assets.md"
check "index: line count not lost to word splitting" grep -q 'Lines: 1' "$I/docs/index/Assets.md"
check "index: --check reports fresh after a build" \
  bash -c 'cd "$1" && CLAUDE_PROJECT_DIR="$1" "$2/scripts/build-index.sh" --check | grep -q "^index fresh"' \
  _ "$I" "$PKG"
# A module name that itself contains a space must not leak into the page filename.
J="$TMP/index-spacemod"
mkdir -p "$J/My Game"
printf 'x = 1\n' >"$J/My Game/a.py"
gitq "$J" init -q && gitq "$J" add -A && gitq "$J" commit -qm init
(cd "$J" && CLAUDE_PROJECT_DIR="$J" "$PKG/scripts/build-index.sh") >/dev/null 2>&1
check "index: spaced module name slugged, not split" test -f "$J/docs/index/My-Game.md"

# A source-free repo exited 0 without writing _overview.md, so --check said
# STALE forever while the rebuild it prescribes wrote nothing — an unbreakable
# loop for /plan-feature step 1 on a greenfield project.
K="$TMP/index-empty"
mkdir -p "$K"
printf '{"name":"t"}\n' >"$K/package.json"
gitq "$K" init -q && gitq "$K" add -A && gitq "$K" commit -qm init
(cd "$K" && CLAUDE_PROJECT_DIR="$K" "$PKG/scripts/build-index.sh") >/dev/null 2>&1 \
  && ok "index builds on a source-free repo" || bad "index builds on a source-free repo"
check "index: source-free repo still gets a stamped overview" \
  grep -q 'workflow-index-stamp' "$K/docs/index/_overview.md"
check "index: source-free repo reports fresh, not a stale loop" \
  bash -c 'cd "$1" && CLAUDE_PROJECT_DIR="$1" "$2/scripts/build-index.sh" --check | grep -q "^index fresh"' \
  _ "$K" "$PKG"

# ============================= toolchain gaps ================================
# P7: a gap is stated, never silent. Node without tsconfig.json left typecheck
# in neither "commands" nor "gaps", so /validate-phase silently skipped it.
echo "== toolchain gaps =="
L="$TMP/toolchain-node"
mkdir -p "$L"
printf '{"name":"t","scripts":{"test":"node --test"},"devDependencies":{"eslint":"^9"}}\n' >"$L/package.json"
gitq "$L" init -q && gitq "$L" add -A && gitq "$L" commit -qm init
(cd "$L" && CLAUDE_PROJECT_DIR="$L" "$PKG/hooks/lib/detect-toolchain.sh") >"$TMP/tc1.log" 2>&1 \
  && ok "detect-toolchain runs on a plain-JS node repo" || bad "detect-toolchain runs on a plain-JS node repo"
check "node without tsconfig.json reports a typecheck gap" \
  bash -c 'jq -e ".gaps[] | select(startswith(\"typecheck (node)\"))" "$1/.claude/workflow/toolchain.json"' \
  _ "$L"
check "typecheck absent from commands (nothing invented)" \
  bash -c 'test "$(jq -r ".commands.typecheck // \"absent\"" "$1/.claude/workflow/toolchain.json")" = absent' \
  _ "$L"

echo ""
echo "corporate-smoke: $((CHECKS-FAILS))/$CHECKS passed"
[ "$FAILS" -eq 0 ] || { echo "corporate-smoke: FAILED ($FAILS)"; exit 1; }
