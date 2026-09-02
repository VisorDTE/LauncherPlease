const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../LauncherModel.js")

const raw = [
  { id: "terminal", label: "Terminal", category: "Apps", chord: "SUPER + RETURN" },
  { id: "email", label: "Email", category: "Web apps", chord: "SUPER + SHIFT + E" },
  { id: "chatgpt", label: "ChatGPT", category: "Web apps", chord: "SUPER + SHIFT + A" },
  { id: "maps", label: "Google Maps", category: "Web apps", chord: "SUPER + SHIFT + S" }
]

test("normalizeApps copies fields and adds chordLabel", () => {
  const apps = Model.normalizeApps(raw)
  assert.equal(apps.length, 4)
  assert.equal(apps[0].label, "Terminal")
  assert.equal(apps[0].chordLabel, "SUPER + RETURN")
  assert.equal(Model.normalizeApps(undefined).length, 0)
})

test("buildFilter excludes by label and id", () => {
  const filter = Model.buildFilter(["Email", "google maps"])
  assert.equal(filter({ label: "Email", id: "email" }), false)
  assert.equal(filter({ label: "Google Maps", id: "maps" }), false)
  assert.equal(filter({ label: "Terminal", id: "terminal" }), true)
})

test("matchesFilter does full-text search across fields", () => {
  const app = {
    id: "chatgpt",
    label: "ChatGPT",
    category: "Web apps",
    chord: "SUPER + SHIFT + A",
    command: "omarchy-launch-webapp"
  }
  assert.equal(Model.matchesFilter(app, ""), true)
  assert.equal(Model.matchesFilter(app, "chat"), true)
  assert.equal(Model.matchesFilter(app, "SHIFT + A"), true)
  assert.equal(Model.matchesFilter(app, "webapp"), true)
  // category, id and any-word matching
  assert.equal(Model.matchesFilter(app, "web"), true)
  assert.equal(Model.matchesFilter(app, "chatgpt"), true)
  assert.equal(Model.matchesFilter(app, "maps"), false)
  // loose full-text: any of the words matches
  assert.equal(Model.matchesFilter(app, "maps chat"), true)
})

test("arrange honors favorites at top of each category and groupOrder", () => {
  const apps = Model.normalizeApps(raw)
  const cfg = { favorites: ["Email"], exclude: [], groupOrder: Model.DEFAULT_GROUP_ORDER }
  const result = Model.arrange(apps, cfg)
  assert.deepEqual(result.categories, ["Web apps", "Apps"])
  const labels = result.apps.map((a) => a.label)
  // Email is a favorite so it leads the first category (Web apps)
  assert.equal(labels[0], "Email")
  // Terminal leads the Apps category
  assert.equal(labels[3], "Terminal")
})

test("arrange drops excluded apps and unknown categories go last", () => {
  const apps = Model.normalizeApps(raw)
  const result = Model.arrange(apps, { exclude: ["Google Maps"], favorites: [], groupOrder: ["Web apps"] })
  assert.deepEqual(result.categories, ["Web apps", "Apps"])
  const labels = result.apps.map((a) => a.label)
  assert.ok(!labels.includes("Google Maps"))
  assert.equal(labels[0], "Email")
})

test("arrange promotes most-used apps to the front", () => {
  const apps = Model.normalizeApps(raw)
  const result = Model.arrange(apps, { mostUsedCount: 2, groupOrder: Model.DEFAULT_GROUP_ORDER }, { terminal: 9, chatgpt: 4 })
  assert.equal(result.categories[0], "Most used")
  assert.equal(result.apps[0].label, "Terminal")
  assert.equal(result.apps[0].category, "Most used")
  assert.equal(result.apps[1].label, "ChatGPT")
})
