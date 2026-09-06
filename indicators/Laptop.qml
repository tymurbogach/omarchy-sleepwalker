import QtQuick
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property bool laptopOn: false

  active: laptopOn
  // FA laptop mono-glyph  — with chassis, same height/centering as others
  activeText: ""
  inactiveText: ""
  activeTooltipText: "Laptop ON — lid closed keeps working (click to turn off)"
  inactiveTooltipText: "Laptop OFF — lid suspends (click to turn on)"

  function refresh() {
    if (statusProc.running) return
    statusProc.running = true
  }

  property bool debouncing: false
  property bool pendingToggle: false

  function toggle() {
    if (toggleProc.running || statusProc.running) {
      pendingToggle = true
      return
    }
    if (debouncing) {
      pendingToggle = true
      return
    }
    debouncing = true
    debounce.restart()
    // optimistic flip — hover does not wait for statusProc
    laptopOn = !laptopOn
    toggleProc.running = true
  }

  Timer {
    id: debounce
    interval: 600
    repeat: false
    onTriggered: {
      root.debouncing = false
      if (root.pendingToggle) {
        root.pendingToggle = false
        root.toggle()
      }
    }
  }

  onBarChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  Process {
    id: toggleProc
    command: ["omarchy-sleepwalker", "lid", "toggle"]
    onExited: function(code) {
      // does not overwrite optimistic flip, only reconciles if systemd failed
      root.refresh()
      settle.restart()
      if (root.pendingToggle) {
        root.pendingToggle = false
        // let debounce trigger the next toggle
      }
    }
  }

  Process {
    id: statusProc
    command: ["omarchy-sleepwalker", "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "{}")
          var actual = data.active === true
          if (!debouncing && !toggleProc.running) root.laptopOn = actual
        } catch(e) {
          if (!debouncing && !toggleProc.running) root.laptopOn = false
        }
      }
    }
    onExited: function(code) {
      if (code !== 0 && !debouncing && !toggleProc.running) root.laptopOn = false
    }
  }

  Timer { id: settle; interval: 300; repeat: false; onTriggered: root.refresh() }
  Timer { interval: 5000; running: root.indicatorHost && root.indicatorHost.visible; repeat: true; onTriggered: root.refresh() }

  onPressed: function() { root.toggle() }
}
