import QtQuick
import Quickshell
import Quickshell.Io

// Sleepwalker service — owns the lid-close inhibitor and the toggle state.
//
// Single source of truth is two files under ~/.local/state/omarchy/toggles/:
//   sleepwalker  presence = keep working with the lid closed (preferred)
//   lid-ignore   presence = same, legacy name (read, never written)
//   lid-lock     presence = additionally lock on lid close (opt-in)
//
// The inhibitor is a child `systemd-inhibit … sleep infinity` held while the
// toggle is on — no systemd unit, no install step. `omarchy plugin add` alone
// is a working install. The bar indicator (indicators/Laptop.qml, same plugin)
// binds to lidOn/lockOnLid reactively; the bundled CLI edits the same files
// for terminal use, so all three always agree.

Item {
  id: root
  visible: false

  // Injected by omarchy-shell for every service plugin.
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string togglesDir: home + "/.local/state/omarchy/toggles"
  readonly property string lidToggle: togglesDir + "/sleepwalker"
  readonly property string lidToggleLegacy: togglesDir + "/lid-ignore"
  readonly property string lockToggle: togglesDir + "/lid-lock"

  property bool lidOn: false
  property bool lockOnLid: false
  property bool stateLoaded: false

  function shQuote(path) {
    return "'" + String(path).split("'").join("'\"'\"'") + "'"
  }

  function refresh() {
    if (probe.running) {
      pendingRefresh = true
      return
    }
    probe.running = true
  }
  property bool pendingRefresh: false

  // Writer is serial: a second toggle while one is in flight waits its turn
  // instead of racing two bash invocations over the same files.
  property bool writerBusy: false
  property string pendingWrite: ""

  function runWrite(command) {
    if (writerBusy) {
      pendingWrite = command
      return
    }
    writerBusy = true
    writer.command = ["bash", "-c", command]
    writer.running = true
  }

  function setLid(desired) {
    var on = desired === true
    // Optimistic: the indicator flips without waiting for disk.
    lidOn = on
    var cmd = "mkdir -p " + shQuote(root.togglesDir) + "; "
    if (on) cmd += "touch " + shQuote(root.lidToggle) + "; rm -f " + shQuote(root.lidToggleLegacy)
    else cmd += "rm -f " + shQuote(root.lidToggle) + " " + shQuote(root.lidToggleLegacy)
    runWrite(cmd)
  }

  function toggleLid() {
    setLid(!(lidOn === true))
  }

  function setLock(desired) {
    var on = desired === true
    lockOnLid = on
    var cmd = "mkdir -p " + shQuote(root.togglesDir) + "; "
    cmd += on ? "touch " + shQuote(root.lockToggle) : "rm -f " + shQuote(root.lockToggle)
    runWrite(cmd)
  }

  function statusJson() {
    return JSON.stringify({
      active: lidOn === true,
      inhibitActive: inhibitProc.running === true,
      lockOnLid: lockOnLid === true
    })
  }

  Component.onCompleted: refresh()

  Process {
    id: probe
    command: ["bash", "-c",
      "if [[ -f " + root.shQuote(root.lidToggle) + " || -f " + root.shQuote(root.lidToggleLegacy) + " ]]; then echo lid=on; else echo lid=off; fi; "
      + "if [[ -f " + root.shQuote(root.lockToggle) + " ]]; then echo lock=on; else echo lock=off; fi"]
    stdout: SplitParser {
      onRead: function(line) {
        var text = String(line).trim()
        if (text === "lid=on") root.lidOn = true
        else if (text === "lid=off") { if (!root.writerBusy) root.lidOn = false }
        else if (text === "lock=on") root.lockOnLid = true
        else if (text === "lock=off") { if (!root.writerBusy) root.lockOnLid = false }
      }
    }
    onExited: function() {
      root.stateLoaded = true
      if (root.pendingRefresh) {
        root.pendingRefresh = false
        root.refresh()
      }
    }
  }

  Process {
    id: writer
    onExited: function() {
      root.writerBusy = false
      if (root.pendingWrite !== "") {
        var next = root.pendingWrite
        root.pendingWrite = ""
        root.runWrite(next)
      } else {
        root.refresh()
      }
    }
  }

  // The inhibitor itself. Held exactly while the toggle is on; released the
  // moment it flips off or this service unloads (disable/remove/restart).
  Process {
    id: inhibitProc
    running: root.lidOn
    command: ["systemd-inhibit",
      "--what=handle-lid-switch",
      "--who=Omarchy Sleepwalker",
      "--why=Keep working lid closed",
      "sleep", "infinity"]
  }

  FileView {
    id: togglesWatcher
    path: root.togglesDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  IpcHandler {
    target: "sleepwalker"

    function status(): string { return root.statusJson() }
    function toggle(): string { root.toggleLid(); return root.statusJson() }
    function lid(desired: string): string {
      if (desired === "on") root.setLid(true)
      else if (desired === "off") root.setLid(false)
      else root.toggleLid()
      return root.statusJson()
    }
  }
}
