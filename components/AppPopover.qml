import QtQuick
import qs.Commons

// The per-application menu: every window of the group (with thumbnails
// when the compositor provides them), then the group actions. Individual
// windows live here — never on the permanent bar.
HotbarPopover {
  id: root
  kind: "app"

  property var group: null
  readonly property int maxThumbnails: 12

  title: group ? String(group.name || "") : ""
  trailingTitle: group && group.count > 0 ? String(group.count) : ""
  emptyText: "Not running."
  showEmpty: false
  preferredWidth: Style.space(340)

  rows: {
    var out = []
    var g = root.group
    var rev = root.hotbar ? root.hotbar.revision : 0
    if (!g) return out
    var live = root.hotbar ? root.hotbar.groupByKey(g.key) : null
    var wins = live ? live.windows : []
    var thumbs = root.hotbar && root.hotbar.previewsEnabled && wins.length <= root.maxThumbnails
    for (var i = 0; i < wins.length; i++) {
      out.push(windowRow(wins[i], thumbs))
    }
    if (wins.length) out.push({ kind: "separator" })

    var canNew = root.hotbar ? root.hotbar.canLaunch(g) : false
    out.push({
      kind: "row", primary: wins.length ? "New Window" : "Launch", glyph: "󰐕", enabled: canNew,
      onActivate: function() { if (root.hotbar) root.hotbar.newWindow(g); root.close() }
    })
    var pinned = root.hotbar ? root.hotbar.isPinned(g.key) : false
    out.push({
      kind: "row", primary: pinned ? "Unpin from Hotbar" : "Pin to Hotbar", glyph: pinned ? "󰤰" : "󰐃",
      onActivate: function() { if (root.hotbar) root.hotbar.togglePin(g.key); root.close() }
    })
    if (pinned && root.hotbar && root.hotbar.pins.length > 1) {
      var idx = root.hotbar.pins.indexOf(g.key)
      if (idx > 0) out.push({ kind: "row", primary: "Move Left", glyph: "󰁍", onActivate: function() { root.hotbar.movePin(g.key, -1) } })
      if (idx >= 0 && idx < root.hotbar.pins.length - 1) out.push({ kind: "row", primary: "Move Right", glyph: "󰁔", onActivate: function() { root.hotbar.movePin(g.key, 1) } })
    }
    if (wins.length) {
      out.push({
        kind: "row", primary: "Close Current Window", glyph: "󰅖",
        onActivate: function() { if (root.hotbar) root.hotbar.closeCurrent(g); if (wins.length <= 1) root.close() }
      })
      out.push({
        kind: "row", primary: wins.length > 1 ? "Close All " + wins.length + " Windows" : "Close Window", glyph: "󰅙", danger: true,
        onActivate: function() { if (root.hotbar) root.hotbar.closeAll(g); root.close() }
      })
    }
    return out
  }

  function windowRow(win, thumbnail) {
    return {
      kind: "window",
      toplevel: win.toplevel,
      thumbnail: thumbnail,
      fallbackTitle: root.group ? root.group.name : "",
      onActivate: function(button) {
        if (button === 3) { if (root.hotbar) root.hotbar.closeWindow(win.toplevel); return }
        if (root.hotbar) root.hotbar.focusWindow(win.toplevel)
        root.close()
      },
      onDelete: function() { if (root.hotbar) root.hotbar.closeWindow(win.toplevel) }
    }
  }
}
