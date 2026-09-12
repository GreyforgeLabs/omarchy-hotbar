#!/usr/bin/env node
"use strict"

// Manifest / runtime parity: HotbarModel.js is the canonical runtime
// validator, and it must match manifest.json. Fails on any drift in setting
// names, types, integer limits, enum values, or defaults.

const assert = require("assert")
const fs = require("fs")
const path = require("path")

const M = require(path.join(__dirname, "..", "HotbarModel.js"))
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))

let passed = 0
function test(name, fn) {
  try { fn(); passed++ } catch (e) { console.error("FAIL:", name); throw e }
}

const schema = manifest.barWidget.schema
const defaults = manifest.barWidget.defaults

test("every manifest schema key exists in the runtime spec", () => {
  for (const entry of schema) {
    assert.ok(M.SETTING_SPEC[entry.key], `missing runtime spec for ${entry.key}`)
  }
})

test("every runtime spec key is declared by the manifest (schema or defaults)", () => {
  const declared = new Set([...schema.map(e => e.key), ...Object.keys(defaults)])
  for (const key of Object.keys(M.SETTING_SPEC)) {
    assert.ok(declared.has(key), `runtime spec ${key} has no manifest entry`)
  }
})

test("every manifest default key has a runtime spec entry", () => {
  for (const key of Object.keys(defaults)) {
    assert.ok(M.SETTING_SPEC[key], `manifest default ${key} has no runtime spec`)
  }
})

test("types agree", () => {
  const typeMap = { integer: "integer", boolean: "boolean", enum: "enum" }
  for (const entry of schema) {
    const spec = M.SETTING_SPEC[entry.key]
    if (entry.key === "pins" || entry.key === "matches" || entry.key === "favorites") continue
    assert.strictEqual(spec.type, typeMap[entry.type] || entry.type,
      `${entry.key}: manifest type ${entry.type} vs runtime ${spec.type}`)
  }
})

test("integer limits agree", () => {
  for (const entry of schema) {
    if (entry.type !== "integer") continue
    const spec = M.SETTING_SPEC[entry.key]
    assert.strictEqual(spec.min, entry.min, `${entry.key}: min drift`)
    assert.strictEqual(spec.max, entry.max, `${entry.key}: max drift`)
  }
})

test("enum values agree", () => {
  for (const entry of schema) {
    if (entry.type !== "enum") continue
    const spec = M.SETTING_SPEC[entry.key]
    assert.deepStrictEqual([...spec.options].sort(), [...entry.options].sort(),
      `${entry.key}: enum drift`)
  }
})

test("defaults agree where practical", () => {
  for (const entry of schema) {
    if (entry.defaultValue === undefined) continue
    const spec = M.SETTING_SPEC[entry.key]
    if (entry.type === "integer" || entry.type === "enum" || entry.type === "boolean") {
      assert.deepStrictEqual(spec.defaultValue, entry.defaultValue,
        `${entry.key}: default drift`)
    }
  }
  for (const [key, value] of Object.entries(defaults)) {
    const checked = M.validateSetting(key, value)
    assert.ok(checked.ok, `manifest default for ${key} fails runtime validation: ${checked.error}`)
  }
})

test("manifest defaults pass runtime validation", () => {
  for (const entry of schema) {
    if (entry.defaultValue === undefined) continue
    if (entry.key === "pins" || entry.key === "matches" || entry.key === "favorites") continue
    const checked = M.validateSetting(entry.key, entry.defaultValue)
    assert.ok(checked.ok, `${entry.key}: default fails validation`)
  }
})

console.log("ManifestParity: " + passed + " tests passed")
