import QtQuick
import Quickshell.Io
import qs.Ui

// Sleepwalker indicator — lives inside this plugin's Indicators clone, so it
// renders at the same 21px slot / 10pt caption size as Dictation, StayAwake…
BarIndicator {
  id: root

  // Live service owned by this same plugin (Service.qml). The bar facade
  // allows a widget its own service id, so this is reactive: no polling.
  // The lookup itself is guarded: a throwing serviceFor must degrade to
  // the CLI fallback, never break property evaluation.
  readonly property var sleepService: {
    try {
      if (bar && bar.shell && typeof bar.shell.serviceFor === "function")
        return bar.shell.serviceFor("io.github.tymurbogach.sleepwalker")
    } catch (e) { console.warn("Sleepwalker: serviceFor failed, using CLI fallback:", e) }
    return null
  }
  readonly property bool svcAvailable: sleepService !== null && sleepService !== undefined

  // Fallback when the service is unreachable (never on a healthy install):
  // the CLI bundled in this plugin, resolved relative to this file — never
  // looked up on PATH, because `omarchy plugin add` runs no install hook.
  readonly property string fallbackCli: decodeURIComponent(String(Qt.resolvedUrl("../bin/omarchy-sleepwalker")).replace(/^file:\/\//, ""))

  property bool probedOn: false

  active: svcAvailable ? (sleepService.lidOn === true) : probedOn
  // FA laptop mono-glyph — with chassis, same height/centering as others
  activeText: ""
  inactiveText: ""
  activeTooltipText: "Laptop ON — lid closed keeps working (click to turn off)"
  inactiveTooltipText: "Laptop OFF — lid suspends (click to turn on)"

  function toggle() {
    if (svcAvailable && typeof sleepService.toggleLid === "function") {
      sleepService.toggleLid()
      return
    }
    if (toggleProc.running || statusProc.running) {
      pendingToggles++
      return
    }
    toggleProc.running = true
  }

  function refresh() {
    if (svcAvailable) return
    if (statusProc.running) return
    statusProc.running = true
  }

  property int pendingToggles: 0

  onBarChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  Process {
    id: toggleProc
    command: [root.fallbackCli, "lid", "toggle"]
    onExited: function(code) {
      if (code !== 0) console.warn("Sleepwalker: fallback toggle failed with code", code)
      root.refresh()
      settle.restart()
      // Clicks queue as a counter because each is a flip: an odd remainder
      // means one net toggle is still owed. Route it through the service if
      // it appeared mid-flight, else re-run the fallback when free.
      var owed = root.pendingToggles % 2
      root.pendingToggles = 0
      if (owed === 1) {
        if (root.svcAvailable && typeof root.sleepService.toggleLid === "function") {
          root.sleepService.toggleLid()
        } else if (!root.toggleProc.running && !root.statusProc.running) {
          root.toggle()
        } else {
          root.pendingToggles = 1
        }
      }
    }
  }

  Process {
    id: statusProc
    command: [root.fallbackCli, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "{}")
          root.probedOn = data.active === true
        } catch(e) {
          console.warn("Sleepwalker: fallback status unparsable")
          root.probedOn = false
        }
      }
    }
    onExited: function(code) {
      if (code !== 0) {
        console.warn("Sleepwalker: fallback status failed with code", code)
        root.probedOn = false
      }
    }
  }

  Timer { id: settle; interval: 300; repeat: false; onTriggered: root.refresh() }
  // Fallback poll only — the service path is push-based and needs none.
  Timer { interval: 30000; running: !root.svcAvailable; repeat: true; onTriggered: root.refresh() }

  onPressed: function() { root.toggle() }
}
