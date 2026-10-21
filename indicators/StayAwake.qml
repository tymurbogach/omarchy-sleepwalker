import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property var idleService: bar?.shell?.firstPartyServiceFor("omarchy.idle")

  // Rain switcher bundled in this plugin, resolved relative to this file.
  readonly property string rainCli: decodeURIComponent(String(Qt.resolvedUrl("../bin/omarchy-rain-mode")).replace(/^file:\/\//, ""))

  property string rainMode: ""
  property bool rainMenuOpen: false

  active: idleService ? idleService.stayAwake : false
  activeText: "󰅶"
  inactiveText: "󰅶"
  activeTooltipText: "Allow Idle Lock & Screensaver. Right-click: Matrix rain."
  inactiveTooltipText: "Stay Awake. Right-click: Matrix rain."

  function toggle() {
    if (root.idleService) root.idleService.setIdleEnabled(root.active)
  }

  function refreshRain() {
    if (!rainProc.running) rainProc.running = true
  }

  function useRain(which) {
    root.rainMenuOpen = false
    switchProc.command = [root.rainCli, which]
    switchProc.running = true
  }

  Process {
    id: rainProc
    command: [root.rainCli, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var mode = String(text || "").trim()
        root.rainMode = (mode === "gpu" || mode === "ttfx") ? mode : ""
      }
    }
    onExited: function(code) {
      if (code !== 0) root.rainMode = ""
    }
  }

  Process {
    id: switchProc
  }

  onPressed: function(button) {
    if (button === Qt.RightButton) {
      root.rainMenuOpen = !root.rainMenuOpen
      if (root.rainMenuOpen) root.refreshRain()
    } else if (button === Qt.LeftButton) {
      root.toggle()
    }
  }

  PopupCard {
    id: rainMenu
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.rainMenuOpen
    contentWidth: rainMenu.fittedContentWidth(Style.space(280))
    contentHeight: rainMenu.fittedContentHeight(menuColumn.implicitHeight)

    Column {
      id: menuColumn
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: "Matrix rain"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Repeater {
        model: [
          { "id": "ttfx", "label": "ttfx — terminal" },
          { "id": "gpu", "label": "Enter the Matrix — GPU" }
        ]

        Item {
          id: rowRoot
          property var modelData
          width: parent.width
          height: Math.max(rowText.implicitHeight, Style.space(24))

          Text {
            id: rowText
            anchors.verticalCenter: parent.verticalCenter
            text: (root.rainMode === rowRoot.modelData.id ? "● " : "○ ") + rowRoot.modelData.label
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.useRain(rowRoot.modelData.id)
          }
        }
      }

      Text {
        visible: root.rainMode === ""
        text: "Reading current rain…"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
