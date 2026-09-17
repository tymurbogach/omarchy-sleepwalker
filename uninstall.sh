#!/usr/bin/env bash
# Undoes what install.sh did (CLI + shim + legacy), and clears toggles.
# The plugin itself is removed with: omarchy plugin remove <id>
# (that restores the built-in indicators strip in place, by itself).
#   ./uninstall.sh
set -uo pipefail
export LC_ALL=C  # stable grep/sort classes regardless of user locale

ID="io.github.tymurbogach.sleepwalker"
OLD_ID="io.github.tymurbogach.lid"
CLI="omarchy-sleepwalker"
OLD_CLI="omarchy-lid"
LEGACY_UNITS=("omarchy-sleepwalker-inhibit.service" "omarchy-lid-inhibit.service")
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SHIM="$BIN_DIR/omarchy-system-lid-close"

# Only remove files we can prove are ours: exact known names plus our own
# header line. A foreign file that merely mentions sleepwalker is left alone.
ours() {
  local f="$1" head=""
  [[ -f $1 ]] || return 1
  head=$(head -n 1 "$f" 2>/dev/null || true)
  case "$(basename "$f"):$head" in
    "$CLI:# omarchy-sleepwalker"*) return 0 ;;
    "${CLI}-uninstall:# Undoes what install.sh did"*) return 0 ;;
    "$OLD_CLI:# omarchy-lid"*) return 0 ;;
    "${OLD_CLI}-uninstall:# Undoes what install.sh did"*) return 0 ;;
    "omarchy-system-lid-close:# omarchy-system-lid-close"*) return 0 ;;
  esac
  return 1
}

# Backups are safety, not residue: keep the newest 3, prune the rest.
# mapfile (line-split) so paths with spaces survive; plain $(...) would not.
prune_backups() {
  local base="$1" f
  local -a bak=()
  mapfile -t bak < <(ls -t "$base".bak.* 2>/dev/null || true) || true
  for f in "${bak[@]:3}"; do rm -f "$f"; done
}

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
    if ours "$f" || [[ -L $f && $(basename "$(readlink "$f")") == "$CLI" ]]; then rm -f "$f"; else echo "  leaving foreign $f alone" >&2; fi
  fi
done
if [[ -f $SHIM ]]; then
  if ours "$SHIM"; then rm -f "$SHIM"; else echo "  leaving foreign $SHIM alone" >&2; fi
fi

echo "· removing lid binding override (stock binding takes over again)"
BINDINGS="$HOME/.config/hypr/bindings.lua"
if [[ -f $BINDINGS ]] && grep -q "^-- BEGIN omarchy-sleepwalker" "$BINDINGS"; then
  # Same guard as install: BEGIN without END means an aborted edit — refuse
  # rather than range-deleting to EOF.
  if ! grep -q "^-- END omarchy-sleepwalker$" "$BINDINGS"; then
    echo "warning: stale BEGIN without END in $BINDINGS — leaving it untouched (fix by hand)" >&2
  else
    cp -f "$BINDINGS" "$BINDINGS.bak.$(date +%s).$$"
    prune_backups "$BINDINGS"
    sed -i "/^-- BEGIN omarchy-sleepwalker/,/^-- END omarchy-sleepwalker$/d" "$BINDINGS"
    sed -i -e :a -e '/./!{$d;N;ba' -e '}' "$BINDINGS"
    echo "  lid binding override removed"
  fi
fi

echo "· removing legacy post-update hook"
rm -f "$HOME/.config/omarchy/hooks/post-update.d/sleepwalker"

echo "· clearing toggles (off = gone)"
rm -f "$HOME/.local/state/omarchy/toggles/sleepwalker" "$HOME/.local/state/omarchy/toggles/lid-ignore"
rm -f "$HOME/.local/state/omarchy/toggles/lid-lock"
rm -rf "$HOME/.local/state/omarchy/sleepwalker" 2>/dev/null || true

# Reap crash-orphaned inhibitors (PPID 1): nothing should be held now, and a
# restart alone never kills them. Match our --who string ([r] trick so the
# pattern never matches our own command line).
strays=$(pgrep -f "systemd-inhibit.*--who=Omarchy Sleepwalke[r]" 2>/dev/null || true)
if [[ -n $strays ]]; then
  # shellcheck disable=SC2086
  kill $strays 2>/dev/null || true
  echo "· reaped orphaned inhibitor(s)"
fi

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

# Layout change detection (same as install.sh): restart only if the strip
# actually changed; re-runs leave the running shell untouched like stock.
MD5_OK=false
command -v md5sum >/dev/null 2>&1 && MD5_OK=true
layout_sum_before=""
[[ -f "$HOME/.config/omarchy/shell.json" ]] && $MD5_OK && layout_sum_before=$(md5sum "$HOME/.config/omarchy/shell.json" | cut -d' ' -f1)

# Legacy (<0.2.0) separate-widget slots under either id. Same keep rules as
# install: entries with `items` and bare strings are never stale slots.
if command -v jq >/dev/null 2>&1 && [[ -f "$HOME/.config/omarchy/shell.json" ]]; then
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

# Removing the plugin restores the built-in strip with a copy of OUR entry —
# including "Laptop" in items, which the built-in cannot load. Take it out of
# both ids so this works whether it runs before or after `plugin remove`.
# A present-but-broken `items` (wrong type) loses the key and falls back to
# defaults — same repair direction as install, mirrored for removal.
if command -v jq >/dev/null 2>&1 && [[ -f "$HOME/.config/omarchy/shell.json" ]]; then
  tmp=$(mktemp "$HOME/.config/omarchy/.shell.json.tmp.XXXXXX")
  jq --arg id "$ID" '
    if (.bar.layout | type) == "object" then
      .bar.layout |= with_entries(
        .value |= ((if type == "array" then
          map(
            if type == "object" and ((.id // "") == "omarchy.indicators" or (.id // "") == $id)
            then if (.items | type) == "array"
                 then .items |= map(select(. != "Laptop"))
                 elif has("items") then del(.items)
                 else . end
            else . end
          )
        else . end) // .)
      )
    else . end' \
    "$HOME/.config/omarchy/shell.json" > "$tmp" 2>/dev/null \
    && commit_tmp "$tmp" "$HOME/.config/omarchy/shell.json" || rm -f "$tmp"
fi

# No rescanPlugins here: stock `plugin remove` already rescanned, and the
# conditional restart below supersedes a second storm.

# Same as install: restart once when the layout changed, so a first load
# always rebuilds; items edits alone already propagate through hot-reload.
layout_changed=false
if [[ -f "$HOME/.config/omarchy/shell.json" ]]; then
  if [[ -n $layout_sum_before ]]; then
    $MD5_OK && [[ $(md5sum "$HOME/.config/omarchy/shell.json" | cut -d' ' -f1) != "$layout_sum_before" ]] && layout_changed=true
  else
    layout_changed=true
  fi
fi
if $layout_changed; then
  echo "· layout changed — restarting shell once to rebuild the strip"
  omarchy-restart-shell >/dev/null 2>&1 || true
else
  echo "· layout unchanged — shell untouched"
fi

cat <<EOF
  Removed (CLI, shim, toggles, legacy).
  Lid close is back to stock: suspend.

  To also remove the bar indicator itself:
    omarchy plugin remove $ID
EOF
