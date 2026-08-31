const test = require("node:test")
const assert = require("node:assert/strict")
const { prettyKey, formatChord, chordKeys, wrapKeys } = require("../ChordKey.js")

test("prettyKey maps modifiers to short labels", () => {
  assert.equal(prettyKey("SUPER"), "Super")
  assert.equal(prettyKey("SHIFT"), "Shift")
  assert.equal(prettyKey("CTRL"), "Ctrl")
  assert.equal(prettyKey("CONTROL"), "Ctrl")
  assert.equal(prettyKey("ALT"), "Alt")
  assert.equal(prettyKey(""), "")
})

test("prettyKey maps punctuation and arrows", () => {
  assert.equal(prettyKey("LEFT"), "←")
  assert.equal(prettyKey("DOWN"), "↓")
  assert.equal(prettyKey("RETURN"), "↵")
  assert.equal(prettyKey("ESCAPE"), "Esc")
  assert.equal(prettyKey("SLASH"), "/")
})

test("prettyKey keeps single letters uppercase", () => {
  assert.equal(prettyKey("e"), "E")
  assert.equal(prettyKey("A"), "A")
})

test("formatChord joins modifiers and key", () => {
  assert.equal(formatChord("SUPER + SHIFT + E"), "Super+Shift+E")
  assert.equal(formatChord("SUPER + RETURN"), "Super+↵")
  assert.equal(formatChord(""), "")
  assert.equal(formatChord("SUPER + SHIFT + SLASH"), "Super+Shift+/")
})

test("chordKeys splits a chord into individual keycap labels", () => {
  assert.deepEqual(chordKeys("SUPER + SHIFT + E"), ["Super", "Shift", "E"])
  assert.deepEqual(chordKeys("SUPER + RETURN"), ["Super", "↵"])
  assert.deepEqual(chordKeys(""), [])
})

test("wrapKeys greedily wraps keys to the available width", () => {
  assert.deepEqual(wrapKeys(["Super", "Shift", "E"], 80, 6, 3, 3), [["Super", "Shift"], ["E"]])
  assert.deepEqual(wrapKeys(["Super", "Shift", "E"], 200, 6, 3, 3), [["Super", "Shift", "E"]])
  assert.deepEqual(wrapKeys(["Super", "Shift"], 30, 6, 3, 3), [["Super"], ["Shift"]])
  assert.deepEqual(wrapKeys([], 100, 6, 3, 3), [])
  assert.deepEqual(wrapKeys(["Ctrl", "Alt"], 40, 6, 3, 3), [["Ctrl"], ["Alt"]])
})
