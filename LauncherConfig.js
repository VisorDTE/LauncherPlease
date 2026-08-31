// Config merge for LauncherPlease: file config (~/.config/omarchy/launcherplease.json)
// overrides defaults, IPC payload overrides the file. Pure for node --test.

var DEFAULTS = {
  columns: 8,
  layout: "compact",
  showChords: true,
  showCategories: true,
  captureChords: true,
  duration: 0,
  groupOrder: ["Most used", "Web apps", "Games", "Development", "Office", "Multimedia", "Internet", "System", "TUIs", "Apps"],
  favorites: [],
  exclude: [],
  categories: {},
  mostUsedCount: 8,
  mostUsedDays: 14,
  effects: { pulse: true, glow: true, bounce: true }
}

function parseJson(raw, fallback) {
  try {
    return JSON.parse(String(raw || ""))
  } catch (e) {
    return fallback
  }
}

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v)
}

function boolOr(value, fallback) {
  if (value === undefined || value === null) return fallback
  return !!value
}

function numberOr(value, fallback) {
  var n = Number(value)
  return isFinite(n) && n >= 0 ? n : fallback
}

function layoutOr(value, fallback) {
  if (value === "roomy" || value === "compact") return value
  return fallback
}

function stringArray(value) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    var v = String(value[i] || "").trim()
    if (v) out.push(v)
  }
  return out
}

function mergeEffects(fileEffects, payloadEffects) {
  var base = isObject(fileEffects) ? fileEffects : {}
  var extra = isObject(payloadEffects) ? payloadEffects : {}
  return {
    pulse: boolOr(extra.pulse, boolOr(base.pulse, DEFAULTS.effects.pulse)),
    glow: boolOr(extra.glow, boolOr(base.glow, DEFAULTS.effects.glow)),
    bounce: boolOr(extra.bounce, boolOr(base.bounce, DEFAULTS.effects.bounce))
  }
}

function merge(fileRaw, payloadRaw) {
  var file = parseJson(fileRaw, {})
  if (!isObject(file)) file = {}
  var payload = parseJson(payloadRaw, {})
  if (!isObject(payload)) payload = {}

  var groupOrder = Array.isArray(file.groupOrder) ? stringArray(file.groupOrder) : DEFAULTS.groupOrder
  if (groupOrder.length === 0) groupOrder = DEFAULTS.groupOrder

  return {
    columns: Math.max(1, Math.floor(numberOr(payload.columns, numberOr(file.columns, DEFAULTS.columns)))),
    layout: layoutOr(payload.layout, layoutOr(file.layout, DEFAULTS.layout)),
    showChords: boolOr(payload.showChords, boolOr(file.showChords, DEFAULTS.showChords)),
    showCategories: boolOr(payload.showCategories, boolOr(file.showCategories, DEFAULTS.showCategories)),
    captureChords: boolOr(payload.captureChords, boolOr(file.captureChords, DEFAULTS.captureChords)),
    duration: numberOr(payload.duration, numberOr(file.duration, DEFAULTS.duration)),
    groupOrder: stringArray(payload.groupOrder).length ? stringArray(payload.groupOrder) : groupOrder,
    favorites: stringArray(payload.favorites).length ? stringArray(payload.favorites) : stringArray(file.favorites),
    exclude: stringArray(file.exclude),
    categories: isObject(file.categories) ? file.categories : {},
    mostUsedCount: Math.max(0, Math.floor(numberOr(payload.mostUsedCount, numberOr(file.mostUsedCount, DEFAULTS.mostUsedCount)))),
    mostUsedDays: Math.max(1, Math.floor(numberOr(payload.mostUsedDays, numberOr(file.mostUsedDays, DEFAULTS.mostUsedDays)))),
    effects: mergeEffects(file.effects, payload.effects)
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { DEFAULTS: DEFAULTS, parseJson: parseJson, boolOr: boolOr, numberOr: numberOr, stringArray: stringArray, layoutOr: layoutOr, merge: merge }
}
