// Fixed-size cells. Small categories share a row (compact header chip + apps).
// Large categories (>= columns apps) keep a full-width banner then wrap.
// In "roomy" mode every category starts on its own row.

function membersOf(apps, category) {
  var members = []
  for (var j = 0; j < apps.length; j++) {
    if (apps[j].category === category) members.push(j)
  }
  return members
}

function categoryOrder(apps) {
  var order = []
  for (var i = 0; i < apps.length; i++) {
    var cat = apps[i].category
    if (order.indexOf(cat) < 0) order.push(cat)
  }
  return order
}

// First app index of each category, in display order (apps are pre-grouped).
function categoryStarts(apps) {
  var out = []
  var last = null
  for (var i = 0; i < apps.length; i++) {
    var cat = apps[i].category
    if (cat !== last) {
      out.push({ category: cat, index: i })
      last = cat
    }
  }
  return out
}

function finishRow(rows, rowApps, pos, current) {
  if (!current.length) return
  var rowIndex = rows.length
  var appsInRow = []
  var col = 0
  for (var i = 0; i < current.length; i++) {
    var item = current[i]
    if (item.kind === "cell") {
      pos[item.appIndex] = { row: rowIndex, col: col }
      appsInRow.push(item.appIndex)
      col++
    }
  }
  rows.push({ type: "row", items: current })
  rowApps[rowIndex] = appsInRow
}

function build(apps, columns, mode) {
  var cols = Math.max(1, Math.floor(Number(columns) || 1))
  var roomy = mode === "roomy"
  var rows = []
  var pos = []
  var rowApps = []
  var catApps = {}
  var catOrder = categoryOrder(apps)

  var current = []
  var used = 0

  function flush() {
    finishRow(rows, rowApps, pos, current)
    current = []
    used = 0
  }

  function addItem(item) {
    if (used >= cols) flush()
    current.push(item)
    used++
  }

  for (var c = 0; c < catOrder.length; c++) {
    var category = catOrder[c]
    var members = membersOf(apps, category)
    catApps[category] = members
    var n = members.length
    if (!n) continue

    if (n >= cols) {
      flush()
      rows.push({ type: "banner", label: category, count: n })
      for (var r = 0; r < n; r += cols) {
        var chunk = members.slice(r, r + cols)
        var items = []
        for (var k = 0; k < chunk.length; k++) items.push({ kind: "cell", appIndex: chunk[k] })
        finishRow(rows, rowApps, pos, items)
      }
      continue
    }

    var need = 1 + n
    if (roomy && used > 0) flush()
    if (used > 0 && used + need > cols) flush()
    addItem({ kind: "header", label: category, count: n })
    for (var m = 0; m < n; m++) addItem({ kind: "cell", appIndex: members[m] })
  }
  flush()

  return {
    apps: apps,
    rows: rows,
    pos: pos,
    rowApps: rowApps,
    catApps: catApps,
    catStarts: categoryStarts(apps),
    columns: cols,
    count: apps.length
  }
}

function left(layout, idx) {
  if (layout.count <= 1) return 0
  return (idx - 1 + layout.count) % layout.count
}

function right(layout, idx) {
  if (layout.count <= 1) return 0
  return (idx + 1) % layout.count
}

function cellRowIndices(layout) {
  var out = []
  var rows = layout.rows || []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].type === "row") out.push(i)
  }
  return out
}

function vertical(layout, idx, delta) {
  var cellRows = cellRowIndices(layout)
  if (cellRows.length === 0) return idx
  var p = layout.pos[idx]
  if (!p) return idx
  var at = cellRows.indexOf(p.row)
  if (at < 0) at = 0
  var next = cellRows[(at + delta + cellRows.length) % cellRows.length]
  var appsInRow = layout.rowApps[next] || []
  if (appsInRow.length === 0) return idx
  var col = Math.min(p.col, appsInRow.length - 1)
  return appsInRow[col]
}

function move(layout, idx, dir) {
  if (!layout || layout.count === 0) return -1
  if (idx < 0 || idx >= layout.count) idx = 0
  switch (dir) {
    case "left": return left(layout, idx)
    case "right": return right(layout, idx)
    case "up": return vertical(layout, idx, -1)
    case "down": return vertical(layout, idx, 1)
    default: return idx
  }
}

// Jump to the first app of the next (delta=1) or previous (delta=-1) category,
// wrapping around the ends.
function categoryJump(layout, idx, delta) {
  var starts = (layout && layout.catStarts) || []
  if (starts.length === 0) return idx
  var cur = 0
  for (var i = 0; i < starts.length; i++) {
    if (starts[i].index <= idx) cur = i
  }
  var next = (cur + delta + starts.length) % starts.length
  return starts[next].index
}

function rowOf(layout, idx) {
  var p = layout && layout.pos && layout.pos[idx]
  return p ? p.row : -1
}

function colOf(layout, idx) {
  var p = layout && layout.pos && layout.pos[idx]
  return p ? p.col : 0
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { build: build, move: move, categoryJump: categoryJump, rowOf: rowOf, colOf: colOf }
}
