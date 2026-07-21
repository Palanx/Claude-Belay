#!/usr/bin/env bash
# Installs the workflow package into a target repo (new or existing — P8: the
# install is identical; only the entry command you run afterwards differs).
#
#   ./install.sh /path/to/target-repo [--cursor]
#
# --cursor additionally wires the same commands and hooks for Cursor (CLI/IDE):
# commands copied to .cursor/commands/, hooks routed through cursor-adapter.sh
# via .cursor/hooks.json, and AGENTS.md symlinked to CLAUDE.md.
#
# Idempotent: package-owned files (commands, hooks, templates, index script)
# are overwritten on re-install; project-owned files (settings.json content,
# boundaries.rules, toolchain.json, CLAUDE.md, docs/*) are never clobbered.
set -euo pipefail

PKG="$(cd "$(dirname "$0")" && pwd)"
TARGET="" CURSOR=0
for a in "$@"; do
  case "$a" in
    --cursor) CURSOR=1 ;;
    *) TARGET="$a" ;;
  esac
done
[ -n "$TARGET" ] && [ -d "$TARGET" ] || { echo "usage: install.sh <target-repo-dir> [--cursor]" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" = "$PKG" ] && { echo "install.sh: target is the package itself" >&2; exit 1; }

echo "Installing workflow package into $TARGET"

# --- package-owned files (safe to overwrite) --------------------------------
mkdir -p "$TARGET/.claude/commands" "$TARGET/.claude/hooks/lib" "$TARGET/scripts" \
         "$TARGET/docs/templates" "$TARGET/docs/product" "$TARGET/docs/adr" \
         "$TARGET/docs/phases" "$TARGET/docs/index" "$TARGET/docs/security" \
         "$TARGET/.claude/workflow"

cp -f "$PKG"/commands/*.md "$TARGET/.claude/commands/"
cp -f "$PKG"/hooks/*.sh "$TARGET/.claude/hooks/"
cp -f "$PKG"/hooks/lib/*.sh "$TARGET/.claude/hooks/lib/"
cp -f "$PKG"/scripts/build-index.sh "$TARGET/scripts/"
cp -f "$PKG"/templates/* "$TARGET/docs/templates/"
chmod +x "$TARGET"/.claude/hooks/*.sh "$TARGET"/.claude/hooks/lib/*.sh "$TARGET/scripts/build-index.sh"

# Version stamp: /belay-feedback cites it so feedback entries name the exact
# package commit whose behavior they observed.
ver="$(git -C "$PKG" rev-parse --short HEAD 2>/dev/null || echo unknown)"
printf 'belay %s (installed %s)\n' "$ver" "$(date +%F)" >"$TARGET/.claude/workflow/belay-version"

# --- project-owned files (create only if absent) ----------------------------
if [ ! -f "$TARGET/.claude/workflow/boundaries.rules" ]; then
  # Ships with the example layers commented out: the hook is inert until the
  # entry-point command writes real layers for THIS project.
  sed 's/^layer /# layer /; s/^deny /# deny /' "$PKG/templates/boundaries.rules" \
    >"$TARGET/.claude/workflow/boundaries.rules"
  echo "  created .claude/workflow/boundaries.rules (inert until /bootstrap-project or /adopt-project fills it)"
fi

# --- settings wiring --------------------------------------------------------
SET="$TARGET/.claude/settings.json"
if [ ! -f "$SET" ]; then
  cp "$PKG/settings/settings.json" "$SET"
  echo "  created .claude/settings.json (hook wiring)"
elif grep -q "post-edit-gate.sh" "$SET"; then
  echo "  .claude/settings.json already wired — left untouched"
elif command -v jq >/dev/null 2>&1; then
  tmp="$(mktemp)"
  jq -s '
    .[1].hooks as $add | .[0]
    | .hooks = (.hooks // {})
    | .hooks.PostToolUse = ((.hooks.PostToolUse // []) + $add.PostToolUse)
    | .hooks.PreToolUse  = ((.hooks.PreToolUse  // []) + $add.PreToolUse)
  ' "$SET" "$PKG/settings/settings.json" >"$tmp" && mv "$tmp" "$SET"
  echo "  merged hook wiring into existing .claude/settings.json (review the diff)"
else
  echo "  WARNING: $SET exists and jq is not installed — merge by hand:"
  echo "           append the PostToolUse/PreToolUse entries from $PKG/settings/settings.json"
fi

# --- Cursor wiring (--cursor) -----------------------------------------------
if [ "$CURSOR" -eq 1 ]; then
  mkdir -p "$TARGET/.cursor/commands"
  cp -f "$PKG"/commands/*.md "$TARGET/.cursor/commands/"
  CHJ="$TARGET/.cursor/hooks.json"
  if [ ! -f "$CHJ" ]; then
    cp "$PKG/settings/hooks.cursor.json" "$CHJ"
    echo "  created .cursor/hooks.json (cursor-adapter wiring)"
  elif grep -q "cursor-adapter.sh" "$CHJ"; then
    echo "  .cursor/hooks.json already wired — left untouched"
  elif command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp)"
    jq -s '
      .[1].hooks as $add | .[0]
      | .version = (.version // 1)
      | .hooks = (.hooks // {})
      | .hooks.afterFileEdit        = ((.hooks.afterFileEdit        // []) + $add.afterFileEdit)
      | .hooks.beforeShellExecution = ((.hooks.beforeShellExecution // []) + $add.beforeShellExecution)
    ' "$CHJ" "$PKG/settings/hooks.cursor.json" >"$tmp" && mv "$tmp" "$CHJ"
    echo "  merged cursor-adapter wiring into existing .cursor/hooks.json (review the diff)"
  else
    echo "  WARNING: $CHJ exists and jq is not installed — merge by hand:"
    echo "           append the entries from $PKG/settings/hooks.cursor.json"
  fi
  # Cursor reads AGENTS.md; keep CLAUDE.md as the single source of truth.
  if [ ! -e "$TARGET/AGENTS.md" ] && [ ! -L "$TARGET/AGENTS.md" ]; then
    ln -s CLAUDE.md "$TARGET/AGENTS.md"
    echo "  created AGENTS.md -> CLAUDE.md symlink (dangling until an entry command writes CLAUDE.md)"
  fi
fi

# --- verify -----------------------------------------------------------------
fail=0
for f in .claude/hooks/post-edit-gate.sh .claude/hooks/boundary-check.sh \
         .claude/hooks/pre-commit-security.sh .claude/hooks/cursor-adapter.sh \
         .claude/hooks/lib/common.sh \
         .claude/hooks/lib/detect-toolchain.sh scripts/build-index.sh \
         .claude/commands/plan-feature.md .claude/commands/belay-feedback.md \
         .claude/workflow/belay-version docs/templates/spec.md; do
  [ -e "$TARGET/$f" ] || { echo "  MISSING after install: $f" >&2; fail=1; }
done
if [ "$CURSOR" -eq 1 ]; then
  for f in .cursor/commands/plan-feature.md .cursor/hooks.json; do
    [ -e "$TARGET/$f" ] || { echo "  MISSING after install: $f" >&2; fail=1; }
  done
  if command -v jq >/dev/null 2>&1; then jq . "$TARGET/.cursor/hooks.json" >/dev/null; fi
fi
bash -n "$TARGET"/.claude/hooks/*.sh "$TARGET"/.claude/hooks/lib/*.sh "$TARGET/scripts/build-index.sh"
if command -v jq >/dev/null 2>&1; then jq . "$SET" >/dev/null; fi
[ $fail -eq 0 ] || exit 1

echo ""
echo "Installed. Next, inside a Claude Code session in $TARGET:"
echo "  new project:       /bootstrap-project <requirements>"
echo "  existing codebase: /adopt-project"
if [ "$CURSOR" -eq 1 ]; then
  echo "Cursor: the same commands work from cursor-agent (/bootstrap-project etc.)"
fi
echo "Smoke test: see 'Verifying the install' in the package README."
