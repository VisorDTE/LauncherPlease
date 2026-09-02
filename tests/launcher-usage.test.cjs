const test = require("node:test")
const assert = require("node:assert/strict")
const Usage = require("../LauncherUsage.js")

test("prune drops days outside the rolling window", () => {
  const days = {
    "2026-08-01": { steam: 9 },
    "2026-08-20": { steam: 1 },
    "2026-08-30": { terminal: 2 }
  }
  const kept = Usage.prune(days, "2026-08-30", 14)
  assert.equal(kept["2026-08-01"], undefined)
  assert.equal(kept["2026-08-20"].steam, 1)
  assert.equal(kept["2026-08-30"].terminal, 2)
})

test("scores sum launches across remaining days", () => {
  const days = {
    "2026-08-20": { steam: 2, terminal: 1 },
    "2026-08-30": { steam: 3, browser: 4 }
  }
  const scores = Usage.scores(days)
  assert.equal(scores.steam, 5)
  assert.equal(scores.terminal, 1)
  assert.equal(scores.browser, 4)
  // Null-prototype: external ids must not collide with Object.prototype.
  assert.equal(Object.getPrototypeOf(scores), null)
})

test("topIds ranks by count then id", () => {
  const ids = Usage.topIds({ steam: 5, terminal: 5, browser: 1, unused: 0 }, 2)
  assert.deepEqual(ids, ["steam", "terminal"])
})

test("record increments today without mutating the previous bucket", () => {
  const days = { "2026-08-30": { steam: 1 } }
  const next = Usage.record(days, "steam", "2026-08-30")
  assert.equal(days["2026-08-30"].steam, 1)
  assert.equal(next["2026-08-30"].steam, 2)
})
