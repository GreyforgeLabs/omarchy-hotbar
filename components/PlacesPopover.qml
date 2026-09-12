import QtQuick
import qs.Commons
import "../PlacesModel.js" as Places

// Places: XDG folders, favourites, mounted drives, Trash, and the default
// file manager. A destination launcher, not a file browser.
HotbarPopover {
  id: root
  kind: "places"

  title: "Places"
  emptyText: "No places found."
  preferredWidth: Style.space(280)

  readonly property var sections: hotbar ? hotbar.placesSections : []

  rows: {
    var out = []
    var secs = root.sections || []
    for (var s = 0; s < secs.length; s++) {
      var sec = secs[s]
      if (!sec || !sec.rows || !sec.rows.length) continue
      if (s > 0 && (sec.id === "system" || !sec.title)) out.push({ kind: "separator" })
      else if (sec.title) out.push({ kind: "header", title: sec.title })
      for (var r = 0; r < sec.rows.length; r++) {
        var place = sec.rows[r]
        out.push(makeRow(place))
      }
    }
    return out
  }

  function makeRow(place) {
    return {
      kind: "row",
      primary: place.name,
      secondary: place.id === "home" || place.id === "filemanager" || place.id === "trash" ? "" : shortPath(place.path),
      glyph: place.glyph || "󰉋",
      place: place,
      onActivate: function(button) {
        if (root.hotbar) root.hotbar.openPlace(place.path)
        root.close()
      }
    }
  }

  function shortPath(path) {
    var p = String(path || "")
    var home = root.hotbar ? root.hotbar.home : ""
    if (home && p.indexOf(home + "/") === 0) return "~" + p.slice(home.length)
    return p
  }
}
