#!/bin/bash
# install.sh — install the Claude 5h-reset notifier as a launchd user agent.
#
#   ./install.sh                       # install, prompt for optional ntfy topic
#   ./install.sh --ntfy-topic NAME     # install with phone push preconfigured
#   ./install.sh --uninstall           # remove agent, plist, and state
set -euo pipefail

LABEL="com.danieldecena.claude-reset-notifier"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$HOME/.claude/reset-notifier"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ "${1:-}" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST_DST"
  rm -rf "$STATE_DIR"
  echo "Uninstalled $LABEL."
  exit 0
fi

NTFY_TOPIC=""
if [ "${1:-}" = "--ntfy-topic" ] && [ -n "${2:-}" ]; then
  NTFY_TOPIC="$2"
elif [ -t 0 ]; then
  suggested="claude-reset-$(head -c4 /dev/urandom | xxd -p)"
  echo "Optional: phone push via ntfy.sh (install the free ntfy app, subscribe to your topic)."
  echo "Topics are public-by-knowledge, so use an unguessable name. Suggested: $suggested"
  read -r -p "ntfy topic (empty = Mac banner only): " NTFY_TOPIC
fi

mkdir -p "$STATE_DIR" "$HOME/Library/LaunchAgents"
cp "$SRC_DIR/check-reset.sh" "$STATE_DIR/check-reset.sh"
chmod +x "$STATE_DIR/check-reset.sh"

if [ -n "$NTFY_TOPIC" ]; then
  printf 'NTFY_TOPIC=%q\nNTFY_SERVER="https://ntfy.sh"\n' "$NTFY_TOPIC" > "$STATE_DIR/config"
  echo "Phone push enabled → topic '$NTFY_TOPIC'."
fi

sed "s|__HOME__|$HOME|g" "$SRC_DIR/$LABEL.plist" > "$PLIST_DST"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
launchctl kickstart "gui/$(id -u)/$LABEL" 2>/dev/null || true

echo "Installed. Checks every 5 min; notifies once, 30 min before each 5h reset."
echo "Dry-run the decision any time:  bash $STATE_DIR/check-reset.sh --dry-run"
