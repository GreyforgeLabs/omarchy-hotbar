import QtQuick
import qs.Commons

// The Running drawer cell: always one slot, whatever is behind it. Shows a
// quiet running indicator when the drawer holds anything, and the urgent
// dot when something in it wants attention.
HotbarCell {
  id: root

  readonly property int itemCount: hotbar ? (hotbar.overflowPins.length + hotbar.runningGroups.length) : 0
  readonly property bool anyUrgent: {
    if (!hotbar) return false
    var lists = [hotbar.overflowPins, hotbar.runningGroups]
    for (var l = 0; l < lists.length; l++) for (var i = 0; i < lists[l].length; i++) if (lists[l][i].urgent) return true
    return false
  }
  readonly property bool anyFocused: {
    if (!hotbar) return false
    var lists = [hotbar.overflowPins, hotbar.runningGroups]
    for (var l = 0; l < lists.length; l++) for (var i = 0; i < lists[l].length; i++) if (lists[l][i].focused) return true
    return false
  }

  tooltipText: itemCount > 0 ? "Running  ·  " + itemCount + (itemCount === 1 ? " app" : " apps") : "Running"
  accessibleName: "Running applications"
  indicator: anyFocused ? "focused" : (itemCount > 0 ? "running" : "none")
  urgent: anyUrgent
  active: hotbar && (hotbar.openPopover === "running" || hotbar.openPopover === "settings")


  Text {
    anchors.centerIn: parent
    text: "󰇘"
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.hotbar ? root.hotbar.fontFamily : Style.font.family
    font.pixelSize: Math.round((root.hotbar ? root.hotbar.iconSize : 18) * 0.95)
    renderType: Text.NativeRendering
  }

  onPressed: function(button) {
    if (!hotbar) return
    if (button === Qt.RightButton) hotbar.openSettingsPopover(root)
    else if (button === Qt.LeftButton) hotbar.openRunningPopover(root)
  }

  onWheelMoved: function(delta) {
    // Wheel over the drawer walks the drawer's apps in MRU order, so an
    // unpinned window is still one flick away.
    if (!hotbar || !hotbar.wheelCycle) return
    wheelAccumulator += delta
    if (Math.abs(wheelAccumulator) < 60) return
    var direction = wheelAccumulator > 0 ? -1 : 1
    wheelAccumulator = 0
    hotbar.cycleDrawer(direction)
  }
  property int wheelAccumulator: 0
}
