#!/bin/sh
# Menubar feed emitter — called by Claude Code lifecycle hooks.
# Usage: emit.sh <EVENT>      (hook JSON arrives on stdin)
# Writes one state file per session: ~/.claude/spinnerfeed/<session_id>.state.json
# Paired with <session_id>.status.json, written by the statusLine script.

event="$1"
dir="$HOME/.claude/spinnerfeed"
mkdir -p "$dir"

input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -z "$sid" ] && exit 0

f="$dir/$sid.state.json"
now=$(date +%s)
cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty')
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
msg=$(printf '%s' "$input" | jq -r '.message // empty')

# turn_start must survive across PreToolUse/PostToolUse within one turn, so carry
# the previous values forward unless this event (re)starts or ends the turn.
# last_seed / last_duration capture the just-finished turn so the app can show
# Claude's grey "Sautéed for 5m 18s" done line until the next prompt.
prev_ts=$(jq -r '.turn_start // empty' "$f" 2>/dev/null)
prev_seed=$(jq -r '.last_seed // empty' "$f" 2>/dev/null)
prev_dur=$(jq -r '.last_duration // empty' "$f" 2>/dev/null)

last_seed="$prev_seed"
last_duration="$prev_dur"

# Host app the session runs in, so the menubar can open the right one on click.
# __CFBundleIdentifier is inherited from the launching GUI app (Claude desktop,
# VS Code, iTerm2, Ghostty, Terminal); TERM_PROGRAM is the terminal fallback.
# Carry the previous value forward if this event's env doesn't expose it.
host="${__CFBundleIdentifier:-${TERM_PROGRAM:-}}"
[ -z "$host" ] && host=$(jq -r '.host // empty' "$f" 2>/dev/null)

# Walk up from this hook to the owning `claude` process and record its pid, so the
# app can prune a session whose process died without firing SessionEnd (e.g. the
# terminal was killed). Match the executable basename exactly — the full path holds
# ".claude/…", which a substring match would false-hit. Carry the previous pid
# forward if the walk comes up empty this event.
pid=""
p="$PPID"
i=0
while [ "$p" -gt 1 ] && [ "$i" -lt 12 ]; do
    line=$(ps -o ppid=,comm= -p "$p" 2>/dev/null)
    [ -z "$line" ] && break
    ppid=$(printf '%s' "$line" | awk '{print $1}')
    comm=$(printf '%s' "$line" | awk '{$1=""; sub(/^ /,""); print}')
    case "${comm##*/}" in claude) pid="$p"; break ;; esac
    p="$ppid"
    i=$((i + 1))
done
[ -z "$pid" ] && pid=$(jq -r '.pid // empty' "$f" 2>/dev/null)

case "$event" in
    SessionStart)     status=idle;      turn_start=""; last_seed=""; last_duration="" ;;
    UserPromptSubmit) status=thinking;  turn_start="$now"; last_seed=""; last_duration="" ;;
    PreToolUse)       status=tool;      turn_start="$prev_ts" ;;
    PostToolUse)      status=thinking;  turn_start="$prev_ts" ;;
    Notification)     status=attention; turn_start="$prev_ts" ;;
    Stop)
        status=idle
        if [ -n "$prev_ts" ]; then
            last_seed="$prev_ts"
            last_duration=$(( now - prev_ts ))
        fi
        turn_start="" ;;
    SessionEnd)       rm -f "$dir/$sid".*; exit 0 ;;
    *) exit 0 ;;
esac

tmp="$f.tmp.$$"
jq -n \
    --arg sid "$sid" --arg status "$status" --arg tool "$tool" \
    --arg cwd "$cwd" --arg msg "$msg" --arg ts "$turn_start" --arg now "$now" \
    --arg ls "$last_seed" --arg ld "$last_duration" --arg host "$host" \
    --arg pid "$pid" \
    '{
        session_id:    $sid,
        status:        $status,
        tool:          $tool,
        cwd:           $cwd,
        message:       $msg,
        host:          $host,
        pid:           (if $pid == "" then null else ($pid | tonumber) end),
        turn_start:    (if $ts == "" then null else ($ts | tonumber) end),
        last_seed:     (if $ls == "" then null else ($ls | tonumber) end),
        last_duration: (if $ld == "" then null else ($ld | tonumber) end),
        updated:       ($now | tonumber)
    }' > "$tmp" 2>/dev/null && mv "$tmp" "$f"

exit 0
