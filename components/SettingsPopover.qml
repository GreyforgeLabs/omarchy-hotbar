import QtQuick
import qs.Commons
import "../WarpModel.js" as Warp

// Hotbar Settings: every toggle the widget honours, flipped from the bar.
// Booleans toggle on click; enums cycle (left = next, right = previous);
// numbers step (left = up, right = down, wrapping at the limits). Writes
// go through persistSettings, so shell.json and the backup mirror stay in
// sync. Pins, favourites and match overrides stay in the CLI — they are
// lists, not toggles.
//
// "Keep pointer in place" is not a bar setting: it reflects the real
// Hyprland cursor-warp state via the 0.2.2 `hotbar warp` backend (queried
// fresh on every open, confirmed again after each change). Keep ON means
// warps are disabled (`warp off`); Keep OFF restores Omarchy defaults
// (`warp on`). Unknown state never guesses — it shows Unavailable.
HotbarPopover {
  id: root
  kind: "settings"

  title: "Hotbar Settings"
  emptyText: "No settings."
  preferredWidth: Style.space(320)

  rows: {
    // Dependencies: rebuild when the settings change or the popover opens.
    var dep = hotbar ? hotbar.effectiveSettings : null
    var depOpen = open
    var warpDep = hotbar ? String(hotbar.warpState) + "|" + String(hotbar.warpBusy) + "|" + String(hotbar.warpError) : ""
    if (!open && !dep && !warpDep) return []
    return buildRows()
  }

  function boolRow(label, key, fallback) {
    var on = hotbar ? hotbar.setting(key, fallback) !== false : fallback !== false
    var off = !on
    return {
      kind: "row",
      primary: label,
      trailing: on ? "On" : "Off",
      glyph: on ? "󰄲" : "󰄱",
      onActivate: (function(k, v) {
        return function() { if (root.hotbar) { var p = {}; p[k] = v; root.hotbar.persistSettings(p) } }
      })(key, off)
    }
  }

  function enumRow(label, key, options, fallback) {
    var cur = hotbar ? String(hotbar.setting(key, fallback)) : String(fallback)
    if (options.indexOf(cur) === -1) cur = fallback
    return {
      kind: "row",
      primary: label,
      trailing: cur,
      glyph: "󰁔",
      onActivate: (function(k, opts, current) {
        return function(button) {
          if (!root.hotbar) return
          var idx = opts.indexOf(current)
          if (idx === -1) idx = 0
          var dir = button === 2 ? -1 : 1
          var next = opts[(idx + dir + opts.length) % opts.length]
          var p = {}
          p[k] = next
          root.hotbar.persistSettings(p)
        }
      })(key, options, cur)
    }
  }

  function intRow(label, key, fallback, min, max, step, suffix) {
    var cur = hotbar ? Math.round(Number(hotbar.setting(key, fallback))) : fallback
    if (!isFinite(cur)) cur = fallback
    cur = Math.max(min, Math.min(max, cur))
    return {
      kind: "row",
      primary: label,
      trailing: cur + (suffix || ""),
      glyph: "󰁔",
      onActivate: (function(k, current, lo, hi, st) {
        return function(button) {
          if (!root.hotbar) return
          var d = button === 2 ? -st : st
          var next = current + d
          if (next > hi) next = lo
          if (next < lo) next = hi
          var p = {}
          p[k] = next
          root.hotbar.persistSettings(p)
        }
      })(key, cur, min, max, step)
    }
  }

  function warpRow() {
    var state = hotbar ? String(hotbar.warpState || "unknown") : "unknown"
    var busy = hotbar ? hotbar.warpBusy === true : false
    var w = Warp.rowData(state, busy)
    return {
      kind: "row",
      primary: w.primary,
      secondary: w.secondary,
      trailing: w.trailing,
      glyph: w.glyph,
      enabled: w.enabled,
      onActivate: function() {
        if (!root.hotbar || root.hotbar.warpBusy === true) return
        var keep = Warp.keepPointerInPlace(String(root.hotbar.warpState || "unknown"))
        if (keep === null || keep === undefined) return
        root.hotbar.setKeepPointerInPlace(!keep)
      }
    }
  }

  function buildRows() {
    if (!hotbar) return []
    var out = []
    out.push({ kind: "header", title: "Appearance" })
    out.push(intRow("Icon size", "iconSize", 18, 12, 24, 1, " px"))
    out.push(intRow("Cell spacing", "spacing", 2, 0, 12, 1, " px"))
    out.push(enumRow("Icon style", "iconStyle", ["color", "mono"], "color"))
    out.push(enumRow("Running indicator", "runningIndicator", ["underline", "dot", "none"], "underline"))
    out.push(boolRow("Section separators", "separators", true))
    out.push(boolRow("Animations", "animations", true))
    out.push({ kind: "header", title: "Behaviour" })
    out.push(boolRow("Hover previews", "previews", true))
    out.push(intRow("Preview delay", "previewDelay", 450, 100, 1500, 50, " ms"))
    out.push(boolRow("Mouse wheel cycles windows", "wheelCycle", true))
    out.push(enumRow("Middle click", "middleClick", ["new-window", "none"], "new-window"))
    out.push(boolRow("Responsive overflow", "responsive", true))
    out.push(warpRow())
    if (String(hotbar.warpError || "") !== "") {
      out.push({
        kind: "row", primary: String(hotbar.warpError), secondary: "",
        glyph: "󰀨", danger: true, enabled: false, onActivate: function() {}
      })
    }
    out.push({ kind: "header", title: "Visible cells" })
    out.push(boolRow("Show Places", "showPlaces", true))
    out.push(boolRow("Show Running drawer", "showRunning", true))
    out.push({ kind: "header", title: "Places sections" })
    out.push(boolRow("Desktop", "showDesktop", true))
    out.push(boolRow("Downloads", "showDownloads", true))
    out.push(boolRow("Documents", "showDocuments", true))
    out.push(boolRow("Pictures", "showPictures", true))
    out.push(boolRow("Music", "showMusic", true))
    out.push(boolRow("Videos", "showVideos", true))
    out.push(boolRow("Trash", "showTrash", true))
    out.push(boolRow("Mounted drives", "showMounts", true))
    out.push({ kind: "separator" })
    out.push({
      kind: "row", primary: "Pins, favourites, overrides via CLI", secondary: "hotbar pin <app> · hotbar set <key> <value>",
      glyph: "󰆍", enabled: false, onActivate: function() {}
    })
    return out
  }
}
