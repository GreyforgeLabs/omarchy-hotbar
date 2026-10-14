#!/usr/bin/env node
"use strict"

// Offline tests for HotbarRegistry.js. The file carries a `.pragma library`
// line for QML; the harness strips only that line and loads the rest
// verbatim — registry logic is never duplicated in the test.

const assert = require("assert")
const fs = require("fs")
const path = require("path")

let passed = 0
function test(name, fn) {
  try { fn(); passed++ } catch (e) { console.error("FAIL:", name); throw e }
}

const src = fs.readFileSync(path.join(__dirname, "..", "HotbarRegistry.js"), "utf8")
const stripped = src.split("\n").filter(l => l.trim() !== ".pragma library").join("\n")
const factory = new Function(`${stripped}; return { register, unregister, lookup, screens, claimSocket, releaseSocket, socketOwnedBy };`)
const R = factory()

const a = { id: "a" }, b = { id: "b" }

test("register first instance and look it up", () => {
  R.register("DP-1", a)
  assert.strictEqual(R.lookup("DP-1"), a)
})

test("register multiple screen names", () => {
  R.register("HDMI-1", b)
  assert.strictEqual(R.lookup("DP-1"), a)
  assert.strictEqual(R.lookup("HDMI-1"), b)
  assert.deepStrictEqual(R.screens().sort(), ["DP-1", "HDMI-1"])
})

test("replacement behavior for the same screen name", () => {
  R.register("DP-1", b)
  assert.strictEqual(R.lookup("DP-1"), b)
  R.register("DP-1", a)
})

test("refuse to unregister a screen owned by another instance", () => {
  R.unregister("DP-1", b) // b does not own DP-1
  assert.strictEqual(R.lookup("DP-1"), a)
})

test("unregister the correct instance", () => {
  R.unregister("DP-1", a)
  assert.strictEqual(R.lookup("DP-1"), null)
  assert.deepStrictEqual(R.screens(), ["HDMI-1"])
  R.unregister("HDMI-1", b)
  assert.deepStrictEqual(R.screens(), [])
})

test("unknown screens look up null", () => {
  assert.strictEqual(R.lookup("NOPE"), null)
  assert.strictEqual(R.lookup(""), null)
})

test("first instance claims the native socket, a second is refused", () => {
  assert.strictEqual(R.claimSocket(a), true)
  assert.strictEqual(R.claimSocket(b), false)
  assert.strictEqual(R.socketOwnedBy(a), true)
  assert.strictEqual(R.socketOwnedBy(b), false)
})

test("the owner may re-claim; releasing by a non-owner is a no-op", () => {
  assert.strictEqual(R.claimSocket(a), true)
  R.releaseSocket(b)
  assert.strictEqual(R.socketOwnedBy(a), true)
})

test("after the owner releases, the next instance may claim", () => {
  R.releaseSocket(a)
  assert.strictEqual(R.socketOwnedBy(a), false)
  assert.strictEqual(R.claimSocket(b), true)
  R.releaseSocket(b)
  assert.strictEqual(R.claimSocket(null), false)
})

test("a refused instance waits and is handed the socket on release, without polling", () => {
  // Instances call claimSocket() from socketFreed(), as Hotbar.qml does.
  const mk = (id) => { const o = { id, freed: 0 }; o.socketFreed = () => { o.freed++; R.claimSocket(o) }; return o }
  const owner = mk("owner"), second = mk("second"), third = mk("third")
  assert.strictEqual(R.claimSocket(owner), true)
  assert.strictEqual(R.claimSocket(second), false)
  assert.strictEqual(R.claimSocket(second), false) // asking twice queues once
  assert.strictEqual(R.claimSocket(third), false)
  R.releaseSocket(owner)
  assert.strictEqual(R.socketOwnedBy(second), true)
  assert.strictEqual(second.freed, 1)
  assert.strictEqual(third.freed, 0)
  R.releaseSocket(second)
  assert.strictEqual(R.socketOwnedBy(third), true)
  R.releaseSocket(third)
  assert.strictEqual(R.socketOwnedBy(third), false)
})

test("a destroyed or failing waiter is skipped; a departed waiter is never called", () => {
  const owner = { id: "o" }
  const gone = { id: "gone", socketFreed() { throw new Error("destroyed") } }
  const left = { id: "left", socketFreed() { throw new Error("must not be called") } }
  const next = { id: "next" }; next.socketFreed = () => R.claimSocket(next)
  R.claimSocket(owner); R.claimSocket(gone); R.claimSocket(left); R.claimSocket(next)
  R.releaseSocket(left) // its Component.onDestruction runs releaseSocket too
  R.releaseSocket(owner)
  assert.strictEqual(R.socketOwnedBy(next), true)
  R.releaseSocket(next)
  const fresh = { id: "fresh" }
  assert.strictEqual(R.claimSocket(fresh), true)
  R.releaseSocket(fresh)
})

test("screen lookup ignores prototype names", () => {
  assert.strictEqual(R.lookup("constructor"), null)
  assert.strictEqual(R.lookup("__proto__"), null)
})

test("waiters that claim later (as Hotbar does) are all told; the first claim wins", () => {
  const owner = { id: "o" }
  const told = []
  const a = { id: "a", socketFreed() { told.push("a") } }, b = { id: "b", socketFreed() { told.push("b") } }
  R.claimSocket(owner); R.claimSocket(a); R.claimSocket(b)
  R.releaseSocket(owner)
  assert.deepStrictEqual(told, ["a", "b"])
  assert.strictEqual(R.claimSocket(a), true)   // a's timer fires first
  assert.strictEqual(R.claimSocket(b), false)  // b is refused and waits again
  R.releaseSocket(a)
  assert.deepStrictEqual(told, ["a", "b", "b"])
  assert.strictEqual(R.claimSocket(b), true)
  R.releaseSocket(b)
})

// Hotbar.qml lifecycle guards, checked in its source (the widget itself
// only loads inside the shell; the nested-rig run is the live check).
const hotbarQml = fs.readFileSync(path.join(__dirname, "..", "Hotbar.qml"), "utf8")

test("bar signals after a screen is removed never call into the destroyed widget", () => {
  const block = hotbarQml.match(/Connections \{\s*target: root\.bar\b[\s\S]*?\n  \}/)
  assert.ok(block, "Connections on root.bar not found")
  const handlers = block[0].match(/function on\w+\(\)\s*\{[^}]*\}/g) || []
  assert.ok(handlers.length >= 2, "expected the layout and position handlers")
  for (const h of handlers) assert.ok(/\{\s*if \(root\) root\./.test(h), "unguarded handler: " + h)
})

test("a missing ~/.config/user-dirs.dirs is not logged as an error", () => {
  const fv = hotbarQml.match(/FileView \{\s*id: userDirsFile[\s\S]*?\n  \}/)
  assert.ok(fv, "userDirsFile FileView not found")
  assert.ok(/printErrors: false/.test(fv[0]), "userDirsFile must set printErrors: false")
  assert.ok(/onLoadFailed:/.test(fv[0]), "userDirsFile must still handle a failed load")
})

console.log("HotbarRegistry: " + passed + " tests passed")
