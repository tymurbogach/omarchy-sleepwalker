# Sleepwalker

**Close the lid. Keep working.**

![Sleepwalker PopupCard in the Omarchy bar](preview.png)

`v0.3.5` · Omarchy 4+ · Laptop with a lid switch

Sleepwalker adds one native **Laptop** indicator to the Omarchy bar. It keeps
your session running when you close the lid. Right-click it to lock the
session without stopping your work.

## Install

```sh
omarchy plugin add https://github.com/tymurbogach/omarchy-sleepwalker.git --enable --yes
~/.config/omarchy/plugins/io.github.tymurbogach.sleepwalker/install.sh
```

The first command installs the native indicator. The second command adds the
terminal command and the safe lid-close integration. It writes only inside
your home directory. It does not need `sudo`.

## Use

| Action | Result |
|---|---|
| Left-click **Laptop** | Toggle lid protection on or off. |
| Right-click **Laptop** | Open the compact **Lock on close** control. |
| `omarchy-sleepwalker lid on` | Keep working after you close the lid. |
| `omarchy-sleepwalker lid off` | Return to normal suspend behavior. |
| `omarchy-sleepwalker lock on` | Lock the session and keep working closed. |
| `omarchy-sleepwalker status` | Show the current state. |

When Sleepwalker is on, closing the lid turns the panel off. Your downloads,
builds, servers, and SSH sessions continue. When it is off, Omarchy uses its
normal lid behavior.

The PopupCard shows the plugin version and one clear option:

- **Lock on close** locks the session while the laptop still works closed.

## Important

Sleepwalker keeps the laptop awake while the lid is closed. Do not put it in a
bag while it is on. Run this command before you move the laptop:

```sh
omarchy-sleepwalker lid off
```

The lid setting persists across reboots. This is intentional.

## Configure

By default, inactive indicators appear when you hover the bar. To keep
Laptop visible all the time:

```sh
omarchy bar set io.github.tymurbogach.sleepwalker alwaysShow true
```

The popup changes only Sleepwalker's lock-on-close setting. It does not change
the global suspend, hibernate, idle, or screensaver policy.

## Update

After `omarchy plugin update`, run the installed setup script again:

```sh
~/.config/omarchy/plugins/io.github.tymurbogach.sleepwalker/install.sh
```

After an Omarchy update, refresh the copied stock indicators too:

```sh
~/.config/omarchy/plugins/io.github.tymurbogach.sleepwalker/install.sh --sync-stock
```

## Remove

```sh
omarchy-sleepwalker remove
```

This is the clean removal path. It removes the plugin, command, lid-close
shim, binding block, and state files. Lid close then returns to normal suspend.

If you ran the setup script and then remove the plugin directly with
`omarchy plugin remove io.github.tymurbogach.sleepwalker`, run this afterwards
to remove the external files created during setup:

```sh
~/.local/bin/omarchy-sleepwalker-uninstall
```

## Help

| Problem | Fix |
|---|---|
| Laptop is missing | Run the installed setup script, then `omarchy restart shell`. |
| The lid still suspends | Run `omarchy-sleepwalker doctor`. |
| The laptop locks unexpectedly | Run `omarchy-sleepwalker lock off`. |

Technical details: [SPEC.md](docs/SPEC.md). Contributor workflow:
[CONTRIBUTING.md](docs/CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
