#!/bin/sh
# Blocking answer hook — lets the menubar app answer a prompt on your behalf.
# Usage: ask.sh question     (PreToolUse, matcher AskUserQuestion)
#        ask.sh permission   (PermissionRequest)
#
# Writes ~/.claude/spinnerfeed/asks/<req>.ask.json, then waits for the app to
# write <req>.answer.json and turns that into the hook's decision JSON.
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
pgrep -x "claude spinner" >/dev/null 2>&1 || exit 0

# A banner has one tap. Fall through to the terminal for the shapes it cannot
# express: several questions at once, or a question that takes several answers.
if [ "$mode" = "question" ]; then
    shape=$(printf '%s' "$input" | jq -r '
        if (.tool_input.questions | length) != 1 then "multi"
        elif (.tool_input.questions[0].multiSelect // false) then "multi"
        else "single" end' 2>/dev/null)
    [ "$shape" = "single" ] || exit 0
fi

mkdir -p "$dir"
now=$(date +%s)
req="$sid-$now-$$"
f="$dir/$req.ask.json"
answer="$dir/$req.answer.json"

cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty')
host="${__CFBundleIdentifier:-${TERM_PROGRAM:-}}"

tmp="$f.tmp.$$"
printf '%s' "$input" | jq -c \
    --arg req "$req" --arg kind "$mode" --arg cwd "$cwd" \
    --arg host "$host" --arg now "$now" \
    '{
        req:        $req,
        kind:       $kind,
        session_id: .session_id,
        cwd:        $cwd,
        host:       $host,
        created:    ($now | tonumber),
        tool_name:  (.tool_name // null),
        tool_input: (.tool_input // null),
        questions:  (.tool_input.questions // null)
    }' > "$tmp" 2>/dev/null && mv "$tmp" "$f" || exit 0

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

if [ "$mode" = "permission" ]; then
    jq -n --arg b "$behavior" \
        '{hookSpecificOutput: {hookEventName: "PermissionRequest",
                               decision: {behavior: $b}}}'
    exit 0
fi

# AskUserQuestion needs allow *paired with* updatedInput — allow alone is not
# enough for it, and the answer has to come back as the original questions array
# plus an answers object keyed on each question's own text.
[ "$behavior" = "allow" ] || exit 0
printf '%s' "$input" | jq -c --argjson reply "$reply" \
    '{hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: {questions: .tool_input.questions,
                       answers: $reply.answers}}}'
exit 0
