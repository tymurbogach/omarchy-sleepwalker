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
| `lid-lock` | Explicit lock ON |
| `lock-off` | Explicit lock OFF (opt-out) |

Effective lock defaults to ON (stock): only `lock-off` without `lid-lock`
means OFF. Neither file (fresh install) is default ON — fail closed. Both
files (hand edit only) resolve to ON. 0.4.x treated a missing flag as OFF,
so a 0.4.x opt-out migrates to default ON (one right-click re-opts out).

Readers check existence only, never content: `touch` and `rm -f`.
Readers: `Service.qml` (probe + `FileView` watcher), `Laptop.qml` fallback
(CLI `--json`), CLI (`status`), shim (lid-close event).
Writers: `Service.qml` (serialized `bash -c`), CLI (`lid`/`lock`).

The toggle persists across reboots by design (see README warning).

## 1.1 Laptop controls

Left-clicking Laptop changes only the lid-ignore state. Right-clicking Laptop
changes only `lid-lock`. Neither control writes `shell.json`, `/etc`, or a
systemd policy.

When `Service.qml` is live, right-click calls `setLock()` directly. Otherwise
it uses the bundled CLI fallback, with lid and lock writes serialized in order.

## 1.2 Notifications controls

The DND indicator has two independent controls. Left-click changes Omarchy's
DND setting. Right-click calls the separate Notification Controls plugin and
reads the `crash-capture-off` flag for its tooltip. Without that plugin, the
right-click action is unavailable. Sleepwalker does not own the flag.

## 1.3 Removal

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
reaping on load would break the persistence in §1. Reapers verify the PID,
private token, and exact arguments that the wrapper recorded. They run only
when nothing should be held:
`lid off`, `doctor` (stray branch), `uninstall.sh`.
`status` reports the live child only; use `systemd-inhibit --list` to see
orphans.

## 3. Shim delegation (`omarchy-system-lid-close`)

Stock semantics preserved on every path:

- Default and explicit ON (`lock-off` absent, or `lid-lock` present):
  `exec` stock 1:1 (lock + clamshell), whether Working is ON or OFF.
- Explicit opt-out only (`lock-off` present without `lid-lock`): run stock
  clamshell only (panel off, displays reconciled), exit its code, no lock.
  When Working is OFF logind still suspends (no inhibitor held); when ON
  the inhibitor holds suspend.
- The suspend-time lock (`omarchy-sleep-lock.service`, PrepareForSleep) is
  suppressed separately: `lock off` stops that user service, `lock on`
  starts it. This covers any suspend (lid, menu, power button), not just
  lid-close. Since the default is ON, a fresh install keeps the stock
  suspend lock until an explicit opt-out. The monitor calls the absolute
  stock path, so no PATH shim can intercept it.
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
