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

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: root.home + "/.config/omarchy/plugins/jose.launcherplease"
  readonly property string listPath: root.pluginDir + "/list.sh"
  readonly property string recordPath: root.pluginDir + "/record.sh"
  readonly property string setLayoutPath: root.pluginDir + "/set-layout.sh"
  readonly property string usagePath: root.home + "/.local/state/omarchy/launcherplease/usage.json"

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color borderColor: Color.menu.border
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color accent: Color.accent
  property var borderSpec: Border.surfaceSpec("menu", "border", root.borderColor, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  property int columns: 8
  readonly property int cellH: Style.space(92)
  readonly property int headerH: Math.max(Style.space(22), Style.font.subtitle + Style.spacing.xs)
  readonly property int footerH: Math.max(Style.space(20), Style.font.caption + Style.spacing.sm)
  readonly property int contentMargin: Style.spacing.md
  readonly property int gridGap: Style.spacing.xs
  readonly property int iconH: Style.space(28)
  readonly property int keycapH: Style.space(16)
  readonly property int keycapFont: Style.font.caption - 1
  readonly property real keycapCharW: (Style.font.caption - 1) * 0.6
  readonly property int keycapPadX: Style.space(3)
  readonly property int keycapGap: Style.space(3)

  function iconUrl(icon) {
    var value = String(icon || "")
    if (!value) return ""
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    return themed && themed.length ? themed : ""
  }

  function applyConfig() {
    root.cfg = LauncherConfig.merge(root.fileConfigRaw, root.payloadConfigRaw)
    root.columns = Math.max(1, root.cfg.columns)
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
    root.layout = GridLayout.build(root.apps, root.columns, root.cfg.layout)

    if (!root.layout.count) root.cursorIndex = 0
    else if (root.cursorIndex >= root.layout.count) root.cursorIndex = root.layout.count - 1
    else if (root.cursorIndex < 0) root.cursorIndex = 0

    var height = 0
    var rows = root.layout.rows || []
    for (var r = 0; r < rows.length; r++) {
      height += rows[r].type === "banner" ? root.headerH : root.cellH
      if (r > 0) height += Style.spacing.xs
    }
    root.gridHeight = height
  }

  function onListLoaded(raw) {
    try { root.rawApps = JSON.parse(String(raw || "[]")) } catch (e) { root.rawApps = [] }
    root.rebuild()
    if (root.opened) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function refreshList() {
    listProc.running = false
    listProc.running = true
  }

  function setFilter(text) {
    root.filterText = text
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
    var next = root.cfg.layout === "roomy" ? "compact" : "roomy"
    root.cfg.layout = next
    root.rebuild()
    setLayoutProc.command = ["bash", root.setLayoutPath, next]
    setLayoutProc.running = false
    setLayoutProc.running = true
  }

  function scrollToCursor() {
    var row = GridLayout.rowOf(root.layout, root.cursorIndex)
    if (row < 0 || !flick) return
    var y = 0
    var rows = root.layout.rows || []
    for (var i = 0; i < row && i < rows.length; i++) {
      y += rows[i].type === "banner" ? root.headerH : root.cellH
      y += Style.spacing.xs
    }
    var rowH = (rows[row] && rows[row].type === "banner") ? root.headerH : root.cellH
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
    recordProc.command = ["bash", root.recordPath, id, String(root.cfg.mostUsedDays)]
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

  function luaCmdLiteral(command) {
    return String(command || "").replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  }

  function chordCaptureScript(bind) {
    var lines = []
    var apps = LauncherModel.normalizeApps(root.rawApps)
    var seen = {}
    if (bind) {
      for (var i = 0; i < apps.length; i++) {
        var chord = apps[i].chord
        if (!chord || seen[chord]) continue
        seen[chord] = true
        lines.push('hyprctl eval \'hl.unbind("' + chord + '")\'')
        lines.push('hyprctl eval \'hl.bind("' + chord + '", hl.dsp.exec_cmd("omarchy-shell launcherplease launch ' + apps[i].id + '"), { description = "' + apps[i].label + '" })\'')
      }
      lines.push('hyprctl eval \'hl.unbind("ESCAPE")\'')
      lines.push('hyprctl eval \'hl.bind("ESCAPE", hl.dsp.exec_cmd("omarchy-shell launcherplease close"), { description = "LauncherPlease close" })\'')
    } else {
      for (var j = 0; j < apps.length; j++) {
        var chord2 = apps[j].chord
        if (!chord2 || seen[chord2]) continue
        seen[chord2] = true
        lines.push('hyprctl eval \'hl.unbind("' + chord2 + '")\'')
        lines.push('hyprctl eval \'hl.bind("' + chord2 + '", hl.dsp.exec_cmd("' + root.luaCmdLiteral(apps[j].command) + '"), { description = "' + apps[j].label + '" })\'')
      }
      lines.push('hyprctl eval \'hl.unbind("ESCAPE")\'')
    }
    return lines.join("\n")
  }

  function startChordCapture() {
    if (!root.cfg.captureChords) return
    root.chordsCaptured = true
    chordProc.command = ["bash", "-c", root.chordCaptureScript(true)]
    chordProc.running = false
    chordProc.running = true
  }

  function stopChordCapture() {
    if (!root.chordsCaptured) return
    root.chordsCaptured = false
    chordProc.command = ["bash", "-c", root.chordCaptureScript(false)]
    chordProc.running = false
    chordProc.running = true
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

  FileView {
    path: root.home + "/.config/omarchy/launcherplease.json"
    watchChanges: true
    printErrors: false
    onLoaded: { root.fileConfigRaw = text() || "{}"; root.applyConfig(); root.rebuild() }
    onFileChanged: reload()
    onLoadFailed: { root.fileConfigRaw = "{}"; root.applyConfig(); root.rebuild() }
  }

  FileView {
    path: root.usagePath
    watchChanges: true
    printErrors: false
    onLoaded: { root.usageRaw = text() || "{}"; if (root.rawApps.length) root.rebuild() }
    onFileChanged: reload()
    onLoadFailed: root.usageRaw = "{}"
  }

  Process {
    id: listProc
    command: ["bash", root.listPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onListLoaded(text)
    }
  }

  Process { id: chordProc }
  Process { id: recordProc }
  Process { id: setLayoutProc }

  Timer { id: autoCloseTimer; repeat: false; onTriggered: root.beginFade() }
  Timer { id: fadeCloseTimer; interval: root.fadeMs; repeat: false; onTriggered: root.close() }
  Timer { id: bounceClearTimer; interval: 460; repeat: false; onTriggered: root.bounceIndex = -1 }

  Component.onCompleted: {
    root.applyConfig()
    root.refreshList()
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
        width: Math.min(panel.width * 0.75, panel.width - Style.gapsOut * 4)
        height: Math.min(root.headerH + root.footerH + root.gridHeight + root.contentMargin * 2 + Style.spacing.sm * 2,
                         panel.height - Style.gapsOut * 2)
        anchors.centerIn: parent
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

          Item {
            width: parent.width
            height: root.headerH

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.filterText ? root.filterText : "Shortcut apps"
              color: root.foreground
              opacity: root.filterText ? 1 : 0.72
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
            }
          }

          Flickable {
            id: flick
            width: parent.width
            height: parent.height - root.headerH - root.footerH - Style.spacing.sm
            clip: true
            contentWidth: width
            contentHeight: gridCol.height
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

                  width: gridCol.width
                  height: isBanner ? root.headerH : root.cellH
                  clip: true

                  Text {
                    visible: rowItem.isBanner
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: root.cfg.showCategories && rowObj ? (rowObj.label + " · " + rowObj.count) : ""
                    color: root.accent
                    opacity: 0.85
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Row {
                    visible: !rowItem.isBanner
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
                                      radius: Style.space(4)
                                      color: cell.hasCursor ? Util.alpha(root.selectedText, 0.18) : Util.alpha(root.foreground, 0.08)
                                      border.color: cell.hasCursor ? Util.alpha(root.selectedText, 0.45) : "transparent"
                                      border.width: 1

                                      Text {
                                        id: keyText
                                        anchors.centerIn: parent
                                        text: keyLabel
                                        color: cell.hasCursor ? root.selectedText : root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: root.keycapFont
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

                  Rectangle {
                    visible: rowItem.startsCategory && rowItem.index > 0
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
              text: "↑↓←→ mover   Tab categoría   Ctrl+Tab layout   ↵ abrir   Esc cerrar"
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
