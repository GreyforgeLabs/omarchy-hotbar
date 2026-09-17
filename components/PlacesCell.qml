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
// flickers: one tiny Canvas repaint at 30 fps, only while the cell is
// visible and the `flame` and `animations` settings are on; brighter on
// hover and while a popover is open. On a vertical bar the pill turns
// with the bar.
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

    readonly property color ember: "#e5322d"
    readonly property color flame: root.hotbar ? root.hotbar.brandAmber : "#fda52b"
    readonly property color hot: "#fff3d0"
    readonly property bool lit: root.hovered || root.active
    readonly property bool burning: root.visible && root.animate && (root.hotbar ? root.hotbar.flameEnabled : true)

    // 0..1 position of the highlight along the badge; 0..1 flame intensity.
    property real phase: 0
    property real heat: 0.7

    function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function mix(a, b, t) {
      t = Math.max(0, Math.min(1, t))
      return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }
    // How hot the sweep is at 0..1 along the badge (wrapping at the ends).
    function lick(t) {
      var d = Math.abs(t - iconRoot.phase)
      d = Math.min(d, 1 - d)
      var k = Math.max(0, 1 - d / 0.22)
      return k * k * (iconRoot.burning ? iconRoot.heat : 0.3) * (iconRoot.lit ? 1 : 0.8)
    }
    // Outline: ember, warming to amber then near-white under the lick.
    function outlineColor(t) {
      var k = lick(t)
      return k < 0.5 ? mix(ember, flame, k * 2) : mix(flame, hot, (k - 0.5) * 1.6)
    }
    // Letters: amber, going orange-white under the lick.
    function textColor(t) {
      return mix(flame, hot, lick(t) * 0.9)
    }

    onPhaseChanged: frame.requestPaint()
    onHeatChanged: frame.requestPaint()
    onLitChanged: frame.requestPaint()
    onBurningChanged: frame.requestPaint()
    onWidthChanged: frame.requestPaint()
    onHeightChanged: frame.requestPaint()
    Connections { target: root; function onVerticalChanged() { frame.requestPaint() } function onBadgeChanged() { frame.requestPaint() } }
    Connections { target: metrics; function onFontChanged() { frame.requestPaint() } }

    Timer {
      interval: 33
      repeat: true
      running: iconRoot.burning
      onTriggered: {
        iconRoot.phase = (iconRoot.phase + 0.012) % 1
        // Flicker: a bounded random walk drifting back toward a resting
        // glow, so the flame breathes instead of strobing.
        var rest = iconRoot.lit ? 0.95 : 0.75
        var h = iconRoot.heat + (Math.random() - 0.5) * 0.3 + (rest - iconRoot.heat) * 0.15
        iconRoot.heat = Math.max(0.35, Math.min(1, h))
      }
    }

    Canvas {
      id: frame
      anchors.fill: parent
      antialiasing: true
      renderStrategy: Canvas.Cooperative
      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        var vertical = root.vertical
        var lw = root.badge ? Math.max(1.5, Math.round(root.fontPx / 6)) : Math.max(1, Math.round(root.iconPx / 12))
        var w = width - 6, h = height - 6
        var x = 3 + lw / 2, y = 3 + lw / 2
        w -= lw; h -= lw
        var r = Math.min(w, h) / 2   // pill ends

        function outline() {
          ctx.beginPath()
          ctx.moveTo(x + r, y)
          ctx.lineTo(x + w - r, y); ctx.arcTo(x + w, y, x + w, y + r, r)
          ctx.lineTo(x + w, y + h - r); ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
          ctx.lineTo(x + r, y + h); ctx.arcTo(x, y + h, x, y + h - r, r)
          ctx.lineTo(x, y + r); ctx.arcTo(x, y, x + r, y, r)
          ctx.closePath()
        }
        function sweep(colorAt) {
          var g = vertical ? ctx.createLinearGradient(0, y, 0, y + h) : ctx.createLinearGradient(x, 0, x + w, 0)
          var steps = 16
          for (var i = 0; i <= steps; i++) g.addColorStop(i / steps, colorAt(i / steps))
          return g
        }

        // Ember glow behind the outline; the flicker shows here too.
        var glow = (iconRoot.burning ? iconRoot.heat : 0.5) * (iconRoot.lit ? 0.5 : 0.28)
        ctx.lineWidth = lw * 3
        ctx.strokeStyle = iconRoot.rgba(iconRoot.ember, glow)
        outline(); ctx.stroke()

        // The outline with the flame sweep.
        ctx.lineWidth = lw
        ctx.strokeStyle = sweep(iconRoot.outlineColor)
        outline(); ctx.stroke()

        if (!root.badge) {
          // Minimal: a short amber bar in the middle of the pill, sharing
          // the sweep.
          var bl = Math.round((vertical ? h : w) * 0.42), bt = Math.max(2, Math.round((vertical ? w : h) * 0.24))
          ctx.fillStyle = sweep(iconRoot.textColor)
          if (vertical) ctx.fillRect(Math.round(x + w / 2 - bt / 2), Math.round(y + h / 2 - bl / 2), bt, bl)
          else ctx.fillRect(Math.round(x + w / 2 - bl / 2), Math.round(y + h / 2 - bt / 2), bl, bt)
          return
        }

        // HOTBAR, letter-spaced, with the same sweep through the letters.
        ctx.save()
        ctx.translate(x + w / 2, y + h / 2)
        if (vertical) ctx.rotate(-Math.PI / 2)
        ctx.font = "bold " + root.fontPx + "px '" + metrics.font.family + "'"
        ctx.textBaseline = "middle"
        ctx.textAlign = "center"
        ctx.fillStyle = sweep(iconRoot.textColor)
        var text = root.badgeText
        var spacing = root.fontPx * 0.12
        var total = ctx.measureText(text).width + spacing * (text.length - 1)
        var cx = -total / 2
        for (var c = 0; c < text.length; c++) {
          var cw = ctx.measureText(text[c]).width
          ctx.fillText(text[c], cx + cw / 2, 0.5)
          cx += cw + spacing
        }
        ctx.restore()
      }
    }
  }

  onPressed: function(button) {
    if (!hotbar) return
    if (button === Qt.MiddleButton) hotbar.openPlace(hotbar.home)
    else if (button === Qt.RightButton) hotbar.openSettingsPopover(root)
    else if (button === Qt.LeftButton) hotbar.openPlacesPopover(root)
  }
}
