# Omarchy Sleepwalker

Close your laptop and keep working. One click, no suspend, lock optional.

![Sleepwalker: close the lid and keep working, with the native Laptop indicator in the Omarchy bar](preview.png)

Listed on the [Omarchy plugin marketplace](https://plugins.omarchy.org/plugin.html?id=io.github.tymurbogach.sleepwalker).

Needs: Omarchy 4 · a laptop with a lid switch (does nothing on desktops) ·
`jq` recommended, not required.

## What it does

Laptops suspend when you close the lid. Sleepwalker adds a **Laptop indicator** to Omarchy's bar: left-click it and closing the lid only powers off the panel — downloads, builds, servers and SSH sessions keep running. Left-click again and you're back to stock. Right-click it to configure locking on lid close.

| Lid closed, Sleepwalker… | Result |
|---|---|
| **ON** | Panel off. No suspend, no hibernate, no lock. Keeps working. |
| **OFF** (stock) | Suspend (+ lock unless docked). |
| **ON + lock** (`lock on`) | Panel off + locked. Still no suspend. |

No separate widget, no oversized icon: Sleepwalker **is** Omarchy's
indicator strip with a 7th entry — same size, same dim-when-off, same
hover-reveal as the other six. The preview shows its compact PopupCard.

## Quickstart

```sh
omarchy plugin add https://github.com/tymurbogach/omarchy-sleepwalker.git --enable --yes
./install.sh
omarchy-sleepwalker lid on
```

Close the lid: the panel goes off, everything keeps running. The Laptop
icon sits next to the clock, bright when on, dimmed when off.

Right-click Laptop to open its compact menu. It shows the installed plugin
version and toggles **Lock on lid close**. The setting takes effect while
Sleepwalker is on. The menu does not change the system-wide lid policy.

## Install

```sh
omarchy plugin add https://github.com/tymurbogach/omarchy-sleepwalker.git --enable --yes
./install.sh
```

- Always pass `--yes`: the entry inherits the stock strip slot, and the
  section question would displace it.
- `plugin add` brings the indicator strip with Laptop.
- `./install.sh` adds the CLI to `PATH`, installs the lid-close shim, and
  pins the lid binding to the shim. It integrates, never moves: it only
  ensures `Laptop` is in the strip's items, wherever the strip sits.
- Everything lives inside `$HOME`: no sudo, no services. A no-op re-run
  touches nothing (no rescan, no restart).

The inhibitor is held by the plugin's own service while the toggle is on;
disabling or removing the plugin releases it. If the shell crashes while
on, the orphaned handle survives: `lid off`, `doctor` and `uninstall.sh`
reap it (see [SPEC.md](docs/SPEC.md)).

## Usage

Click the indicator, or run:

| Command | What it does |
|---|---|
| `omarchy-sleepwalker lid on` | Keep working with the lid closed |
| `omarchy-sleepwalker lid off` | Back to stock suspend |
| `omarchy-sleepwalker lid toggle` | Flip it (default with no argument) |
| `omarchy-sleepwalker lock on` | Also lock on close (default off; still no suspend) |
| `omarchy-sleepwalker lock off` | Close without locking |
| `omarchy-sleepwalker status` | Show lid, inhibitor and lock state |
| `omarchy-sleepwalker status --json` | Same, as JSON |
| `omarchy-sleepwalker doctor` | Reconcile toggle vs inhibitor, fix drift |

Example session:

```sh
$ omarchy-sleepwalker lid on
lid on
$ omarchy-sleepwalker status
lid-ignore: on
inhibit:    active
lock-on-lid:off
```

The toggle persists across reboots by design (it is a file, not a
process). Warning: shelve the laptop with it on and it stays awake in
the bag. When in doubt, `status`; `lid off` always releases.

Stock idle keeps counting with the lid closed (screensaver at
`idle.screensaver`, lock at `idle.lock`; stock defaults 150 s / 300 s) —
that is Omarchy behavior, not controlled here.

## Configure

Flip `alwaysShow` with the stock CLI:

```sh
omarchy bar set io.github.tymurbogach.sleepwalker alwaysShow true
```

For `items`, edit `~/.config/omarchy/shell.json` directly — the shell
hot-reloads it. (Skip `omarchy bar set ... items ...`: the shell IPC
transport mangles JSON arrays.) The installer ensures `Laptop` is present
and never touches your order otherwise.

After an `omarchy update`, refresh the stock indicator copies (Laptop is untouched):

```sh
./install.sh --sync-stock
```

After every plugin update (`omarchy plugin update`), re-run `./install.sh`
— the store refreshes the plugin dir, but the CLI, shim and binding pin
only update when the installer runs (it is idempotent).

## Remove

```sh
omarchy-sleepwalker remove
```

This is the clean removal command. It removes plugin-owned CLI files, the
lid-close shim, the marked binding block, state files and the plugin through
Omarchy. Lid close returns to stock suspend.

`omarchy plugin remove io.github.tymurbogach.sleepwalker` cannot run a plugin
uninstall hook. If you use it directly, run
`~/.local/bin/omarchy-sleepwalker-uninstall` afterwards to remove the external
files that `./install.sh` created.

## Troubleshooting

- **No Laptop icon.** Run `./install.sh` (it ensures the entry). If it is
  still missing, `omarchy-restart-shell` once.
- **It asks for password on open.** That is `lock on`, or the shim/pin
  missing: run `omarchy-sleepwalker doctor`.
- **Lid still suspends.** Check `omarchy-sleepwalker status`: `lid-ignore`
  must be on and `inhibit` active. If they disagree, `doctor` reconciles.
- **After an update things look stale.** Re-run `./install.sh` (see
  Configure above); it restarts the shell only if layout or code changed.

## How it works

- **Indicator:** a native stock-style entry bound reactively to the plugin
  service, with a CLI fallback when the service is unreachable.
- **Inhibitor:** `systemd-inhibit --what=handle-lid-switch`, held exactly
  while the toggle is on. No daemon, user session only.
- **No lock:** a shim plus a pinned lid binding skip the stock lock but
  still reconcile displays.

Details for reviewers and contributors: [SPEC.md](docs/SPEC.md) (contract)
and [CONTRIBUTING.md](docs/CONTRIBUTING.md) (workflow, architecture).

## License

MIT — see [LICENSE](LICENSE).
