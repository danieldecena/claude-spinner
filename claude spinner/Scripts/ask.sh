#!/bin/sh
# Answer hook — lets the menubar app answer a prompt on your behalf.
# Usage: ask.sh question     (PreToolUse, matcher AskUserQuestion)
#        ask.sh permission   (PermissionRequest)
#
# Writes ~/.claude/spinnerfeed/asks/<req>.ask.json. A permission then waits for
# the app to write <req>.answer.json and turns that into the hook's decision
# JSON. A question does not wait: it returns at once so the terminal draws its
# own box, and the app answers by typing the option's digit into that box.
#
# The fallback is the point: on no answer this prints nothing and exits 0, so
# Claude Code shows the ordinary terminal prompt. It must never exit 2 — that
# reads as a deny on PreToolUse, which would turn "you weren't at the notch"
# into "the tool was refused".

mode="$1"
dir="$HOME/.claude/spinnerfeed/asks"

input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -z "$sid" ] && exit 0

# Nobody to answer means nobody to wait for. Without this every tool call would
# stall for the whole deadline whenever the app happens to be closed, which is
# the worst version of this feature.
# $2 exists so the test can point this at a process it starts itself: the guard
# is only trustworthy if the same pgrep call is run once with its condition known
# true and once known false. Deliberately an argument and not an environment
# variable -- settings.json passes exactly one argument, so nothing inherited
# from a parent shell can redirect the guard at a process that is always running
# and turn "app closed, exit fast" into a 300s block on every permission request.
pgrep -x "${2:-claude spinner}" >/dev/null 2>&1 || exit 0

host="${__CFBundleIdentifier:-${TERM_PROGRAM:-}}"

if [ "$mode" = "question" ]; then
    # One digit picks one option. Several questions at once, or a question that
    # takes several answers, stay terminal-only.
    shape=$(printf '%s' "$input" | jq -r '
        if (.tool_input.questions | length) != 1 then "multi"
        elif (.tool_input.questions[0].multiSelect // false) then "multi"
        else "single" end' 2>/dev/null)
    [ "$shape" = "single" ] || exit 0
else
    # A PermissionRequest hook holds the terminal prompt until it returns, so
    # waiting here while you are looking at the terminal means the prompt never
    # appears there. Only route to the app when the session's own terminal is
    # not the frontmost app.
    if [ -n "$host" ]; then
        front=$(lsappinfo info -only bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null \
            | sed -n 's/.*bundleID="\([^"]*\)".*/\1/p')
        [ "$front" = "$host" ] && exit 0
    fi
fi

mkdir -p "$dir"
now=$(date +%s)
req="$sid-$now-$$"
f="$dir/$req.ask.json"
answer="$dir/$req.answer.json"

tmp="$f.tmp.$$"
waits=true
spid=""
if [ "$mode" = "question" ]; then
    # Nothing waits on a question, so its file outlives this hook on purpose; the
    # app drops it once the session's state moves off AskUserQuestion. The pid is
    # the owning `claude` process (same walk as emit.sh), whose pane gets the digit.
    waits=false
    p="$PPID"
    i=0
    while [ "$p" -gt 1 ] && [ "$i" -lt 12 ]; do
        line=$(ps -o ppid=,comm= -p "$p" 2>/dev/null)
        [ -z "$line" ] && break
        ppid=$(printf '%s' "$line" | awk '{print $1}')
        comm=$(printf '%s' "$line" | awk '{$1=""; sub(/^ /,""); print}')
        case "${comm##*/}" in claude) spid="$p"; break ;; esac
        p="$ppid"
        i=$((i + 1))
    done
else
    # Claude Code stops this hook when the prompt is answered in the terminal, and
    # without the trap the ask file outlived it: the app kept a card for a request
    # nothing was waiting on. SIGKILL can't be trapped, so the app also drops any
    # request whose pid (the last field of $req) is gone.
    trap 'rm -f "$f" "$answer" "$tmp"' EXIT
    trap 'exit 0' HUP INT TERM
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty')

printf '%s' "$input" | jq -c \
    --arg req "$req" --arg kind "$mode" --arg cwd "$cwd" \
    --arg host "$host" --arg now "$now" --argjson waits "$waits" --arg spid "$spid" \
    '{
        req:         $req,
        kind:        $kind,
        session_id:  .session_id,
        cwd:         $cwd,
        host:        $host,
        created:     ($now | tonumber),
        waits:       $waits,
        session_pid: (if $spid == "" then null else ($spid | tonumber) end),
        tool_name:   (.tool_name // null),
        tool_input:  (.tool_input // null),
        questions:   (.tool_input.questions // null)
    }' > "$tmp" 2>/dev/null && mv "$tmp" "$f" || { rm -f "$tmp"; exit 0; }

[ "$waits" = true ] || exit 0

# Poll rather than wait on the file: sh has no portable inotify, and a dropped
# notification must still time out cleanly.
deadline=$(( now + ${SPINNER_ASK_TIMEOUT:-300} ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    [ -f "$answer" ] && break
    sleep 0.2
done

if [ ! -f "$answer" ]; then
    rm -f "$f"
    exit 0
fi

reply=$(cat "$answer" 2>/dev/null)
rm -f "$f" "$answer"
behavior=$(printf '%s' "$reply" | jq -r '.behavior // empty' 2>/dev/null)

# "passthrough" is the app saying it saw the ask and is declining to answer it
# (you dismissed the banner, or clicked into the session instead). Same exit as
# a timeout: the terminal prompt takes over.
case "$behavior" in
    allow|deny) ;;
    *) exit 0 ;;
esac

jq -n --arg b "$behavior" \
    '{hookSpecificOutput: {hookEventName: "PermissionRequest",
                           decision: {behavior: $b}}}'
exit 0
