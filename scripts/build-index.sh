#!/usr/bin/env bash
# Repo index generator (package section 3.4).
#
# Writes docs/index/: one markdown file per module + _overview.md with the
# module table, dependency edges, and entry points. Generated only — the whole
# directory is owned by this script; never hand-edit it.
#
#   scripts/build-index.sh          rebuild the index
#   scripts/build-index.sh --check  exit 1 (with a message) if the index is
#                                   stale relative to the working tree or HEAD;
#                                   used by /refresh-index and /validate-phase
#
# Format rationale: markdown-per-module, not one JSON blob, because the index
# is read by sessions (one section at a time, P1), reviewed by humans, and
# diffed in git. Traded away: machine-precise symbol data. Symbols come from
# universal-ctags when installed, else a grep heuristic over declaration
# keywords — good enough to locate files, which is the whole job.
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$ROOT"
OUTDIR="docs/index"
STAMP_RE='<!-- workflow-index-stamp: ([0-9a-f]+|no-commits) -->'

git rev-parse --git-dir >/dev/null 2>&1 || { echo "build-index: not a git repository" >&2; exit 1; }
HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo no-commits)"

SRC_EXT='py|js|jsx|ts|tsx|mjs|cjs|go|rs|rb|java|kt|kts|c|h|cc|cpp|hpp|cs|php|swift|scala|ex|exs|lua|sh'

# --- staleness check mode ---------------------------------------------------
if [ "${1:-}" = "--check" ]; then
  # Corporate collision check: warn if upstream now tracks a path the local
  # exclude manifest hides — the next pull would die with "untracked working
  # tree files would be overwritten". Warn-only; staleness governs the exit code.
  EXC="$(git rev-parse --git-path info/exclude)"
  if grep -q '^# >>> claude-belay' "$EXC" 2>/dev/null; then
    REF="HEAD"; git rev-parse -q --verify '@{u}' >/dev/null 2>&1 && REF='@{u}'
    block="$(sed -n '/^# >>> claude-belay/,/^# <<< claude-belay/p' "$EXC")"
    # Read the uninstall-manifest section only. The containment section above it
    # excludes whole directories (/.claude/, /.cursor/), which legitimately hold
    # the company's own tracked files — a pull only collides where belay actually
    # wrote a file. Blocks from before that split have no marker: use them whole.
    manifest="$(printf '%s\n' "$block" | sed -n '/^# --- uninstall manifest/,$p')"
    [ -n "$manifest" ] || manifest="$block"
    # Manifest paths are plain (letters, digits, ., /, -): escaping dots is enough.
    pat="$(printf '%s\n' "$manifest" \
      | grep '^/' | sed -e 's#^/##' -e 's/\./\\./g' \
      | awk '{ if ($0 ~ /\/$/) print "^"$0; else print "^"$0"$" }')"
    hits="$([ -n "$pat" ] && git ls-tree -r --name-only "$REF" 2>/dev/null | grep -E "$pat" || true)"
    if [ -n "$hits" ]; then
      {
        echo "WARNING: upstream ($REF) tracks paths the corporate exclude manifest hides:"
        printf '%s\n' "$hits" | sed 's/^/  /'
        echo "The next pull will refuse to overwrite your local untracked copies."
        echo "Move the local belay state aside (or delete those paths and their lines in"
        echo ".git/info/exclude) before pulling."
      } >&2
    fi
  fi

  OV="$OUTDIR/_overview.md"
  [ -f "$OV" ] || { echo "index STALE: $OV missing — run scripts/build-index.sh"; exit 1; }
  stamp="$(grep -oE "$STAMP_RE" "$OV" | grep -oE '[0-9a-f]+|no-commits' | tail -1 || true)"
  [ -n "$stamp" ] || { echo "index STALE: no stamp in $OV — run scripts/build-index.sh"; exit 1; }

  # The index is generated from the files on disk, so the working tree — not just HEAD —
  # is what it drifts from. HEAD does not move during a phase, which made every check
  # below a no-op for the whole window /validate-phase step 4 runs in.
  # A path gone from disk is asked of the index, not of mtime: a deletion stays in
  # `git status` until it is committed, so testing it by mtime would report STALE forever,
  # including right after the rebuild that fixed it. Asking whether the index still names
  # the file answers the real question and clears itself. Renames arrive as `old -> new`;
  # awk emits both sides, so the vanished path and the new one are each judged on merit.
  # belay-debt: an edit landing in the same clock tick as the build AND leaving the line
  # count unchanged still reads as fresh. Upgrade path: a second stamp line hashing the
  # file list and contents, at the cost of reading every source file on a check whose
  # whole point is being cheap.
  drift=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -e "$f" ]; then
      if grep -rqF -- "$f" "$OUTDIR" 2>/dev/null; then drift="$drift$f (gone, still indexed)"$'\n'; fi
    elif [ "$f" -nt "$OV" ]; then
      drift="$drift$f"$'\n'
    else
      # mtime cannot see an edit that landed in the same clock tick as the build, so fall
      # back to what the index already records about this file: its line count. Only files
      # git already calls dirty are read, so the check stays cheap.
      was="$(grep -hF -- "### $f (" "$OUTDIR"/*.md 2>/dev/null | sed -E 's/.*\(([0-9]+) lines\)$/\1/' | head -1 || true)"
      now="$(wc -l <"$f" | tr -d ' ')"
      if [ "$was" != "$now" ]; then drift="$drift$f (indexed at ${was:-no} lines, now $now)"$'\n'; fi
    fi
  done <<<"$(git status --porcelain -uall 2>/dev/null | sed 's/^...//' \
             | awk '{ n = split($0, a, " -> "); for (i = 1; i <= n; i++) print a[i] }' \
             | grep -E "\.($SRC_EXT)\$" | grep -vE '^(docs|\.claude)/' || true)"
  if [ -n "$drift" ]; then
    echo "index STALE: source files on disk changed after it was built — run scripts/build-index.sh"
    printf '%s' "$drift" | sed 's/^/  /'
    exit 1
  fi

  [ "$stamp" = "$HEAD" ] && { echo "index fresh ($HEAD)"; exit 0; }
  if git diff --name-only "$stamp" HEAD 2>/dev/null | grep -qE "\.($SRC_EXT)\$"; then
    echo "index STALE: built at $stamp, HEAD is $HEAD and source files changed — run scripts/build-index.sh"
    exit 1
  fi
  echo "index fresh enough ($stamp -> $HEAD touched no source files)"
  exit 0
fi

# --- collect source files (tracked + untracked-but-not-ignored) -------------
mkdir -p "$OUTDIR"
rm -f "$OUTDIR"/*.md   # directory is fully generated; stale module files must not linger

FILES="$(git ls-files -co --exclude-standard | grep -E "\.($SRC_EXT)\$" | grep -vE '^(docs|\.claude)/' || true)"
if [ -z "$FILES" ]; then
  # A source-free repo still gets a stamped overview. Without it --check reports
  # STALE forever and the rebuild it prescribes writes nothing, so /plan-feature
  # and /validate-phase can never clear their freshness step on a fresh project.
  {
    echo "# Repo index"
    echo "<!-- generated by scripts/build-index.sh — do not edit -->"
    echo "<!-- workflow-index-stamp: $HEAD -->"
    echo ""
    echo "Built: $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit \`$HEAD\`."
    echo ""
    echo "_No source files yet — nothing to index. Re-run once code exists._"
  } >"$OUTDIR/_overview.md"
  echo "index written: $OUTDIR (no source files yet, stamp $HEAD)"
  exit 0
fi

# module key per file: <root>/<child> under container dirs (src, lib, ...), else <root>
map_module() {
  awk -F/ '{
    if (NF == 1) { print "(root)\t" $0 }
    else if (NF >= 3 && ($1=="src" || $1=="lib" || $1=="app" || $1=="apps" || $1=="packages" || $1=="internal" || $1=="cmd" || $1=="pkg")) { print $1"/"$2 "\t" $0 }
    else { print $1 "\t" $0 }
  }'
}
MAPPED="$(printf '%s\n' "$FILES" | map_module)"
MODULES="$(printf '%s\n' "$MAPPED" | cut -f1 | sort -u)"

HAVE_CTAGS=0
command -v ctags >/dev/null 2>&1 && ctags --version 2>/dev/null | grep -qi universal && HAVE_CTAGS=1

symbols_of() { # symbols_of <file> — markdown bullet list of public-ish symbols
  local f="$1"
  if [ "$HAVE_CTAGS" = 1 ]; then
    { ctags -x --sort=no "$f" 2>/dev/null | awk '{printf "- %s `%s` (L%s)\n", $2, $1, $3}' | head -40; } || true
  else
    { grep -nE '^[[:space:]]*(export[[:space:]]|export default|module\.exports|exports\.[a-zA-Z]|pub[[:space:]]|public[[:space:]]|def[[:space:]]|async def[[:space:]]|class[[:space:]]|function[[:space:]]|func[[:space:]]|fn[[:space:]]|interface[[:space:]]|struct[[:space:]]|trait[[:space:]]|module[[:space:]]|type[[:space:]][A-Z])' "$f" 2>/dev/null \
      | head -40 \
      | sed -E 's/^([0-9]+):[[:space:]]*(.{0,100}).*$/- L\1: `\2`/'; } || true
  fi
}

IMPORT_RE='^[[:space:]]*(import|export|from|require|include|use|using|#include)[[:space:](]|require\(|import\('

# imports_of <module> — all import-ish lines in the module, deduped
imports_of() {
  local m="$1" f
  while IFS=$'\t' read -r mod f; do
    [ "$mod" = "$m" ] || continue
    grep -hE "$IMPORT_RE" "$f" 2>/dev/null || true
  done <<<"$MAPPED" | sort -u
}

# --- per-module pages + edge collection -------------------------------------
EDGES=""
# Paths with spaces are normal in engine projects (Unity ships "Assets/TextMesh
# Pro/", which detect-toolchain.sh exempts by name), so every module/file walk
# here reads line-by-line instead of word-splitting. A herestring is not a
# subshell, so EDGES still accumulates across the loop.
while IFS= read -r m; do
  [ -n "$m" ] || continue
  slug="$(printf '%s' "$m" | tr '/() ' '-' | sed 's/^-*//;s/-*$//')"
  [ -n "$slug" ] || slug="root"
  page="$OUTDIR/$slug.md"

  mfiles="$(printf '%s\n' "$MAPPED" | awk -F'\t' -v m="$m" '$1==m {print $2}')"
  nfiles="$(printf '%s\n' "$mfiles" | wc -l | tr -d ' ')"
  nlines=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    nlines=$((nlines + $(wc -l <"$f")))
  done <<<"$mfiles"

  {
    echo "# Module: $m"
    echo "<!-- generated by scripts/build-index.sh — do not edit; regenerate with /refresh-index -->"
    echo ""
    echo "Files: $nfiles · Lines: ${nlines:-?}"
    echo ""
    echo "## Files and public symbols"
    while read -r f; do
      [ -n "$f" ] || continue
      echo ""
      echo "### $f ($(wc -l <"$f" | tr -d ' ') lines)"
      syms="$(symbols_of "$f")"
      [ -n "$syms" ] && echo "$syms" || echo "_no declarations detected_"
    done <<<"$mfiles"
  } >"$page"

  # belay-debt: substring match, not import resolution — a module whose name appears inside
  # an unrelated string gets a false edge, and an aliased import gets none. Performance is
  # no longer the ceiling: the scan is still O(modules²) but spawns nothing, and measures
  # 7.4s at 150 modules where it used to extrapolate to minutes. Upgrade path is the
  # same resolver boundary-check.sh names, and it belongs in scripts/check.sh, not here.
  mimports="$(imports_of "$m")"
  deps=""
  while IFS= read -r other; do
    [ -n "$other" ] || continue
    [ "$other" = "$m" ] && continue
    [ "$other" = "(root)" ] && continue
    obase="${other##*/}"   # not basename: that is a process, and this loop runs modules² times
    # Substring test in the shell, not a pipe to grep. This loop runs modules² times, so
    # what cost anything was the process spawns, never the comparison: with the pipe and
    # the basename call, 60 modules took 23.3s and 150 extrapolated to ~145s; in-shell they
    # measure 3.2s and 7.4s. Same two branches, the module key or its delimited basename,
    # except both are now literal instead of interpolated into an ERE.
    if [[ $mimports == *"$other"* ]] || [[ $mimports == *[/\"\'[:space:].]"$obase"[/\"\']* ]]; then
      deps="$deps$other
"
      EDGES="$EDGES$m -> $other
"
    fi
  done <<<"$MODULES"
  {
    echo ""
    echo "## Depends on"
    if [ -n "$deps" ]; then printf '%s' "$deps" | sed 's/^/- /'; else echo "_none detected_"; fi
  } >>"$page"
done <<<"$MODULES"

# --- overview ---------------------------------------------------------------
ENTRY_POINTS="$(printf '%s\n' "$FILES" | grep -E '(^|/)(main|index|app|server|cli|__main__|entry)\.[a-z]+$|(^|/)cmd/[^/]+/main\.go$' || true)"

{
  echo "# Repo index"
  echo "<!-- generated by scripts/build-index.sh — do not edit -->"
  echo "<!-- workflow-index-stamp: $HEAD -->"
  echo ""
  echo "Built: $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit \`$HEAD\`."
  echo "Load only the module section you need — one file per module below."
  echo ""
  echo "## Modules"
  echo ""
  echo "| Module | Files | Index page |"
  echo "|--------|-------|------------|"
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    slug="$(printf '%s' "$m" | tr '/() ' '-' | sed 's/^-*//;s/-*$//')"
    [ -n "$slug" ] || slug="root"
    n="$(printf '%s\n' "$MAPPED" | awk -F'\t' -v m="$m" '$1==m' | wc -l | tr -d ' ')"
    echo "| $m | $n | [$slug.md]($slug.md) |"
  done <<<"$MODULES"
  echo ""
  echo "## Dependency edges (heuristic, import-based)"
  echo ""
  if [ -n "$EDGES" ]; then
    printf '%s' "$EDGES" | sort -u | sed 's/^/- /'
  else
    echo "_none detected_"
  fi
  echo ""
  echo "## Entry points"
  echo ""
  if [ -n "$ENTRY_POINTS" ]; then
    printf '%s\n' "$ENTRY_POINTS" | sed 's/^/- /'
  else
    echo "_none matched the entry-point name heuristic_"
  fi
} >"$OUTDIR/_overview.md"

echo "index written: $OUTDIR ($(printf '%s\n' "$MODULES" | wc -l | tr -d ' ') modules, stamp $HEAD)"
