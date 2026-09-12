import QtQuick
import qs.Commons

// The Running drawer: pinned apps that overflowed the width budget first,
// then every unpinned running application. Each row is one application
// group; clicking follows the same MRU/focus rules as a pinned cell, and
// right-click / Right arrow opens that group's menu.
HotbarPopover {
  id: root
  kind: "running"

  title: "Running"
  emptyText: "Nothing else is running. Apps you open that are not pinned show up here."
  preferredWidth: Style.space(300)

  readonly property var overflow: hotbar ? hotbar.overflowPins : []
  readonly property var running: hotbar ? hotbar.runningGroups : []

  showEmpty: overflow.length === 0 && running.length === 0

  rows: {
    var out = []
    var rev = root.hotbar ? root.hotbar.revision : 0
    var over = root.overflow || []
    var run = root.running || []
    if (over.length) {
      out.push({ kind: "header", title: "Pinned" })
      for (var i = 0; i < over.length; i++) out.push(groupRow(over[i]))
    }
    if (run.length) {
      if (over.length) out.push({ kind: "separator" })
      out.push({ kind: "header", title: "Running" })
      for (var j = 0; j < run.length; j++) out.push(groupRow(run[j]))
    }
    return out
  }

  function groupRow(group) {
    var count = group.count || 0
    return {
      kind: "row",
      primary: group.name,
      secondary: count === 1 && group.windows.length ? String(group.windows[0].toplevel ? group.windows[0].toplevel.title || "" : "") : "",
      trailing: count > 1 ? count + "  ›" : (count === 1 ? "›" : ""),
      iconSource: root.hotbar ? root.hotbar.iconSourceFor(group) : "",
      glyph: "󰣆",
      emphasize: group.focused === true,
      group: group,
      onActivate: function(button) {
        if (!root.hotbar) return
        if (button === 2) { root.hotbar.openAppPopover(group, root.hotbar.runningAnchor); return }
        if (button === 3) { root.hotbar.togglePin(group.key); return }
        root.hotbar.activateGroup(group)
        root.close()
      }
    }
  }
}
