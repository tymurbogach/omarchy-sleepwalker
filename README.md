# Omarchy Sleepwalker

Keep working with the lid closed — a Laptop indicator inside Omarchy's own indicator strip.

> **Placement:** the indicators strip left of the clock (🎙️ ● ⚓ … ☕). After install, Sleepwalker is the **7th icon**, same 21px slot and dim-when-off (0.45) behaviour as the other six. Click it to toggle.

## Install

```sh
omarchy plugin add https://github.com/tymurbogach/omarchy-sleepwalker.git --enable
```

That alone is a working install: indicator + lid inhibitor, straight from the store. No scripts to run.

For the full lid-closed behaviour (closed lid powers off the panel **without locking** — stock locks), one extra step:

```sh
./install.sh
```

It only puts the CLI on `PATH` and installs the lid-close shim. Everything lands inside `$HOME` — no sudo, no `/usr` writes, no systemd units. The inhibitor is held by the plugin's own service while the toggle is on.

## Usage

Click the  indicator to turn lid-ignore on/off. Right side of the behaviour:

- **Lid off (stock):** close lid → suspend-then-hibernate (+ lock unless docked).
- **Lid on (this plugin):** close lid → only powers off the panel, **no suspend, no lock** by default. The machine keeps working. Optional lock: `omarchy-sleepwalker lock on`.

Terminal:

```sh
omarchy-sleepwalker status              # human readable
omarchy-sleepwalker status --json       # {"active":true,"inhibitActive":true,"lockOnLid":false}
omarchy-sleepwalker lid on|off|toggle
omarchy-sleepwalker lock on|off|toggle
omarchy-sleepwalker doctor              # reconcile toggle vs inhibitor
omarchy-sleepwalker lid on && systemd-inhibit --list | grep -i sleepwalker
```

## Configure

The strip is Omarchy's indicators widget, so the standard bar commands apply:

```sh
omarchy bar set io.github.tymurbogach.sleepwalker items '["Dictation","Laptop","StayAwake"]' --json
omarchy bar move io.github.tymurbogach.sleepwalker --section center --index 0
```

After an `omarchy update`, refresh the stock indicator copies (Laptop is untouched):

```sh
./install.sh --sync-stock
```

## Remove

```sh
omarchy plugin remove io.github.tymurbogach.sleepwalker
```

The built-in indicators strip is restored in place automatically. If you ran `./install.sh`, also remove the CLI + shim + toggles:

```sh
./uninstall.sh
# or: omarchy-sleepwalker-uninstall
```

## How it works

- **Indicator:** `indicators/Laptop.qml`, a `BarIndicator` like the stock six. It binds reactively to the plugin's `Service.qml` (`lidOn`) — no polling, same size/style/hover-reveal as the rest of the strip.
- **Inhibitor:** `Service.qml` holds `systemd-inhibit --what=handle-lid-switch … sleep infinity` exactly while the toggle is on. Disabling or removing the plugin releases it.
- **No lock:** Hyprland runs `omarchy-system-lid-close` on lid close. `./install.sh` places a shim earlier on `PATH` (`~/.local/bin`) that, with lid-ignore on and lock off, only reconciles displays instead of locking. Without the shim, stock behaviour applies (lock, then whatever the inhibitor allows).
- **State:** `~/.local/state/omarchy/toggles/sleepwalker` (on = file exists) and `lid-lock` (opt-in lock). The CLI, the service and the indicator all read the same files, so terminal and bar always agree.
- **Privileges:** none beyond the user session. No sudo, no setuid, no second Quickshell process, no writes outside `$HOME`.

## License

MIT
