import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Gpu.js" as Gpu

// Compact VRAM readout in the bar + per-process VRAM breakdown & Game Mode panel.
// Left click: open panel. Right click: toggle Game / Godot Mode.
Panel {
  id: root
  moduleName: "cornerstone.gpu"
  ipcTarget: "cornerstone-gpu"
  manageIpc: false

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("cornerstone.gpu") : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.55)
  readonly property color hairline: Qt.darker(foreground, 2.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var palette: ({})
  readonly property color okColor: palette.color2 || Color.accent
  readonly property color warnColor: palette.color3 || "#FFB020"
  readonly property color badColor: Color.urgent

  FileView {
    id: paletteFile
    path: Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: {
      var found = {}
      var re = /^\s*([A-Za-z0-9_]+)\s*=\s*"(#[0-9A-Fa-f]{6,8})"/gm
      var m
      while ((m = re.exec(String(text()))) !== null) found[m[1]] = m[2]
      root.palette = found
    }
  }
  Connections {
    target: Color
    function onBackgroundChanged() { paletteFile.reload() }
    function onAccentChanged() { paletteFile.reload() }
  }

  readonly property string gpuName: service ? service.gpuName : ""
  readonly property bool unified: service ? service.unified : false
  readonly property bool hasLocalStt: service ? service.hasLocalStt : true
  readonly property real usedMb: service ? service.usedMb : 0
  readonly property real totalMb: service ? service.totalMb : 0
  readonly property int percent: service ? service.percent : 0
  readonly property int busyPct: service ? service.busyPct : 0
  readonly property real tempC: service ? service.tempC : 0
  readonly property bool qwenActive: service ? service.qwenActive : false
  readonly property bool whisperActive: service ? service.whisperActive : false
  readonly property bool gameMode: service ? service.gameMode : false
  readonly property var procs: service ? service.procs : []
  readonly property string severity: service ? service.severity : "normal"

  readonly property color levelColor: severity === "critical" ? badColor
    : (severity === "warn" ? warnColor : (gameMode ? okColor : foreground))

  readonly property string barTooltip: totalMb > 0
    ? (gpuName ? gpuName + " · " : "") + "VRAM " + Gpu.fmtMb(usedMb) + " / " + Gpu.fmtMb(totalMb) + " (" + percent + "%)"
      + (tempC > 0 ? " · " + Math.round(tempC) + "°C" : "")
      + (gameMode ? " · Game Mode ON" : "")
    : (gpuName || "GPU") + (gameMode ? " · Game Mode ON" : " · Unified memory")

  property bool watching: false
  property int cursor: -1
  readonly property var quickActions: {
    var list = [{ id: "gameMode", label: gameMode ? "Game / Godot Mode: ON (click to restore)" : (hasLocalStt ? "Game / Godot Mode (unload AI STT + pause LAN Mouse)" : "Game / Focus Mode (pause LAN Mouse)") }]
    if (hasLocalStt) {
      if (qwenActive || whisperActive)
        list.push({ id: "freeStt", label: "Unload local STT from GPU (frees ~4.2 GB)" })
      else
        list.push({ id: "restoreStt", label: "Start local STT GPU servers" })
    }
    return list
  }

  onOpenedChanged: {
    cursor = -1
    if (service) {
      if (opened && !watching) { watching = true; service.watchers++; service.refresh() }
      else if (!opened && watching) { watching = false; service.watchers = Math.max(0, service.watchers - 1) }
    }
  }
  Component.onDestruction: {
    if (watching && service) service.watchers = Math.max(0, service.watchers - 1)
  }

  function runQuick(id) {
    if (!service) return
    if (id === "gameMode") service.toggleGameMode()
    else if (id === "freeStt") service.freeDictationVram()
    else if (id === "restoreStt") service.restoreDictationVram()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 5
    fixedWidth: vertical ? -1 : pill.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: vertical ? Math.max(Style.bar.iconSlot, pill.implicitHeight + Style.space(6)) : -1
    tooltipText: root.opened ? "" : root.barTooltip
    onPressed: function(code) {
      if (code === Qt.RightButton && root.service) root.service.toggleGameMode()
      else root.toggle()
    }

    Row {
      id: pill
      anchors.centerIn: parent
      scale: button.pressScale
      spacing: Style.space(4)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.gameMode ? "󰊗" : (root.unified ? "GPU" : "VRAM")
        color: root.gameMode ? root.okColor : root.muted
        font.family: root.fontFamily
        font.pixelSize: root.gameMode ? Style.bar.iconFont : Style.font.caption
        font.bold: true
        renderType: Text.NativeRendering
      }
      Text {
        visible: !root.unified || root.totalMb > 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.totalMb > 0 ? (root.percent + "%") : "--"
        color: root.levelColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.severity !== "normal" || root.gameMode
        font.features: { "tnum": 1 }
        renderType: Text.NativeRendering
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(350))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(560))

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy === 0 || root.quickActions.length === 0) return
        var n = root.quickActions.length
        root.cursor = root.cursor < 0 ? (dy > 0 ? 0 : n - 1) : (root.cursor + dy + n) % n
      }
      onActivateRequested: {
        if (root.cursor >= 0 && root.cursor < root.quickActions.length)
          root.runQuick(root.quickActions[root.cursor].id)
      }
      onTextKey: function(t) {
        if (!root.service) return
        if (t === "g" || t === "G") root.service.toggleGameMode()
        else if (t === "r" || t === "R") root.service.refresh()
      }
      clip: true

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        // Header + VRAM bar
        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            height: headTitle.implicitHeight
            Text {
              id: headTitle
              anchors.left: parent.left
              textFormat: Text.PlainText
              text: (root.gpuName || "GPU VRAM") + (root.tempC > 0 ? "  ·  " + Math.round(root.tempC) + "°C" : "")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: headTitle.verticalCenter
              textFormat: Text.PlainText
              text: root.totalMb > 0
                ? (Gpu.fmtMb(root.usedMb) + " / " + Gpu.fmtMb(root.totalMb) + " (" + root.percent + "%)")
                : "Unified memory"
              color: root.levelColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.features: { "tnum": 1 }
            }
          }

          Rectangle {
            visible: root.totalMb > 0
            width: parent.width
            height: Style.space(10)
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            Rectangle {
              width: Math.max(root.percent > 0 ? height : 0, parent.width * Math.min(1, root.percent / 100))
              height: parent.height
              radius: height / 2
              color: root.severity === "critical" ? root.badColor : (root.severity === "warn" ? root.warnColor : Color.accent)
              Behavior on width { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
            }
          }
        }

        // Quick actions
        Column {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.quickActions
            Rectangle {
              required property var modelData
              required property int index
              readonly property bool focused: root.cursor === index
              readonly property bool activeMode: modelData.id === "gameMode" && root.gameMode
              width: parent.width
              height: Style.space(30)
              radius: Style.space(6)
              color: activeMode
                ? Util.alpha(root.okColor, rowArea.containsMouse || focused ? 0.34 : 0.24)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, rowArea.containsMouse || focused ? 0.2 : 0.11)
              border.width: focused ? 1 : 0
              border.color: Color.accent
              Behavior on color { ColorAnimation { duration: Style.duration(120) } }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                width: parent.width - Style.space(20)
                textFormat: Text.PlainText
                text: modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: activeMode
                elide: Text.ElideRight
              }
              MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.cursor = index
                onClicked: root.runQuick(modelData.id)
              }
            }
          }
        }

        Rectangle { visible: root.totalMb > 0; width: parent.width; height: 1; color: root.hairline }

        Text {
          visible: root.totalMb > 0
          textFormat: Text.PlainText
          text: "Top VRAM holders (tap service/app to unload)"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Column {
          visible: root.totalMb > 0
          width: parent.width
          spacing: Style.space(5)

          Text {
            visible: root.procs.length === 0
            textFormat: Text.PlainText
            text: "No heavy GPU processes detected"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.procs.slice(0, 7)
            Rectangle {
              required property var modelData
              readonly property bool protectedProc: /^(Hyprland|quickshell|omarchy-shell)$/i.test(String(modelData.comm || ""))
              width: parent.width
              height: Style.space(28)
              radius: Style.space(6)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                             !protectedProc && pArea.containsMouse ? 0.14 : 0.05)
              Behavior on color { ColorAnimation { duration: Style.duration(120) } }

              // Subtle fill bar showing share of total VRAM
              Rectangle {
                height: parent.height
                width: root.totalMb > 0 ? Math.min(parent.width, parent.width * (modelData.vramMb / root.totalMb)) : 0
                radius: parent.radius
                color: Util.alpha(modelData.unit ? root.warnColor : Color.accent, 0.16)
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: vramText.left
                anchors.rightMargin: Style.space(8)
                textFormat: Text.PlainText
                text: modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Text {
                id: vramText
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                textFormat: Text.PlainText
                text: !protectedProc && pArea.containsMouse
                  ? (modelData.unit ? "stop" : "close")
                  : Gpu.fmtMb(modelData.vramMb)
                color: !protectedProc && pArea.containsMouse ? root.badColor : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.features: { "tnum": 1 }
              }

              MouseArea {
                id: pArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: !protectedProc
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (root.service) root.service.terminateProc(modelData)
              }
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Right-click VRAM = toggle Game Mode · g Game Mode · r refresh"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
