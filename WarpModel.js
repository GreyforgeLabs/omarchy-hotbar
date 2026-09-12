// Hotbar cursor-warp UI bridge (0.2.3).
//
// Pure, deterministic mapping between the 0.2.2 `hotbar warp` backend and
// the Settings popover's "Keep pointer in place" toggle. QML imports this
// file; node tests require() it. No I/O, no Hyprland, no timers.
//
// The UX is expressed positively ("Keep pointer in place") while the CLI
// describes the compositor feature being disabled. The inversion is
// intentional and lives in exactly one place — warpModeForKeep() /
// keepPointerInPlace() below:
//
//   Keep ON  (true)  <=> warps disabled <=> `hotbar warp off` (exit 0)
//   Keep OFF (false) <=> warps enabled  <=> `hotbar warp on`  (exit 1)
//   unknown          <=> null (indeterminate — never guess)
//
// QML must invoke the existing backend via discrete argv
// (warpArgv(pluginDir, mode)); nothing here builds a shell command, and the
// managed config block stays canonical in bin/hotbar.

var WARP_DISABLED = "disabled"
var WARP_ENABLED = "enabled"
var WARP_UNKNOWN = "unknown"

var KEEP_PRIMARY = "Keep pointer in place"
var KEEP_SECONDARY = "Prevent Hyprland from moving the pointer when Hotbar focuses a window. Applies system-wide to Hyprland."
var KEEP_SECONDARY_UNKNOWN = "Could not read the Hyprland pointer setting. Applies system-wide to Hyprland."
var KEEP_ERROR = "Could not change pointer behavior."

var APPLY_ERROR = KEEP_ERROR

function str(value) {
  return value === undefined || value === null ? "" : String(value)
}

// Parse `hotbar warp status` output. Exit codes are the primary signal
// (0 disabled, 1 enabled, 2 unknown); the output text cross-checks so a
// stale or garbled answer can never present a false confirmed state.
// Returns { state, details } where details is the first output line for
// logs/diagnostics (never a GUI label).
function parseWarpStatus(output, exitCode) {
  var text = str(output)
  var lines = text.split(/\r?\n/).map(function(l) { return l.trim() }).filter(function(l) { return l.length > 0 })
  var first = lines.length ? lines[0] : ""
  var code = Number(exitCode)

  if (first.indexOf("unknown") === 0) return { state: WARP_UNKNOWN, details: first }

  var parsed = parseWarpDetailsLine(first)

  if (code === 2) return { state: WARP_UNKNOWN, details: first }
  if (code === 0) {
    if (parsed && parsed.disabled) return { state: WARP_DISABLED, details: first }
    if (/warps disabled/.test(text)) return { state: WARP_DISABLED, details: first }
    return { state: WARP_UNKNOWN, details: first }
  }
  if (code === 1) {
    if (parsed && !parsed.disabled) return { state: WARP_ENABLED, details: first }
    if (/warps enabled/.test(text)) return { state: WARP_ENABLED, details: first }
    // Exit 1 without a readable body still means "not disabled", but without
    // evidence of what the compositor reported, refuse to claim a state.
    if (parsed) return { state: WARP_ENABLED, details: first }
    return { state: WARP_UNKNOWN, details: first }
  }
  return { state: WARP_UNKNOWN, details: first }
}

// Parse the `no_warps=<v> warp_workspace=<v> warp_special=<v>` details line.
// Returns { disabled: true|false } or null when unreadable.
function parseWarpDetailsLine(line) {
  var text = str(line)
  var noWarps = /no_warps=([^\s]+)/.exec(text)
  var workspace = /warp_workspace=([^\s]+)/.exec(text)
  if (!noWarps || !workspace) return null
  return { disabled: noWarps[1] === "true" && workspace[1] === "0" }
}

// Warp backend state -> toggle position. null = indeterminate (never guess).
function keepPointerInPlace(warpState) {
  var s = str(warpState)
  if (s === WARP_DISABLED) return true
  if (s === WARP_ENABLED) return false
  return null
}

// Toggle position -> backend mode. null = refuse (unknown must not act blind).
function warpModeForKeep(keepOn) {
  if (keepOn === true) return "off"
  if (keepOn === false) return "on"
  return null
}

// Discrete argv for invoking the existing backend from QML Process.
// No shell, no concatenation into a command string; the mode allowlist is
// the injection boundary. Returns null on invalid input.
function warpArgv(pluginDir, mode) {
  var dir = str(pluginDir)
  var m = str(mode)
  if (!dir) return null
  if (m !== "status" && m !== "off" && m !== "on") return null
  return [dir + "/bin/hotbar", "warp", m]
}

// Presentation data for the Settings row. `busy` covers both the opening
// query and the apply+re-read cycle: trailing "…" and disabled, never a
// claimed state. Callers add onActivate (toggle) and an optional danger
// error row using APPLY_ERROR.
function rowData(warpState, busy) {
  var keep = keepPointerInPlace(warpState)
  var isBusy = busy === true
  if (keep === null) {
    return {
      primary: KEEP_PRIMARY,
      secondary: KEEP_SECONDARY_UNKNOWN,
      trailing: isBusy ? "…" : "Unavailable",
      glyph: "󰄱",
      enabled: false,
      keep: null
    }
  }
  return {
    primary: KEEP_PRIMARY,
    secondary: KEEP_SECONDARY,
    trailing: isBusy ? "…" : (keep ? "On" : "Off"),
    glyph: keep ? "󰄲" : "󰄱",
    enabled: !isBusy,
    keep: keep
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    WARP_DISABLED: WARP_DISABLED,
    WARP_ENABLED: WARP_ENABLED,
    WARP_UNKNOWN: WARP_UNKNOWN,
    KEEP_PRIMARY: KEEP_PRIMARY,
    KEEP_SECONDARY: KEEP_SECONDARY,
    KEEP_SECONDARY_UNKNOWN: KEEP_SECONDARY_UNKNOWN,
    KEEP_ERROR: KEEP_ERROR,
    APPLY_ERROR: APPLY_ERROR,
    parseWarpStatus: parseWarpStatus,
    parseWarpDetailsLine: parseWarpDetailsLine,
    keepPointerInPlace: keepPointerInPlace,
    warpModeForKeep: warpModeForKeep,
    warpArgv: warpArgv,
    rowData: rowData
  }
}
