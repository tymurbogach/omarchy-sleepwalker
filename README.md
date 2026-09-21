# Omarchy Sleepwalker

Close your laptop and keep working. One click, no suspend, lock optional.

![Sleepwalker: close the lid and keep working, with the native Laptop indicator in the Omarchy bar](preview.png)

Listed on the [Omarchy plugin marketplace](https://plugins.omarchy.org/plugin.html?id=io.github.tymurbogach.sleepwalker).

Needs: Omarchy 4 · a laptop with a lid switch (does nothing on desktops) ·
`jq` recommended, not required.

## Install

```sh
omarchy plugin add https://github.com/tymurbogach/omarchy-sleepwalker.git --enable --yes
~/.config/omarchy/plugins/io.github.tymurbogach.sleepwalker/install.sh
omarchy-sleepwalker lid on
```

- Always pass `--yes`: the entry inherits the stock strip slot.
- The setup script adds the CLI, lid-close shim, and pinned lid binding.
- Everything lives inside `$HOME`: no sudo, no system service.

The final command enables Sleepwalker. Close the lid: the panel goes off and
work continues. Click Laptop to turn it off again. Right-click Laptop to
switch Lock on close on or off.

## What it does

Sleepwalker adds a **Laptop** indicator to Omarchy's bar. When it is on,
downloads, builds, servers, and SSH sessions continue with the lid closed.

| Lid closed, Sleepwalker… | Result |
|---|---|
| **ON** | Panel off. No suspend, no hibernate, no lock. Keeps working. |
| **OFF** (stock) | Suspend (+ lock unless docked). |
| **ON + lock** (`lock on`) | Panel off + locked. Still no suspend. |

No separate widget, no oversized icon: Sleepwalker **is** Omarchy's
indicator strip with a 7th entry — same size, same dim-when-off, same
hover-reveal as the other six.

> **Right-click Laptop to switch Lock on close on or off.** This setting
> takes effect while Sleepwalker is on. It does not change the global suspend,
> hibernate, idle, or screensaver policy.

## Commands

| Command | What it does |
|---|---|
| `omarchy-sleepwalker lid on` | Keep working with the lid closed. |
| `omarchy-sleepwalker lid off` | Return to stock suspend. |
| `omarchy-sleepwalker lid toggle` | Flip the lid setting. |
| `omarchy-sleepwalker lock on` | Lock on close, with no suspend. |
| `omarchy-sleepwalker lock off` | Close without locking. |
| `omarchy-sleepwalker status` | Show lid, inhibitor, and lock state. |
| `omarchy-sleepwalker doctor` | Reconcile the toggle and inhibitor. |

The lid setting persists across reboots. Do not put the laptop in a bag while
it is on. Run `omarchy-sleepwalker lid off` before you move it.

## Configure

Keep Laptop visible when it is inactive:

```sh
omarchy bar set io.github.tymurbogach.sleepwalker alwaysShow true
```

For `items`, edit `~/.config/omarchy/shell.json` directly. The installer
ensures `Laptop` is present and never changes your order.

## Update

After an Omarchy update, refresh the copied stock indicators:

```sh
~/.config/omarchy/plugins/io.github.tymurbogach.sleepwalker/install.sh --sync-stock
```

After a plugin update, run:

```sh
omarchy plugin update io.github.tymurbogach.sleepwalker --yes
~/.config/omarchy/plugins/io.github.tymurbogach.sleepwalker/install.sh
```

## Remove

```sh
omarchy-sleepwalker remove
```

This clean path removes the plugin, command, lid-close shim, binding block,
and state files. Lid close then returns to stock suspend.

If setup ran first and you remove the plugin directly, use this recovery path:

```sh
omarchy plugin remove io.github.tymurbogach.sleepwalker --yes
~/.local/bin/omarchy-sleepwalker-uninstall
```

## Troubleshooting

- **No Laptop icon.** Run the setup script, then `omarchy restart shell`.
- **The lid still suspends.** Run `omarchy-sleepwalker doctor`.
- **The laptop locks unexpectedly.** Run `omarchy-sleepwalker lock off`.

Technical details: [SPEC.md](docs/SPEC.md). Contributor workflow:
[CONTRIBUTING.md](docs/CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
