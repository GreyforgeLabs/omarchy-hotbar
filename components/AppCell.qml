import QtQuick
import qs.Commons

// One pinned application. Left click launches / focuses / cycles, wheel
// cycles, middle click opens a new window, right click opens the app menu,
// a long hover shows previews. The cell never changes size or position
// because of what the app is doing.
//
// The cell is keyed by identity, not by a group object: the group is
// looked up live so the cell survives every model rebuild.
HotbarCell {
  id: root

  required property string pinKey
  readonly property var live: hotbar ? hotbar.groupByKey(pinKey) : null
  readonly property string name: live ? String(live.name || "") : ""
  readonly property int count: live ? (live.count || 0) : 0
  readonly property bool running: count > 0
  readonly property bool focused: live ? live.focused === true : false
  readonly property bool isPopoverOwner: !!hotbar && hotbar.openPopover === "app" && hotbar.popoverAnchor === root
    && !!hotbar.popoverGroup && hotbar.popoverGroup.key === pinKey

  tooltipText: count > 1 ? name + "  ·  " + count + " windows" : name
  accessibleName: name
  indicator: focused ? "focused" : (running ? "running" : "none")
  urgent: live ? live.urgent === true : false
  dimmed: !running
  active: isPopoverOwner

  AppIcon {
    anchors.fill: parent
    source: root.hotbar && root.live ? root.hotbar.iconSourceFor(root.live) : ""
    fallbackGlyph: "󰣆"
    fontFamily: root.hotbar ? root.hotbar.fontFamily : "monospace"
    tint: root.foreground
    mono: root.hotbar ? root.hotbar.monoIcons : false
    dpr: root.hotbar ? root.hotbar.devicePixelRatio : 1
  }

  onPressed: function(button) {
    if (!hotbar || !live) return
    if (button === Qt.RightButton) {
      hotbar.openAppPopover(live, root)
    } else if (button === Qt.MiddleButton) {
      if (hotbar.middleClick === "new-window") hotbar.newWindow(live)
    } else {
      if (hotbar.opened) hotbar.close()
      hotbar.activateGroup(live)
    }
  }

  property int wheelAccumulator: 0
  onWheelMoved: function(delta) {
    if (!hotbar || !live || !hotbar.wheelCycle || !running) return
    wheelAccumulator += delta
    if (Math.abs(wheelAccumulator) < 60) return
    var direction = wheelAccumulator > 0 ? -1 : 1
    wheelAccumulator = 0
    hotbar.cycleGroup(live, direction)
  }

  onHoverStarted: if (hotbar && live && count > 1) hotbar.requestPreview(live, root)
  onHoverEnded: if (hotbar) hotbar.releasePreview()
}
