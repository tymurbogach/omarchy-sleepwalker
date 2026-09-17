# Contributing to Omarchy Sleepwalker

Omarchy Sleepwalker is an Omarchy plugin (`io.github.tymurbogach.sleepwalker`).
It adds a "Laptop" indicator to the Omarchy bar. While the indicator is on,
the plugin holds a `systemd-inhibit --what=handle-lid-switch`, so a closed lid
turns the panel off instead of suspending the laptop. It ships as a clone of
the stock Omarchy indicator strip plus one new indicator, not as a separate
bar widget.

## Commands

There is no build step, package manager or test suite: the plugin is QML plus
bash scripts. After a substantial change, run this verification:

```bash
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" <changed .qml files>

# from-zero reinstall cycle
omarchy plugin disable io.github.tymurbogach.sleepwalker
omarchy plugin remove  io.github.tymurbogach.sleepwalker --yes
ls ~/.config/omarchy/plugins/io.github.tymurbogach.sleepwalker/   # MUST NOT exist
omarchy plugin add . --enable --yes
omarchy-restart-shell                  # the only reliable QML reload
```

Then verify a cold start by hand: the bar renders, a click toggles the
indicator, a lid close behaves, `omarchy plugin list --json` shows the plugin,
and disable, enable, restart and remove all work cleanly.

For fast local iteration without a full reinstall, copy the repository into
`~/.config/omarchy/plugins/io.github.tymurbogach.sleepwalker/`. Then run
`omarchy-shell shell rescanPlugins` and `omarchy-restart-shell`.

After an Omarchy update, refresh the clone of the stock indicators:

```sh
./install.sh --sync-stock
```

## Architecture

Three moving parts, one shared state directory, no polling:

- **`Service.qml`** (entry point `service`, `IpcHandler` target
  `sleepwalker`) owns the lid-inhibit child process and the toggle state. It
  holds `systemd-inhibit … sleep infinity` as a child `Process` exactly while
  the toggle is on. There is no systemd unit, so `omarchy plugin add` alone is
  a working install. `runWrite` and `writerBusy` serialize the writes, so a
  fast second toggle waits in a queue instead of racing a second bash call
  over the same state files.
- **`Indicators.qml`** (entry point `barWidget`) is a clone of the stock
  Omarchy indicator strip (`$OMARCHY_PATH/shell/plugins/bar/widgets/Indicators.qml`).
  `install.sh --sync-stock` regenerates it with three documented patches (see
  the header comment of the file): a fix for the relative import path,
  `Laptop` added to `defaultIndicatorEntries`, and the stock `IpcHandler`
  removed to avoid a handler collision warning against the disabled built-in.
  **Never hand-edit this file.** Always regenerate it.
- **`indicators/Laptop.qml`** is the new indicator. It binds to `Service.qml`
  through `bar.shell.serviceFor("io.github.tymurbogach.sleepwalker")` when
  that is available. When the service is unreachable, it falls back to the
  bundled CLI (`bin/omarchy-sleepwalker`, resolved relative to the plugin,
  never through `PATH`) plus a 30 s poll.
  `indicators/{Dictation,Dnd,NightLight,Reminder,ScreenRecording,StayAwake}.qml`
  are verbatim copies of the stock indicators, which `--sync-stock` also
  refreshes. Do not edit them by hand either.
- **`bin/omarchy-sleepwalker`** is the user-facing CLI (`status`,
  `lid on|off|toggle`, `lock on|off|toggle`, `doctor`). It reads and writes
  the same state files as `Service.qml` and `Laptop.qml`, so all three views
  of the toggle always agree.
- **`bin/omarchy-system-lid-close`** is a shim installed to `~/.local/bin`,
  which comes before `/usr/share/omarchy/bin` on `PATH`. When the toggle is on
  and lock-on-lid is off, a lid-close event skips the stock lock, and the shim
  still reconciles the displays through the stock clamshell script. Otherwise
  it delegates 1:1 to the real script.

State lives only under `~/.local/state/omarchy/toggles/`. The file
`sleepwalker` (preferred) or `lid-ignore` (legacy, read-only) means that the
toggle is on. The file `lid-lock` means that lock-on-lid is on (opt-in). The
plugin reads only whether a file exists, never its content: `touch` and
`rm -f`.

`install.sh` and `uninstall.sh` also carry substantial legacy migration logic:
the old plugin id `io.github.tymurbogach.lid`, pre-0.2.0 systemd inhibit
units, pre-0.2.0 derived-clone plugin folders and pre-0.2.0 separate
bar-widget layout entries. When you change install or uninstall, keep this
migration path. Real installs still hit it, so do not assume a clean slate.

`install.sh` also pins `switch:on:Lid Switch` to the shim by absolute path
in a marked block in `~/.config/hypr/bindings.lua`, and `uninstall.sh`
removes exactly that block. The pin exists because bare command names resolve
by `PATH`, and systemd-unit exec contexts order `/usr/share/omarchy/bin`
before `~/.local/bin`: without it the stock lid-close script can win and lock
the session despite the toggle. Never touch outside the marked block; manual
user edits elsewhere in the file always survive install and uninstall.

## Conventions

- Everything (code, docs, commits) is English.
- No symlinks anywhere in the repository (`omarchy plugin validate` rejects
  them).
- No agent instruction files in the repository (`CLAUDE.md`, `AGENTS.md` and
  the like). The complete checkout becomes the plugin payload, and the
  marketplace review rejects files that steer coding agents. Contributor
  notes live here, in `docs/`.
- Zero residue on remove: `uninstall.sh` leaves no files, caches or stray
  `shell.json` entries behind, and removes only the files that it can verify
  as its own (see the `ours()` check in `uninstall.sh`).
- Commits: English, imperative, one concern per commit, authored by the
  maintainer. No tool bylines or `Co-Authored-By` lines for tools.
