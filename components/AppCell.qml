import QtQuick
import qs.Commons

// One pinned application. Left click launches / focuses / cycles, wheel
// cycles, middle click opens a new window, right click opens the app menu,
// a long hover shows previews. The cell never changes size or position
// because of what the app is doing.
HotbarCell {
  id: root

  required property var group
  readonly property var live: hotbar ? (hotbar.groupByKey(group ? group.key : "") || group) : group
  readonly property int count: live ? (live.count || 0) : 0
  readonly property bool running: count > 0
  readonly property bool focused: live ? live.focused === true : false
  readonly property bool isPopoverOwner: hotbar && hotbar.openPopover === "app" && hotbar.popoverAnchor === root
    && hotbar.popoverGroup && group && hotbar.popoverGroup.key === group.key

  tooltipText: group ? (count > 1 ? group.name + "  ·  " + count + " windows" : group.name) : ""
  accessibleName: group ? group.name : ""
  indicator: focused ? "focused" : (running ? "running" : "none")
  urgent: live ? live.urgent === true : false
  dimmed: !running
  active: isPopoverOwner


  AppIcon {
    anchors.fill: parent
    source: root.hotbar ? root.hotbar.iconSourceFor(root.live) : ""
    fallbackGlyph: "󰣆"
    fontFamily: root.hotbar ? root.hotbar.fontFamily : "monospace"
    tint: root.foreground
    mono: root.hotbar ? root.hotbar.monoIcons : false
    dpr: root.hotbar ? root.hotbar.devicePixelRatio : 1
  }

  onPressed: function(button) {
    if (!hotbar) return
    if (button === Qt.RightButton) {
      hotbar.openAppPopover(root.live, root)
    } else if (button === Qt.MiddleButton) {
      if (hotbar.middleClick === "new-window") hotbar.newWindow(root.live)
    } else {
      if (hotbar.opened) hotbar.close()
      hotbar.activateGroup(root.live)
    }
  }

  onWheelMoved: function(delta) {
    if (!hotbar || !hotbar.wheelCycle || !running) return
    wheelAccumulator += delta
    if (Math.abs(wheelAccumulator) < 60) return
    var direction = wheelAccumulator > 0 ? -1 : 1
    wheelAccumulator = 0
    hotbar.cycleGroup(root.live, direction)
  }
  property int wheelAccumulator: 0

  onHoverStarted: if (hotbar && count > 1) hotbar.requestPreview(root.live, root)
  onHoverEnded: if (hotbar) hotbar.releasePreview()
}
