#!/usr/bin/env node
"use strict"

const assert = require("assert")
const path = require("path")
const P = require(path.join(__dirname, "..", "PlacesModel.js"))

let passed = 0
function test(name, fn) {
  try { fn(); passed++ } catch (e) { console.error("FAIL:", name); throw e }
}

const HOME = "/home/ada"
const USER_DIRS = `
# This file is written by xdg-user-dirs-update
XDG_DESKTOP_DIR="$HOME/"
XDG_DOWNLOAD_DIR="$HOME/Téléchargements"
XDG_DOCUMENTS_DIR="$HOME/My Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="/data/pics"
XDG_VIDEOS_DIR="$HOME/Videos"
XDG_PROJECTS_DIR="$HOME/Projects"
XDG_TEMPLATES_DIR="$HOME/"
`

const MOUNTS = { filesystems: [
  { target: "/", source: "/dev/mapper/root[/@]", fstype: "btrfs", label: "OMARCHY", partlabel: null, options: "rw", fsroot: "/@", children: [
    { target: "/home", source: "/dev/mapper/root[/@home]", fstype: "btrfs", label: "OMARCHY", options: "rw", fsroot: "/@home", children: [
      { target: "/home/ada/.cache/x", source: "/dev/nvme1n1p3[/x]", fstype: "ext4", label: null, options: "rw", fsroot: "/x" },
      { target: "/home/greyforge", source: "/dev/nvme1n1p3[/greyforge]", fstype: "ext4", label: null, options: "rw", fsroot: "/greyforge", children: [
        { target: "/home/greyforge/.openclaw", source: "/dev/nvme1n1p3[/greyforge/.openclaw]", fstype: "ext4", options: "ro", fsroot: "/greyforge/.openclaw" }
      ] }
    ] },
    { target: "/var/cache/pacman/pkg", source: "/dev/mapper/root[/@pkg]", fstype: "btrfs", label: "OMARCHY", options: "rw", fsroot: "/@pkg" },
    { target: "/boot", source: "/dev/nvme0n1p1", fstype: "vfat", label: null, options: "rw", fsroot: "/" },
    { target: "/run/media/ada/OMARCHY_202609", source: "/dev/sda1", fstype: "ntfs3", label: "OMARCHY_202609", options: "rw", fsroot: "/" },
    { target: "/run/media/ada/OMARCHY_202609", source: "/dev/sda1", fstype: "ntfs3", label: "OMARCHY_202609", options: "rw", fsroot: "/" },
    { target: "/mnt/ubuntu", source: "/dev/nvme0n1p5", fstype: "ext4", label: "Ubuntu", options: "rw", fsroot: "/" },
    { target: "/mnt/win", source: "/dev/nvme0n1p3", fstype: "ntfs3", label: "", partlabel: "Basic data partition", options: "rw", fsroot: "/" },
    { target: "/mnt/nas", source: "nas.local:/export/media", fstype: "nfs4", label: null, options: "rw", fsroot: "/" },
    { target: "/run/user/1000/doc", source: "portal", fstype: "fuse.portal", options: "rw", fsroot: "/" },
    { target: "/tmp", source: "tmpfs", fstype: "tmpfs", options: "rw", fsroot: "/" },
    { target: "/mnt/greyforge-data", source: "/dev/nvme1n1p3", fstype: "ext4", label: null, options: "rw", fsroot: "/" },
    { target: "/mnt/hidden", source: "/dev/sdb1", fstype: "ext4", label: "Hidden", options: "rw,x-gvfs-hide", fsroot: "/" }
  ] }
] }

test("parseUserDirs expands $HOME and keeps unicode/spaces", () => {
  const d = P.parseUserDirs(USER_DIRS, HOME)
  assert.strictEqual(d.DOWNLOAD, "/home/ada/Téléchargements")
  assert.strictEqual(d.DOCUMENTS, "/home/ada/My Documents")
  assert.strictEqual(d.PICTURES, "/data/pics")
  assert.strictEqual(d.DESKTOP, "/home/ada")
  assert.strictEqual(d.PROJECTS, "/home/ada/Projects")
})

test("xdgEntries omits Home-fallback dirs and missing dirs; Home first", () => {
  const d = P.parseUserDirs(USER_DIRS, HOME)
  const exists = { "/home/ada/Téléchargements": true, "/home/ada/My Documents": true, "/home/ada/Music": false, "/data/pics": true, "/home/ada/Videos": true }
  const rows = P.xdgEntries(d, HOME, exists, { showVideos: false })
  assert.deepStrictEqual(rows.map(r => r.name), ["Home", "Downloads", "Documents", "Pictures"])
  assert.strictEqual(rows[0].path, HOME)
  assert.strictEqual(rows[1].path, "/home/ada/Téléchargements")
})

test("favorites: expansion, dedupe, no commands, missing dropped", () => {
  const favs = [
    { name: "Projects", path: "~/Projects" },
    { path: "$HOME/Projects" },
    { name: "Evil", path: "/tmp", exec: "rm -rf /" },
    { name: "Missing", path: "~/nope" },
    "~/Work",
    { name: "Rel", path: "relative/path" },
    { name: "Quoted", path: "/srv/it's \"here\"" },
    null, 42
  ]
  const exists = { "/home/ada/Projects": true, "/home/ada/nope": false, "/home/ada/Work": true, "/srv/it's \"here\"": true }
  const rows = P.favoriteEntries(favs, HOME, exists, {})
  assert.deepStrictEqual(rows.map(r => r.name), ["Projects", "Work", "Quoted"])
  assert.strictEqual(rows[2].path, "/srv/it's \"here\"")
})

test("mounts: pseudo, system, subvolumes, hidden, duplicates excluded; labels preferred", () => {
  const rows = P.mountEntries(MOUNTS, HOME, {})
  const names = rows.map(r => r.name)
  assert.deepStrictEqual(names, ["greyforge", "greyforge-data", "nas", "OMARCHY_202609", "Ubuntu", "win"])
  assert.ok(!rows.some(r => r.path === "/" || r.path === "/home" || r.path === "/boot" || r.path === "/tmp"))
  assert.ok(!rows.some(r => r.path.indexOf("/.") !== -1))
  assert.strictEqual(rows.filter(r => r.path === "/run/media/ada/OMARCHY_202609").length, 1)
  assert.strictEqual(rows.find(r => r.name === "nas").glyph, "󰒍")
})

test("mounts: garbage input never throws", () => {
  assert.deepStrictEqual(P.mountEntries(null, HOME, {}), [])
  assert.deepStrictEqual(P.mountEntries("nonsense", HOME, {}), [])
  assert.deepStrictEqual(P.mountEntries({ filesystems: [{ target: 42 }] }, HOME, {}), [])
})

test("trash: scheme handler, files dir fallback, hidden otherwise", () => {
  assert.strictEqual(P.trashEntry(true, "", {}).path, "trash:///")
  assert.strictEqual(P.trashEntry(false, "/home/ada/.local/share/Trash/files", { "/home/ada/.local/share/Trash/files": true }).path, "/home/ada/.local/share/Trash/files")
  assert.strictEqual(P.trashEntry(false, "/home/ada/.local/share/Trash/files", {}), null)
})

test("buildPlaces assembles sections and drops empty ones", () => {
  const input = {
    home: HOME,
    userDirs: P.parseUserDirs(USER_DIRS, HOME),
    exists: { "/home/ada/Téléchargements": true, "/home/ada/Projects": true, "/home/ada/.local/share/Trash/files": true,
              "/home/ada/My Documents": false, "/home/ada/Music": false, "/data/pics": false, "/home/ada/Videos": false },
    mounts: MOUNTS,
    trashHandler: false,
    settings: { favorites: [{ name: "Projects", path: "~/Projects" }], showDocuments: true }
  }
  const sections = P.buildPlaces(input)
  assert.deepStrictEqual(sections.map(s => s.id), ["places", "favorites", "drives", "system"])
  assert.deepStrictEqual(sections[0].rows.map(r => r.name), ["Home", "Downloads"])
  assert.deepStrictEqual(sections[3].rows.map(r => r.name), ["Trash", "Open File Manager"])
  const noMounts = P.buildPlaces(Object.assign({}, input, { settings: { showMounts: false, showTrash: false } }))
  assert.deepStrictEqual(noMounts.map(s => s.id), ["places", "system"])
  assert.deepStrictEqual(noMounts[1].rows.map(r => r.name), ["Open File Manager"])
})

test("candidatePaths covers xdg, favorites and trash", () => {
  const paths = P.candidatePaths({ home: HOME, userDirs: { DOWNLOAD: "/home/ada/Dl" }, settings: { favorites: ["~/Work", { path: "/x" }, { path: "rel" }] } })
  assert.deepStrictEqual(paths, ["/home/ada/Dl", "/home/ada/Work", "/x", "/home/ada/.local/share/Trash/files"])
})

test("openArgv is argv-only and refuses non-paths", () => {
  assert.deepStrictEqual(P.openArgv("/home/ada/My Documents"), ["uwsm-app", "--", "xdg-open", "/home/ada/My Documents"])
  assert.deepStrictEqual(P.openArgv("/x; rm -rf /"), ["uwsm-app", "--", "xdg-open", "/x; rm -rf /"])
  assert.deepStrictEqual(P.openArgv("trash:///"), ["uwsm-app", "--", "gio", "open", "trash:///"])
  assert.strictEqual(P.openArgv("file:///etc"), null)
  assert.strictEqual(P.openArgv("$(id)"), null)
  assert.strictEqual(P.openArgv(""), null)
})

console.log("PlacesModel: " + passed + " tests passed")
