#!/bin/sh
# Answer hook — lets the menubar app answer a prompt on your behalf.
# Usage: ask.sh question     (PreToolUse, matcher AskUserQuestion)
#        ask.sh permission   (PermissionRequest)
#
# Writes ~/.claude/spinnerfeed/asks/<req>.ask.json. A permission then waits for
# the app to write <req>.answer.json and turns that into the hook's decision
# JSON. A single question does not wait: it returns at once so the terminal draws
# its own box, and the app answers by typing the option's digit into that box.
# A form (several questions, or one that takes several answers) waits like a
# permission when the terminal is behind, and returns the app's answers.
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

# Whether the session's own terminal is the frontmost app. A hook that waits
# holds the terminal's prompt back until it returns, so waiting while you are
# looking at the terminal means the prompt never appears there.
#
# Unknown counts as front: waiting on a guess holds the prompt back for the whole
# deadline, while answering "front" only costs the terminal drawing its own box.
# TERM_PROGRAM is not a bundle id (tmux sets it to "tmux"), so only
# __CFBundleIdentifier can say which app to compare against.
terminal_is_front() {
    [ -n "${__CFBundleIdentifier:-}" ] || return 0
    front=$(lsappinfo info -only bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null \
        | sed -n 's/.*bundleID="\([^"]*\)".*/\1/p')
    [ -n "$front" ] || return 0
    [ "$front" = "$__CFBundleIdentifier" ]
}

form=false
if [ "$mode" = "question" ]; then
    # One digit picks one option, so a single question never waits: the terminal
    # draws its box and the card types the digit. Several questions at once, or a
    # question that takes several answers, cannot be typed that way. Those wait
    # for the app to send every answer back, but only with the terminal behind.
    shape=$(printf '%s' "$input" | jq -r '
        if (.tool_input.questions | length) < 1 then "none"
        elif (.tool_input.questions | length) > 1 then "form"
        elif (.tool_input.questions[0].multiSelect // false) then "form"
        else "single" end' 2>/dev/null)
    case "$shape" in
        single) ;;
        form) terminal_is_front && exit 0
              form=true ;;
        *) exit 0 ;;
    esac
else
    # A question raises a permission request of its own. Answering that one with
    # Allow/Deny is a card that asks nothing, and while it waits the real box is
    # never drawn. The question path owns AskUserQuestion; this one steps aside.
    tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
    [ "$tool" = "AskUserQuestion" ] && exit 0

    terminal_is_front && exit 0
fi

mkdir -p "$dir"
now=$(date +%s)
req="$sid-$now-$$"
f="$dir/$req.ask.json"
answer="$dir/$req.answer.json"

tmp="$f.tmp.$$"
waits=true
spid=""
if [ "$mode" = "question" ] && [ "$form" = false ]; then
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
timeout="${SPINNER_ASK_TIMEOUT:-300}"
case "$timeout" in ''|*[!0-9]*) timeout=300 ;; esac
deadline=$(( now + timeout ))
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

if [ "$mode" = "question" ]; then
    # Only one answer per question decides the call. Anything less prints
    # nothing, so the terminal box opens instead of a half-answered form
    # skipping it.
    [ "$behavior" = "allow" ] || exit 0
    printf '%s' "$input" | jq -c --argjson reply "$reply" '
        ($reply.answers // {}) as $a
        | select(($a | type) == "object"
                 and ($a | all(.[]; type == "string"))
                 and ([.tool_input.questions[].question] - ($a | keys)) == [])
        | {hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            updatedInput: {questions: .tool_input.questions, answers: $a}}}' 2>/dev/null
    exit 0
fi

jq -n --arg b "$behavior" \
    '{hookSpecificOutput: {hookEventName: "PermissionRequest",
                           decision: {behavior: $b}}}'
exit 0
