#!/bin/bash
# Persist the chosen layout to ~/.config/omarchy/launcherplease.json.
# Usage: set-layout.sh <compact|roomy|list>

set -euo pipefail

mode="${1:-compact}"
case "$mode" in
  compact|roomy|list) ;;
  *) exit 0 ;;
esac

file="${HOME:-}/.config/omarchy/launcherplease.json"
mkdir -p "$(dirname "$file")"

raw="{}"
[[ -f $file ]] && raw=$(cat "$file" 2>/dev/null || echo "{}")

tmp=$(mktemp "${file}.XXXXXX")
jq -nc --argjson raw "$raw" --arg mode "$mode" \
  '($raw | if type == "object" then . else {} end) + { layout: $mode }' \
  >"$tmp" && mv "$tmp" "$file"
