// Rolling launch stats for the Most used section. Days older than `windowDays`
// drop off, so an app promotes itself by being launched and demotes itself by
// going unused. Pure so node --test can cover prune/score/top without QML.

// Null-prototype maps: day keys and app ids come from external state, so a
// value like "__proto__" must never reach a normal object's prototype.
function nullMap() {
  return Object.create(null)
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

function dayKey(date) {
  var d = date || new Date()
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

function parseDays(raw) {
  var data = raw
  if (typeof raw === "string") {
    try { data = JSON.parse(raw) } catch (e) { return nullMap() }
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) return nullMap()
  var days = data.days
  if (!days || typeof days !== "object" || Array.isArray(days)) return nullMap()
  var out = nullMap()
  var keys = Object.keys(days)
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i]
    var bucket = days[k]
    if (!bucket || typeof bucket !== "object" || Array.isArray(bucket)) continue
    var copy = nullMap()
    var ids = Object.keys(bucket)
    for (var j = 0; j < ids.length; j++) copy[ids[j]] = bucket[ids[j]]
    out[k] = copy
  }
  return out
}

function prune(days, todayKey, windowDays) {
  var keep = nullMap()
  var window = Math.max(1, Math.min(365, Number(windowDays) || 14))
  var today = todayKey || dayKey()
  var parts = today.split("-")
  var end = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  var start = new Date(end.getTime())
  start.setDate(start.getDate() - (window - 1))
  var keys = Object.keys(days || {})
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i]
    var p = k.split("-")
    if (p.length !== 3) continue
    var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
    if (d >= start && d <= end) keep[k] = days[k]
  }
  return keep
}

function scores(days) {
  var out = nullMap()
  var keys = Object.keys(days || {})
  for (var i = 0; i < keys.length; i++) {
    var bucket = days[keys[i]]
    if (!bucket || typeof bucket !== "object") continue
    var ids = Object.keys(bucket)
    for (var j = 0; j < ids.length; j++) {
      var n = Number(bucket[ids[j]])
      if (!isFinite(n) || n <= 0) continue
      out[ids[j]] = (out[ids[j]] || 0) + n
    }
  }
  return out
}

function topIds(scoreMap, limit) {
  var max = Math.max(0, Math.floor(Number(limit) || 0))
  if (max > 100) max = 100
  var ids = Object.keys(scoreMap || {})
  ids.sort(function (a, b) {
    var diff = scoreMap[b] - scoreMap[a]
    if (diff !== 0) return diff
    return a < b ? -1 : a > b ? 1 : 0
  })
  if (ids.length > max) ids.length = max
  return ids
}

function record(days, id, todayKey) {
  var next = nullMap()
  var keys = Object.keys(days || {})
  for (var i = 0; i < keys.length; i++) next[keys[i]] = days[keys[i]]
  var day = todayKey || dayKey()
  var bucket = next[day]
  if (!bucket || typeof bucket !== "object") bucket = nullMap()
  else {
    var copy = nullMap()
    var bkeys = Object.keys(bucket)
    for (var j = 0; j < bkeys.length; j++) copy[bkeys[j]] = bucket[bkeys[j]]
    bucket = copy
  }
  var key = String(id || "")
  if (key) bucket[key] = (Number(bucket[key]) || 0) + 1
  next[day] = bucket
  return next
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    dayKey: dayKey,
    parseDays: parseDays,
    prune: prune,
    scores: scores,
    topIds: topIds,
    record: record
  }
}
