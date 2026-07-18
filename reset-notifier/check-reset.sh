#!/bin/bash
# check-reset.sh — notify 30 minutes before the Claude 5-hour rate-limit reset.
#
# Run periodically (launchd StartInterval 300). Resolves the current 5h window's
# reset time, and when the clock is inside the final LEAD_SECONDS of the window,
# fires a macOS notification (and an ntfy.sh phone push if configured) exactly
# once per window.
#
# Reset-time sources, in order:
#   1. Newest ~/.claude/spinnerfeed/*.status.json (raw Claude Code statusLine
#      payload; .rate_limits.five_hour.resets_at is epoch seconds). Free, but
#      only fresh while a Claude Code session is running.
#   2. API fallback: one max_tokens:1 request to api.anthropic.com using the
#      Claude Code OAuth token from the login keychain; reset time comes back in
#      the anthropic-ratelimit-unified-5h-reset response header (epoch seconds).
#      Utilization header is a 0-1 fraction (the file's used_percentage is 0-100).
#
# Env overrides (for tests / non-mac): FEED_DIR, STATE_DIR, NOW, NO_API=1,
# NOTIFY_CMD (replaces osascript), PUSH_CMD (replaces curl push), LEAD_SECONDS,
# STALE_AFTER. --dry-run prints the decision instead of notifying.

set -u

FEED_DIR="${FEED_DIR:-$HOME/.claude/spinnerfeed}"
STATE_DIR="${STATE_DIR:-$HOME/.claude/reset-notifier}"
LEAD_SECONDS="${LEAD_SECONDS:-1800}"
STALE_AFTER="${STALE_AFTER:-1800}"
NOW="${NOW:-$(date +%s)}"
STAMP="$STATE_DIR/last-notified"
CONFIG="$STATE_DIR/config"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

mkdir -p "$STATE_DIR"

# Optional config: NTFY_TOPIC, NTFY_SERVER.
NTFY_TOPIC=""
NTFY_SERVER="https://ntfy.sh"
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"

# Epoch → local clock string, BSD (macOS) or GNU date.
clock() {
  date -r "$1" +"%-I:%M %p" 2>/dev/null || date -d "@$1" +"%-I:%M %p"
}

# --- Source 1: newest fresh status.json with a future resets_at ---------------
resets_at=""
used_pct=""
newest=""
for f in "$FEED_DIR"/*.status.json; do
  [ -e "$f" ] || continue
  if [ -z "$newest" ] || [ "$f" -nt "$newest" ]; then newest="$f"; fi
done
if [ -n "$newest" ]; then
  # GNU order first: BSD stat rejects -c outright, but GNU stat accepts -f %m
  # "successfully" with filesystem output, so the reverse order misparses.
  mtime=$(stat -c %Y "$newest" 2>/dev/null || stat -f %m "$newest" 2>/dev/null)
  if [ -n "$mtime" ] && [ $((NOW - mtime)) -le "$STALE_AFTER" ]; then
    r=$(jq -r '.rate_limits.five_hour.resets_at // empty' "$newest" 2>/dev/null)
    p=$(jq -r '.rate_limits.five_hour.used_percentage // empty' "$newest" 2>/dev/null)
    r=${r%%.*}
    if [ -n "$r" ] && [ "$r" -gt "$NOW" ] 2>/dev/null; then
      resets_at="$r"
      [ -n "$p" ] && used_pct=$(printf '%.0f' "$p")
    fi
  fi
fi

# --- Source 2: API fallback (mirrors the spinner's UsagePoller) ---------------
if [ -z "$resets_at" ] && [ "${NO_API:-0}" != "1" ]; then
  token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
    | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  if [ -n "$token" ]; then
    headers=$(curl -sS --max-time 15 -o /dev/null -D - \
      -X POST "https://api.anthropic.com/v1/messages" \
      -H "authorization: Bearer $token" \
      -H "anthropic-version: 2023-06-01" \
      -H "anthropic-beta: oauth-2025-04-20" \
      -H "content-type: application/json" \
      -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"."}]}' \
      2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]')
    r=$(printf '%s\n' "$headers" | awk -F': ' '/^anthropic-ratelimit-unified-5h-reset:/ {print $2}')
    u=$(printf '%s\n' "$headers" | awk -F': ' '/^anthropic-ratelimit-unified-5h-utilization:/ {print $2}')
    r=${r%%.*}
    if [ -n "$r" ] && [ "$r" -gt "$NOW" ] 2>/dev/null; then
      resets_at="$r"
      # Header utilization is a 0-1 fraction; scale to percent.
      [ -n "$u" ] && used_pct=$(printf '%.0f' "$(printf '%s * 100\n' "$u" | bc -l 2>/dev/null || echo 0)")
    fi
  fi
fi

if [ -z "$resets_at" ]; then
  [ "$DRY_RUN" = 1 ] && echo "no reset time available (feed stale/missing, API unavailable) — silent"
  exit 0
fi

remaining=$((resets_at - NOW))

if [ "$remaining" -gt "$LEAD_SECONDS" ]; then
  [ "$DRY_RUN" = 1 ] && echo "outside window: resets at $(clock "$resets_at") in $((remaining / 60)) min — silent"
  exit 0
fi

# Dedupe: one notification per window. The file and API report the same reset
# instant with slight drift, so match within 60s rather than exactly.
if [ -f "$STAMP" ]; then
  last=$(cat "$STAMP" 2>/dev/null)
  if [ -n "$last" ] && [ "$last" -eq "$last" ] 2>/dev/null; then
    diff=$((resets_at - last)); [ "$diff" -lt 0 ] && diff=$((-diff))
    if [ "$diff" -le 60 ]; then
      [ "$DRY_RUN" = 1 ] && echo "already notified for window resetting at $(clock "$resets_at") — silent"
      exit 0
    fi
  fi
fi

mins=$(( (remaining + 59) / 60 ))
title="Claude 5h window resets in $mins min"
body="Resets at $(clock "$resets_at")"
[ -n "$used_pct" ] && body="Usage at ${used_pct}% — $body"

if [ "$DRY_RUN" = 1 ]; then
  echo "WOULD NOTIFY: [$title] $body"
  exit 0
fi

notified=1
if [ -n "${NOTIFY_CMD:-}" ]; then
  "$NOTIFY_CMD" "$title" "$body" && notified=0
else
  esc_title=${title//\"/\\\"}
  esc_body=${body//\"/\\\"}
  osascript -e "display notification \"$esc_body\" with title \"$esc_title\"" && notified=0
fi

if [ -n "$NTFY_TOPIC" ]; then
  if [ -n "${PUSH_CMD:-}" ]; then
    "$PUSH_CMD" "$title" "$body" "$NTFY_SERVER/$NTFY_TOPIC" && notified=0
  else
    curl -fsS --max-time 10 \
      -H "Title: $title" \
      -H "Tags: hourglass_flowing_sand" \
      -d "$body" \
      "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null && notified=0
  fi
fi

# Stamp only if at least one channel got through, so a total failure retries
# on the next tick instead of going silent for the window.
[ "$notified" = 0 ] && printf '%s' "$resets_at" > "$STAMP"
exit 0
