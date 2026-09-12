#!/usr/bin/env node
"use strict"

const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "..", "HotbarModel.js"))

let passed = 0
function test(name, fn) {
  try { fn(); passed++ } catch (e) { console.error("FAIL:", name); throw e }
}

// ------------------------------------------------------------ fixtures

const ENTRIES = [
  { id: "chromium", name: "Chromium", icon: "chromium", execString: "/usr/bin/chromium %U", startupClass: "@@startup_wm_class", noDisplay: false },
  { id: "foot", name: "Foot", icon: "foot", execString: "foot", startupClass: "foot", noDisplay: false },
  { id: "visual-studio-code", name: "Visual Studio Code", icon: "vscode", execString: "/usr/bin/code %F", startupClass: "Code", noDisplay: false },
  { id: "discord", name: "Discord", icon: "discord", execString: "/usr/bin/discord", startupClass: "discord", noDisplay: false },
  { id: "YouTube", name: "YouTube", icon: "youtube", execString: "omarchy-launch-webapp https://youtube.com/", startupClass: "", noDisplay: false },
  { id: "suno", name: "Suno", icon: "suno", execString: "chromium --app=https://suno.com/", startupClass: "", noDisplay: false },
  { id: "org.gnome.Nautilus", name: "Files", icon: "org.gnome.Nautilus", execString: "nautilus --new-window %U", startupClass: "", noDisplay: false },
  { id: "steam", name: "Steam", icon: "steam", execString: "/usr/bin/steam %U", startupClass: "Steam", noDisplay: false },
  { id: "Disk Usage", name: "Disk Usage", icon: "", execString: 'xdg-terminal-exec --app-id=TUI.float -e bash -c "dua i /"', startupClass: "", noDisplay: false },
  { id: "spotify", name: "Spotify", icon: "spotify", execString: "spotify %U", startupClass: "", noDisplay: false },
  { id: "chrome-abcdefghijklmnopabcdefghijklmnop-Default", name: "GitHub", icon: "chrome-abc", execString: '/usr/bin/chromium --profile-directory=Default --app-id=abcdefghijklmnopabcdefghijklmnop', startupClass: "crx_abcdefghijklmnopabcdefghijklmnop", noDisplay: false }
]
const INDEX = M.buildEntryIndex(ENTRIES)

function heuristic(token) {
  const t = String(token).toLowerCase()
  if (t === "spotify") return { id: "spotify", name: "Spotify", icon: "spotify" }
  if (t === "nautilus") return { id: "org.gnome.Nautilus", name: "Files" }
  if (t === "tui.float") return { id: "chromium", name: "Chromium" } // a bad fuzzy hit
  return null
}

function win(over) {
  return Object.assign({ address: "a1", appId: "", cls: "", initialClass: "", title: "", workspaceId: 1, workspaceName: "1", monitorName: "DP-1", activated: false, urgent: false }, over)
}

// ------------------------------------------------------------ identity

test("native wayland app resolves by app id", () => {
  const r = M.resolveIdentity({ appId: "foot", cls: "foot", initialClass: "foot" }, INDEX, [], heuristic)
  assert.strictEqual(r.key, "foot"); assert.strictEqual(r.source, "desktop-id"); assert.strictEqual(r.icon, "foot")
})

test("class case differences still resolve", () => {
  const r = M.resolveIdentity({ appId: "Chromium", cls: "Chromium" }, INDEX, [], heuristic)
  assert.strictEqual(r.key, "chromium")
})

test("electron app resolves through StartupWMClass", () => {
  const r = M.resolveIdentity({ appId: "code", cls: "code", initialClass: "code" }, INDEX, [], heuristic)
  assert.strictEqual(r.key, "visual-studio-code"); assert.strictEqual(r.source, "startup-class")
})

test("omarchy web app groups by host, not with chromium", () => {
  const r = M.resolveIdentity({ appId: "chrome-youtube.com__-Default", cls: "chrome-youtube.com__-Default" }, INDEX, [], heuristic)
  assert.strictEqual(r.key, "YouTube"); assert.strictEqual(r.source, "web-app")
  const s = M.resolveIdentity({ appId: "chrome-www.suno.com__-Default" }, INDEX, [], heuristic)
  assert.strictEqual(s.key, "suno")
})

test("installed PWA resolves through crx StartupWMClass", () => {
  const r = M.resolveIdentity({ appId: "crx_abcdefghijklmnopabcdefghijklmnop", cls: "crx_abcdefghijklmnopabcdefghijklmnop" }, INDEX, [], heuristic)
  assert.strictEqual(r.key, "chrome-abcdefghijklmnopabcdefghijklmnop-Default")
})

test("unknown web app gets its own bounded identity", () => {
  const r = M.resolveIdentity({ appId: "chrome-example.org__app-Default" }, INDEX, [], heuristic)
  assert.strictEqual(r.key, "class:chrome-example.org__app-default"); assert.strictEqual(r.name, "Example")
  assert.notStrictEqual(r.key, "chromium")
})

test("chromium normal window stays chromium", () => {
  const r = M.resolveIdentity({ appId: "chromium", cls: "chromium", initialClass: "chromium" }, INDEX, [], heuristic)
  assert.strictEqual(r.key, "chromium")
})

test("heuristic accepted only when plausible", () => {
  const ok = M.resolveIdentity({ appId: "nautilus" }, INDEX, [], heuristic)
  assert.strictEqual(ok.key, "org.gnome.Nautilus")
  const bad = M.resolveIdentity({ appId: "TUI.float" }, INDEX, [], heuristic)
  assert.strictEqual(bad.key, "class:tui.float"); assert.strictEqual(bad.name, "TUI.float")
})

test("terminal custom class is its own identity", () => {
  const a = M.resolveIdentity({ appId: "TUI.tile", cls: "TUI.tile", initialClass: "TUI.tile" }, INDEX, [], heuristic)
  const b = M.resolveIdentity({ appId: "foot" }, INDEX, [], heuristic)
  assert.notStrictEqual(a.key, b.key)
})

test("exec basename fallback", () => {
  const r = M.resolveIdentity({ appId: "nautilus", cls: "nautilus" }, INDEX, [], null)
  assert.strictEqual(r.key, "org.gnome.Nautilus"); assert.strictEqual(r.source, "exec")
})

test("wrappers never become identities", () => {
  assert.strictEqual(INDEX.byExecBase["xdg-terminal-exec"], undefined)
  assert.strictEqual(INDEX.byExecBase["omarchy-launch-webapp"], undefined)
})

test("class differs from initialClass: still one group", () => {
  const a = M.resolveIdentity({ appId: "steam", cls: "steam", initialClass: "Steam" }, INDEX, [], heuristic)
  const b = M.resolveIdentity({ appId: "Steam", cls: "Steam", initialClass: "steam" }, INDEX, [], heuristic)
  assert.strictEqual(a.key, b.key)
})

test("steam games are separate identities named by title", () => {
  const r = M.resolveIdentity({ appId: "steam_app_440", cls: "steam_app_440", title: "Team Fortress 2" }, INDEX, [], heuristic)
  assert.strictEqual(r.key, "class:steam_app_440"); assert.strictEqual(r.name, "Team Fortress 2")
})

test("missing desktop entry falls back to a class identity", () => {
  const r = M.resolveIdentity({ appId: "org.example.Thing", cls: "org.example.Thing" }, INDEX, [], null)
  assert.strictEqual(r.key, "class:org.example.thing"); assert.strictEqual(r.name, "Thing")
})

test("empty window data does not throw", () => {
  const r = M.resolveIdentity({}, INDEX, [], heuristic)
  assert.strictEqual(r.key, "class:unknown")
  assert.strictEqual(M.resolveIdentity(null, null, null, null).key, "class:unknown")
})

test("overrides win and cannot carry commands", () => {
  const ov = M.compileOverrides([
    { name: "Discord", matchClass: "^chrome-discord\\.com.*$", desktopId: "discord" },
    { matchClass: "(((", desktopId: "foot" },
    "junk", null,
    { matchClass: "^Weird$", name: "Weird App", icon: "weird", exec: "rm -rf /" }
  ])
  assert.strictEqual(ov.length, 2)
  const r = M.resolveIdentity({ appId: "chrome-discord.com__-Default" }, INDEX, ov, heuristic)
  assert.strictEqual(r.key, "discord"); assert.strictEqual(r.source, "override"); assert.strictEqual(r.name, "Discord")
  const w = M.resolveIdentity({ appId: "Weird" }, INDEX, ov, heuristic)
  assert.strictEqual(w.key, "class:weird"); assert.strictEqual(w.name, "Weird App"); assert.strictEqual(w.icon, "weird")
  assert.strictEqual(ov[1].exec, undefined)
})

// ----------------------------------------------------------------- MRU

test("mru touch/remove/prune", () => {
  let m = []
  m = M.touchMru(m, "a"); m = M.touchMru(m, "b"); m = M.touchMru(m, "a")
  assert.deepStrictEqual(m, ["a", "b"])
  m = M.removeMru(m, "b"); assert.deepStrictEqual(m, ["a"])
  m = M.touchMru(m, "c"); m = M.pruneMru(m, ["c"]); assert.deepStrictEqual(m, ["c"])
})

test("orderByMru uses focusHistory for unknown windows", () => {
  const list = [{ address: "x", focusHistory: 5 }, { address: "y", focusHistory: 0 }, { address: "z", focusHistory: 2 }]
  assert.deepStrictEqual(M.orderByMru(list, ["z"]).map(w => w.address), ["z", "y", "x"])
})

test("clickTarget: focus MRU, then cycle, wrap, wheel backwards", () => {
  const ordered = [{ address: "a" }, { address: "b" }, { address: "c" }]
  assert.strictEqual(M.clickTarget(ordered, "zzz", 1).address, "a")
  assert.strictEqual(M.clickTarget(ordered, "a", 1).address, "b")
  assert.strictEqual(M.clickTarget(ordered, "c", 1).address, "a")
  assert.strictEqual(M.clickTarget(ordered, "a", -1).address, "c")
  assert.strictEqual(M.clickTarget([{ address: "only" }], "only", 1).address, "only")
  assert.strictEqual(M.clickTarget([], "a", 1), null)
})

// -------------------------------------------------------------- groups

function resolved(over) {
  const w = win(over)
  w.identity = M.resolveIdentity(w, INDEX, [], heuristic)
  return w
}

test("one app, many windows, many workspaces -> one group", () => {
  const windows = []
  for (let i = 0; i < 20; i++) windows.push(resolved({ address: "c" + i, appId: "chromium", title: "Tab " + i, workspaceId: (i % 4) + 1, workspaceName: String((i % 4) + 1) }))
  const g = M.buildGroups(windows, ["chromium", "foot"], [], INDEX, [])
  assert.strictEqual(Object.keys(g.groups).length, 2)
  assert.strictEqual(g.groups.chromium.count, 20)
  assert.strictEqual(g.pinned.length, 2)
  assert.strictEqual(g.pinned[0].key, "chromium"); assert.strictEqual(g.pinned[1].key, "foot")
  assert.strictEqual(g.pinned[1].running, false); assert.strictEqual(g.pinned[1].pinned, true)
  assert.strictEqual(g.running.length, 0)
})

test("pinned order never changes with launches, focus or closes", () => {
  const pins = ["foot", "chromium", "spotify"]
  const a = M.buildGroups([], pins, [], INDEX, []).pinned.map(g => g.key)
  const windows = [resolved({ address: "s1", appId: "spotify", activated: true }), resolved({ address: "f1", appId: "foot" })]
  const b = M.buildGroups(windows, pins, ["s1", "f1"], INDEX, []).pinned.map(g => g.key)
  const c = M.buildGroups(windows.slice(1), pins, ["f1"], INDEX, []).pinned.map(g => g.key)
  assert.deepStrictEqual(a, pins); assert.deepStrictEqual(b, pins); assert.deepStrictEqual(c, pins)
})

test("unpinned running apps are separate, sorted, and never in pinned", () => {
  const windows = [
    resolved({ address: "n1", appId: "nautilus" }),
    resolved({ address: "d1", appId: "discord" }),
    resolved({ address: "t1", appId: "TUI.float" }),
    resolved({ address: "t2", appId: "TUI.float" })
  ]
  const g = M.buildGroups(windows, ["chromium"], [], INDEX, [])
  assert.deepStrictEqual(g.running.map(x => x.key), ["discord", "org.gnome.Nautilus", "class:tui.float"])
  assert.strictEqual(g.groups["class:tui.float"].count, 2)
  assert.strictEqual(g.pinned.length, 1)
})

test("focused and urgent flags", () => {
  const windows = [resolved({ address: "a", appId: "foot", activated: true }), resolved({ address: "b", appId: "foot", urgent: true }), resolved({ address: "c", appId: "discord", urgent: true, activated: false })]
  const g = M.buildGroups(windows, [], [], INDEX, [])
  assert.strictEqual(g.groups.foot.focused, true); assert.strictEqual(g.groups.foot.urgent, true)
  assert.strictEqual(g.groups.discord.urgent, true); assert.strictEqual(g.groups.discord.focused, false)
})

test("group windows are MRU ordered", () => {
  const windows = [resolved({ address: "a", appId: "foot" }), resolved({ address: "b", appId: "foot" }), resolved({ address: "c", appId: "foot" })]
  const g = M.buildGroups(windows, [], ["b", "c"], INDEX, [])
  assert.deepStrictEqual(g.groups.foot.windows.map(w => w.address), ["b", "c", "a"])
})

test("pins normalize, toggle, move, dedupe", () => {
  assert.deepStrictEqual(M.normalizePins(["foot.desktop", { desktopId: "chromium" }, "class:TUI.Float", "", null, "foot"]), ["foot", "chromium", "class:tui.float"])
  assert.deepStrictEqual(M.togglePin(["foot"], "chromium"), ["foot", "chromium"])
  assert.deepStrictEqual(M.togglePin(["foot", "chromium"], "foot"), ["chromium"])
  assert.deepStrictEqual(M.movePin(["a", "b", "c"], "c", -1), ["a", "c", "b"])
  assert.deepStrictEqual(M.movePin(["a", "b", "c"], "a", -1), ["a", "b", "c"])
  assert.deepStrictEqual(M.movePin(["a", "b", "c"], "zzz", 1), ["a", "b", "c"])
})

test("pinned app with a missing desktop entry still gets a cell", () => {
  const g = M.buildGroups([], ["gone-app", "class:tui.tile"], [], INDEX, [])
  assert.strictEqual(g.pinned.length, 2)
  assert.strictEqual(g.pinned[0].name, "Gone-app"); assert.strictEqual(g.pinned[1].name, "Tui.tile")
})

// --------------------------------------------------------- width budget

test("visiblePinCount", () => {
  // cell 27, gap 2, places + running = 2 fixed cells, 2 separators of 9
  assert.strictEqual(M.visiblePinCount(0, 27, 2, 8, 2, 18), 8)      // unknown -> all
  assert.strictEqual(M.visiblePinCount(-5, 27, 2, 8, 2, 18), 8)
  assert.strictEqual(M.visiblePinCount(10000, 27, 2, 8, 2, 18), 8)
  assert.strictEqual(M.visiblePinCount(58 + 18 + 27 * 3 + 2 * 3, 27, 2, 8, 2, 18), 3)
  assert.strictEqual(M.visiblePinCount(58 + 18 + 27 * 3 + 2 * 2, 27, 2, 8, 2, 18), 3)
  assert.strictEqual(M.visiblePinCount(58 + 18 + 27 * 3 + 2 * 2 - 1, 27, 2, 8, 2, 18), 2)
  assert.strictEqual(M.visiblePinCount(70, 27, 2, 8, 2, 18), 0)
})

test("availableExtent per region", () => {
  // bar 1000 wide; left section starts at 8; center occupies 450..550; right starts at 800
  const b = { leftStart: 8, leftEnd: 300, centerStart: 450, centerEnd: 550, rightStart: 800, rightEnd: 992 }
  assert.strictEqual(M.availableExtent("left", 1000, b, 100, 20, 12), 450 - 12 - 8 - 100 - 20)
  assert.strictEqual(M.availableExtent("right", 1000, b, 30, 40, 12), 992 - 550 - 12 - 30 - 40)
  assert.strictEqual(M.availableExtent("center", 1000, b, 0, 0, 12), 2 * Math.min(500 - 300 - 12, 800 - 500 - 12))
  // empty center & right: left widget may use the whole bar
  assert.strictEqual(M.availableExtent("left", 1000, { leftStart: 8 }, 0, 0, 12), 1000 - 12 - 8)
})

// ------------------------------------------------------------ launching

test("launch argv has no shell", () => {
  assert.deepStrictEqual(M.launchArgv("foot.desktop"), ["uwsm-app", "--", "gtk-launch", "foot.desktop"])
  assert.deepStrictEqual(M.launchArgv("Disk Usage"), ["uwsm-app", "--", "gtk-launch", "Disk Usage.desktop"])
  assert.strictEqual(M.launchArgv(""), null)
  // Only real desktop ids reach gtk-launch: no paths, options, or control bytes.
  assert.strictEqual(M.launchArgv("../../tmp/evil"), null)
  assert.strictEqual(M.launchArgv("/usr/share/applications/foot"), null)
  assert.strictEqual(M.launchArgv("--help"), null)
  assert.strictEqual(M.launchArgv("foot\nbar"), null)
  assert.strictEqual(M.isDesktopId("org.gnome.Nautilus"), true)
  assert.deepStrictEqual(M.actionArgv(["/usr/bin/chromium", "--new-window", "$(rm -rf /)"]), ["uwsm-app", "--", "/usr/bin/chromium", "--new-window", "$(rm -rf /)"])
  assert.strictEqual(M.actionArgv([]), null)
})

test("newWindowAction detection", () => {
  assert.strictEqual(M.newWindowAction([{ id: "new-private-window", name: "New Private Window" }, { id: "new-window", name: "New Window" }]).id, "new-window")
  assert.strictEqual(M.newWindowAction([{ id: "NewWindow", name: "Open a New Window" }]).id, "NewWindow")
  assert.strictEqual(M.newWindowAction([{ id: "profile", name: "Profile Manager" }]), null)
  assert.strictEqual(M.newWindowAction(null), null)
})

test("windowLocation", () => {
  assert.strictEqual(M.windowLocation({ workspaceId: 3, workspaceName: "3", monitorName: "DP-2" }), "Workspace 3 · DP-2")
  assert.strictEqual(M.windowLocation({ workspaceId: -99, workspaceName: "special:scratch", monitorName: "DP-2" }), "Special · DP-2")
  assert.strictEqual(M.windowLocation({ workspaceId: 2, workspaceName: "mail", monitorName: "" }), "mail")
})

test("brutal scenario: 60 windows across 4 pins -> 4 pinned cells, bounded running", () => {
  const pins = ["chromium", "foot", "spotify", "YouTube"]
  const windows = []
  for (let i = 0; i < 10; i++) windows.push(resolved({ address: "c" + i, appId: "chromium", title: "Site " + i }))
  for (let i = 0; i < 10; i++) windows.push(resolved({ address: "f" + i, appId: "foot", title: "sh " + i }))
  for (let i = 0; i < 5; i++) windows.push(resolved({ address: "y" + i, appId: "chrome-youtube.com__-Default" }))
  windows.push(resolved({ address: "s", appId: "spotify" }))
  for (let i = 0; i < 20; i++) windows.push(resolved({ address: "u" + i, appId: "org.random.App" + (i % 7) }))
  for (let i = 0; i < 14; i++) windows.push(resolved({ address: "t" + i, appId: "TUI.float" }))
  const g = M.buildGroups(windows, pins, [], INDEX, [])
  assert.strictEqual(g.pinned.length, 4)
  assert.deepStrictEqual(g.pinned.map(x => x.key), pins)
  assert.strictEqual(g.running.length, 8)
  assert.strictEqual(M.visiblePinCount(400, 27, 2, g.pinned.length, 2, 18), 4)
})

console.log("HotbarModel: " + passed + " tests passed")
