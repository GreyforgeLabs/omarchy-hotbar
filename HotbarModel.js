// Hotbar — pure application model.
//
// Identity engine, ApplicationGroup construction, MRU ordering and the
// responsive width budget. QML imports this file; node tests require() it.
// No I/O, no Hyprland, no timers: every function is deterministic over its
// arguments so the whole model can be unit-tested with fixtures.
//
// Every string that arrives here (app ids, classes, titles, desktop entry
// fields, user config) is untrusted. Nothing in this file builds a shell
// command; launch targets leave as argv arrays or desktop ids.

var CLASS_PREFIX = "class:"

// Bounds for untrusted configuration data.
var MAX_PIN_KEY_LENGTH = 255
var MAX_LIST_ENTRIES = 128
var MAX_PATTERN_LENGTH = 256
var COLD_START_FALLBACK_PINS = 6

// --------------------------------------------------------------- utilities

function str(value) {
  return value === undefined || value === null ? "" : String(value)
}

function lower(value) {
  return str(value).trim().toLowerCase()
}

function stripDesktop(id) {
  var value = str(id).trim()
  return value.slice(-8) === ".desktop" ? value.slice(0, -8) : value
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

// Human name for an identity that has no desktop entry. Reverse-DNS ids keep
// their last segment ("org.gnome.Loupe" -> "Loupe"); everything else is shown
// verbatim so a custom terminal class stays recognisable.
function prettyClassName(token) {
  var value = str(token).trim()
  if (!value) return "Unknown"
  var parts = value.split(".")
  if (parts.length >= 3 && /^[a-z]{2,}$/i.test(parts[0]) && parts[parts.length - 1]) {
    value = parts[parts.length - 1]
  }
  return value.charAt(0).toUpperCase() + value.slice(1)
}

// ------------------------------------------------------ chromium web apps

// Chromium names --app windows "chrome-<host>__<path>-<profile>". Returns the
// host ("youtube.com") or "" when the id is not of that shape.
function chromeAppHost(appId) {
  var m = /^chrome-([^_]+)__(.*)-([^-]+)$/.exec(str(appId))
  if (!m) return ""
  return lower(m[1]).replace(/^www\./, "")
}

// Host of the URL a desktop entry opens as a web app, from Exec lines such as
// "chromium --app=https://suno.com/" or "omarchy-launch-webapp https://x.com/".
function webAppHost(execString) {
  var exec = str(execString)
  var m = /--app=(?:"|')?(https?:\/\/[^\s"']+)/.exec(exec)
  if (!m) m = /omarchy-launch-webapp\s+(?:"|')?(https?:\/\/[^\s"']+)/.exec(exec)
  if (!m) return ""
  var url = m[1]
  var host = /^https?:\/\/([^\/:?#]+)/.exec(url)
  return host ? lower(host[1]).replace(/^www\./, "") : ""
}

function execBasename(execString) {
  var exec = str(execString).trim()
  if (!exec) return ""
  // Skip env assignments and wrappers that carry the real program later.
  var parts = exec.split(/\s+/)
  var i = 0
  while (i < parts.length && (/^[A-Za-z_][A-Za-z0-9_]*=/.test(parts[i]) || parts[i] === "env")) i++
  var wrappers = { "uwsm-app": true, "uwsm": true, "setsid": true, "nohup": true, "--": true, "app": true }
  while (i < parts.length && wrappers[parts[i]]) i++
  if (i >= parts.length) return ""
  var first = parts[i].replace(/^"+|"+$/g, "")
  var base = first.split("/").pop()
  return lower(base)
}

// ---------------------------------------------------------- entry index

// entries: [{ id, name, icon, execString, startupClass, noDisplay }]
function buildEntryIndex(entries) {
  var index = { byId: {}, byIdLower: {}, byStartupClass: {}, byWebHost: {}, byExecBase: {}, byName: {}, count: 0 }
  var list = Array.isArray(entries) ? entries : []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry) continue
    var id = stripDesktop(entry.id)
    if (!id) continue
    var info = {
      id: id,
      name: str(entry.name) || id,
      icon: str(entry.icon),
      execString: str(entry.execString),
      startupClass: str(entry.startupClass),
      noDisplay: entry.noDisplay === true
    }
    index.count++
    index.byId[id] = info
    var idl = lower(id)
    if (!index.byIdLower[idl]) index.byIdLower[idl] = info
    var sc = lower(info.startupClass)
    if (sc && sc.charAt(0) !== "@" && !index.byStartupClass[sc]) index.byStartupClass[sc] = info
    var host = webAppHost(info.execString)
    if (host && !index.byWebHost[host]) index.byWebHost[host] = info
    var base = execBasename(info.execString)
    // Wrappers such as xdg-terminal-exec or omarchy-launch-webapp launch many
    // different apps; they must not become an identity for their app id.
    if (base && !/^(xdg-terminal-exec|omarchy-launch-|gtk-launch|bash|sh|python|env)/.test(base)) {
      if (!index.byExecBase[base] || info.noDisplay === false && index.byExecBase[base].noDisplay) index.byExecBase[base] = info
    }
    var nm = lower(info.name)
    if (nm && !index.byName[nm]) index.byName[nm] = info
  }
  return index
}

// ------------------------------------------------------------ overrides

// One canonical pin/identity-key validation path. `|` is the IPC pin-list
// delimiter, so no valid key may contain it. Also rejected: empty strings,
// NUL, C0 controls, DEL, and absurdly long keys. Valid desktop ids,
// `class:<app-id>` keys, mixed-case ids and Unicode all pass.
function isValidPinKey(key) {
  var value = str(key)
  if (!value) return false
  if (value !== str(key).trim()) {
    // Leading/trailing whitespace is normalized away, not rejected — but an
    // all-whitespace key is empty after trimming.
    if (!str(key).trim()) return false
  }
  var v = str(key).trim()
  if (!v || v.length > MAX_PIN_KEY_LENGTH) return false
  if (v.indexOf("|") !== -1) return false
  if (/[\x00-\x1f\x7f]/.test(v)) return false
  return true
}

// User config: [{ name?, matchClass, desktopId?, icon? }]. Invalid regexes are
// skipped, never thrown. Overrides can only *name* a desktop id or icon;
// there is deliberately no exec/command field.
function compileOverrides(matches) {
  var out = []
  var list = Array.isArray(matches) ? matches : []
  for (var i = 0; i < list.length; i++) {
    if (out.length >= MAX_LIST_ENTRIES) break
    var m = list[i]
    if (!isPlainObject(m)) continue
    var pattern = str(m.matchClass || m.match)
    if (!pattern) continue
    if (pattern.length > MAX_PATTERN_LENGTH) continue
    var re
    try { re = new RegExp(pattern, "i") } catch (e) { continue }
    out.push({
      re: re,
      desktopId: stripDesktop(m.desktopId),
      name: str(m.name),
      icon: str(m.icon)
    })
  }
  return out
}

// ------------------------------------------------------------- identity

// win: { appId, cls, initialClass, title }
// index: buildEntryIndex() result
// overrides: compileOverrides() result
// heuristic: optional function(token) -> { id, name, icon } | null
//
// Returns { key, desktopId, name, icon, source }. `key` is the group identity:
// the desktop id when one was found, otherwise "class:<token>".
function resolveIdentity(win, index, overrides, heuristic) {
  var w = win || {}
  var appId = str(w.appId).trim()
  var cls = str(w.cls).trim()
  var initialClass = str(w.initialClass).trim()
  var candidates = []
  function push(v) { if (v && candidates.indexOf(v) === -1) candidates.push(v) }
  push(appId); push(cls); push(initialClass)

  function fromInfo(info, source) {
    return { key: info.id, desktopId: info.id, name: info.name || info.id, icon: info.icon || "", source: source }
  }

  // 1. explicit user override
  var ov = Array.isArray(overrides) ? overrides : []
  for (var o = 0; o < ov.length; o++) {
    for (var c = 0; c < candidates.length; c++) {
      if (!ov[o].re.test(candidates[c])) continue
      var target = ov[o].desktopId && index && index.byId[ov[o].desktopId]
      var result
      if (target) result = fromInfo(target, "override")
      else if (ov[o].desktopId) result = { key: ov[o].desktopId, desktopId: ov[o].desktopId, name: ov[o].name || ov[o].desktopId, icon: ov[o].icon, source: "override" }
      else result = { key: CLASS_PREFIX + lower(candidates[c]), desktopId: "", name: ov[o].name || prettyClassName(candidates[c]), icon: ov[o].icon, source: "override" }
      if (ov[o].name) result.name = ov[o].name
      if (ov[o].icon) result.icon = ov[o].icon
      return result
    }
  }

  if (index) {
    // 2. exact desktop id (app id first — it is the Wayland-stable one)
    for (var i = 0; i < candidates.length; i++) {
      var exact = index.byId[stripDesktop(candidates[i])] || index.byIdLower[lower(stripDesktop(candidates[i]))]
      if (exact) return fromInfo(exact, "desktop-id")
    }
    // 3. StartupWMClass
    for (var s = 0; s < candidates.length; s++) {
      var sc = index.byStartupClass[lower(candidates[s])]
      if (sc) return fromInfo(sc, "startup-class")
    }
    // 4. Chromium web app -> entry that opens the same host
    for (var h = 0; h < candidates.length; h++) {
      var host = chromeAppHost(candidates[h])
      if (!host) continue
      var byHost = index.byWebHost[host]
      if (byHost) return fromInfo(byHost, "web-app")
    }
  }

  // Steam games report "steam_app_<id>" and have no desktop entry of their
  // own; fuzzy matching would fold every game into Steam. Keep each game its
  // own identity, named by its (stable, for games) title.
  var steam = /^steam_app_\d+$/i.test(appId || cls || initialClass)
  if (steam) {
    var steamToken = appId || cls || initialClass
    return { key: CLASS_PREFIX + lower(steamToken), desktopId: "", name: str(w.title).trim() || "Steam game", icon: "steam", source: "steam" }
  }

  // 5. host heuristic (Quickshell's DesktopEntries.heuristicLookup), bounded:
  //    the hit must plausibly be *about* the token, or it is discarded.
  if (typeof heuristic === "function") {
    for (var k = 0; k < candidates.length; k++) {
      // Chromium web-app ids must never fuzzy-match "chromium" itself.
      if (chromeAppHost(candidates[k])) continue
      var found = null
      try { found = heuristic(candidates[k]) } catch (e) { found = null }
      if (found && found.id && heuristicPlausible(candidates[k], found)) {
        var info = index && index.byId[stripDesktop(found.id)]
        return info ? fromInfo(info, "heuristic") : { key: stripDesktop(found.id), desktopId: stripDesktop(found.id), name: str(found.name) || stripDesktop(found.id), icon: str(found.icon), source: "heuristic" }
      }
    }
  }

  if (index) {
    // 6. executable name equals the app id / class
    for (var e = 0; e < candidates.length; e++) {
      var base = index.byExecBase[lower(candidates[e])]
      if (base) return fromInfo(base, "exec")
    }
    // 7. entry name equals the class (XWayland apps often report their name)
    for (var n = 0; n < candidates.length; n++) {
      var byName = index.byName[lower(candidates[n])]
      if (byName) return fromInfo(byName, "name")
    }
  }

  // 8. bounded fallback: the class itself is the identity
  var token = appId || cls || initialClass
  if (!token) return { key: CLASS_PREFIX + "unknown", desktopId: "", name: "Unknown", icon: "", source: "fallback" }
  var webHost = chromeAppHost(token)
  return {
    key: CLASS_PREFIX + lower(token),
    desktopId: "",
    name: webHost ? prettyClassName(webHost.split(".")[0]) : prettyClassName(token),
    icon: "",
    source: "fallback"
  }
}

function heuristicPlausible(token, found) {
  var t = lower(token)
  var id = lower(stripDesktop(found.id))
  var name = lower(found.name)
  var sc = lower(found.startupClass)
  if (!t || !id) return false
  if (id === t || name === t || sc === t) return true
  if (id.indexOf(t) !== -1 || t.indexOf(id) !== -1) return true
  // reverse-DNS ids: compare the last segment ("org.gnome.Loupe" vs "loupe")
  var last = id.split(".").pop()
  return last === t || t.split(".").pop() === last
}

// Identity for a pin key with no running window ("chromium" or "class:foo").
function identityForKey(key, index, overrides) {
  var value = str(key).trim()
  if (!value) return null
  if (value.indexOf(CLASS_PREFIX) === 0) {
    var token = value.slice(CLASS_PREFIX.length)
    var resolved = resolveIdentity({ appId: token }, index, overrides, null)
    if (resolved.key !== value) resolved = { key: value, desktopId: "", name: prettyClassName(token), icon: "", source: "pin" }
    return resolved
  }
  var id = stripDesktop(value)
  var info = index ? (index.byId[id] || index.byIdLower[lower(id)]) : null
  if (info) return { key: info.id, desktopId: info.id, name: info.name, icon: info.icon, source: "pin" }
  return { key: id, desktopId: id, name: prettyClassName(id), icon: "", source: "pin-missing" }
}

// --------------------------------------------------------------------- MRU

function touchMru(list, address) {
  var addr = str(address)
  if (!addr) return list
  var out = [addr]
  var src = Array.isArray(list) ? list : []
  for (var i = 0; i < src.length; i++) if (src[i] !== addr) out.push(src[i])
  return out
}

function removeMru(list, address) {
  var addr = str(address)
  var src = Array.isArray(list) ? list : []
  return src.filter(function(a) { return a !== addr })
}

// Drop addresses that no longer exist so the list cannot grow unbounded.
function pruneMru(list, liveAddresses) {
  var live = {}
  var addrs = Array.isArray(liveAddresses) ? liveAddresses : []
  for (var i = 0; i < addrs.length; i++) live[str(addrs[i])] = true
  var src = Array.isArray(list) ? list : []
  return src.filter(function(a) { return live[a] === true })
}

// Sort windows by MRU rank; unknown addresses fall back to the compositor's
// focusHistoryID (0 = most recent) and finally to their original order.
function orderByMru(windows, mru) {
  var rank = {}
  var src = Array.isArray(mru) ? mru : []
  for (var i = 0; i < src.length; i++) rank[src[i]] = i
  var list = (Array.isArray(windows) ? windows : []).map(function(w, idx) { return { w: w, idx: idx } })
  list.sort(function(a, b) {
    var ra = rank[a.w.address], rb = rank[b.w.address]
    var ha = ra !== undefined, hb = rb !== undefined
    if (ha && hb) return ra - rb
    if (ha) return -1
    if (hb) return 1
    var fa = typeof a.w.focusHistory === "number" ? a.w.focusHistory : 1e9
    var fb = typeof b.w.focusHistory === "number" ? b.w.focusHistory : 1e9
    if (fa !== fb) return fa - fb
    return a.idx - b.idx
  })
  return list.map(function(x) { return x.w })
}

// Which window a click should go to. `ordered` is MRU order for the group.
// If the group already owns focus, advance to the next window (wrapping);
// otherwise go to the most recent one.
function clickTarget(ordered, activeAddress, direction) {
  var list = Array.isArray(ordered) ? ordered : []
  if (!list.length) return null
  var step = direction < 0 ? -1 : 1
  var idx = -1
  for (var i = 0; i < list.length; i++) if (list[i].address === str(activeAddress)) { idx = i; break }
  if (idx === -1) return list[0]
  if (list.length === 1) return list[0]
  // MRU order is "most recent first"; cycling forward walks toward older
  // windows, which is what repeated clicks should feel like.
  return list[(idx + step + list.length) % list.length]
}

// ------------------------------------------------------------------ groups

// windows: [{ address, identity, title, workspaceId, workspaceName,
//             monitorName, activated, urgent, focusHistory }]
// pins: ["chromium", "foot", "class:tui.float"]
// index/overrides: for empty pinned groups
function buildGroups(windows, pins, mru, index, overrides) {
  var groups = {}
  var order = []
  var list = Array.isArray(windows) ? windows : []
  for (var i = 0; i < list.length; i++) {
    var w = list[i]
    if (!w || !w.identity || !w.identity.key) continue
    var key = w.identity.key
    var g = groups[key]
    if (!g) {
      g = {
        key: key,
        desktopId: str(w.identity.desktopId),
        name: str(w.identity.name),
        icon: str(w.identity.icon),
        windows: [],
        pinned: false,
        running: false,
        focused: false,
        urgent: false,
        count: 0
      }
      groups[key] = g
      order.push(key)
    }
    g.windows.push(w)
  }

  var pinList = normalizePins(pins)
  for (var p = 0; p < pinList.length; p++) {
    var pk = pinList[p]
    if (!groups[pk]) {
      var ident = identityForKey(pk, index, overrides)
      if (!ident) continue
      groups[pk] = {
        key: pk, desktopId: ident.desktopId, name: ident.name, icon: ident.icon,
        windows: [], pinned: true, running: false, focused: false, urgent: false, count: 0
      }
      order.push(pk)
    }
    groups[pk].pinned = true
  }

  for (var k in groups) {
    var grp = groups[k]
    grp.windows = orderByMru(grp.windows, mru)
    grp.count = grp.windows.length
    grp.running = grp.count > 0
    grp.focused = false
    grp.urgent = false
    for (var j = 0; j < grp.windows.length; j++) {
      if (grp.windows[j].activated) grp.focused = true
      if (grp.windows[j].urgent && !grp.windows[j].activated) grp.urgent = true
    }
  }

  var pinned = pinList.map(function(key) { return groups[key] }).filter(Boolean)
  var running = []
  for (var r = 0; r < order.length; r++) {
    var rg = groups[order[r]]
    if (rg.running && !rg.pinned) running.push(rg)
  }
  running.sort(function(a, b) {
    var na = lower(a.name), nb = lower(b.name)
    if (na < nb) return -1
    if (na > nb) return 1
    return a.key < b.key ? -1 : a.key > b.key ? 1 : 0
  })

  return { groups: groups, pinned: pinned, running: running }
}

// Pins are stored as an array of identity keys. Accepts legacy objects
// ({desktopId}) and strings; dedupes; drops garbage. Invalid keys (pipe,
// control characters, overlong) are dropped, and the list is capped so an
// accidental huge configuration cannot propagate.
function normalizePins(pins) {
  var out = []
  var list = Array.isArray(pins) ? pins : []
  for (var i = 0; i < list.length; i++) {
    if (out.length >= MAX_LIST_ENTRIES) break
    var item = list[i]
    var key = ""
    if (typeof item === "string") key = item.trim()
    else if (isPlainObject(item)) key = str(item.key || item.desktopId || item.id).trim()
    if (!key) continue
    if (key.indexOf(CLASS_PREFIX) === 0) key = CLASS_PREFIX + lower(key.slice(CLASS_PREFIX.length))
    else key = stripDesktop(key)
    if (!isValidPinKey(key)) continue
    if (out.indexOf(key) === -1) out.push(key)
  }
  return out
}

function togglePin(pins, key) {
  var list = normalizePins(pins)
  var k = normalizePins([key])[0]
  if (!k) return list
  var idx = list.indexOf(k)
  if (idx === -1) list.push(k)
  else list.splice(idx, 1)
  return list
}

function movePin(pins, key, delta) {
  var list = normalizePins(pins)
  var k = normalizePins([key])[0]
  var idx = list.indexOf(k)
  if (idx === -1) return list
  var to = Math.max(0, Math.min(list.length - 1, idx + delta))
  if (to === idx) return list
  list.splice(idx, 1)
  list.splice(to, 0, k)
  return list
}

// ------------------------------------------------------------ width budget

// Given the extent available along the bar axis, how many pinned cells fit.
// available <= 0 means "unknown": failure must remain bounded, so this
// returns a conservative fallback (at most COLD_START_FALLBACK_PINS), never
// the whole pin list. Callers that hold a last known good budget should
// prefer fallbackVisibleCount() so a transient failure keeps the old budget.
function visiblePinCount(available, cell, spacing, pinCount, fixedCells, separators) {
  var pins = Math.max(0, Math.floor(Number(pinCount) || 0))
  var avail = Number(available)
  if (!(avail > 0)) return Math.min(COLD_START_FALLBACK_PINS, pins)
  var cellExtent = Math.max(1, Number(cell) || 1)
  var gap = Math.max(0, Number(spacing) || 0)
  var fixed = Math.max(0, Math.floor(Number(fixedCells) || 0)) * (cellExtent + gap)
  var seps = Math.max(0, Number(separators) || 0)
  var room = avail - fixed - seps
  if (room <= 0) return 0
  var n = Math.floor((room + gap) / (cellExtent + gap))
  return Math.max(0, Math.min(pins, n))
}

// Safe fallback when section discovery failed: keep the last known good
// budget if one exists, otherwise show at most COLD_START_FALLBACK_PINS and
// route the rest into Running. Never expands to every pin.
function fallbackVisibleCount(pinCount, lastGood) {
  var pins = Math.max(0, Math.floor(Number(pinCount) || 0))
  var good = Math.floor(Number(lastGood))
  if (isFinite(good) && good >= 0) return Math.max(0, Math.min(pins, good))
  return Math.min(COLD_START_FALLBACK_PINS, pins)
}

// Available extent for a widget inside one bar section.
//   region: "left" | "center" | "right"
//   total: bar length along its axis
//   blockers: { leftEnd, centerStart, centerEnd, rightStart } in bar coords
//             (use NaN/undefined when a section is empty)
//   before/after: extents of the widget's own siblings before/after it in
//                 its section
//   reserve: minimum gap to keep from the neighbouring section
function availableExtent(region, total, blockers, before, after, reserve) {
  var b = blockers || {}
  var T = Number(total) || 0
  var pre = Math.max(0, Number(before) || 0)
  var post = Math.max(0, Number(after) || 0)
  var gap = Math.max(0, Number(reserve) || 0)
  function num(v, fallback) { var n = Number(v); return isFinite(n) ? n : fallback }
  if (region === "left") {
    var limit = Math.min(num(b.centerStart, T), num(b.rightStart, T))
    var start = num(b.leftStart, 0)
    return limit - gap - start - pre - post
  }
  if (region === "right") {
    var floor = Math.max(num(b.centerEnd, 0), num(b.leftEnd, 0))
    var end = num(b.rightEnd, T)
    return end - floor - gap - pre - post
  }
  // center: the group is centred, so growth is symmetric about T/2
  var leftRoom = T / 2 - Math.max(num(b.leftEnd, 0), 0) - gap
  var rightRoom = Math.min(num(b.rightStart, T), T) - T / 2 - gap
  return 2 * Math.min(leftRoom, rightRoom) - pre - post
}

// ------------------------------------------------------------- launching

// A desktop id is a file name inside an applications/ directory: no path
// separators, no leading dash (gtk-launch would read it as an option), no
// control characters. Anything else is not an id and is refused.
function isDesktopId(id) {
  var value = str(id)
  return value.length > 0 && value.length <= 255 && value.charAt(0) !== "-" && !/[\/\x00-\x1f\x7f]/.test(value)
}

// argv for launching a desktop entry the way the host shell does.
function launchArgv(desktopId) {
  var id = stripDesktop(desktopId)
  if (!isDesktopId(id)) return null
  return ["uwsm-app", "--", "gtk-launch", id + ".desktop"]
}

// argv for a desktop action, or null if the action has no parsed command.
function actionArgv(command) {
  var list = Array.isArray(command) ? command.map(str).filter(function(s) { return s.length > 0 }) : []
  if (!list.length) return null
  return ["uwsm-app", "--"].concat(list)
}

// Pick the "open a new window" action from a desktop entry's actions.
function newWindowAction(actions) {
  var list = Array.isArray(actions) ? actions : []
  var byId = null, byName = null
  for (var i = 0; i < list.length; i++) {
    var a = list[i]
    if (!a) continue
    var id = lower(a.id)
    var name = lower(a.name)
    if (!byId && (id === "new-window" || id === "newwindow" || id === "new_window" || id === "window-new")) byId = a
    if (!byName && /^(open )?new (private |incognito )?window$/.test(name)) byName = a
    if (!byName && /^new window$/.test(name)) byName = a
  }
  return byId || byName || null
}

// Hex <-> UTF-8 JSON. The shell's IPC layer parses "[...]" arguments as
// lists, so structured settings travel as hex and are decoded here.
function decodeHexUtf8(hex) {
  var h = str(hex).trim()
  if (!h || h.length % 2 !== 0 || !/^[0-9a-fA-F]+$/.test(h)) return null
  var bytes = []
  for (var i = 0; i < h.length; i += 2) bytes.push(parseInt(h.substr(i, 2), 16))
  try {
    if (typeof TextDecoder !== "undefined") return new TextDecoder("utf-8").decode(new Uint8Array(bytes))
  } catch (e) {}
  // Manual UTF-8 decode for engines without TextDecoder.
  var out = ""
  for (var j = 0; j < bytes.length; j++) {
    var b = bytes[j]
    if (b < 0x80) out += String.fromCharCode(b)
    else if (b >= 0xc0 && b < 0xe0) { out += String.fromCharCode(((b & 0x1f) << 6) | (bytes[++j] & 0x3f)) }
    else if (b >= 0xe0 && b < 0xf0) { out += String.fromCharCode(((b & 0x0f) << 12) | ((bytes[++j] & 0x3f) << 6) | (bytes[++j] & 0x3f)) }
    else { var cp = ((b & 0x07) << 18) | ((bytes[++j] & 0x3f) << 12) | ((bytes[++j] & 0x3f) << 6) | (bytes[++j] & 0x3f); cp -= 0x10000; out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff)) }
  }
  return out
}

// Canonical runtime setting specification. This is the validator of record:
// it must match manifest.json (see tests/test_manifest.js), and every
// settings write — CLI, IPC, or persisted-state normalization — goes through
// validateSetting(). Invalid enum values and out-of-range numbers are refused,
// never silently persisted.
var SETTING_SPEC = {
  pins:             { type: "pins" },
  matches:          { type: "matches" },
  favorites:        { type: "favorites" },
  iconSize:         { type: "integer", min: 12, max: 24, defaultValue: 18 },
  spacing:          { type: "integer", min: 0, max: 12, defaultValue: 2 },
  iconStyle:        { type: "enum", options: ["color", "mono"], defaultValue: "color" },
  runningIndicator: { type: "enum", options: ["underline", "dot", "none"], defaultValue: "underline" },
  separators:       { type: "boolean", defaultValue: true },
  previews:         { type: "boolean", defaultValue: true },
  previewDelay:     { type: "integer", min: 100, max: 1500, defaultValue: 450 },
  animations:       { type: "boolean", defaultValue: true },
  wheelCycle:       { type: "boolean", defaultValue: true },
  middleClick:      { type: "enum", options: ["new-window", "none"], defaultValue: "new-window" },
  showPlaces:       { type: "boolean", defaultValue: true },
  showRunning:      { type: "boolean", defaultValue: true },
  responsive:       { type: "boolean", defaultValue: true },
  showDesktop:      { type: "boolean", defaultValue: true },
  showDownloads:    { type: "boolean", defaultValue: true },
  showDocuments:    { type: "boolean", defaultValue: true },
  showPictures:     { type: "boolean", defaultValue: true },
  showMusic:        { type: "boolean", defaultValue: true },
  showVideos:       { type: "boolean", defaultValue: true },
  showTrash:        { type: "boolean", defaultValue: true },
  showMounts:       { type: "boolean", defaultValue: true }
}

// Legacy type map kept for IPC getSetting lookups.
var SETTING_KEYS = {
  pins: "array", matches: "array", favorites: "array",
  iconSize: "integer", spacing: "integer", iconStyle: "string", runningIndicator: "string",
  separators: "boolean", previews: "boolean", previewDelay: "integer", animations: "boolean",
  wheelCycle: "boolean", middleClick: "string", showPlaces: "boolean", showRunning: "boolean",
  responsive: "boolean", showDesktop: "boolean", showDownloads: "boolean", showDocuments: "boolean",
  showPictures: "boolean", showMusic: "boolean", showVideos: "boolean", showTrash: "boolean", showMounts: "boolean"
}

// Favorites stay path-only: objects carrying execution-oriented fields are
// rejected outright, and configuration data is never executed.
function validateFavorites(value) {
  var list = Array.isArray(value) ? value : null
  if (!list) return { ok: false, error: "favorites must be a JSON array" }
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (out.length >= MAX_LIST_ENTRIES) break
    var item = list[i]
    if (typeof item === "string") {
      if (str(item).trim()) out.push(item)
      continue
    }
    if (!isPlainObject(item)) continue
    if ("exec" in item || "command" in item || "args" in item || "run" in item) continue
    var favPath = str(item.path)
    if (!favPath) continue
    var fav = { path: item.path }
    if (str(item.name)) fav.name = str(item.name)
    out.push(fav)
  }
  return { ok: true, value: out }
}

function validateMatches(value) {
  var list = Array.isArray(value) ? value : null
  if (!list) return { ok: false, error: "matches must be a JSON array" }
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (out.length >= MAX_LIST_ENTRIES) break
    var item = list[i]
    if (!isPlainObject(item)) continue
    var pattern = str(item.matchClass || item.match)
    if (!pattern || pattern.length > MAX_PATTERN_LENGTH) continue
    try { new RegExp(pattern, "i") } catch (e) { continue }
    var rule = {}
    for (var k in item) {
      if (k === "exec" || k === "command" || k === "args" || k === "run") continue
      rule[k] = item[k]
    }
    out.push(rule)
  }
  return { ok: true, value: out }
}

function validatePins(value) {
  if (!Array.isArray(value)) return { ok: false, error: "pins must be a JSON array" }
  return { ok: true, value: normalizePins(value) }
}

// Validate one setting value against the canonical spec. Returns
// { ok, value } or { ok: false, error }.
function validateSetting(key, value) {
  var name = str(key)
  var spec = SETTING_SPEC[name]
  if (!spec) return { ok: false, error: "unknown setting: " + name }
  if (spec.type === "pins") return validatePins(value)
  if (spec.type === "favorites") return validateFavorites(value)
  if (spec.type === "matches") return validateMatches(value)
  if (spec.type === "boolean") return typeof value === "boolean" ? { ok: true, value: value } : { ok: false, error: name + " must be true or false" }
  if (spec.type === "integer") {
    var n = Number(value)
    if (!isFinite(n)) return { ok: false, error: name + " must be a number" }
    n = Math.round(n)
    if (n < spec.min || n > spec.max) return { ok: false, error: name + " must be " + spec.min + ".." + spec.max }
    return { ok: true, value: n }
  }
  if (spec.type === "enum") {
    var s = str(value)
    if (spec.options.indexOf(s) === -1) return { ok: false, error: name + " must be one of: " + spec.options.join(", ") }
    return { ok: true, value: s }
  }
  return { ok: false, error: "unknown setting: " + name }
}

// Location label for a window row: "Workspace 3 · DP-2".
function windowLocation(win) {
  var w = win || {}
  var ws = str(w.workspaceName)
  var id = Number(w.workspaceId)
  var wsLabel
  if (!ws) wsLabel = ""
  else if (ws.indexOf("special") === 0) wsLabel = "Special"
  else if (isFinite(id) && String(id) === ws) wsLabel = "Workspace " + ws
  else wsLabel = ws
  var mon = str(w.monitorName)
  if (wsLabel && mon) return wsLabel + " · " + mon
  return wsLabel || mon
}

if (typeof module !== "undefined") {
  module.exports = {
    CLASS_PREFIX: CLASS_PREFIX,
    MAX_PIN_KEY_LENGTH: MAX_PIN_KEY_LENGTH,
    MAX_LIST_ENTRIES: MAX_LIST_ENTRIES,
    MAX_PATTERN_LENGTH: MAX_PATTERN_LENGTH,
    COLD_START_FALLBACK_PINS: COLD_START_FALLBACK_PINS,
    stripDesktop: stripDesktop,
    prettyClassName: prettyClassName,
    chromeAppHost: chromeAppHost,
    webAppHost: webAppHost,
    execBasename: execBasename,
    buildEntryIndex: buildEntryIndex,
    compileOverrides: compileOverrides,
    resolveIdentity: resolveIdentity,
    identityForKey: identityForKey,
    touchMru: touchMru,
    removeMru: removeMru,
    pruneMru: pruneMru,
    orderByMru: orderByMru,
    clickTarget: clickTarget,
    buildGroups: buildGroups,
    normalizePins: normalizePins,
    isValidPinKey: isValidPinKey,
    togglePin: togglePin,
    movePin: movePin,
    visiblePinCount: visiblePinCount,
    fallbackVisibleCount: fallbackVisibleCount,
    availableExtent: availableExtent,
    isDesktopId: isDesktopId,
    launchArgv: launchArgv,
    actionArgv: actionArgv,
    newWindowAction: newWindowAction,
    heuristicPlausible: heuristicPlausible,
    windowLocation: windowLocation,
    decodeHexUtf8: decodeHexUtf8,
    validateSetting: validateSetting,
    validatePins: validatePins,
    validateFavorites: validateFavorites,
    validateMatches: validateMatches,
    SETTING_SPEC: SETTING_SPEC,
    SETTING_KEYS: SETTING_KEYS
  }
}
