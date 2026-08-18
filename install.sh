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
# are overwritten on re-install; project-owned files (boundaries.rules,
# toolchain.json, CLAUDE.md, docs/*) are never clobbered. Hook *wiring* is
# package-owned too: belay's own entries in settings.json are replaced on every
# re-install (see rewire()), so a hook added to the package reaches projects
# that are already installed. Entries the project added itself survive.
set -euo pipefail

PKG="$(cd "$(dirname "$0")" && pwd)"
TARGET="" CURSOR=0 CORPORATE=0 GITHOOK=0
for a in "$@"; do
  case "$a" in
    --cursor) CURSOR=1 ;;
    --corporate) CORPORATE=1 ;;
    --git-hook) GITHOOK=1 ;;
    *) TARGET="$a" ;;
  esac
done
[ -n "$TARGET" ] && [ -d "$TARGET" ] || { echo "usage: install.sh <target-repo-dir> [--cursor] [--corporate] [--git-hook]" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" = "$PKG" ] && { echo "install.sh: target is the package itself" >&2; exit 1; }

tracked() { git -C "$TARGET" ls-files --error-unmatch "$1" >/dev/null 2>&1; }

if [ "$CORPORATE" -eq 1 ]; then
  git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 \
    || { echo "install.sh: --corporate requires a git repo (.git/info/exclude is the containment mechanism)" >&2; exit 1; }
  # Both mode switches are refused, not just corporate -> normal (below). Going
  # normal -> corporate would leave two state trees (docs/ and .belay/) and,
  # because a committed .claude/workflow/ is tracked and so omitted from the
  # exclude manifest, the corporate marker itself would show in git status —
  # failing the no-touch check while already having flipped the mode.
  if [ ! -f "$TARGET/.claude/workflow/corporate" ] && [ -f "$TARGET/docs/templates/spec.md" ]; then
    echo "install.sh: $TARGET already has a normal (non-corporate) belay install" >&2
    echo "  Switching modes in place is not supported: docs/ is tracked by the repo, so" >&2
    echo "  corporate mode could neither relocate nor hide it, and the install would flip" >&2
    echo "  the mode marker while failing its own no-touch check." >&2
    echo "  To move this repo to corporate mode, uninstall the normal install first" >&2
    echo "  (delete docs/, scripts/build-index.sh, .claude/{commands,hooks,workflow} and" >&2
    echo "  belay's hook entries in .claude/settings.json), commit that, then re-run" >&2
    echo "  install.sh --corporate." >&2
    exit 1
  fi
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

# --- agent-doc canonicalization (normal mode only) --------------------------
# One rule: CLAUDE.md is the real file, AGENTS.md is a symlink to it or absent.
# The installer never rewrites either — the merge needs an entry command — but a
# CLAUDE.md symlink has to stop the install *before* anything is written, or
# step 9 writes through it and silently clobbers the target. Corporate mode is
# exempt: it never writes CLAUDE.md at all.
if [ "$CORPORATE" -eq 0 ] && [ -L "$TARGET/CLAUDE.md" ]; then
  echo "install.sh: $TARGET/CLAUDE.md is a symlink -> $(readlink "$TARGET/CLAUDE.md")" >&2
  echo "  belay writes CLAUDE.md as a real file; installing would let /adopt-project write" >&2
  echo "  through the symlink and overwrite its target. Resolve it first: replace CLAUDE.md" >&2
  echo "  with the real content (rm CLAUDE.md && cp <target> CLAUDE.md), then re-run." >&2
  exit 1
fi

echo "Installing workflow package into $TARGET"

if [ "$CORPORATE" -eq 0 ] && [ -f "$TARGET/AGENTS.md" ] && [ ! -L "$TARGET/AGENTS.md" ]; then
  echo "  note: AGENTS.md is a real file — left untouched here; /adopt-project or"
  echo "        /bootstrap-project will fold it into CLAUDE.md and leave it a symlink"
fi

# --- package-owned files (safe to overwrite) --------------------------------
mkdir -p "$TARGET/.claude/commands" "$TARGET/.claude/hooks/lib" "$TARGET/$SCRIPTS" \
         "$TARGET/$DOCS/templates" "$TARGET/$DOCS/product" "$TARGET/$DOCS/adr" \
         "$TARGET/$DOCS/phases" "$TARGET/$DOCS/index" "$TARGET/$DOCS/security" \
         "$TARGET/.claude/workflow"

# Every path this install writes, one per line, relative to the target. Written
# to .claude/workflow/installed at the end and compared against the previous
# run's copy to find files the package no longer ships (see the reaping step) —
# in normal mode as well as corporate, where a dropped command would otherwise
# stay a live slash command forever.
INSTALLED=""
record() { INSTALLED="$INSTALLED$1
"; }

copy_into() { # copy_into <target-relative destdir> <src files...>
  local dest="$1" f b out; shift
  for f in "$@"; do
    b="$(basename "$f")"; out="$TARGET/$dest/$b"
    if [ "$CORPORATE" -eq 1 ] && tracked "$dest/$b"; then
      echo "  SKIP $dest/$b — tracked by the target repo; corporate mode never overwrites tracked files"
      continue
    fi
    cp -f "$f" "$out"
    record "$dest/$b"
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

MANIFEST="$TARGET/.claude/workflow/installed"
PREV_INSTALLED=""
[ -f "$MANIFEST" ] && PREV_INSTALLED="$(grep -v '^[[:space:]]*#' "$MANIFEST" | grep -v '^$' || true)"

copy_into .claude/commands  "$PKG"/commands/*.md
copy_into .claude/hooks     "$PKG"/hooks/*.sh
copy_into .claude/hooks/lib "$PKG"/hooks/lib/*.sh
copy_into "$SCRIPTS"        "$PKG"/scripts/build-index.sh
copy_into "$DOCS/templates" "$PKG"/templates/*

# Version stamp: /belay-feedback cites it so feedback entries name the exact
# package commit whose behavior they observed.
ver="$(git -C "$PKG" rev-parse --short HEAD 2>/dev/null || echo unknown)"
printf 'belay %s (installed %s)\n' "$ver" "$(date +%F)" >"$TARGET/.claude/workflow/belay-version"
# The corporate marker is stamped at the very END of this script, once every
# check has passed: it flips the target into a mode whose plain re-install is
# refused, so a failed install must not leave it behind.

# Install registry, same $HOME channel as /belay-feedback: outside the repo, so
# no git footprint and corporate-safe. scripts/installs-stale.sh (package repo
# only) reads it to report installs left behind by a newer package commit.
REG="$HOME/.claude-belay/installs"
if mkdir -p "$(dirname "$REG")" 2>/dev/null; then
  grep -qxF "$TARGET" "$REG" 2>/dev/null || printf '%s\n' "$TARGET" >>"$REG"
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

# Ownership test for hook entries: any command pointing into .claude/hooks/ is
# belay's — that whole directory is package-owned (see the README). Matching on
# the directory instead of a list of script names also cleans up the wiring of
# a hook that was deleted upstream, whose file no longer exists to name.
rewire() { # rewire <target json> <package wiring json> <label> — needs jq
  local dst="$1" add="$2" label="$3" tmp
  tmp="$(mktemp)"
  # Drop every belay-owned entry from every event key, then append the
  # package's current wiring. Generic over event names, so a hook on a new
  # event (SessionStart, ...) propagates too. Groups left empty by the filter
  # are dropped, so wiring removed upstream disappears downstream.
  jq -s '
    .[1] as $pkg | .[0]
    | .hooks = (.hooks // {})
    | .hooks |= with_entries(
        .value |= ( map(.hooks = ((.hooks // []) | map(select(
                        (.command // "") | contains(".claude/hooks/") | not))))
                  | map(select((.hooks | length) > 0)) ))
    | reduce ($pkg.hooks | keys[]) as $k (.; .hooks[$k] = ((.hooks[$k] // []) + $pkg.hooks[$k]))
    | .hooks |= with_entries(select((.value | length) > 0))
    | if $pkg.version then .version = (.version // $pkg.version) else . end
  ' "$dst" "$add" >"$tmp" || { rm -f "$tmp"; echo "  WARNING: could not rewire $label (invalid JSON?)"; return 0; }
  if cmp -s "$tmp" "$dst"; then
    rm -f "$tmp"; echo "  $label already wired — up to date"
  else
    mv "$tmp" "$dst"; echo "  re-wired belay hooks in $label (the project's own entries are preserved)"
  fi
}

unwired() { # unwired <settings file> <package wiring file> — names package hooks absent from it
  local out="" b f
  for f in "$PKG"/hooks/*.sh; do
    b="$(basename "$f")"
    grep -qF "$b" "$2" || continue
    grep -qF "$b" "$1" || out="$out $b"
  done
  printf '%s' "$out"
}

SETREL="${SET#"$TARGET"/}"
SET_SKIPPED=0
# SET_CREATED distinguishes "belay made this file" from "belay merged into the
# operator's file" — the uninstall manifest must not tell anyone to delete the
# latter. Only meaningful on a first install; re-installs carry the earlier
# verdict forward through the manifest (see wiring_owner below).
SET_CREATED=0
if [ "$CORPORATE" -eq 1 ] && [ -f "$SET" ] && tracked "$SETREL"; then
  SET_SKIPPED=1
  echo "  WARNING: $SETREL is tracked by the target repo — left untouched; merge by hand:"
  echo "           append the hook entries from $PKG/settings/settings.json"
elif [ ! -f "$SET" ]; then
  cp "$PKG/settings/settings.json" "$SET"
  SET_CREATED=1
  echo "  created $SETREL (hook wiring)"
elif command -v jq >/dev/null 2>&1; then
  rewire "$SET" "$PKG/settings/settings.json" "$SETREL"
else
  SET_SKIPPED=1
  miss="$(unwired "$SET" "$PKG/settings/settings.json")"
  echo "  WARNING: $SETREL exists and jq is not installed — belay's hook wiring was NOT updated."
  [ -z "$miss" ] || echo "           these package hooks are not wired in $SETREL:$miss"
  echo "           install jq and re-run, or copy the hook entries from $PKG/settings/settings.json by hand"
fi

# --- Cursor wiring (--cursor) -----------------------------------------------
if [ "$CURSOR" -eq 1 ]; then
  mkdir -p "$TARGET/.cursor/commands"
  copy_into .cursor/commands "$PKG"/commands/*.md
  CHJ="$TARGET/.cursor/hooks.json"
  CHJ_CREATED=0
  if [ "$CORPORATE" -eq 1 ] && [ -f "$CHJ" ] && tracked ".cursor/hooks.json"; then
    # Cursor has no local-settings variant; skipping is the only clean option.
    echo "  WARNING: .cursor/hooks.json is tracked by the target repo — left untouched;"
    echo "           Cursor hooks won't fire until you merge $PKG/settings/hooks.cursor.json by hand"
  elif [ ! -f "$CHJ" ]; then
    cp "$PKG/settings/hooks.cursor.json" "$CHJ"
    CHJ_CREATED=1
    echo "  created .cursor/hooks.json (cursor-adapter wiring)"
  elif command -v jq >/dev/null 2>&1; then
    rewire "$CHJ" "$PKG/settings/hooks.cursor.json" ".cursor/hooks.json"
  else
    echo "  WARNING: $CHJ exists and jq is not installed — cursor wiring was NOT updated;"
    echo "           copy the entries from $PKG/settings/hooks.cursor.json by hand"
  fi
  # Cursor reads AGENTS.md; keep CLAUDE.md as the single source of truth.
  # Corporate: no symlink — a new root file is repo-visible noise; the Cursor
  # pointer file is .cursor/rules/belay.mdc, written by the entry commands.
  if [ "$CORPORATE" -eq 0 ] && [ ! -e "$TARGET/AGENTS.md" ] && [ ! -L "$TARGET/AGENTS.md" ]; then
    ln -s CLAUDE.md "$TARGET/AGENTS.md"
    echo "  created AGENTS.md -> CLAUDE.md symlink (dangling until an entry command writes CLAUDE.md)"
  fi
fi

# --- git pre-commit hook (--git-hook) ---------------------------------------
# Opt-in, because it is the only part of the install that changes what happens
# when a PERSON commits — everything else gates the agent. Off by default so a
# re-install never silently starts blocking the operator's own commits.
#
# Never clobbers: plenty of repos already ship a pre-commit hook, and it may
# already scan for secrets. An existing hook is left exactly as it is and the
# one line to append is printed instead — merging into someone else's shell
# script is not something an installer should guess at.
if [ "$GITHOOK" -eq 1 ]; then
  if ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    echo "  WARNING: --git-hook needs a git repo — skipped"
  else
    # --git-path honours core.hooksPath, so husky/lefthook setups land in the
    # directory git will actually run, not a .git/hooks/ nobody reads.
    GH="$(git -C "$TARGET" rev-parse --git-path hooks/pre-commit)"
    case "$GH" in /*) ;; *) GH="$TARGET/$GH" ;; esac
    GHREL="${GH#"$TARGET"/}"
    if [ -e "$GH" ] && grep -qF 'pre-commit-security.sh' "$GH" 2>/dev/null; then
      echo "  $GHREL already runs belay's security gate — left alone"
    elif [ -e "$GH" ]; then
      echo "  NOTE: $GHREL already exists and does not call belay — left untouched."
      echo "        To gate human commits too, append this line to it:"
      echo "          echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit\"}}' | \"\$(git rev-parse --show-toplevel)\"/.claude/hooks/pre-commit-security.sh"
    elif tracked "$GHREL"; then
      # Only reachable via core.hooksPath pointing inside the working tree.
      echo "  WARNING: $GHREL is tracked by the target repo — skipped (belay never writes tracked files)"
    else
      mkdir -p "$(dirname "$GH")"
      cp "$PKG/settings/pre-commit.githook" "$GH"
      chmod +x "$GH"
      echo "  created $GHREL (human commits now hit the same secret gate as the agent)"
    fi
  fi
fi

# --- corporate: hide everything installed from git --------------------------
if [ "$CORPORATE" -eq 1 ]; then
  EXC="$(git -C "$TARGET" rev-parse --git-path info/exclude)"
  case "$EXC" in /*) ;; *) EXC="$TARGET/$EXC" ;; esac   # relative on normal repos, absolute in worktrees
  mkdir -p "$(dirname "$EXC")"
  [ -f "$EXC" ] || : >"$EXC"
  # The previous block is the record of what belay installed last time, so read
  # it before deleting it: paths it lists that this run does not are orphans
  # (see the reaping step below), and its "# merged:" comments carry the
  # created-vs-merged verdict forward across re-installs.
  OLD_BLOCK="$(sed -n '/^# >>> claude-belay/,/^# <<< claude-belay/p' "$EXC")"
  OLD_PATHS="$(printf '%s\n' "$OLD_BLOCK" | grep '^/' || true)"
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
  emit_wiring() { # emit_wiring <manifest path> <created-by-belay-this-run 0|1>
    # A wiring file belay merged into is the operator's, and the manifest header
    # says "delete these paths" — so mark it. The verdict is decided once (was
    # the file there before belay?) and then read back out of the old block, or
    # a re-install would see belay's own file already present and call it theirs.
    local owner=user
    if [ "$2" -eq 1 ]; then owner=belay
    elif printf '%s\n' "$OLD_BLOCK" | grep -qxF "# merged: $1"; then owner=user
    elif printf '%s\n' "$OLD_PATHS" | grep -qxF "$1"; then owner=belay
    fi
    [ "$owner" = belay ] || echo "# merged: $1"
    emit "$1"
  }
  # Cursor directories are only claimed if belay wired them, now or before.
  CURSOR_SEEN="$CURSOR"
  printf '%s\n' "$OLD_PATHS" | grep -q '^/\.cursor/' && CURSOR_SEEN=1
  NEW_BLOCK="$(
    echo "# >>> claude-belay corporate mode >>>"
    echo "# --- containment: shared directories belay writes into ---"
    echo "# Directory-wide on purpose. Listing belay's files one by one is not enough:"
    echo "# .claude/ holds no tracked files, so a SINGLE unlisted file under it makes"
    echo "# git collapse the lot to '?? .claude/' and expose the whole tree. Safe for"
    echo "# the company's own files — exclude rules never apply to TRACKED paths, so"
    echo "# their versioned .claude/settings.json still reports its changes normally."
    echo "# These two are NOT belay's to delete: see the manifest below for that."
    echo "/.claude/"
    [ "$CURSOR_SEEN" -eq 1 ] && echo "/.cursor/"
    echo "#"
    echo "# --- uninstall manifest: delete EXACTLY the paths below, then this block ---"
    echo "# Never delete the two directories above: they also hold company files. A"
    echo "# path preceded by '# merged:' existed before belay and was only merged"
    echo "# into — leave those in place."
    emit "/.belay/"
    emit "/CLAUDE.local.md"
    emit "/.claude/workflow/"
    emit_wiring "/.claude/settings.local.json" "$SET_CREATED"
    # Straight from what copy_into actually wrote, so this list cannot drift from
    # the install. Only the shared dirs need naming — everything under .belay/ is
    # already covered by the /.belay/ line above.
    printf '%s' "$INSTALLED" | grep -E '^\.(claude|cursor)/(commands|hooks)/' | sort \
      | while IFS= read -r p; do emit "/$p"; done
    if [ "$CURSOR" -eq 1 ]; then
      emit_wiring "/.cursor/hooks.json" "${CHJ_CREATED:-0}"
      emit "/.cursor/rules/belay.mdc"
    else
      # A re-install that forgot --cursor leaves the Cursor files on disk (the
      # reaping step below deliberately spares them), so they stay in the
      # manifest: still belay's, still there to delete at uninstall.
      printf '%s\n' "$OLD_PATHS" | grep '^/\.cursor/' | while IFS= read -r p; do
        [ -e "$TARGET$p" ] && emit "$p"
      done
    fi
    echo "# <<< claude-belay <<<"
  )"
  printf '%s\n' "$NEW_BLOCK" >>"$EXC"
  echo "  wrote exclude block to .git/info/exclude (nothing installed will appear in git status)"

fi

# --- record what was installed, and reap what the package no longer ships ----
# Both modes. A dropped hook is harmless (rewire() removes its wiring, so nothing
# runs it), but a dropped COMMAND stays a live slash command forever, and in
# corporate mode any orphan also falls out of the uninstall manifest that is
# supposed to account for every installed path.
if [ -z "$PREV_INSTALLED" ] && [ "$CORPORATE" -eq 1 ] && [ -n "${OLD_PATHS:-}" ]; then
  # Installed by a version that predates this manifest: the corporate exclude
  # block was the only record, so fall back to it for this one run.
  PREV_INSTALLED="$(printf '%s\n' "$OLD_PATHS" | sed 's#^/##')"
fi
while IFS= read -r p; do
  [ -n "$p" ] || continue
  printf '%s' "$INSTALLED" | grep -qxF "$p" && continue
  # Only ever reap paths copy_into manages. The corporate fallback list is the old
  # exclude block, which also names files belay writes by other means —
  # settings.local.json (wiring, possibly merged into the operator's own),
  # CLAUDE.local.md and .cursor/rules/belay.mdc (written by an entry command).
  # Deleting any of those would be destructive, not tidy.
  case "$p" in
    .claude/commands/*|.claude/hooks/*|.cursor/commands/*|"$SCRIPTS"/*|"$DOCS"/templates/*) ;;
    *) continue ;;
  esac
  # Spare .cursor/ unless this run wired Cursor: a re-install that merely forgot
  # --cursor must not delete the command copies or the pointer doc an entry
  # command wrote.
  case "$p" in .cursor/*) [ "$CURSOR" -eq 1 ] || continue ;; esac
  # Regular files only (never a directory entry from the fallback), and never
  # anything the repo tracks — a company that committed belay's copy owns it now.
  [ -f "$TARGET/$p" ] || continue
  tracked "$p" && continue
  rm -f "$TARGET/$p"
  echo "  removed $p — no longer shipped by the package"
done <<<"$PREV_INSTALLED"

{
  echo "# Files installed by belay, one per line, relative to this repo root."
  echo "# Written by install.sh; used to delete files the package stops shipping,"
  echo "# and as the uninstall list (delete these, then .claude/workflow/)."
  echo "# Not project state — do not hand-edit."
  printf '%s' "$INSTALLED" | sort
} >"$MANIFEST"

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
# Only assert the hook belay itself wrote: a pre-existing one was deliberately
# left alone above, and that is a successful install, not a missing file.
if [ "$GITHOOK" -eq 1 ] && [ -n "${GH:-}" ] && [ -x "$GH" ]; then
  bash -n "$GH"
fi
bash -n "$TARGET"/.claude/hooks/*.sh "$TARGET"/.claude/hooks/lib/*.sh "$TARGET/$SCRIPTS/build-index.sh"
if command -v jq >/dev/null 2>&1 && [ -f "$SET" ]; then jq . "$SET" >/dev/null; fi
# The rewire is silent on success, so assert it took: every package hook the
# wiring references must be present in the target settings (P7 — loud gaps).
if [ "$SET_SKIPPED" -eq 0 ] && [ -f "$SET" ]; then
  miss="$(unwired "$SET" "$PKG/settings/settings.json")"
  [ -z "$miss" ] || { echo "  MISSING after install: hooks not wired in $SETREL:$miss" >&2; fail=1; }
fi
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

if [ "$CORPORATE" -eq 1 ]; then
  # Marker the entry commands check: write CLAUDE.local.md, never CLAUDE.md.
  # Last write in the script, and deliberately after the no-touch check — it is
  # covered by the /.claude/workflow/ exclude entry, and a failed install above
  # must leave the target in whatever mode it was already in.
  : >"$TARGET/.claude/workflow/corporate"
fi

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
