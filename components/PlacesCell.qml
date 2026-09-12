import QtQuick
import qs.Commons

// Places: a destination launcher. Left click opens the popover, middle
// click goes straight to Home in the default file manager, right click
// opens Hotbar Settings.
HotbarCell {
  id: root

  tooltipText: "Hotbar · Places"
  accessibleName: "Hotbar Places"
  active: hotbar && (hotbar.openPopover === "places" || hotbar.openPopover === "settings")


  // Miniature hotbar: a horizontal (or vertical) bar with a red border
  // holding three pin slots, so the cell reads as Hotbar itself rather
  // than a generic folder.
  Item {
    id: iconRoot
    anchors.centerIn: parent
    width: root.hotbar ? root.hotbar.iconSize : 18
    height: width
    readonly property bool isVertical: root.hotbar ? root.hotbar.vertical : false
    readonly property color pinColor: root.foreground
    readonly property color frameColor: root.hotbar ? root.hotbar.urgentColor : "#e5484d"
    readonly property color accentPin: root.hotbar ? root.hotbar.accentColor : pinColor
    readonly property int pinPx: Math.max(2, Math.round((root.hotbar ? root.hotbar.iconSize : 18) / 6))
    readonly property int pinGap: Math.max(2, Math.round((root.hotbar ? root.hotbar.iconSize : 18) / 9))

    Rectangle {
      anchors.centerIn: parent
      width: iconRoot.isVertical ? Math.max(6, Math.round(iconRoot.width * 0.55)) : iconRoot.width
      height: iconRoot.isVertical ? iconRoot.height : Math.max(6, Math.round(iconRoot.height * 0.6))
      radius: 3
      color: "transparent"
      border.color: iconRoot.frameColor
      border.width: Math.max(1, Math.round((root.hotbar ? root.hotbar.iconSize : 18) / 12))

      Row {
        visible: !iconRoot.isVertical
        anchors.centerIn: parent
        spacing: iconRoot.pinGap
        Repeater {
          model: 3
          Rectangle {
            required property int index
            width: iconRoot.pinPx
            height: width
            radius: 1
            color: index === 1 ? iconRoot.accentPin : iconRoot.pinColor
            opacity: index === 1 ? 1 : 0.85
          }
        }
      }

      Column {
        visible: iconRoot.isVertical
        anchors.centerIn: parent
        spacing: iconRoot.pinGap
        Repeater {
          model: 3
          Rectangle {
            required property int index
            width: iconRoot.pinPx
            height: width
            radius: 1
            color: index === 1 ? iconRoot.accentPin : iconRoot.pinColor
            opacity: index === 1 ? 1 : 0.85
          }
        }
      }
    }
  }

  onPressed: function(button) {
    if (!hotbar) return
    if (button === Qt.MiddleButton) hotbar.openPlace(hotbar.home)
    else if (button === Qt.RightButton) hotbar.openSettingsPopover(root)
    else if (button === Qt.LeftButton) hotbar.openPlacesPopover(root)
  }
}
