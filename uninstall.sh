#!/usr/bin/env bash
# Undoes the Sleepwalker plugin (and legacy Lid).
#   ./uninstall.sh
set -uo pipefail

ID="io.github.tymurbogach.sleepwalker"
OLD_ID="io.github.tymurbogach.lid"
CLI="omarchy-sleepwalker"
OLD_CLI="omarchy-lid"
SERVICE="omarchy-sleepwalker-inhibit.service"
OLD_SERVICE="omarchy-lid-inhibit.service"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

echo "· stopping inhibitor $SERVICE and legacy $OLD_SERVICE"
systemctl --user disable --now "$SERVICE" >/dev/null 2>&1 || systemctl --user stop "$SERVICE" >/dev/null 2>&1 || true
systemctl --user disable --now "$OLD_SERVICE" >/dev/null 2>&1 || systemctl --user stop "$OLD_SERVICE" >/dev/null 2>&1 || true
rm -f "$SYSTEMD_USER_DIR/$SERVICE" "$SYSTEMD_USER_DIR/$OLD_SERVICE"
systemctl --user daemon-reload >/dev/null 2>&1 || true

echo "· removing bar widget $ID and legacy $OLD_ID"
for rid in "$ID" "$OLD_ID"; do
  omarchy-plugin-remove "$rid" --yes >/dev/null 2>&1 || omarchy-plugin-remove "$rid" >/dev/null 2>&1 || true
  for dir in "$PLUGINS_DIR"/.*.bak.*; do
    [[ -d $dir ]] || continue
    id=$(jq -r '.id // empty' "$dir/manifest.json" 2>/dev/null || echo "")
    if [[ $id == "$rid" ]]; then rm -rf "$dir"; fi
  done
  rm -rf "$PLUGINS_DIR/$rid" "$PLUGINS_DIR/.$rid.staging" "$PLUGINS_DIR/.$rid.retired" 2>/dev/null || true
done

echo "· removing lid-close shim and CLI"
rm -f "$BIN_DIR/omarchy-system-lid-close"
rm -f "$BIN_DIR/$CLI" "$BIN_DIR/${CLI}-uninstall" "$BIN_DIR/$OLD_CLI" "$BIN_DIR/${OLD_CLI}-uninstall"

echo "· clearing toggles (off = gone)"
rm -f "$HOME/.local/state/omarchy/toggles/sleepwalker" "$HOME/.local/state/omarchy/toggles/lid-ignore"
rm -f "$HOME/.local/state/omarchy/toggles/lid-lock"

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy-restart-shell >/dev/null 2>&1 || true

cat <<EOF
  Removed.
  Lid close is back to stock: suspend-then-hibernate.
EOF
