#!/bin/bash
# Persist the chosen layout to ~/.config/omarchy/launcherplease.json.
# Usage: set-layout.sh <compact|roomy|list>
#
# Config is stored in a locked, 0600 file; reads/writes are bounded and atomic.

set -euo pipefail

mode="${1:-compact}"
case "$mode" in
  compact|roomy|list) ;;
  *) exit 0 ;;
esac

file="${HOME:-}/.config/omarchy/launcherplease.json"
dir="$(dirname "$file")"

umask 077
mkdir -p -m 700 "$dir"
lock="$dir/.launcherplease.json.lock"
exec 9>"$lock"
flock -w 2 9

# Bounded, regular-file-only read. Fail closed on unexpected state.
raw="{}"
if [[ -e $file ]]; then
  if [[ -f $file && ! -L $file ]]; then
    size=$(wc -c <"$file" 2>/dev/null || echo 0)
    if [[ $size -le 65536 ]]; then
      raw=$(head -c 65536 "$file" 2>/dev/null || echo "{}")
    fi
  fi
fi

tmp=$(mktemp "${file}.XXXXXX")
jq -nc --argjson raw "$raw" --arg mode "$mode" \
  '($raw | if type == "object" then . else {} end) + { layout: $mode }' \
  >"$tmp"
chmod 600 "$tmp"
mv "$tmp" "$file"

flock -u 9
