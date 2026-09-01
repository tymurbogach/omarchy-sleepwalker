#!/usr/bin/env bash
# Undoes the Lid plugin.
#   ./uninstall.sh
set -uo pipefail

ID="io.github.tymurbogach.lid"
CLI="omarchy-lid"
SERVICE="omarchy-lid-inhibit.service"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

echo "· stopping inhibitor $SERVICE"
systemctl --user disable --now "$SERVICE" >/dev/null 2>&1 || systemctl --user stop "$SERVICE" >/dev/null 2>&1 || true
rm -f "$SYSTEMD_USER_DIR/$SERVICE"
systemctl --user daemon-reload >/dev/null 2>&1 || true

echo "· removing bar widget $ID"
omarchy-plugin-remove "$ID" --yes >/dev/null 2>&1 || omarchy-plugin-remove "$ID" >/dev/null 2>&1 || true
# omarchy plugin remove renames to .<id>.bak.<ts> — prune ours
for dir in "$PLUGINS_DIR"/.*.bak.*; do
  [[ -d $dir ]] || continue
  id=$(jq -r '.id // empty' "$dir/manifest.json" 2>/dev/null || echo "")
  if [[ $id == "$ID" ]]; then rm -rf "$dir"; fi
done
# Also remove live folder if remove wasn't available
rm -rf "$PLUGINS_DIR/$ID" "$PLUGINS_DIR/.$ID.staging" "$PLUGINS_DIR/.$ID.retired" 2>/dev/null || true

echo "· removing lid-close shim and CLI"
rm -f "$BIN_DIR/omarchy-system-lid-close"
rm -f "$BIN_DIR/$CLI" "$BIN_DIR/${CLI}-uninstall"

echo "· clearing toggles (off = gone)"
rm -f "$HOME/.local/state/omarchy/toggles/lid-ignore"
rm -f "$HOME/.local/state/omarchy/toggles/lid-lock"

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy-restart-shell >/dev/null 2>&1 || true

cat <<EOF
  Removed.
  Lid close is back to stock: suspend-then-hibernate.
EOF
