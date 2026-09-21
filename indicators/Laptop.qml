import QtQuick
import Quickshell.Io
import qs.Commons
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
  property bool probedLockOn: false
  property var fallbackActions: []

  active: svcAvailable ? (sleepService.lidOn === true) : probedOn
  readonly property bool lockOnLid: svcAvailable ? (sleepService.lockOnLid === true) : probedLockOn
  readonly property bool fallbackBusy: fallbackActionProc.running || fallbackActions.length > 0
  // FA laptop mono-glyph — with chassis, same height/centering as others
  activeText: ""
  inactiveText: ""
  activeTooltipText: lockOnLid
    ? "Working ON. Lock  ON. Right-click: switch lock off."
    : "Working ON. Lock  OFF. Right-click: switch lock on."
  inactiveTooltipText: lockOnLid
    ? "Working OFF. Lock  ON. Right-click: switch lock off."
    : "Working OFF. Lock  OFF. Right-click: switch lock on."
  // Keep the inactive slot interactive while the pointer remains over it.
  // A left-click can turn the indicator off under that same pointer.
  maintainIndicatorReveal: true

  function refreshTooltip() {
    Qt.callLater(function() {
      if (root.bar && root.tooltipHovered)
        root.bar.showTooltip(root, root.tooltipText)
    })
  }

  function toggle() {
    if (svcAvailable && typeof sleepService.toggleLid === "function") {
      sleepService.toggleLid()
      return
    }
    enqueueFallback("lid-toggle")
  }

  function setLock(desired) {
    var on = desired === true
    if (svcAvailable && typeof sleepService.setLock === "function") {
      sleepService.setLock(on)
      return
    }
    enqueueFallback(on ? "lock-on" : "lock-off")
  }

  function enqueueFallback(action) {
    fallbackActions = fallbackActions.concat([action])
    drainFallbackActions()
  }

  // The fallback owns one write process. This preserves the order of fast
  // left-click and lock changes even when Service.qml is temporarily absent.
  function drainFallbackActions() {
    if (fallbackActionProc.running || fallbackActions.length === 0) return

    var action = fallbackActions[0]
    if (svcAvailable) {
      fallbackActions = fallbackActions.slice(1)
      if (action === "lid-toggle" && typeof sleepService.toggleLid === "function")
        sleepService.toggleLid()
      else if (action === "lock-on" && typeof sleepService.setLock === "function")
        sleepService.setLock(true)
      else if (action === "lock-off" && typeof sleepService.setLock === "function")
        sleepService.setLock(false)
      else {
        fallbackActions = [action].concat(fallbackActions)
        return
      }
      Qt.callLater(drainFallbackActions)
      return
    }

    if (action === "lid-toggle") fallbackActionProc.command = [fallbackCli, "lid", "toggle"]
    else if (action === "lock-on") fallbackActionProc.command = [fallbackCli, "lock", "on"]
    else fallbackActionProc.command = [fallbackCli, "lock", "off"]
    fallbackActionProc.running = true
  }

  function refresh() {
    if (svcAvailable || statusProc.running || fallbackBusy) return
    statusProc.running = true
  }

  onActiveChanged: refreshTooltip()
  onLockOnLidChanged: refreshTooltip()
  onBarChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  Process {
    id: fallbackActionProc
    onExited: function(code) {
      var action = root.fallbackActions.length > 0 ? root.fallbackActions[0] : "unknown"
      if (root.fallbackActions.length > 0) root.fallbackActions = root.fallbackActions.slice(1)
      if (code !== 0) console.warn("Sleepwalker: fallback " + action + " failed with code", code)
      root.drainFallbackActions()
      Qt.callLater(function() {
        if (!root.fallbackBusy) {
          root.refresh()
          settle.restart()
        }
      })
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
          root.probedLockOn = data.lockOnLid === true
        } catch(e) {
          console.warn("Sleepwalker: fallback status unparsable")
          root.probedOn = false
          root.probedLockOn = false
        }
      }
    }
    onExited: function(code) {
      if (code !== 0) {
        console.warn("Sleepwalker: fallback status failed with code", code)
        root.probedOn = false
        root.probedLockOn = false
      }
    }
  }

  Timer { id: settle; interval: 300; repeat: false; onTriggered: root.refresh() }
  // Fallback poll only — the service path is push-based and needs none.
  Timer { interval: 30000; running: !root.svcAvailable; repeat: true; onTriggered: root.refresh() }

  onPressed: function(button) {
    if (button === Qt.RightButton) root.setLock(!root.lockOnLid)
    else if (button === Qt.LeftButton) root.toggle()
  }
}
