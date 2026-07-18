#!/bin/bash
# test.sh — fixture-driven tests for check-reset.sh. Runs on macOS or Linux;
# no osascript/launchd/network involved (NOTIFY_CMD/PUSH_CMD/NO_API overrides).
set -u

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SRC_DIR/check-reset.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

# Fake notifier: appends "banner <title>" / "push <url>" lines to calls.log.
cat > "$TMP/fake-notify" <<'EOF'
#!/bin/bash
echo "banner $1" >> "$CALLS"
EOF
cat > "$TMP/fake-push" <<'EOF'
#!/bin/bash
echo "push $3" >> "$CALLS"
EOF
chmod +x "$TMP/fake-notify" "$TMP/fake-push"

# run <name> <now> — invokes the script against the current fixture dirs.
run() {
  NOW="$2" FEED_DIR="$FEED" STATE_DIR="$STATE" NO_API=1 \
  NOTIFY_CMD="$TMP/fake-notify" PUSH_CMD="$TMP/fake-push" CALLS="$CALLS" \
  bash "$SCRIPT"
}

# fresh_case <name> — new empty feed/state dirs and calls log.
fresh_case() {
  FEED="$TMP/$1/feed"; STATE="$TMP/$1/state"; CALLS="$TMP/$1/calls.log"
  mkdir -p "$FEED" "$STATE"
  : > "$CALLS"
}

# write_status <resets_at> <pct> — fixture status.json (always "fresh": the
# script compares mtime to NOW, and NOW is pinned near real wall-clock time).
write_status() {
  printf '{"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s}}}' \
    "$2" "$1" > "$FEED/abc123.status.json"
}

check() { # check <name> <expected-calls-line-count>
  got=$(wc -l < "$CALLS" | tr -d ' ')
  if [ "$got" = "$2" ]; then
    PASS=$((PASS + 1)); echo "PASS: $1"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $1 (expected $2 notify calls, got $got)"; cat "$CALLS"
  fi
}

BASE=$(date +%s)

# 1. Inside window → one banner; rerun same window → no repeat.
fresh_case t1
write_status $((BASE + 1200)) 82
run t1 "$BASE"
check "inside window notifies" 1
run t1 "$BASE"
check "same window no repeat" 1
grep -q "banner Claude 5h window resets in 20 min" "$CALLS" \
  && { PASS=$((PASS + 1)); echo "PASS: title has minutes"; } \
  || { FAIL=$((FAIL + 1)); echo "FAIL: title has minutes"; cat "$CALLS"; }

# 2. Outside window (>30 min out) → silent.
fresh_case t2
write_status $((BASE + 7200)) 40
run t2 "$BASE"
check "outside window silent" 0

# 3. resets_at in the past → silent.
fresh_case t3
write_status $((BASE - 60)) 90
run t3 "$BASE"
check "past reset silent" 0

# 4. Stale feed file + NO_API → silent, exit 0.
fresh_case t4
write_status $((BASE + 1200)) 82
touch -d '@100' "$FEED/abc123.status.json" 2>/dev/null \
  || touch -t 202001010000 "$FEED/abc123.status.json"
run t4 "$BASE"; rc=$?
[ "$rc" = 0 ] && { PASS=$((PASS + 1)); echo "PASS: stale exits 0"; } \
  || { FAIL=$((FAIL + 1)); echo "FAIL: stale exits 0 (rc=$rc)"; }
check "stale feed silent" 0

# 5. New window (resets_at differs beyond the 60s drift tolerance) → notifies again.
fresh_case t5
write_status $((BASE + 1200)) 82
run t5 "$BASE"
write_status $((BASE + 1500)) 5            # different window, still inside lead
run t5 "$BASE"
check "new window notifies again" 2

# 6. NTFY_TOPIC configured → banner + push; no config → banner only (covered by t1).
fresh_case t6
printf 'NTFY_TOPIC="my-secret-topic"\n' > "$STATE/config"
write_status $((BASE + 1200)) 82
run t6 "$BASE"
check "ntfy config fires both channels" 2
grep -q "push https://ntfy.sh/my-secret-topic" "$CALLS" \
  && { PASS=$((PASS + 1)); echo "PASS: push hits configured topic"; } \
  || { FAIL=$((FAIL + 1)); echo "FAIL: push hits configured topic"; cat "$CALLS"; }

# 7. Dry run inside window → prints decision, no calls, no stamp.
fresh_case t7
write_status $((BASE + 1200)) 82
out=$(NOW="$BASE" FEED_DIR="$FEED" STATE_DIR="$STATE" NO_API=1 \
      NOTIFY_CMD="$TMP/fake-notify" CALLS="$CALLS" bash "$SCRIPT" --dry-run)
case "$out" in
  "WOULD NOTIFY:"*) PASS=$((PASS + 1)); echo "PASS: dry-run prints decision" ;;
  *) FAIL=$((FAIL + 1)); echo "FAIL: dry-run prints decision (got: $out)" ;;
esac
check "dry-run makes no calls" 0
[ ! -f "$STATE/last-notified" ] && { PASS=$((PASS + 1)); echo "PASS: dry-run leaves no stamp"; } \
  || { FAIL=$((FAIL + 1)); echo "FAIL: dry-run leaves no stamp"; }

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
