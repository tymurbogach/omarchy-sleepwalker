#!/usr/bin/env bash
# Installs the Lid plugin: bar widget + inhibitor + lid-close shim.
#   ./install.sh
#   ./install.sh --sync   # only (re)stage plugin + bin, no enable/restart
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ID="io.github.tymurbogach.lid"
CLI="omarchy-lid"
SYNC_ONLY=0
[[ ${1:-} != "--sync" ]] || SYNC_ONLY=1

command -v omarchy >/dev/null || { echo "this needs Omarchy" >&2; exit 1; }

PLUGINS_DIR="$HOME/.config/omarchy/plugins"
BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE="omarchy-lid-inhibit.service"

stage_plugin() {
  local id="$1"
  local dest="$PLUGINS_DIR/$id" staging="$PLUGINS_DIR/.$id.staging" retired="$PLUGINS_DIR/.$id.retired"
  rm -rf "$staging" "$retired"
  mkdir -p "$staging"
  cp -f "$HERE/manifest.json" "$staging/manifest.json"
  cp -f "$HERE/Panel.qml" "$staging/Panel.qml"

  if ! omarchy-plugin-validate "$staging" >/dev/null; then
    rm -rf "$staging"
    echo "  $id does not pass omarchy-plugin-validate; aborting" >&2
    exit 1
  fi
  [[ ! -e $dest ]] || mv "$dest" "$retired"
  mv "$staging" "$dest"
  rm -rf "$retired"
}

echo "· plugin $ID"
mkdir -p "$PLUGINS_DIR"
stage_plugin "$ID"

echo "· $CLI in $BIN_DIR"
mkdir -p "$BIN_DIR"
install -m 755 "$HERE/bin/$CLI" "$BIN_DIR/$CLI"
install -m 755 "$HERE/bin/omarchy-system-lid-close" "$BIN_DIR/omarchy-system-lid-close"
install -m 755 "$HERE/uninstall.sh" "$BIN_DIR/${CLI}-uninstall"

echo "· systemd user unit $SERVICE"
mkdir -p "$SYSTEMD_USER_DIR"
cp -f "$HERE/systemd/user/$SERVICE" "$SYSTEMD_USER_DIR/$SERVICE"
systemctl --user daemon-reload 2>/dev/null || true

# Reconcile inhibitor with existing toggle (so reinstall after reboot keeps state)
if [[ -f $HOME/.local/state/omarchy/toggles/lid-ignore ]]; then
  systemctl --user enable --now "$SERVICE" >/dev/null 2>&1 || systemctl --user start "$SERVICE" >/dev/null 2>&1 || true
fi

if ((SYNC_ONLY)); then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  exit 0
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 0.5

# Enable the widget exactly left of the clock (between indicators and clock,
# the strip you screenshot'd — 6 icons + Lid = 7). --before may fail if
# omarchy.clock is not yet in the layout (fresh shell.json), fallback to plain enable.
if ! omarchy plugin enable "$ID" --before omarchy.clock 2>/dev/null; then
  omarchy plugin enable "$ID" 2>/dev/null || true
  # Best-effort move to center-before-clock even if already enabled elsewhere
  omarchy bar put "$ID" --before omarchy.clock 2>/dev/null || true
fi
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 0.3

echo
"$BIN_DIR/$CLI" doctor || true

# One restart at the end: bar widget sizing + single instance guarantee
omarchy-restart-shell >/dev/null 2>&1 || true

cat <<EOF

  Done.

  $CLI                      toggle from terminal
    $CLI status --json       what is on
    $CLI lid on|off|toggle   keep working with lid closed
    $CLI lock on|off         lock on lid close (opt-in)
    $CLI doctor              reconcile toggle vs inhibitor

  Bar: Lid icon near the clock — tap for the two switches, Repair, Uninstall.
  Not there yet? Enable the widget: omarchy bar / Plugins → Lid.
  Default section is center (left of the clock); drag it where you want.

  Behavior:
    lid on  → inhibitor active (handle-lid-switch), closing lid only powers
               off eDP-1 via clamshell, no suspend, no lock by default.
    lid off → stock: lid close → suspend-then-hibernate (+ lock if no dock).

  Verify:
    $CLI lid on && systemd-inhibit --list | grep -i lid
    # close lid 10s → hyprctl monitors, journalctl -u systemd-logind (no suspend)
EOF
