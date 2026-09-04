#!/bin/sh
# Menubar feed emitter — called by Claude Code lifecycle hooks.
# Usage: emit.sh <EVENT>      (hook JSON arrives on stdin)
# Writes one state file per session: ~/.claude/spinnerfeed/<session_id>.state.json
# Paired with <session_id>.status.json, written by the statusLine script.
# Events whose stdin carries agent_id (a subagent) write
# ~/.claude/spinnerfeed/<session_id>.<agent_id>.state.json instead, and never
# touch the parent file.

event="$1"
dir="$HOME/.claude/spinnerfeed"
mkdir -p "$dir"

input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -z "$sid" ] && exit 0

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty')
agent_type=$(printf '%s' "$input" | jq -r '.agent_type // empty')
# Filename-safe. Observed values are hex (`a639953774a9953ac`) and docs
# examples like `agent-abc123`. Anything else is stripped; an empty result
# is treated as a root event so we never write a junk path.
agent_id=$(printf '%s' "$agent_id" | tr -cd 'A-Za-z0-9_-')

if [ -n "$agent_id" ]; then
    parent_sid="$sid"
    f="$dir/$sid.$agent_id.state.json"
else
    parent_sid=""
    f="$dir/$sid.state.json"
fi

now=$(date +%s)
cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty')
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
msg=$(printf '%s' "$input" | jq -r '.message // empty')
# Which KIND of notification. Every Notification event became "attention",
# so a session that merely finished 60s ago (idle_prompt) was indistinguishable
# from one actually blocked on a question — same orange row, same "needs input".
notif=$(printf '%s' "$input" | jq -r '.notification_type // empty')

# turn_start must survive across PreToolUse/PostToolUse within one turn, so carry
# the previous values forward unless this event (re)starts or ends the turn.
# last_seed / last_duration capture the just-finished turn so the app can show
# Claude's grey "Sautéed for 5m 18s" done line until the next prompt.
prev_ts=$(jq -r '.turn_start // empty' "$f" 2>/dev/null)
prev_seed=$(jq -r '.last_seed // empty' "$f" 2>/dev/null)
prev_dur=$(jq -r '.last_duration // empty' "$f" 2>/dev/null)
prev_todo_total=$(jq -r '.todo_total // empty' "$f" 2>/dev/null)
prev_todo_done=$(jq -r '.todo_done // empty' "$f" 2>/dev/null)
prev_agent_type=$(jq -r '.agent_type // empty' "$f" 2>/dev/null)
prev_msg=$(jq -r '.message // empty' "$f" 2>/dev/null)
prev_notif=$(jq -r '.notification_type // empty' "$f" 2>/dev/null)

last_seed="$prev_seed"
last_duration="$prev_dur"
todo_total="$prev_todo_total"
todo_done="$prev_todo_done"
[ -z "$agent_type" ] && agent_type="$prev_agent_type"
# Only the Notification event carries .message, and the PreToolUse that follows
# it lands milliseconds later — without this the attention banner's body was the
# bare project name every time. Cleared where the turn restarts or ends, below.
[ -z "$msg" ] && msg="$prev_msg"
[ -z "$notif" ] && notif="$prev_notif"

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
    SessionStart)     status=idle;      turn_start=""; last_seed=""; last_duration=""; todo_total=""; todo_done=""; msg=""; notif="" ;;
    UserPromptSubmit) status=thinking;  turn_start="$now"; last_seed=""; last_duration=""; msg=""; notif="" ;;
    PreToolUse)       status=tool;      turn_start="$prev_ts" ;;
    PostToolUse)      status=thinking;  turn_start="$prev_ts" ;;
    Notification)     status=attention; turn_start="$prev_ts" ;;
    SubagentStart)
        [ -z "$agent_id" ] && exit 0
        status=thinking; turn_start="$now"; last_seed=""; last_duration=""; todo_total=""; todo_done=""; msg=""; notif="" ;;
    Stop|SubagentStop)
        [ "$event" = "SubagentStop" ] && [ -z "$agent_id" ] && exit 0
        status=idle
        if [ -n "$prev_ts" ]; then
            last_seed="$prev_ts"
            last_duration=$(( now - prev_ts ))
        fi
        turn_start=""; msg=""; notif="" ;;
    SessionEnd)
        if [ -n "$agent_id" ]; then
            rm -f "$dir/$sid.$agent_id.state.json"
        else
            rm -f "$dir/$sid".*
        fi
        exit 0 ;;
    *) exit 0 ;;
esac

if [ "$event" = "PostToolUse" ] && [ "$tool" = "TodoWrite" ]; then
    todos_json=$(printf '%s' "$input" | jq -c '.tool_input.todos // []')
    todo_total=$(printf '%s' "$todos_json" | jq 'length')
    todo_done=$(printf '%s' "$todos_json" | jq '[.[] | select(.status == "completed")] | length')
fi

tmp="$f.tmp.$$"
jq -n \
    --arg sid "$sid" --arg status "$status" --arg tool "$tool" \
    --arg cwd "$cwd" --arg msg "$msg" --arg ts "$turn_start" --arg now "$now" \
    --arg ls "$last_seed" --arg ld "$last_duration" --arg host "$host" \
    --arg pid "$pid" --arg tt "$todo_total" --arg td "$todo_done" \
    --arg psid "$parent_sid" --arg aid "$agent_id" --arg atype "$agent_type" \
    --arg notif "$notif" \
    '{
        session_id:        $sid,
        status:            $status,
        tool:              $tool,
        cwd:               $cwd,
        message:           $msg,
        notification_type: (if $notif == "" then null else $notif end),
        host:              $host,
        pid:               (if $pid == "" then null else ($pid | tonumber) end),
        turn_start:        (if $ts == "" then null else ($ts | tonumber) end),
        todo_total:        (if $tt == "" then null else ($tt | tonumber) end),
        todo_done:         (if $td == "" then null else ($td | tonumber) end),
        last_seed:         (if $ls == "" then null else ($ls | tonumber) end),
        last_duration:     (if $ld == "" then null else ($ld | tonumber) end),
        parent_session_id: (if $psid == "" then null else $psid end),
        agent_id:          (if $aid == "" then null else $aid end),
        agent_type:        (if $atype == "" then null else $atype end),
        updated:           ($now | tonumber)
    }' > "$tmp" 2>/dev/null && mv "$tmp" "$f"

exit 0
