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
  property bool injectError: false
  property bool wantInjector: true

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
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
    if (!injector.running) { root.injectError = true; return }
    if (key.type === "char") {
      if (root.shiftOn) root.sendRaw(42, true)
      root.sendRaw(key.c, true)
      root.sendRaw(key.c, false)
      if (root.shiftOn) root.sendRaw(42, false)
      return
    }
    var map = { "back": 14, "enter": 28, "tab": 15, "space": 57 }
    var code = map[key.type]
    if (code !== undefined) {
      root.sendRaw(code, true)
      root.sendRaw(code, false)
    }
  }

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
      { n:"Shift", s:"Shift", c:42, type:"shift", w:1.6 },
      { n:"z", s:"Z", c:44, type:"char" },
      { n:"x", s:"X", c:45, type:"char" },
      { n:"c", s:"C", c:46, type:"char" },
      { n:"v", s:"V", c:47, type:"char" },
      { n:"b", s:"B", c:48, type:"char" },
      { n:"n", s:"N", c:49, type:"char" },
      { n:"m", s:"M", c:50, type:"char" },
      { n:",", s:"<", c:51, type:"char" },
      { n:".", s:">", c:52, type:"char" },
      { n:"/", s:"?", c:53, type:"char" }
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(580))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(6)
        anchors.centerIn: parent

        // Drag handle: grab here to move the keyboard anywhere on screen.
        Rectangle {
          id: grip
          width: parent.width
          height: Style.space(16)
          radius: 4
          color: "#222222"
          property point last: Qt.point(0, 0)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.SizeAllCursor
            onPressed: function(mouse) { grip.last = grip.mapToItem(panel, mouse.x, mouse.y) }
            onPositionChanged: function(mouse) {
              if (!pressed) return
              var g = grip.mapToItem(panel, mouse.x, mouse.y)
              panel.dragOffset = Qt.point(panel.dragOffset.x + (g.x - grip.last.x), panel.dragOffset.y + (g.y - grip.last.y))
              grip.last = g
            }
          }

          Text {
            anchors.centerIn: parent
            text: "⠿  drag"
            color: "#888888"
            font.family: Style.font.family
            font.pixelSize: 11
          }
        }

        Repeater {
          model: root.rows
          delegate: Row {
            spacing: Style.space(6)
            Repeater {
              model: modelData
              delegate: KeyButton {
                key: modelData
                shift: root.shiftOn
                error: root.injectError
                onPressed: root.pressKey(modelData)
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.injectError
          text: "quill-inject not running — build it and ensure /dev/uinput access"
          color: "#ff6b6b"
          font.family: Style.font.family
          font.pixelSize: 12
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
