#!/usr/bin/env bash
# velka collect - digest all sessions into a cache (mtime-keyed; only re-parses changed).
# maxdepth 2 = real sessions only; EXCLUDES <session>/subagents/*.jsonl (they double-count).
# Usage: collect.sh [projects-root]   # default ~/.claude/projects
set -euo pipefail
ROOT="${1:-$HOME/.claude/projects}"
DIGDIR="${VELKA_DIGDIR:-$HOME/.claude/velka/digests}"
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIGDIR"

new=0; cached=0; failed=0
while IFS= read -r f; do
  sid="$(basename "$f" .jsonl)"
  out="$DIGDIR/$sid.json"
  # Also newer than digest.sh: a digester fix must re-digest old sessions, not serve stale records
  if [ -f "$out" ] && [ "$out" -nt "$f" ] && [ "$out" -nt "$here/digest.sh" ]; then cached=$((cached+1)); continue; fi
  if bash "$here/digest.sh" "$f" >"$out.tmp" 2>/dev/null && [ -s "$out.tmp" ]; then
    mv "$out.tmp" "$out"; new=$((new+1))
  else
    rm -f "$out.tmp"; failed=$((failed+1))
  fi
done < <(find "$ROOT" -maxdepth 2 -name '*.jsonl' -type f)

echo "velka: $new digested, $cached cached, $failed failed → $DIGDIR"
