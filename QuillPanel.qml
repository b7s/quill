import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Layer-shell popup used as the Quill virtual keyboard surface.
//
// Forked from shell/Ui/KeyboardPanel.qml with three changes for standalone use:
//   1. `anchorItem` / `bar` are OPTIONAL (null when summoned as a bare
//      `panel` plugin, i.e. without a bar widget), instead of `required`.
//   2. `takeFocus` defaults to false so the surface never grabs keyboard
//      focus — Quill injects keys via uinput and must let the focused app
//      keep receiving them. (The upstream panel primes Exclusive focus for
//      Escape-to-close; Quill closes via the ✕ button and outside-click.)
//   3. `dragOffset` is added to `cardOrigin` so the keyboard can be dragged
//      anywhere on screen.
//
// API subset of Common.PopupCard: anchorItem, owner, bar, open, padding,
// margin, contentWidth/Height, default contentItem.

PanelWindow {
  id: root

  property var anchorItem: null
  property var bar: null
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  property bool centerOnBar: false
  property bool open: false
  property int gap: Style.gapsOut
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false
  property bool takeFocus: false
  property bool focusPrimed: false

  // User drag, in screen-space pixels, added to the computed card origin.
  property point dragOffset: Qt.point(0, 0)

  // Item that should take keyboard focus once the panel maps. Kept for API
  // compatibility with the upstream panel; Quill sets takeFocus:false so this
  // is never actually focused.
  property Item focusTarget: null

  default property alias panelContent: contentHolder.children

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPos: bar ? bar.position : "top"

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  function beginFocusPrime() {
    if (open && backingWindowVisible) focusPrimeTimer.restart()
  }

  // --- screen + lifetime ---------------------------------------------------

  // --- screen + position persistence --------------------------------------
  // The keyboard remembers the last screen and drag position (saved to disk) so
  // it reopens exactly where it was instead of jumping to a default that can end
  // up off-screen / clipped. When no saved position exists, it falls back to the
  // focused monitor (auto-detected via hyprctl).

  // Focused (auto-detected) screen — used as the fallback.
  property string _activeScreenName: ""
  property var _activeScreen: null

  // Persisted position.
  readonly property string _posPath: "~/.local/state/omarchy/quill.pos"
  property string _posScreenName: ""
  property bool _hasSavedPos: false
  property var _savedScreen: null
  property bool _userMoved: false
  property var _currentScreen: null

  function resolveScreen() {
    root._activeScreen = root._nameToScreen(root._activeScreenName)
  }
  function resolveSavedScreen() {
    root._savedScreen = root._nameToScreen(root._posScreenName)
    if (root._posScreenName && !root._savedScreen) root._hasSavedPos = false
  }
  function _nameToScreen(name) {
    if (!name) return null
    for (var i = 0; i < Quickshell.screens.length; i++) {
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
    }
    return null
  }

  function savePos() {
    if (!root._posScreenName) return
    posWrite.running = true
  }

  function _markMoved() {
    root._userMoved = true
    root._hasSavedPos = true
    if (root.screen) {
      root._posScreenName = root.screen.name
      root._savedScreen = root.screen
      root._currentScreen = root.screen
    }
    posSaveTimer.restart()
  }

  // Which screen the keyboard should open on: saved one if valid, else focused.
  function targetScreen() {
    if (root._hasSavedPos && root._savedScreen) return root._savedScreen
    return root._activeScreen || (Quickshell.screens.length ? Quickshell.screens[0] : null)
  }

  screen: anchorWindow ? anchorWindow.screen
    : (root._currentScreen || root.targetScreen())

  on_ActiveScreenNameChanged: root.resolveScreen()
  on_PosScreenNameChanged: root.resolveSavedScreen()
  Component.onCompleted: { posRead.running = true; screenProbe.running = true }

  // Load saved position.
  Process {
    id: posRead
    running: false
    command: ["sh", "-c", "cat ~/.local/state/omarchy/quill.pos 2>/dev/null || true"]
    stdout: StdioCollector { onDataChanged: posRead._raw = text }
    property string _raw: ""
    onExited: function(code) {
      var p = (posRead._raw || "").trim().split("|")
      if (p.length === 3 && p[0]) {
        root._posScreenName = p[0]
        root.dragOffset = Qt.point(Number(p[1]) || 0, Number(p[2]) || 0)
        root._hasSavedPos = true
      }
    }
  }

  // Persist position (debounced writes handled by posSaveTimer).
  Process {
    id: posWrite
    running: false
    command: ["sh", "-c", "mkdir -p ~/.local/state/omarchy && printf '%s' '" + root._posScreenName + "|" + Math.round(root.dragOffset.x) + "|" + Math.round(root.dragOffset.y) + "' > ~/.local/state/omarchy/quill.pos"]
  }
  Timer {
    id: posSaveTimer
    interval: 300
    onTriggered: root.savePos()
  }

  // Detect which monitor to open on: prefer the one under the mouse cursor (most
  // reliable — opening the keyboard can otherwise steal focus to the bar's screen),
  // then fall back to the focused monitor, then screens[0].
  Process {
    id: screenProbe
    running: false
    command: ["sh", "-c", "echo MON; hyprctl -j monitors 2>/dev/null || echo '[]'; echo POS; hyprctl -j cursorpos 2>/dev/null || echo '{}'"]
    stdout: StdioCollector { onDataChanged: screenProbe._raw = text }
    property string _raw: ""
    onExited: function(code) {
      try {
        var raw = screenProbe._raw
        var mi = raw.indexOf("POS")
        var monStr = raw.substring(0, mi >= 0 ? mi : raw.length).replace(/MON/g, "").trim()
        var posStr = mi >= 0 ? raw.substring(mi + 3).trim() : "{}"
        var monitors = JSON.parse(monStr), pos = JSON.parse(posStr)
        var found = null
        for (var i = 0; i < monitors.length; i++) {
          var m = monitors[i]
          if (pos.x >= m.x && pos.x < m.x + m.width && pos.y >= m.y && pos.y < m.y + m.height) found = m
        }
        if (!found) for (var j = 0; j < monitors.length; j++) if (monitors[j].focused) found = monitors[j]
        if (found) root._activeScreenName = found.name
      } catch (e) {}
    }
  }

  visible: open || card.opacity > 0 || popoutSwitching
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "quill-keyboard"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: root.takeFocus && root.open
    ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
    : WlrKeyboardFocus.None

  onBackingWindowVisibleChanged: beginFocusPrime()

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  readonly property real _barStripSize: {
    if (!bar) return 0
    var actual = (root.barPos === "top" || root.barPos === "bottom") ? root.barH : root.barW
    return Math.max(bar.barSize, actual) + root.gap
  }
  mask: Region {
    width: root.screenW
    height: root.screenH
  }

  TransformWatcher {
    id: anchorWatcher
    a: anchorWindow ? anchorWindow.contentItem : null
    b: anchorItem
  }

  readonly property point anchorScreenPos: {
    anchorWatcher.transform
    if (!anchorItem || !anchorWindow) return Qt.point(0, 0)
    return anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
  }
  readonly property real anchorW: anchorItem ? anchorItem.width : 0
  readonly property real anchorH: anchorItem ? anchorItem.height : 0
  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((barPos === "left" || barPos === "right") ? barW + gap + margin : margin * 2))
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((barPos === "top" || barPos === "bottom") ? barH + gap + margin : margin * 2))
    : 0
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    return Math.round(Math.min(desired, maxHeight))
  }

  readonly property real barW: anchorWindow ? anchorWindow.width : screenW
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property point cardOrigin: {
    if (!anchorItem || !bar) return Qt.point(margin, margin)
    var x = 0, y = 0
    if (centerOnBar && (barPos === "top" || barPos === "bottom")) {
      x = screenW / 2 - contentWidth / 2
      y = barPos === "bottom" ? screenH - barH - contentHeight - gap : barH + gap
    } else if (centerOnBar) {
      x = barPos === "left" ? barW + gap : screenW - barW - contentWidth - gap
      y = screenH / 2 - contentHeight / 2
    } else if (barPos === "bottom") {
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = screenH - barH - contentHeight - gap
    } else if (barPos === "left") {
      x = barW + gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else if (barPos === "right") {
      x = screenW - barW - contentWidth - gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else { // "top" (default)
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = barH + gap
    }
    x = Math.max(margin, Math.min(x, screenW - contentWidth - margin))
    y = Math.max(margin, Math.min(y, screenH - contentHeight - margin))
    return Qt.point(Math.round(x) + root.dragOffset.x, Math.round(y) + root.dragOffset.y)
  }

  // --- popout coordination (same-bar single-popout model) -----------------

  onOpenChanged: {
    if (open) {
      focusPrimed = false
      screenProbe.running = true
      // Position after the focused-monitor probe resolves so we use the correct
      // screen and never apply a stale offset (that previously pushed the
      // keyboard off-screen / clipped it).
      Qt.callLater(function() {
        var s = root.targetScreen()
        root._currentScreen = s
        if (root._hasSavedPos && root._savedScreen) {
          root._posScreenName = root._savedScreen.name
        } else {
          // No saved position: sit at the computed card origin (centered on the
          // chosen screen). dragOffset is a relative adjustment to that origin, so
          // leave it at (0,0) rather than writing absolute screen coords.
          root._posScreenName = s ? s.name : ""
          root.dragOffset = Qt.point(0, 0)
        }
        root.savePos()
      })
      beginFocusPrime()
      if (focusTarget) Qt.callLater(function() {
        if (root.open && root.focusTarget) root.focusTarget.forceActiveFocus()
      })
    } else {
      root.savePos()
      focusPrimeTimer.stop()
      focusPrimed = false
    }
    if (!bar) return
    if (open) {
      popoutSwitchClosing = false
      popoutSwitching = bar.activePopout && bar.activePopout !== coordinatorKey
      bar.requestPopout(coordinatorKey)
      if (popoutSwitching) popoutSwitchTimer.restart()
    } else {
      popoutSwitchClosing = !!(owner && owner.popoutSwitchClosing)
      popoutSwitching = false
      if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
      if (popoutSwitchClosing) closeSwitchTimer.restart()
    }
  }

  Timer {
    id: focusPrimeTimer
    interval: 75
    onTriggered: if (root.open) root.focusPrimed = true
  }

  Timer {
    id: popoutSwitchTimer
    interval: 150
    onTriggered: root.popoutSwitching = false
  }

  Timer {
    id: closeSwitchTimer
    interval: 1
    onTriggered: root.popoutSwitchClosing = false
  }

  // --- outside-click dismissal --------------------------------------------

  MouseArea {
    id: dismissArea
    anchors.fill: parent
    enabled: root.open
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    property bool hoveringBar: false
    cursorShape: hoveringBar ? Qt.PointingHandCursor : Qt.ArrowCursor

    function inBarRegion(px, py) {
      if (root.barPos === "bottom") return py >= root.screenH - root._barStripSize
      if (root.barPos === "left") return px <= root._barStripSize
      if (root.barPos === "right") return px >= root.screenW - root._barStripSize
      return py <= root._barStripSize
    }

    function barPoint(px, py) {
      if (root.barPos === "bottom") return Qt.point(px, py - (root.screenH - root.barH))
      if (root.barPos === "right") return Qt.point(px - (root.screenW - root.barW), py)
      return Qt.point(px, py)
    }

    function pressTargetAt(px, py) {
      if (!root.anchorWindow || !root.anchorWindow.contentItem || !root.bar || !root.bar.clickTargets) return null
      var p = barPoint(px, py)
      var targets = root.bar.clickTargets
      for (var i = targets.length - 1; i >= 0; i--) {
        var target = targets[i]
        if (!target || !target.triggerPress || target.visible === false || target.opacity === 0 || !target.mapToItem) continue
        if (root.bar.targetBelongsToWindow && !root.bar.targetBelongsToWindow(target, root.anchorWindow)) continue
        var pos = root.anchorWindow.itemPosition(target)
        if (p.x >= pos.x && p.x <= pos.x + target.width && p.y >= pos.y && p.y <= pos.y + target.height) return target
      }
      return null
    }

    function forwardBarClick(px, py, button) {
      if (button !== Qt.LeftButton && button !== Qt.RightButton && button !== Qt.MiddleButton) return false
      var target = pressTargetAt(px, py)
      if (!target) return false
      target.triggerPress(button)
      return true
    }

    onPositionChanged: function(mouse) { hoveringBar = inBarRegion(mouse.x, mouse.y) }
    onExited: hoveringBar = false
    onClicked: function(mouse) {
      if (root.takeFocus && root.focusPrimed && inBarRegion(mouse.x, mouse.y) && forwardBarClick(mouse.x, mouse.y, mouse.button)) return
      root.close()
    }
  }

  Variants {
    model: root.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        visible: root.open && !!root.screen && modelData.name !== root.screen.name
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "quill-keyboard-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: root.close()
        }
      }
    }
  }

  // --- drag proxy ----------------------------------------------------------
  // Lives at the panel-window (screen) level, NOT inside the card, so it never
  // moves when `dragOffset` changes — that keeps the drag math free of feedback
  // loops. The grab handle in Panel.qml drives `drag.target` here; we translate
  // the screen-space deltas into `dragOffset`.
  Item {
    id: dragProxy
    property real lastX: 0
    property real lastY: 0
    onXChanged: {
      root.dragOffset = Qt.point(root.dragOffset.x + (x - lastX), root.dragOffset.y)
      lastX = x
      root._markMoved()
    }
    onYChanged: {
      root.dragOffset = Qt.point(root.dragOffset.x, root.dragOffset.y + (y - lastY))
      lastY = y
      root._markMoved()
    }
  }
  property alias dragHandle: dragProxy

  // --- card ----------------------------------------------------------------

  BorderSurface {
    id: card
    x: root.cardOrigin.x
    y: root.cardOrigin.y
    width: root.contentWidth
    height: root.contentHeight
    color: Color.popups.background
    borderSpec: root.borderSpec
    padding: root.padding
    radius: Style.cornerRadius
    opacity: root.open || root.popoutSwitching ? 1.0 : 0

    Behavior on opacity {
      enabled: !root.popoutSwitching && !root.popoutSwitchClosing
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      opacity: root.popoutSwitching ? (root.open ? 1.0 : 0) : 1.0

      Behavior on opacity {
        enabled: root.popoutSwitching
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }
  }
}
