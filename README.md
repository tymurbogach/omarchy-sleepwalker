# Omarchy Sleepwalker

Close your laptop and keep working. One click, no suspend, lock optional.

![Sleepwalker: close the lid and keep working, with the native Laptop indicator in the Omarchy bar](preview.png)

## What it does

Laptops suspend when you close the lid. Sleepwalker adds a **Laptop indicator** to Omarchy's bar: click it and closing the lid only powers off the panel — downloads, builds, servers and SSH sessions keep running. Click again and you're back to stock.

| Lid closed, Sleepwalker… | Result |
|---|---|
| **ON** | Panel off. No suspend, no hibernate, no lock. Keeps working. |
| **OFF** (stock) | Suspend (+ lock unless docked). |
| **ON + lock** (`lock on`) | Panel off + locked. Still no suspend. |

## Looks stock, because it is the strip

No separate widget, no oversized icon. Sleepwalker **is** Omarchy's indicator strip with a 7th entry — same size, same dim-when-off, same hover-reveal as the other six:

**ON** — bright, next to the clock:

![Laptop indicator on](docs/bar-on.png)

**OFF** — dimmed among the rest (inactive indicators hide until hover, like stock):

![Laptop indicator off, dimmed with the other indicators](docs/bar-off.png)

## Install

```sh
omarchy plugin add https://github.com/tymurbogach/omarchy-sleepwalker.git --enable --yes
./install.sh
```

Always install with `--yes`: the entry inherits the stock strip slot, and
the section question would displace it. The installer integrates, never
moves: it only ensures `Laptop` is in the strip's items, wherever it sits.

| Step | What you get |
|---|---|
| `plugin add` | The indicator strip with Laptop (inherits your indicator list). |
| `install.sh` | Adds Laptop to the strip, puts the CLI on `PATH`, installs the lid-close shim, and pins the lid binding to the shim by absolute path (bare names resolve by `PATH`, and systemd-unit contexts would run stock and lock). Restarts the shell once if the layout changed, so a first load always rebuilds; never on a no-op re-run. Everything inside `$HOME` — no sudo, no services. |

The inhibitor is held by the plugin's own service while the toggle is on; disabling or removing the plugin releases it. If the shell crashes while on, the orphaned handle (PPID 1) survives: `lid off`, `doctor` and `uninstall.sh` reap it (see SPEC.md).

## Usage

Click the indicator, or from the terminal:

```sh
omarchy-sleepwalker lid on|off|toggle   # keep working with lid closed
omarchy-sleepwalker lock on|off|toggle  # also lock on close (default off)
omarchy-sleepwalker status --json       # {"active":true,"inhibitActive":true,"lockOnLid":false}
omarchy-sleepwalker doctor              # reconcile toggle vs inhibitor
```

The toggle persists across reboots by design (it is a file, not a process).
Warning: if you leave it on and shelve the laptop, it stays awake in the
bag. Check `status` when in doubt; `lid off` always releases.

`lock` is opt-in and off by default; with `lock on` the lid still never
suspends. Stock idle keeps counting with the lid closed (screensaver at
`idle.screensaver`, lock at `idle.lock`; stock defaults 150 s / 300 s) —
that is Omarchy behavior, not controlled here.

## Configure

Like any indicators strip. Flip `alwaysShow` with the stock CLI:

```sh
omarchy bar set io.github.tymurbogach.sleepwalker alwaysShow true
```

For `items`, edit `~/.config/omarchy/shell.json` directly (the shell
hot-reloads it). Do not use `omarchy bar set ... items ...` — the shell IPC
transport splits on whitespace and mangles JSON arrays. The installer
ensures `Laptop` is present and never touches your order otherwise.

After an `omarchy update`, refresh the stock indicator copies (Laptop is untouched):

```sh
./install.sh --sync-stock
```

After every plugin update (`omarchy plugin update`), re-run `./install.sh`
— the store refreshes the plugin dir, but the CLI, shim and binding pin
only update when the installer runs (it is idempotent).

## Remove

```sh
./uninstall.sh
omarchy plugin remove io.github.tymurbogach.sleepwalker
```

In this order the restored built-in strip comes back clean. Lid close returns to stock suspend.

## Requirements

- Omarchy 4 with `omarchy`, `omarchy-shell`, `omarchy-restart-shell` on `PATH`
- `systemd-inhibit` (logind) for the lid inhibitor
- Stock `omarchy-system-lid-close` + `omarchy-hyprland-monitor-clamshell` (shim delegates to them)
- `jq` recommended (without it the installer skips layout edits with a warning)
- `perl` only for `./install.sh --sync-stock`

## How it works

- **Indicator** (`indicators/Laptop.qml`): a native `BarIndicator` bound reactively to the plugin service. No polling on the healthy path; if the service is unreachable it falls back to the bundled CLI plus a 30 s poll. The six sibling files are verbatim copies of Omarchy's stock indicators — don't edit them by hand, refresh with `./install.sh --sync-stock`.
- **Inhibitor** (`Service.qml`): holds `systemd-inhibit --what=handle-lid-switch` exactly while the toggle is on. No daemon: the service spawns short-lived `bash` helpers for disk state plus the one inhibitor child.
- **No lock**: `./install.sh` places a shim earlier on `PATH` (`~/.local/bin/omarchy-system-lid-close`) that only reconciles displays instead of locking, and pins the lid binding to it by absolute path (systemd-unit contexts resolve stock first by `PATH`). Without either, stock lock applies.
- **State**: `~/.local/state/omarchy/toggles/sleepwalker` (on = file exists) and `lid-lock` (opt-in). CLI, service and indicator read the same files.
- **Privileges**: user session only. No sudo, no setuid, no second shell process, nothing outside `$HOME`.

## License

MIT
