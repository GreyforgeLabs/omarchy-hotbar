import QtQuick
import qs.Commons

// One row in a Hotbar popover: leading glyph or icon, primary text,
// optional secondary line, trailing text (count / chevron). The whole row
// is the hit target. Headers and separators are rendered by the popover
// itself; this is only for actionable rows.
Item {
  id: root

  required property var hotbar
  property var row: ({})
  property bool hasCursor: false
  property bool enabled: row && row.enabled !== false
  property string primary: row ? String(row.primary || "") : ""
  property string secondary: row ? String(row.secondary || "") : ""
  property string trailing: row ? String(row.trailing || "") : ""
  property string glyph: row ? String(row.glyph || "") : ""
  property string iconSource: row ? String(row.iconSource || "") : ""
  property bool danger: row && row.danger === true
  property bool tall: secondary !== ""

  signal hovered()
  signal clicked(int button)

  readonly property color foreground: hotbar ? hotbar.popupForeground : Color.popups.text
  readonly property color accent: hotbar ? hotbar.accentColor : Color.accent
  readonly property string fontFamily: hotbar ? hotbar.fontFamily : Style.font.family
  readonly property bool animate: hotbar ? hotbar.animationsEnabled : true

  width: parent ? parent.width : implicitWidth
  implicitHeight: tall ? Style.space(44) : Style.spacing.popupRowHeight
  height: implicitHeight
  opacity: enabled ? 1 : 0.45

  Accessible.role: Accessible.Button
  Accessible.name: secondary ? primary + ", " + secondary : primary

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

    Item {
      id: lead
      width: Style.space(18)
      height: parent.height
      visible: root.glyph !== "" || root.iconSource !== ""

      Text {
        anchors.centerIn: parent
        visible: root.iconSource === ""
        text: root.glyph
        textFormat: Text.PlainText
        color: root.danger ? (root.hotbar ? root.hotbar.urgentColor : Color.urgent) : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        renderType: Text.NativeRendering
      }

      AppIcon {
        anchors.centerIn: parent
        width: Style.space(16)
        height: width
        visible: root.iconSource !== ""
        source: root.iconSource
        fallbackGlyph: root.glyph || "󰣆"
        fontFamily: root.fontFamily
        tint: root.foreground
        mono: root.hotbar ? root.hotbar.monoIcons : false
        dpr: root.hotbar ? root.hotbar.devicePixelRatio : 1
      }
    }

    Column {
      width: parent.width - (lead.visible ? lead.width + parent.spacing : 0) - (trail.visible ? trail.width + parent.spacing : 0)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        width: parent.width
        text: root.primary
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        color: root.danger ? (root.hotbar ? root.hotbar.urgentColor : Color.urgent) : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.hasCursor && root.row && root.row.emphasize === true
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        visible: root.secondary !== ""
        text: root.secondary
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
      id: trail
      visible: root.trailing !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.trailing
      textFormat: Text.PlainText
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.62)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hovered()
    onPositionChanged: root.hovered()
    onClicked: function(mouse) { root.clicked(mouse.button) }
  }
}
