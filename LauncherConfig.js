// Config merge for LauncherPlease: file config (~/.config/omarchy/launcherplease.json)
// overrides defaults, IPC payload overrides the file. Pure for node --test.
// All numeric/string inputs are clamped so hostile payloads cannot force the
// shell into unbounded work.

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

// Hard ceilings, independent of theme scale.
var LIMITS = {
  columns: { min: 1, max: 24 },
  duration: { min: 0, max: 3600000 },
  mostUsedCount: { min: 0, max: 100 },
  mostUsedDays: { min: 1, max: 365 },
  maxStringLen: 512,
  maxArrayLen: 64
}

function parseJson(raw, fallback) {
  var s = String(raw || "")
  if (s.length > 65536) return fallback
  try {
    return JSON.parse(s)
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

function clamp(value, lim) {
  var n = Math.floor(numberOr(value, lim.min))
  if (n < lim.min) n = lim.min
  if (n > lim.max) n = lim.max
  return n
}

function layoutOr(value, fallback) {
  if (value === "roomy" || value === "compact" || value === "list") return value
  return fallback
}

function cappedString(value) {
  var s = String(value === undefined || value === null ? "" : value)
  return s.length > LIMITS.maxStringLen ? s.slice(0, LIMITS.maxStringLen) : s
}

function stringArray(value) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length && i < LIMITS.maxArrayLen; i++) {
    var v = cappedString(value[i]).trim()
    if (v) out.push(v)
  }
  return out
}

// Categories is an externally keyed map; strip prototype-dangerous keys, bound
// both the count and value lengths, and use a null-prototype object so
// ordinary lookups can never hit Object.prototype.
function safeCategories(value) {
  if (!isObject(value)) return Object.create(null)
  var out = Object.create(null)
  var keys = Object.keys(value)
  for (var i = 0; i < keys.length && i < LIMITS.maxArrayLen; i++) {
    var k = keys[i]
    if (k === "__proto__" || k === "constructor" || k === "prototype") continue
    out[k] = cappedString(value[k])
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
    columns: clamp(numberOr(payload.columns, numberOr(file.columns, DEFAULTS.columns)), LIMITS.columns),
    layout: layoutOr(payload.layout, layoutOr(file.layout, DEFAULTS.layout)),
    showChords: boolOr(payload.showChords, boolOr(file.showChords, DEFAULTS.showChords)),
    showCategories: boolOr(payload.showCategories, boolOr(file.showCategories, DEFAULTS.showCategories)),
    captureChords: boolOr(payload.captureChords, boolOr(file.captureChords, DEFAULTS.captureChords)),
    duration: clamp(numberOr(payload.duration, numberOr(file.duration, DEFAULTS.duration)), LIMITS.duration),
    groupOrder: stringArray(payload.groupOrder).length ? stringArray(payload.groupOrder) : groupOrder,
    favorites: stringArray(payload.favorites).length ? stringArray(payload.favorites) : stringArray(file.favorites),
    exclude: stringArray(file.exclude),
    categories: safeCategories(file.categories),
    mostUsedCount: clamp(numberOr(payload.mostUsedCount, numberOr(file.mostUsedCount, DEFAULTS.mostUsedCount)), LIMITS.mostUsedCount),
    mostUsedDays: clamp(numberOr(payload.mostUsedDays, numberOr(file.mostUsedDays, DEFAULTS.mostUsedDays)), LIMITS.mostUsedDays),
    effects: mergeEffects(file.effects, payload.effects)
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { DEFAULTS: DEFAULTS, LIMITS: LIMITS, parseJson: parseJson, boolOr: boolOr, numberOr: numberOr, stringArray: stringArray, layoutOr: layoutOr, merge: merge }
}
