import QtQuick
import qs.Commons

// One permanent Hotbar slot. Square-ish against the bar thickness, generous
// hit target, quiet hover fill, an indicator strip on the inner (workspace)
// side. Every cell registers itself as a bar click target so the host's
// keyboard panels can forward bar-strip clicks while a popover is open.
Item {
  id: root

  required property var hotbar          // the Hotbar root (theme, geometry, actions)
  property string tooltipText: ""
  property string accessibleName: ""
  property bool hovered: mouseArea.containsMouse
  property bool pressedState: mouseArea.pressed
  property bool showHoverFill: true
  // "none" | "running" | "focused"
  property string indicator: "none"
  property bool urgent: false
  property bool dimmed: false
  property bool active: false          // a popover for this cell is open

  signal pressed(int button)
  signal wheelMoved(int delta)
  signal hoverStarted()
  signal hoverEnded()

  readonly property var bar: hotbar ? hotbar.bar : null
  readonly property bool vertical: hotbar ? hotbar.vertical : false
  readonly property real cellExtent: hotbar ? hotbar.cellExtent : 27
  readonly property int barSize: hotbar ? hotbar.barSize : 26
  readonly property color foreground: hotbar ? hotbar.foreground : Color.foreground
  readonly property color accent: hotbar ? hotbar.accentColor : Color.accent
  readonly property color urgentColor: hotbar ? hotbar.urgentColor : Color.urgent
  readonly property bool animate: hotbar ? hotbar.animationsEnabled : true
  readonly property string barPosition: bar ? bar.position : "top"

  implicitWidth: vertical ? barSize : cellExtent
  implicitHeight: vertical ? cellExtent : barSize

  Accessible.role: Accessible.Button
  Accessible.name: accessibleName || tooltipText

  // The host bar's keyboard panels call triggerPress(button) on registered
  // click targets when the user clicks the bar strip while a panel is open.
  function triggerPress(button) {
    if (bar) bar.hideTooltip(root)
    root.pressed(button)
  }

  function hideOwnTooltip() {
    if (bar) bar.hideTooltip(root)
  }

  property var registeredBar: null
  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(root)
  }
  onBarChanged: syncClickRegistration()
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: {
    hideOwnTooltip()
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
  }
  onVisibleChanged: if (!visible) hideOwnTooltip()

  // Hover / pressed / active fill. Uses the host's control fill tokens so it
  // matches every other bar button in the active theme.
  Rectangle {
    id: fill
    anchors.fill: parent
    anchors.margins: Style.space(2)
    radius: Math.max(Style.space(3), Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(6)) : Style.space(3))
    color: root.pressedState
      ? Style.pressedFillFor(root.foreground, root.accent)
      : (root.active
        ? Style.selectedFillFor(root.foreground, root.accent)
        : (root.hovered && root.showHoverFill ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"))
    Behavior on color {
      enabled: root.animate
      ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
    }
  }

  default property alias content: contentHolder.data

  Item {
    id: contentHolder
    anchors.centerIn: parent
    width: root.hotbar ? root.hotbar.iconSize : 18
    height: width
    opacity: root.dimmed ? 0.6 : 1
    Behavior on opacity {
      enabled: root.animate
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
  }

  // Running/focused indicator: a short strip on the inner edge of the bar.
  // Running = thin and muted, focused = longer and accent-coloured, so the
  // two states differ in shape as well as colour.
  Rectangle {
    id: strip
    readonly property bool shown: root.indicator !== "none" && (root.hotbar ? root.hotbar.runningIndicator !== "none" : true)
    readonly property bool dot: root.hotbar ? root.hotbar.runningIndicator === "dot" : false
    readonly property bool focused: root.indicator === "focused"
    readonly property real thickness: dot ? Style.space(4) : (focused ? Style.space(2) : Math.max(1, Style.space(1.5)))
    readonly property real length: dot ? Style.space(4) : Math.round(root.cellExtent * (focused ? 0.62 : 0.34))
    readonly property real inset: Style.space(2)

    visible: shown
    radius: thickness
    color: focused ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
    width: root.vertical ? thickness : length
    height: root.vertical ? length : thickness

    anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
    anchors.verticalCenter: root.vertical ? parent.verticalCenter : undefined
    anchors.bottom: root.barPosition === "top" ? parent.bottom : undefined
    anchors.bottomMargin: inset
    anchors.top: root.barPosition === "bottom" ? parent.top : undefined
    anchors.topMargin: inset
    anchors.right: root.barPosition === "left" ? parent.right : undefined
    anchors.rightMargin: inset
    anchors.left: root.barPosition === "right" ? parent.left : undefined
    anchors.leftMargin: inset

    Behavior on width { enabled: root.animate && !root.vertical; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: root.animate && root.vertical; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on color { enabled: root.animate; ColorAnimation { duration: 140 } }
  }

  // Urgent marker: a small static dot in the theme's urgent colour at the
  // outer corner. No pulsing — attention is signalled once, quietly.
  Rectangle {
    visible: root.urgent
    width: Style.space(5)
    height: width
    radius: width / 2
    color: root.urgentColor
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Style.space(3)
    anchors.rightMargin: Style.space(3)
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onEntered: {
      if (root.bar && root.tooltipText !== "") root.bar.showTooltip(root, root.tooltipText)
      root.hoverStarted()
    }
    onExited: {
      if (root.bar) root.bar.hideTooltip(root)
      root.hoverEnded()
    }
    onClicked: function(mouse) {
      if (root.bar) root.bar.hideTooltip(root)
      root.pressed(mouse.button)
    }
    onWheel: function(wheel) {
      var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
      if (delta !== 0) root.wheelMoved(delta)
    }
  }
}
