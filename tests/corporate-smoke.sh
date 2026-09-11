#!/usr/bin/env bash
# The package's smoke suite. Named for its origin (install.sh --corporate) but it
# now covers the whole package: it builds a hostile scratch repo (tracked
# CLAUDE.md, tracked .claude/settings.json and docs/, a tracked homonymous
# command, a pre-existing settings.local.json), installs, and asserts every
# corporate guarantee — plus normal-mode regressions, agent-doc canonicalization,
# the install registry, the index generator, toolchain gap detection, edit-gate
# behaviour, and documentation consistency. Run from anywhere:
#   tests/corporate-smoke.sh
#
# Every assert here should be able to fail: when adding one, check it fails
# against the commit before the fix. Three consistency asserts guard the
# "two files say different things" class that no behavioural test can see.
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
unrewritten="$(grep -RhoE '(\.belay/)?(docs/(product|adr|phases|index|security|templates|constraints\.md|adoption-report\.md)|scripts/(build-index|check)\.sh)' "${seddirs[@]}" | grep -v '^\.belay/' || true)"
check "sed: no unrewritten docs/ or scripts/ references" test -z "$unrewritten"
check "sed: no double rewrite (.belay/.belay)" bash -c '! grep -Rq "\.belay/\.belay" "$1" "$2" "$3"' _ "${seddirs[@]}" "$A/.belay"
check "sed: build-index OUTDIR relocated" grep -q '\.belay/docs/index' "$A/.belay/scripts/build-index.sh"
check "corporate: check.sh installed under .belay/scripts" test -x "$A/.belay/scripts/check.sh"
check "sed: post-edit-gate containment globs survived rewrite" grep -q 'docs/\[p\]roduct' "$A/.claude/hooks/post-edit-gate.sh"

# settings.local.json merged, not clobbered
check "settings.local.json: custom key preserved" test "$(jq -r .belaytest "$A/.claude/settings.local.json")" = "keep"
check "settings.local.json: hook wiring merged in" grep -q 'edit-gate-adapter.sh' "$A/.claude/settings.local.json"

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
gaterun() { # gaterun <gate> <file> — runs installed gate with argv, returns its exit
  CLAUDE_PROJECT_DIR="$A" "$A/.claude/hooks/$1" "$2" >/dev/null 2>&1
}
hookrun bash-gate-adapter.sh '{"tool_input":{"command":"git clean -fdx"}}' \
  && bad "clean guard: git clean -fdx blocked" || ok "clean guard: git clean -fdx blocked"
hookrun bash-gate-adapter.sh '{"tool_input":{"command":"git clean -fd"}}' \
  && ok "clean guard: git clean -fd (no -x) passes" || bad "clean guard: git clean -fd (no -x) passes"
hookrun bash-gate-adapter.sh '{"tool_input":{"command":"git clean --exclude=foo -fd"}}' \
  && ok "clean guard: --exclude does not false-positive" || bad "clean guard: --exclude does not false-positive"

mkdir -p "$A/docs/phases" && printf 'stray\n' >"$A/docs/phases/stray.md"
hookrun bash-gate-adapter.sh '{"tool_input":{"command":"git commit -m x"}}' \
  && bad "containment: commit blocked while stray docs/phases file exists" \
  || ok "containment: commit blocked while stray docs/phases file exists"
gaterun post-edit-gate.sh "$A/docs/phases/stray.md" \
  && bad "containment: post-edit-gate flags write to old canonical path" \
  || ok "containment: post-edit-gate flags write to old canonical path"
rm -rf "$A/docs/phases"
hookrun bash-gate-adapter.sh '{"tool_input":{"command":"git commit -m x"}}' \
  && ok "containment: commit passes once stray file removed" \
  || bad "containment: commit passes once stray file removed"
gaterun post-edit-gate.sh "$A/docs/adr/001-company.md" \
  && ok "containment: tracked company docs/adr file passes" \
  || bad "containment: tracked company docs/adr file passes"
mkdir -p "$A/.belay/docs/phases" && printf 'legit\n' >"$A/.belay/docs/phases/notes.md"
gaterun post-edit-gate.sh "$A/.belay/docs/phases/notes.md" \
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
  test "$(grep -c 'edit-gate-adapter.sh' "$B/.claude/settings.json")" = 1

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
# --check was commit-relative only: HEAD does not move during a phase, so the stamp always
# equalled HEAD and the check short-circuited to "fresh" however far the index had drifted
# from the files on disk — a no-op for the window /validate-phase step 4 runs in. The edit
# below is left uncommitted on purpose, which is the whole reported case; ageing the
# overview alongside it keeps the mtime comparison off the clock's granularity.
printf 'def f(): pass\ndef g(): pass\n' >"$I/src/a.py"
touch -t 202001010000 "$I/docs/index/_overview.md"
check "index: --check reports stale when source is newer than the index" \
  bash -c 'cd "$1" && CLAUDE_PROJECT_DIR="$1" "$2/scripts/build-index.sh" --check | grep -q "^index STALE"' \
  _ "$I" "$PKG"
check "index: --check reports fresh again after the rebuild" \
  bash -c 'cd "$1" && CLAUDE_PROJECT_DIR="$1" "$2/scripts/build-index.sh" >/dev/null &&
           CLAUDE_PROJECT_DIR="$1" "$2/scripts/build-index.sh" --check | grep -q "^index fresh"' \
  _ "$I" "$PKG"
# A deletion stays in `git status` until it is committed, so judging a vanished path by
# mtime would report STALE forever — including right after the rebuild that fixed it. The
# operator who deletes a file by hand mid-phase (a blocked phase, --implemented) is exactly
# who hits that, and a check that cannot go green is the defect this fix exists to remove.
rm "$I/src/a.py"
check "index: --check reports stale on an uncommitted source deletion" \
  bash -c 'cd "$1" && CLAUDE_PROJECT_DIR="$1" "$2/scripts/build-index.sh" --check | grep -q "^index STALE"' \
  _ "$I" "$PKG"
check "index: --check clears once the deletion is rebuilt out of the index" \
  bash -c 'cd "$1" && CLAUDE_PROJECT_DIR="$1" "$2/scripts/build-index.sh" >/dev/null &&
           CLAUDE_PROJECT_DIR="$1" "$2/scripts/build-index.sh" --check | grep -q "^index fresh"' \
  _ "$I" "$PKG"
# mtime alone cannot see an edit that lands in the same clock tick as the build. Ageing the
# file below the index reproduces that blind spot deterministically, without racing the
# clock: the content differs, the timestamp says otherwise, and only the line count the
# index already records can tell.
printf 'x = 1\ny = 2\nz = 3\n' >"$I/src/a.py"
touch -t 202001010000 "$I/src/a.py"
check "index: --check catches an edit mtime cannot see" \
  bash -c 'cd "$1" && CLAUDE_PROJECT_DIR="$1" "$2/scripts/build-index.sh" --check | grep -q "^index STALE"' \
  _ "$I" "$PKG"
# A module name that itself contains a space must not leak into the page filename.
J="$TMP/index-spacemod"
mkdir -p "$J/My Game"
printf 'x = 1\n' >"$J/My Game/a.py"
gitq "$J" init -q && gitq "$J" add -A && gitq "$J" commit -qm init
(cd "$J" && CLAUDE_PROJECT_DIR="$J" "$PKG/scripts/build-index.sh") >/dev/null 2>&1
check "index: spaced module name slugged, not split" test -f "$J/docs/index/My-Game.md"

# Nothing pinned the `## Depends on` section, so the edge scan could be rewritten or broken
# in silence. These three cover the two branches the matcher has — the full module key and
# the delimited basename — plus the negative case.
L="$TMP/index-edges"
mkdir -p "$L/src/api" "$L/src/db" "$L/src/lonely"
printf 'import c from "../db/conn"\nexport const q = 1\n' >"$L/src/api/a.js"
printf 'export const conn = 1\n' >"$L/src/db/conn.js"
printf 'export const alone = 1\n' >"$L/src/lonely/x.js"
gitq "$L" init -q && gitq "$L" add -A && gitq "$L" commit -qm init
(cd "$L" && CLAUDE_PROJECT_DIR="$L" "$PKG/scripts/build-index.sh") >/dev/null 2>&1
check "index: edge detected from an import naming the module" \
  bash -c 'sed -n "/^## Depends on/,\$p" "$1/docs/index/src-api.md" | grep -q "src/db"' _ "$L"
check "index: a module importing nothing declares none" \
  bash -c 'sed -n "/^## Depends on/,\$p" "$1/docs/index/src-lonely.md" | grep -q "_none detected_"' _ "$L"
check "index: the overview lists the edge" \
  grep -q 'src/api -> src/db' "$L/docs/index/_overview.md"
# The old form interpolated the module key into an ERE, so a dot in a directory name was a
# wildcard. The shell test matches literally; nothing else would notice that changing back.
mkdir -p "$L/src/foo.bar" "$L/src/fooXbar"
printf 'export const a = 1\n' >"$L/src/foo.bar/a.js"
printf 'import z from "../fooXbar/b"\nexport const b = 1\n' >"$L/src/fooXbar/b.js"
gitq "$L" add -A && gitq "$L" commit -qm dots
(cd "$L" && CLAUDE_PROJECT_DIR="$L" "$PKG/scripts/build-index.sh") >/dev/null 2>&1
check "index: a dot in a module name is literal, not a wildcard" \
  bash -c '! grep -q "src/fooXbar -> src/foo.bar" "$1/docs/index/_overview.md"' _ "$L"

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

# The manual file is project-owned: re-detection must not read, rewrite or delete
# it. The byte-identical assert is a forward guard — the detector does not open
# the file today, so it cannot fail against the commit that introduced it; it is
# here to catch a later refactor that makes detection "merge" the manual file.
printf '{ "commands": { "test": "my-custom-runner" } }\n' >"$L/.claude/workflow/toolchain.manual.json"
MANUAL_BEFORE="$(cat "$L/.claude/workflow/toolchain.manual.json")"
(cd "$L" && CLAUDE_PROJECT_DIR="$L" "$PKG/hooks/lib/detect-toolchain.sh") >"$TMP/tc2.log" 2>&1
check "re-detection leaves toolchain.manual.json byte-identical" \
  bash -c 'test "$(cat "$1")" = "$2"' _ "$L/.claude/workflow/toolchain.manual.json" "$MANUAL_BEFORE"
check "re-detection reports that a manual file is in play" \
  grep -q 'toolchain.manual.json present' "$TMP/tc2.log"

# ========================= edit-gate behaviour ===============================
# Formatters all write in place, so a successful format leaves the file on disk
# different from what was just written — silently, until a later edit fails to
# match. And the edit gates used to exit 0 with no JSON parser, i.e. not run at
# all, while the commit gate fails closed on the same condition.
echo "== edit gates =="
M="$TMP/gates"
mkdir -p "$M/.claude/workflow"
gitq "$M" init -q
printf 'let x = 1\n' >"$M/a.js"
tcjson() { printf '{ "stacks": ["fake"], "commands": {}, "file_commands": { "js": { "format": %s, "lint": %s } }, "exempt": [], "gaps": [] }\n' "$1" "$2" >"$M/.claude/workflow/toolchain.json"; }
gate() { CLAUDE_PROJECT_DIR="$M" "$PKG/hooks/post-edit-gate.sh" "$M/a.js" 2>"$TMP/gate.err"; }

tcjson '"true"' '"true"'
gate && ok "no-op formatter stays silent (exit 0)" || bad "no-op formatter stays silent (exit 0)"
check "no-op formatter prints nothing" test ! -s "$TMP/gate.err"

tcjson '"echo formatted >>"' '"true"'   # appends: rewrites the file, lint passes
gate && bad "in-place reformat is reported" || ok "in-place reformat is reported"
check "reformat message names the file and says re-read" \
  bash -c 'grep -q "REFORMATTED ON DISK" "$1" && grep -q "Re-read it" "$1"' _ "$TMP/gate.err"

tcjson '"echo formatted >>"' '"false"'  # reformat AND a lint failure: one report, not two
gate && bad "lint failure still reported when the file was also reformatted" \
     || ok "lint failure still reported when the file was also reformatted"
check "combined report leads with the gate failure" grep -q 'POST-EDIT GATE FAILED' "$TMP/gate.err"
check "combined report also mentions the reformat" grep -q 'formatter also rewrote' "$TMP/gate.err"

# --- toolchain.manual.json ---------------------------------------------------
# detect-toolchain.sh rewrites toolchain.json wholesale on every /refresh-index,
# so a command hand-added there was silently lost while the README called the
# file project-owned. The manual file is the durable half: the detector never
# opens it, and common.sh consults it before the generated one.
tcmanual() { printf '%s\n' "$1" >"$M/.claude/workflow/toolchain.manual.json"; }
gatef() { CLAUDE_PROJECT_DIR="$M" "$PKG/hooks/post-edit-gate.sh" "$M/$1" 2>"$TMP/gate.err"; }

# Supplies a tool detection missed entirely: without it this file has no gates.
printf '{ "stacks": ["fake"], "commands": {}, "file_commands": {}, "exempt": [], "gaps": [] }\n' \
  >"$M/.claude/workflow/toolchain.json"
tcmanual '{ "file_commands": { "js": { "format": "echo manual-fmt >>" } } }'
gate && bad "manual file supplies a formatter detection missed" \
     || ok "manual file supplies a formatter detection missed"
check "the manual formatter ran, instead of a gap warning" \
  bash -c 'grep -q "REFORMATTED ON DISK" "$1" && ! grep -q "workflow gap" "$1"' _ "$TMP/gate.err"

# Same ext + category in both files: the manual one wins.
tcjson '"true"' '"true"'   # detected formatter is a no-op, so only manual rewrites
tcmanual '{ "file_commands": { "js": { "format": "echo manual-fmt >>" } } }'
gate && bad "manual command overrides the detected one" \
     || ok "manual command overrides the detected one"
check "the command that ran is the manual one, not the detected no-op" \
  grep -q 'REFORMATTED ON DISK' "$TMP/gate.err"

# exempt is a list: manual APPENDS to detection, it does not replace it.
printf '{ "stacks": ["fake"], "commands": {}, "file_commands": { "js": { "lint": "false" } }, "exempt": ["vendor/"], "gaps": [] }\n' \
  >"$M/.claude/workflow/toolchain.json"
tcmanual '{ "exempt": ["thirdparty/"] }'
mkdir -p "$M/vendor" "$M/thirdparty"
printf 'let y = 1\n' >"$M/vendor/c.js"
printf 'let z = 1\n' >"$M/thirdparty/b.js"
gatef thirdparty/b.js && ok "manual exempt prefix is honoured" \
                      || bad "manual exempt prefix is honoured"
gatef vendor/c.js && ok "detected exempt prefix survives the append" \
                  || bad "detected exempt prefix survives the append"
rm -f "$M/.claude/workflow/toolchain.manual.json"

# No jq and no python3: the gates must say they did not run, not exit 0.
NOJSON="$TMP/nojson"
mkdir -p "$NOJSON"
for t in bash dirname basename cat grep sed awk cut shasum sha1sum cksum git printf rm ls mktemp; do
  b="$(command -v $t 2>/dev/null)" && ln -sf "$b" "$NOJSON/$t"
done
check "sandbox PATH really has no jq/python3 but does have dirname" \
  bash -c 'PATH="$1"; ! command -v jq >/dev/null && ! command -v python3 >/dev/null && command -v dirname >/dev/null' _ "$NOJSON"
printf 'layer a src/\nlayer b lib/\ndeny a -> b\n' >"$M/.claude/workflow/boundaries.rules"
# The gates take argv and parse nothing, so the fail-closed contract moved to
# the one file that still reads a payload. If it ever exits 0 here, both gates
# are silently skipped on every edit — the exact thing P7 forbids.
h=edit-gate-adapter
if printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/a.js"}}' "$M" \
   | env PATH="$NOJSON" CLAUDE_PROJECT_DIR="$M" bash "$PKG/hooks/$h.sh" >/dev/null 2>"$TMP/$h.err"; then
  bad "$h fails closed with no JSON parser"
else
  grep -q 'DID NOT RUN' "$TMP/$h.err" && ok "$h fails closed with no JSON parser" \
    || { bad "$h fails closed: wrong message"; sed 's/^/    /' "$TMP/$h.err"; }
fi

# One payload, two entry points: the adapter must produce what calling the gate
# directly produces, or the agent path and the shell path drift apart silently.
tcjson '"echo formatted >>"' '"true"'
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/a.js"}}' "$M" \
  | CLAUDE_PROJECT_DIR="$M" "$PKG/hooks/edit-gate-adapter.sh" 2>"$TMP/via-adapter.err" || true
CLAUDE_PROJECT_DIR="$M" "$PKG/hooks/post-edit-gate.sh" "$M/a.js" 2>"$TMP/via-argv.err" || true
check "adapter and direct call report the same thing" \
  cmp -s "$TMP/via-adapter.err" "$TMP/via-argv.err"

# The gate is now callable with no payload at all — that is the interface CI and
# the git hook use, and nothing covered it while it was a PreToolUse hook.
BARE="$TMP/bare-gate"
mkdir -p "$BARE/.claude/workflow"
cp -R "$PKG/hooks/." "$BARE/.claude/hooks/"
gitq "$BARE" init -q
printf 'aws_key = "AKIAIOSFODNN7EXAMPLE"\n' >"$BARE/leak.txt"
gitq "$BARE" add leak.txt
CLAUDE_PROJECT_DIR="$BARE" "$BARE/.claude/hooks/pre-commit-security.sh" >/dev/null 2>&1 \
  && bad "gate blocks a staged secret when called bare (no payload)" \
  || ok "gate blocks a staged secret when called bare (no payload)"
gitq "$BARE" rm -q --cached leak.txt >/dev/null && rm -f "$BARE/leak.txt"
printf 'clean\n' >"$BARE/ok.txt"; gitq "$BARE" add ok.txt
CLAUDE_PROJECT_DIR="$BARE" "$BARE/.claude/hooks/pre-commit-security.sh" >/dev/null 2>&1 \
  && ok "gate passes a clean staged set when called bare" \
  || bad "gate passes a clean staged set when called bare"

# ============================== check.sh runner ==============================
# Until now the only thing that read toolchain.json's project-wide commands was
# /validate-phase — a markdown file. Running your own gates required an agent.
echo "== check.sh runner =="
C="$TMP/checkrun"
mkdir -p "$C/.claude/hooks/lib" "$C/.claude/workflow"
gitq "$C" init -q
cp "$PKG/hooks/lib/common.sh" "$C/.claude/hooks/lib/common.sh"
cp "$PKG/scripts/check.sh" "$C/check.sh"
# check.sh resolves common.sh from the git root, so the fixture needs it at that
# exact path; copying only check.sh fails every assert for the wrong reason.
cjson() { printf '%s\n' "$1" >"$C/.claude/workflow/toolchain.json"; }
cmanual() { printf '%s\n' "$1" >"$C/.claude/workflow/toolchain.manual.json"; }
runcheck() { (cd "$C" && ./check.sh "$@") >"$TMP/check.out" 2>&1; }

cjson '{ "commands": { "test": "true", "lint": "true", "typecheck": "true" } }'
runcheck && ok "all categories passing exits 0" || bad "all categories passing exits 0"
check "each passing category is reported" \
  bash -c 'test "$(grep -c "   PASS" "$1")" = 3' _ "$TMP/check.out"

cjson '{ "commands": { "test": "true", "lint": "false", "typecheck": "true" } }'
runcheck && bad "a failing category exits 1" || ok "a failing category exits 1"
check "the summary names the failed category" grep -q 'FAILED — lint' "$TMP/check.out"

# A gap is loud but not a failure: an unconfigured category must not turn a
# green run red, or nobody configures anything (P7).
cjson '{ "commands": { "test": "true" } }'
runcheck && ok "an unconfigured category does not fail the run" \
         || bad "an unconfigured category does not fail the run"
check "the unconfigured category is reported as a gap" grep -q 'workflow gap:' "$TMP/check.out"

# The CLI reaches the manual file too — this is what tc_init exists for.
cjson '{ "commands": { "test": "false" } }'
cmanual '{ "commands": { "test": "true" } }'
runcheck test && ok "manual command wins from the CLI" || bad "manual command wins from the CLI"
rm -f "$C/.claude/workflow/toolchain.manual.json"

# --files: the same gates the agent hits, addressed by path.
mkdir -p "$C/.claude/hooks" "$C/src" "$C/lib"
cp "$PKG/hooks/post-edit-gate.sh" "$PKG/hooks/boundary-check.sh" "$C/.claude/hooks/"
printf 'layer app src/\nlayer infra lib/\ndeny app -> infra\n' >"$C/.claude/workflow/boundaries.rules"
cjson '{ "commands": {}, "file_commands": {}, "exempt": [], "gaps": [] }'
printf 'import x from "../lib/db"\n' >"$C/src/bad.js"
printf 'const x = 1\n' >"$C/src/good.js"
runcheck --files src/bad.js && bad "--files blocks a boundary violation" \
                            || ok "--files blocks a boundary violation"
check "--files names the violated rule" grep -q 'BOUNDARY VIOLATION' "$TMP/check.out"
runcheck --files src/good.js && ok "--files passes a clean file" || bad "--files passes a clean file"

# The gate's contract was underivable from its header: a wrapper built on it treated any
# non-zero as a layering breach, so a broken hook would have been reported to the operator
# as a violation. Every caller here (edit-gate-adapter, check.sh) folds non-zero into
# "violation", so these pin 2 as the only failure code and keep the no-coverage cases at 0.
bc() { (cd "$C" && CLAUDE_PROJECT_DIR="$C" ./.claude/hooks/boundary-check.sh "$@" >/dev/null 2>&1; echo $?); }
check "boundary-check: violation exits exactly 2" test "$(bc src/bad.js)" = 2
check "boundary-check: clean file in a layer exits 0" test "$(bc src/good.js)" = 0
mkdir -p "$C/tools" && printf 'const t = 1\n' >"$C/tools/t.js"
check "boundary-check: file under no declared layer exits 0" test "$(bc tools/t.js)" = 0
mv "$C/.claude/workflow/boundaries.rules" "$C/.claude/workflow/boundaries.rules.off"
check "boundary-check: no rules file exits 0" test "$(bc src/bad.js)" = 0
mv "$C/.claude/workflow/boundaries.rules.off" "$C/.claude/workflow/boundaries.rules"
rm -rf "$C/tools"

# --staged: the human commit path. Same gates, addressed by what git has staged.
cp "$PKG/hooks/pre-commit-security.sh" "$C/.claude/hooks/"
gitq "$C" add -A >/dev/null; gitq "$C" commit -qm init
printf 'import y from "../lib/db"\n' >"$C/src/bad2.js"; gitq "$C" add src/bad2.js
runcheck --staged && bad "--staged blocks a staged boundary violation" \
                  || ok "--staged blocks a staged boundary violation"
gitq "$C" reset -q; rm -f "$C/src/bad2.js"

# A formatter that rewrites a staged file invalidates what git holds: the commit
# would capture the unformatted blob while the worktree has the formatted one.
cjson '{ "commands": {}, "file_commands": { "js": { "format": "echo fmt >>" } }, "exempt": [], "gaps": [] }'
printf 'const z = 1\n' >"$C/src/fmt.js"; gitq "$C" add src/fmt.js
runcheck --staged && bad "--staged blocks when a formatter rewrote a staged file" \
                  || ok "--staged blocks when a formatter rewrote a staged file"
check "--staged says which files to re-stage" \
  bash -c 'grep -q "Stage them and commit again" "$1" && grep -q "src/fmt.js" "$1"' _ "$TMP/check.out"
gitq "$C" reset -q; rm -f "$C/src/fmt.js"

cjson '{ "commands": {}, "file_commands": {}, "exempt": [], "gaps": [] }'
printf 'const ok = 1\n' >"$C/src/clean.js"; gitq "$C" add src/clean.js
runcheck --staged && ok "--staged passes a clean staged set" || bad "--staged passes a clean staged set"
gitq "$C" reset -q

# ==================== normal-mode orphan reaping =============================
echo "== normal-mode orphan reaping =="
N="$TMP/norm-orphan"
mkdir -p "$N"
printf 'print("hi")\n' >"$N/main.py"
gitq "$N" init -q && gitq "$N" add -A && gitq "$N" commit -qm init
mkdir -p "$TMP/pkgnorm"
cp -R "$PKG/install.sh" "$PKG/hooks" "$PKG/commands" "$PKG/templates" "$PKG/scripts" "$PKG/settings" "$TMP/pkgnorm/"
printf '# a command a later release drops\n' >"$TMP/pkgnorm/commands/temp-thing.md"
"$TMP/pkgnorm/install.sh" "$N" >/dev/null 2>&1
check "manifest written" test -f "$N/.claude/workflow/installed"
check "manifest lists a command" grep -qx '.claude/commands/plan-feature.md' "$N/.claude/workflow/installed"
# /validate-phase decides "upstream" by asking whether the manifest lists the file, so the
# manifest has to hold exactly the package-owned set. record() runs only inside copy_into,
# which is why boundaries.rules (created separately) and toolchain.json (written by
# detection) stay out — if that ever changes, attribution starts blaming the package for a
# project's own config.
check "installed manifest excludes project-owned files" \
  bash -c '! grep -qxF ".claude/workflow/boundaries.rules" "$1/.claude/workflow/installed" &&
           ! grep -qxF ".claude/workflow/toolchain.json" "$1/.claude/workflow/installed"' _ "$N"
check "installed manifest holds the package files attribution points at" \
  bash -c 'grep -qxF ".claude/hooks/boundary-check.sh" "$1/.claude/workflow/installed" &&
           grep -qxF ".claude/commands/validate-phase.md" "$1/.claude/workflow/installed"' _ "$N"
printf 'the project own command\n' >"$N/.claude/commands/my-own.md"
"$PKG/install.sh" "$N" >"$TMP/install15.log" 2>&1 \
  && ok "normal re-install after an upstream deletion exits 0" \
  || { bad "normal re-install after an upstream deletion exits 0"; sed 's/^/    /' "$TMP/install15.log"; }
check "normal mode reaps the dropped command" test ! -e "$N/.claude/commands/temp-thing.md"
check "the project's own command survives the reap" test -f "$N/.claude/commands/my-own.md"
check "belay's wiring survives the reap" test -f "$N/.claude/settings.json"

# Corporate installs predating the manifest fall back to the old exclude block —
# which also names files copy_into never wrote and must never delete.
O="$TMP/corp-fallback"
mkdir -p "$O"
printf 'print("hi")\n' >"$O/main.py"
gitq "$O" init -q && gitq "$O" add -A && gitq "$O" commit -qm init
OBEFORE="$(gitq "$O" status --porcelain)"
"$TMP/pkgnorm/install.sh" "$O" --corporate >/dev/null 2>&1
rm -f "$O/.claude/workflow/installed"          # as an older belay would have left it
"$PKG/install.sh" "$O" --corporate >"$TMP/install16.log" 2>&1 \
  && ok "corporate re-install with no manifest exits 0" \
  || { bad "corporate re-install with no manifest exits 0"; sed 's/^/    /' "$TMP/install16.log"; }
check "fallback reaps the dropped command" test ! -e "$O/.claude/commands/temp-thing.md"
check "fallback never deletes the hook wiring" test -f "$O/.claude/settings.local.json"
check "fallback leaves the wiring intact" grep -q 'edit-gate-adapter.sh' "$O/.claude/settings.local.json"
ONEW="$(comm -13 <(printf '%s\n' "$OBEFORE" | sort) <(gitq "$O" status --porcelain | sort) | grep -v '^$' || true)"
check "git status clean after the fallback reap" test -z "$ONEW"

# ======================= stale report: unknown stamp =========================
# `belay unknown` can never equal HEAD, so reporting it as behind nagged forever.
printf 'belay unknown (installed 2020-01-01)\n' >"$N/.claude/workflow/belay-version"
"$PKG/scripts/installs-stale.sh" >"$TMP/stale.log" 2>&1 || true
check "unknown stamp reported as uncomparable, not behind" \
  bash -c 'grep -q "version unknown" "$1" && ! grep -q "installs behind.*-> " "$1"' _ "$TMP/stale.log"

# ========================== git pre-commit hook ==============================
# The gate belay wires into Claude Code only ever sees the agent's commands.
# --git-hook extends it to human commits — and must never eat an existing hook.
echo "== git pre-commit hook (--git-hook) =="
G="$TMP/githook"
mkdir -p "$G"; gitq "$G" init -q; printf 'x\n' >"$G/a.txt"; gitq "$G" add -A; gitq "$G" commit -qm init

check "no --git-hook: no pre-commit written" \
  bash -c '"$1/install.sh" "$2" >/dev/null 2>&1 && test ! -e "$2/.git/hooks/pre-commit"' _ "$PKG" "$G"

"$PKG/install.sh" "$G" --git-hook >"$TMP/gh1.log" 2>&1 \
  && ok "--git-hook exits 0" || { bad "--git-hook exits 0"; sed 's/^/    /' "$TMP/gh1.log"; }
check "pre-commit created and executable" test -x "$G/.git/hooks/pre-commit"

# The whole point: a real `git commit` by a person must be blocked.
printf 'aws_key = "AKIAIOSFODNN7EXAMPLE"\n' >"$G/leak.txt"; gitq "$G" add leak.txt
check "human commit with a staged secret is BLOCKED" \
  bash -c '! git -C "$1" -c user.email=t@t -c user.name=t commit -qm leak' _ "$G"
check "--no-verify still commits (documented escape hatch)" \
  gitq "$G" commit -q --no-verify -m leak
gitq "$G" reset -q --hard HEAD~1

# Re-install must not append a second copy.
"$PKG/install.sh" "$G" --git-hook >"$TMP/gh2.log" 2>&1
check "re-install leaves the hook byte-identical to the shipped one" \
  cmp -s "$PKG/settings/pre-commit.githook" "$G/.git/hooks/pre-commit"
check "re-install refreshes belay's own hook" grep -q "belay's own hook — refreshed" "$TMP/gh2.log"

# A hook from before the shim retargeted carries the old marker only. It must be
# upgraded, not mistaken for a third party's and left behind forever.
printf '#!/bin/sh\nexec .claude/hooks/pre-commit-security.sh\n' >"$G/.git/hooks/pre-commit"
"$PKG/install.sh" "$G" --git-hook >"$TMP/gh2b.log" 2>&1
check "a hook with only the pre-retarget marker is upgraded" \
  cmp -s "$PKG/settings/pre-commit.githook" "$G/.git/hooks/pre-commit"

# Someone else's hook is sacred: left byte-identical, instructions printed.
P="$TMP/githook-pre-existing"
mkdir -p "$P"; gitq "$P" init -q; printf 'x\n' >"$P/a.txt"; gitq "$P" add -A; gitq "$P" commit -qm init
printf '#!/bin/sh\necho theirs\n' >"$P/.git/hooks/pre-commit"; chmod +x "$P/.git/hooks/pre-commit"
H_PRE="$(shasum "$P/.git/hooks/pre-commit" | cut -d' ' -f1)"
"$PKG/install.sh" "$P" --git-hook >"$TMP/gh3.log" 2>&1
check "pre-existing hook left byte-identical" \
  test "$(shasum "$P/.git/hooks/pre-commit" | cut -d' ' -f1)" = "$H_PRE"
check "pre-existing hook: manual-merge line printed" grep -q 'append this line' "$TMP/gh3.log"

# core.hooksPath (husky et al) must be honoured, or the hook lands where git never looks.
Q="$TMP/githook-hookspath"
mkdir -p "$Q"; gitq "$Q" init -q; printf 'x\n' >"$Q/a.txt"; gitq "$Q" add -A; gitq "$Q" commit -qm init
gitq "$Q" config core.hooksPath .husky
"$PKG/install.sh" "$Q" --git-hook >"$TMP/gh4.log" 2>&1
check "core.hooksPath honoured (.husky/, not .git/hooks/)" \
  bash -c 'test -x "$1/.husky/pre-commit" && test ! -e "$1/.git/hooks/pre-commit"' _ "$Q"

# Uninstalling belay must not brick commits — the hook fails open.
rm -rf "$G/.claude"
check "fails open once belay is gone" \
  gitq "$G" commit -q --allow-empty -m "after uninstall"

# ===================== documentation consistency =============================
# This whole class of bug is "two files say different things", so it fails here
# rather than in the next audit.
echo "== documentation consistency =="
VOCAB='pending | expanded | in-progress | blocked | superseded by <ids> | done'
check "status vocabulary identical in both CLAUDE templates" \
  bash -c 'test "$(grep -lF "$2" "$1/templates/CLAUDE.bootstrap.md" "$1/templates/CLAUDE.adopted.md" | wc -l | tr -d " ")" = 2' \
  _ "$PKG" "$VOCAB"
for s in pending expanded in-progress blocked "superseded by" done; do
  check "PHASES.md template defines status '$s'" grep -qF "$s" "$PKG/templates/PHASES.md"
done
# A finding is the one category with no artifact of its own: it lands in a section
# of constraints.md that also holds something else. So the only thing keeping it
# out of docs/adr/ is what the always-loaded CLAUDE.md says, and both variants
# have to say it identically -- a project on the bootstrap template routing
# findings differently from one on the adopted template is the corruption of
# /plan-feature this sentence exists to prevent.
FINDING='is a **finding**, not an ADR: it goes to `docs/constraints.md` `§Observed conventions`'
check "finding routing identical in both CLAUDE templates" \
  bash -c 'test "$(grep -lF "$2" "$1/templates/CLAUDE.bootstrap.md" "$1/templates/CLAUDE.adopted.md" | wc -l | tr -d " ")" = 2' \
  _ "$PKG" "$FINDING"
# Every §Section referenced anywhere in the shipped commands and templates must
# exist in constraints.md — the file all of them mean by §. This is #10's class:
# /expand-phase pointed at a "repair protocol in docs/constraints.md" that was
# never in the template. Assert the reference set is non-empty first, or the loop
# silently validates nothing and looks like coverage.
refs="$(grep -rhoE '§[A-Za-z][A-Za-z]*( [a-z][A-Za-z]*)*' "$PKG"/commands/*.md "$PKG"/templates/*.md \
        | sed 's/^§//;s/ *$//' | sort -u)"
check "there are §section references to validate" test -n "$refs"
missing=""
while IFS= read -r sec; do
  [ -n "$sec" ] || continue
  grep -qiE "^#+ +$sec\$" "$PKG/templates/constraints.md" || missing="$missing '$sec'"
done <<<"$refs"
check "every §section referenced by a command or template exists in constraints.md" test -z "$missing"
[ -z "$missing" ] || echo "    missing sections:$missing"
# gap_warn is the entry point to hand-configuration: it is what an operator reads
# when a gate has no tool. The file it names must be the one the README calls
# project-owned, or the message sends people to a file re-detection overwrites —
# which is exactly the bug this assert was written for.
gapfile="$(grep 'workflow gap:' "$PKG/hooks/lib/common.sh" \
           | grep -oE '\.claude/workflow/[A-Za-z.]+\.json' | head -1)"
check "gap_warn names a workflow file to edit" test -n "$gapfile"
check "the file gap_warn points at is listed as project-owned in the README" \
  bash -c 'grep -A4 "^\*\*Customize (project-owned):\*\*" "$1/README.md" | grep -qF "$2"' \
  _ "$PKG" "$gapfile"

# check.sh's usage block is its own source of truth; the README repeats it. A mode
# added without documenting it is invisible to everyone who is not reading shell.
modes="$(sed -n '3,6p' "$PKG/scripts/check.sh" | grep -oE '^# +check\.sh --[a-z]+' | grep -oE '\-\-[a-z]+')"
check "check.sh declares at least one mode flag" test -n "$modes"
missingmodes=""
while IFS= read -r m; do
  [ -n "$m" ] || continue
  grep -qF -- "check.sh $m" "$PKG/README.md" || missingmodes="$missingmodes $m"
done <<<"$modes"
check "every check.sh mode flag is documented in the README" test -z "$missingmodes"
[ -z "$missingmodes" ] || echo "    undocumented:$missingmodes"

# requirements.md is bootstrap-only, so every reference must tolerate its absence.
check "plan-feature guards its requirements.md read with 'if present'" \
  grep -q 'requirements.md` \*\*if present\*\*' "$PKG/commands/plan-feature.md"
check "adopt-project states it never writes requirements.md" \
  grep -q 'adoption never writes one' "$PKG/commands/adopt-project.md"
# Human-implemented phases. The flag must be documented in the prose Arguments
# section, not only in argument-hint: Cursor ignores the frontmatter and appends
# arguments as text instead of substituting $1, so a frontmatter-only flag is
# invisible from .cursor/commands/. And /validate-phase must build its diff from
# the recorded base ref — work the operator already committed shows an empty
# working-tree diff, which would pass the boundary sweep, the independent review
# and the closure test having examined nothing.
check "/implement-phase documents --implemented in its Arguments section" \
  bash -c 'sed -n "/^\*\*Arguments:\*\*/,/^$/p" "$1" | grep -q -- "--implemented"' \
  _ "$PKG/commands/implement-phase.md"
check "/implement-phase --implemented writes no source" \
  grep -q 'Do not touch source' "$PKG/commands/implement-phase.md"
# A finding is fixed where it was reported unless something asks whether it is one instance
# of a property. The step-5 reviewer cannot ask — it is starved to one spec and one diff by
# design — so the burden is /implement-phase's, which holds the whole tree. Without it a
# property violated in N places costs N rounds, and the 1-2 iteration assumption silently
# stops holding. And the --implemented branch skips the implementing steps by number, so the
# range has to cover the new one or human-implemented phases start running the gates twice.
check "/implement-phase generalises a finding before fixing it" \
  bash -c 'grep -qF "Generalise before fixing" "$1" && grep -qF "enumerate every place it must hold" "$1"' \
  _ "$PKG/commands/implement-phase.md"
check "/implement-phase --implemented skips every implementing step" \
  bash -c 'last="$(grep -oE "^[0-9]+\. \*\*" "$1" | grep -oE "[0-9]+" | head -6 | tail -1)"
           grep -qE "Steps 3.$last are skipped whole" "$1"' \
  _ "$PKG/commands/implement-phase.md"
check "/validate-phase diffs against a recorded base ref, not just the working tree" \
  grep -q 'base: <ref>' "$PKG/commands/validate-phase.md"
# ...and diffs that ref against the working tree, not <ref>..HEAD. With a real base ref
# recorded while hand-written work is still uncommitted, ..HEAD shows only the committed
# half — so the closure test, the boundary sweep and the starved review would all examine
# an empty diff and all three report clean. The mirror of the failure the base ref exists
# to fix, from the other side.
check "/validate-phase's base-ref diff reaches uncommitted work" \
  bash -c 'grep -qF "$2" "$1" && ! grep -qF "$3" "$1"' \
  _ "$PKG/commands/validate-phase.md" \
  'use `git diff <ref>` and `git diff --name-only <ref>`' '`git diff <ref>..HEAD`'
check "/validate-phase defines the file set before the subagent step" \
  bash -c 'test "$(grep -n "phase.s file set" "$1" | head -1 | cut -d: -f1)" -lt \
           "$(grep -n "Dispatch ONE subagent" "$1" | cut -d: -f1)"' \
  _ "$PKG/commands/validate-phase.md"
# A phase that goes round the validation loop once has its own spec.md in its diff:
# step 5's `undecidable` route prescribes exactly that amendment. Step 6 must not then
# read that amendment as the phase escaping its scope, or the loop cannot converge — and
# notes.md and PHASES.md are in every phase's diff from round one.
check "/validate-phase's closure test exempts the files the workflow writes" \
  bash -c 'sec="$(sed -n "/Closure test/,/^## Mandatory/p" "$1")"
           for p in spec.md notes.md PHASES.md docs/index/; do
             printf "%s" "$sec" | grep -qF "$p" || exit 1
           done' \
  _ "$PKG/commands/validate-phase.md"
# ...and both CLAUDE templates state the same four paths, because step 5's reviewer gets
# CLAUDE.md, the spec and the diff — never the command. An exemption living only in
# validate-phase.md reaches the closure test and not the reviewer, which then returns those
# paths as `undecidable` on every phase forever. Verified in a consuming project the first
# time the exemption was made structural, so the duplication is load-bearing, not drift.
check "both CLAUDE templates tell the starved reviewer which files the workflow writes" \
  bash -c 'for t in CLAUDE.bootstrap.md CLAUDE.adopted.md; do
             line="$(grep -F "escaping its scope" "$1/templates/$t")" || exit 1
             for p in "phases/<id>/spec.md" "phases/<id>/notes.md" "phases/PHASES.md" "docs/index/"; do
               printf "%s" "$line" | grep -qF -- "$p" || exit 1
             done
           done' _ "$PKG"
# An inert boundaries.rules makes every file pass, so a sweep over it proves nothing. The
# gate is silent about that by design; the validation report is what must not be (P7).
check "/validate-phase distinguishes an unswept boundary sweep from a clean one" \
  grep -q 'not swept: no active deny rules' "$PKG/commands/validate-phase.md"
# The other vacuity, reported by hand five rounds running in a consuming project: the rules
# are live but the phase touched no file any layer prefix covers, which is every test-only or
# script-only phase. `clean` there is a claim about work that never happened.
check "/validate-phase catches a sweep whose file set no layer covers" \
  grep -q 'not swept: no file in the set is under a declared layer' "$PKG/commands/validate-phase.md"
# ...and says it is not a failure. The routing paragraph sends "steps 1-4" back to
# /implement-phase, and /adopt-project deliberately leaves boundaries.rules inert where the
# layering is still a human decision — so an unswept sweep read as a step-3 failure would
# bounce every phase of such a project at code that can never add a deny rule.
check "/validate-phase says an unswept boundary sweep does not fail the phase" \
  bash -c 'sed -n "/Boundary sweep/,/Corporate mode/p" "$1" | grep -q "not a failure"' \
  _ "$PKG/commands/validate-phase.md"
# The iteration-3+ escape prescribed a status flip to `pending` that no command performed,
# and /expand-phase refuses any other status — a route ending in a bounce, which is P9's bug.
# The command that detects the escape now applies it, so its Writes contract has to say so.
check "/validate-phase performs the status flip its escape prescribes" \
  bash -c 'sed -n "/^\*\*Writes:/p" "$1" | grep -q "pending"' _ "$PKG/commands/validate-phase.md"
# ...and counts rounds against the current spec, not for the phase's lifetime. The escape's
# own verdict is the reset point: without it, a phase that escapes once is permanently in
# escape territory and every later round demands re-expanding a spec written one round ago.
# A Goal that quantifies without naming its set is undecidable, not vague: the starved
# reviewer cannot compute a set the spec never states, so `undecidable` is its only verdict,
# and the finding regenerates every round as each diff closes only the instances it touched.
# The closure test already measures whether a cold reader can decide; this is that question.
check "the closure test requires a quantified claim to name its set" \
  bash -c 'sec="$(sed -n "/Closure test/,/^## Mandatory/p" "$1")"
           printf "%s" "$sec" | grep -qF "quantified claim owes its set"' \
  _ "$PKG/commands/validate-phase.md"
check "the spec template warns that a quantified Goal owes an enumeration" \
  bash -c 'sed -n "/^## Goal/,/^## Context/p" "$1" | grep -qF "quantifies over a set"' \
  _ "$PKG/templates/spec.md"
check "/validate-phase counts iterations against the current spec" \
  bash -c 'grep -qF "against the current spec" "$1" && grep -qF "escaped to /expand-phase\` verdict" "$1"' \
  _ "$PKG/commands/validate-phase.md"
# A re-expansion has the implementation sitting in the tree, and writing the spec from it is
# how a validation passes while proving nothing. notes.md existing is the signal; no new
# status value is needed to carry it.
check "/expand-phase detects a re-expansion from notes.md" \
  bash -c 'grep -qF "Is this a re-expansion" "$1" && grep -qF "from the tree" "$1"' \
  _ "$PKG/commands/expand-phase.md"
# /expand-phase turns the index into the spec's Context pointers, which is the section that
# makes the closure test pass — so it was the one command reading the index without ever
# checking it, and a stale one there fails a gate two commands downstream. All four commands
# that touch the index must check it.
check "every command that reads the index checks its freshness" \
  bash -c 'for c in plan-feature expand-phase validate-phase refresh-index; do
             grep -qF "build-index.sh --check" "$1/commands/$c.md" || exit 1
           done' _ "$PKG"
# Two verdicts, two destinations, both inside this project: a package defect arrived as
# `undecidable`, got patched into one project's spec.md prose, and the next project
# rediscovered it from zero. Attribution is stated on its own line, and never blocks.
check "/validate-phase routes a package-caused finding to /belay-feedback" \
  bash -c 'grep -q "^- upstream:" "$1" && grep -q "belay-feedback" "$1"' \
  _ "$PKG/commands/validate-phase.md"
# The manifest is untracked in a normal install and absent from one old enough to predate
# it. Without a clause for that, the grep finds nothing, every upstream cause reads as
# project-local, and the laundering this whole route exists to stop resumes silently (P7).
check "/validate-phase does not read a missing manifest as 'nothing upstream'" \
  grep -q 'manifest is absent' "$PKG/commands/validate-phase.md"
# The proactive prompt already existed; its trigger was "misfires", which a command that
# behaves exactly as documented never looks like — so it never fired on the defect class
# that produced three of the four entries in the feedback store.
check "both CLAUDE templates trigger /belay-feedback on a correct-but-wrong command" \
  bash -c 'grep -qF "documented behaviour is itself the defect" "$1" &&
           grep -qF "documented behaviour is itself the defect" "$2"' \
  _ "$PKG/templates/CLAUDE.bootstrap.md" "$PKG/templates/CLAUDE.adopted.md"
# The status that closes a feedback entry lived only in feedback-pending.sh's echo, so
# the command that writes an entry never said how one is closed. Both files must name the
# same string or the SessionStart listing and the operator drift apart.
check "belay-feedback and feedback-pending name the same closing status" \
  bash -c 'grep -qF "resolved (<commit>)" "$1" && grep -qF "resolved (<commit>)" "$2"' \
  _ "$PKG/commands/belay-feedback.md" "$PKG/scripts/feedback-pending.sh"

# CLAUDE.md's pointer table is the only thing loaded every session, so an ADR directory it
# does not name is one nobody opens — and a pointer at an empty directory is worse. The
# range it cites has to match the table it points at, or it sends people looking for a
# principle that is not there.
check "CLAUDE.md points at the package's own ADRs, and they exist" \
  bash -c 'grep -q "docs/adr/" "$1/CLAUDE.md" && ls "$1"/docs/adr/*.md >/dev/null 2>&1' _ "$PKG"
check "the principle range CLAUDE.md cites matches the README table" \
  bash -c 'hi="$(grep -oE "^\| P[0-9]+ " "$1/README.md" | grep -oE "[0-9]+" | sort -n | tail -1)"
           grep -qE "P1.?P$hi" "$1/CLAUDE.md"' _ "$PKG"
# The package ships templates/adr.md and tells its consumers to use it. An ADR here that
# drifts from that shape is the same two-files-disagree bug, one level up.
# Pass 1 of sanitizing, as a guard rather than a habit: an absolute home path in a published
# document leaks a username and usually the consuming project beside it. Generic on purpose —
# it fires on a document nobody thought to audit, which is the only kind that leaks.
check "no published document carries an absolute home path" \
  bash -c '! grep -rlE "/(Users|home)/[A-Za-z0-9._-]+/" "$1/docs" "$1/templates" >/dev/null 2>&1' \
  _ "$PKG"
check "every package ADR follows the shipped template's shape" \
  bash -c 'for f in "$1"/docs/adr/*.md; do
             for h in "- Status:" "## Context" "## Decision" "## Consequences"; do
               grep -qF -- "$h" "$f" || exit 1
             done
           done' _ "$PKG"
# Every Plan step in the spec template and its example carries its own check, so
# the repo is left working at each step boundary (a human can stop; an agent
# converges in small loops instead of batching failure to the end).
check "spec template requires a per-step check in the Plan" \
  grep -q 'check: ' "$PKG/templates/spec.md"
check "spec example demonstrates per-step checks" \
  bash -c 'test "$(sed -n "/^## Plan/,/^## Acceptance/p" "$1" | grep -c -- "— check: ")" -ge 3' \
  _ "$PKG/templates/spec.example.md"
check "spec template rejects a separate generated plan document" \
  grep -q 'never authoritative' "$PKG/templates/spec.md"
# Both CLAUDE templates ship both workflow variants; the entry commands must both
# pick one, and must both assert no template marker survives.
for c in bootstrap-project adopt-project; do
  check "/$c picks a workflow variant" grep -q 'LIGHTWEIGHT' "$PKG/commands/$c.md"
  check "/$c asserts no template marker survives" \
    grep -q "grep -c 'LIGHTWEIGHT" "$PKG/commands/$c.md"
  # Corporate mode skips the AGENTS.md -> CLAUDE.md symlink, so the company's rules
  # reach Claude Code only through the @AGENTS.md import. And the same block that
  # forbids touching .cursor/rules/* orders belay.mdc written, so it must say which
  # one wins — twice now that paragraph has drifted into contradicting itself.
  check "/$c corporate block bridges AGENTS.md into Claude Code" \
    grep -qF '@AGENTS.md' "$PKG/commands/$c.md"
  check "/$c corporate block exempts belay.mdc from the prohibition" \
    grep -q 'exception is belay' "$PKG/commands/$c.md"
done

echo ""
echo "corporate-smoke: $((CHECKS-FAILS))/$CHECKS passed"
[ "$FAILS" -eq 0 ] || { echo "corporate-smoke: FAILED ($FAILS)"; exit 1; }
