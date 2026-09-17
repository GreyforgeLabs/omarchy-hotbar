import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "HotbarModel.js" as Model
import "PlacesModel.js" as Places
import "HotbarRegistry.js" as Registry
import "WarpModel.js" as Warp
import "components"

// Hotbar — Places, pinned apps, and one Running drawer.
//
// The permanent surface is a fixed row of cells: [Places] [pins…] [Running].
// Windows never become cells. Every window belongs to exactly one
// ApplicationGroup (HotbarModel.js), every group owns at most one cell, and
// groups that are neither pinned nor visible collapse into Running.
//
// State lives here once; cells and popovers only bind to it.
BarWidget {
  id: root
  moduleName: "greyforge.hotbar"

  // ------------------------------------------------------------ settings

  // The host injects `settings` from its in-memory layout entry, but after a
  // plugin hot-reload that copy can predate the last inline settings write
  // (pins persisted a moment ago would silently vanish). shell.json on disk
  // is the durable truth, so it is watched and preferred; the injected
  // object is the fallback when the user has no shell.json yet.
  property var fileSettings: null
  readonly property var effectiveSettings: fileSettings || settings || ({})

  function setting(name, fallback) {
    var source = effectiveSettings
    var value = source ? source[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  FileView {
    id: shellConfigFile
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    onLoaded: root.fileSettings = root.readOwnEntry(text())
    onLoadFailed: root.fileSettings = null
    onFileChanged: reload()
  }

  function readOwnEntry(raw) {
    var parsed
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { return null }
    if (!parsed || typeof parsed !== "object") return null
    var layout = parsed.bar && parsed.bar.layout ? parsed.bar.layout : null
    var sections = ["left", "center", "right"]
    if (layout) {
      for (var s = 0; s < sections.length; s++) {
        var list = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
        for (var i = 0; i < list.length; i++) {
          var entry = list[i]
          if (entry && typeof entry === "object" && String(entry.id || "") === moduleName) {
            var copy = {}
            for (var k in entry) if (k !== "id") copy[k] = entry[k]
            return copy
          }
        }
      }
    }
    return null
  }

  // Disabling a bar widget removes its layout entry, and enabling it again
  // creates a bare one — the host forgets pins, favourites and overrides.
  // A small mirror under ~/.local/state brings them back when the entry has
  // never held any (a deliberately emptied pin list is left alone).
  readonly property string backupPath: Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") + "/omarchy/hotbar-settings.json" : home + "/.local/state/omarchy/hotbar-settings.json"
  property var backupSettings: null
  property bool restoreAttempted: false

  FileView {
    id: backupFile
    path: root.backupPath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var raw = text()
      try { root.backupSettings = JSON.parse(raw) } catch (e) { root.backupSettings = null }
      if (root.backupSettings) root.lastBackupText = raw
      root.maybeRestoreBackup()
    }
    onLoadFailed: root.backupSettings = null
  }

  onFileSettingsChanged: maybeRestoreBackup()

  function maybeRestoreBackup() {
    if (restoreAttempted || !fileSettings || !backupSettings || typeof backupSettings !== "object") return
    if ("pins" in fileSettings) return
    var patch = {}
    var keys = ["pins", "favorites", "matches"]
    for (var i = 0; i < keys.length; i++) if (Array.isArray(backupSettings[keys[i]]) && backupSettings[keys[i]].length) patch[keys[i]] = backupSettings[keys[i]]
    restoreAttempted = true
    if (Object.keys(patch).length) {
      console.log("Hotbar: restoring pins/favourites/overrides from " + backupPath)
      persistSettings(patch)
    }
  }

  property string lastBackupText: ""
  function writeBackup(next) {
    var copy = {}
    var keys = ["pins", "favorites", "matches"]
    for (var i = 0; i < keys.length; i++) if (Array.isArray(next[keys[i]])) copy[keys[i]] = next[keys[i]]
    var text = JSON.stringify(copy, null, 2) + "\n"
    if (text === lastBackupText) return
    lastBackupText = text
    try { backupFile.setText(text) } catch (e) {}
  }

  readonly property var pins: Model.normalizePins(setting("pins", []))
  readonly property var overrideRules: Model.compileOverrides(setting("matches", []))
  readonly property int iconSize: clampInt(setting("iconSize", 18), 12, 24)
  readonly property int cellSpacing: clampInt(setting("spacing", 2), 0, 12)
  readonly property bool monoIcons: String(setting("iconStyle", "color")) === "mono"
  readonly property string runningIndicator: String(setting("runningIndicator", "underline"))
  readonly property bool separators: setting("separators", true) !== false
  readonly property bool previewsEnabled: setting("previews", true) !== false
  readonly property int previewDelay: clampInt(setting("previewDelay", 450), 100, 1500)
  readonly property bool animationsEnabled: setting("animations", true) !== false && (bar ? bar.foregroundAnimationEnabled !== false : true)
  readonly property bool flameEnabled: setting("flame", true) !== false
  readonly property string placesStyle: String(setting("placesStyle", "minimal"))
  readonly property bool wheelCycle: setting("wheelCycle", true) !== false
  readonly property string middleClick: String(setting("middleClick", "new-window"))
  readonly property bool showPlaces: setting("showPlaces", true) !== false
  readonly property bool showRunning: setting("showRunning", true) !== false
  readonly property bool responsive: setting("responsive", true) !== false

  function clampInt(value, min, max) {
    var n = Math.round(Number(value))
    if (!isFinite(n)) n = min
    return Math.max(min, Math.min(max, n))
  }

  // ------------------------------------------------------------- theme

  readonly property color foreground: bar ? bar.barForeground : Color.bar.text
  readonly property color popupForeground: Color.popups.text
  readonly property color accentColor: Color.accent
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  // Greyforge Labs brand colours (fixed, theme-independent): the cyan
  // structural seam and the single amber core of the mark.
  readonly property color brandCyan: "#38c8e8"
  readonly property color brandAmber: "#fda52b"
  // Version string from the plugin's own manifest, for the Settings eyebrow.
  property string version: ""
  FileView {
    path: root.pluginDir + "/manifest.json"
    printErrors: false
    onLoaded: { try { root.version = "v" + String(JSON.parse(text()).version || "") } catch (e) { root.version = "" } }
  }
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real devicePixelRatio: {
    var w = root.QsWindow.window
    return w && w.screen ? Math.max(1, w.screen.devicePixelRatio) : 1
  }
  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    return url.indexOf("file://") === 0 ? url.slice(7).replace(/\/+$/, "") : url
  }

  // ---------------------------------------------------------- geometry

  // Cells are approximately square against the bar thickness; the icon may
  // be smaller than the hit target but the target never shrinks.
  readonly property real cellExtent: Math.max(Style.bar.iconSlot, iconSize + 8)
  // The Places cell is the HOTBAR badge, longer than a pin cell; it reports
  // its own extent so the pin budget and the surface size stay honest.
  readonly property real placesExtent: placesCellLoader.item ? (vertical ? placesCellLoader.item.implicitHeight : placesCellLoader.item.implicitWidth) : cellExtent
  readonly property real separatorExtent: separators ? Style.space(9) : 0

  // ------------------------------------------------------- app identity

  property var entryIndex: Model.buildEntryIndex([])
  property var identityCache: ({})

  function refreshEntryIndex() {
    var values = DesktopEntries.applications.values || []
    var list = []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e) continue
      list.push({ id: e.id, name: e.name, icon: e.icon, execString: e.execString, startupClass: e.startupClass, noDisplay: e.noDisplay })
    }
    entryIndex = Model.buildEntryIndex(list)
    identityCache = ({})
    iconCache = ({})
    scheduleRebuild()
  }

  function heuristic(token) {
    var found = DesktopEntries.heuristicLookup(String(token || ""))
    return found ? { id: found.id, name: found.name, icon: found.icon, startupClass: found.startupClass } : null
  }

  function entryFor(desktopId) {
    var id = String(desktopId || "")
    if (!id) return null
    return DesktopEntries.byId(id) || DesktopEntries.byId(id + ".desktop") || null
  }

  function identityFor(toplevel) {
    var ipc = toplevel.lastIpcObject || {}
    var wl = toplevel.wayland
    var appId = wl ? String(wl.appId || "") : ""
    var cls = String(ipc["class"] || "")
    var initialClass = String(ipc.initialClass || "")
    var cacheKey = appId + "\u0001" + cls + "\u0001" + initialClass
    var cached = identityCache[cacheKey]
    if (cached && !/^steam_app_/i.test(appId || cls)) return cached
    var ident = Model.resolveIdentity({ appId: appId, cls: cls, initialClass: initialClass, title: toplevel.title }, entryIndex, overrideRules, heuristic)
    identityCache[cacheKey] = ident
    // Cache keys are (appId, class, initialClass) triples; ephemeral random
    // ids must not grow this object without bound.
    if (Object.keys(identityCache).length > 1024) identityCache = ({})
    return ident
  }

  // ----------------------------------------------------- window model

  property var mru: []
  property var groups: ({})
  property var pinnedGroups: []
  property var runningGroups: []
  property int revision: 0
  // Hyprland.activeToplevel is null until the first focus change after the
  // shell starts, so the foreign-toplevel `activated` flag (correct from the
  // first frame) and the compositor's focus history back it up.
  // Hyprland.activeToplevel also flips to null for a moment between two
  // focus changes; the last non-null value bridges that gap.
  readonly property string activeAddress: {
    var tl = Hyprland.activeToplevel
    if (tl && tl.address) return String(tl.address)
    return lastActiveAddress || fallbackActiveAddress
  }
  property string lastActiveAddress: ""
  property string fallbackActiveAddress: ""

  function detectActiveAddress(values) {
    var best = "", bestRank = 1e9
    for (var i = 0; i < values.length; i++) {
      var tl = values[i]
      if (!tl) continue
      if (tl.wayland && tl.wayland.activated) return String(tl.address || "")
      var ipc = tl.lastIpcObject || {}
      if (typeof ipc.focusHistoryID === "number" && ipc.focusHistoryID < bestRank) { bestRank = ipc.focusHistoryID; best = String(tl.address || "") }
    }
    return best
  }

  function snapshot(toplevel) {
    var ipc = toplevel.lastIpcObject || {}
    return {
      address: String(toplevel.address || ""),
      toplevel: toplevel,
      identity: identityFor(toplevel),
      title: String(toplevel.title || ""),
      activated: String(toplevel.address || "") === activeAddress,
      urgent: toplevel.urgent === true,
      focusHistory: typeof ipc.focusHistoryID === "number" ? ipc.focusHistoryID : undefined
    }
  }

  function rebuild() {
    var values = Hyprland.toplevels.values || []
    fallbackActiveAddress = detectActiveAddress(values)
    var windows = []
    var live = []
    for (var i = 0; i < values.length; i++) {
      var tl = values[i]
      if (!tl) continue
      var ipc = tl.lastIpcObject || {}
      // Unmapped / hidden windows (Reprieve-parked, special scratchpads that
      // are hidden) still belong to their app; only skip what Hyprland says
      // is not a real client yet.
      if (ipc.mapped === false) continue
      windows.push(snapshot(tl))
      live.push(String(tl.address || ""))
    }
    mru = Model.pruneMru(mru, live)
    var built = Model.buildGroups(windows, pins, mru, entryIndex, overrideRules)
    groups = built.groups
    var pinCountChanged = built.pinned.length !== pinnedGroups.length
    pinnedGroups = built.pinned
    runningGroups = built.running
    revision++
    // The budget depends on how many pins exist and on the bar's geometry
    // (watched separately) — not on which window has focus.
    if (pinCountChanged) scheduleLayout()
  }

  Timer {
    id: rebuildTimer
    interval: 0
    onTriggered: root.rebuild()
  }
  function scheduleRebuild() { rebuildTimer.restart() }

  function groupByKey(key) {
    return groups[String(key || "")] || null
  }

  function isPinned(key) {
    return pins.indexOf(String(key || "")) !== -1
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.scheduleRebuild() }
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      var tl = Hyprland.activeToplevel
      if (tl && tl.address) {
        root.lastActiveAddress = String(tl.address)
        root.mru = Model.touchMru(root.mru, root.lastActiveAddress)
      }
      root.scheduleRebuild()
    }
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      // Focus is tracked through activeToplevel; these are the remaining
      // events that change identity, location or attention state.
      if (name === "urgent" || name === "movewindowv2" || name === "changefloatingmode" || name === "configreloaded") root.scheduleRebuild()
    }
  }

  // Per-window identity inputs can change after the window appears (app id
  // arrives late, lastIpcObject filled in, urgency raised). Watch each one.
  Instantiator {
    model: Hyprland.toplevels
    delegate: QtObject {
      required property var modelData
      readonly property var wl: modelData ? modelData.wayland : null
      property Connections tl: Connections {
        target: modelData
        ignoreUnknownSignals: true
        function onLastIpcObjectChanged() { root.scheduleRebuild() }
        function onUrgentChanged() { root.scheduleRebuild() }
        function onWaylandHandleChanged() { root.scheduleRebuild() }
      }
      property Connections wlc: Connections {
        target: wl
        ignoreUnknownSignals: true
        function onAppIdChanged() { root.scheduleRebuild() }
        function onActivatedChanged() { root.scheduleRebuild() }
      }
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.refreshEntryIndex() }
  }

  onPinsChanged: scheduleRebuild()
  onOverrideRulesChanged: { identityCache = ({}); iconCache = ({}); scheduleRebuild() }
  // A theme switch may bring a different icon theme; drop cached lookups.
  onForegroundChanged: iconCache = ({})

  // Screen-addressed IPC: every instance announces itself by screen name.
  readonly property string screenName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""
  property string registeredScreen: ""
  onScreenNameChanged: {
    Registry.unregister(registeredScreen, root)
    registeredScreen = screenName
    Registry.register(registeredScreen, root)
    root.resetLayoutProbe()
  }
  Component.onDestruction: Registry.unregister(registeredScreen, root)

  Component.onCompleted: {
    refreshEntryIndex()
    Hyprland.refreshToplevels()
    scheduleRebuild()
    resetLayoutProbe()
  }

  // ---------------------------------------------------------- actions

  // Window addresses are hex from the compositor; anything else is refused
  // before it can reach a dispatcher string.
  function safeAddress(toplevel) {
    var addr = String(toplevel && toplevel.address ? toplevel.address : "").replace(/^0x/, "")
    return /^[0-9a-fA-F]{1,16}$/.test(addr) ? addr : ""
  }

  // Omarchy 4.x configures Hyprland in Lua, where dispatchers take the
  // `hl.dsp.*` form (the same one the host's Workspaces widget sends). The
  // request goes straight down the IPC socket — no process, no shell.
  function focusWindow(toplevel) {
    var addr = safeAddress(toplevel)
    if (!addr) return
    Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + addr + '" })')
    hidePreview()
  }

  function closeWindow(toplevel) {
    var addr = safeAddress(toplevel)
    if (!addr) return
    Hyprland.dispatch('hl.dsp.window.close({ window = "address:0x' + addr + '" })')
  }

  function canLaunch(group) {
    return !!group && !!group.desktopId && !!entryFor(group.desktopId)
  }

  // Only desktop entries the host can see are launchable: a pin whose entry
  // was uninstalled, or a hand-written key, must never reach gtk-launch.
  function launch(group) {
    if (!canLaunch(group)) return
    var argv = Model.launchArgv(group.desktopId)
    if (argv) Quickshell.execDetached(argv)
  }

  function newWindow(group) {
    if (!group) return
    var entry = entryFor(group.desktopId)
    if (entry) {
      var action = Model.newWindowAction(entry.actions)
      var argv = action ? Model.actionArgv(action.command) : null
      if (argv) { Quickshell.execDetached(argv); return }
    }
    launch(group)
  }

  // Left click: launch when nothing runs, focus MRU when the group is not
  // active, otherwise step through the group's windows.
  function activateGroup(group) {
    if (!group) return
    var live = groupByKey(group.key) || group
    if (!live.windows.length) { launch(live); return }
    var target = Model.clickTarget(live.windows, activeAddress, 1)
    if (target) focusWindow(target.toplevel)
  }

  function cycleGroup(group, direction) {
    if (!group) return ""
    var live = groupByKey(group.key) || group
    if (live.windows.length < 2) {
      if (live.windows.length === 1 && !live.focused) focusWindow(live.windows[0].toplevel)
      return live.windows.length ? live.windows[0].address : ""
    }
    var target = Model.clickTarget(live.windows, activeAddress, direction)
    if (target) focusWindow(target.toplevel)
    return target ? target.address : ""
  }

  // Wheel over the Running cell: step through every window behind the
  // drawer in MRU order.
  function cycleDrawer(direction) {
    var wins = []
    var lists = [overflowPins, runningGroups]
    for (var l = 0; l < lists.length; l++)
      for (var g = 0; g < lists[l].length; g++) wins = wins.concat(lists[l][g].windows)
    if (!wins.length) return
    var target = Model.clickTarget(Model.orderByMru(wins, mru), activeAddress, direction)
    if (target) focusWindow(target.toplevel)
  }

  function closeCurrent(group) {
    var live = groupByKey(group ? group.key : "") || group
    if (!live || !live.windows.length) return
    closeWindow(live.windows[0].toplevel)
  }

  function closeAll(group) {
    var live = groupByKey(group ? group.key : "") || group
    if (!live) return
    var wins = live.windows.slice()
    for (var i = 0; i < wins.length; i++) closeWindow(wins[i].toplevel)
  }

  // Pins persist through the host's own settings writer: the whole entry is
  // rewritten atomically, and nothing else about the layout is touched.
  function persistSettings(patch) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") {
      console.warn("Hotbar: cannot persist settings (no shell facade)")
      return false
    }
    var next = {}
    var current = effectiveSettings || {}
    for (var k in current) next[k] = current[k]
    for (var p in patch) next[p] = patch[p]
    // The host reports "nothing changed" as a failure; it is not one.
    if (JSON.stringify(next) === JSON.stringify(current)) return true
    var ok = bar.shell.updateEntryInline(moduleName, next)
    if (ok) {
      // shell.json is rewritten asynchronously; take the new values now so
      // a second write arriving before the file watcher fires cannot start
      // from the old ones and drop this change.
      fileSettings = next
      writeBackup(next)
    }
    return ok
  }

  function togglePin(key) {
    persistSettings({ pins: Model.togglePin(pins, key) })
  }

  function movePin(key, delta) {
    persistSettings({ pins: Model.movePin(pins, key, delta) })
  }

  // --------------------------------------------------------------- icons

  // Icon theme lookups hit the filesystem; identities are stable, so each
  // (key, icon, name) triple is resolved once per entry-index generation.
  property var iconCache: ({})

  function iconSourceFor(group) {
    if (!group) return ""
    var icon = String(group.icon || "")
    if (icon.indexOf("/") === 0) return "file://" + icon
    if (icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0) return icon
    var cacheKey = String(group.key || "") + "\u0001" + icon + "\u0001" + String(group.desktopId || "") + "\u0001" + String(group.name || "")
    var hit = iconCache[cacheKey]
    if (hit !== undefined) return hit
    var path = lookupIconPath(group, icon)
    iconCache[cacheKey] = path
    return path
  }

  function lookupIconPath(group, icon) {
    var path = icon ? Quickshell.iconPath(icon, true) : ""
    if (!path && group.desktopId) path = Quickshell.iconPath(String(group.desktopId), true)
    if (!path && String(group.key || "").indexOf(Model.CLASS_PREFIX) === 0) {
      var token = String(group.key).slice(Model.CLASS_PREFIX.length)
      path = Quickshell.iconPath(token, true)
      if (!path && token.indexOf(".") !== -1) path = Quickshell.iconPath(token.split(".").pop(), true)
    }
    if (!path && group.name) path = Quickshell.iconPath(String(group.name).toLowerCase(), true)
    return path || ""
  }

  function locationLabel(toplevel) {
    if (!toplevel) return ""
    var ws = toplevel.workspace
    var mon = toplevel.monitor
    return Model.windowLocation({
      workspaceId: ws ? ws.id : NaN,
      workspaceName: ws ? ws.name : "",
      monitorName: mon ? mon.name : ""
    })
  }

  // -------------------------------------------------------------- places

  property var placesSections: []
  property var placesRaw: null
  property var userDirs: ({})

  FileView {
    id: userDirsFile
    path: root.home + "/.config/user-dirs.dirs"
    watchChanges: true
    onLoaded: root.userDirs = Places.parseUserDirs(text(), root.home)
    onLoadFailed: root.userDirs = ({})
    onFileChanged: reload()
  }

  function placesInput() {
    return {
      home: root.home,
      userDirs: root.userDirs,
      settings: {
        favorites: setting("favorites", []),
        showDesktop: setting("showDesktop", true) !== false,
        showDownloads: setting("showDownloads", true) !== false,
        showDocuments: setting("showDocuments", true) !== false,
        showPictures: setting("showPictures", true) !== false,
        showMusic: setting("showMusic", true) !== false,
        showVideos: setting("showVideos", true) !== false,
        showTrash: setting("showTrash", true) !== false,
        showMounts: setting("showMounts", true) !== false
      },
      exists: placesRaw ? placesRaw.exists : {},
      mounts: placesRaw ? placesRaw.mounts : null,
      trashHandler: placesRaw ? placesRaw.trashHandler === true : false
    }
  }

  function refreshPlaces() {
    // Build immediately from what we know so the popover opens instantly,
    // then let the helper refine (existence, mounts, trash) when it returns.
    placesSections = Places.buildPlaces(placesInput())
    if (placesProcess.running) return
    placesProcess.command = [root.pluginDir + "/bin/hotbar-places"].concat(Places.candidatePaths(placesInput()))
    placesProcess.running = true
    placesWatchdog.restart()
  }

  Process {
    id: placesProcess
    stdout: StdioCollector {
      onStreamFinished: {
        placesWatchdog.stop()
        try {
          root.placesRaw = JSON.parse(text)
        } catch (e) {
          // Killed by the watchdog, or garbage: keep the last good answer.
        }
        root.placesSections = Places.buildPlaces(root.placesInput())
      }
    }
  }

  // `test -d` on a dead network mount can block indefinitely. The helper is
  // given a few seconds; after that the popover keeps what it already knows.
  Timer {
    id: placesWatchdog
    interval: 3000
    onTriggered: if (placesProcess.running) { console.warn("Hotbar: places helper timed out"); placesProcess.running = false }
  }

  function openPlace(path) {
    var argv = Places.openArgv(path)
    if (argv) Quickshell.execDetached(argv)
  }

  // -------------------------------------------------- cursor warp (0.2.3)

  // "Keep pointer in place" toggle state. The 0.2.2 `hotbar warp` CLI is
  // the source of truth; this only queries it (on Settings open) and runs
  // it (on toggle) through discrete argv — no shell, no duplicated config
  // handling. warpState: "disabled" (warps off, Keep ON) | "enabled"
  // (warps on, Keep OFF) | "unknown" (indeterminate, never guessed).
  // warpBusy covers the opening query and the apply+re-read cycle; the UI
  // shows "…" and disables the row rather than claiming a state.
  property string warpState: "unknown"
  property bool warpBusy: false
  property string warpError: ""
  property string warpDetails: ""

  function refreshWarpState() {
    var argv = Warp.warpArgv(pluginDir, "status")
    if (!argv) { warpState = "unknown"; warpDetails = ""; warpBusy = false; return }
    warpBusy = true
    warpStatusProc.command = argv
    warpStatusProc.running = true
    warpStatusWatchdog.restart()
  }

  // keepOn=true (Keep ON) => `warp off`; false => `warp on`. Never sets
  // warpState optimistically: the row stays busy until the post-apply
  // re-read confirms the real state. Failures keep the inline error and
  // restore the control to the re-read real state.
  function setKeepPointerInPlace(keepOn) {
    var mode = Warp.warpModeForKeep(keepOn)
    if (!mode) return
    var argv = Warp.warpArgv(pluginDir, mode)
    if (!argv) { warpError = Warp.APPLY_ERROR; return }
    warpError = ""
    warpBusy = true
    warpApplyProc.command = argv
    warpApplyProc.running = true
    warpApplyWatchdog.restart()
  }

  Process {
    id: warpStatusProc
    stdout: StdioCollector { id: warpStatusOut }
    onExited: function(exitCode, exitStatus) {
      warpStatusWatchdog.stop()
      var parsed = Warp.parseWarpStatus(warpStatusOut.text, exitCode)
      root.warpState = parsed.state
      root.warpDetails = parsed.details
      root.warpBusy = false
    }
  }

  // Quickshell 0.3 Process has no error signal: a helper that cannot start
  // never exits. The watchdogs keep the Settings row from staying busy
  // forever and report the indeterminate state honestly.
  Timer {
    id: warpStatusWatchdog
    interval: 5000
    onTriggered: {
      if (!root.warpBusy) return
      console.warn("Hotbar: warp status helper did not answer")
      warpStatusProc.running = false
      root.warpState = "unknown"
      root.warpDetails = ""
      root.warpBusy = false
    }
  }

  Process {
    id: warpApplyProc
    stdout: StdioCollector { id: warpApplyOut }
    stderr: StdioCollector { id: warpApplyErr }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        root.warpError = Warp.APPLY_ERROR
        console.warn("Hotbar: warp apply failed (exit " + exitCode + "): " + warpApplyOut.text + " " + warpApplyErr.text)
      }
      // Re-read the real state either way; the control follows what the
      // compositor confirms, never what was requested.
      root.refreshWarpState()
    }
  }

  Timer {
    id: warpApplyWatchdog
    interval: 15000
    onTriggered: {
      if (!root.warpBusy || warpStatusProc.running) return
      console.warn("Hotbar: warp apply helper did not answer")
      warpApplyProc.running = false
      root.warpError = Warp.APPLY_ERROR
      root.refreshWarpState()
    }
  }

  // Real state on every Settings open (external changes picked up); idle
  // otherwise — no polling.
  onOpenPopoverChanged: {
    if (openPopover === "settings") {
      warpError = ""
      refreshWarpState()
    }
  }

  // ------------------------------------------------------------ popovers

  // Exactly one of Hotbar's popovers is open at a time, and the bar's own
  // coordinator closes it when another widget opens a panel.
  property string openPopover: ""      // "" | "places" | "app" | "running" | "settings"
  property var popoverGroup: null
  property Item popoverAnchor: null
  readonly property bool opened: openPopover !== ""
  readonly property Item runningAnchor: runningCellLoader.item

  function close() {
    openPopover = ""
    popoverGroup = null
    hidePreview()
  }

  function closeForPopoutSwitch() { close() }

  function openPlacesPopover(anchor) {
    hidePreview()
    if (openPopover === "places") { close(); return }
    refreshPlaces()
    popoverAnchor = anchor
    popoverGroup = null
    openPopover = "places"
  }

  function openAppPopover(group, anchor) {
    hidePreview()
    if (openPopover === "app" && popoverGroup && group && popoverGroup.key === group.key) { close(); return }
    popoverGroup = group
    popoverAnchor = anchor || popoverAnchor
    openPopover = "app"
  }

  function openByName(which) {
    var w = String(which || "")
    if (w === "places") { openPlacesPopover(placesCellLoader.item || root); return "ok" }
    if (w === "running") { openRunningPopover(runningCellLoader.item || root); return "ok" }
    if (w === "settings") { openSettingsPopover(popoverAnchor || placesCellLoader.item || root); return "ok" }
    var g = groupByKey(w)
    if (!g) return "unknown"
    openAppPopover(g, cellFor(w) || root)
    return "ok"
  }

  function openRunningPopover(anchor) {
    hidePreview()
    if (openPopover === "running") { close(); return }
    popoverAnchor = anchor
    popoverGroup = null
    openPopover = "running"
  }

  function openSettingsPopover(anchor) {
    hidePreview()
    if (openPopover === "settings") { close(); return }
    popoverAnchor = anchor || popoverAnchor
    popoverGroup = null
    openPopover = "settings"
  }

  // The group the popover shows is looked up live so that a popover left
  // open while windows come and go always reflects the current state.
  readonly property var livePopoverGroup: popoverGroup ? groupByKey(popoverGroup.key) : null
  // Deferred: close() clears popoverGroup, which would re-enter this binding
  // from inside its own change handler.
  onLivePopoverGroupChanged: if (openPopover === "app" && !livePopoverGroup) Qt.callLater(closeIfPopoverGroupGone)
  function closeIfPopoverGroupGone() { if (openPopover === "app" && !livePopoverGroup) close() }

  // Hover previews: a passive strip, never coordinated with the bar.
  property bool previewOpen: false
  property string previewDebug: ""
  property var previewGroup: null
  property Item previewAnchor: null

  Timer {
    id: previewTimer
    interval: root.previewDelay
    onTriggered: {
      if (!root.previewGroup || root.opened) { root.previewDebug = "bail: no group/opened"; return }
      if (!root.previewAnchor || !root.previewAnchor.hovered) { root.previewDebug = "bail: anchor not hovered"; return }
      var live = root.groupByKey(root.previewGroup.key)
      if (!live || live.windows.length < 2) { root.previewDebug = "bail: windows " + (live ? live.windows.length : -1); return }
      root.previewDebug = "opened " + live.key
      root.previewOpen = true
    }
  }

  Timer {
    id: previewCloseTimer
    interval: 220
    onTriggered: {
      if (!previewCard.containsMouse && !(root.previewAnchor && root.previewAnchor.hovered)) root.hidePreview()
    }
  }

  function requestPreview(group, anchor) {
    if (!previewsEnabled || opened) return
    previewGroup = group
    previewAnchor = anchor
    previewCloseTimer.stop()
    if (previewOpen) return
    previewTimer.restart()
  }

  function releasePreview() {
    previewTimer.stop()
    if (previewOpen) previewCloseTimer.restart()
    else previewGroup = null
  }

  function hidePreview() {
    previewTimer.stop()
    previewCloseTimer.stop()
    previewOpen = false
    previewGroup = null
  }

  onOpenedChanged: if (opened) hidePreview()

  // ---------------------------------------------------- width budget

  // The host bar does no overflow handling, so Hotbar finds its own section
  // and the neighbouring ones inside the bar window and computes how much
  // room it has before it would crowd another widget. When the sections
  // cannot be found the budget is unknown and Hotbar stays bounded: it keeps
  // the last known good budget, or shows at most 6 pins on a cold start,
  // routing the rest into Running. It never expands to every pin because
  // discovery failed.
  property var sectionItems: ({ left: [], center: [], right: [] })
  property string region: ""
  property real availableExtent: 0
  property int visiblePinCount: Math.min(pinnedGroups.length, 6)
  // Last budget computed from valid section geometry. Updated only on a
  // valid discovery pass; transient QML-tree failure must not expand Hotbar.
  property int lastGoodVisiblePinCount: -1

  readonly property var visiblePins: pinnedGroups.slice(0, Math.max(0, Math.min(pinnedGroups.length, visiblePinCount)))
  readonly property var overflowPins: pinnedGroups.slice(Math.max(0, Math.min(pinnedGroups.length, visiblePinCount)))

  // The surface Repeater is driven by identity keys, not group objects: a JS
  // array model recreates every delegate whenever the array is reassigned,
  // and groups are rebuilt on every focus change. Keys only change when a
  // pin is added, removed, moved or overflowed, so the cells — with their
  // hover state, tooltips, loaded icons and popover anchors — persist.
  property var visiblePinKeys: []
  onVisiblePinsChanged: {
    var keys = visiblePins.map(function(g) { return g.key })
    if (keys.join("\n") !== visiblePinKeys.join("\n")) visiblePinKeys = keys
  }

  property int layoutScanAttempts: 0
  // One helper for restarting layout discovery: resets the retry count, the
  // timer interval and the temporary scan state. Used on startup, bar layout
  // changes, bar position changes and screen changes so the retry counter
  // never stays permanently exhausted after a later layout change.
  function resetLayoutProbe() {
    layoutScanAttempts = 0
    layoutScanTimer.interval = 250
    region = ""
    sectionItems = ({ left: [], center: [], right: [] })
    layoutScanTimer.restart()
  }
  Timer {
    id: layoutScanTimer
    interval: 250
    onTriggered: {
      root.scanSections()
      root.scheduleLayout()
      // The bar may still be building its sections; look again a few times
      // before settling for the bounded fallback.
      if (!root.region && root.layoutScanAttempts < 4) { root.layoutScanAttempts++; interval = 500; restart() }
      else interval = 250
    }
  }

  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onLayoutConfigChanged() { root.resetLayoutProbe() }
    function onPositionChanged() { root.resetLayoutProbe() }
  }

  // The ModuleSlot the bar wrapped us in: the nearest ancestor that carries
  // the bar's `region` + `entry` pair. (Our direct parent is its Loader.)
  function ownSlot() {
    var item = root.parent
    for (var depth = 0; item && depth < 4; depth++) {
      if (typeof item.region === "string" && ("entry" in item)) return item
      item = item.parent
    }
    return null
  }

  function scanSections() {
    var w = root.QsWindow.window
    var found = { left: [], center: [], right: [] }
    var region = ""
    var slot = ownSlot()
    if (slot) region = slot.region
    function walk(item, depth) {
      if (!item || depth > 8) return
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) {
        var k = kids[i]
        if (!k) continue
        if (typeof k.region === "string" && ("entries" in k) && found[k.region]) found[k.region].push(k)
        else if (typeof k.region === "string" && ("entry" in k) && k.region === "center" && k !== slot) found.center.push(k)
        else walk(k, depth + 1)
      }
    }
    if (w && w.contentItem) walk(w.contentItem, 0)
    root.region = region
    root.sectionItems = found
  }

  function extentOf(item) {
    // Bar-axis start/end of a section list in bar-window coordinates.
    var w = root.QsWindow.window
    if (!item || !item.visible || !w || !w.contentItem) return null
    var p = item.mapToItem(w.contentItem, 0, 0)
    var start = root.vertical ? p.y : p.x
    var size = root.vertical ? item.height : item.width
    if (!(size > 0)) return null
    return { start: start, end: start + size }
  }

  function sectionExtent(list) {
    var start = NaN, end = NaN
    for (var i = 0; i < list.length; i++) {
      var e = extentOf(list[i])
      if (!e) continue
      start = isNaN(start) ? e.start : Math.min(start, e.start)
      end = isNaN(end) ? e.end : Math.max(end, e.end)
    }
    return { start: start, end: end }
  }

  function siblingExtents() {
    var slot = ownSlot()
    var row = slot ? slot.parent : null
    var before = 0, after = 0
    if (!row || !row.children) return { before: before, after: after }
    var seen = false
    for (var i = 0; i < row.children.length; i++) {
      var c = row.children[i]
      if (c === slot) { seen = true; continue }
      if (!c || !c.visible) continue
      var size = root.vertical ? c.height : c.width
      if (seen) after += size
      else before += size
    }
    return { before: before, after: after }
  }

  // Everything the budget depends on, folded into one number so a single
  // change handler can debounce recomputation. None of it depends on this
  // widget's own width, so the layout cannot oscillate.
  readonly property string budgetProbe: {
    var w = root.QsWindow.window
    var parts = [w ? (root.vertical ? w.height : w.width) : 0]
    var s = root.sectionItems
    var lists = ["left", "center", "right"]
    for (var r = 0; r < lists.length; r++) {
      var items = s[lists[r]] || []
      for (var i = 0; i < items.length; i++) {
        var it = items[i]
        if (!it) continue
        // Each value on its own: a neighbour that shifts left while it grows
        // must not cancel out.
        parts.push(it.x, it.y, it.width, it.height, it.visible ? 1 : 0)
      }
    }
    var slot = ownSlot()
    var row = slot ? slot.parent : null
    if (row && row.children) {
      for (var c = 0; c < row.children.length; c++) {
        var ch = row.children[c]
        if (ch && ch !== slot) parts.push(root.vertical ? ch.height : ch.width, ch.visible ? 1 : 0)
      }
    }
    parts.push(root.cellExtent, root.placesExtent, root.cellSpacing, root.separatorExtent, root.showPlaces ? 1 : 0, root.showRunning ? 1 : 0)
    return parts.join(",")
  }
  onBudgetProbeChanged: scheduleLayout()

  Timer {
    id: layoutTimer
    interval: 16
    onTriggered: root.applyBudget()
  }
  function scheduleLayout() { layoutTimer.restart() }

  function applyBudget() {
    if (!responsive) { visiblePinCount = pinnedGroups.length; availableExtent = 0; return }
    var w = root.QsWindow.window
    var total = (w && (root.vertical ? w.height : w.width)) || 0
    var s = root.sectionItems
    var left = sectionExtent(s.left || []), center = sectionExtent(s.center || []), right = sectionExtent(s.right || [])
    // Discovery is successful only when enough section geometry exists to
    // calculate a meaningful budget — a region string alone is not enough.
    var geometryValid = total > 0 && region !== "" && (
      isFinite(left.start) || isFinite(center.start) || isFinite(right.start))
    if (!geometryValid) {
      // Bounded fallback: last good budget, else at most 6 pins. Retry a few
      // more times in case the bar is still building its sections.
      visiblePinCount = Model.fallbackVisibleCount(pinnedGroups.length, lastGoodVisiblePinCount)
      availableExtent = 0
      if (layoutScanAttempts < 8) { layoutScanAttempts++; layoutScanTimer.interval = 500; layoutScanTimer.restart() }
      return
    }
    var own = siblingExtents()
    var blockers = {
      leftStart: left.start, leftEnd: left.end,
      centerStart: center.start, centerEnd: center.end,
      rightStart: right.start, rightEnd: right.end
    }
    var reserve = Style.space(12)
    var available = Model.availableExtent(region, total, blockers, own.before, own.after, reserve)
    availableExtent = available
    var fixed = (showPlaces ? 1 : 0) + (showRunning ? 1 : 0)
    // Fixed extent beyond the fixed cells themselves: the separators plus
    // whatever the Places badge needs over a plain cell.
    var seps = (showPlaces ? separatorExtent + Math.max(0, placesExtent - cellExtent) : 0) + (showRunning ? separatorExtent : 0)
    var count = Model.visiblePinCount(available, cellExtent, cellSpacing, pinnedGroups.length, fixed, seps)
    // Hysteresis: adding a pin back needs half a cell of slack beyond what
    // the count strictly requires, so a neighbour wobbling by a pixel cannot
    // make the last pin flicker in and out.
    if (count > visiblePinCount && count < pinnedGroups.length) {
      var needed = fixed * (cellExtent + cellSpacing) + seps + count * (cellExtent + cellSpacing) - cellSpacing
      if (available < needed + cellExtent / 2) count = Math.max(visiblePinCount, count - 1)
    }
    // Only a valid discovery pass updates the last known good budget.
    lastGoodVisiblePinCount = count
    if (count !== visiblePinCount) visiblePinCount = count
  }

  // ------------------------------------------------------------ surface

  readonly property real surfaceExtent: {
    var n = 0
    var extent = 0
    if (showPlaces) { extent += placesExtent; n++ }
    var pinsShown = visiblePins.length
    if (pinsShown > 0) {
      if (n > 0) extent += separatorExtent
      extent += pinsShown * cellExtent + (pinsShown - 1) * cellSpacing
      n++
    }
    if (showRunning) {
      if (n > 0) extent += separatorExtent
      extent += cellExtent
    }
    return extent
  }

  implicitWidth: vertical ? barSize : Math.max(0, surfaceExtent)
  implicitHeight: vertical ? Math.max(0, surfaceExtent) : barSize

  Behavior on implicitWidth { enabled: root.animationsEnabled && !root.vertical; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  Behavior on implicitHeight { enabled: root.animationsEnabled && root.vertical; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

  Accessible.role: Accessible.ToolBar
  Accessible.name: "Hotbar"

  component SectionSeparator: Item {
    visible: root.separators
    width: root.vertical ? root.barSize : root.separatorExtent
    height: root.vertical ? root.separatorExtent : root.barSize
    Rectangle {
      anchors.centerIn: parent
      width: root.vertical ? Math.round(root.barSize * 0.5) : 1
      height: root.vertical ? 1 : Math.round(root.barSize * 0.5)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
    }
  }

  // One Grid handles both orientations: a single row on a horizontal bar,
  // a single column on a vertical one. Invisible children take no space.
  Grid {
    id: surface
    anchors.centerIn: parent
    columns: root.vertical ? 1 : 1000
    rows: root.vertical ? 1000 : 1
    flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
    spacing: 0

    Loader {
      id: placesCellLoader
      active: root.showPlaces
      visible: active
      sourceComponent: PlacesCell { hotbar: root }
    }

    SectionSeparator {
      visible: root.separators && root.showPlaces && root.visiblePins.length > 0
    }

    Grid {
      id: pinGrid
      columns: root.vertical ? 1 : 1000
      rows: root.vertical ? 1000 : 1
      flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
      spacing: root.cellSpacing
      visible: root.visiblePins.length > 0

      Repeater {
        model: root.visiblePinKeys
        delegate: AppCell {
          required property var modelData
          hotbar: root
          pinKey: modelData
        }
      }
    }

    SectionSeparator {
      visible: root.separators && root.showRunning && (root.showPlaces || root.visiblePins.length > 0)
    }

    Loader {
      id: runningCellLoader
      active: root.showRunning
      visible: active
      sourceComponent: RunningCell { hotbar: root }
    }
  }

  // ----------------------------------------------------------------- IPC

  // `omarchy-shell hotbar <method> [arg]` — scripting surface used by the
  // bin/hotbar CLI and the live test suite. Nothing here runs commands; the
  // arguments are identity keys, popover names, or nothing.
  Timer {
    id: ipcRegisterTimer
    interval: 400
    running: true
    onTriggered: ipc.enabled = true
  }
  IpcHandler {
    id: ipc
    target: "hotbar"
    // On a plugin hot-reload the outgoing instance still holds the target
    // while the new one is created; registering a beat later lets the new
    // handler take over instead of silently failing.
    enabled: false

    function pin(key: string): string {
      var k = root.resolveKey(key)
      if (!k) return "error: empty key"
      if (!Model.isValidPinKey(k)) return "error: invalid key"
      if (root.isPinned(k)) return "already pinned"
      return root.persistSettings({ pins: Model.togglePin(root.pins, k) }) ? "ok" : "error: could not persist"
    }

    function unpin(key: string): string {
      var k = root.resolveKey(key)
      if (!k || !root.isPinned(k)) return "not pinned"
      return root.persistSettings({ pins: Model.togglePin(root.pins, k) }) ? "ok" : "error: could not persist"
    }

    // Keys separated by "|" (qs ipc would read a JSON array as several
    // arguments). An empty string clears every pin. Every key passes the
    // canonical pin validation; invalid ones are dropped, never stored.
    function setPins(keys: string): string {
      var list = String(keys || "").split("|").map(function(k) { return k.trim() }).filter(function(k) { return k.length > 0 })
      return root.persistSettings({ pins: Model.normalizePins(list) }) ? "ok" : "error: could not persist"
    }

    function pins(): string { return root.pins.join("|") }

    // Liveness probe for the CLI preflight: the shell can be alive while
    // this target is not yet re-registered after a plugin hot-reload.
    function ping(): string { return "ok" }

    // setSetting <key> <hex of JSON value>. Hex because the IPC layer would
    // split a JSON array into separate arguments.
    function setSetting(key: string, hexJson: string): string {
      var raw = Model.decodeHexUtf8(hexJson)
      if (raw === null) return "error: value must be hex-encoded JSON"
      var value
      try { value = JSON.parse(raw) } catch (e) { return "error: invalid JSON" }
      var checked = Model.validateSetting(key, value)
      if (!checked.ok) return "error: " + checked.error
      var patch = {}
      patch[String(key)] = checked.value
      return root.persistSettings(patch) ? "ok" : "error: could not persist"
    }

    function getSetting(key: string): string {
      var k = String(key || "")
      if (!Model.SETTING_KEYS[k]) return "error: unknown setting: " + k
      var v = root.effectiveSettings ? root.effectiveSettings[k] : undefined
      return JSON.stringify(v === undefined ? null : v)
    }

    function open(which: string): string { return root.openByName(which) }

    function close(): void { root.close() }

    // Same, on the bar of a named screen (`hyprctl monitors`). Only one
    // instance owns this IPC target, so these forward to the sibling
    // instance registered for that screen.
    function openOn(screen: string, which: string): string {
      var inst = Registry.lookup(screen)
      if (!inst) return "unknown screen " + screen + " (" + Registry.screens().join(", ") + ")"
      return inst.openByName(which)
    }

    function closeOn(screen: string): string {
      var inst = Registry.lookup(screen)
      if (!inst) return "unknown screen " + screen
      inst.close()
      return "ok"
    }

    function screens(): string { return Registry.screens().join("|") }

    function activate(key: string): string {
      var g = root.groupByKey(String(key || ""))
      if (!g) return "unknown"
      root.activateGroup(g)
      return "ok"
    }

    // Pinned slot n (1-based) — for a Hyprland binding such as
    // bind Super+1 → `omarchy-shell hotbar activateIndex 1`.
    function activateIndex(index: string): string {
      var n = Math.round(Number(index))
      if (!(n >= 1) || n > root.pinnedGroups.length) return "no pin " + index
      root.activateGroup(root.pinnedGroups[n - 1])
      return "ok"
    }

    function newWindow(key: string): string {
      var g = root.groupByKey(root.resolveKey(key))
      if (!g) return "unknown"
      root.newWindow(g)
      return "ok"
    }

    function cycle(key: string): string {
      var g = root.groupByKey(String(key || ""))
      if (!g) return "unknown"
      var order = g.windows.map(function(w) { return w.address }).join(",")
      return "ok " + root.cycleGroup(g, 1) + " from " + root.activeAddress + " order " + order
    }

    function identify(): string {
      // Every window with the identity Hotbar resolved for it — the tool for
      // writing `matches` overrides.
      var out = []
      for (var key in root.groups) {
        var g = root.groups[key]
        for (var i = 0; i < g.windows.length; i++) {
          var w = g.windows[i]
          var tl = w.toplevel
          var ipc = tl && tl.lastIpcObject ? tl.lastIpcObject : {}
          out.push({ address: w.address, appId: tl && tl.wayland ? tl.wayland.appId : "", class: ipc["class"] || "", initialClass: ipc.initialClass || "", key: key, name: g.name, desktopId: g.desktopId, source: w.identity ? w.identity.source : "" })
        }
      }
      return JSON.stringify(out)
    }

    function state(): string {
      var w = root.QsWindow.window
      return JSON.stringify({
        region: root.region,
        screen: w && w.screen ? w.screen.name : "",
        surfaceExtent: root.surfaceExtent,
        cellExtent: root.cellExtent,
        placesExtent: root.placesExtent,
        availableExtent: root.availableExtent,
        visiblePinCount: root.visiblePinCount,
        pins: root.pins,
        visiblePins: root.visiblePins.map(function(g) { return { key: g.key, name: g.name, count: g.count, focused: g.focused, urgent: g.urgent } }),
        overflowPins: root.overflowPins.map(function(g) { return g.key }),
        running: root.runningGroups.map(function(g) { return { key: g.key, name: g.name, count: g.count } }),
        groups: Object.keys(root.groups).length,
        windows: (Hyprland.toplevels.values || []).length,
        openPopover: root.openPopover,
        previewOpen: root.previewOpen,
        activeAddress: root.activeAddress,
        mru: root.mru.slice(0, 8),
        barActivePopout: !!(root.bar && root.bar.activePopout),
        previewGroup: root.previewGroup ? root.previewGroup.key : "",
        previewTimerRunning: previewTimer.running,
        previewDebug: root.previewDebug,
        placesSections: root.placesSections.map(function(s) { return { id: s.id, rows: s.rows.map(function(r) { return r.name + " -> " + r.path }) } }),
        cells: root.cellGeometry()
      })
    }
  }

  // A key can be a desktop id, an identity key ("class:foo"), or the app
  // id / class of something that is running now; the last form is resolved
  // to whatever identity Hotbar gave that window.
  function resolveKey(key) {
    var k = Model.normalizePins([key])[0]
    if (!k) return ""
    if (root.groupByKey(k)) return k
    var asClass = Model.CLASS_PREFIX + k.toLowerCase()
    if (root.groupByKey(asClass)) return asClass
    if (root.entryFor(k)) return k
    var values = Hyprland.toplevels.values || []
    for (var i = 0; i < values.length; i++) {
      var tl = values[i]
      var ipc = tl && tl.lastIpcObject ? tl.lastIpcObject : {}
      var appId = tl && tl.wayland ? String(tl.wayland.appId || "") : ""
      if (appId.toLowerCase() === k.toLowerCase() || String(ipc["class"] || "").toLowerCase() === k.toLowerCase()) {
        return root.identityFor(tl).key
      }
    }
    return k
  }

  // Bar-window coordinates of every surface cell — for tests that need to
  // point at a cell without guessing where the widget was placed.
  function cellGeometry() {
    var w = root.QsWindow.window
    if (!w || !w.contentItem) return []
    var out = []
    function add(key, item) {
      if (!item || !item.visible) return
      var p = item.mapToItem(w.contentItem, 0, 0)
      out.push({ key: key, x: Math.round(p.x), y: Math.round(p.y), w: Math.round(item.width), h: Math.round(item.height), hovered: item.hovered === true })
    }
    add("places", placesCellLoader.item)
    for (var i = 0; i < pinGrid.children.length; i++) {
      var c = pinGrid.children[i]
      if (c && c.pinKey !== undefined) add(c.pinKey, c)
    }
    add("running", runningCellLoader.item)
    return out
  }

  function cellFor(key) {
    // The AppCell currently showing this group, if it is on the surface.
    var grid = pinGrid
    if (!grid) return null
    for (var i = 0; i < grid.children.length; i++) {
      var c = grid.children[i]
      if (c && c.pinKey === key) return c
    }
    return null
  }

  // ------------------------------------------------------- popover items

  PlacesPopover {
    hotbar: root
    anchorItem: root.popoverAnchor || root
    open: root.openPopover === "places"
  }

  AppPopover {
    hotbar: root
    anchorItem: root.popoverAnchor || root
    group: root.livePopoverGroup
    open: root.openPopover === "app" && root.livePopoverGroup !== null
  }

  RunningPopover {
    hotbar: root
    anchorItem: root.popoverAnchor || root
    open: root.openPopover === "running"
  }

  SettingsPopover {
    hotbar: root
    anchorItem: root.popoverAnchor || root
    open: root.openPopover === "settings"
  }

  PreviewPopover {
    id: previewCard
    hotbar: root
    group: root.previewGroup
    open: root.previewOpen && root.previewGroup !== null && root.previewAnchor !== null
    onContainsMouseChanged: if (!containsMouse && root.previewOpen) previewCloseTimer.restart()
  }
}
