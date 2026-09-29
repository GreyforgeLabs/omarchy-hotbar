#!/usr/bin/env node
"use strict"

// Equivalence test for the native Places helper: on this machine, the shell
// helper (findmnt + jq) and bin/hotbar-places-native must lead PlacesModel to
// the same sections for the same candidate paths. Skips when the native
// binary is not built.

const assert = require("assert")
const { execFileSync } = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")
const P = require(path.join(__dirname, "..", "PlacesModel.js"))

const repo = path.join(__dirname, "..")
const native = path.join(repo, "bin", "hotbar-places-native")
if (!fs.existsSync(native)) {
  console.log("PlacesNative: skipped (run make native)")
  process.exit(0)
}

const home = os.homedir()
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "hotbar-places-"))
const paths = [home, path.join(home, "Downloads"), path.join(home, "Documents"), tmp, path.join(tmp, "missing"), "/nonexistent dir with spaces", "/"]

function run(bin) {
  const out = execFileSync(bin, paths, { encoding: "utf8", timeout: 5000 })
  return JSON.parse(out)
}

let passed = 0
function test(name, fn) {
  try { fn(); passed++ } catch (e) { console.error("FAIL:", name); throw e }
}

const shell = run(path.join(repo, "bin", "hotbar-places"))
const fast = run(native)

test("exists map is identical", () => {
  assert.deepStrictEqual(fast.exists, shell.exists)
  assert.strictEqual(fast.exists[tmp], true)
  assert.strictEqual(fast.exists[path.join(tmp, "missing")], false)
})

test("trash handler verdict is identical", () => {
  assert.strictEqual(fast.trashHandler, shell.trashHandler)
})

test("native mounts are a flat findmnt-shaped list", () => {
  assert.ok(Array.isArray(fast.mounts.filesystems))
  for (const fsEntry of fast.mounts.filesystems) {
    assert.strictEqual(typeof fsEntry.target, "string")
    assert.strictEqual(typeof fsEntry.source, "string")
    assert.strictEqual(typeof fsEntry.fstype, "string")
    assert.strictEqual(typeof fsEntry.options, "string")
    assert.ok(!/\n/.test(fsEntry.options))
  }
})

function flat(node, out) {
  if (!node) return out
  if (Array.isArray(node)) { node.forEach(n => flat(n, out)); return out }
  if (node.target !== undefined) out.push(node)
  if (Array.isArray(node.children)) flat(node.children, out)
  return out
}

test("every real mount findmnt reports is present with the same label, fsroot and fstype", () => {
  const byTarget = new Map(fast.mounts.filesystems.map(m => [m.target, m]))
  for (const m of flat(shell.mounts ? shell.mounts.filesystems : [], [])) {
    const mine = byTarget.get(m.target)
    assert.ok(mine, "missing mount " + m.target)
    assert.strictEqual(mine.fstype, m.fstype, "fstype " + m.target)
    assert.strictEqual(mine.fsroot || "/", m.fsroot || "/", "fsroot " + m.target)
    assert.strictEqual(mine.label || null, m.label || null, "label " + m.target)
    assert.strictEqual(mine.partlabel || null, m.partlabel || null, "partlabel " + m.target)
    assert.strictEqual(mine.source, String(m.source).replace(/\[.*\]$/, ""), "source " + m.target)
    // Every kernel-side option findmnt lists is present; utab options may
    // legitimately appear only in the native answer.
    for (const opt of String(m.options).split(",")) assert.ok(mine.options.split(",").includes(opt), "option " + opt + " on " + m.target)
  }
})

test("PlacesModel builds identical sections from either helper", () => {
  const input = (raw) => ({
    home, userDirs: { DESKTOP: home + "/Desktop", DOWNLOAD: home + "/Downloads", DOCUMENTS: home + "/Documents" },
    settings: { favorites: [tmp, "~/Documents"], showMounts: true, showTrash: true },
    exists: raw.exists, mounts: raw.mounts, trashHandler: raw.trashHandler === true
  })
  assert.deepStrictEqual(P.buildPlaces(input(fast)), P.buildPlaces(input(shell)))
})

fs.rmSync(tmp, { recursive: true, force: true })
console.log("PlacesNative: " + passed + " tests passed")
