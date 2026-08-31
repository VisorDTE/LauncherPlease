// Turns the raw list.sh JSON into an ordered, filtered app list grouped by
// category. Pure functions so node --test can cover them without the shell.

var DEFAULT_GROUP_ORDER = ["Most used", "Web apps", "Games", "Development", "Office", "Multimedia", "Internet", "System", "TUIs", "Apps"]

function normalizeApps(rawApps) {
  var values = rawApps || []
  return values.map(function (raw, index) {
    return {
      index: index,
      id: String(raw.id || ("app-" + index)),
      label: String(raw.label || ""),
      chord: String(raw.chord || ""),
      kind: String(raw.kind || ""),
      category: String(raw.category || "Apps"),
      command: String(raw.command || ""),
      icon: String(raw.icon || ""),
      glyph: String(raw.glyph || ""),
      iconFont: String(raw.iconFont || ""),
      chordLabel: String(raw.chord || "")
    }
  })
}

function buildFilter(exclude) {
  var set = {}
  var values = exclude || []
  for (var i = 0; i < values.length; i++) {
    var v = String(values[i] || "").trim()
    if (v) set[v.toLowerCase()] = true
  }
  return function (app) {
    return !set[app.label.toLowerCase()] && !set[app.id.toLowerCase()]
  }
}

function matchesFilter(app, text) {
  var q = String(text || "").trim().toLowerCase()
  if (!q) return true
  return app.label.toLowerCase().indexOf(q) >= 0 ||
    app.chord.toLowerCase().indexOf(q) >= 0 ||
    app.command.toLowerCase().indexOf(q) >= 0
}

// Returns the ordered category list honoring groupOrder; unknown categories go
// last in first-seen order.
function orderedCategories(categories, groupOrder) {
  var order = groupOrder || DEFAULT_GROUP_ORDER
  var seen = {}
  var out = []
  for (var i = 0; i < order.length; i++) {
    if (categories[order[i]]) {
      out.push(order[i])
      seen[order[i]] = true
    }
  }
  var keys = Object.keys(categories)
  for (var j = 0; j < keys.length; j++) {
    if (!seen[keys[j]]) out.push(keys[j])
  }
  return out
}

// favorites are pinned at the top of their own category; the rest keep source
// order. Returns { categories, apps } where categories is an ordered array and
// apps is the filtered flat list in display order.
function cloneAsMostUsed(app) {
  return {
    index: app.index,
    id: app.id,
    label: app.label,
    chord: app.chord,
    kind: app.kind,
    category: "Most used",
    command: app.command,
    icon: app.icon,
    glyph: app.glyph,
    iconFont: app.iconFont,
    chordLabel: app.chordLabel
  }
}

function arrange(apps, config, usageScores) {
  var cfg = config || {}
  var filter = buildFilter(cfg.exclude)
  var favorites = {}
  var favValues = cfg.favorites || []
  for (var i = 0; i < favValues.length; i++) {
    var f = String(favValues[i] || "").toLowerCase().trim()
    if (f) favorites[f] = true
  }
  var catOverride = cfg.categories || {}

  var filtered = apps.filter(filter)
  var byId = {}
  for (var fidx = 0; fidx < filtered.length; fidx++) byId[filtered[fidx].id] = filtered[fidx]

  var mostLimit = Math.max(0, Math.floor(Number(cfg.mostUsedCount) || 8))
  var ranked = []
  if (usageScores && mostLimit > 0) {
    var ids = Object.keys(usageScores)
    ids.sort(function (a, b) {
      var diff = usageScores[b] - usageScores[a]
      if (diff !== 0) return diff
      return a < b ? -1 : a > b ? 1 : 0
    })
    for (var m = 0; m < ids.length && ranked.length < mostLimit; m++) {
      if (byId[ids[m]]) ranked.push(cloneAsMostUsed(byId[ids[m]]))
    }
  }

  var byCategory = {}
  if (ranked.length) byCategory["Most used"] = { favs: ranked, rest: [] }
  for (var j = 0; j < filtered.length; j++) {
    var app = filtered[j]
    var override = catOverride[app.label]
    var cat = override ? String(override) : app.category
    if (!byCategory[cat]) byCategory[cat] = { favs: [], rest: [] }
    var key = app.label.toLowerCase()
    if (favorites[key] || favorites[app.id.toLowerCase()]) byCategory[cat].favs.push(app)
    else byCategory[cat].rest.push(app)
  }

  var cats = orderedCategories(byCategory, cfg.groupOrder)
  var ordered = []
  for (var k = 0; k < cats.length; k++) {
    var bucket = byCategory[cats[k]]
    ordered = ordered.concat(bucket.favs).concat(bucket.rest)
  }
  return { categories: cats, apps: ordered }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    DEFAULT_GROUP_ORDER: DEFAULT_GROUP_ORDER,
    normalizeApps: normalizeApps,
    buildFilter: buildFilter,
    matchesFilter: matchesFilter,
    orderedCategories: orderedCategories,
    arrange: arrange
  }
}
