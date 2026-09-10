#!/usr/bin/env bash
# Sleepwalker install — thin on purpose.
#
# The plugin itself needs no install step: `omarchy plugin add <repo> --enable`
# is a working install (indicator + inhibitor, straight from the store).
# This script only does the two things the store cannot:
#   1. puts the CLI on PATH (~/.local/bin) for terminal use
#   2. installs the lid-close shim (~/.local/bin/omarchy-system-lid-close)
#      so a closed lid powers off the panel WITHOUT locking (stock locks)
#
# Everything is written inside $HOME. No sudo, no /usr, no services.
#
#   ./install.sh              full: migrate legacy + CLI + shim + enable
#   ./install.sh --sync-stock refresh Indicators.qml + stock indicators from
#                             Omarchy's current source (after `omarchy update`)
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ID="io.github.tymurbogach.sleepwalker"
CLI="omarchy-sleepwalker"
OLD_ID="io.github.tymurbogach.lid"
OLD_CLI="omarchy-lid"
LEGACY_UNITS=("omarchy-sleepwalker-inhibit.service" "omarchy-lid-inhibit.service")

command -v omarchy >/dev/null || { echo "this needs Omarchy" >&2; exit 1; }

PLUGINS_DIR="$HOME/.config/omarchy/plugins"
BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
OMARCHY_SRC="${OMARCHY_PATH:-/usr/share/omarchy}"

# --- refresh derived files from Omarchy's current source -------------------
# Indicators.qml is a clone of stock plus two documented patches (see the file
# header). The six sibling indicators are verbatim copies. Re-run after an
# Omarchy update so the strip never becomes a frozen fork.
sync_stock() {
  local src_widget="$OMARCHY_SRC/shell/plugins/bar/widgets/Indicators.qml"
  local src_ind="$OMARCHY_SRC/shell/plugins/bar/indicators"
  [[ -f $src_widget && -d $src_ind ]] || { echo "cannot find Omarchy's indicators source" >&2; exit 1; }

  case "$(cat "$src_widget")" in
    *'Qt.resolvedUrl("../indicators/"'*) ;;
    *) echo "Omarchy's Indicators.qml no longer loads from ../indicators/ — refusing to regenerate" >&2; exit 1 ;;
  esac
  case "$(cat "$src_widget")" in
    *'defaultIndicatorEntries: ['*) ;;
    *) echo "Omarchy's Indicators.qml no longer lists defaultIndicatorEntries — refusing to regenerate" >&2; exit 1 ;;
  esac

  {
    printf '%s\n' \
      '// Sleepwalker — derived from Omarchy stock Indicators.qml.' \
      '// Regenerate after an Omarchy update with: ./install.sh --sync-stock' \
      '// Local patches vs stock (keep them minimal so diffs stay reviewable):' \
      '//   1. Qt.resolvedUrl("../indicators/" -> Qt.resolvedUrl("indicators/"' \
      '//      (in a clone both files sit at the top level; ".." points outside)' \
      '//   2. defaultIndicatorEntries gains "Laptop" (Sleepwalker lid behaviour).' \
      ''
    sed -e 's|Qt\.resolvedUrl("\.\./indicators/"|Qt.resolvedUrl("indicators/"|' \
        -e 's|defaultIndicatorEntries: \[ "Dictation", "ScreenRecording", "Reminder", "NightLight", "Dnd", "StayAwake" \]|defaultIndicatorEntries: [ "Dictation", "ScreenRecording", "Reminder", "NightLight", "Dnd", "StayAwake", "Laptop" ]|' \
        "$src_widget"
  } > "$HERE/Indicators.qml"
  grep -q '"Laptop"' "$HERE/Indicators.qml" || { echo "patch 2 did not apply — aborting" >&2; exit 1; }

  local f
  for f in Dictation Dnd NightLight Reminder ScreenRecording StayAwake; do
    cp -f "$src_ind/$f.qml" "$HERE/indicators/$f.qml"
  done
  echo "· stock refreshed (Indicators.qml + 6 indicators); Laptop.qml untouched"
}

if [[ ${1:-} == "--sync-stock" ]]; then
  sync_stock
  exit 0
fi

# --- legacy migration (<0.2.0: separate bar-widget + systemd unit + derived clone) ---

echo "· migrating legacy state if present"

# Legacy inhibitor units: the Service owns the inhibitor now.
for u in "${LEGACY_UNITS[@]}"; do
  if [[ -f $SYSTEMD_USER_DIR/$u ]]; then
    systemctl --user disable --now "$u" >/dev/null 2>&1 || systemctl --user stop "$u" >/dev/null 2>&1 || true
    rm -f "$SYSTEMD_USER_DIR/$u"
  fi
done
systemctl --user daemon-reload >/dev/null 2>&1 || true

# Legacy plugin dirs (old lid id, staging leftovers).
omarchy plugin remove "$OLD_ID" --yes >/dev/null 2>&1 || true
rm -rf "$PLUGINS_DIR/$OLD_ID" "$PLUGINS_DIR/.$OLD_ID.staging" "$PLUGINS_DIR/.$OLD_ID.retired" 2>/dev/null || true

# Legacy derived indicators clones (built by <0.2.0 install.sh): the plugin IS
# the clone now, so these are redundant forks. Remove ours, spare others'.
for d in "$PLUGINS_DIR"/*.indicators; do
  [[ -d $d ]] || continue
  [[ "$(jq -r '.omarchy.clonedFrom // empty' "$d/manifest.json" 2>/dev/null)" == "omarchy.indicators" ]] || continue
  if [[ "$(jq -r '.omarchy.derivedBy // empty' "$d/manifest.json" 2>/dev/null)" == "$CLI" ]]; then
    echo "· removing legacy derived clone $(basename "$d")"
    rm -rf "$d"
    omarchy plugin enable omarchy.indicators >/dev/null 2>&1 || true
  fi
done

# Legacy separate-widget slot: <0.2.0 staged a big BarIconButton beside the
# strip. The new model has no such widget; any layout entry with our id that
# carries no `items` is that stale slot. (Entries WITH items are the new
# indicators strip — never touch those.)
if command -v jq >/dev/null 2>&1 && [[ -f $HOME/.config/omarchy/shell.json ]]; then
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

# Legacy toggle name → new one.
if [[ -f $HOME/.local/state/omarchy/toggles/lid-ignore && ! -f $HOME/.local/state/omarchy/toggles/sleepwalker ]]; then
  cp -f "$HOME/.local/state/omarchy/toggles/lid-ignore" "$HOME/.local/state/omarchy/toggles/sleepwalker" 2>/dev/null || true
fi

# Legacy PATH leftovers + post-update hook from the derive era.
rm -f "$BIN_DIR/$OLD_CLI" "$BIN_DIR/${OLD_CLI}-uninstall" "$HOME/.config/omarchy/hooks/post-update.d/sleepwalker" 2>/dev/null || true

# --- the two things the store cannot do ---

echo "· $CLI in $BIN_DIR (terminal use)"
mkdir -p "$BIN_DIR"
install -m 755 "$HERE/bin/$CLI" "$BIN_DIR/$CLI"
install -m 755 "$HERE/uninstall.sh" "$BIN_DIR/${CLI}-uninstall"

echo "· lid-close shim (closed lid: screen off, no lock, no suspend)"
install -m 755 "$HERE/bin/omarchy-system-lid-close" "$BIN_DIR/omarchy-system-lid-close"

# --- enable (in-place replace of the built-in strip, settings preserved) ---

if omarchy plugin list --json 2>/dev/null | jq -e --arg id "$ID" 'any(.[]; .id == $id)' >/dev/null; then
  omarchy plugin enable "$ID" >/dev/null 2>&1 || true
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
else
  echo "· plugin not added yet — finish with:"
  echo "    omarchy plugin add https://github.com/tymurbogach/omarchy-sleepwalker.git --enable"
fi

echo
"$BIN_DIR/$CLI" doctor || true

cat <<EOF

  Done. CLI + shim installed; the plugin itself comes from the store:

    omarchy plugin add https://github.com/tymurbogach/omarchy-sleepwalker.git --enable

  Bar: Laptop indicator inside the strip (same size/style as the other six).
       Click toggles lid ignore; dim when off, full when on.

  Verify:
    $CLI lid on && systemd-inhibit --list | grep -i sleepwalker
    # close lid 10s → panel off, no suspend, no lock (lock opt-in: $CLI lock on)
EOF
