import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Lid — bar widget left of the clock.
//
// One icon on the bar, one panel on tap.
// Owns no state: every question goes to `omarchy-lid status --json`.
//
// lid on  = systemd-inhibit handle-lid-switch (no suspend) + Hyprland
//          clamshell disables eDP-1, optional lock (off by default).
// lid off = stock: lid close → suspend-then-hibernate (+ lock if no dock).
Panel {
  id: root

  moduleName: "io.github.tymurbogach.lid"
  manageIpc: false

  readonly property string cli: "omarchy-lid"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // --- CLI state --------------------------------------------------------

  property var state: ({})
  property bool asked: false

  readonly property bool lidOn: state.active === true
  readonly property bool inhibitOn: state.inhibitActive === true
  readonly property bool lockOnLid: state.lockOnLid === true

  readonly property string summary: {
    if (!asked) return "…"
    if (lidOn) return lockOnLid ? "lid ignore + lock" : "lid ignore"
    return "normal — lid suspends"
  }

  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property int itemCount: 4 // 2 toggles + Repair + Uninstall

  function moveCursor(dx, dy) {
    var step = dy !== 0 ? dy : dx
    cursorIndex = (cursorIndex + step + itemCount) % itemCount
  }

  function activateCursor() {
    if (cursorIndex === 0) toggleLid()
    else if (cursorIndex === 1) toggleLock()
    else if (cursorIndex === 2) repair()
    else uninstall()
  }

  // --- actions -----------------------------------------------------------

  function run(command) {
    if (bar) bar.run(command)
  }

  function runVisibly(command) {
    run("omarchy-launch-floating-terminal-with-presentation '" + command + "'")
  }

  function toggleLid() {
    run(cli + " lid toggle")
    settle.restart()
  }

  function toggleLock() {
    run(cli + " lock toggle")
    settle.restart()
  }

  function repair() {
    runVisibly(cli + " doctor")
    root.close()
  }

  function uninstall() {
    runVisibly(cli + "-uninstall")
    root.close()
  }

  function refresh() {
    if (!status.running) status.running = true
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      refresh()
    }
  }

  Component.onCompleted: refresh()

  Process {
    id: status
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.state = JSON.parse(text || "{}")
        } catch (e) {
          root.state = ({})
        }
        root.asked = true
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.state = ({})
        root.asked = true
      }
    }
  }

  Timer {
    id: settle
    interval: 1100
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    running: root.opened
    interval: 3000
    repeat: true
    onTriggered: root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // portátil abierto — 󰍹 + base fina
    text: "󰍹"
    tooltipText: "Lid — " + root.summary
    foreground: root.lidOn
      ? (root.bar ? root.bar.barForeground : Color.foreground)
      : Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.55)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.repair()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Lid"
          meta: root.summary
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.lidOn ? 1.0 : 0.5
          iconComponent: Component {
            Text {
              text: root.lidOn ? "󰍹" : "󰋊"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Text {
          width: parent.width
          text: "Cerrar la tapa solo apaga el panel. La máquina sigue trabajando — sin suspender, sin hibernar."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Toggle {
          width: column.width
          label: "Lid Ignore"
          description: "Tapa cerrada sigue trabajando, pantalla off"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          checked: root.lidOn
          hasCursor: root.cursorActive && root.cursorIndex === 0
          onHovered: function(isHovered) {
            if (isHovered) { root.cursorActive = true; root.cursorIndex = 0 }
          }
          onClicked: {
            root.cursorActive = true
            root.cursorIndex = 0
            root.toggleLid()
          }
        }

        Toggle {
          width: column.width
          label: "Lock on lid"
          description: "Bloquear al cerrar (con Lid Ignore activo)"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          checked: root.lockOnLid
          hasCursor: root.cursorActive && root.cursorIndex === 1
          onHovered: function(isHovered) {
            if (isHovered) { root.cursorActive = true; root.cursorIndex = 1 }
          }
          onClicked: {
            root.cursorActive = true
            root.cursorIndex = 1
            root.toggleLock()
          }
        }

        PanelSeparator { width: parent.width }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: "Repair"
            iconText: "󰗠"
            tooltipText: "Reconcilia servicio vs toggle (doctor)"
            bordered: true
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.cursorIndex === 2
            onHovered: function(isHovered) {
              if (isHovered) { root.cursorActive = true; root.cursorIndex = 2 }
            }
            onClicked: root.repair()
          }

          Button {
            text: "Uninstall"
            iconText: "󰩹"
            tooltipText: "Quita el plugin y el inhibitor"
            bordered: true
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.cursorIndex === 3
            onHovered: function(isHovered) {
              if (isHovered) { root.cursorActive = true; root.cursorIndex = 3 }
            }
            onClicked: root.uninstall()
          }
        }

        Text {
          id: inhibitStatus
          width: parent.width
          property string statusText: {
            if (!root.asked) return ""
            if (root.lidOn && !root.inhibitOn) return "⚠ toggle on pero inhibitor inactivo — pulsa Repair"
            if (!root.lidOn && root.inhibitOn) return "⚠ inhibitor activo pero toggle off — pulsa Repair"
            if (root.lidOn) return "inhibitor activo (handle-lid-switch)"
            return ""
          }
          text: statusText
          visible: statusText !== ""
          color: root.lidOn && !root.inhibitOn ? Color.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
