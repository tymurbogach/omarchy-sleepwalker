#!/usr/bin/env bash
# Undoes what install.sh did (CLI + shim + legacy), and clears toggles.
# The plugin itself is removed with: omarchy plugin remove <id>
# (that restores the built-in indicators strip in place, by itself).
#   ./uninstall.sh
set -uo pipefail

ID="io.github.tymurbogach.sleepwalker"
OLD_ID="io.github.tymurbogach.lid"
CLI="omarchy-sleepwalker"
OLD_CLI="omarchy-lid"
LEGACY_UNITS=("omarchy-sleepwalker-inhibit.service" "omarchy-lid-inhibit.service")
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SHIM="$BIN_DIR/omarchy-system-lid-close"

ours() { [[ -f $1 ]] && grep -qi "sleepwalker" "$1"; }

echo "· stopping legacy inhibitor units (<0.2.0)"
for u in "${LEGACY_UNITS[@]}"; do
  if [[ -f $SYSTEMD_USER_DIR/$u ]]; then
    systemctl --user disable --now "$u" >/dev/null 2>&1 || systemctl --user stop "$u" >/dev/null 2>&1 || true
    rm -f "$SYSTEMD_USER_DIR/$u"
  fi
done
systemctl --user daemon-reload >/dev/null 2>&1 || true

echo "· removing CLI and lid-close shim (only if ours)"
for f in "$BIN_DIR/$CLI" "$BIN_DIR/${CLI}-uninstall" "$BIN_DIR/$OLD_CLI" "$BIN_DIR/${OLD_CLI}-uninstall"; do
  if [[ -f $f || -L $f ]]; then
    if ours "$f" || [[ -L $f && $(readlink "$f") == *sleepwalker* ]]; then rm -f "$f"; else echo "  leaving foreign $f alone" >&2; fi
  fi
done
if [[ -f $SHIM ]]; then
  if ours "$SHIM"; then rm -f "$SHIM"; else echo "  leaving foreign $SHIM alone" >&2; fi
fi

echo "· removing legacy post-update hook"
rm -f "$HOME/.config/omarchy/hooks/post-update.d/sleepwalker"

echo "· clearing toggles (off = gone)"
rm -f "$HOME/.local/state/omarchy/toggles/sleepwalker" "$HOME/.local/state/omarchy/toggles/lid-ignore"
rm -f "$HOME/.local/state/omarchy/toggles/lid-lock"

# Legacy (<0.2.0) derived indicators clones: remove ours, spare others'.
for d in "$PLUGINS_DIR"/*.indicators; do
  [[ -d $d ]] || continue
  [[ "$(jq -r '.omarchy.clonedFrom // empty' "$d/manifest.json" 2>/dev/null)" == "omarchy.indicators" ]] || continue
  if [[ "$(jq -r '.omarchy.derivedBy // empty' "$d/manifest.json" 2>/dev/null)" == "$CLI" ]]; then
    echo "· removing legacy derived clone $(basename "$d")"
    rm -rf "$d"
    omarchy plugin enable omarchy.indicators >/dev/null 2>&1 || true
  fi
done

# Legacy (<0.2.0) separate-widget slots under either id.
if command -v jq >/dev/null 2>&1 && [[ -f "$HOME/.config/omarchy/shell.json" ]]; then
  for section in left center right; do
    tmp=$(mktemp)
    jq --arg id "$ID" --arg old "$OLD_ID" --arg sec "$section" '
      .bar.layout[$sec] |= (map(
        (if type == "string" then . else (.id // "") end) as $eid
        | select($eid != $old and ($eid != $id or (type == "object" and has("items"))))
      ) // .)' \
      "$HOME/.config/omarchy/shell.json" > "$tmp" 2>/dev/null \
      && mv "$tmp" "$HOME/.config/omarchy/shell.json" || rm -f "$tmp"
  done
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

cat <<EOF
  Removed (CLI, shim, toggles, legacy).
  Lid close is back to stock: suspend-then-hibernate.

  To also remove the bar indicator itself:
    omarchy plugin remove $ID
EOF
