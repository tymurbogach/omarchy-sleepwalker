# Sleepwalker SPEC

Contract-level description. README is the user manual; this file is what
a reviewer or future maintainer must hold in their head. Code wins on any
conflict.

## 1. State (single source of truth)

All state is file presence under `~/.local/state/omarchy/toggles/`:

| File | Meaning |
|---|---|
| `sleepwalker` | Lid-ignore on (preferred name) |
| `lid-ignore` | Same, legacy name. Read everywhere, written nowhere. Migrated to `sleepwalker` on write. |
| `lid-lock` | Lock on lid close, opt-in, default absent |

Readers check existence only, never content: `touch` and `rm -f`.
Readers: `Service.qml` (probe + `FileView` watcher), `Laptop.qml` fallback
(CLI `--json`), CLI (`status`), shim (lid-close event).
Writers: `Service.qml` (serialized `bash -c`), CLI (`lid`/`lock`).

The toggle persists across reboots by design (see README warning).

## 1.1 Laptop menu

Right-clicking Laptop opens a `PopupCard` anchored to the indicator. It reads
the name and version from the bundled manifest, and changes only `lid-lock`.
Left-click keeps its existing lid-toggle behavior. The menu never writes
`shell.json`, `/etc`, or a systemd policy.

When `Service.qml` is live, the menu calls `setLock()` directly. Otherwise it
uses the bundled CLI fallback, with lid and lock writes serialized in order.

## 1.2 Removal

`omarchy-sleepwalker remove` runs the installed uninstaller with
`--remove-plugin`. It removes plugin-owned external files before it asks
Omarchy to remove the plugin directory. Omarchy has no plugin uninstall hook,
so direct `omarchy plugin remove` cannot clean those external files. The
installed `omarchy-sleepwalker-uninstall` remains available for that recovery
path.

## 2. Inhibitor ownership

Exactly one handle per live service: child
`systemd-inhibit --what=handle-lid-switch --who="Omarchy Sleepwalker"
--why="Keep working lid closed" sleep infinity`, spawned by the binding
`running: root.lidOn` in `Service.qml`. No systemd unit; `plugin add`
alone is a working install.

Orphans: a shell crash reparents the child to PID 1 and the handle
survives (logind ORs duplicates). The service never reaps on load —
reaping on load would break the persistence in §1. Reapers, all matching
the `--who` string and only when nothing should be held:
`lid off`, `doctor` (stray branch), `uninstall.sh`.
`status` reports the live child only; use `systemd-inhibit --list` to see
orphans.

## 3. Shim delegation (`omarchy-system-lid-close`)

Stock semantics preserved on every path:

- Toggle off, or toggle on with `lid-lock` present: `exec` stock 1:1.
- Toggle on without lock: run stock clamshell only (panel off, displays
  reconciled), exit its code, no lock.
- The lid binding is pinned to the shim by absolute path
  (`install.sh:pin_lid_binding`, marked block in `bindings.lua`) because
  systemd-unit exec contexts resolve `/usr/share/omarchy/bin` before
  `~/.local/bin`, which would run stock and lock.

## 4. Layout and binding invariants

- One strip entry with our id, wherever the user keeps it. The installer
  integrates, never moves: it only ensures `Laptop` inside that entry's
  `items` (dedupe preserving order, repair of non-array `items`).
- No `items` key means stock defaults, which include `Laptop` via our
  `Indicators.qml` patch. Never write `items` through the shell IPC path:
  the transport splits on whitespace and mangles JSON arrays.
- Outside the marked `bindings.lua` block, user edits always survive
  install and uninstall. Backups beside edited files are capped at 3.

## 5. Clone design (`omarchy.clonedFrom`)

The plugin IS the stock indicators strip plus one entry, permanently.
`clonedFrom: omarchy.indicators` is load-bearing, not a migration
leftover: enable swaps our id into the stock slot inheriting its entry,
and remove restores the built-in preserving other keys (stock
`PluginRegistry` replace/restore). Dropping it would break both.
The stock `IpcHandler (omarchy.indicators)` is removed (patch 3): with
the built-in disabled there is no collision to avoid, and no stock
caller addresses that target (verified by repo-wide search), so nothing
is lost.

## 6. IPC and CLI behavior

- `target: sleepwalker`: `status()` (optimistic `lidOn` + live child),
  `toggle()`, `lid(on|off)` — anything else is an error, never a toggle.
- CLI mirrors the files: `lid/lock on|off|toggle` (bare word = toggle),
  `status [--json]`, `doctor` (reconcile + legacy-unit cleanup + stray
  recovery). Extra arguments are rejected, not ignored.
- Service writes serialize through one slot with overflow queue; commands
  are absolute per file, so coalescing stays correct across `lid`/`lock`
  interleaves.
