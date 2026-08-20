import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.b7s.quill"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool shiftOn: false
  property bool ctrlOn: false
  property bool altOn: false
  property bool injectError: false
  property bool wantInjector: true

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function sendRaw(code, down) {
    if (!injector.running) return
    injector.write((down ? "d " : "u ") + code + "\n")
  }

  function keyCode(k) {
    if (k.c !== undefined) return k.c
    var map = { "back": 14, "enter": 28, "tab": 15, "space": 57 }
    return map[k.type]
  }

  function isModifier(k) {
    return k.type === "shift" || k.type === "ctrl" || k.type === "alt"
  }

  // Send a key down (with the held sticky modifiers) and keep it held — used for
  // both the initial press and each auto-repeat tick. The matching up is sent on
  // release via sendRelease().
  function sendHold(code) {
    if (root.ctrlOn) root.sendRaw(29, true)
    if (root.altOn) root.sendRaw(56, true)
    if (root.shiftOn) root.sendRaw(42, true)
    root.sendRaw(code, true)
  }

  function sendRelease(code) {
    root.sendRaw(code, false)
    if (root.shiftOn) root.sendRaw(42, false)
    if (root.altOn) root.sendRaw(56, false)
    if (root.ctrlOn) root.sendRaw(29, false)
  }

  // Press: modifiers toggle immediately; other keys go down and begin auto-repeat
  // (after a short delay, like a physical keyboard) so holding deletes/types/etc.
  function keyDown(k) {
    if (!k) return
    if (isModifier(k)) {
      if (k.type === "shift") root.shiftOn = !root.shiftOn
      else if (k.type === "ctrl") root.ctrlOn = !root.ctrlOn
      else if (k.type === "alt") root.altOn = !root.altOn
      return
    }
    if (!injector.running) { root.injectError = true; return }
    var code = keyCode(k)
    if (code === undefined) return
    root._repeatCode = code
    root.sendHold(code)
    repeatDelay.restart()
  }

  // Release: stop auto-repeat and lift the key (and any held modifiers).
  function keyReleased(k) {
    if (!k || isModifier(k)) return
    if (root._repeatCode === null) return
    repeatDelay.stop()
    repeatTimer.stop()
    root.sendRelease(root._repeatCode)
    root._repeatCode = null
  }

  // Native visual tokens (qs.Commons Color/Style), passed into the
  // (Style-free) KeyButton delegates as typed properties.
  readonly property color keySurface: Qt.alpha(Color.foreground, 0.07)
  readonly property color keySurfaceHover: Qt.alpha(Color.foreground, 0.13)
  readonly property color keySurfacePressed: Qt.alpha(Color.foreground, 0.20)
  readonly property color keySurfaceError: Qt.alpha(Color.urgent, 0.20)
  readonly property color keyBorder: Qt.alpha(Color.foreground, 0.18)
  readonly property color keyContent: Color.popups.text
  readonly property color keyContentDim: Qt.alpha(Color.popups.text, 0.6)

  readonly property int keyGap: Style.space(6)
  readonly property int keyBase: 40
  readonly property int keyH: 46
  readonly property int gripH: 22
  // Uniform, small padding used for all sides of the keyboard surface.
  readonly property int pad: 8

  function kbRowWidth(row) {
    var w = 0
    for (var i = 0; i < row.length; i++) w += root.keyBase * ((row[i].w) ? row[i].w : 1)
    w += (row.length - 1) * root.keyGap
    return w
  }
  readonly property int kbNaturalWidth: {
    var m = 0
    for (var r = 0; r < root.rows.length; r++) m = Math.max(m, root.kbRowWidth(root.rows[r]))
    return m + root.pad * 2
  }
  readonly property int kbNaturalHeight: root.gripH + root.keyGap
    + root.rows.length * root.keyH + (root.rows.length - 1) * root.keyGap
    + root.pad * 2

  // Active layout, auto-detected at startup from the system keyboard layout
  // (Hyprland kb_layout / $LANG). Falls back to "us".
  property string activeLayout: "us"

  readonly property var layouts: ({
    "us": [
      [
        { n:"1", s:"!", c:2,  type:"char" },
        { n:"2", s:"@", c:3,  type:"char" },
        { n:"3", s:"#", c:4,  type:"char" },
        { n:"4", s:"$", c:5,  type:"char" },
        { n:"5", s:"%", c:6,  type:"char" },
        { n:"6", s:"^", c:7,  type:"char" },
        { n:"7", s:"&", c:8,  type:"char" },
        { n:"8", s:"*", c:9,  type:"char" },
        { n:"9", s:"(", c:10, type:"char" },
        { n:"0", s:")", c:11, type:"char" },
        { n:"-", s:"_", c:12, type:"char" },
        { n:"=", s:"+", c:13, type:"char" },
        { n:"⌫", s:"⌫", c:14, type:"back", w:1.6 }
      ],
      [
        { n:"Tab", s:"Tab", c:15, type:"tab", w:1.4 },
        { n:"q", s:"Q", c:16, type:"char" },
        { n:"w", s:"W", c:17, type:"char" },
        { n:"e", s:"E", c:18, type:"char" },
        { n:"r", s:"R", c:19, type:"char" },
        { n:"t", s:"T", c:20, type:"char" },
        { n:"y", s:"Y", c:21, type:"char" },
        { n:"u", s:"U", c:22, type:"char" },
        { n:"i", s:"I", c:23, type:"char" },
        { n:"o", s:"O", c:24, type:"char" },
        { n:"p", s:"P", c:25, type:"char" },
        { n:"[", s:"{", c:26, type:"char" },
        { n:"]", s:"}", c:27, type:"char" },
        { n:"\\", s:"|", c:43, type:"char" }
      ],
      [
        { n:"Shift", s:"Shift", c:42, type:"shift", w:1.6 },
        { n:"a", s:"A", c:30, type:"char" },
        { n:"s", s:"S", c:31, type:"char" },
        { n:"d", s:"D", c:32, type:"char" },
        { n:"f", s:"F", c:33, type:"char" },
        { n:"g", s:"G", c:34, type:"char" },
        { n:"h", s:"H", c:35, type:"char" },
        { n:"j", s:"J", c:36, type:"char" },
        { n:"k", s:"K", c:37, type:"char" },
        { n:"l", s:"L", c:38, type:"char" },
        { n:";", s:":", c:39, type:"char" },
        { n:"'", s:'"', c:40, type:"char" },
        { n:"Enter", s:"Enter", c:28, type:"enter", w:1.8 }
      ],
      [
        { n:"Ctrl", s:"Ctrl", c:29, type:"ctrl", w:1.6 },
        { n:"z", s:"Z", c:44, type:"char" },
        { n:"x", s:"X", c:45, type:"char" },
        { n:"c", s:"C", c:46, type:"char" },
        { n:"v", s:"V", c:47, type:"char" },
        { n:"b", s:"B", c:48, type:"char" },
        { n:"n", s:"N", c:49, type:"char" },
        { n:"m", s:"M", c:50, type:"char" },
        { n:",", s:"<", c:51, type:"char" },
        { n:".", s:">", c:52, type:"char" },
        { n:"/", s:"?", c:53, type:"char" },
        { n:"Ctrl", s:"Ctrl", c:29, type:"ctrl", w:1.3 },
        { n:"Alt", s:"Alt", c:56, type:"alt", w:1.3 }
      ],
      [
        { n:"Space", s:"Space", c:57, type:"space", w:7 }
      ]
    ],

    // Portuguese (Brazil) ABNT2. Keycodes taken from the system xkb symbols
    // (/usr/share/X11/xkb/symbols/br); the two extra ABNT keys are the Ç key
    // (Linux 39) and the /? key (Linux 181 = KEY_International1), plus the
    // 102nd < > key (Linux 86).
    "pt-br": [
      [
        { n:"'", s:'"', c:41, type:"char" },
        { n:"1", s:"!", c:2,  type:"char" },
        { n:"2", s:"@", c:3,  type:"char" },
        { n:"3", s:"#", c:4,  type:"char" },
        { n:"4", s:"$", c:5,  type:"char" },
        { n:"5", s:"%", c:6,  type:"char" },
        { n:"6", s:"¨", c:7,  type:"char" },
        { n:"7", s:"&", c:8,  type:"char" },
        { n:"8", s:"*", c:9,  type:"char" },
        { n:"9", s:"(", c:10, type:"char" },
        { n:"0", s:")", c:11, type:"char" },
        { n:"-", s:"_", c:12, type:"char" },
        { n:"=", s:"+", c:13, type:"char" },
        { n:"⌫", s:"⌫", c:14, type:"back", w:1.6 }
      ],
      [
        { n:"Tab", s:"Tab", c:15, type:"tab", w:1.4 },
        { n:"q", s:"Q", c:16, type:"char" },
        { n:"w", s:"W", c:17, type:"char" },
        { n:"e", s:"E", c:18, type:"char" },
        { n:"r", s:"R", c:19, type:"char" },
        { n:"t", s:"T", c:20, type:"char" },
        { n:"y", s:"Y", c:21, type:"char" },
        { n:"u", s:"U", c:22, type:"char" },
        { n:"i", s:"I", c:23, type:"char" },
        { n:"o", s:"O", c:24, type:"char" },
        { n:"p", s:"P", c:25, type:"char" },
        { n:"[", s:"{", c:27, type:"char" },
        { n:"]", s:"}", c:43, type:"char" },
        { n:"´", s:"`", c:26, type:"char" }
      ],
      [
        { n:"Shift", s:"Shift", c:42, type:"shift", w:1.6 },
        { n:"a", s:"A", c:30, type:"char" },
        { n:"s", s:"S", c:31, type:"char" },
        { n:"d", s:"D", c:32, type:"char" },
        { n:"f", s:"F", c:33, type:"char" },
        { n:"g", s:"G", c:34, type:"char" },
        { n:"h", s:"H", c:35, type:"char" },
        { n:"j", s:"J", c:36, type:"char" },
        { n:"k", s:"K", c:37, type:"char" },
        { n:"l", s:"L", c:38, type:"char" },
        { n:"Ç", s:"ç", c:39, type:"char" },
        { n:"~", s:"^", c:40, type:"char" },
        { n:"Enter", s:"Enter", c:28, type:"enter", w:1.8 }
      ],
      [
        { n:"Ctrl", s:"Ctrl", c:29, type:"ctrl", w:1.6 },
        { n:"\\", s:"|", c:86, type:"char" },
        { n:"z", s:"Z", c:44, type:"char" },
        { n:"x", s:"X", c:45, type:"char" },
        { n:"c", s:"C", c:46, type:"char" },
        { n:"v", s:"V", c:47, type:"char" },
        { n:"b", s:"B", c:48, type:"char" },
        { n:"n", s:"N", c:49, type:"char" },
        { n:"m", s:"M", c:50, type:"char" },
        { n:",", s:"<", c:51, type:"char" },
        { n:".", s:">", c:52, type:"char" },
        { n:";", s:":", c:53, type:"char" },
        { n:"/", s:"?", c:181, type:"char" },
        { n:"Ctrl", s:"Ctrl", c:29, type:"ctrl", w:1.3 },
        { n:"Alt", s:"Alt", c:56, type:"alt", w:1.3 }
      ],
      [
        { n:"Space", s:"Space", c:57, type:"space", w:7 }
      ]
    ]
  })

  property var rows: layouts[activeLayout] || layouts["us"]

  // Key auto-repeat: hold a key to repeat it like a real keyboard.
  property var _repeatCode: null

  Timer {
    id: repeatDelay
    interval: 400
    repeat: false
    onTriggered: {
      if (root._repeatCode === null) return
      repeatTimer.interval = 45
      repeatTimer.restart()
    }
  }
  Timer {
    id: repeatTimer
    interval: 45
    repeat: true
    onTriggered: {
      if (root._repeatCode !== null) root.sendHold(root._repeatCode)
    }
  }

  Process {
    id: injector
    running: false
    command: ["quill-inject"]
    stdinEnabled: true
    onStarted: root.injectError = false
    onExited: {
      if (root.wantInjector) restartTimer.restart()
    }
  }

  // Detect the system keyboard layout at startup so the on-screen layout matches
  // the physical one (e.g. "br" -> pt-br ABNT2). Reads Hyprland's kb_layout,
  // falling back to $LANG, normalised to a known layout id.
  Process {
    id: layoutProbe
    running: false
    command: ["sh", "-c", "h=$(hyprctl -j getoption input.kb_layout 2>/dev/null); [ -z \"$h\" ] && h=\"$LANG\"; printf \"%s\" \"$h\""]
    stdout: StdioCollector { onDataChanged: layoutProbe._probeRaw = text }
    property string _probeRaw: ""
    onExited: function(code) {
      var raw = layoutProbe._probeRaw.trim()
      if (raw.charAt(0) === "{") {
        try { var j = JSON.parse(raw); if (j && j.str) raw = j.str } catch (e) {}
      }
      raw = raw.toLowerCase()
      if (raw.indexOf("br") >= 0 || raw.indexOf("pt") >= 0) root.activeLayout = "pt-br"
      else root.activeLayout = "us"
    }
  }

  Timer {
    id: restartTimer
    interval: 1500
    repeat: false
    onTriggered: injector.running = true
  }

  Component.onCompleted: {
    injector.running = true
    layoutProbe.running = true
  }

  QuillPanel {
    id: panel
    takeFocus: false
    padding: root.pad
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.kbNaturalWidth)
    contentHeight: panel.fittedContentHeight(root.kbNaturalHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: root.keyGap
        anchors.centerIn: parent

        // Header: the whole top bar (except the close button) is the drag handle;
        // keys themselves no longer drag the keyboard.
        Row {
          id: header
          width: parent.width
          height: root.gripH
          spacing: root.keyGap

          Item {
            id: grip
            width: parent.width - closeBtn.width - root.keyGap
            height: root.gripH

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "⠿"
              color: Qt.alpha(Color.popups.text, 0.55)
              font.family: Style.font.family
              font.pixelSize: 14
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.SizeAllCursor
              drag.target: panel.dragHandle
              drag.axis: Drag.XAndYAxis
              drag.smoothed: false
              onPressed: {
                panel.dragHandle.lastX = panel.dragHandle.x
                panel.dragHandle.lastY = panel.dragHandle.y
              }
            }
          }

          Rectangle {
            id: closeBtn
            width: root.gripH
            height: root.gripH
            radius: 4
            color: Qt.alpha(Color.foreground, 0.12)

            MouseArea {
              anchors.fill: parent
              onClicked: root.close()
            }
            Text {
              anchors.centerIn: parent
              text: "✕"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: 12
            }
          }
        }

          Repeater {
            model: root.rows
            delegate: RowLayout {
              width: parent.width
              spacing: root.keyGap
              Repeater {
                model: modelData
                delegate: QuillKey {
                  key: modelData
                  shift: root.shiftOn
                  active: (modelData.type === "shift" && root.shiftOn)
                    || (modelData.type === "ctrl" && root.ctrlOn)
                    || (modelData.type === "alt" && root.altOn)
                  error: root.injectError
                  surface: root.keySurface
                  surfaceHover: root.keySurfaceHover
                  surfacePressed: root.keySurfacePressed
                  surfaceError: root.keySurfaceError
                  borderColor: root.keyBorder
                  contentColor: root.keyContent
                  contentColorDim: root.keyContentDim
                  keyRadius: Style.space(8)
                  keyFont: Style.font.family
                  keyFontSize: Style.font.body
                  Layout.preferredWidth: root.keyBase * (key.type === "char" ? 1 : (key.w || 1))
                  Layout.preferredHeight: root.keyH
                  Layout.fillWidth: key.type !== "char"
                  Layout.fillHeight: false
                  onPressed: root.keyDown(modelData)
                  onReleased: root.keyReleased(modelData)
                }
              }
            }
          }

        Text {
          width: parent.width
          visible: root.injectError
          text: "quill-inject not running — build it and ensure /dev/uinput access"
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: 12
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
