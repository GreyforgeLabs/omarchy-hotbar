import QtQuick
import Quickshell.Wayland
import qs.Commons

// A window entry inside the App popover: a small thumbnail (when the
// compositor can provide one), the live title, and where the window lives.
// Titles are bound straight to the toplevel so they update while the
// popover is open without rebuilding the row model.
Item {
  id: root

  required property var hotbar
  property var row: ({})
  property bool hasCursor: false
  readonly property var toplevel: row ? row.toplevel : null
  readonly property bool showThumb: row && row.thumbnail === true && !!toplevel && !!toplevel.wayland
  readonly property color foreground: hotbar ? hotbar.popupForeground : Color.popups.text
  readonly property color accent: hotbar ? hotbar.accentColor : Color.accent
  readonly property string fontFamily: hotbar ? hotbar.fontFamily : Style.font.family
  readonly property bool animate: hotbar ? hotbar.animationsEnabled : true
  readonly property bool isActive: !!toplevel && hotbar && hotbar.activeAddress === toplevel.address

  signal hovered()
  signal clicked(int button)

  width: parent ? parent.width : implicitWidth
  height: showThumb ? Style.space(58) : Style.space(44)

  Accessible.role: Accessible.Button
  Accessible.name: toplevel ? String(toplevel.title || "") : ""

  Rectangle {
    anchors.fill: parent
    radius: Math.max(Style.space(4), Math.min(Style.cornerRadius, Style.space(8)))
    color: root.hasCursor ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
    Behavior on color { enabled: root.animate; ColorAnimation { duration: 100 } }
  }

  Row {
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.rightMargin: Style.spacing.controlPaddingX
    spacing: Style.spacing.controlGap

    Rectangle {
      id: thumbFrame
      visible: root.showThumb
      width: Style.space(80)
      height: Style.space(46)
      anchors.verticalCenter: parent.verticalCenter
      radius: Style.space(3)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
      border.width: 1
      border.color: root.isActive ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
      clip: true

      ScreencopyView {
        id: thumb
        anchors.centerIn: parent
        captureSource: root.showThumb ? root.toplevel.wayland : null
        // One frame per row: the popover is a menu, not a monitor.
        live: false
        paintCursor: false
        visible: hasContent && sourceSize.width > 0 && sourceSize.height > 0
        readonly property real fit: (sourceSize.width > 0 && sourceSize.height > 0)
          ? Math.min((thumbFrame.width - 2) / sourceSize.width, (thumbFrame.height - 2) / sourceSize.height) : 1
        width: Math.round(sourceSize.width * fit)
        height: Math.round(sourceSize.height * fit)
        constraintSize: Qt.size(thumbFrame.width * 2, thumbFrame.height * 2)
      }

      Text {
        anchors.centerIn: parent
        visible: !thumb.visible
        text: "󰖯"
        textFormat: Text.PlainText
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        renderType: Text.NativeRendering
      }
    }

    Column {
      width: parent.width - (thumbFrame.visible ? thumbFrame.width + parent.spacing : 0) - (activeMark.visible ? activeMark.width + parent.spacing : 0)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: root.toplevel ? String(root.toplevel.title || root.row.fallbackTitle || "Untitled") : ""
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        maximumLineCount: 1
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.isActive
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        text: root.hotbar && root.toplevel ? root.hotbar.locationLabel(root.toplevel) : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.62)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }

    Text {
      id: activeMark
      visible: root.isActive
      anchors.verticalCenter: parent.verticalCenter
      text: "󰄬"
      textFormat: Text.PlainText
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
      renderType: Text.NativeRendering
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hovered()
    onPositionChanged: root.hovered()
    onClicked: function(mouse) { root.clicked(mouse.button) }
  }
}
