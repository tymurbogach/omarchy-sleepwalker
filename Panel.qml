import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Sleepwalker — bar widget left of the clock.
// No large panel — bar icon only.
// Left click toggles lid ignore, right click refreshes status.
Panel {
  id: root

  moduleName: "io.github.tymurbogach.sleepwalker"
  manageIpc: false

  readonly property string cli: "omarchy-sleepwalker"

  property var state: ({})
  property bool asked: false

  readonly property bool lidOn: state.active === true
  readonly property bool lockOnLid: state.lockOnLid === true

  readonly property string summary: {
    if (!asked) return "…"
    if (lidOn) return lockOnLid ? "lid ignore + lock" : "lid ignore"
    return "normal — lid suspends"
  }

  function run(command) {
    if (bar) bar.run(command)
  }

  function toggleLid() {
    run(cli + " lid toggle")
    settle.restart()
  }

  function refresh() {
    if (!status.running) status.running = true
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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: "Sleepwalker — " + root.summary
    foreground: root.lidOn
      ? (root.bar ? root.bar.barForeground : Color.foreground)
      : Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.55)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggleLid()
    }
  }
}
