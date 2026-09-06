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

echo "· removing the post-update hook"
rm -f "$HOME/.config/omarchy/hooks/post-update.d/sleepwalker"

echo "· clearing toggles (off = gone)"
rm -f "$HOME/.local/state/omarchy/toggles/sleepwalker" "$HOME/.local/state/omarchy/toggles/lid-ignore"
rm -f "$HOME/.local/state/omarchy/toggles/lid-lock"

# The derived indicators clone. install.sh builds it from Omarchy's own source
# so this plugin can put one file inside it; leaving it behind leaves a fork of
# Omarchy's indicators that nobody maintains, holding a Laptop.qml that calls a
# command this script has just deleted.
#
# Ownership is not guessed: omarchy.derivedBy names the CLI that rebuilt it. A
# clone this plugin derived is removed and the built-in re-enabled; one that was
# already here — somebody else's, with their own indicators in it — is left
# alone and only has Laptop.qml taken out.
for d in "$PLUGINS_DIR"/*.indicators; do
  [[ -d $d ]] || continue
  [[ "$(jq -r '.omarchy.clonedFrom // empty' "$d/manifest.json" 2>/dev/null)" == "omarchy.indicators" ]] || continue
  if [[ "$(jq -r '.omarchy.derivedBy // empty' "$d/manifest.json" 2>/dev/null)" == "$CLI" ]]; then
    echo "· removing the indicators clone this plugin derived ($(basename "$d"))"
    rm -rf "$d"
    # install.sh disabled the built-in in favour of the clone, so putting it
    # back is what "uninstalled" means. Without this the bar is left with no
    # indicators at all.
    omarchy plugin enable omarchy.indicators >/dev/null 2>&1 || true
  else
    echo "· leaving $(basename "$d") alone; taking only Laptop.qml out of it"
    rm -f "$d/indicators/Laptop.qml"
  fi
done

# The bar layout: put the slot back to the built-in, in place. Enabling
# omarchy.indicators APPENDS a second entry, and removing the clone while its id
# stays in the layout is a dangling reference — a residue like any other. Rename
# whatever *.indicators entry is there, collapse to the first, drop Laptop.
if command -v jq >/dev/null 2>&1 && [[ -f "$HOME/.config/omarchy/shell.json" ]]; then
  tmp=$(mktemp)
  jq '
    .bar.layout |= with_entries(
      .value |= (
          map(if (.id | test("\\.indicators$")) then .id = "omarchy.indicators" else . end)
        | reduce .[] as $e ([]; if any(.[]; .id == $e.id) then . else . + [$e] end)
        | map(if .id == "omarchy.indicators"
              then .items = ((.items // []) - ["Laptop"]) else . end)
      )
    )
  ' "$HOME/.config/omarchy/shell.json" > "$tmp" 2>/dev/null \
    && mv "$tmp" "$HOME/.config/omarchy/shell.json" || rm -f "$tmp"
fi

# Kill any lingering inhibitor and verify
systemd-inhibit --list 2>/dev/null | grep -qi "sleepwalker" && systemctl --user stop "$SERVICE" >/dev/null 2>&1 || true
rm -f "$SYSTEMD_USER_DIR/$SERVICE" 2>/dev/null || true

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy-restart-shell >/dev/null 2>&1 || true

cat <<EOF
  Removed.
  Lid close is back to stock: suspend-then-hibernate.
EOF
