import QtQuick
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

  function pressKey(key) {
    if (!key) return
    if (key.type === "shift") { root.shiftOn = !root.shiftOn; return }
    if (key.type === "ctrl") { root.ctrlOn = !root.ctrlOn; return }
    if (key.type === "alt") { root.altOn = !root.altOn; return }
    if (!injector.running) { root.injectError = true; return }
    var code = key.c
    if (code === undefined) {
      var map = { "back": 14, "enter": 28, "tab": 15, "space": 57 }
      code = map[key.type]
    }
    if (code === undefined) return
    root.sendWithMods(code)
  }

  // Send a keycode wrapped in the currently-held sticky modifiers (Ctrl, Alt,
  // Shift), pressed first and released last, exactly like a real chord.
  function sendWithMods(code) {
    if (root.ctrlOn) root.sendRaw(29, true)
    if (root.altOn) root.sendRaw(56, true)
    if (root.shiftOn) root.sendRaw(42, true)
    root.sendRaw(code, true)
    root.sendRaw(code, false)
    if (root.shiftOn) root.sendRaw(42, false)
    if (root.altOn) root.sendRaw(56, false)
    if (root.ctrlOn) root.sendRaw(29, false)
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

  property var rows: [
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
      { n:"'", s:"\"", c:40, type:"char" },
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
  ]

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

  Timer {
    id: restartTimer
    interval: 1500
    repeat: false
    onTriggered: injector.running = true
  }

  Component.onCompleted: injector.running = true

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

    Component.onCompleted: {
      if (!root.bar && panel.screen) {
        var w = panel.contentWidth, h = panel.contentHeight
        panel.dragOffset = Qt.point(
          Math.round(panel.screen.width / 2 - w / 2),
          Math.round(panel.screen.height - h - Style.space(24))
        )
      }
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // Full-surface drag layer (behind the keys) so the keyboard can be moved
      // by click-and-hold-drag anywhere, including gaps and padding.
      MouseArea {
        id: dragLayer
        anchors.fill: parent
        drag.target: panel.dragHandle
        drag.axis: Drag.XAndYAxis
        drag.threshold: 6
        onPressed: {
          panel.dragHandle.lastX = panel.dragHandle.x
          panel.dragHandle.lastY = panel.dragHandle.y
        }
      }

      Column {
        id: content
        width: parent.width
        spacing: root.keyGap
        anchors.centerIn: parent

        // Header: drag icon (top-left) + close button (top-right). The drag
        // icon drives the panel's stable dragHandle proxy, so the whole gesture
        // is captured and the keyboard follows the cursor smoothly.
        Row {
          id: header
          width: parent.width
          height: root.gripH
          spacing: root.keyGap

          Item {
            id: grip
            width: root.gripH
            height: root.gripH

            Text {
              anchors.centerIn: parent
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

          Item {
            id: spacer
            width: parent.width - grip.width - closeBtn.width - root.keyGap * 2
            height: 1
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
          delegate: Row {
            spacing: root.keyGap
            Repeater {
              model: modelData
              delegate:               QuillKey {
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
                boardWidth: root.kbNaturalWidth - root.pad * 2
                dragTarget: panel.dragHandle
                borderColor: root.keyBorder
                contentColor: root.keyContent
                contentColorDim: root.keyContentDim
                keyRadius: Style.space(8)
                keyFont: Style.font.family
                keyFontSize: Style.font.body
                onPressed: root.pressKey(modelData)
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
