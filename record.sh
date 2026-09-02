#!/bin/bash
# Record one launch for the rolling Most used window.
# Usage: record.sh <app-id> [window-days]
#
# State is stored as JSON in a locked, 0600 file inside a 0700 directory.
# Reads/writes are bounded and atomic; hostile inputs fail closed.

set -euo pipefail

id="${1:-}"
window_raw="${2:-14}"

# App ids are the sanitized lowercase slug emitted by list.sh.
[[ $id =~ ^[a-z0-9_.-]{1,128}$ ]] || exit 0

# Clamp the rolling window to a sane range.
window=14
if [[ $window_raw =~ ^[0-9]+$ ]]; then
  window=$((window_raw))
  [[ $window -lt 1 ]] && window=1
  [[ $window -gt 365 ]] && window=365
fi

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/launcherplease"
file="$state_dir/usage.json"
lock="$state_dir/usage.lock"

umask 077
mkdir -p -m 700 "$state_dir"

# Serialize concurrent writers; bounded wait.
exec 9>"$lock"
flock -w 2 9

today=$(date +%F)

# Bounded, regular-file-only read. Fail closed on anything unexpected.
raw="{}"
if [[ -e $file ]]; then
  [[ -f $file && ! -L $file ]] || { raw="{}"; }
fi
if [[ -f $file && ! -L $file ]]; then
  size=$(wc -c <"$file" 2>/dev/null || echo 0)
  if [[ $size -gt 1048576 ]]; then
    raw="{}"
  else
    raw=$(head -c 1048576 "$file" 2>/dev/null || echo "{}")
  fi
fi

# Keep only the days inside the rolling window.
keep='[]'
for ((i = 0; i < window; i++)); do
  keep=$(jq -nc --argjson k "$keep" --arg d "$(date -d "$today -$i days" +%F)" '$k + [$d]')
done

tmp=$(mktemp "$state_dir/usage.XXXXXX")
jq -nc --argjson raw "$raw" --arg id "$id" --arg today "$today" --argjson keep "$keep" '
  (($raw | if type == "object" then . else {} end).days // {}) as $days
  | ($keep | map({key: ., value: true}) | from_entries) as $ok
  | ($days | to_entries | map(select($ok[.key])) | from_entries) as $kept
  | ($kept[$today] // {}) as $bucket
  | { days: ($kept + { ($today): ($bucket + { ($id): (($bucket[$id] // 0) + 1) }) }) }
' >"$tmp"
chmod 600 "$tmp"
mv "$tmp" "$file"

# Release the lock.
flock -u 9
