#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TOGGLES="$TMP/toggles" PROC="$TMP/proc" LOG="$TMP/killed"
mkdir -p "$TOGGLES" "$PROC/41" "$PROC/42"
token='sleepwalker-test-token-1234'
printf '41\t%s\n' "$token" > "$TOGGLES/sleepwalker-inhibit.pid"
printf 'systemd-inhibit\0--what=handle-lid-switch\0--who=Omarchy Sleepwalker\0--why=Keep working lid closed\0sleep\0infinity\0' > "$PROC/41/cmdline"
printf 'SLEEPWALKER_INHIBIT_TOKEN=%s\0' "$token" > "$PROC/41/environ"
# This process has a similar argument but no ownership token. It must survive.
printf 'systemd-inhibit\0--who=Omarchy Sleepwalker\0sleep\0infinity\0' > "$PROC/42/cmdline"
printf 'SLEEPWALKER_INHIBIT_TOKEN=outside\0' > "$PROC/42/environ"
cat > "$TMP/kill" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$SLEEPWALKER_KILL_LOG"
EOF
chmod +x "$TMP/kill"
SLEEPWALKER_TOGGLES_DIR="$TOGGLES" SLEEPWALKER_PROC_ROOT="$PROC" \
  SLEEPWALKER_KILL_BIN="$TMP/kill" SLEEPWALKER_KILL_LOG="$LOG" \
  "$HERE/bin/omarchy-sleepwalker-inhibit" --reap
[[ "$(cat "$LOG")" == 41 ]]
[[ ! -e "$TOGGLES/sleepwalker-inhibit.pid" ]]
[[ -r "$PROC/42/cmdline" ]]
echo 'reap tests passed'
