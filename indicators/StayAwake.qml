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

  // Called by PopupCard on outside-click dismissal. Flipping the source
  // property keeps the open binding intact (assigning popup.open directly
  // would break it and the menu would never reopen).
  function close() {
    root.rainMenuOpen = false
  }

  function refreshRain() {
    console.log("Sleepwalker: rain menu opened, cli:", root.rainCli)
    if (!rainProc.running) rainProc.running = true
  }

  function useRain(which) {
    console.log("Sleepwalker: rain row clicked:", which)
    root.rainMenuOpen = false
    if (which === "gpu") {
      if (!useGpuProc.running) useGpuProc.running = true
    } else {
      if (!useTtfxProc.running) useTtfxProc.running = true
    }
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
    id: useGpuProc
    command: [root.rainCli, "use-gpu"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: console.log("Sleepwalker: rain switch out:", String(text || "").trim().slice(-200))
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: console.warn("Sleepwalker: rain switch err:", String(text || "").trim().slice(-200))
    }
    onExited: function(code) {
      console.log("Sleepwalker: rain switch exited:", code)
      root.refreshRain()
    }
  }

  Process {
    id: useTtfxProc
    command: [root.rainCli, "use-ttfx"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: console.log("Sleepwalker: rain switch out:", String(text || "").trim().slice(-200))
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: console.warn("Sleepwalker: rain switch err:", String(text || "").trim().slice(-200))
    }
    onExited: function(code) {
      console.log("Sleepwalker: rain switch exited:", code)
      root.refreshRain()
    }
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

      Item {
        id: ttfxRow
        width: parent.width
        height: Math.max(ttfxText.implicitHeight, Style.space(24))

        Text {
          id: ttfxText
          anchors.verticalCenter: parent.verticalCenter
          text: (root.rainMode === "ttfx" ? "● " : "○ ") + "ttfx — terminal"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.useRain("ttfx")
        }
      }

      Item {
        id: gpuRow
        width: parent.width
        height: Math.max(gpuText.implicitHeight, Style.space(24))

        Text {
          id: gpuText
          anchors.verticalCenter: parent.verticalCenter
          text: (root.rainMode === "gpu" ? "● " : "○ ") + "Enter the Matrix — GPU"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.useRain("gpu")
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
