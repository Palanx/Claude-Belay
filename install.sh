#!/usr/bin/env bash
# Installs the workflow package into a target repo (new or existing — P8: the
# install is identical; only the entry command you run afterwards differs).
#
#   ./install.sh /path/to/target-repo [--cursor] [--corporate]
#
# --cursor additionally wires the same commands and hooks for Cursor (CLI/IDE):
# commands copied to .cursor/commands/, hooks routed through cursor-adapter.sh
# via .cursor/hooks.json, and AGENTS.md symlinked to CLAUDE.md.
#
# --corporate installs without touching anything git tracks: docs/ + scripts/
# state relocates under .belay/, hook wiring goes to .claude/settings.local.json,
# entry commands write CLAUDE.local.md instead of CLAUDE.md, and every installed
# path is hidden from git via a marked block in .git/info/exclude — which
# doubles as the uninstall manifest.
#
# Idempotent: package-owned files (commands, hooks, templates, index script)
# are overwritten on re-install; project-owned files (settings.json content,
# boundaries.rules, toolchain.json, CLAUDE.md, docs/*) are never clobbered.
set -euo pipefail

PKG="$(cd "$(dirname "$0")" && pwd)"
TARGET="" CURSOR=0 CORPORATE=0
for a in "$@"; do
  case "$a" in
    --cursor) CURSOR=1 ;;
    --corporate) CORPORATE=1 ;;
    *) TARGET="$a" ;;
  esac
done
[ -n "$TARGET" ] && [ -d "$TARGET" ] || { echo "usage: install.sh <target-repo-dir> [--cursor] [--corporate]" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" = "$PKG" ] && { echo "install.sh: target is the package itself" >&2; exit 1; }

tracked() { git -C "$TARGET" ls-files --error-unmatch "$1" >/dev/null 2>&1; }

if [ "$CORPORATE" -eq 1 ]; then
  git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 \
    || { echo "install.sh: --corporate requires a git repo (.git/info/exclude is the containment mechanism)" >&2; exit 1; }
  DOCS=".belay/docs" SCRIPTS=".belay/scripts"
  SET="$TARGET/.claude/settings.local.json"
  STATUS_BEFORE="$(git -C "$TARGET" status --porcelain)"
elif [ -f "$TARGET/.claude/workflow/corporate" ]; then
  # A plain re-run would write docs/ into the repo and merge tracked settings.
  echo "install.sh: $TARGET was installed in corporate mode — re-run with --corporate" >&2
  exit 1
else
  DOCS="docs" SCRIPTS="scripts"
  SET="$TARGET/.claude/settings.json"
fi

echo "Installing workflow package into $TARGET"

# --- package-owned files (safe to overwrite) --------------------------------
mkdir -p "$TARGET/.claude/commands" "$TARGET/.claude/hooks/lib" "$TARGET/$SCRIPTS" \
         "$TARGET/$DOCS/templates" "$TARGET/$DOCS/product" "$TARGET/$DOCS/adr" \
         "$TARGET/$DOCS/phases" "$TARGET/$DOCS/index" "$TARGET/$DOCS/security" \
         "$TARGET/.claude/workflow"

copy_into() { # copy_into <target-relative destdir> <src files...>
  local dest="$1" f b out; shift
  for f in "$@"; do
    b="$(basename "$f")"; out="$TARGET/$dest/$b"
    if [ "$CORPORATE" -eq 1 ] && tracked "$dest/$b"; then
      echo "  SKIP $dest/$b — tracked by the target repo; corporate mode never overwrites tracked files"
      continue
    fi
    cp -f "$f" "$out"
    if [ "$CORPORATE" -eq 1 ]; then
      # Rewrite canonical paths in the copy (package sources stay canonical).
      # Maintenance point: any new docs/<subdir> referenced by commands or
      # templates must be added to the first alternation.
      sed -E -i.belaybak \
        -e 's#docs/(product|adr|phases|index|security|templates|constraints\.md|adoption-report\.md)#.belay/docs/\1#g' \
        -e 's#scripts/build-index\.sh#.belay/scripts/build-index.sh#g' "$out"
      rm -f "$out.belaybak"
    fi
    case "$b" in *.sh) chmod +x "$out" ;; esac
  done
}

copy_into .claude/commands  "$PKG"/commands/*.md
copy_into .claude/hooks     "$PKG"/hooks/*.sh
copy_into .claude/hooks/lib "$PKG"/hooks/lib/*.sh
copy_into "$SCRIPTS"        "$PKG"/scripts/build-index.sh
copy_into "$DOCS/templates" "$PKG"/templates/*

# Version stamp: /belay-feedback cites it so feedback entries name the exact
# package commit whose behavior they observed.
ver="$(git -C "$PKG" rev-parse --short HEAD 2>/dev/null || echo unknown)"
printf 'belay %s (installed %s)\n' "$ver" "$(date +%F)" >"$TARGET/.claude/workflow/belay-version"
if [ "$CORPORATE" -eq 1 ]; then
  # Marker the entry commands check: write CLAUDE.local.md, never CLAUDE.md.
  : >"$TARGET/.claude/workflow/corporate"
fi

# --- project-owned files (create only if absent) ----------------------------
if [ ! -f "$TARGET/.claude/workflow/boundaries.rules" ]; then
  # Ships with the example layers commented out: the hook is inert until the
  # entry-point command writes real layers for THIS project.
  sed 's/^layer /# layer /; s/^deny /# deny /' "$PKG/templates/boundaries.rules" \
    >"$TARGET/.claude/workflow/boundaries.rules"
  echo "  created .claude/workflow/boundaries.rules (inert until /bootstrap-project or /adopt-project fills it)"
fi

# --- settings wiring --------------------------------------------------------
# Corporate mode targets .claude/settings.local.json (Claude Code merges it in,
# conventionally untracked) so a tracked settings.json is never modified.
SETREL="${SET#"$TARGET"/}"
if [ "$CORPORATE" -eq 1 ] && [ -f "$SET" ] && tracked "$SETREL"; then
  echo "  WARNING: $SETREL is tracked by the target repo — left untouched; merge by hand:"
  echo "           append the PostToolUse/PreToolUse entries from $PKG/settings/settings.json"
elif [ ! -f "$SET" ]; then
  cp "$PKG/settings/settings.json" "$SET"
  echo "  created $SETREL (hook wiring)"
elif grep -q "post-edit-gate.sh" "$SET"; then
  echo "  $SETREL already wired — left untouched"
elif command -v jq >/dev/null 2>&1; then
  tmp="$(mktemp)"
  jq -s '
    .[1].hooks as $add | .[0]
    | .hooks = (.hooks // {})
    | .hooks.PostToolUse = ((.hooks.PostToolUse // []) + $add.PostToolUse)
    | .hooks.PreToolUse  = ((.hooks.PreToolUse  // []) + $add.PreToolUse)
  ' "$SET" "$PKG/settings/settings.json" >"$tmp" && mv "$tmp" "$SET"
  echo "  merged hook wiring into existing $SETREL (review the diff)"
else
  echo "  WARNING: $SET exists and jq is not installed — merge by hand:"
  echo "           append the PostToolUse/PreToolUse entries from $PKG/settings/settings.json"
fi

# --- Cursor wiring (--cursor) -----------------------------------------------
if [ "$CURSOR" -eq 1 ]; then
  mkdir -p "$TARGET/.cursor/commands"
  copy_into .cursor/commands "$PKG"/commands/*.md
  CHJ="$TARGET/.cursor/hooks.json"
  if [ "$CORPORATE" -eq 1 ] && [ -f "$CHJ" ] && tracked ".cursor/hooks.json"; then
    # Cursor has no local-settings variant; skipping is the only clean option.
    echo "  WARNING: .cursor/hooks.json is tracked by the target repo — left untouched;"
    echo "           Cursor hooks won't fire until you merge $PKG/settings/hooks.cursor.json by hand"
  elif [ ! -f "$CHJ" ]; then
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
  # Corporate: no symlink — a new root file is repo-visible noise; the Cursor
  # pointer file is .cursor/rules/belay.mdc, written by the entry commands.
  if [ "$CORPORATE" -eq 0 ] && [ ! -e "$TARGET/AGENTS.md" ] && [ ! -L "$TARGET/AGENTS.md" ]; then
    ln -s CLAUDE.md "$TARGET/AGENTS.md"
    echo "  created AGENTS.md -> CLAUDE.md symlink (dangling until an entry command writes CLAUDE.md)"
  fi
fi

# --- corporate: hide everything installed from git --------------------------
if [ "$CORPORATE" -eq 1 ]; then
  EXC="$(git -C "$TARGET" rev-parse --git-path info/exclude)"
  case "$EXC" in /*) ;; *) EXC="$TARGET/$EXC" ;; esac   # relative on normal repos, absolute in worktrees
  mkdir -p "$(dirname "$EXC")"
  [ -f "$EXC" ] || : >"$EXC"
  sed -i.belaybak '/^# >>> claude-belay/,/^# <<< claude-belay/d' "$EXC"
  rm -f "$EXC.belaybak"
  emit() { # a tracked path is company-owned (install skipped it): excluding it
           # would hide company files from their status, and the uninstall
           # manifest must never tell anyone to delete a company file.
    if tracked "${1#/}"; then
      echo "  NOTE: ${1#/} is tracked by the target repo — omitted from the exclude manifest" >&2
    else
      echo "$1"
    fi
  }
  {
    echo "# >>> claude-belay corporate mode — uninstall manifest: delete these paths, then this block >>>"
    emit "/.belay/"
    emit "/CLAUDE.local.md"
    emit "/.claude/workflow/"
    emit "/.claude/settings.local.json"
    for f in "$PKG"/commands/*.md;  do emit "/.claude/commands/$(basename "$f")"; done
    for f in "$PKG"/hooks/*.sh;     do emit "/.claude/hooks/$(basename "$f")"; done
    for f in "$PKG"/hooks/lib/*.sh; do emit "/.claude/hooks/lib/$(basename "$f")"; done
    if [ "$CURSOR" -eq 1 ]; then
      for f in "$PKG"/commands/*.md; do emit "/.cursor/commands/$(basename "$f")"; done
      emit "/.cursor/hooks.json"
      emit "/.cursor/rules/belay.mdc"
    fi
    echo "# <<< claude-belay <<<"
  } >>"$EXC"
  echo "  wrote exclude block to .git/info/exclude (nothing installed will appear in git status)"
fi

# --- verify -----------------------------------------------------------------
fail=0
for f in .claude/hooks/post-edit-gate.sh .claude/hooks/boundary-check.sh \
         .claude/hooks/pre-commit-security.sh .claude/hooks/cursor-adapter.sh \
         .claude/hooks/lib/common.sh \
         .claude/hooks/lib/detect-toolchain.sh "$SCRIPTS/build-index.sh" \
         .claude/commands/plan-feature.md .claude/commands/belay-feedback.md \
         .claude/workflow/belay-version "$DOCS/templates/spec.md"; do
  [ -e "$TARGET/$f" ] || { echo "  MISSING after install: $f" >&2; fail=1; }
done
if [ "$CURSOR" -eq 1 ]; then
  for f in .cursor/commands/plan-feature.md .cursor/hooks.json; do
    [ -e "$TARGET/$f" ] || { echo "  MISSING after install: $f" >&2; fail=1; }
  done
  if command -v jq >/dev/null 2>&1; then jq . "$TARGET/.cursor/hooks.json" >/dev/null; fi
fi
bash -n "$TARGET"/.claude/hooks/*.sh "$TARGET"/.claude/hooks/lib/*.sh "$TARGET/$SCRIPTS/build-index.sh"
if command -v jq >/dev/null 2>&1 && [ -f "$SET" ]; then jq . "$SET" >/dev/null; fi
if [ "$CORPORATE" -eq 1 ]; then
  grep -q 'claude-belay' "$EXC" || { echo "  MISSING after install: exclude block in $EXC" >&2; fail=1; }
  # No-touch guarantee: nothing NEW may appear in git status. Lines may
  # disappear — a pre-existing untracked file (e.g. settings.local.json) is now
  # hidden by the exclude block, which is containment working, not a change.
  NEW_ENTRIES="$(comm -13 <(printf '%s\n' "$STATUS_BEFORE" | sort) \
                          <(git -C "$TARGET" status --porcelain | sort))"
  if [ -n "$NEW_ENTRIES" ]; then
    echo "  FAIL: install changed git status — corporate no-touch guarantee violated:" >&2
    printf '%s\n' "$NEW_ENTRIES" >&2
    fail=1
  fi
fi
[ $fail -eq 0 ] || exit 1

echo ""
echo "Installed. Next, inside a Claude Code session in $TARGET:"
echo "  new project:       /bootstrap-project <requirements>"
echo "  existing codebase: /adopt-project"
if [ "$CURSOR" -eq 1 ]; then
  echo "Cursor: the same commands work from cursor-agent (/bootstrap-project etc.)"
fi
if [ "$CORPORATE" -eq 1 ]; then
  echo "Corporate mode: state lives under .belay/, the pointer doc will be CLAUDE.local.md,"
  echo "and nothing installed appears in git status (see .git/info/exclude for the manifest)."
fi
echo "Smoke test: see 'Verifying the install' in the package README."
