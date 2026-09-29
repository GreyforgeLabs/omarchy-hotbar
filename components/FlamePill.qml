import QtQuick

// The hot bar itself: a hollow pill with an ember outline and a flame
// highlight sweeping along it, drawn by one fragment shader
// (shaders/flame.frag). The badge style adds the HOTBAR letters, rendered
// once by a hidden Text item and coloured by the same sweep in the shader.
//
// This replaced a 30 fps Canvas: that repainted gradients and letters in
// JavaScript on every tick and cost the shell about 5 % of a core around
// the clock. Here the per-frame work is two uniform updates; the GPU does
// the rest.
Item {
  id: root

  // Geometry: the pill fills the item minus a 3 px glow margin.
  property bool vertical: false
  property bool badge: false
  property real lineWidth: 1.5

  // Letters (badge style only).
  property string text: "HOTBAR"
  property string fontFamily: "sans-serif"
  property int fontPx: 10
  property real letterSpacing: 1

  // Animation state, driven from outside.
  property real phase: 0          // 0..1 along the pill
  property real heat: 0.7         // 0..1 flame intensity
  property bool lit: false        // hover / popover open
  property bool burning: true     // animating; false freezes a dim sweep

  property color ember: "#e5322d"
  property color flame: "#fda52b"
  property color hot: "#fff3d0"

  // The intensity the Canvas used: heat while burning, a fixed dim glow
  // otherwise, brighter when lit.
  readonly property real lickScale: (burning ? heat : 0.3) * (lit ? 1 : 0.8)
  readonly property real glowAlpha: (burning ? heat : 0.5) * (lit ? 0.5 : 0.28)

  // Letters, white on transparent, rotated with a vertical bar. Never shown
  // directly: the shader samples them.
  Item {
    id: lettersSource
    width: root.width
    height: root.height
    visible: false
    Text {
      anchors.centerIn: parent
      rotation: root.vertical ? -90 : 0
      text: root.badge ? root.text : ""
      color: "white"
      font.family: root.fontFamily
      font.pixelSize: root.fontPx
      font.bold: true
      font.letterSpacing: root.letterSpacing
      renderType: Text.NativeRendering
    }
  }

  ShaderEffectSource {
    id: letters
    sourceItem: lettersSource
    hideSource: true
    live: true
    smooth: true
  }

  ShaderEffect {
    anchors.fill: parent
    fragmentShader: Qt.resolvedUrl("shaders/flame.frag.qsb")

    property vector2d size: Qt.vector2d(root.width, root.height)
    property real lineWidth: root.lineWidth
    property real phase: root.phase
    property real lick: root.lickScale
    property real glow: root.glowAlpha
    property real vertical: root.vertical ? 1 : 0
    property real badge: root.badge ? 1 : 0
    property color ember: root.ember
    property color flame: root.flame
    property color hot: root.hot
    property var letters: letters
  }
}
