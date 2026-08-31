// Formats a Hyprland chord ("SUPER + SHIFT + E") into compact keycap labels
// ("Super+Shift+E"). Kept dependency-free so the same code runs in the shell
// and in node --test.

function prettyKey(token) {
  var key = String(token || "").trim()
  if (!key) return ""
  var upper = key.toUpperCase()
  var names = {
    SUPER: "Super",
    META: "Super",
    SHIFT: "Shift",
    CTRL: "Ctrl",
    CONTROL: "Ctrl",
    ALT: "Alt",
    MINUS: "-",
    EQUAL: "=",
    LEFT: "←",
    RIGHT: "→",
    UP: "↑",
    DOWN: "↓",
    RETURN: "↵",
    ENTER: "↵",
    BACKSPACE: "⌫",
    ESCAPE: "Esc",
    ESC: "Esc",
    TAB: "Tab",
    SPACE: "Space",
    HOME: "Home",
    SLASH: "/",
    COMMA: ",",
    PERIOD: ".",
    SEMICOLON: ";",
    APOSTROPHE: "'",
    GRAVE: "`",
    PRINT: "Print",
    DELETE: "Del",
    "LEFT MOUSE BUTTON": "LMB",
    "RIGHT MOUSE BUTTON": "RMB"
  }
  if (names[upper]) return names[upper]
  if (key.length === 1) return key.toUpperCase()
  if (key.charAt(0) === key.charAt(0).toUpperCase()) return key.charAt(0) + key.slice(1).toLowerCase()
  return key.charAt(0).toUpperCase() + key.slice(1).toLowerCase()
}

function formatChord(chord) {
  var raw = String(chord || "").trim()
  if (!raw) return ""
  var parts = raw.split(" + ")
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var label = prettyKey(parts[i].trim())
    if (label) out.push(label)
  }
  return out.join("+")
}

// Individual keycap labels for a chord, e.g. "SUPER + SHIFT + E" ->
// ["Super", "Shift", "E"].
function chordKeys(chord) {
  var raw = String(chord || "").trim()
  if (!raw) return []
  var parts = raw.split(" + ")
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var label = prettyKey(parts[i].trim())
    if (label) out.push(label)
  }
  return out
}

// Greedy width-aware wrap of key labels into rows so every shortcut is shown
// in full. `charWidth` is the (monospace) advance per character, `chipPadX` is
// one side's horizontal padding, and `gap` is the spacing between chips.
function wrapKeys(keys, availableWidth, charWidth, chipPadX, gap) {
  var cw = Math.max(0, Number(charWidth) || 0)
  var pad = Math.max(0, Number(chipPadX) || 0)
  var g = Math.max(0, Number(gap) || 0)
  var max = Math.max(0, Number(availableWidth) || 0)
  var rows = []
  var row = []
  var used = 0
  for (var i = 0; i < keys.length; i++) {
    var chipW = String(keys[i]).length * cw + pad * 2
    var add = row.length === 0 ? chipW : g + chipW
    if (row.length > 0 && used + add > max) {
      rows.push(row)
      row = []
      used = 0
      add = chipW
    }
    row.push(keys[i])
    used += add
  }
  if (row.length) rows.push(row)
  return rows
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { prettyKey: prettyKey, formatChord: formatChord, chordKeys: chordKeys, wrapKeys: wrapKeys }
}
