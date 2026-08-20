import QtQuick

// A single keyboard key. Deliberately free of any `qs.*` import so it stays
// safe as a Repeater delegate (module singletons like Style do not resolve
// inside a delegate's own file scope). Visuals are supplied by the parent as
// typed properties, each with a literal fallback so the key still renders if a
// value is ever missing.

Item {
  id: root
  property var key: null
  property bool shift: false
  property bool active: false
  property bool error: false
  property color surface: "#2a2a2a"
  property color surfaceHover: "#333333"
  property color surfacePressed: "#4a4a4a"
  property color surfaceError: "#3a2a2a"
  property color borderColor: "#555555"
  property color contentColor: "#eeeeee"
  property color contentColorDim: "#999999"
  property int keyRadius: 6
  property string keyFont: "monospace"
  property int keyFontSize: 14
  signal pressed(var key)
  signal released(var key)

  // Inner width of the whole keyboard; the Space key stretches to fill it.
  property int boardWidth: 0

  readonly property real span: (key && key.w) ? key.w : 1

  implicitWidth: (key && key.type === "space" && boardWidth > 0) ? boardWidth : 40 * span
  implicitHeight: 46

  Rectangle {
    anchors.fill: parent
    radius: root.keyRadius
    color: mouse.pressed ? root.surfacePressed
      : (root.error ? root.surfaceError : (root.active ? root.surfacePressed : (mouse.containsMouse ? root.surfaceHover : root.surface)))
    border.color: root.borderColor
    border.width: 1

    Text {
      anchors.centerIn: parent
      text: (root.key && (root.shift ? root.key.s : root.key.n)) || ""
      color: root.error ? "#ff9a9a"
        : (root.key && (root.key.type === "shift" || root.key.type === "ctrl" || root.key.type === "alt")
            ? (root.active ? root.contentColor : root.contentColorDim)
            : root.contentColor)
      font.family: root.keyFont
      font.pixelSize: root.keyFontSize
      font.bold: root.key && root.key.type === "enter"
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onPressed: root.pressed(root.key)
    onReleased: root.released(root.key)
  }
}
