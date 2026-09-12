import QtQuick
import qs.Commons

// Places: a destination launcher. Left click opens the popover, middle
// click goes straight to Home in the default file manager.
HotbarCell {
  id: root

  tooltipText: "Places"
  accessibleName: "Places"
  active: hotbar && hotbar.openPopover === "places"


  Text {
    anchors.centerIn: parent
    text: "󰉋"
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.hotbar ? root.hotbar.fontFamily : Style.font.family
    font.pixelSize: Math.round((root.hotbar ? root.hotbar.iconSize : 18) * 0.92)
    renderType: Text.NativeRendering
  }

  onPressed: function(button) {
    if (!hotbar) return
    if (button === Qt.MiddleButton) hotbar.openPlace(hotbar.home)
    else if (button === Qt.LeftButton) hotbar.openPlacesPopover(root)
  }
}
