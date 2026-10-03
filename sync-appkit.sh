#!/bin/zsh
# Copies App Kit's Swift into the App Kit tab, or checks the copies still match.
#
#   ./sync-appkit.sh           copy both files from ~/developer/app-kit
#   ./sync-appkit.sh --check   OK / DRIFT per file; exit 1 on any drift
#
# Exits 2 with BROKEN when app-kit's sources cannot be read or the spike's
# boundary marker is not there exactly once. An unreachable source is not "in
# sync", so it must never come out as OK. ~/bin/invariants.sh check 41 runs
# --check daily.
#
# The components file is the spike up to MARKER. The marker, not a line number,
# is the boundary: the spike's own window and launcher follow it, and this app
# has its own (AppKitShowcase.swift).
set -euo pipefail

here="${0:A:h}"
appkit="${APPKIT_DIR:-$HOME/developer/app-kit}"
tokens_src="$appkit/swift/AppKit.swift"
spike_src="$appkit/build/source/music-components-spike.swift"
tokens_dst="$here/claude spinner/AppKitTokens.swift"
comps_dst="$here/claude spinner/AppKitMusicComponents.swift"
MARKER='// MARK: - Spike window'

mode="${1:-copy}"
case "$mode" in
  copy|--check) ;;
  *) print -ru2 -- "usage: sync-appkit.sh [--check]"; exit 2 ;;
esac

for f in "$tokens_src" "$spike_src"; do
  if [ ! -r "$f" ] || [ ! -s "$f" ]; then
    print -r -- "BROKEN	$f is missing, unreadable or empty"
    exit 2
  fi
done
n=$(grep -cxF -- "$MARKER" "$spike_src" || true)
if [ "$n" != 1 ]; then
  print -r -- "BROKEN	'$MARKER' matches $n lines in $spike_src, expected 1"
  exit 2
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
awk -v m="$MARKER" '$0 == m { exit } { print }' "$spike_src" > "$tmp"
if [ ! -s "$tmp" ]; then
  print -r -- "BROKEN	nothing precedes the marker in $spike_src"
  exit 2
fi

if [ "$mode" = copy ]; then
  cp "$tokens_src" "$tokens_dst"
  cp "$tmp" "$comps_dst"
fi

drift=0
cmp -s "$tokens_src" "$tokens_dst" && print -r -- "OK	AppKitTokens.swift" \
  || { print -r -- "DRIFT	AppKitTokens.swift"; drift=1; }
cmp -s "$tmp" "$comps_dst" && print -r -- "OK	AppKitMusicComponents.swift" \
  || { print -r -- "DRIFT	AppKitMusicComponents.swift"; drift=1; }
exit $drift
