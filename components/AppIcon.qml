import QtQuick
import QtQuick.Effects

// One application icon, decoded at physical pixels, with an optional
// monochrome treatment that tints the icon with the bar foreground so a
// colourful icon set can still read as part of a monochrome Omarchy bar.
Item {
  id: root

  property string source: ""
  property string fallbackGlyph: ""
  property string fontFamily: "monospace"
  property color tint: "white"
  property bool mono: false
  property real dpr: 1

  readonly property bool hasImage: source !== "" && image.status === Image.Ready

  Image {
    id: image
    anchors.fill: parent
    source: root.source
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    cache: true
    smooth: true
    // Decoded at the physical size it is drawn at, so no mipmaps are needed.
    sourceSize.width: Math.round(root.width * Math.max(1, root.dpr))
    sourceSize.height: Math.round(root.height * Math.max(1, root.dpr))
    visible: root.hasImage && !root.mono
  }

  // The tint pass is a shader; only instantiate it when it is actually used.
  Loader {
    anchors.fill: image
    active: root.mono && root.hasImage
    sourceComponent: MultiEffect {
      source: image
      colorization: 1.0
      colorizationColor: root.tint
      saturation: -1.0
    }
  }

  Text {
    anchors.centerIn: parent
    visible: !root.hasImage
    text: root.fallbackGlyph
    textFormat: Text.PlainText
    color: root.tint
    font.family: root.fontFamily
    font.pixelSize: Math.round(root.height * 0.8)
    renderType: Text.NativeRendering
  }
}
