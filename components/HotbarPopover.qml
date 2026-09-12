import QtQuick
import qs.Commons
import qs.Ui

// Shared popover chrome for Places, App and Running: a KeyboardPanel (the
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
  // Which of Hotbar's popovers this is ("places" | "app" | "running"). The
  // owner object below is what the bar's popout coordinator holds; its
  // close() only acts when this popover is still the one that is open, so
  // switching from one Hotbar popover to another cannot close the new one.
  required property string kind
  property string title: ""
  property string trailingTitle: ""
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
        height: root.title !== "" ? Style.space(22) : 0
        visible: root.title !== ""

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.title
          textFormat: Text.PlainText
          elide: Text.ElideRight
          width: parent.width - (trailingLabel.visible ? trailingLabel.width + Style.space(8) : 0)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          renderType: Text.NativeRendering
        }

        Text {
          id: trailingLabel
          visible: root.trailingTitle !== ""
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.trailingTitle
          textFormat: Text.PlainText
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.62)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }
      }

      Text {
        visible: root.showEmpty
        width: parent.width
        text: root.emptyText
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.62)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
        topPadding: Style.space(4)
        bottomPadding: Style.space(4)
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
    }
  }
}
