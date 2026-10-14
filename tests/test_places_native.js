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

// Fixture mountinfo/utab (HOTBAR_MOUNTINFO / HOTBAR_UTAB): the kernel's
// octal escapes, an empty source field, the vfs+superblock option merge,
// utab options joined by escaped target, and pseudo filesystems dropped.
// Device numbers are anonymous (0:N) and the sources do not exist, so no
// host label can attach.
const MOUNTINFO = [
  "21 1 0:19 / /proc rw,nosuid,nodev,noexec,relatime shared:12 - proc proc rw",
  "30 1 0:300 / / rw,relatime shared:1 - ext4 /dev/hbtest-root rw",
  "40 30 0:301 / /run/media/ada/My\\040Disk rw,nosuid,nodev,relatime shared:200 - exfat /dev/hbtest-usb rw,uid=1000,iocharset=utf8",
  "41 30 0:302 / /mnt/back\\134slash\\011tab rw,relatime - ext4 /dev/hbtest-b ro,errors=remount-ro",
  "42 30 0:303 / /mnt/blank rw,relatime - fuse.mything  rw,user_id=1000",
  "43 30 0:304 /sub /mnt/sub rw,relatime shared:5 master:1 - btrfs /dev/hbtest-c rw,subvol=/sub",
  "44 30 0:305 / /mnt/hide rw - ext4 /dev/hbtest-d rw",
  "45 30 0:306 / /mnt/truncated rw"
].join("\n") + "\n"
const UTAB = "ID=40 SRC=/dev/hbtest-usb TARGET=/run/media/ada/My\\040Disk ROOT=/ OPTS=x-udisks-auth\n" +
  "ID=44 SRC=/dev/hbtest-d TARGET=/mnt/hide ROOT=/ OPTS=x-gvfs-hide\n"

test("fixture mountinfo: escapes, empty source, option merge, utab", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "hotbar-mountinfo-"))
  fs.writeFileSync(path.join(dir, "mountinfo"), MOUNTINFO)
  fs.writeFileSync(path.join(dir, "utab"), UTAB)
  const env = Object.assign({}, process.env, { HOTBAR_MOUNTINFO: path.join(dir, "mountinfo"), HOTBAR_UTAB: path.join(dir, "utab") })
  const out = JSON.parse(execFileSync(native, [], { encoding: "utf8", timeout: 5000, env }))
  fs.rmSync(dir, { recursive: true, force: true })
  const got = out.mounts.filesystems.map(m => [m.target, m.source, m.fstype, m.options, m.fsroot, m.label, m.partlabel])
  assert.deepStrictEqual(got, [
    ["/", "/dev/hbtest-root", "ext4", "rw,relatime", "/", null, null],
    ["/run/media/ada/My Disk", "/dev/hbtest-usb", "exfat", "rw,nosuid,nodev,relatime,uid=1000,iocharset=utf8,x-udisks-auth", "/", null, null],
    ["/mnt/back\\slash\ttab", "/dev/hbtest-b", "ext4", "rw,relatime,errors=remount-ro", "/", null, null],
    ["/mnt/blank", "", "fuse.mything", "rw,relatime,user_id=1000", "/", null, null],
    ["/mnt/sub", "/dev/hbtest-c", "btrfs", "rw,relatime,subvol=/sub", "/sub", null, null],
    ["/mnt/hide", "/dev/hbtest-d", "ext4", "rw,x-gvfs-hide", "/", null, null]
  ])
  const drives = P.mountEntries(out.mounts, "/home/ada", {})
  assert.deepStrictEqual(drives.map(d => d.name + " -> " + d.path), [
    "back\\slash\ttab -> /mnt/back\\slash\ttab", "blank -> /mnt/blank", "My Disk -> /run/media/ada/My Disk", "sub -> /mnt/sub"
  ])
})

fs.rmSync(tmp, { recursive: true, force: true })
console.log("PlacesNative: " + passed + " tests passed")
