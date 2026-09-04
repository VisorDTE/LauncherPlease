#!/bin/bash
# Chord capture for LauncherPlease.
#
# Temporarily rebinds each app's shortcut to the overlay's launch IPC while the
# overlay is open, and restores the original bindings on close. Apps arrive as
# a JSON array (bounded) as a positional argument, one object per app:
#   { "chord": "...", "id": "...", "label": "...", "command": "..." }
#
# Usage: chords.sh capture|restore <apps_json>
#
# Each hyprctl invocation is built from argv (never a shell string built by
# interpolation), Lua literals are escaped at every grammar boundary, and a
# failed mutation rolls the already-applied changes back. Exit status is
# non-zero on any failure so the caller can log and roll back.

set -euo pipefail

mode="${1:-}"
apps_json="${2:-}"
[[ $mode == "capture" || $mode == "restore" ]] || { echo "usage: chords.sh capture|restore <apps_json>" >&2; exit 2; }

# Bounded input: truncate the app list to MAX_BYTES.
MAX_BYTES=262144
apps_json="${apps_json:0:$MAX_BYTES}"

# Escape a string for inclusion inside a Lua double-quoted literal: backslash,
# double quote, newline, CR, and other control bytes become \ddd or \n/\r.
lua_escape() {
  local s="$1" i c o=""
  local byte
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    if [[ $c == '\\' ]]; then
      o+='\\\\'
    elif [[ $c == '"' ]]; then
      o+='\"'
    elif [[ $c == $'\n' ]]; then
      o+='\n'
    elif [[ $c == $'\r' ]]; then
      o+='\r'
    elif [[ $c =~ [[:cntrl:]] ]]; then
      byte=$(printf '%d' "'$c")
      printf -v esc '\\%03d' "$byte"
      o+="$esc"
    else
      o+="$c"
    fi
  done
  printf '%s' "$o"
}

# Build the Lua source for one bind/unbind and run it through hyprctl eval
# (argv, no shell interpolation).
do_eval() {
  hyprctl eval "$1"
}

declare -a done=()

rollback() {
  local chord
  for chord in "${done[@]}"; do
    do_eval "hl.unbind(\"$chord\")" >/dev/null 2>&1 || true
  done
}

if [[ $mode == "capture" ]]; then
  # Bind each app chord to the overlay launch IPC.
  while IFS= read -r app; do
    [[ -z $app ]] && continue
    chord="$(jq -r '.chord // empty' <<<"$app")"
    id="$(jq -r '.id // empty' <<<"$app")"
    label="$(jq -r '.label // empty' <<<"$app")"
    [[ -n $chord && -n $id ]] || continue

    lchord="$(lua_escape "$chord")"
    llabel="$(lua_escape "$label")"

    do_eval "hl.unbind(\"$lchord\")" >/dev/null 2>&1 || true
    if ! do_eval "hl.bind(\"$lchord\", hl.dsp.exec_cmd(\"omarchy-shell launcherplease launch $id\"), { description = \"$llabel\" })" >/dev/null 2>&1; then
      rollback
      exit 1
    fi
    done+=("$lchord")
  done < <(jq -r '.[] | select(.chord != null and .chord != "") | @json' <<<"$apps_json" 2>/dev/null || true)

  # Esc is rebound while open, unbound on close (same pattern as WindowsPlease).
  do_eval 'hl.unbind("ESCAPE")' >/dev/null 2>&1 || true
  if ! do_eval 'hl.bind("ESCAPE", hl.dsp.exec_cmd("omarchy-shell launcherplease close"), { description = "LauncherPlease close" })' >/dev/null 2>&1; then
    rollback
    exit 1
  fi
  done+=("ESCAPE")
else
  # Restore: unbind the temporary chord bindings.
  while IFS= read -r app; do
    [[ -z $app ]] && continue
    chord="$(jq -r '.chord // empty' <<<"$app")"
    [[ -n $chord ]] || continue
    lchord="$(lua_escape "$chord")"
    do_eval "hl.unbind(\"$lchord\")" >/dev/null 2>&1 || true
  done < <(jq -r '.[] | select(.chord != null and .chord != "") | @json' <<<"$apps_json" 2>/dev/null || true)

  # Restore the original bindings for each app command.
  while IFS= read -r app; do
    [[ -z $app ]] && continue
    chord="$(jq -r '.chord // empty' <<<"$app")"
    command="$(jq -r '.command // empty' <<<"$app")"
    label="$(jq -r '.label // empty' <<<"$app")"
    [[ -n $chord && -n $command ]] || continue
    lchord="$(lua_escape "$chord")"
    lcommand="$(lua_escape "$command")"
    llabel="$(lua_escape "$label")"
    if ! do_eval "hl.bind(\"$lchord\", hl.dsp.exec_cmd(\"$lcommand\"), { description = \"$llabel\" })" >/dev/null 2>&1; then
      rollback
      exit 1
    fi
  done < <(jq -r '.[] | select(.chord != null and .chord != "") | @json' <<<"$apps_json" 2>/dev/null || true)

  do_eval 'hl.unbind("ESCAPE")' >/dev/null 2>&1 || true
fi

exit 0
