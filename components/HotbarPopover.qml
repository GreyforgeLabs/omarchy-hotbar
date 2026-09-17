import QtQuick
import qs.Commons
import qs.Ui

// Shared popover chrome for Places, App, Running and Settings: a KeyboardPanel (the
// host's own click/keyboard panel surface) holding a title line and a flat
// list of rows. Rows are plain objects:
//   { kind: "header",    title }
//   { kind: "separator" }
//   { kind: "row",       primary, secondary?, trailing?, glyph?, iconSource?,
//                        enabled?, danger?, onActivate(button), onDelete()? }
//   { kind: "window",    toplevel, thumbnail?, onActivate(button), onDelete() }
//
// One cursor is shared by keyboard and mouse. Only "row"/"window" items are
// selectable. Enter/Space activate, x deletes (closes a window), Escape
// closes, Up/Down/j/k move, Home/End jump.
KeyboardPanel {
  id: root

  required property var hotbar
  // Which of Hotbar's popovers this is ("places" | "app" | "running" | "settings"). The
  // owner object below is what the bar's popout coordinator holds; its
  // close() only acts when this popover is still the one that is open, so
  // switching from one Hotbar popover to another cannot close the new one.
  required property string kind
  property string title: ""
  property string trailingTitle: ""
  // Eyebrow above the title: the product line, in brand cyan. Popovers that
  // stand for something else (an app menu) keep the eyebrow but change
  // the label so the surface still reads as Hotbar's.
  property string eyebrow: "HOTBAR"
  property string iconSource: ""     // app icon shown in the header instead of the mark
  property bool signature: true      // Greyforge Labs wordmark at the foot
  property string footerText: ""     // right-aligned hint next to the wordmark
  property var rows: []
  property int cursor: -1
  property bool cursorActive: false
  property int listMaxHeight: Style.space(560)
  property int preferredWidth: Style.space(300)
  property bool showEmpty: rows.length === 0
  property string emptyText: "Nothing here yet"

  signal activated(var row, int button)
  signal deleted(var row)

  bar: hotbar ? hotbar.bar : null
  owner: QtObject {
    function close() { if (root.hotbar && root.hotbar.openPopover === root.kind) root.hotbar.close() }
    function closeForPopoutSwitch() { close() }
  }
  contentWidth: fittedContentWidth(preferredWidth)
  contentHeight: fittedContentHeight(column.implicitHeight)
  focusTarget: keys

  readonly property color foreground: hotbar ? hotbar.popupForeground : Color.popups.text
  readonly property string fontFamily: hotbar ? hotbar.fontFamily : Style.font.family
  readonly property color brandCyan: hotbar ? hotbar.brandCyan : "#38c8e8"
  readonly property color brandAmber: hotbar ? hotbar.brandAmber : "#fda52b"
  readonly property color hairline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)

  function isSelectable(index) {
    var r = rows[index]
    return !!r && (r.kind === "row" || r.kind === "window") && r.enabled !== false
  }

  function firstSelectable() {
    for (var i = 0; i < rows.length; i++) if (isSelectable(i)) return i
    return -1
  }

  function lastSelectable() {
    for (var i = rows.length - 1; i >= 0; i--) if (isSelectable(i)) return i
    return -1
  }

  function moveCursor(step) {
    if (!rows.length) return
    cursorActive = true
    if (cursor < 0) { cursor = step > 0 ? firstSelectable() : lastSelectable(); ensureVisible(); return }
    var i = cursor
    for (var n = 0; n < rows.length; n++) {
      i = (i + step + rows.length) % rows.length
      if (isSelectable(i)) { cursor = i; ensureVisible(); return }
    }
  }

  function ensureVisible() {
    if (cursor >= 0) list.positionViewAtIndex(cursor, ListView.Contain)
  }

  function activateCursor(button) {
    if (cursor < 0 || !isSelectable(cursor)) return
    var r = rows[cursor]
    if (typeof r.onActivate === "function") r.onActivate(button === undefined ? 1 : button)
    root.activated(r, button === undefined ? 1 : button)
  }

  function deleteCursor() {
    if (cursor < 0 || !isSelectable(cursor)) return
    var r = rows[cursor]
    if (typeof r.onDelete === "function") r.onDelete()
    root.deleted(r)
  }

  function resetCursor() {
    cursorActive = false
    cursor = -1
    list.positionViewAtBeginning()
  }

  onOpenChanged: if (open) resetCursor()
  onRowsChanged: {
    if (cursor >= rows.length) cursor = lastSelectable()
    else if (cursor >= 0 && !isSelectable(cursor)) cursor = firstSelectable()
  }

  PanelKeyCatcher {
    id: keys
    anchors.fill: parent
    onMoveRequested: function(dx, dy) {
      if (dy !== 0) root.moveCursor(dy)
      else if (dx > 0) root.activateCursor(2)   // Right: secondary action (submenu)
      else if (dx < 0) root.close()
    }
    onActivateRequested: root.activateCursor(1)
    onCloseRequested: root.close()
    onDeleteRequested: root.deleteCursor()
    onTextKey: function(t) {
      if (t === "g") { root.cursor = root.firstSelectable(); root.cursorActive = true; root.ensureVisible() }
      else if (t === "G") { root.cursor = root.lastSelectable(); root.cursorActive = true; root.ensureVisible() }
    }
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Home) { root.cursor = root.firstSelectable(); root.cursorActive = true; root.ensureVisible(); event.accepted = true }
      else if (event.key === Qt.Key_End) { root.cursor = root.lastSelectable(); root.cursorActive = true; root.ensureVisible(); event.accepted = true }
      else if (event.key === Qt.Key_Delete) { root.deleteCursor(); event.accepted = true }
    }

    Column {
      id: column
      width: parent.width
      spacing: Style.space(6)

      Item {
        id: header
        width: parent.width
        height: root.title !== "" ? Math.max(headerMark.height, headerLabels.implicitHeight) + Style.space(8) : 0
        visible: root.title !== ""

        // App menus lead with the app's own icon; the other popovers have
        // no leading mark — the eyebrow already says whose surface it is.
        Item {
          id: headerMark
          anchors.left: parent.left
          anchors.top: parent.top
          width: root.iconSource !== "" ? Style.space(30) : 0
          height: root.iconSource !== "" ? Style.space(30) : headerLabels.implicitHeight
          AppIcon {
            visible: root.iconSource !== ""
            anchors.centerIn: parent
            width: Style.space(22)
            height: width
            source: root.iconSource
            fallbackGlyph: "󰣆"
            fontFamily: root.fontFamily
            tint: root.foreground
            mono: false
            dpr: root.hotbar ? root.hotbar.devicePixelRatio : 1
          }
        }

        Column {
          id: headerLabels
          anchors.left: headerMark.right
          anchors.leftMargin: root.iconSource !== "" ? Style.space(10) : Style.space(2)
          anchors.right: parent.right
          anchors.verticalCenter: headerMark.verticalCenter
          spacing: Style.space(1)

          Text {
            width: parent.width
            text: root.eyebrow + "  ·  GREYFORGE LABS"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.brandCyan
            opacity: 0.9
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.4
            renderType: Text.NativeRendering
          }

          Item {
            width: parent.width
            height: titleText.implicitHeight
            Text {
              id: titleText
              anchors.left: parent.left
              text: root.title
              textFormat: Text.PlainText
              elide: Text.ElideRight
              width: parent.width - (trailingLabel.visible ? trailingLabel.width + Style.space(8) : 0)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              renderType: Text.NativeRendering
            }
            Rectangle {
              id: trailingLabel
              visible: root.trailingTitle !== ""
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: trailingText.implicitWidth + Style.space(10)
              height: trailingText.implicitHeight + Style.space(4)
              radius: height / 2
              color: Qt.rgba(root.brandAmber.r, root.brandAmber.g, root.brandAmber.b, 0.16)
              border.width: 1
              border.color: Qt.rgba(root.brandAmber.r, root.brandAmber.g, root.brandAmber.b, 0.5)
              Text {
                id: trailingText
                anchors.centerIn: parent
                text: root.trailingTitle
                textFormat: Text.PlainText
                color: root.brandAmber
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                renderType: Text.NativeRendering
              }
            }
          }
        }

        // steel rule with the amber core under the header
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: root.brandAmber }
            GradientStop { position: 0.18; color: root.brandCyan }
            GradientStop { position: 0.7; color: root.hairline }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }
      }

      Column {
        visible: root.showEmpty
        width: parent.width
        spacing: Style.space(6)
        topPadding: Style.space(10)
        bottomPadding: Style.space(6)
        Text {
          width: parent.width
          text: root.emptyText
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.62)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
        }
      }

      ListView {
        id: list
        width: parent.width
        height: Math.min(root.listMaxHeight, contentHeight)
        implicitHeight: height
        clip: true
        model: root.rows
        spacing: Style.space(1)
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        currentIndex: root.cursor
        highlightFollowsCurrentItem: false
        // Rows are recreated on every rebuild; keep it cheap.
        cacheBuffer: Style.space(200)

        delegate: Loader {
          id: rowLoader
          required property var modelData
          required property int index
          width: list.width
          sourceComponent: {
            var k = modelData ? modelData.kind : ""
            if (k === "header") return headerComponent
            if (k === "separator") return separatorComponent
            if (k === "window") return windowComponent
            return rowComponent
          }

          Component {
            id: rowComponent
            PopoverRow {
              hotbar: root.hotbar
              row: rowLoader.modelData
              hasCursor: root.cursorActive && root.cursor === rowLoader.index
              onHovered: { root.cursorActive = true; root.cursor = rowLoader.index }
              onClicked: function(button) {
                root.cursor = rowLoader.index
                root.activateCursor(button === Qt.RightButton ? 2 : (button === Qt.MiddleButton ? 3 : 1))
              }
            }
          }

          Component {
            id: windowComponent
            WindowRow {
              hotbar: root.hotbar
              row: rowLoader.modelData
              hasCursor: root.cursorActive && root.cursor === rowLoader.index
              onHovered: { root.cursorActive = true; root.cursor = rowLoader.index }
              onClicked: function(button) {
                root.cursor = rowLoader.index
                root.activateCursor(button === Qt.RightButton ? 2 : (button === Qt.MiddleButton ? 3 : 1))
              }
            }
          }

          Component {
            id: headerComponent
            Item {
              width: list.width
              height: Style.space(24)
              PanelSectionHeader {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.controlPaddingX
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(3)
                text: String(rowLoader.modelData.title || "").toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
            }
          }

          Component {
            id: separatorComponent
            Item {
              width: list.width
              height: Style.space(9)
              PanelSeparator {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                foreground: root.foreground
              }
            }
          }
        }
      }

      // Signature: a quiet one-liner. The header already carries the mark
      // and the eyebrow, so the foot only whispers the studio name.
      Item {
        visible: root.signature
        width: parent.width
        height: visible ? footerMark.implicitHeight + Style.space(8) : 0
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07) }
        Text {
          id: footerMark
          anchors.left: parent.left
          anchors.leftMargin: Style.space(4)
          anchors.bottom: parent.bottom
          text: "greyforge labs"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.3
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 1)
          font.letterSpacing: 1.2
          renderType: Text.NativeRendering
        }
        Text {
          visible: root.footerText !== ""
          anchors.right: parent.right
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: footerMark.verticalCenter
          text: root.footerText
          textFormat: Text.PlainText
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 1)
          renderType: Text.NativeRendering
        }
      }
    }
  }
}
