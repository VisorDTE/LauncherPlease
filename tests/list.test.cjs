const test = require("node:test")
const assert = require("node:assert/strict")
const { execFileSync } = require("node:child_process")
const path = require("node:path")

const pluginDir = path.join(__dirname, "..")

function runList() {
  const out = execFileSync("bash", [path.join(pluginDir, "list.sh")], { encoding: "utf8", timeout: 30000 })
  return JSON.parse(out)
}

test("list.sh emits a valid JSON array", () => {
  const apps = runList()
  assert.ok(Array.isArray(apps))
  assert.ok(apps.length >= 5)
  for (const app of apps) {
    assert.equal(typeof app.id, "string")
    assert.equal(typeof app.label, "string")
    assert.equal(typeof app.chord, "string")
    assert.equal(typeof app.kind, "string")
    assert.equal(typeof app.category, "string")
    assert.equal(typeof app.command, "string")
    assert.ok(app.id.length > 0)
    assert.ok(app.label.length > 0)
    assert.ok(app.command.length > 0)
  }
})

test("known shortcut apps are present", () => {
  const labels = runList().map((a) => a.label)
  for (const expected of ["Terminal", "Browser", "Email", "ChatGPT", "Agent", "Editor"]) {
    assert.ok(labels.includes(expected), `missing ${expected}`)
  }
})

test("non-app commands are excluded", () => {
  for (const app of runList()) {
    assert.ok(!app.command.startsWith("omarchy-shell "), `shell IPC leaked: ${app.label}`)
    assert.ok(!app.command.startsWith("hyprctl "), `hyprctl leaked: ${app.label}`)
    assert.ok(!app.command.startsWith("omarchy-menu"), `menu action leaked: ${app.label}`)
  }
})

test("in-app action shortcuts are hidden", () => {
  const labels = runList().map((a) => a.label)
  for (const action of ["New email", "X Post"]) {
    assert.ok(!labels.includes(action), `action shortcut leaked: ${action}`)
  }
})

test("categories include Apps and Web apps", () => {
  const cats = new Set(runList().map((a) => a.category))
  assert.ok(cats.has("Apps"))
  assert.ok(cats.has("Web apps"))
})

test("native apps are categorized from desktop entries", () => {
  const byLabel = Object.fromEntries(runList().map((a) => [a.label, a.category]))
  assert.equal(byLabel["Editor"], "Development")
  assert.equal(byLabel["Browser"], "Internet")
  assert.equal(byLabel["Terminal"], "System")
  assert.equal(byLabel["Obsidian"], "Office")
})

test("games are categorized as Games", () => {
  const steam = runList().find((a) => a.label === "Steam")
  if (steam) assert.equal(steam.category, "Games")
})

test("webapps carry a launchable command", () => {
  const chatgpt = runList().find((a) => a.label === "ChatGPT")
  assert.ok(chatgpt)
  assert.equal(chatgpt.kind, "webapp")
  assert.match(chatgpt.command, /^omarchy-launch-webapp/)
})
