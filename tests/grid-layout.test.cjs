const test = require("node:test")
const assert = require("node:assert/strict")
const Grid = require("../GridLayout.js")

function app(label, category) {
  return { id: label.toLowerCase(), label: label, category: category, chord: "", command: "" }
}

test("large categories get a banner and wrap by columns", () => {
  const apps = [
    app("Terminal", "Apps"), app("Browser", "Apps"), app("Editor", "Apps"),
    app("ChatGPT", "Web apps"), app("Email", "Web apps"), app("YouTube", "Web apps")
  ]
  const layout = Grid.build(apps, 2)
  assert.equal(layout.count, 6)
  const kinds = layout.rows.map((r) => r.type)
  assert.equal(kinds.filter((k) => k === "banner").length, 2)
  const banners = layout.rows.filter((r) => r.type === "banner").map((r) => r.label)
  assert.deepEqual(banners, ["Apps", "Web apps"])
  const rowCells = layout.rows.filter((r) => r.type === "row").map((r) => r.items.filter((i) => i.kind === "cell").length)
  assert.deepEqual(rowCells, [2, 1, 2, 1])
})

test("small categories pack onto one row", () => {
  const apps = [app("Steam", "Games"), app("Editor", "Development"), app("Agent", "Development")]
  const layout = Grid.build(apps, 8)
  assert.equal(layout.rows.length, 1)
  assert.equal(layout.rows[0].type, "row")
  const kinds = layout.rows[0].items.map((i) => i.kind)
  assert.deepEqual(kinds, ["header", "cell", "header", "cell", "cell"])
})

test("navigation wraps across the whole list horizontally", () => {
  const apps = [app("Terminal", "Apps"), app("Browser", "Apps"), app("Editor", "Apps")]
  const layout = Grid.build(apps, 2)
  assert.equal(Grid.move(layout, 0, "left"), 2)
  assert.equal(Grid.move(layout, 2, "right"), 0)
  assert.equal(Grid.move(layout, 0, "right"), 1)
})

test("navigation moves between rows and wraps vertically", () => {
  const apps = [app("A", "X"), app("B", "X"), app("C", "X"), app("D", "X")]
  const layout = Grid.build(apps, 2)
  assert.equal(Grid.move(layout, 0, "down"), 2)
  assert.equal(Grid.move(layout, 2, "up"), 0)
  assert.equal(Grid.move(layout, 1, "down"), 3)
  assert.equal(Grid.move(layout, 1, "down"), 3)
})

test("navigation crosses packed categories", () => {
  const apps = [app("Steam", "Games"), app("Editor", "Development"), app("ChatGPT", "Web apps")]
  const layout = Grid.build(apps, 8)
  assert.equal(Grid.move(layout, 0, "right"), 1)
  assert.equal(Grid.move(layout, 1, "right"), 2)
  assert.equal(Grid.move(layout, 2, "left"), 1)
})

test("empty and single-app layouts", () => {
  const empty = Grid.build([], 3)
  assert.equal(empty.count, 0)
  assert.equal(Grid.move(empty, 0, "right"), -1)
  const single = Grid.build([app("Only", "Apps")], 3)
  assert.equal(Grid.move(single, 0, "right"), 0)
  assert.equal(Grid.move(single, 0, "up"), 0)
  assert.equal(Grid.rowOf(single, 0), 0)
})

test("rowOf and colOf track cursor position", () => {
  const apps = [app("A", "X"), app("B", "X"), app("C", "X")]
  const layout = Grid.build(apps, 2)
  assert.equal(Grid.rowOf(layout, 0), 1)
  assert.equal(Grid.colOf(layout, 0), 0)
  assert.equal(Grid.colOf(layout, 2), 0)
})

test("roomy layout starts every category on its own row", () => {
  const apps = [app("Steam", "Games"), app("Editor", "Development"), app("Agent", "Development")]
  const layout = Grid.build(apps, 8, "roomy")
  assert.equal(layout.rows.length, 2)
  const kinds = layout.rows.map((r) => r.items.map((i) => i.kind).join(","))
  assert.deepEqual(kinds, ["header,cell", "header,cell,cell"])
})

test("roomy layout still banners and wraps large categories", () => {
  const apps = [
    app("Terminal", "Apps"), app("Browser", "Apps"), app("Editor", "Apps"),
    app("ChatGPT", "Web apps")
  ]
  const layout = Grid.build(apps, 2, "roomy")
  const banners = layout.rows.filter((r) => r.type === "banner").map((r) => r.label)
  assert.deepEqual(banners, ["Apps"])
  const lastRow = layout.rows[layout.rows.length - 1]
  assert.equal(lastRow.type, "row")
  assert.deepEqual(lastRow.items.map((i) => i.kind), ["header", "cell"])
})

test("categoryJump moves to first app of next/prev category and wraps", () => {
  const apps = [
    app("Steam", "Games"),
    app("Editor", "Development"), app("Agent", "Development"),
    app("ChatGPT", "Web apps")
  ]
  const layout = Grid.build(apps, 8)
  assert.equal(Grid.categoryJump(layout, 0, 1), 1)
  assert.equal(Grid.categoryJump(layout, 1, 1), 3)
  assert.equal(Grid.categoryJump(layout, 2, 1), 3)
  assert.equal(Grid.categoryJump(layout, 3, 1), 0)
  assert.equal(Grid.categoryJump(layout, 0, -1), 3)
  assert.equal(Grid.categoryJump(layout, 1, -1), 0)
})

test("categoryJump is a no-op on empty and single-category layouts", () => {
  const empty = Grid.build([], 3)
  assert.equal(Grid.categoryJump(empty, 0, 1), 0)
  const single = Grid.build([app("A", "X"), app("B", "X")], 3)
  assert.equal(Grid.categoryJump(single, 1, 1), 0)
  assert.equal(Grid.categoryJump(single, 1, -1), 0)
})
