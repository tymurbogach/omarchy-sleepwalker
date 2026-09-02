# Omarchy Sleepwalker

Keep working with the lid closed — one tap left of the clock.

![Sleepwalker icon](https://img.shields.io/badge/Omarchy-bar--widget-9cf)

> **Placement:** in the indicators strip (`omarchy.indicators`), to the left of the clock. That row of 6 icons (🎙️ ● ⚓ … ☕). After install, Sleepwalker appears as the **7th icon** right between the indicators and the clock (`omarchy.clock`). Dim when off (0.45), full brightness when on — matching the other 6.

## What it does

- **Lid off (stock):** close lid → `suspend-then-hibernate` (+ lock if no external monitor). Defined in `/etc/systemd/logind.conf.d/99-lid.conf:1` + `omarchy-system-lid-close:13`.
- **Lid on (this plugin):** close lid → only powers off the panel (`eDP-1` via `omarchy-hyprland-monitor-clamshell`), **no suspend, no hibernate, no lock** by default. The machine keeps working. With a dock (external monitor) it was already clamshell — no regression.

Optional: enable **Lock on lid** so that even with Sleepwalker on, it locks on close.

## Installation

```bash
git clone https://github.com/tymurbogach/omarchy-sleepwalker.git
cd omarchy-sleepwalker
./install.sh
# enables and places the icon left of the clock (between indicators and clock)
# if you already had the repo: ./install.sh --sync
```

Also via plugin manager:
```bash
omarchy plugin add https://github.com/tymurbogach/omarchy-sleepwalker.git --enable
omarchy plugin enable io.github.tymurbogach.sleepwalker --before omarchy.clock
```

Validate with:
```bash
omarchy-plugin-validate .
omarchy-sleepwalker status --json
systemd-inhibit --list | grep -i lid   # should show "Omarchy Sleepwalker  handle-lid-switch  block"
```

## Usage

- **Bar:** icon `` left of the clock. Left click toggles lid ignore, right click refreshes status.
- **Terminal:**
```bash
omarchy-sleepwalker status              # human readable
omarchy-sleepwalker status --json       # {"active":true,"inhibitActive":true,"lockOnLid":false}
omarchy-sleepwalker lid on|off|toggle
omarchy-sleepwalker lock on|off|toggle
omarchy-sleepwalker doctor              # reconciles toggle vs systemd service
omarchy-sleepwalker lid on && systemd-inhibit --list | grep -i lid
```

Move the icon:
```bash
omarchy bar put io.github.tymurbogach.sleepwalker --before omarchy.clock   # left of clock (default)
omarchy bar put io.github.tymurbogach.sleepwalker --after omarchy.indicators
omarchy bar move io.github.tymurbogach.sleepwalker --section center --index 1
```

## How it works (no sudo)

- **Inhibitor:** `systemd-inhibit --what=handle-lid-switch --who="Omarchy Sleepwalker" sleep infinity` in a user service `omarchy-sleepwalker-inhibit.service` (`~/.config/systemd/user/`). `lid on` → `systemctl --user enable --now`, `lid off` → `disable --now`. Survives `omarchy-restart-shell`; writes only inside `$HOME`, so it passes `omarchy-plugin-validate`.
- **No lock:** Hyprland triggers `omarchy-system-lid-close` on `switch:on:Lid Switch` (`default/hypr/bindings/utilities.lua:34`). The plugin installs a shim at `~/.local/bin/omarchy-system-lid-close` (highest in `$PATH`) that, when `lid-ignore` + `!lid-lock`, only runs `omarchy-hyprland-monitor-clamshell` (powers off `eDP-1`), skipping `omarchy-system-lock`.
- **Persistence:** `~/.local/state/omarchy/toggles/lid-ignore` and `lid-lock` (pattern `omarchy-toggle:10`, `StayAwake.qml:6`). `doctor` reconciles toggle state vs inhibitor.

## Verification

```bash
omarchy-sleepwalker lid on
systemd-inhibit --list | grep Sleepwalker   # block
# close lid 10s without dock:
hyprctl monitors                    # eDP-1 disabled
journalctl -u systemd-logind --since "1 min ago" | grep -i suspend  # nothing
omarchy-sleepwalker lid off                 # back to stock
```

On lid open, `omarchy-hyprland-monitor-clamshell` re-enables `eDP-1`.

## Publishing to plugins.omarchy.org

- `manifest.json` at root, `id` reverse-DNS not reserved (`io.github.tymurbogach.sleepwalker`), `schemaVersion:1`, `kinds:["bar-widget"]`, `entryPoints.barWidget:"Panel.qml"`.
- Public git repo + tag `v0.1.0` + this README with `omarchy plugin add <url> --enable`.

## Uninstall

```bash
./uninstall.sh
# or
omarchy-sleepwalker-uninstall
# removes toggles and service; lid close returns to suspend (off = gone)
```

## License

MIT
