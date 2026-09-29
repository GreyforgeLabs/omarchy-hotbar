import QtQuick
import qs.Commons

// Places: a destination launcher. Left click opens the popover, middle
// click goes straight to Home in the default file manager, right click
// opens Hotbar Settings.
//
// The cell is a hollow pill with a red outline — a *hot* bar. Two styles
// (`placesStyle`): "minimal" (default) is cell-sized with a short amber
// bar in the middle; "badge" is longer and spells HOTBAR in amber. In both
// a flame highlight sweeps along the outline (and through the letters) and
// flickers. The drawing is one fragment shader (FlamePill); the animation
// is two numbers nudged at 24 fps, only while the cell is visible and the
// `flame` and `animations` settings are on; brighter on hover and while a
// popover is open. On a vertical bar the pill turns with the bar.
HotbarCell {
  id: root

  tooltipText: "Hotbar · Places"
  accessibleName: "Hotbar Places"
  active: hotbar && (hotbar.openPopover === "places" || hotbar.openPopover === "settings")

  readonly property bool badge: hotbar ? hotbar.placesStyle === "badge" : false
  readonly property string badgeText: "HOTBAR"
  readonly property int iconPx: hotbar ? hotbar.iconSize : 18
  readonly property int fontPx: Math.max(8, Math.round((hotbar ? hotbar.barSize : 26) * 0.36))
  readonly property int padX: Math.round(fontPx * 0.8)
  readonly property int padY: Math.max(2, Math.round(fontPx * 0.32))
  readonly property int badgeLength: badge ? Math.ceil(metrics.advanceWidth + fontPx * 0.12 * badgeText.length) + padX * 2 : iconPx + 4
  readonly property int badgeThickness: badge ? metrics.height + padY * 2 : Math.max(8, Math.round(iconPx * 0.6))
  // Along the bar the badge takes what it needs (+ the usual cell margins);
  // minimal is an ordinary cell. Across the bar it is the bar's size.
  implicitWidth: vertical ? barSize : (badge ? badgeLength + Style.space(8) : cellExtent)
  implicitHeight: vertical ? (badge ? badgeLength + Style.space(8) : cellExtent) : barSize

  TextMetrics {
    id: metrics
    font.family: root.hotbar ? root.hotbar.fontFamily : Style.font.family
    font.pixelSize: root.fontPx
    font.bold: true
    text: root.badgeText
  }

  Item {
    id: iconRoot
    anchors.centerIn: parent
    // Room for the glow outside the outline.
    width: (root.vertical ? root.badgeThickness : root.badgeLength) + 6
    height: (root.vertical ? root.badgeLength : root.badgeThickness) + 6
    // Whole-pixel placement: a half-pixel centre would blur the strokes.
    anchors.horizontalCenterOffset: (parent.width - width) % 2 ? 0.5 : 0
    anchors.verticalCenterOffset: (parent.height - height) % 2 ? 0.5 : 0

    readonly property bool lit: root.hovered || root.active
    readonly property bool burning: root.visible && root.animate && (root.hotbar ? root.hotbar.flameEnabled : true)

    // 0..1 position of the highlight along the badge; 0..1 flame intensity.
    property real phase: 0
    property real heat: 0.7

    // 24 fps: every tick re-renders the whole bar window, so the rate is
    // the remaining cost of the shimmer. The sweep covers the pill in the
    // same 2.8 s it did at 30 fps.
    Timer {
      interval: 42
      repeat: true
      running: iconRoot.burning
      onTriggered: {
        iconRoot.phase = (iconRoot.phase + 0.015) % 1
        // Flicker: a bounded random walk drifting back toward a resting
        // glow, so the flame breathes instead of strobing.
        var rest = iconRoot.lit ? 0.95 : 0.75
        var h = iconRoot.heat + (Math.random() - 0.5) * 0.34 + (rest - iconRoot.heat) * 0.19
        iconRoot.heat = Math.max(0.35, Math.min(1, h))
      }
    }

    // The pill, its glow, the sweep and the letters are one fragment shader
    // (FlamePill.qml → shaders/flame.frag); the JavaScript above is all the
    // CPU work a frame costs.
    FlamePill {
      anchors.fill: parent
      vertical: root.vertical
      badge: root.badge
      lineWidth: root.badge ? Math.max(1.5, Math.round(root.fontPx / 6)) : Math.max(1, Math.round(root.iconPx / 12))
      text: root.badgeText
      fontFamily: metrics.font.family
      fontPx: root.fontPx
      letterSpacing: root.fontPx * 0.12
      phase: iconRoot.phase
      heat: iconRoot.heat
      lit: iconRoot.lit
      burning: iconRoot.burning
      flame: root.hotbar ? root.hotbar.brandAmber : "#fda52b"
    }
  }

  onPressed: function(button) {
    if (!hotbar) return
    if (button === Qt.MiddleButton) hotbar.openPlace(hotbar.home)
    else if (button === Qt.RightButton) hotbar.openSettingsPopover(root)
    else if (button === Qt.LeftButton) hotbar.openPlacesPopover(root)
  }
}
