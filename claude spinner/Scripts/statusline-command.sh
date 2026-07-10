#!/bin/sh
# Claude Code status line — danieldecena
# Reads JSON from stdin (CC statusLine schema), outputs a single status line.
# Layout: <project> <model> | <ctx-bar cache-hit> │ <5h-bar reset> [· 7d-bar if binding]
# Colors: per-model (Opus=magenta, Sonnet=cyan, Haiku=green, Fable=blue)
# Cache metrics: hit %, 5h/7d rate limits, reset urgency (red/yellow/dim).

input=$(cat)

# --- menubar feed: dump raw session JSON for the menubar app to read ---
sid=$(echo "$input" | jq -r '.session_id // empty')
if [ -n "$sid" ]; then
    mkdir -p "$HOME/.claude/spinnerfeed"
    # Atomic write (temp + mv) so a concurrent menubar rescan never reads a
    # half-written file.
    sf="$HOME/.claude/spinnerfeed/$sid.status.json"
    printf '%s' "$input" > "$sf.tmp.$$" && mv "$sf.tmp.$$" "$sf"
fi

cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
model="${model%% *}"    # keep just the family name (e.g. "Opus")
ctx=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
t_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
t_new=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
t_in=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
h5_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
h5_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
d7_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# ANSI
reset="\033[0m"; dim="\033[2m"; bright="\033[1m"
green="\033[32m"; cyan="\033[36m"; yellow="\033[33m"; red="\033[31m"
magenta="\033[35m"; blue="\033[34m"
bright_green="\033[92m"; bright_yellow="\033[93m"; bright_red="\033[91m"

# Glyphs (UTF-8 bytes for printf %b) — block bar, matching the menubar app.
BAR_F="\342\226\210" # █ (full block)
BAR_E="\342\226\221" # ░ (light shade)
CYC="\342\206\273"   # ↻ (cache-hit ratio)

# Pick a color for a 0-100 percentage: gradient from green → yellow → red.
pct_color() {
    if   [ "$1" -ge 95 ]; then printf '%s' "$bright_red"
    elif [ "$1" -ge 85 ]; then printf '%s' "$red"
    elif [ "$1" -ge 75 ]; then printf '%s' "$bright_yellow"
    elif [ "$1" -ge 60 ]; then printf '%s' "$yellow"
    elif [ "$1" -ge 40 ]; then printf '%s' "$cyan"
    elif [ "$1" -ge 20 ]; then printf '%s' "$green"
    else printf '%s' "$bright_green"
    fi
}

# Pick a color based on minutes remaining (urgency, not percentage).
urgency_color() {
    if   [ "$1" -lt 5 ];  then printf '%s' "$red"
    elif [ "$1" -lt 15 ]; then printf '%s' "$yellow"
    else printf '%s' "$dim"
    fi
}

# Pick a color for each model family.
model_color() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        opus*) printf '%s' "$magenta" ;;
        sonnet*) printf '%s' "$cyan" ;;
        haiku*) printf '%s' "$green" ;;
        fable*) printf '%s' "$blue" ;;
        *) printf '%s' "$dim" ;;
    esac
}

# Render a 10-segment progress bar for a 0-100 percentage.
bar10() {
    fill=$(( ($1 * 10 + 50) / 100 )); [ "$fill" -gt 10 ] && fill=10
    b=""; i=0
    while [ "$i" -lt 10 ]; do
        if [ "$i" -lt "$fill" ]; then b="${b}${BAR_F}"; else b="${b}${BAR_E}"; fi
        i=$((i + 1))
    done
    printf '%s' "$b"
}

# ===== Row 1: identity (project name and model) =====
dir_name="$(basename "${cwd:-$PWD}")"
mc="$dim"  # default to dim if no model
if [ -n "$model" ]; then
    mc=$(model_color "$model")
    model_name="${mc}${model}${reset}"
else
    model_name=""
fi

# ===== Meters: ctx and rate-limit with progress bars =====
ctx_seg=""
lim_seg=""

if [ -n "$ctx" ]; then
    ctx_int=$(printf '%.0f' "$ctx")
    # ctx warns red earlier (88%) than the rate-limit bars — running out of
    # context mid-task is disruptive, so flag it before it's fully gone.
    if   [ "$ctx_int" -ge 95 ]; then cc="$bright_red"
    elif [ "$ctx_int" -ge 88 ]; then cc="$red"
    elif [ "$ctx_int" -ge 75 ]; then cc="$bright_yellow"
    elif [ "$ctx_int" -ge 65 ]; then cc="$yellow"
    elif [ "$ctx_int" -ge 45 ]; then cc="$cyan"
    elif [ "$ctx_int" -ge 25 ]; then cc="$green"
    else cc="$bright_green"
    fi
    bar=$(bar10 "$ctx_int")
    ctx_seg="${cc}${bar} ${ctx_int}%${reset}"

    # cache-hit badge: show only if it differs >10% from ctx % (signal, not noise)
    turn=$(( t_read + t_new + t_in ))
    if [ "$turn" -gt 0 ]; then
        hit=$(awk -v c="$t_read" -v t="$turn" 'BEGIN{printf "%d", (c*100+t/2)/t}')
        diff=$(( hit > ctx_int ? hit - ctx_int : ctx_int - hit ))
        if [ "$diff" -gt 10 ]; then
            ctx_seg="${ctx_seg} ${bright}${CYC}${hit}%${reset}"
        fi
    fi
else
    # No context data yet (session start / just after /clear): dim placeholder
    # so the line reads as loading rather than looking broken/empty.
    ctx_seg="${dim}$(bar10 0) --%${reset}"
fi

# Rate-limit meter: 5h percentage bar and compact reset countdown.
if [ -n "$h5_pct" ]; then
    h5_int=$(printf '%.0f' "$h5_pct")
    cb=$(pct_color "$h5_int")
    bar=$(bar10 "$h5_int")
    seg="${cb}${bar} ${h5_int}%"

    # Compute 7-day if available (for binding-only display below)
    d7_int=0
    if [ -n "$d7_pct" ]; then
        d7_int=$(printf '%.0f' "$d7_pct")
    fi

    # time until the 5h block resets (compact format: ~Nh or ~Nm, colored by urgency)
    if [ -n "$h5_reset" ]; then
        now=$(date +%s)
        rem=$(( (h5_reset - now) / 60 ))
        if [ "$rem" -gt 0 ]; then
            uc=$(urgency_color "$rem")
            if [ "$rem" -ge 60 ]; then
                h=$(( (rem + 30) / 60 ))  # round to nearest hour
                seg="${seg} ${uc}~${h}h${reset}"
            else
                seg="${seg} ${uc}~${rem}m${reset}"
            fi
        fi
    else
        seg="${seg}${reset}"
    fi

    # 7-day bar: only show if it's the binding (larger) constraint
    if [ "$d7_int" -gt "$h5_int" ] && [ "$d7_int" -gt 0 ]; then
        cb7=$(pct_color "$d7_int")
        bar7=$(bar10 "$d7_int")
        seg="${seg} ${dim}·${reset} ${cb7}${bar7} ${d7_int}%${reset}"
    fi

    lim_seg="$seg"
else
    # No rate-limit data yet: dim placeholder matching the ctx segment.
    lim_seg="${dim}$(bar10 0) --%${reset}"
fi

# Build the meter line: project model | ctx-bar % │ session-bar % reset
out="${mc}${dir_name}${reset} ${model_name} ${mc}|${reset} ${ctx_seg} ${mc}│${reset} ${lim_seg}"

# Write plain-text (ANSI-stripped) version to menubar text feed
if [ -n "$sid" ]; then
    out_plain=$(printf '%b' "$out" | sed 's/\x1b\[[0-9;]*m//g')
    printf '%s' "$out_plain" > "$HOME/.claude/spinnerfeed/$sid.status.txt"
fi

printf '%b' "$out"
