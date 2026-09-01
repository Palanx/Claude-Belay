#!/usr/bin/env bash
# Package-repo-only SessionStart hook (not shipped by install.sh): lists open
# feedback entries written by /belay-feedback in consuming projects, so a
# session opened here starts knowing what to fix. Silent when nothing is open.
set -euo pipefail

DIR="$HOME/.claude-belay/feedback"
[ -d "$DIR" ] || exit 0

shopt -s nullglob
files=("$DIR"/*.md)
[ ${#files[@]} -gt 0 ] || exit 0

open=0
report=""
for f in "${files[@]}"; do
  entry=""
  while IFS= read -r line; do
    case "$line" in
      "## "*) entry="$line" ;;
      "status: open"*) open=$((open + 1)); report+="  ${entry#\#\# }"$'\n'"    -> $f"$'\n' ;;
    esac
  done <"$f"
done

# belay-debt: the "re-run install.sh" line below rides on the open-entry listing, so it
# stops printing exactly when the last entry is resolved and it becomes actionable.
# Harmless today — installs-stale.sh reports the same consumers on every SessionStart,
# keyed on the version stamp rather than on feedback state. Upgrade path: name each
# entry's repo here as it closes, so the two hooks say which fix is missing where instead
# of leaving the operator to join them by hand.
[ "$open" -gt 0 ] || exit 0
echo "belay feedback: $open open entries from consuming projects:"
printf '%s' "$report"
echo "Read the file(s) above for verbatim repro data. After fixing one, change its 'status: open' to 'status: resolved (<commit>)' and re-run install.sh in the consumers."
