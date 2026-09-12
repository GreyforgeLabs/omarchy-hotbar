import QtQuick
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Hover preview for a multi-window app: a strip of live thumbnails that
// appears after the configured delay and goes away when the pointer leaves
// both the cell and the strip. It deliberately does not take part in the
// bar's popout coordination — hovering must never close another widget's
// open panel — so it talks to a small proxy instead of the real bar.
PopupCard {
  id: root

  required property var hotbar
  property var group: null
  readonly property int maxPreviews: 6
  readonly property var windows: group && hotbar ? (hotbar.groupByKey(group.key) || group).windows : []
  readonly property int shown: Math.min(maxPreviews, windows.length)
  readonly property int hidden: Math.max(0, windows.length - shown)
  readonly property real thumbW: Style.space(168)
  readonly property real thumbH: Style.space(96)
  readonly property color foreground: hotbar ? hotbar.popupForeground : Color.popups.text
  readonly property color accent: hotbar ? hotbar.accentColor : Color.accent
  readonly property string fontFamily: hotbar ? hotbar.fontFamily : Style.font.family

  triggerMode: "hover"
  bar: proxy
  owner: null
  anchorItem: hotbar ? hotbar.previewAnchor : null
  padding: Style.space(8)
  contentWidth: shown > 0 ? Math.min(availableCardWidth, shown * thumbW + (shown - 1) * Style.space(8) + padding * 2 + Border.left(borderSpec) + Border.right(borderSpec)) : padding * 2
  contentHeight: cappedContentHeight(thumbH + Style.space(20) + (hidden > 0 ? Style.space(16) : 0) + padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec))

  property QtObject proxy: QtObject {
    id: proxy
    readonly property string position: root.hotbar && root.hotbar.bar ? root.hotbar.bar.position : "top"
    property var activePopout: null
    function requestPopout(owner) {}
    function releasePopout(owner) {}
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(2)

    Row {
      spacing: Style.space(8)

      Repeater {
        model: root.shown

        Item {
          id: cell
          required property int index
          readonly property var win: root.windows[index]
          readonly property var toplevel: win ? win.toplevel : null
          readonly property bool isActive: !!toplevel && root.hotbar && root.hotbar.activeAddress === toplevel.address
          width: root.thumbW
          height: root.thumbH + Style.space(20)

          Rectangle {
            id: frame
            width: parent.width
            height: root.thumbH
            radius: Style.space(4)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, cellHover.hovered ? 0.12 : 0.06)
            border.width: 1
            border.color: cell.isActive ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, cellHover.hovered ? 0.4 : 0.18)
            clip: true

            ScreencopyView {
              id: view
              anchors.centerIn: parent
              captureSource: cell.toplevel && cell.toplevel.wayland ? cell.toplevel.wayland : null
              live: root.open
              paintCursor: false
              visible: hasContent && sourceSize.width > 0 && sourceSize.height > 0
              readonly property real fit: (sourceSize.width > 0 && sourceSize.height > 0)
                ? Math.min((frame.width - 4) / sourceSize.width, (frame.height - 4) / sourceSize.height) : 1
              width: Math.round(sourceSize.width * fit)
              height: Math.round(sourceSize.height * fit)
              constraintSize: Qt.size(frame.width * 2, frame.height * 2)
            }

            Text {
              anchors.centerIn: parent
              visible: !view.visible
              text: "󰖯"
              textFormat: Text.PlainText
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              renderType: Text.NativeRendering
            }
          }

          Text {
            anchors.top: frame.bottom
            anchors.topMargin: Style.space(4)
            width: parent.width
            text: cell.toplevel ? String(cell.toplevel.title || "") : ""
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            maximumLineCount: 1
            horizontalAlignment: Text.AlignHCenter
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: cell.isActive
            renderType: Text.NativeRendering
          }

          HoverHandler { id: cellHover }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
              if (!root.hotbar || !cell.toplevel) return
              if (mouse.button === Qt.MiddleButton) root.hotbar.closeWindow(cell.toplevel)
              else { root.hotbar.focusWindow(cell.toplevel); root.hotbar.hidePreview() }
            }
          }
        }
      }
    }

    Text {
      visible: root.hidden > 0
      width: parent.width
      text: "+" + root.hidden + " more — right-click for the full list"
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.62)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }
  }
}
