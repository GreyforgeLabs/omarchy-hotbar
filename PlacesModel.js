// Hotbar — Places model. Pure functions over text/JSON gathered by
// bin/hotbar-places; QML imports this, node tests require() it.
//
// Paths are data, never command fragments. Everything returned here is
// handed to Quickshell.execDetached as a discrete argv element.

var SYSTEM_TARGETS = {
  "/": true, "/home": true, "/root": true, "/boot": true, "/boot/efi": true, "/efi": true, "/esp": true,
  "/usr": true, "/var": true, "/opt": true, "/srv": true, "/tmp": true, "/nix": true, "/nix/store": true,
  "/snap": true, "/var/lib/snapd": true
}
var SYSTEM_PREFIXES = ["/boot/", "/usr/", "/var/", "/proc", "/sys", "/dev", "/run/user/", "/run/credentials", "/run/systemd",
  "/nix/", "/snap/", "/tmp/", "/opt/", "/srv/", "/etc/", "/root/", "/var/lib/"]
var USER_PREFIXES = ["/run/media/", "/media/", "/mnt/"]
var PSEUDO_FSTYPES = {
  proc: true, sysfs: true, devtmpfs: true, devpts: true, tmpfs: true, cgroup: true, cgroup2: true, pstore: true,
  bpf: true, securityfs: true, debugfs: true, tracefs: true, configfs: true, mqueue: true, hugetlbfs: true,
  fusectl: true, autofs: true, efivarfs: true, binfmt_misc: true, overlay: true, squashfs: true, ramfs: true,
  nsfs: true, rpc_pipefs: true, fuse: true, "fuse.portal": true, "fuse.gvfsd-fuse": true, "fuse.snapfuse": true,
  "fuse.appimagelauncherfs": true, "fuse.rclone": false, "fuse.sshfs": false, "fuse.encfs": false
}

function str(value) {
  return value === undefined || value === null ? "" : String(value)
}

function expandHome(path, home) {
  var value = str(path).trim()
  var h = str(home).replace(/\/+$/, "")
  if (value === "~") return h
  if (value.indexOf("~/") === 0) return h + value.slice(1)
  value = value.replace(/^\$HOME(?=\/|$)/, h).replace(/^\$\{HOME\}(?=\/|$)/, h)
  return value
}

function normalizePath(path) {
  var value = str(path)
  if (!value) return ""
  value = value.replace(/\/{2,}/g, "/")
  if (value.length > 1) value = value.replace(/\/+$/, "")
  return value
}

function basename(path) {
  var value = normalizePath(path)
  var idx = value.lastIndexOf("/")
  return idx === -1 ? value : value.slice(idx + 1)
}

// ------------------------------------------------------- XDG directories

var XDG_ORDER = [
  { key: "DESKTOP", id: "desktop", name: "Desktop", icon: "user-desktop", glyph: "󰇄", setting: "showDesktop" },
  { key: "DOWNLOAD", id: "downloads", name: "Downloads", icon: "folder-download", glyph: "󰉍", setting: "showDownloads" },
  { key: "DOCUMENTS", id: "documents", name: "Documents", icon: "folder-documents", glyph: "󱧶", setting: "showDocuments" },
  { key: "PICTURES", id: "pictures", name: "Pictures", icon: "folder-pictures", glyph: "󰉏", setting: "showPictures" },
  { key: "MUSIC", id: "music", name: "Music", icon: "folder-music", glyph: "󱍙", setting: "showMusic" },
  { key: "VIDEOS", id: "videos", name: "Videos", icon: "folder-videos", glyph: "󱧺", setting: "showVideos" }
]

// Parse ~/.config/user-dirs.dirs. Lines look like
//   XDG_DOWNLOAD_DIR="$HOME/Downloads"
// Values may be quoted, may use $HOME, may be absolute. Unknown keys are kept
// too (XDG_PROJECTS_DIR exists in the wild).
function parseUserDirs(text, home) {
  var out = {}
  var lines = str(text).split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.charAt(0) === "#") continue
    var m = /^XDG_([A-Z0-9_]+)_DIR\s*=\s*(.*)$/.exec(line)
    if (!m) continue
    var raw = m[2].trim()
    if (raw.length >= 2 && (raw.charAt(0) === '"' || raw.charAt(0) === "'") && raw.charAt(raw.length - 1) === raw.charAt(0)) {
      raw = raw.slice(1, -1)
    }
    raw = raw.replace(/\\(.)/g, "$1")
    var path = normalizePath(expandHome(raw, home))
    if (path && path.charAt(0) === "/") out[m[1]] = path
  }
  return out
}

// Build the XDG section. `dirs` from parseUserDirs, `exists` is a map
// path -> bool from the helper, `settings` carries the show* toggles.
// Home is always first. Entries that resolve to Home (the XDG fallback when a
// directory is unset) or to a missing directory are omitted.
function xdgEntries(dirs, home, exists, settings) {
  var h = normalizePath(home)
  var cfg = settings || {}
  var out = [{ id: "home", name: "Home", path: h, icon: "user-home", glyph: "󰋜", section: "places" }]
  var seen = {}
  seen[h] = true
  var known = dirs || {}
  var ex = exists || {}
  for (var i = 0; i < XDG_ORDER.length; i++) {
    var spec = XDG_ORDER[i]
    if (cfg[spec.setting] === false) continue
    var path = normalizePath(known[spec.key] || "")
    if (!path || path === h) continue
    if (ex[path] === false) continue
    if (seen[path]) continue
    seen[path] = true
    out.push({ id: spec.id, name: spec.name, path: path, icon: spec.icon, glyph: spec.glyph, section: "places" })
  }
  return out
}

// ------------------------------------------------------------ favorites

// settings.favorites: [{ name, path }] — paths only. Objects carrying exec,
// command, or args are rejected outright rather than partially honoured.
function favoriteEntries(favorites, home, exists, taken) {
  var out = []
  var list = Array.isArray(favorites) ? favorites : []
  var seen = {}
  var used = taken || {}
  var ex = exists || {}
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    var name = "", rawPath = ""
    if (typeof item === "string") rawPath = item
    else if (item && typeof item === "object" && !Array.isArray(item)) {
      if ("exec" in item || "command" in item || "args" in item || "run" in item) continue
      name = str(item.name).trim()
      rawPath = str(item.path)
    }
    var path = normalizePath(expandHome(rawPath, home))
    if (!path || path.charAt(0) !== "/") continue
    if (ex[path] === false) continue
    if (seen[path] || used[path]) continue
    seen[path] = true
    out.push({ id: "fav:" + path, name: name || basename(path) || path, path: path, icon: "folder", glyph: "󰓎", section: "favorites" })
  }
  return out
}

// ---------------------------------------------------------------- mounts

function flattenMounts(node, out) {
  if (!node) return out
  if (Array.isArray(node)) {
    for (var i = 0; i < node.length; i++) flattenMounts(node[i], out)
    return out
  }
  if (typeof node === "object") {
    if (node.target !== undefined) out.push(node)
    if (Array.isArray(node.children)) flattenMounts(node.children, out)
  }
  return out
}

function hasHiddenComponent(path) {
  var parts = normalizePath(path).split("/")
  for (var i = 1; i < parts.length; i++) if (parts[i].charAt(0) === "." && parts[i].length > 1) return true
  return false
}

function isSystemTarget(target) {
  var t = normalizePath(target)
  if (SYSTEM_TARGETS[t]) return true
  for (var i = 0; i < SYSTEM_PREFIXES.length; i++) if (t.indexOf(SYSTEM_PREFIXES[i]) === 0) return true
  return false
}

function isUserTarget(target) {
  var t = normalizePath(target)
  for (var i = 0; i < USER_PREFIXES.length; i++) if (t.indexOf(USER_PREFIXES[i]) === 0) return true
  return false
}

function isRealFs(fstype) {
  var ft = str(fstype).toLowerCase()
  if (!ft) return false
  if (PSEUDO_FSTYPES[ft] === true) return false
  if (PSEUDO_FSTYPES[ft] === false) return true
  if (ft.indexOf("fuse.") === 0) return true
  return true
}

function mountLabel(fs) {
  var label = str(fs.label).trim()
  if (label) return label
  var part = str(fs.partlabel).trim()
  if (part && !/^(basic data partition|linux filesystem|efi system partition|microsoft reserved partition)$/i.test(part)) return part
  var base = basename(fs.target)
  if (base) return base
  return str(fs.source).split("/").pop() || str(fs.target)
}

function mountGlyph(fs) {
  var ft = str(fs.fstype).toLowerCase()
  var t = normalizePath(fs.target)
  var src = str(fs.source)
  if (/^(nfs|nfs4|cifs|smb3|sshfs|fuse\.sshfs|fuse\.rclone|davfs|9p|afs|ceph)$/.test(ft) || /^[^\/]+:\//.test(src)) return "󰒍"
  if (ft === "ntfs" || ft === "ntfs3" || ft === "exfat" || ft === "vfat") return t.indexOf("/run/media/") === 0 ? "󱊞" : "󰋊"
  if (t.indexOf("/run/media/") === 0 || t.indexOf("/media/") === 0) return "󱊞"
  return "󰋊"
}

// findmntJson: parsed `findmnt -J --real` output (or null). home: the user's
// home path. Returns the Drives section, deduplicated by (source, fsroot).
function mountEntries(findmntJson, home, exists) {
  var list = []
  try {
    var root = findmntJson && findmntJson.filesystems ? findmntJson.filesystems : findmntJson
    flattenMounts(root, list)
  } catch (e) {
    return []
  }
  var h = normalizePath(home)
  var ex = exists || {}
  var out = []
  var seenTarget = {}
  var seenSource = {}
  var rootSource = ""
  for (var r = 0; r < list.length; r++) if (normalizePath(list[r].target) === "/") rootSource = str(list[r].source).replace(/\[.*\]$/, "")
  for (var i = 0; i < list.length; i++) {
    var fs = list[i]
    var target = normalizePath(fs.target)
    if (!target || target.charAt(0) !== "/") continue
    if (!isRealFs(fs.fstype)) continue
    if (target === h) continue
    if (isSystemTarget(target) && !isUserTarget(target)) continue
    if (hasHiddenComponent(target)) continue
    if (target.indexOf("/run/") === 0 && !isUserTarget(target)) continue
    if (target.indexOf(h + "/.") === 0) continue
    var opts = str(fs.options)
    if (/(^|,)x-gvfs-hide(,|$)/.test(opts) || /(^|,)x-omarchy-hide(,|$)/.test(opts)) continue
    var baseSource = str(fs.source).replace(/\[.*\]$/, "")
    var fsroot = str(fs.fsroot) || (/\[(.*)\]$/.exec(str(fs.source)) || [])[1] || "/"
    // Subvolumes of the root filesystem (btrfs @home, @log, @pkg…) are the
    // system disk, not a drive.
    if (baseSource && baseSource === rootSource && !isUserTarget(target)) continue
    if (seenTarget[target]) continue
    var sourceKey = baseSource + "|" + fsroot
    if (baseSource && seenSource[sourceKey]) continue
    if (ex[target] === false) continue
    seenTarget[target] = true
    if (baseSource) seenSource[sourceKey] = true
    out.push({
      id: "mount:" + target,
      name: mountLabel(fs),
      path: target,
      icon: "drive-harddisk",
      glyph: mountGlyph(fs),
      fstype: str(fs.fstype),
      section: "drives"
    })
  }
  out.sort(function(a, b) {
    var na = a.name.toLowerCase(), nb = b.name.toLowerCase()
    return na < nb ? -1 : na > nb ? 1 : 0
  })
  return out
}

// ----------------------------------------------------------------- trash

// Trash target: trash:/// when a scheme handler exists, else the physical
// files directory if present, else nothing (entry hidden).
function trashEntry(hasSchemeHandler, trashFilesPath, exists) {
  if (hasSchemeHandler) return { id: "trash", name: "Trash", path: "trash:///", icon: "user-trash", glyph: "󰩹", section: "system" }
  var p = normalizePath(trashFilesPath)
  if (p && exists && exists[p] === true) return { id: "trash", name: "Trash", path: p, icon: "user-trash", glyph: "󰩹", section: "system" }
  return null
}

// -------------------------------------------------------------- assembly

// Full popover model. Sections with no rows are omitted.
function buildPlaces(input) {
  var inp = input || {}
  var home = normalizePath(inp.home)
  var exists = inp.exists || {}
  var settings = inp.settings || {}
  var sections = []
  var taken = {}

  var xdg = xdgEntries(inp.userDirs || {}, home, exists, settings)
  for (var i = 0; i < xdg.length; i++) taken[xdg[i].path] = true
  if (xdg.length) sections.push({ id: "places", title: "Places", rows: xdg })

  var favs = favoriteEntries(settings.favorites, home, exists, taken)
  for (var f = 0; f < favs.length; f++) taken[favs[f].path] = true
  if (favs.length) sections.push({ id: "favorites", title: "Favorites", rows: favs })

  if (settings.showMounts !== false) {
    var mounts = mountEntries(inp.mounts, home, exists).filter(function(m) { return !taken[m.path] })
    if (mounts.length) sections.push({ id: "drives", title: "Drives", rows: mounts })
  }

  var system = []
  if (settings.showTrash !== false) {
    var trash = trashEntry(inp.trashHandler === true, home ? home + "/.local/share/Trash/files" : "", exists)
    if (trash) system.push(trash)
  }
  system.push({ id: "filemanager", name: "Open File Manager", path: home, icon: "system-file-manager", glyph: "󰉋", section: "system" })
  sections.push({ id: "system", title: "", rows: system })

  return sections
}

// Every path the helper should stat, so missing entries can be dropped.
function candidatePaths(input) {
  var inp = input || {}
  var home = normalizePath(inp.home)
  var out = []
  var seen = {}
  function add(p) {
    var v = normalizePath(p)
    if (v && v.charAt(0) === "/" && !seen[v]) { seen[v] = true; out.push(v) }
  }
  var dirs = inp.userDirs || {}
  for (var k in dirs) add(dirs[k])
  var favs = Array.isArray(inp.settings && inp.settings.favorites) ? inp.settings.favorites : []
  for (var i = 0; i < favs.length; i++) {
    var item = favs[i]
    add(expandHome(typeof item === "string" ? item : (item && item.path), home))
  }
  if (home) add(home + "/.local/share/Trash/files")
  return out
}

function flatRows(sections) {
  var out = []
  var list = Array.isArray(sections) ? sections : []
  for (var i = 0; i < list.length; i++) for (var j = 0; j < list[i].rows.length; j++) out.push(list[i].rows[j])
  return out
}

// argv to open a place with the registered handler. trash:/// goes through
// gio (it understands the scheme); paths go through xdg-open.
function openArgv(path) {
  var p = str(path)
  if (!p) return null
  if (p === "trash:///") return ["uwsm-app", "--", "gio", "open", "trash:///"]
  if (p.charAt(0) !== "/") return null
  return ["uwsm-app", "--", "xdg-open", p]
}

if (typeof module !== "undefined") {
  module.exports = {
    expandHome: expandHome,
    normalizePath: normalizePath,
    parseUserDirs: parseUserDirs,
    xdgEntries: xdgEntries,
    favoriteEntries: favoriteEntries,
    mountEntries: mountEntries,
    mountLabel: mountLabel,
    trashEntry: trashEntry,
    buildPlaces: buildPlaces,
    candidatePaths: candidatePaths,
    flatRows: flatRows,
    openArgv: openArgv
  }
}
