const test = require("node:test")
const assert = require("node:assert/strict")
const Config = require("../LauncherConfig.js")

test("defaults are used when nothing is configured", () => {
  const cfg = Config.merge("{}", "{}")
  assert.equal(cfg.columns, 8)
  assert.equal(cfg.layout, "compact")
  assert.equal(cfg.showChords, true)
  assert.equal(cfg.captureChords, true)
  assert.equal(cfg.duration, 0)
  assert.equal(cfg.mostUsedCount, 8)
  assert.equal(cfg.mostUsedDays, 14)
  assert.deepEqual(cfg.groupOrder, ["Most used", "Web apps", "Games", "Development", "Office", "Multimedia", "Internet", "System", "TUIs", "Apps"])
  assert.deepEqual(cfg.effects, { pulse: true, glow: true, bounce: true })
})

test("file config overrides defaults", () => {
  const cfg = Config.merge(JSON.stringify({
    columns: 4,
    showChords: false,
    groupOrder: ["Apps"],
    favorites: ["Terminal"]
  }), "{}")
  assert.equal(cfg.columns, 4)
  assert.equal(cfg.showChords, false)
  assert.deepEqual(cfg.groupOrder, ["Apps"])
  assert.deepEqual(cfg.favorites, ["Terminal"])
})

test("payload overrides file", () => {
  const cfg = Config.merge(JSON.stringify({ columns: 4, duration: 1000 }),
    JSON.stringify({ columns: 8 }))
  assert.equal(cfg.columns, 8)
  assert.equal(cfg.duration, 1000)
})

test("malformed json falls back", () => {
  const cfg = Config.merge("not json", "not json either")
  assert.equal(cfg.columns, 8)
})

test("effects merge independently and disable cleanly", () => {
  const cfg = Config.merge(JSON.stringify({ effects: { pulse: false } }), "{}")
  assert.equal(cfg.effects.pulse, false)
  assert.equal(cfg.effects.glow, true)
  const cfg2 = Config.merge("{}", JSON.stringify({ effects: { bounce: false } }))
  assert.equal(cfg2.effects.bounce, false)
  assert.equal(cfg2.effects.pulse, true)
})

test("layout selects roomy and rejects unknown values", () => {
  const roomy = Config.merge(JSON.stringify({ layout: "roomy" }), "{}")
  assert.equal(roomy.layout, "roomy")
  const bad = Config.merge(JSON.stringify({ layout: "spacious" }), "{}")
  assert.equal(bad.layout, "compact")
  const payload = Config.merge("{}", JSON.stringify({ layout: "roomy" }))
  assert.equal(payload.layout, "roomy")
})
