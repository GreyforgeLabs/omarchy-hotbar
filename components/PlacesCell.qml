import QtQuick
import qs.Commons
import "../brand"

// Places: a destination launcher. Left click opens the popover, middle
// click goes straight to Home in the default file manager, right click
// opens Hotbar Settings.
HotbarCell {
  id: root

  tooltipText: "Hotbar · Places"
  accessibleName: "Hotbar Places"
  active: hotbar && (hotbar.openPopover === "places" || hotbar.openPopover === "settings")


  // The Greyforge mark holding three pin slots: Hotbar's own cell is the
  // brand plate, so the bar reads as a Greyforge Labs surface at a glance.
  // The middle pin carries the amber core.
  GreyforgeMark {
    id: iconRoot
    anchors.centerIn: parent
    readonly property int iconPx: root.hotbar ? root.hotbar.iconSize : 18
    readonly property bool isVertical: root.hotbar ? root.hotbar.vertical : false
    readonly property int pinPx: Math.max(2, Math.round(iconPx / 6))
    readonly property int pinGap: Math.max(1, Math.round(iconPx / 10))
    size: iconPx + 4
    steel: root.foreground
    plate: root.hotbar && root.hotbar.bar ? root.hotbar.bar.background : Color.bar.background
    seams: root.active || root.hovered
    showCore: false
    scale: root.pressedState ? 0.92 : 1
    Behavior on scale { enabled: root.animate; NumberAnimation { duration: 90 } }

    Grid {
      anchors.centerIn: parent
      columns: iconRoot.isVertical ? 1 : 3
      rows: iconRoot.isVertical ? 3 : 1
      spacing: iconRoot.pinGap
      Repeater {
        model: 3
        Rectangle {
          required property int index
          width: iconRoot.pinPx
          height: width
          radius: index === 1 ? width / 2 : 1
          color: index === 1 ? (root.hotbar ? root.hotbar.brandAmber : "#fda52b") : root.foreground
          opacity: index === 1 ? 1 : 0.85
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
