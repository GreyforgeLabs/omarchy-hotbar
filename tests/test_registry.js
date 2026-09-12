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
const factory = new Function(`${stripped}; return { register, unregister, lookup, screens };`)
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

console.log("HotbarRegistry: " + passed + " tests passed")
