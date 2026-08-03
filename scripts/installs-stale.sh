#!/usr/bin/env bash
# Package-repo-only SessionStart hook (not shipped by install.sh): compares the
# version stamp of every registered install against this repo's HEAD and lists
# the ones left behind, so a session opened here knows which consumers to
# re-install. Silent when everything is current.
#
# The check runs here, never in the consuming project: the package may not exist
# on that machine, a mid-session update would mutate the gates a running session
# is being judged by (P3), and corporate installs must stay no-touch.
set -euo pipefail

PKG="$(cd "$(dirname "$0")/.." && pwd)"
REG="$HOME/.claude-belay/installs"
[ -f "$REG" ] || exit 0
ver="$(git -C "$PKG" rev-parse --short HEAD 2>/dev/null)" || exit 0

report=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  stamp="$p/.claude/workflow/belay-version"
  # Moved, deleted or uninstalled: skipped silently, the registry is not pruned.
  [ -f "$stamp" ] || continue
  installed="$(cut -d' ' -f2 <"$stamp")"
  [ "$installed" = "$ver" ] || report+="  $p (belay $installed -> $ver)"$'\n'
done <"$REG"

[ -n "$report" ] || exit 0
echo "belay: installs behind $ver:"
printf '%s' "$report"
echo "Re-run ./install.sh <path> in each, repeating the flags it was installed with (--cursor / --corporate)."
