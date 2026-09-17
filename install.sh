#!/usr/bin/env bash
# Sleepwalker install — thin on purpose.
#
# The plugin itself needs no install step: `omarchy plugin add <repo> --enable`
# is a working install (indicator + inhibitor, straight from the store).
# This script only does the three things the store cannot:
#   1. puts the CLI on PATH (~/.local/bin) for terminal use
#   2. installs the lid-close shim (~/.local/bin/omarchy-system-lid-close)
#      so a closed lid powers off the panel WITHOUT locking (stock locks)
#   3. pins the lid-close binding to the shim by absolute path
#      (PATH order differs per exec context; systemd units would run stock)
#
# Everything is written inside $HOME. No sudo, no /usr, no services.
#
#   ./install.sh              full: migrate legacy + CLI + shim + enable
#   ./install.sh --sync-stock refresh Indicators.qml + stock indicators from
#                             Omarchy's current source (after `omarchy update`)
set -euo pipefail
export LC_ALL=C  # stable grep/sort classes regardless of user locale

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ID="io.github.tymurbogach.sleepwalker"
CLI="omarchy-sleepwalker"
OLD_ID="io.github.tymurbogach.lid"
OLD_CLI="omarchy-lid"
LEGACY_UNITS=("omarchy-sleepwalker-inhibit.service" "omarchy-lid-inhibit.service")

command -v omarchy >/dev/null || { echo "this needs Omarchy" >&2; exit 1; }
command -v jq >/dev/null || echo "warning: jq not found — Laptop icon and layout migration will be skipped" >&2
# md5sum drives layout-change detection; without it every run assumes changed.
MD5_OK=false
command -v md5sum >/dev/null 2>&1 && MD5_OK=true
$MD5_OK || echo "warning: md5sum not found — shell restarts on every run" >&2

PLUGINS_DIR="$HOME/.config/omarchy/plugins"
BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
OMARCHY_SRC="${OMARCHY_PATH:-/usr/share/omarchy}"

# --- refresh derived files from Omarchy's current source -------------------
# Indicators.qml is a clone of stock plus three documented patches (see the file
# header). The six sibling indicators are verbatim copies. Re-run after an
# Omarchy update so the strip never becomes a frozen fork.
sync_stock() {
  local src_widget="$OMARCHY_SRC/shell/plugins/bar/widgets/Indicators.qml"
  local src_ind="$OMARCHY_SRC/shell/plugins/bar/indicators"
  [[ -f $src_widget && -d $src_ind ]] || { echo "cannot find Omarchy's indicators source" >&2; exit 1; }
  command -v perl >/dev/null || { echo "sync-stock needs perl" >&2; exit 1; }

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
      '//   3. Stock IpcHandler (target "omarchy.indicators") removed: the disabled' \
      '//      built-in keeps serving that target and nothing calls it, so keeping it' \
      '//      only logged a handler-collision warning on every load.' \
      ''
    sed -e 's|Qt\.resolvedUrl("\.\./indicators/"|Qt.resolvedUrl("indicators/"|' \
        -e 's|\(defaultIndicatorEntries: \[[^]]*[^ ]\) *\]|\1, "Laptop" ]|' \
        "$src_widget" \
    | perl -0777 -pe 's/  IpcHandler \{\n    target: "omarchy\.indicators"\n\n    function refresh\(\): void \{\n      root\.broadcast\("refresh"\)\n    \}\n  \}\n\n/  \/\/ (Stock IpcHandler removed — see header patch 3.)\n\n/'
  } > "$HERE/Indicators.qml"
  grep -q '"Laptop"' "$HERE/Indicators.qml" || { echo "patch 2 did not apply — aborting" >&2; exit 1; }
  grep -q 'target: "omarchy.indicators"' "$HERE/Indicators.qml" && { echo "patch 3 did not apply — aborting" >&2; exit 1; } || true

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

# Move jq output into place only on real content change; never clobber the
# original on tool failure. Same-dir tmp (see callers) keeps rename atomic.
commit_tmp() {
  local tmp="$1" dest="$2" st
  cmp -s "$tmp" "$dest" 2>/dev/null; st=$?
  if [[ $st -eq 0 ]]; then rm -f "$tmp"
  elif [[ $st -eq 1 ]]; then mv "$tmp" "$dest"
  else echo "warning: cannot verify $dest — leaving it untouched" >&2; rm -f "$tmp"
  fi
}

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
rm -rf "${PLUGINS_DIR:?}/$OLD_ID" "${PLUGINS_DIR:?}/.$OLD_ID.staging" "${PLUGINS_DIR:?}/.$OLD_ID.retired" 2>/dev/null || true

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

# Layout change detection: only a shell restart rebuilds the strip from the
# new layout (verified: rescanPlugins alone leaves the old strip rendering).
# Re-runs with nothing to change touch neither rescan nor restart.
layout_sum_before=""
[[ -f $HOME/.config/omarchy/shell.json ]] && $MD5_OK && layout_sum_before=$(md5sum "$HOME/.config/omarchy/shell.json" | cut -d' ' -f1)

# Legacy separate-widget slot: <0.2.0 staged a big BarIconButton beside the
# strip. The new model has no such widget; any layout entry with our id that
# carries no `items` is that stale slot. (Entries WITH items are the new
# indicators strip — never touch those. Bare-string entries are user
# shorthand — never touch those either.)
if command -v jq >/dev/null 2>&1 && [[ -f $HOME/.config/omarchy/shell.json ]]; then
  for section in left center right; do
    tmp=$(mktemp "$HOME/.config/omarchy/.shell.json.tmp.XXXXXX")
    jq --arg id "$ID" --arg old "$OLD_ID" --arg sec "$section" '
      if (.bar.layout[$sec] | type) == "array" then
        .bar.layout[$sec] |= (map(
          (if type == "string" then .
            elif type == "object" then (.id // "")
            else "" end) as $eid
          | select($eid != $old and ($eid != $id or type == "string" or (type == "object" and has("items"))))
        ) // .)
      else . end' \
      "$HOME/.config/omarchy/shell.json" > "$tmp" 2>/dev/null \
      && commit_tmp "$tmp" "$HOME/.config/omarchy/shell.json" || rm -f "$tmp"
  done
fi

# Legacy toggle name → new one (move, not copy: nothing reads it back).
# Both present means an earlier copy-migration; drop the legacy leftover.
if [[ -f $HOME/.local/state/omarchy/toggles/lid-ignore ]]; then
  if [[ ! -f $HOME/.local/state/omarchy/toggles/sleepwalker ]]; then
    mv -f "$HOME/.local/state/omarchy/toggles/lid-ignore" "$HOME/.local/state/omarchy/toggles/sleepwalker" 2>/dev/null || true
  else
    rm -f "$HOME/.local/state/omarchy/toggles/lid-ignore" 2>/dev/null || true
  fi
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

# --- pin lid-close to the shim by absolute path -----------------------------
# The stock binding runs a bare `omarchy-system-lid-close`, which resolves by
# PATH. PATH order differs per context: systemd units put
# /usr/share/omarchy/bin first, so the stock script can win over our shim and
# lock the session despite the toggle. An absolute path wins everywhere.
# Managed block in the user's bindings.lua: ours to refresh, theirs to keep.
# Backups are safety, not residue: keep the newest 3, prune the rest.
# mapfile (line-split) so paths with spaces survive; plain $(...) would not.
prune_backups() {
  local base="$1" f
  local -a bak=()
  mapfile -t bak < <(ls -t "$base".bak.* 2>/dev/null || true) || true
  for f in "${bak[@]:3}"; do rm -f "$f"; done
}

pin_lid_binding() {
  local bindings="$HOME/.config/hypr/bindings.lua"
  local begin="-- BEGIN omarchy-sleepwalker (managed by install.sh - do not edit)"
  local end="-- END omarchy-sleepwalker"
  mkdir -p "$(dirname "$bindings")"
  [[ -f $bindings ]] || : > "$bindings"
  # A pre-existing Lid Switch binding outside our block (e.g. the user's own
  # lock script) is about to be shadowed by hl.unbind — say so, with backup.
  # (Our own block mentions Lid Switch too, so look past it.)
  if sed "/^-- BEGIN omarchy-sleepwalker/,/^-- END omarchy-sleepwalker$/d" "$bindings" 2>/dev/null | grep -q "Lid Switch"; then
    echo "warning: $bindings already binds Lid Switch — our pin shadows it (backup kept)" >&2
  fi
  local tmp
  tmp=$(mktemp "$(dirname "$bindings")/.bindings.lua.tmp.XXXXXX")
  cp -f "$bindings" "$tmp"
  # A BEGIN without its END means a previous aborted edit: refuse to touch
  # the file rather than range-deleting to EOF (GNU sed semantics).
  if grep -q "^-- BEGIN omarchy-sleepwalker" "$tmp" && ! grep -q "^-- END omarchy-sleepwalker$" "$tmp"; then
    echo "warning: stale BEGIN without END in $bindings — leaving it untouched (fix by hand, backup kept)" >&2
    cp -f "$bindings" "$bindings.bak.$(date +%s).$$"
    rm -f "$tmp"
    return 0
  fi
  sed -i "/^-- BEGIN omarchy-sleepwalker/,/^-- END omarchy-sleepwalker$/d" "$tmp"
  # Strip blank lines left at EOF so re-runs don't stack separators.
  sed -i -e :a -e '/./!{$d;N;ba' -e '}' "$tmp"
  [[ -s $tmp ]] && printf '\n' >> "$tmp"
  # Lua-escape the path for the double-quoted string (\ and " only; spaces
  # are fine inside quotes).
  local shim_path="${BIN_DIR//\\/\\\\}"
  shim_path="${shim_path//\"/\\\"}"
  cat >> "$tmp" <<EOF
$begin
-- Absolute path on purpose: bare names resolve by PATH, and systemd-unit
-- contexts order /usr/share/omarchy/bin before ~/.local/bin (stock would win).
hl.unbind("switch:on:Lid Switch")
o.bind("switch:on:Lid Switch", nil, "$shim_path/omarchy-system-lid-close", { locked = true })
$end
EOF
  if cmp -s "$bindings" "$tmp"; then
    rm -f "$tmp"
    echo "· lid binding already pinned"
  else
    cp -f "$bindings" "$bindings.bak.$(date +%s).$$"
    prune_backups "$bindings"
    mv "$tmp" "$bindings"
    echo "· lid binding pinned to $BIN_DIR/omarchy-system-lid-close"
  fi
}

echo "· lid binding override (absolute path beats PATH shadowing)"
pin_lid_binding

# --- enable (in-place replace of the built-in strip, settings preserved) ---

# Without jq the JSON check below falls back to grep; the layout edits
# stay skipped (jq-only) and say so.
plugin_added() {
  local list
  list=$(omarchy plugin list --json 2>/dev/null) || return 1
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$list" | jq -e --arg id "$ID" 'any(.[]; .id == $id)' >/dev/null
  else
    # Flattened first: pretty printers may split "id": and value across lines.
    # Dots escaped, trailing boundary: sleepwalker-fork must not match.
    printf '%s' "$list" | tr '\n' ' ' | grep -qE -- '"id"[[:space:]]*:[[:space:]]*"io\.github\.tymurbogach\.sleepwalker"($|[^0-9A-Za-z._-])'
  fi
}

if plugin_added; then
  # Enable is idempotent registry-side, but it still costs a replace+rescan
  # storm — skip it when already enabled. (Without jq we cannot see the
  # flag, so run it unconditionally there.)
  if omarchy plugin list --json 2>/dev/null | jq -e --arg id "$ID" 'any(.[]; .id == $id and .enabled == true)' >/dev/null 2>&1; then
    echo "· plugin already enabled"
  else
    omarchy plugin enable "$ID" >/dev/null 2>&1 || true
  fi
  # The enable replaces the built-in strip in place and inherits its explicit
  # `items` — which predate Laptop. Ensure it once so the icon actually shows.
  # (No `items` key at all means "defaults", which already include Laptop.)
  # A present-but-broken `items` (wrong type — e.g. a string left by the
  # `setBarWidget` IPC path, which mangles JSON arrays) is repaired to
  # ["Laptop"]: the curation it replaced is already unrecoverable.
  # Principle: integrate, never move. This only touches our entry's `items`,
  # wherever it sits; it never reorders or relocates layout entries. Install
  # with --yes so the section question never displaces the inherited slot.
  # The filter also collapses duplicate items inside the entry, keeping
  # first-occurrence order (never `unique`: it would reshuffle the icons).
  if command -v jq >/dev/null 2>&1 && [[ -f $HOME/.config/omarchy/shell.json ]]; then
    tmp=$(mktemp "$HOME/.config/omarchy/.shell.json.tmp.XXXXXX")
    jq --arg id "$ID" '
      if (.bar.layout | type) == "object" then
        .bar.layout |= with_entries(
          .value |= ((if type == "array" then
            map(
              if type == "object" and (.id // "") == $id
              then if (.items | type) == "array"
                   then .items |= (reduce .[] as $x ([]; if index($x) then . else . + [$x] end)
                                   | if index("Laptop") then . else . + ["Laptop"] end)
                   elif has("items") then .items = ["Laptop"]
                   else . end
              else . end
            )
          else . end) // .)
        )
      else . end' \
      "$HOME/.config/omarchy/shell.json" > "$tmp" 2>/dev/null \
      && commit_tmp "$tmp" "$HOME/.config/omarchy/shell.json" || rm -f "$tmp"
  else
    echo "warning: jq or shell.json missing — skipping Laptop/layout ensure (install jq and re-run)" >&2
  fi
  # `plugin add/enable` already rescanned; a restart (below) supersedes
  # rescanPlugins, so don't fire both storms.
else
  echo "· plugin not added yet — finish with:"
  echo "    omarchy plugin add https://github.com/tymurbogach/omarchy-sleepwalker.git --enable --yes"
fi

layout_changed=false
if [[ -f $HOME/.config/omarchy/shell.json ]]; then
  if [[ -n $layout_sum_before ]]; then
    $MD5_OK && [[ $(md5sum "$HOME/.config/omarchy/shell.json" | cut -d' ' -f1) != "$layout_sum_before" ]] && layout_changed=true
  else
    layout_changed=true
  fi
fi

# Code-change detection: QML only (re)loads on restart — keepLoaded services
# survive rescan — so a code update with an unchanged layout would leave
# stale code running with no restart to pick it up. Stamp the hash of the
# INSTALLED plugin dir (what the shell actually loads, not this repo);
# mismatch means the store refreshed the code since our last run.
STAMP_DIR="$HOME/.local/state/omarchy/sleepwalker"
STAMP_FILE="$STAMP_DIR/installed-code.md5"
code_changed=true
if $MD5_OK && [[ -d $PLUGINS_DIR/$ID ]]; then
  installed_hash=$(md5sum "$PLUGINS_DIR/$ID/manifest.json" "$PLUGINS_DIR/$ID/Indicators.qml" "$PLUGINS_DIR/$ID/Service.qml" "$PLUGINS_DIR/$ID"/indicators/*.qml 2>/dev/null | md5sum | cut -d' ' -f1 || true)
  [[ -f $STAMP_FILE ]] && [[ $installed_hash == "$(cat "$STAMP_FILE" 2>/dev/null)" ]] && code_changed=false
fi

echo
doc_out=$("$BIN_DIR/$CLI" doctor || true)
echo "$doc_out"

# The strip picks up `items` edits through the shell's hot-reload, but the
# first load / widget swap after enable is only safe with a rebuild, so
# restart at most once per run, and never on a no-op re-run: like stock
# plugin ops, those leave the running shell untouched.
case "$doc_out" in
  *restarting*) ;;
  *)
    if $layout_changed; then
      echo "· layout changed — restarting shell once to rebuild the strip"
      omarchy-restart-shell >/dev/null 2>&1 || true
    elif $code_changed; then
      echo "· plugin code changed — restarting shell once to reload it"
      omarchy-restart-shell >/dev/null 2>&1 || true
    else
      echo "· layout and code unchanged — shell untouched ( restart it yourself if the bar looks stale: omarchy-restart-shell )"
    fi
    ;;
esac

# Stamp after the decision so a failed run retries the restart next time.
if $MD5_OK && [[ -d $PLUGINS_DIR/$ID ]]; then
  mkdir -p "$STAMP_DIR" 2>/dev/null || true
  md5sum "$PLUGINS_DIR/$ID/manifest.json" "$PLUGINS_DIR/$ID/Indicators.qml" "$PLUGINS_DIR/$ID/Service.qml" "$PLUGINS_DIR/$ID"/indicators/*.qml 2>/dev/null | md5sum | cut -d' ' -f1 > "$STAMP_FILE" 2>/dev/null || true
fi

cat <<EOF

  Done. CLI + shim installed; the plugin itself comes from the store:

    omarchy plugin add https://github.com/tymurbogach/omarchy-sleepwalker.git --enable --yes

  Bar: Laptop indicator inside the strip (same size/style as the other six).
       Click toggles lid ignore; dim when off, full when on.

  Verify:
    $CLI lid on && systemd-inhibit --list | grep -i sleepwalker
    # close lid 10s → panel off, no suspend, no lock (lock opt-in: $CLI lock on)

  Note: if the shell crashes mid-install (known stock Quickshell
  instability on reload storms), wait for its auto-restart and run
  $CLI doctor — the install stays valid.
EOF
