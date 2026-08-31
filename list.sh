#!/bin/bash

# LauncherPlease data layer.
#
# Emits the JSON array of every application that has a Hyprland shortcut:
#   [ { "id","label","chord","kind","category","command","icon","glyph","iconFont" } ]
#
# Source of truth is the o.bind(...) calls that launch an app in Omarchy's
# default bindings plus the user's ~/.config/hypr/bindings.lua. Anything that
# does not launch an app (window management, shell IPC, hyprctl, menus) is
# skipped, so the overlay only ever shows the apps you can actually launch.

set -euo pipefail

home="${HOME:-}"
omarchy="${OMARCHY_PATH:-/usr/share/omarchy}"
user_bindings="$home/.config/hypr/bindings.lua"

# ---------------------------------------------------------------- category
declare -A ICON_BY_NAME=()   # upper-case app Name        -> Icon
declare -A ICON_BY_URL=()    # webapp url in Exec         -> Icon
declare -A ICON_BY_EXEC=()   # first word of Exec         -> Icon
declare -A CAT_BY_NAME=()    # upper-case app Name        -> freedesktop Categories
declare -A CAT_BY_URL=()     # webapp url in Exec         -> freedesktop Categories
declare -A CAT_BY_EXEC=()    # first word of Exec         -> freedesktop Categories

# Category overrides for Omarchy launchers whose binding label does not match a
# desktop entry name (e.g. "Terminal" launches Foot). Values are friendly group
# labels.
declare -A CURATED_CAT=(
  ["Terminal"]="System"
  ["Browser"]="Internet"
  ["Browser (private)"]="Internet"
  ["Editor"]="Development"
  ["File manager"]="System"
  ["File manager (cwd)"]="System"
  ["Music"]="Multimedia"
  ["Signal"]="Internet"
  ["Agent"]="Development"
)

# Labels that launch an *action* inside an app (compose a new message, compose a
# post, ...) rather than the app itself. These are intentionally hidden from the
# launcher grid.
declare -A ACTION_LABELS=(
  ["New email"]=1
  ["X Post"]=1
)

# Curated icons for well-known Omarchy apps that have no desktop entry or whose
# desktop entry name does not match the binding label. Values are themed icon
# names (resolved through the icon theme) or omarchy-font glyphs.
declare -A CURATED_ICON=(
  ["Terminal"]="foot"
  ["Browser"]="chromium"
  ["Browser (private)"]="chromium"
  ["Editor"]="nvim"
  ["File manager"]="org.gnome.Nautilus"
  ["File manager (cwd)"]="org.gnome.Nautilus"
  ["Email"]="hey"
  ["Calendar"]="hey"
  ["Activity"]="btop"
  ["Music TUI"]="cliamp"
  ["Tmux"]="terminal"
)
declare -A CURATED_GLYPH_OMARCHY=(
  ["Grok"]=$'\ue904'
)

# Maps themed icon names to concrete files on disk (svg preferred, then the
# largest png). Built once per run so per-app resolution is a dictionary hit;
# mirrors how AppLibrary refreshes its icon index.
declare -A ICON_INDEX=()

build_icon_index() {
  # Index every icon theme's apps/ directory with shell globbing instead of
  # find: themes live at <dir>/<theme>/<size>/apps, so the tree is shallow and
  # cheap to enumerate. svg wins over png/xpm; first hit per name is kept.
  local ext dir theme size appsdir f base name
  local -a adirs=()
  local -a icon_dirs=("$home/.icons" "$home/.local/share/icons" /usr/local/share/icons /usr/share/icons)
  shopt -s nullglob
  for dir in "${icon_dirs[@]}"; do
    [[ -d $dir ]] || continue
    for theme in "$dir"/*/; do
      theme="${theme%/}"
      [[ -d "$theme/scalable/apps" ]] && adirs+=("$theme/scalable/apps")
      for size in "$theme"/*/; do
        size="${size%/}"
        [[ -d "$size/apps" ]] && adirs+=("$size/apps")
      done
    done
  done
  shopt -u nullglob

  for ext in svg png xpm; do
    for appsdir in "${adirs[@]}"; do
      for f in "$appsdir"/*.$ext; do
        [[ -f $f || -L $f ]] || continue
        base="${f##*/}"
        name="${base%.$ext}"
        [[ -n $name && -z ${ICON_INDEX[$name]:-} ]] && ICON_INDEX["$name"]="$f"
      done
    done
  done

  for f in /usr/share/pixmaps/*.svg /usr/share/pixmaps/*.png; do
    [[ -f $f ]] || continue
    base="${f##*/}"
    name="${base%.*}"
    [[ -z ${ICON_INDEX[$name]:-} ]] && ICON_INDEX["$name"]="$f"
  done
}

load_desktop_entries() {
  local dir file name icon exec cats line key url first
  for dir in "$home/.local/share/applications" "$home/.local/share/applications/kde" \
             /usr/local/share/applications /usr/share/applications /usr/share/applications/kde; do
    [[ -d $dir ]] || continue
    for file in "$dir"/*.desktop; do
      [[ -f $file ]] || continue
      name="" icon="" exec="" cats=""
      while IFS= read -r line; do
        case "$line" in
          "Name="*) name="${line#Name=}" ;;
          "Icon="*) icon="${line#Icon=}" ;;
          "Exec="*) exec="${line#Exec=}" ;;
          "Categories="*) cats="${line#Categories=}" ;;
        esac
      done <"$file"
      [[ -n $name ]] || continue
      key="${name^^}"
      [[ -n $icon && -z ${ICON_BY_NAME[$key]:-} ]] && ICON_BY_NAME["$key"]="$icon"
      [[ -n $cats && -z ${CAT_BY_NAME[$key]:-} ]] && CAT_BY_NAME["$key"]="$cats"
      url="$(printf '%s\n' "$exec" | grep -oE 'https?://[^ "'"'"']+' | head -1 || true)"
      [[ -n $url && -z ${ICON_BY_URL[$url]:-} ]] && ICON_BY_URL["$url"]="$icon"
      [[ -n $url && -z ${CAT_BY_URL[$url]:-} ]] && CAT_BY_URL["$url"]="$cats"
      first="${exec%% *}"
      first="${first#/}"
      first="${first##*/}"
      [[ -n $first && -z ${ICON_BY_EXEC[$first]:-} ]] && ICON_BY_EXEC["$first"]="$icon"
      [[ -n $first && -z ${CAT_BY_EXEC[$first]:-} ]] && CAT_BY_EXEC["$first"]="$cats"
    done
  done
}

# Map a freedesktop Categories string (semicolon-separated) to a friendly group,
# checking keywords in semantic priority order so a game with "Network;Game"
# lands in Games rather than Internet.
friendly_category() {
  local cats=";$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
  case "$cats" in
    *';GAME;'*) echo "Games"; return ;;
  esac
  case "$cats" in
    *';DEVELOPMENT;'*|*';IDE;'*) echo "Development"; return ;;
  esac
  case "$cats" in
    *';WEBBROWSER;'*) echo "Internet"; return ;;
  esac
  case "$cats" in
    *';OFFICE;'*|*';WORDPROCESSOR;'*|*';SPREADSHEET;'*|*';PRESENTATION;'*) echo "Office"; return ;;
  esac
  case "$cats" in
    *';AUDIO;'*|*';VIDEO;'*|*';AUDIOVIDEO;'*|*';MUSIC;'*|*';GRAPHICS;'*|*';PHOTOGRAPHY;'*) echo "Multimedia"; return ;;
  esac
  case "$cats" in
    *';TEXTEDITOR;'*) echo "Development"; return ;;
  esac
  case "$cats" in
    *';COMMUNICATION;'*|*';CHAT;'*|*';EMAIL;'*|*';FILETRANSFER;'*|*';NETWORK;'*) echo "Internet"; return ;;
  esac
  case "$cats" in
    *';FILEMANAGER;'*|*';TERMINALEMULATOR;'*|*';SYSTEM;'*|*';UTILITY;'*|*';MONITOR;'*) echo "System"; return ;;
  esac
  echo "Apps"
}

resolve_category() {
  local label="$1" value="$2" kind="$3"
  [[ -n ${CURATED_CAT[$label]:-} ]] && { printf '%s' "${CURATED_CAT[$label]}"; return; }
  local cats=""
  case "$kind" in
    webapp) cats="${CAT_BY_URL[$value]:-}" ;;
    *) cats="${CAT_BY_NAME["${label^^}"]:-}"; [[ -z $cats ]] && cats="${CAT_BY_EXEC[${value%% *}]:-}" ;;
  esac
  if [[ -n $cats ]]; then friendly_category "$cats"; else printf 'Apps'; fi
}

# Glyph for the default coding agent from the omarchy icon font.
agent_glyph() {
  local a
  a="$(omarchy-default-agent 2>/dev/null || true)"
  case "$a" in
    opencode) printf '\ue902' ;;
    codex) printf '\ue905' ;;
    grok) printf '\ue904' ;;
    pi) printf '\ue901' ;;
    omp) printf '\ue903' ;;
    *) printf '' ;;
  esac
}

# ---------------------------------------------------------------- parsing
# Read a single o.bind(...) line and append one TSV record (fields joined by
# \x1f) to stdout when the action launches an app. Emits nothing otherwise.
parse_line() {
  local line="$1" catg="$2"
  [[ $line == *'o.bind('* ]] || return 0

  local re='o\.bind\("[^"]*"[[:space:]]*,[[:space:]]*"[^"]*"[[:space:]]*,[[:space:]]*(.*)\)[[:space:]]*;?[[:space:]]*$'
  [[ $line =~ o\.bind\(\"[^\"]*\"[[:space:]]*,[[:space:]]*\"([^\"]+)\"[[:space:]]*,[[:space:]]*\"([^\"]+)\"[[:space:]]*,[[:space:]]*(.*)$ ]] && {
    # four-argument form (options after the command) — command is a plain string
    local chord4="${BASH_REMATCH[1]}" label4="${BASH_REMATCH[2]}" cmd4="${BASH_REMATCH[3]}"
    cmd4="${cmd4//\"/}"
    [[ $cmd4 == omarchy-launch-* || $cmd4 == "uwsm-app --"* || $cmd4 == omarchy-agent* \
       || $cmd4 == omarchy-launch-or-focus-* ]] || return 0
    emit_record "$chord4" "$label4" "string" "$cmd4" "$catg"
    return 0
  }

  [[ $line =~ o\.bind\(\"([^\"]+)\"[[:space:]]*,[[:space:]]*\"([^\"]+)\"[[:space:]]*,[[:space:]]*(.+)$ ]] || return 0
  local chord="${BASH_REMATCH[1]}" label="${BASH_REMATCH[2]}" rest="${BASH_REMATCH[3]}"

  local kind="" value="" focus=""
  if [[ $rest == \{* ]]; then
    if [[ $rest =~ omarchy[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
      kind="omarchy"; value="${BASH_REMATCH[1]}"
    elif [[ $rest =~ webapp[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
      kind="webapp"; value="${BASH_REMATCH[1]}"
    elif [[ $rest =~ tui[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
      kind="tui"; value="${BASH_REMATCH[1]}"
    elif [[ $rest =~ launch[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
      kind="launch"; value="${BASH_REMATCH[1]}"
    fi
    [[ $rest =~ focus[[:space:]]*=[[:space:]]*true ]] && focus="true"
    [[ -n $kind ]] || return 0
  else
    local cmd="${rest%*)}"
    cmd="${cmd//\"/}"
    case "$cmd" in
      omarchy-launch-* | "uwsm-app --"* | omarchy-agent*) kind="string"; value="$cmd" ;;
      *) return 0 ;;
    esac
  fi
  emit_record "$chord" "$label" "$kind" "$value" "$catg" "$focus"
}

emit_record() {
  local chord="$1" label="$2" kind="$3" value="$4" catg="$5" focus="${6:-}"
  [[ -n ${ACTION_LABELS[$label]:-} ]] && return 0

  local category=""
  case "$kind" in
    webapp) category="Web apps" ;;
    tui) category="TUIs" ;;
    *) category="$(resolve_category "$label" "$value" "$kind")" ;;
  esac

  local command="" icon="" glyph="" iconfont=""
  case "$kind" in
    omarchy) command="omarchy-launch-$value" ;;
    webapp)
      if [[ $focus == true ]]; then
        command="omarchy-launch-or-focus-webapp \"$label\" \"$value\""
      else
        command="omarchy-launch-webapp \"$value\""
      fi
      icon="${ICON_BY_URL[$value]:-}"
      ;;
    tui)
      if [[ $focus == true ]]; then
        command="omarchy-launch-or-focus-tui $value"
      else
        command="omarchy-launch-tui $value"
      fi
      ;;
    launch)
      if [[ $focus == true ]]; then
        command="omarchy-launch-or-focus \"$label\" \"uwsm-app -- $value\""
      else
        command="uwsm-app -- $value"
      fi
      ;;
    string)
      command="$value"
      case "$value" in
        omarchy-agent*) glyph="$(agent_glyph)"; iconfont="omarchy" ;;
      esac
      ;;
  esac

  if [[ -z $icon ]]; then
    icon="${CURATED_ICON[$label]:-}"
  fi
  if [[ -z $icon ]]; then
    icon="${ICON_BY_NAME["${label^^}"]:-}"
  fi
  if [[ -z $icon && -z $glyph ]]; then
    local first
    first="$(printf '%s\n' "$command" | grep -oE '[A-Za-z0-9_.+-]+' | head -1 || true)"
    # Only trust the Exec lookup when the first word is a concrete binary, not
    # one of the generic omarchy/uwsm launcher wrappers.
    case "$first" in
      omarchy-* | uwsm-app) ;;
      *) icon="${ICON_BY_EXEC[$first]:-}" ;;
    esac
  fi

  # Resolve the icon name to a themed file path. Names without a real icon fall
  # back to a themed glyph.
  if [[ -n $icon && -n ${ICON_INDEX[$icon]:-} ]]; then
    icon="${ICON_INDEX[$icon]}"
  elif [[ -n $icon ]]; then
    icon=""
  fi
  if [[ -z $icon && -z $glyph ]]; then
    case "$kind" in
      webapp) glyph="󰖩" ;;
      *) glyph="󰈉" ;;
    esac
    if [[ -n ${CURATED_GLYPH_OMARCHY[$label]:-} ]]; then
      glyph="${CURATED_GLYPH_OMARCHY[$label]}"
      iconfont="omarchy"
    fi
  fi

  local id
  id="$(printf '%s\n' "$label" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
  id="$(printf '%s\n' "$id" | sed -E 's/[^a-z0-9_.-]//g')"

  printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' \
    "$id" "$label" "$chord" "$kind" "$category" "$command" "$icon" "$glyph" "$iconfont" "$focus"
}

# ---------------------------------------------------------------- output
main() {
  build_icon_index
  load_desktop_entries

  local json="[]" rec
  local files=()
  if [[ -d $omarchy/default/hypr/bindings ]]; then
    local f
    for f in "$omarchy"/default/hypr/bindings/*.lua; do [[ -f $f ]] && files+=("$f"); done
  fi
  [[ -f $user_bindings ]] && files+=("$user_bindings")

  while IFS= read -r line; do
    [[ -z $line ]] && continue
    rec="$line"
    IFS=$'\x1f' read -r id label chord kind catg command icon glyph iconfont focus <<<"$rec"
    json="$(
      jq -nc \
        --argjson arr "$json" \
        --arg id "$id" --arg label "$label" --arg chord "$chord" \
        --arg kind "$kind" --arg catg "$catg" --arg command "$command" \
        --arg icon "$icon" --arg glyph "$glyph" --arg iconfont "$iconfont" \
        '$arr + [{ id: $id, label: $label, chord: $chord, kind: $kind,
                    category: $catg, command: $command, icon: $icon,
                    glyph: $glyph, iconFont: $iconfont }]'
    )"
  done < <(
    for file in "${files[@]}"; do
      grep -n 'o\.bind(' "$file" 2>/dev/null | while IFS= read -r l; do
        parse_line "${l#*:}" ""
      done
    done
  )

  printf '%s\n' "$json"
}

main "$@"
