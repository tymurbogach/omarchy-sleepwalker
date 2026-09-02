#!/usr/bin/env bash
# Installs the Sleepwalker plugin: bar widget + inhibitor + lid-close shim.
#   ./install.sh
#   ./install.sh --sync   # only (re)stage plugin + bin, no enable/restart
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ID="io.github.tymurbogach.sleepwalker"
CLI="omarchy-sleepwalker"
OLD_ID="io.github.tymurbogach.lid"
OLD_CLI="omarchy-lid"
OLD_SERVICE="omarchy-lid-inhibit.service"
SYNC_ONLY=0
[[ ${1:-} != "--sync" ]] || SYNC_ONLY=1

command -v omarchy >/dev/null || { echo "this needs Omarchy" >&2; exit 1; }

PLUGINS_DIR="$HOME/.config/omarchy/plugins"
BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE="omarchy-sleepwalker-inhibit.service"

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

# Migrate from old Lid if present
echo "· migrating from $OLD_ID if present"
omarchy plugin remove "$OLD_ID" --yes >/dev/null 2>&1 || true
rm -rf "$PLUGINS_DIR/$OLD_ID" "$PLUGINS_DIR/.$OLD_ID.staging" "$PLUGINS_DIR/.$OLD_ID.retired" 2>/dev/null || true
for d in "$PLUGINS_DIR"/.*.bak.*; do [[ -d $d ]] || continue; id=$(jq -r '.id // empty' "$d/manifest.json" 2>/dev/null || echo ""); [[ $id == "$OLD_ID" ]] && rm -rf "$d"; done
systemctl --user disable --now "$OLD_SERVICE" >/dev/null 2>&1 || systemctl --user stop "$OLD_SERVICE" >/dev/null 2>&1 || true
rm -f "$SYSTEMD_USER_DIR/$OLD_SERVICE" 2>/dev/null || true
rm -f "$BIN_DIR/$OLD_CLI" "$BIN_DIR/${OLD_CLI}-uninstall" 2>/dev/null || true
if [[ -f $HOME/.local/state/omarchy/toggles/lid-ignore && ! -f $HOME/.local/state/omarchy/toggles/sleepwalker ]]; then
  cp -f "$HOME/.local/state/omarchy/toggles/lid-ignore" "$HOME/.local/state/omarchy/toggles/sleepwalker" 2>/dev/null || true
fi

echo "· $CLI in $BIN_DIR"
mkdir -p "$BIN_DIR"
install -m 755 "$HERE/bin/$CLI" "$BIN_DIR/$CLI"
# keep legacy symlink for Laptop indicator until it migrates to new CLI
ln -sf "$BIN_DIR/$CLI" "$BIN_DIR/$OLD_CLI" 2>/dev/null || true
install -m 755 "$HERE/bin/omarchy-system-lid-close" "$BIN_DIR/omarchy-system-lid-close"
install -m 755 "$HERE/uninstall.sh" "$BIN_DIR/${CLI}-uninstall"

echo "· systemd user unit $SERVICE"
mkdir -p "$SYSTEMD_USER_DIR"
cp -f "$HERE/systemd/user/$SERVICE" "$SYSTEMD_USER_DIR/$SERVICE"
systemctl --user daemon-reload 2>/dev/null || true

# Reconcile inhibitor with existing toggle (so reinstall after reboot keeps state)
if [[ -f $HOME/.local/state/omarchy/toggles/sleepwalker || -f $HOME/.local/state/omarchy/toggles/lid-ignore ]]; then
  systemctl --user enable --now "$SERVICE" >/dev/null 2>&1 || systemctl --user start "$SERVICE" >/dev/null 2>&1 || true
fi

if ((SYNC_ONLY)); then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  exit 0
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 0.5

# Integrated icon: disable the large separate bar-widget and use the
# small indicator inside cyberdyne.indicators (same strip as Reminder/StayAwake)
# — matches Omarchy's original indicator styling (statusSlot, dim 0.45).
omarchy plugin disable "$ID" >/dev/null 2>&1 || true
if command -v jq >/dev/null 2>&1 && [[ -f "$HOME/.config/omarchy/shell.json" ]]; then
  tmp=$(mktemp)
  jq '
    .bar.layout.center |= map(select(.id != "'"$ID"'"))
    | if .bar.layout.center then
        .bar.layout.center |= map(
          if .id == "cyberdyne.indicators" then
            .items = (["Dictation","ScreenRecording","Reminder","NightLight","Dnd","StayAwake","Laptop"])
            | .alwaysShow = true
          else . end
        )
      else . end
  ' "$HOME/.config/omarchy/shell.json" > "$tmp" 2>/dev/null && mv "$tmp" "$HOME/.config/omarchy/shell.json" || rm -f "$tmp"
fi
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 0.3

echo
"$BIN_DIR/$CLI" doctor || true

# One restart at the end: indicator sizing + single instance guarantee
omarchy-restart-shell >/dev/null 2>&1 || true

cat <<EOF

  Done.

  $CLI                      toggle from terminal
    $CLI status --json       what is on
    $CLI lid on|off|toggle   keep working with lid closed
    $CLI lock on|off         lock on lid close (opt-in)
    $CLI doctor              reconcile toggle vs inhibitor

  Bar: Small Laptop indicator integrated with Reminder/StayAwake/etc.
       left of the clock — same size/style as Omarchy's original indicators.
       Click the  to toggle lid ignore.

  Behavior:
    lid on  → inhibitor active (handle-lid-switch), closing lid only powers
               off eDP-1 via clamshell, no suspend, no lock by default.
    lid off → stock: lid close → suspend-then-hibernate (+ lock if no dock).

  Verify:
    $CLI lid on && systemd-inhibit --list | grep -i lid
    # close lid 10s → hyprctl monitors, journalctl -u systemd-logind (no suspend)
EOF
