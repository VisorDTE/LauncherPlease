import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "ChordKey.js" as ChordKey
import "GridLayout.js" as GridLayout
import "LauncherConfig.js" as LauncherConfig
import "LauncherModel.js" as LauncherModel
import "LauncherUsage.js" as LauncherUsage

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int cursorIndex: 0
  property bool cursorActive: true
  property int bounceIndex: -1
  property real fadeOpacity: 1
  readonly property int fadeMs: 260

  property var rawApps: []
  property var apps: []
  property var layout: ({ rows: [], count: 0, apps: [] })
  property var cfg: LauncherConfig.merge("{}", "{}")
  property string fileConfigRaw: "{}"
  property string payloadConfigRaw: "{}"
  property string usageRaw: "{}"
  property bool chordsCaptured: false
  property int gridHeight: 0

  property bool isList: false
  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: root.home + "/.config/omarchy/plugins/jose.launcherplease"
  readonly property string listPath: root.pluginDir + "/list.sh"
  readonly property string recordPath: root.pluginDir + "/record.sh"
  readonly property string setLayoutPath: root.pluginDir + "/set-layout.sh"
  readonly property string chordPath: root.pluginDir + "/chords.sh"
  readonly property string stateioPath: root.pluginDir + "/stateio.py"
  readonly property string configPath: root.home + "/.config/omarchy/launcherplease.json"
  readonly property string usagePath: root.home + "/.local/state/omarchy/launcherplease/usage.json"

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color borderColor: Color.menu.border
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorderColor: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", root.selectedBorderColor, 0)
  property color accent: Color.accent
  property var borderSpec: Border.surfaceSpec("menu", "border", root.borderColor, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  property int columns: 8
  readonly property int cellH: Style.space(92)
  readonly property int listMargin: Math.max(Style.gapsOut * 2, Style.spacing.md)
  readonly property int listRowH: Math.max(Style.space(44), Style.font.body + Style.font.caption + Style.spacing.md)
  readonly property int listIconH: Math.min(Style.space(22), root.listRowH - Style.spacing.md * 2)
  readonly property int searchH: Math.max(Style.space(26), Style.font.body + Style.spacing.controlPaddingY * 2)
  readonly property int headerH: Math.max(Style.space(22), Style.font.subtitle + Style.spacing.xs)
  readonly property int footerH: Math.max(Style.space(20), Style.font.caption + Style.spacing.sm)
  readonly property int contentMargin: Style.spacing.md
  readonly property int gridGap: Style.spacing.xs
  readonly property int iconH: Style.space(28)
  readonly property int keycapH: Style.space(17)
  readonly property int keycapFont: Style.font.caption
  readonly property real keycapCharW: Style.font.caption * 0.6
  readonly property int keycapPadX: Style.space(4)
  readonly property int keycapGap: Style.space(3)
  readonly property color keycapFill: Util.alpha(root.accent, 0.13)
  readonly property color keycapFillCursor: Util.alpha(root.selectedText, 0.2)
  readonly property color keycapBorder: Util.alpha(root.accent, 0.6)
  readonly property color keycapBorderCursor: Util.alpha(root.selectedText, 0.7)
  readonly property color keycapText: root.foreground
  readonly property color keycapTextCursor: root.selectedText

  function iconUrl(icon) {
    var value = String(icon || "")
    if (!value) return ""
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    return themed && themed.length ? themed : ""
  }

  // Monospace advance approximations (the shell font is effectively mono), used
  // to auto-size the list panel so the shortcut column hugs the app name with a
  // small fixed gap and only widens when a long name needs the room.
  function nameWidthPx(label) {
    return String(label || "").length * Style.font.body * 0.6
  }

  function chordWidthPx(chord) {
    var keys = ChordKey.chordKeys(chord)
    if (!keys.length) return 0
    var total = 0
    for (var i = 0; i < keys.length; i++) {
      total += String(keys[i]).length * root.keycapCharW + root.keycapPadX * 2
    }
    total += (keys.length - 1) * root.keycapGap
    return Math.ceil(total)
  }

  // Widest visible row measured as icon + name + gap + shortcut. The panel is
  // only as wide as its content demands, clamped to stay on screen.
  property int listFitW: 0
  property int listCardW: 0

  function computeListFit() {
    var w = 0
    var cap = Math.floor(Style.space(420))
    for (var i = 0; i < root.apps.length; i++) {
      var nameW = Math.min(root.nameWidthPx(root.apps[i].label), cap)
      var chordW = root.cfg.showChords ? root.chordWidthPx(root.apps[i].chord) : 0
      var row = nameW + chordW
      if (row > w) w = row
    }
    root.listFitW = w
    root.listCardW = root.computeListCardW()
  }

  function computeListCardW() {
    // icon slot + 4 md gaps (outer margins, around name, before shortcut)
    var pw = Number(panel.width)
    if (!isFinite(pw) || pw <= 0) pw = 1920
    var content = root.listFitW + root.listIconH + Style.spacing.md * 4
    var minW = Style.space(240)
    var maxW = Style.space(560)
    var res = Math.min(maxW, Math.max(minW, Math.min(content, pw - root.listMargin * 2)))
    return Math.round(res)
  }

  function listCardWidth() {
    if (root.listCardW > 0) return root.listCardW
    return root.computeListCardW()
  }

  function applyConfig() {
    root.cfg = LauncherConfig.merge(root.fileConfigRaw, root.payloadConfigRaw)
    root.columns = Math.max(1, root.cfg.columns)
    root.isList = root.cfg.layout === "list"
  }

  function rowHeight(rowType) {
    if (rowType === "banner") return root.headerH
    return root.isList ? root.listRowH : root.cellH
  }

  function rebuild() {
    var normalized = LauncherModel.normalizeApps(root.rawApps)
    var filtered = []
    for (var i = 0; i < normalized.length; i++) {
      if (LauncherModel.matchesFilter(normalized[i], root.filterText)) filtered.push(normalized[i])
    }
    var days = LauncherUsage.prune(LauncherUsage.parseDays(root.usageRaw), LauncherUsage.dayKey(), root.cfg.mostUsedDays)
    var arranged = LauncherModel.arrange(filtered, root.cfg, LauncherUsage.scores(days))
    root.apps = arranged.apps
    if (root.isList) {
      root.layout = GridLayout.buildList(root.apps, root.cfg.showCategories)
      root.computeListFit()
    } else {
      root.layout = GridLayout.build(root.apps, root.columns, root.cfg.layout)
    }

    if (!root.layout.count) root.cursorIndex = 0
    else if (root.cursorIndex >= root.layout.count) root.cursorIndex = root.layout.count - 1
    else if (root.cursorIndex < 0) root.cursorIndex = 0

    var height = 0
    var rows = root.layout.rows || []
    for (var r = 0; r < rows.length; r++) {
      height += root.rowHeight(rows[r].type)
      if (r > 0) height += Style.spacing.xs
    }
    root.gridHeight = height
  }

  function onListLoaded(raw) {
    try { root.rawApps = JSON.parse(String(raw || "[]")) } catch (e) { root.rawApps = [] }
    root.rebuild()
    if (root.opened) {
      root.scrollToCursor()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  function refreshList() {
    listProc.running = false
    listProc.running = true
  }

  function setFilter(text) {
    var t = String(text || "")
    if (t.length > 128) t = t.slice(0, 128)
    root.filterText = t
    root.cursorIndex = 0
    root.rebuild()
  }

  function moveCursor(dir) {
    var next = GridLayout.move(root.layout, root.cursorIndex, dir)
    if (next < 0) return
    root.cursorIndex = next
    root.cursorActive = true
    root.scrollToCursor()
  }

  function jumpCategory(delta) {
    if (root.layout.count === 0) return
    var next = GridLayout.categoryJump(root.layout, root.cursorIndex, delta)
    root.cursorIndex = next
    root.cursorActive = true
    root.scrollToCursor()
  }

  function toggleLayout() {
    var order = ["compact", "roomy", "list"]
    var cur = order.indexOf(root.cfg.layout)
    var next = order[(cur + 1) % order.length]
    root.cfg.layout = next
    root.isList = next === "list"
    root.rebuild()
    root.scrollToCursor()
    setLayoutProc.command = ["/usr/bin/timeout", "-k", "2", "5", "/usr/bin/bash", root.setLayoutPath, next]
    setLayoutProc.running = false
    setLayoutProc.running = true
  }

  function scrollToCursor() {
    var row = GridLayout.rowOf(root.layout, root.cursorIndex)
    if (row < 0 || !flick) return
    var y = 0
    var rows = root.layout.rows || []
    for (var i = 0; i < row && i < rows.length; i++) {
      y += root.rowHeight(rows[i].type)
      y += Style.spacing.xs
    }
    var rowH = (rows[row] && rows[row].type === "banner") ? root.headerH : root.rowHeight(rows[row] ? rows[row].type : "")
    if (y < flick.contentY) flick.contentY = y
    else if (y + rowH > flick.contentY + flick.height) flick.contentY = Math.max(0, y + rowH - flick.height)
  }

  function appIndexById(id) {
    for (var i = 0; i < root.apps.length; i++) {
      if (root.apps[i].id === id) return i
    }
    return -1
  }

  function open(payloadJson) {
    root.payloadConfigRaw = payloadJson || "{}"
    root.applyConfig()
    root.fadeOpacity = 1
    root.opened = true
    root.cursorActive = true
    root.cursorIndex = 0
    root.bounceIndex = -1
    root.filterText = ""
    root.refreshList()
    if (flick) flick.contentY = 0
    if (root.cfg.duration > 0) {
      autoCloseTimer.interval = root.cfg.duration
      autoCloseTimer.restart()
    } else {
      autoCloseTimer.stop()
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    root.startChordCapture()
  }

  function close() {
    root.stopChordCapture()
    autoCloseTimer.stop()
    root.opened = false
    root.chordsCaptured = false
  }

  function beginFade() {
    if (!root.opened) return
    autoCloseTimer.stop()
    root.fadeOpacity = 0
    fadeCloseTimer.restart()
  }

  function toggle(payloadJson) {
    if (root.opened) root.close()
    else root.open(payloadJson || "{}")
  }

  function playBounce(appIndex) {
    root.bounceIndex = appIndex
    bounceClearTimer.restart()
  }

  function launchApp(appIndex) {
    if (appIndex < 0 || appIndex >= root.apps.length) return
    var app = root.apps[appIndex]
    var command = app.command
    if (!command) return
    root.recordUsage(app.id)
    root.playBounce(appIndex)
    root.execLaunch(command)
  }

  function confirm() {
    if (root.layout.count > 0) root.launchApp(root.cursorIndex)
  }

  function execLaunch(command) {
    if (!command) return
    Util.execDetached(command)
    root.close()
  }

  function recordUsage(id) {
    if (!id) return
    recordProc.command = ["/usr/bin/timeout", "-k", "2", "5", "/usr/bin/bash", root.recordPath, id, String(root.cfg.mostUsedDays)]
    recordProc.running = false
    recordProc.running = true
  }

  function qtKeyFromToken(token) {
    var t = String(token || "").toUpperCase()
    if (t === "RETURN" || t === "ENTER") return Qt.Key_Return
    if (t === "SLASH") return Qt.Key_Slash
    if (t === "SPACE") return Qt.Key_Space
    if (t === "COMMA") return Qt.Key_Comma
    if (t === "PERIOD") return Qt.Key_Period
    if (t === "MINUS") return Qt.Key_Minus
    if (t === "EQUAL") return Qt.Key_Equal
    if (t === "TAB") return Qt.Key_Tab
    if (t === "ESCAPE" || t === "ESC") return Qt.Key_Escape
    if (t.length === 1) return t.charCodeAt(0)
    return -1
  }

  function eventMatchesChord(event, chord) {
    var raw = String(chord || "").toUpperCase()
    if (!raw) return false
    var wantSuper = raw.indexOf("SUPER") >= 0
    var wantShift = raw.indexOf("SHIFT") >= 0
    var wantCtrl = raw.indexOf("CTRL") >= 0 || raw.indexOf("CONTROL") >= 0
    var wantAlt = raw.indexOf("ALT") >= 0
    var mods = event.modifiers
    if (wantSuper !== !!(mods & Qt.MetaModifier)) return false
    if (wantShift !== !!(mods & Qt.ShiftModifier)) return false
    if (wantCtrl !== !!(mods & Qt.ControlModifier)) return false
    if (wantAlt !== !!(mods & Qt.AltModifier)) return false
    var token = raw
    var plus = raw.lastIndexOf(" + ")
    if (plus >= 0) token = raw.slice(plus + 3).replace(/^\s+|\s+$/g, "")
    var wantKey = root.qtKeyFromToken(token)
    if (wantKey < 0) return false
    if (event.key === wantKey) return true
    if (wantKey === Qt.Key_Return && event.key === Qt.Key_Enter) return true
    return false
  }

  function launchMatchingChord(event) {
    for (var i = 0; i < root.apps.length; i++) {
      if (root.eventMatchesChord(event, root.apps[i].chord)) {
        root.launchApp(i)
        return true
      }
    }
    return false
  }

  function chordPayloadJson() {
    var apps = LauncherModel.normalizeApps(root.rawApps)
    var out = []
    var seen = {}
    for (var i = 0; i < apps.length; i++) {
      var chord = apps[i].chord
      if (!chord || seen[chord]) continue
      seen[chord] = true
      out.push({
        chord: chord,
        id: apps[i].id,
        label: apps[i].label,
        command: apps[i].command
      })
    }
    return JSON.stringify(out)
  }

  function startChordCapture() {
    if (!root.cfg.captureChords) return
    root.chordsCaptured = true
    chordProc.command = ["/usr/bin/timeout", "-k", "2", "5", "/usr/bin/bash", root.chordPath, "capture", root.chordPayloadJson()]
    chordProc.running = false
    chordProc.running = true
  }

  function stopChordCapture() {
    if (!root.chordsCaptured) return
    root.chordsCaptured = false
    chordProc.command = ["/usr/bin/timeout", "-k", "2", "5", "/usr/bin/bash", root.chordPath, "restore", root.chordPayloadJson()]
    chordProc.running = false
    chordProc.running = true
  }

  function readConfig() {
    configReadProc.running = false
    configReadProc.running = true
  }

  function readUsage() {
    usageReadProc.running = false
    usageReadProc.running = true
  }

  IpcHandler {
    target: "launcherplease"
    function open(payloadJson: string): string { root.open(payloadJson); return "ok" }
    function close(): string { root.close(); return "ok" }
    function fade(): string { root.beginFade(); return "ok" }
    function toggle(payloadJson: string): string { root.toggle(payloadJson); return "ok" }
    function state(): string { return root.opened ? "open:" + root.apps.length : "closed" }
    function ping(): string { return "ok" }
    function refresh(): string { root.refreshList(); return "ok" }
    function flash(id: string): string { return "ok" }
    function launch(id: string): string {
      var idx = root.appIndexById(id)
      if (idx >= 0) { root.launchApp(idx); return "ok" }
      var apps = LauncherModel.normalizeApps(root.rawApps)
      for (var i = 0; i < apps.length; i++) {
        if (apps[i].id === id) { root.execLaunch(apps[i].command); return "ok" }
      }
      return "notfound"
    }
  }

  // Config and usage are read through stateio.py (held directory fd, no-follow
  // open, owner check, byte cap). FileView is used only as a change trigger:
  // preload is off and text() is never called, so no unbounded read happens.
  FileView {
    path: root.configPath
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: root.readConfig()
  }

  FileView {
    path: root.usagePath
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: root.readUsage()
  }

  Process {
    id: listProc
    command: ["/usr/bin/timeout", "-k", "2", "8", "/usr/bin/bash", root.listPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onListLoaded(text)
    }
  }

  Process {
    id: configReadProc
    command: ["/usr/bin/timeout", "-k", "2", "5", "/usr/bin/python3", root.stateioPath, "read-config"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.fileConfigRaw = String(text || "{}")
        root.applyConfig()
        root.rebuild()
      }
    }
  }

  Process {
    id: usageReadProc
    command: ["/usr/bin/timeout", "-k", "2", "5", "/usr/bin/python3", root.stateioPath, "read-usage"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.usageRaw = String(text || "{}")
        if (root.rawApps.length) root.rebuild()
      }
    }
  }

  Process { id: chordProc }
  Process { id: recordProc }
  Process { id: setLayoutProc }

  Timer { id: autoCloseTimer; repeat: false; onTriggered: root.beginFade() }
  Timer { id: fadeCloseTimer; interval: root.fadeMs; repeat: false; onTriggered: root.close() }
  Timer { id: bounceClearTimer; interval: 460; repeat: false; onTriggered: root.bounceIndex = -1 }

  Component.onCompleted: {
    root.readConfig()
    root.readUsage()
    root.applyConfig()
    root.refreshList()
  }

  Component.onDestruction: {
    // Terminate/reap every tracked child process so none outlives the plugin.
    listProc.running = false
    recordProc.running = false
    setLayoutProc.running = false
    configReadProc.running = false
    usageReadProc.running = false

    if (root.chordsCaptured) {
      // Restore as a detached, timeout-bounded fail-safe whose lifetime
      // outlives this QML component, so temporary Hyprland binds are always
      // reverted even when the shell is tearing down.
      chordProc.command = ["/usr/bin/timeout", "-k", "2", "5", "/usr/bin/bash", root.chordPath, "restore", root.chordPayloadJson()]
      chordProc.startDetached()
    } else {
      chordProc.running = false
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "launcherplease"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    onVisibleChanged: if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      opacity: root.fadeOpacity
      MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      opacity: root.fadeOpacity
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.setFilter("")
          else root.close()
          event.accepted = true
          return
        }
        if (root.launchMatchingChord(event)) {
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier)) {
          root.toggleLayout()
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Tab) {
          root.jumpCategory(event.modifiers & Qt.ShiftModifier ? -1 : 1)
          event.accepted = true
          return
        }
        var combo = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
        if (combo) {
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Left) {
          root.moveCursor("left"); event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          root.moveCursor("right"); event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.moveCursor("up"); event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.moveCursor("down"); event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.moveCursor("up"); event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          root.moveCursor("down"); event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
          if (root.filterText) { root.setFilter(root.filterText.slice(0, -1)); event.accepted = true }
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.confirm(); event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
          root.setFilter(root.filterText + event.text)
          event.accepted = true
        }
      }

      BorderSurface {
        id: card
        x: root.isList ? (parent.width - width - root.listMargin) : (parent.width - width) / 2
        y: root.isList ? root.listMargin : (parent.height - height) / 2
        width: root.isList ? root.listCardWidth() : Math.min(panel.width * 0.75, panel.width - Style.gapsOut * 4)
        height: root.isList ? parent.height - root.listMargin * 2
                           : Math.min(root.searchH + root.footerH + root.gridHeight + root.contentMargin * 2 + Style.spacing.sm * 2,
                                      panel.height - Style.gapsOut * 2)
        radius: root.cornerRadius
        color: root.background
        borderSpec: root.borderSpec
        padding: root.contentMargin
        clip: true

        MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }

        Column {
          id: body
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: Style.spacing.sm

          Rectangle {
            id: searchBox
            width: parent.width
            height: root.searchH
            radius: root.cornerRadius
            color: Util.alpha(root.foreground, 0.06)
            border.color: Util.alpha(root.accent, 0.35)
            border.width: root.filterText ? 1 : 0
            clip: true

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.IBeamCursor
              onClicked: keyCatcher.forceActiveFocus()
            }

            Item {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.md
              anchors.rightMargin: Style.spacing.md

              Text {
                id: searchIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf002"
                color: root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                id: searchText
                anchors.left: searchIcon.right
                anchors.leftMargin: Style.spacing.sm
                anchors.right: clearSearch.visible ? clearSearch.left : parent.right
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: root.filterText ? root.filterText : "Buscar apps…"
                textFormat: Text.PlainText
                color: root.foreground
                opacity: root.filterText ? 1 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                id: clearSearch
                visible: root.filterText.length > 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf00d"
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.setFilter("")
                    keyCatcher.forceActiveFocus()
                  }
                }
              }
            }
          }

          Flickable {
            id: flick
            width: parent.width
            height: parent.height - root.searchH - root.footerH - Style.spacing.sm
            clip: true
            contentWidth: width
            contentHeight: root.gridHeight
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: true
            focus: false

            Column {
              id: gridCol
              width: flick.width
              spacing: Style.spacing.xs

              Repeater {
                model: root.layout.rows ? root.layout.rows.length : 0

                delegate: Item {
                  id: rowItem
                  required property int index
                  readonly property var rowObj: root.layout.rows[index]
                  readonly property bool isBanner: rowObj && rowObj.type === "banner"
                  readonly property var rowItems: (rowObj && rowObj.items) ? rowObj.items : []
                  readonly property real slotW: (width - (root.columns - 1) * root.gridGap) / root.columns
                  readonly property bool startsCategory: rowObj ? (rowObj.type === "banner" || (rowObj.items && rowObj.items.length && rowObj.items[0].kind === "header")) : false
                  readonly property int listAppIndex: (!root.isList || rowItem.isBanner || rowItem.rowItems.length === 0) ? -1 : (rowItem.rowItems[0].appIndex >= 0 ? rowItem.rowItems[0].appIndex : -1)
                  readonly property var listApp: rowItem.listAppIndex >= 0 ? root.apps[rowItem.listAppIndex] : null
                  readonly property string listIcon: rowItem.listApp ? rowItem.listApp.icon : ""
                  readonly property string listGlyph: rowItem.listApp ? rowItem.listApp.glyph : ""
                  readonly property string listIconFont: rowItem.listApp ? rowItem.listApp.iconFont : ""
                  readonly property string listLabel: rowItem.listApp ? rowItem.listApp.label : ""
                  readonly property string listChord: rowItem.listApp ? rowItem.listApp.chord : ""
                  readonly property string listIconSrc: root.iconUrl(rowItem.listIcon)
                  readonly property var listChordKeys: ChordKey.chordKeys(rowItem.listChord)

                  width: gridCol.width
                  height: rowItem.isBanner ? root.headerH : (root.isList ? root.listRowH : root.cellH)
                  clip: true

                  Text {
                    visible: rowItem.isBanner
                    anchors.fill: parent
                    anchors.leftMargin: root.isList ? Style.spacing.md : 0
                    anchors.rightMargin: root.isList ? Style.spacing.md : 0
                    verticalAlignment: Text.AlignVCenter
                    text: root.cfg.showCategories && rowObj ? (rowObj.label + " · " + rowObj.count) : ""
                    textFormat: Text.PlainText
                    color: root.accent
                    opacity: 0.85
                    font.family: root.fontFamily
                    font.pixelSize: root.isList ? Style.font.caption : Style.font.title
                    font.bold: root.isList ? false : true
                  }

                  Row {
                    visible: !rowItem.isBanner && !root.isList
                    anchors.fill: parent
                    spacing: root.gridGap

                    Repeater {
                      model: rowItem.rowItems.length

                      delegate: Item {
                        id: cell
                        required property int index
                        readonly property var slot: rowItem.rowItems[index]
                        readonly property bool isCat: slot && slot.kind === "header"
                        readonly property int appIndex: (slot && slot.kind === "cell") ? slot.appIndex : -1
                        readonly property var app: appIndex >= 0 ? root.apps[appIndex] : null
                        readonly property string appLabel: app ? app.label : ""
                        readonly property string appIcon: app ? app.icon : ""
                        readonly property string appGlyph: app ? app.glyph : ""
                        readonly property string appFont: app ? app.iconFont : ""
                        readonly property string appChord: app ? app.chord : ""
                        readonly property string iconSrc: root.iconUrl(appIcon)
                        readonly property bool hasCursor: root.cursorActive && appIndex === root.cursorIndex
                        readonly property bool isBouncing: root.bounceIndex === appIndex
                        readonly property var chordKeys: ChordKey.chordKeys(appChord)
                        readonly property var chordRows: ChordKey.wrapKeys(chordKeys, width - Style.spacing.md * 2, root.keycapCharW, root.keycapPadX, root.keycapGap)

                        width: rowItem.slotW
                        height: root.cellH
                        clip: true

                        Text {
                          visible: cell.isCat
                          anchors.fill: parent
                          anchors.margins: Style.space(2)
                          verticalAlignment: Text.AlignVCenter
                          horizontalAlignment: Text.AlignRight
                          text: (cell.isCat && slot && slot.label) ? slot.label : ""
                          textFormat: Text.PlainText
                          color: root.accent
                          opacity: 0.85
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                          wrapMode: Text.WordWrap
                          elide: Text.ElideRight
                        }

                        Rectangle {
                          visible: cell.isCat && cell.index > 0
                          anchors.top: parent.top
                          anchors.bottom: parent.bottom
                          anchors.left: parent.left
                          width: Math.max(1, Style.space(1))
                          color: Util.alpha(root.accent, 0.35)
                        }

                        Rectangle {
                          id: cellBg
                          visible: !cell.isCat
                          anchors.fill: parent
                          anchors.margins: Style.space(2)
                          radius: root.cornerRadius
                          color: hasCursor ? root.selectedBackground : (mouseArea.containsMouse ? Util.alpha(root.accent, 0.06) : "transparent")
                          border.color: hasCursor && root.cfg.effects.glow ? root.accent : "transparent"
                          border.width: hasCursor && root.cfg.effects.glow ? Math.max(1, Style.space(2)) : 0
                          scale: isBouncing ? 1.08 : (hasCursor && root.cfg.effects.pulse ? 1.04 : 1)
                          transformOrigin: Item.Center
                          Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                          Behavior on color { ColorAnimation { duration: 100 } }
                        }

                        Item {
                          visible: !cell.isCat
                          anchors.fill: parent

                          Item {
                            id: iconArea
                            anchors.top: parent.top
                            anchors.topMargin: Style.spacing.md
                            anchors.left: parent.left
                            anchors.leftMargin: Style.spacing.md
                            anchors.right: parent.right
                            anchors.rightMargin: Style.spacing.md
                            height: root.iconH

                            Image {
                              id: appIconImg
                              anchors.centerIn: parent
                              width: root.iconH
                              height: root.iconH
                              sourceSize: Qt.size(root.iconH * 2, root.iconH * 2)
                              source: cell.iconSrc
                              fillMode: Image.PreserveAspectFit
                              visible: cell.iconSrc !== "" && status !== Image.Error
                              asynchronous: true
                            }

                            Text {
                              anchors.centerIn: parent
                              visible: !appIconImg.visible
                              text: cell.appGlyph || "󰈉"
                              textFormat: Text.PlainText
                              color: hasCursor ? root.selectedText : root.foreground
                              font.family: cell.appFont ? cell.appFont : root.fontFamily
                              font.pixelSize: Style.font.displayLarge
                            }
                          }

                          Text {
                            anchors.top: iconArea.bottom
                            anchors.topMargin: Style.spacing.xxs
                            anchors.left: parent.left
                            anchors.leftMargin: Style.spacing.md
                            anchors.right: parent.right
                            anchors.rightMargin: Style.spacing.md
                            text: cell.appLabel
                            textFormat: Text.PlainText
                            color: hasCursor ? root.selectedText : root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                          }

                          Column {
                            id: chipArea
                            visible: root.cfg.showChords && cell.chordKeys.length > 0
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Style.spacing.md
                            anchors.left: parent.left
                            anchors.leftMargin: Style.spacing.md
                            anchors.right: parent.right
                            anchors.rightMargin: Style.spacing.md
                            spacing: Style.spacing.xxs

                            Repeater {
                              model: cell.chordRows.length

                              delegate: Item {
                                id: keyRow
                                required property int index

                                width: parent.width
                                height: root.keycapH

                                Row {
                                  anchors.horizontalCenter: parent.horizontalCenter
                                  spacing: root.keycapGap

                                  Repeater {
                                    model: cell.chordRows[keyRow.index].length

                                    delegate: Rectangle {
                                      required property int index
                                      readonly property string keyLabel: cell.chordRows[keyRow.index][index]

                                      height: root.keycapH
                                      width: keyText.implicitWidth + root.keycapPadX * 2
                                      radius: Math.min(root.cornerRadius, Style.space(4))
                                      color: cell.hasCursor ? root.keycapFillCursor : root.keycapFill
                                      border.color: cell.hasCursor ? root.keycapBorderCursor : root.keycapBorder
                                      border.width: 1

                                      Text {
                                        id: keyText
                                        anchors.centerIn: parent
                                        text: keyLabel
                                        textFormat: Text.PlainText
                                        color: cell.hasCursor ? root.keycapTextCursor : root.keycapText
                                        font.family: root.fontFamily
                                        font.pixelSize: root.keycapFont
                                        font.bold: true
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }

                        MouseArea {
                          id: mouseArea
                          visible: !cell.isCat
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onContainsMouseChanged: if (containsMouse && cell.appIndex >= 0) {
                            root.cursorActive = true
                            root.cursorIndex = cell.appIndex
                          }
                          onClicked: {
                            if (cell.appIndex < 0) return
                            root.cursorIndex = cell.appIndex
                            keyCatcher.forceActiveFocus()
                            root.launchApp(cell.appIndex)
                          }
                        }
                      }
                    }
                  }

                  BorderSurface {
                    id: listItem
                    visible: root.isList && !rowItem.isBanner && rowItem.listAppIndex >= 0
                    anchors.fill: parent
                    radius: root.cornerRadius
                    readonly property bool listHasCursor: root.cursorActive && rowItem.listAppIndex === root.cursorIndex
                    color: listHasCursor ? root.selectedBackground : "transparent"
                    borderSpec: listHasCursor ? root.selectedBorderSpec : Border.none()

                    Behavior on color { ColorAnimation { duration: 90 } }

                    Item {
                      id: listContent
                      anchors.fill: parent
                      anchors.topMargin: listItem.borderTop
                      anchors.rightMargin: listItem.contentRightInset + Style.spacing.md
                      anchors.bottomMargin: listItem.borderBottom
                      anchors.leftMargin: listItem.contentLeftInset + Style.spacing.md
                      clip: true

                      Item {
                        id: listIconSlot
                        width: root.listIconH
                        height: root.listIconH
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left

                        Image {
                          id: listIconImg
                          anchors.centerIn: parent
                          width: root.listIconH
                          height: root.listIconH
                          sourceSize: Qt.size(root.listIconH * 2, root.listIconH * 2)
                          source: rowItem.listIconSrc
                          fillMode: Image.PreserveAspectFit
                          visible: rowItem.listIconSrc !== "" && status !== Image.Error
                          asynchronous: true
                        }

                        Text {
                          anchors.centerIn: parent
                          visible: !listIconImg.visible
                          text: rowItem.listGlyph || "󰈉"
                          textFormat: Text.PlainText
                          color: listItem.listHasCursor ? root.selectedText : root.foreground
                          font.family: rowItem.listIconFont ? rowItem.listIconFont : root.fontFamily
                          font.pixelSize: root.listIconH
                        }
                      }

                      Text {
                        anchors.left: listIconSlot.right
                        anchors.leftMargin: Style.spacing.md
                        anchors.right: listKeysSlot.left
                        anchors.rightMargin: Style.spacing.md
                        anchors.verticalCenter: parent.verticalCenter
                        text: rowItem.listLabel
                        textFormat: Text.PlainText
                        color: listItem.listHasCursor ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideMiddle
                      }

                      Item {
                        id: listKeysSlot
                        visible: root.cfg.showChords && rowItem.listChordKeys.length > 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.cfg.showChords && rowItem.listChordKeys.length > 0 ? listKeysRow.implicitWidth : 0
                        height: root.keycapH

                        Row {
                          id: listKeysRow
                          spacing: root.keycapGap

                          Repeater {
                            model: rowItem.listChordKeys.length

                            delegate: Rectangle {
                              required property int index
                              readonly property string keyLabel: rowItem.listChordKeys[index]

                              height: root.keycapH
                              width: listKeyText.implicitWidth + root.keycapPadX * 2
                              radius: Math.min(root.cornerRadius, Style.space(4))
                              color: listItem.listHasCursor ? root.keycapFillCursor : root.keycapFill
                              border.color: listItem.listHasCursor ? root.keycapBorderCursor : root.keycapBorder
                              border.width: 1

                              Text {
                                id: listKeyText
                                anchors.centerIn: parent
                                text: keyLabel
                                textFormat: Text.PlainText
                                color: listItem.listHasCursor ? root.keycapTextCursor : root.keycapText
                                font.family: root.fontFamily
                                font.pixelSize: root.keycapFont
                                font.bold: true
                              }
                            }
                          }
                        }
                      }
                    }

                    MouseArea {
                      id: listMouseArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onContainsMouseChanged: if (containsMouse && rowItem.listAppIndex >= 0) {
                        root.cursorActive = true
                        root.cursorIndex = rowItem.listAppIndex
                      }
                      onClicked: {
                        if (rowItem.listAppIndex < 0) return
                        root.cursorIndex = rowItem.listAppIndex
                        keyCatcher.forceActiveFocus()
                        root.launchApp(rowItem.listAppIndex)
                      }
                    }
                  }

                  Rectangle {
                    visible: !root.isList && rowItem.startsCategory && rowItem.index > 0
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: Math.max(1, Style.space(1))
                    color: Util.alpha(root.accent, 0.35)
                  }
                }
              }
            }
          }

          Item {
            width: parent.width
            height: root.footerH

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              text: root.isList
                    ? "↑↓ mover   Tab categoría   Ctrl+Tab layout   ↵ abrir   Esc cerrar"
                    : "↑↓←→ mover   Tab categoría   Ctrl+Tab layout   ↵ abrir   Esc cerrar"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
