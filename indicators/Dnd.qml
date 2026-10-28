import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property var notificationService: bar && bar.shell ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false
  property bool crashAlertsOff: false
  property bool crashStateLoaded: false
  property bool crashControlAvailable: false
  property bool refreshPending: false

  function refreshCrashState() {
    if (crashProbe.running) refreshPending = true
    else crashProbe.running = true
  }

  function refreshTooltip() {
    Qt.callLater(function() {
      if (root.bar && root.tooltipHovered) root.bar.showTooltip(root, root.tooltipText)
    })
  }

  readonly property string crashAction: !crashControlAvailable ? "Install Notification Controls for crash alerts"
    : !crashStateLoaded ? "Toggle crash alerts"
    : crashAlertsOff ? "Enable crash alerts" : "Disable crash alerts"

  active: dnd
  activeText: "󰂛"
  inactiveText: "󰂛"
  activeTooltipText: "Left-click: allow notifications · Right-click: " + crashAction
  inactiveTooltipText: "Left-click: silence notifications · Right-click: " + crashAction
  maintainIndicatorReveal: true

  Component.onCompleted: {
    serviceProbe.running = true
  }
  onCrashAlertsOffChanged: refreshTooltip()
  onCrashControlAvailableChanged: {
    refreshTooltip()
    if (crashControlAvailable) refreshCrashState()
  }
  onDndChanged: refreshTooltip()

  Process {
    id: serviceProbe
    command: ["omarchy-shell", "crash-alerts", "status"]
    stdout: SplitParser {
      onRead: function(line) { root.crashControlAvailable = String(line).trim() === "ready" }
    }
    onExited: function(code) {
      if (code !== 0) root.crashControlAvailable = false
    }
  }

  Process {
    id: crashProbe
    command: ["bash", "-c", "test -f \"$HOME/.local/state/omarchy/toggles/crash-capture-off\" && echo off || echo on"]
    stdout: SplitParser {
      onRead: function(line) { root.crashAlertsOff = String(line).trim() === "off" }
    }
    onExited: {
      root.crashStateLoaded = true
      if (root.refreshPending) {
        root.refreshPending = false
        root.refreshCrashState()
      }
    }
  }

  Process {
    id: crashToggle
    command: ["omarchy-shell", "crash-alerts", "toggle"]
    onExited: function(code) {
      if (code !== 0) {
        root.crashControlAvailable = false
        console.warn("Sleepwalker: Notification Controls is unavailable")
      }
      root.refreshCrashState()
    }
  }

  FileView {
    path: root.crashControlAvailable ? Quickshell.env("HOME") + "/.local/state/omarchy/toggles" : ""
    watchChanges: root.crashControlAvailable
    printErrors: false
    onFileChanged: root.refreshCrashState()
  }

  onPressed: function(button) {
    if (button === Qt.RightButton && root.crashControlAvailable && !crashToggle.running) {
      crashToggle.running = true
    } else if (button === Qt.RightButton && !serviceProbe.running) {
      serviceProbe.running = true
    } else if (button === Qt.LeftButton && root.notificationService) {
      root.notificationService.setDoNotDisturb(!root.notificationService.doNotDisturb)
    }
  }
}
