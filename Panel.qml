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

  // --- word suggestions ----------------------------------------------------
  // Dictionary is the open-source Hunspell word list shipped by Firefox /
  // Chromium (via wooorm/dictionaries). It is downloaded + preprocessed into a
  // plain lowercase word list on first use (per language) and kept in memory
  // for prefix lookups.
  property string _loadedLocale: ""
  property bool dictReady: false
  property bool dictLoading: false
  property string suggestionError: ""
  property var dictWords: []
  property string typedWord: ""
  property bool wordStartShift: false
  property var suggestions: []

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

    // Track the current word for suggestions.
    if (k.type === "char") {
      var ch = k.n
      if (ch && /^[a-zA-Z]$/.test(ch)) {
        if (root.typedWord.length === 0) root.wordStartShift = root.shiftOn
        root.typedWord += ch.toLowerCase()
      } else {
        root.typedWord = ""   // symbol / digit breaks the word
      }
      root.updateSuggestions()
    } else if (k.type === "back") {
      if (root.typedWord.length > 0) root.typedWord = root.typedWord.slice(0, -1)
      root.updateSuggestions()
    } else if (k.type === "space" || k.type === "enter" || k.type === "tab") {
      root.typedWord = ""
      root.suggestions = []
    }

    root._repeatCode = code
    root._repeatChar = (k.type === "char" && k.n && /^[a-zA-Z]$/.test(k.n)) ? k.n.toLowerCase() : null
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

  // --- word suggestions ----------------------------------------------------

  // Inject a single ASCII letter, adding a Shift press for uppercase so we do
  // not depend on the on-screen shift state.
  // Correct Linux evdev keycodes for a-z (not consecutive!)
  function letterCode(ch) {
    var map = {
      "a": 30, "b": 48, "c": 46, "d": 32, "e": 18, "f": 33, "g": 34, "h": 35,
      "i": 23, "j": 36, "k": 37, "l": 38, "m": 50, "n": 49, "o": 24, "p": 25,
      "q": 16, "r": 19, "s": 31, "t": 20, "u": 22, "v": 47, "w": 17, "x": 45,
      "y": 21, "z": 44
    };
    return map[ch];
  }

  function injectChar(ch) {
    var lower = ch.toLowerCase()
    var code = root.letterCode(lower)
    if (code === undefined) return
    if (ch !== lower) root.sendRaw(42, true)
    root.sendRaw(code, true)
    root.sendRaw(code, false)
    if (ch !== lower) root.sendRaw(42, false)
  }

  // Click a suggestion: delete the currently typed (tracked) word, then type
  // the suggestion in its place.
  function applySuggestion(word) {
    if (!injector.running) { root.injectError = true; return }
    var n = root.typedWord.length
    for (var i = 0; i < n; i++) { root.sendRaw(14, true); root.sendRaw(14, false) }
    var typed = word
    if (root.wordStartShift && typed.length) typed = typed.charAt(0).toUpperCase() + typed.slice(1)
    for (var j = 0; j < typed.length; j++) root.injectChar(typed.charAt(j))
    root.typedWord = typed.toLowerCase()
    root.suggestions = []
  }

  function updateSuggestions() {
    if (root.typedWord.length < 2 || !root.dictReady) { root.suggestions = []; return }
    root.suggestions = root.suggest(root.typedWord, 4)
  }

  // Binary-search prefix matches in the sorted dictionary.
  function suggest(prefix, max) {
    var arr = root.dictWords
    if (!arr || !prefix || prefix.length < 2) return []
    prefix = prefix.toLowerCase()
    var lo = 0, hi = arr.length
    while (lo < hi) { var mid = (lo + hi) >> 1; if (arr[mid] < prefix) lo = mid + 1; else hi = mid }
    var res = []
    for (var i = lo; i < arr.length && res.length < max; i++) {
      if (arr[i].indexOf(prefix) !== 0) break
      res.push(arr[i])
    }
    return res
  }

  function buildDict(raw) {
    var lines = raw.split("\n")
    var arr = []
    for (var i = 0; i < lines.length; i++) {
      var w = lines[i].trim()
      if (w.length >= 2 && w.length <= 20) arr.push(w)
    }
    arr.sort()
    root.dictWords = arr
  }

  // Download + preprocess the language dictionary on first use, then load it.
  function ensureDict() {
    var loc = (root.activeLayout === "pt-br") ? "pt" : "en"
    if (root._loadedLocale === loc && (root.dictReady || root.dictLoading)) return
    root._loadedLocale = loc
    root.dictLoading = true
    var url = "https://raw.githubusercontent.com/wooorm/dictionaries/main/dictionaries/" + loc + "/index.dic"
    var script = "D=$(echo ~)/.local/share/quill/dict; L=" + loc + "; F=$D/$L.words; mkdir -p \"$D\"; " +
      "if [ ! -f \"$F\" ]; then T=$(mktemp); " +
      "if curl -fsSL '" + url + "' -o \"$T\"; then " +
      "tail -n +2 \"$T\" | iconv -f UTF-8 -t ASCII//TRANSLIT | " +
      "awk '{split($0,a,\"/\"); w=tolower(a[1]); gsub(/[^a-z]/,\"\",w); if(length(w)>=2 && length(w)<=20) print w}' | sort -u > \"$F\"; fi; " +
      "rm -f \"$T\"; fi; echo ok"
    dictSetup.command = ["sh", "-c", script]
    dictSetup.running = true
  }

  function loadDictFile() {
    var loc = root._loadedLocale
    dictLoad.command = ["sh", "-c", "cat \"$(echo ~)/.local/share/quill/dict/" + loc + ".words\""]
    dictLoad.running = true
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
  function kbBlockWidth(rows) {
    var m = 0
    for (var r = 0; r < rows.length; r++) m = Math.max(m, root.kbRowWidth(rows[r]))
    return m
  }
  readonly property int kbNaturalWidth: {
    var mainW = root.kbBlockWidth(root.rows)
    var navW = root.kbBlockWidth(root.navRows)
    return mainW + root.keyGap + navW + root.pad * 2
  }
  readonly property int kbNaturalHeight: {
    var n = Math.max(root.rows.length, root.navRows.length)
    return root.gripH + root.keyGap + n * root.keyH + (n - 1) * root.keyGap + root.pad * 2
  }

  // Active layout, auto-detected at startup from the system keyboard layout
  // (Hyprland kb_layout / $LANG). Falls back to "us".
  property string activeLayout: "us"

  // Navigation / editing cluster shown to the right of the main keyboard (like a
  // real keyboard), with the arrow keys below it. Codes are Linux/evdev keycodes
  // (matching quill-inject). "spacer" entries reserve a key slot without rendering.
  readonly property var navRows: [
    [
      { n:"PrtSc", s:"PrtSc", c:99,  type:"fn" },
      { n:"ScrLk", s:"ScrLk", c:70,  type:"fn" },
      { n:"Pause", s:"Pause", c:119, type:"fn" }
    ],
    [
      { n:"Ins", s:"Ins", c:110, type:"fn" },
      { n:"Home", s:"Home", c:102, type:"fn" },
      { n:"PgUp", s:"PgUp", c:104, type:"fn" }
    ],
    [
      { n:"Del", s:"Del", c:111, type:"fn" },
      { n:"End", s:"End", c:107, type:"fn" },
      { n:"PgDn", s:"PgDn", c:109, type:"fn" }
    ],
    [
      { type:"spacer" },
      { n:"↑", s:"↑", c:103, type:"fn" },
      { type:"spacer" }
    ],
    [
      { n:"←", s:"←", c:105, type:"fn" },
      { n:"↓", s:"↓", c:108, type:"fn" },
      { n:"→", s:"→", c:106, type:"fn" }
    ]
  ]

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
  property var _repeatChar: null

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
      if (root._repeatCode !== null) {
        root.sendHold(root._repeatCode)
        if (root._repeatCode === 14) {
          if (root.typedWord.length > 0) { root.typedWord = root.typedWord.slice(0, -1); root.updateSuggestions() }
        } else if (root._repeatChar) {
          root.typedWord += root._repeatChar
          root.updateSuggestions()
        }
      }
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
      root.ensureDict()
    }
  }

  // Downloads + preprocesses the language dictionary (if absent) then reads it.
  Process {
    id: dictSetup
    running: false
    stdout: StdioCollector {}
    onExited: function(code) { root.loadDictFile() }
  }
  Process {
    id: dictLoad
    running: false
    property string _raw: ""
    stdout: StdioCollector { onDataChanged: dictLoad._raw = text }
    onExited: function(code) {
      root.dictLoading = false
      if (code === 0 && dictLoad._raw) {
        root.buildDict(dictLoad._raw)
        root.dictReady = true
        root.updateSuggestions()
      } else {
        root.suggestionError = "could not load dictionary"
      }
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
    root.ensureDict()
  }

  onOpenedChanged: {
    root.typedWord = ""
    root.suggestions = []
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

      Component {
        id: keyDelegate
        QuillKey {
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
          enabled: key.type !== "spacer"
          opacity: key.type === "spacer" ? 0 : 1
          Layout.preferredWidth: root.keyBase * (key.w || 1)
          Layout.preferredHeight: root.keyH
          Layout.fillWidth: key.type === "shift" || key.type === "ctrl" || key.type === "alt" || key.type === "space" || key.type === "back" || key.type === "tab" || key.type === "enter"
          Layout.fillHeight: false
          onPressed: root.keyDown(modelData)
          onReleased: root.keyReleased(modelData)
        }
      }

      Component {
        id: suggestionDelegate
        Rectangle {
          height: root.gripH - 6
          Layout.preferredHeight: root.gripH - 6
          radius: 4
          width: lbl.implicitWidth + 12
          Layout.preferredWidth: lbl.implicitWidth + 12
          color: sugMA.containsMouse ? Qt.alpha(Color.foreground, 0.20) : Qt.alpha(Color.foreground, 0.12)
          border.color: root.keyBorder
          border.width: 1

          Text {
            id: lbl
            anchors.centerIn: parent
            text: modelData
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: 12
          }
          MouseArea {
            id: sugMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.applySuggestion(modelData)
          }
        }
      }

      Column {
        id: content
        width: parent.width
        spacing: root.keyGap
        anchors.centerIn: parent

        // Header: left area is the drag handle; the word suggestions appear
        // centred between it and the close button.
        RowLayout {
          id: header
          width: parent.width
          height: root.gripH
          spacing: root.keyGap

          Item {
            id: grip
            Layout.fillWidth: true
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

          RowLayout {
            id: sugRow
            spacing: 6
            visible: root.suggestions.length > 0
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignVCenter
            Repeater {
              model: root.suggestions
              delegate: suggestionDelegate
            }
          }

          Item {
            Layout.fillWidth: true
            height: root.gripH
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

          // Body: main typing block (left) + navigation/edit cluster (right).
          Row {
            width: parent.width
            spacing: root.keyGap

            Column {
              id: mainBlock
              width: root.kbBlockWidth(root.rows)
              spacing: root.keyGap
              Repeater {
                model: root.rows
                delegate: RowLayout {
                  width: parent.width
                  spacing: root.keyGap
                  Repeater { model: modelData; delegate: keyDelegate }
                }
              }
            }

            Column {
              id: navBlock
              width: root.kbBlockWidth(root.navRows)
              spacing: root.keyGap
              Repeater {
                model: root.navRows
                delegate: RowLayout {
                  width: parent.width
                  spacing: root.keyGap
                  Repeater { model: modelData; delegate: keyDelegate }
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
