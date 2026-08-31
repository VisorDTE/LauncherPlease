#!/bin/bash
# Record one launch for the rolling Most used window.
# Usage: record.sh <app-id> [window-days]

set -euo pipefail

id="${1:-}"
window="${2:-14}"
[[ -n $id ]] || exit 0

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/launcherplease"
file="$state_dir/usage.json"
mkdir -p "$state_dir"

today=$(date +%F)
raw="{}"
[[ -f $file ]] && raw=$(cat "$file" 2>/dev/null || echo "{}")

keep='[]'
for ((i = 0; i < window; i++)); do
  keep=$(jq -nc --argjson k "$keep" --arg d "$(date -d "$today -$i days" +%F)" '$k + [$d]')
done

tmp=$(mktemp "$state_dir/usage.XXXXXX")
jq -nc --argjson raw "$raw" --arg id "$id" --arg today "$today" --argjson keep "$keep" '
  ($raw.days // {}) as $days
  | ($keep | map({key: ., value: true}) | from_entries) as $ok
  | ($days | to_entries | map(select($ok[.key])) | from_entries) as $kept
  | ($kept[$today] // {}) as $bucket
  | { days: ($kept + { ($today): ($bucket + { ($id): (($bucket[$id] // 0) + 1) }) }) }
' >"$tmp" && mv "$tmp" "$file"
