#!/usr/bin/env node
"use strict"

// 0.2.3 UI/control boundary: the Settings "Keep pointer in place" toggle
// over the 0.2.2 `hotbar warp` backend.
//
// Pure-logic tests run against WarpModel.js; wiring tests read the QML to
// prove the popover queries real state on open, confirms after apply, never
// polls, never duplicates the config handling, and keeps every 0.2.2 row.

const assert = require("assert")
const fs = require("fs")
const path = require("path")

const W = require(path.join(__dirname, "..", "WarpModel.js"))

const ROOT = path.join(__dirname, "..")
const read = (p) => fs.readFileSync(path.join(ROOT, p), "utf8")
const hotbarQml = read("Hotbar.qml")
const settingsQml = read("components/SettingsPopover.qml")
const cli = read("bin/hotbar")

let passed = 0
function test(name, fn) {
  try { fn(); passed++ } catch (e) { console.error("FAIL:", name); throw e }
}

// ---------------------------------------------------------------- mapping

const DISABLED_OUT = "no_warps=true warp_workspace=0 warp_special=0\nwarps disabled\n"
const ENABLED_OUT = "no_warps=false warp_workspace=1 warp_special=0\nwarps enabled (pointer jumps to center on Hotbar focus; run: hotbar warp off)\n"
const UNKNOWN_OUT = "unknown: hyprctl not found or cursor options unreadable\n"

test("1: warp disabled reports Keep pointer in place = ON", () => {
  const parsed = W.parseWarpStatus(DISABLED_OUT, 0)
  assert.strictEqual(parsed.state, "disabled")
  assert.strictEqual(W.keepPointerInPlace(parsed.state), true)
  const row = W.rowData(parsed.state, false)
  assert.strictEqual(row.keep, true)
  assert.strictEqual(row.trailing, "On")
  assert.strictEqual(row.enabled, true)
})

test("2: warp enabled reports Keep pointer in place = OFF", () => {
  const parsed = W.parseWarpStatus(ENABLED_OUT, 1)
  assert.strictEqual(parsed.state, "enabled")
  assert.strictEqual(W.keepPointerInPlace(parsed.state), false)
  const row = W.rowData(parsed.state, false)
  assert.strictEqual(row.keep, false)
  assert.strictEqual(row.trailing, "Off")
  assert.strictEqual(row.enabled, true)
})

test("3: unknown never presents a confirmed state", () => {
  for (const [out, code] of [
    [UNKNOWN_OUT, 2],
    ["", 2],
    ["", 0],
    ["garbage without markers", 0],
    ["garbage without markers", 1],
    [DISABLED_OUT, 2], // backend says unknown: trust it over the body
    [DISABLED_OUT, 99],
    ["", 127], // CLI missing
  ]) {
    const parsed = W.parseWarpStatus(out, code)
    assert.strictEqual(parsed.state, "unknown", JSON.stringify([out, code]))
    assert.strictEqual(W.keepPointerInPlace(parsed.state), null)
    const row = W.rowData(parsed.state, false)
    assert.strictEqual(row.keep, null)
    assert.strictEqual(row.enabled, false)
    assert.ok(row.trailing === "Unavailable", "indeterminate trailing, got " + row.trailing)
  }
})

test("4: toggle ON invokes the equivalent of `hotbar warp off`", () => {
  assert.strictEqual(W.warpModeForKeep(true), "off")
  const argv = W.warpArgv("/plugin/dir", W.warpModeForKeep(true))
  assert.deepStrictEqual(argv, ["/plugin/dir/bin/hotbar", "warp", "off"])
})

test("5: toggle OFF invokes the equivalent of `hotbar warp on`", () => {
  assert.strictEqual(W.warpModeForKeep(false), "on")
  const argv = W.warpArgv("/plugin/dir", W.warpModeForKeep(false))
  assert.deepStrictEqual(argv, ["/plugin/dir/bin/hotbar", "warp", "on"])
})

test("6: failed apply returns the UI to actual state, not desired state", () => {
  // The QML never sets warpState optimistically; after a failed apply it
  // re-reads. Whatever the re-read confirms is what the row shows — even
  // when the user just asked for the opposite.
  assert.strictEqual(W.warpModeForKeep(null), null)
  assert.strictEqual(W.warpModeForKeep(undefined), null)
  const actual = W.parseWarpStatus(ENABLED_OUT, 1) // user wanted ON, still enabled
  assert.strictEqual(W.keepPointerInPlace(actual.state), false)
  assert.strictEqual(W.rowData(actual.state, false).trailing, "Off")
  // Busy (apply in flight) claims nothing permanently.
  const busy = W.rowData("enabled", true)
  assert.strictEqual(busy.trailing, "…")
  assert.strictEqual(busy.enabled, false)
})

// ------------------------------------------------------------- presentation

test("wording: behavior language, system-wide disclosure, no impl jargon", () => {
  const row = W.rowData("disabled", false)
  assert.strictEqual(row.primary, "Keep pointer in place")
  assert.ok(row.secondary.includes("Prevent Hyprland from moving the pointer when Hotbar focuses a window."),
    "supporting text missing")
  assert.ok(row.secondary.includes("Applies system-wide to Hyprland."),
    "system-wide disclosure missing")
  const banned = ["warp_on_change_workspace", "no_warps", "Cursor Warp Override",
    "Disable Warps", "Hyprland Warp Setting", "cursor:no_warps"]
  for (const b of banned) assert.ok(!row.primary.includes(b), "banned primary label: " + b)
  const unknownRow = W.rowData("unknown", false)
  assert.strictEqual(unknownRow.primary, "Keep pointer in place")
  assert.ok(unknownRow.secondary.includes("Applies system-wide to Hyprland."))
  assert.ok(String(W.APPLY_ERROR).length > 0 && String(W.APPLY_ERROR).length < 80,
    "error line must stay a concise inline message")
})

test("argv boundary: discrete array, allowlisted modes only", () => {
  assert.strictEqual(W.warpArgv("/p", "status").join(" "), "/p/bin/hotbar warp status")
  assert.strictEqual(W.warpArgv("/p", "off; rm -rf ~"), null)
  assert.strictEqual(W.warpArgv("/p", "status --json"), null)
  assert.strictEqual(W.warpArgv("", "status"), null)
  assert.strictEqual(W.warpArgv("/p", ""), null)
})

// ------------------------------------------------------------------ wiring

test("7: reopening Settings re-reads real system state", () => {
  assert.ok(/onOpenPopoverChanged[\s\S]*?openPopover\s*===\s*"settings"[\s\S]*?refreshWarpState\(\)/.test(hotbarQml),
    "Settings open must trigger a warp state refresh")
  assert.ok(/function refreshWarpState\(\)[\s\S]*?warpArgv\(pluginDir,\s*"status"\)/.test(hotbarQml),
    "refresh must query the existing backend via discrete argv")
  assert.ok(/warpApplyProc[\s\S]*?onExited[\s\S]*?refreshWarpState\(\)/.test(hotbarQml),
    "apply completion must re-read actual state")
  assert.ok(settingsQml.includes("hotbar.warpState") && settingsQml.includes("hotbar.warpBusy"),
    "Settings rows must depend on live warp state, not a cached preference")
  assert.ok(/warpDep/.test(settingsQml), "rows binding must rebuild on warp changes")
})

test("8: no background polling for warp state", () => {
  const timerBlocks = hotbarQml.match(/Timer\s*\{[\s\S]*?\n\s*\}/g) || []
  for (const block of timerBlocks) {
    assert.ok(!/warp/i.test(block), "warp must not be driven by a Timer: " + block.slice(0, 120))
  }
  const settingsTimers = settingsQml.match(/Timer\s*\{[\s\S]*?\n\s*\}/g) || []
  assert.strictEqual(settingsTimers.length, 0, "Settings popover must not poll")
  const callers = (hotbarQml.match(/refreshWarpState\(\)/g) || []).length
  // Definition + open handler + apply-exit + apply-error paths only.
  assert.ok(callers >= 3 && callers <= 5, "unexpected refresh call sites: " + callers)
})

test("9: existing Settings controls keep working", () => {
  const labels = ["Icon size", "Cell spacing", "Icon style", "Running indicator",
    "Section separators", "Animations", "Hover previews", "Preview delay",
    "Mouse wheel cycles windows", "Middle click", "Responsive overflow",
    "Show Places", "Show Running drawer", "Desktop", "Downloads", "Documents",
    "Pictures", "Music", "Videos", "Trash", "Mounted drives"]
  for (const label of labels) assert.ok(settingsQml.includes('"' + label + '"'), "missing row: " + label)
  const behaviourIdx = settingsQml.indexOf('"Behaviour"')
  const warpIdx = settingsQml.indexOf("out.push(warpRow())")
  const cellsIdx = settingsQml.indexOf('"Visible cells"')
  assert.ok(behaviourIdx !== -1 && warpIdx > behaviourIdx && cellsIdx > warpIdx,
    "warp control must sit under Behaviour without moving other sections")
  assert.ok(settingsQml.includes("Pins, favourites, overrides via CLI"),
    "CLI hint footer must survive")
})

test("no duplicated warp implementation in QML", () => {
  for (const [name, src] of [["Hotbar.qml", hotbarQml], ["SettingsPopover.qml", settingsQml]]) {
    for (const banned of ["looknfeel", "no_warps", "warp_on_change", "warp_on_toggle", "hl.config"]) {
      assert.ok(!src.includes(banned), name + " duplicates backend detail: " + banned)
    }
  }
  assert.ok(!/execDetached\(\s*["'`]hotbar/.test(hotbarQml), "warp must not go through a shell string")
  assert.ok(/\.command\s*=\s*argv/.test(hotbarQml), "backend must be invoked via discrete Process argv")
})

test("failure surfaces inline without modal spam", () => {
  assert.ok(/warpError\s*=\s*Warp\.APPLY_ERROR/.test(hotbarQml), "apply failure must set the inline error")
  assert.ok(/danger:\s*true/.test(settingsQml), "error row must reuse the danger treatment")
  assert.ok(/onErrorOccurred[\s\S]*?warpState\s*=\s*"unknown"/.test(hotbarQml),
    "helper failure must fall back to indeterminate, never a guess")
})

test("0.2.2 CLI surface unchanged", () => {
  assert.ok(cli.includes("warp status"), "warp status missing")
  assert.ok(cli.includes("warp off"), "warp off missing")
  assert.ok(cli.includes("warp on"), "warp on missing")
  assert.ok(/cmd_warp_status|warp_read_state/.test(cli), "backend reader missing")
  assert.ok(cli.includes("doctor"), "doctor missing")
})

console.log("WarpUI: " + passed + " tests passed")
