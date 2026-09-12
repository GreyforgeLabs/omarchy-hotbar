import QtQuick
import qs.Commons

// The per-application menu: every window of the group (with thumbnails
// when the compositor provides them), then the group actions. Individual
// windows live here — never on the permanent bar.
HotbarPopover {
  id: root
  kind: "app"

  property var group: null
  readonly property int maxThumbnails: 8

  title: group ? String(group.name || "") : ""
  trailingTitle: group && group.count > 0 ? String(group.count) : ""
  emptyText: "Not running."
  showEmpty: false
  preferredWidth: Style.space(340)

  // Rows are rebuilt only when the group's window set, pin state or the
  // launchability changes — never on a mere focus change — so the
  // thumbnails inside them are not torn down and recreated while the
  // compositor is still delivering frames.
  readonly property string signature: {
    var g = root.group
    var rev = root.hotbar ? root.hotbar.revision : 0
    if (!g || !root.open) return ""
    var live = root.hotbar ? root.hotbar.groupByKey(g.key) : null
    var wins = live ? live.windows : []
    var addrs = wins.map(function(w) { return w.address }).sort().join(",")
    var pinned = root.hotbar ? root.hotbar.isPinned(g.key) : false
    var idx = root.hotbar ? root.hotbar.pins.indexOf(g.key) : -1
    var total = root.hotbar ? root.hotbar.pins.length : 0
    return g.key + "|" + addrs + "|" + pinned + "|" + idx + "/" + total + "|" + (root.hotbar ? root.hotbar.previewsEnabled : false)
  }
  // An empty signature means closed: drop the rows (and their thumbnails).
  onSignatureChanged: rows = signature ? buildRows() : []

  function buildRows() {
    var out = []
    var g = root.group
    if (!g || !root.hotbar) return out
    var live = root.hotbar.groupByKey(g.key)
    // MRU order as of the moment the rows are built; the signature ignores
    // focus changes, so the list does not shuffle under the pointer while
    // the popover is open.
    var wins = live ? live.windows.slice() : []
    var thumbs = root.hotbar.previewsEnabled && wins.length <= root.maxThumbnails
    for (var i = 0; i < wins.length; i++) out.push(windowRow(wins[i], thumbs))
    if (wins.length) out.push({ kind: "separator" })

    var canNew = root.hotbar.canLaunch(g)
    out.push({
      kind: "row", primary: wins.length ? "New Window" : "Launch", glyph: "󰐕", enabled: canNew,
      onActivate: function() { root.hotbar.newWindow(g); root.close() }
    })
    var pinned = root.hotbar.isPinned(g.key)
    out.push({
      kind: "row", primary: pinned ? "Unpin from Hotbar" : "Pin to Hotbar", glyph: pinned ? "󰤰" : "󰐃",
      onActivate: function() { root.hotbar.togglePin(g.key); root.close() }
    })
    if (pinned && root.hotbar.pins.length > 1) {
      var idx = root.hotbar.pins.indexOf(g.key)
      if (idx > 0) out.push({ kind: "row", primary: root.hotbar.vertical ? "Move Up" : "Move Left", glyph: root.hotbar.vertical ? "󰁝" : "󰁍", onActivate: function() { root.hotbar.movePin(g.key, -1) } })
      if (idx >= 0 && idx < root.hotbar.pins.length - 1) out.push({ kind: "row", primary: root.hotbar.vertical ? "Move Down" : "Move Right", glyph: root.hotbar.vertical ? "󰁅" : "󰁔", onActivate: function() { root.hotbar.movePin(g.key, 1) } })
    }
    if (wins.length) {
      out.push({
        kind: "row", primary: "Close Current Window", glyph: "󰅖",
        onActivate: function() { root.hotbar.closeCurrent(g); if (wins.length <= 1) root.close() }
      })
      out.push({
        kind: "row", primary: wins.length > 1 ? "Close All " + wins.length + " Windows" : "Close Window", glyph: "󰅙", danger: true,
        onActivate: function() { root.hotbar.closeAll(g); root.close() }
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
