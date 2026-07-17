#!/bin/sh
# Claude Code status line — danieldecena
# Reads JSON from stdin (CC statusLine schema), outputs a single status line.
# Layout: [⚠] <project> [branch[*]] <model> [tier] [⚡] [tokens] |
#         <ctx-bar cache-hit [▲] [⧗]> │ <5h-bar reset [cap-eta]> [· 7d-bar day ~Nd [cap-eta] if binding]
# Additions are conditional (shown only when they carry signal) to stay uncluttered.
# Colors: per-model (Opus=magenta, Sonnet=cyan, Haiku=green, Fable=blue)
# Meters: unified 24-bit truecolor smooth gradient, each with its own red-onset
# point (ctx=88%, rate-limits=95%). ⚠ appears when 2+ meters are critical at
# once; ▲ appears when context is climbing fast (not just high).

input=$(cat)

# Extract every field in a single jq pass rather than spawning jq once per
# field — the status line renders often, so subprocess count is the dominant
# cost. Fields are joined with ASCII Unit Separator (0x1F): a *non-whitespace*
# delimiter, so `read` preserves empty fields (tab would collapse consecutive
# separators and shift every field after an empty one). Empty/missing fields
# become empty strings (not "null"), so the downstream `[ -n ... ]` guards
# behave exactly as before.
US=$(printf '\037')
IFS="$US" read -r sid cwd model cws over200k fast_mode sess_tok ctx t_read t_new t_in h5_pct h5_reset d7_pct d7_reset <<EOF
$(echo "$input" | jq -r '[
    .session_id // "",
    (.cwd // .workspace.current_dir // ""),
    (.model.display_name // ""),
    (.context_window.context_window_size // 0),
    (.exceeds_200k_tokens // false),
    (.fast_mode // false),
    ((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)),
    (.context_window.used_percentage // ""),
    (.context_window.current_usage.cache_read_input_tokens // 0),
    (.context_window.current_usage.cache_creation_input_tokens // 0),
    (.context_window.current_usage.input_tokens // 0),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // "")
] | map(tostring) | join("")')
EOF
model="${model%% *}"    # keep just the family name (e.g. "Opus")

# --- menubar feed: dump raw session JSON for the menubar app to read ---
feed="$HOME/.claude/spinnerfeed"
if [ -n "$sid" ]; then
    mkdir -p "$feed"
    # Atomic write (temp + mv) so a concurrent menubar rescan never reads a
    # half-written file.
    sf="$feed/$sid.status.json"
    printf '%s' "$input" > "$sf.tmp.$$" && mv "$sf.tmp.$$" "$sf"
fi

# Integer readings for all three meters, defaulted to 0 so downstream
# comparisons (compound-urgency check) are always safe even when a meter has
# no data yet.
ctx_int=0
h5_int=0
d7_int=0

# ANSI
reset="\033[0m"; dim="\033[2m"; bright="\033[1m"
green="\033[32m"; cyan="\033[36m"; yellow="\033[33m"; red="\033[31m"
magenta="\033[35m"; blue="\033[34m"
bright_yellow="\033[93m"; bright_red="\033[91m"
# Muted gray for "no data yet" placeholders — deliberately not on the
# green→red gradient so it never reads as a real low value. Truecolor to match
# the gradient's color space (was 256-color 238 ≈ this gray).
placeholder="\033[38;2;68;68;68m"

# Glyphs (UTF-8 bytes for printf %b) — block bar. Filled uses the full block
# █, matching the full-cell light-shade empty track so the bar's top edge is
# even (the old lower-3/4 ▆ sat short and jagged the top edge).
BAR_F="\342\226\210" # █ (full block — filled)
BAR_E="\342\226\221" # ░ (light shade — empty track)
CYC="\342\206\273"   # ↻ (cache-hit ratio)
TRI="\342\226\262"   # ▲ (fast-climb trend indicator)
WARN="\342\232\240"  # ⚠ (compound-urgency indicator)
HINT="\342\247\227"  # ⧗ (context nearing compact threshold)
FAST="\342\232\241"  # ⚡ (fast mode on)

# Compute all three meter colors in a SINGLE awk pass. Each meter maps a 0-100
# percentage onto a smooth 24-bit truecolor gradient (green → amber → orange →
# red) with its own red-onset point (ctx escalates at 88, rate limits at 95),
# passed as the second arg to grad(). Batching into one awk invocation avoids
# forking awk once per meter — subprocess count dominates this script's cost.
# Output: three ANSI codes joined by the Unit Separator, read back below.
gradient_triple() {
    awk -v cp="$1" -v hp="$2" -v dp="$3" -v US="$US" '
    function grad(p, e,    norm,i,span,t,r,g,b,dark,ri,gi,bi,
                          stopPos,stopR,stopG,stopB) {
        norm = p * 100.0 / e
        if (norm > 100) norm = 100
        if (norm < 0) norm = 0
        # dataviz skill status palette (references/palette.md): good/warning/serious/critical
        stopPos[0]=0;   stopR[0]=0.047; stopG[0]=0.639; stopB[0]=0.047  # good     #0ca30c
        stopPos[1]=45;  stopR[1]=0.980; stopG[1]=0.698; stopB[1]=0.098  # warning  #fab219
        stopPos[2]=70;  stopR[2]=0.925; stopG[2]=0.514; stopB[2]=0.353  # serious  #ec835a
        stopPos[3]=100; stopR[3]=0.816; stopG[3]=0.231; stopB[3]=0.231  # critical #d03b3b
        r=stopR[3]; g=stopG[3]; b=stopB[3]   # default to critical (norm==100)
        for (i=0; i<3; i++) {
            if (norm >= stopPos[i] && norm <= stopPos[i+1]) {
                span = stopPos[i+1] - stopPos[i]
                t = (span > 0) ? (norm - stopPos[i]) / span : 0
                r = stopR[i] + t * (stopR[i+1] - stopR[i])
                g = stopG[i] + t * (stopG[i+1] - stopG[i])
                b = stopB[i] + t * (stopB[i+1] - stopB[i])
                break
            }
        }
        # Truecolor (24-bit), not the 216-color cube: the cube only has 6 levels
        # per channel, which band visibly once darkened, collapsing distinct
        # high-urgency percentages into the same color. Ghostty/iTerm both
        # render 38;2 natively.
        dark = 0.65  # scale brightness down so the gradient reads as darker, same hues
        ri = int(r * 255 * dark + 0.5); gi = int(g * 255 * dark + 0.5); bi = int(b * 255 * dark + 0.5)
        if (ri > 255) ri = 255; if (gi > 255) gi = 255; if (bi > 255) bi = 255
        return sprintf("\033[38;2;%d;%d;%dm", ri, gi, bi)
    }
    BEGIN { printf "%s%s%s%s%s", grad(cp,88), US, grad(hp,95), US, grad(dp,95) }
    '
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

# Format a unix epoch as local time, portably: BSD/macOS `date -r`, falling
# back to GNU `date -d @epoch` on Linux.
epoch_fmt() {
    date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2"
}

# Format seconds-to-cap as a compact "cap~Nh" / "cap~Nm" tag.
fmt_eta() {
    m=$(( $1 / 60 ))
    if [ "$m" -ge 60 ]; then printf 'cap~%dh' "$(( (m + 30) / 60 ))"
    else printf 'cap~%dm' "$m"; fi
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

# ===== Precompute: single fork where possible =====
# One `date` for the current time, reused by the trend check and the 5h reset
# countdown. Integer meter readings up front so all three gradient colors come
# from a single gradient_triple (one awk fork) instead of one awk per meter.
now=$(date +%s)
[ -n "$ctx" ]    && ctx_int=$(printf '%.0f' "$ctx")
[ -n "$h5_pct" ] && h5_int=$(printf '%.0f' "$h5_pct")
[ -n "$d7_pct" ] && d7_int=$(printf '%.0f' "$d7_pct")

# Prune the feed dir. Nothing else does: every session ever run leaves a
# status.json and two trend anchors here forever.
#
# The last-sweep epoch lives in the stamp's *contents*, not its mtime, so the
# common path reads it with a redirect and compares two integers — both builtin.
# Reading the mtime instead would need a `find -mmin` or `date -r` fork on every
# render, which costs more than the sweep saves. The sweep itself (one `find`,
# hourly, backgrounded) never blocks the render.
#
# Only the suffixes this script writes are named, plus the now-dead .status.txt
# it used to write. emit.sh lives in this directory too, and deleting it kills
# the whole feed silently — the app just reports "No active sessions" forever.
# This must never widen to a bare *.
if [ -n "$sid" ]; then
    gc_stamp="$feed/.gc-stamp"
    last_gc=0
    [ -f "$gc_stamp" ] && read -r last_gc < "$gc_stamp" 2>/dev/null
    case "$last_gc" in *[!0-9]*|"") last_gc=0 ;; esac
    if [ "$(( now - last_gc ))" -ge 3600 ]; then
        printf '%s' "$now" > "$gc_stamp.tmp.$$" && mv "$gc_stamp.tmp.$$" "$gc_stamp"
        find "$feed" -maxdepth 1 -type f -mtime +7 \
            \( -name '*.status.json' -o -name '*.status.txt' \
               -o -name '*.prevctx' -o -name '*.prevlim' \) \
            -delete 2>/dev/null &
    fi
fi
IFS="$US" read -r cc cb cb7 <<EOF
$(gradient_triple "$ctx_int" "$h5_int" "$d7_int")
EOF

# Git context: one rev-parse prints branch (line 1) + repo root (line 2), or
# nothing when cwd isn't a repo. Split the two lines with `read` — a
# newline-pattern parameter expansion (${v%%"$NL"*}) returns empty under macOS
# /bin/sh, so it can't be used here. Dirty is a fast index-vs-worktree diff (no
# untracked-file walk) so it stays quick even in a huge repo like $HOME —
# untracked files deliberately don't count toward the dirty marker.
git_root=""; git_branch=""; git_dirty=""
if [ -n "$cwd" ]; then
    { read -r git_branch; read -r git_root; } <<EOF
$(git -C "$cwd" rev-parse --abbrev-ref HEAD --show-toplevel 2>/dev/null)
EOF
    [ -z "$git_root" ] && git_branch=""   # no root line = not a repo
    if [ -n "$git_root" ]; then
        # One diff against HEAD covers index and worktree together; the separate
        # --cached pass was a second fork asking half the same question.
        # HEAD always resolves here: on an unborn branch rev-parse above emits no
        # toplevel, so git_root is empty and this block never runs.
        git -C "$cwd" diff --quiet HEAD 2>/dev/null || git_dirty="*"
    fi
fi

# Model detail: 1M-context tier tag and a compact count of the current context
# window in tokens. Same quantity the ctx bar shows as a percentage, deliberately
# duplicated: the 200k pricing cliff is an absolute threshold, invisible on a
# 1M-window bar (200k reads as a harmless 20%).
#
# The tier comes from the window size the payload reports, not from an "[1m]"
# substring in the model id. The id's shape is a naming convention that can
# change without notice; the window size is the thing the tag is actually about.
tier=""
[ "${cws:-0}" -gt 200000 ] && tier="1M"
tok_disp=""
if [ "${sess_tok:-0}" -ge 1000 ]; then tok_disp="$(( sess_tok / 1000 ))k"
elif [ "${sess_tok:-0}" -gt 0 ]; then tok_disp="$sess_tok"; fi

# 200k long-context-pricing cliff: on 1M-tier models, requests over 200k input
# tokens bill at a premium (2x in / 1.5x out). Regular models cap at 200k, so
# the marker only carries signal on the 1M tier. tokc defaults to dim (no signal).
#
# Red is driven by the payload's own exceeds_200k_tokens rather than by
# re-deriving the threshold here. The old comparison summed total input AND
# output, which isn't the quantity the cliff is priced on — it billed on input —
# so it could turn red early. The payload states the answer; take it.
# Amber stays hand-rolled: it's an "approaching" warning the payload has no
# equivalent for, and it's advisory rather than a billing fact.
tokc="$dim"
if [ "$tier" = "1M" ] && [ "${sess_tok:-0}" -gt 0 ]; then
    if   [ "$over200k" = "true" ];      then tokc="$bright_red"
    elif [ "$sess_tok" -ge 150000 ];    then tokc="$bright_yellow"; fi
fi

# Burn-rate ETA: keep a rate-limit sample (h5:d7:ts) and re-anchor it only every
# >=120s so the rate is measured over a stable window, not render-to-render
# jitter. Surface a cap-ETA only when we'd reach 100% BEFORE the window resets.
h5_eta=""; d7_eta=""
if [ -n "$sid" ]; then
    limfile="$HOME/.claude/spinnerfeed/$sid.prevlim"
    reanchor=1
    if [ -f "$limfile" ]; then
        IFS=: read -r p_h5 p_d7 p_ts < "$limfile"
        dt=$(( now - p_ts ))
        [ "$dt" -lt 120 ] && reanchor=0
        if [ "$dt" -ge 60 ]; then
            dh=$(( h5_int - p_h5 ))
            if [ "$dh" -gt 0 ] && [ "$h5_int" -ge 20 ] && [ -n "$h5_reset" ]; then
                eta=$(( (100 - h5_int) * dt / dh ))
                [ "$eta" -lt "$(( h5_reset - now ))" ] && h5_eta=$eta
            fi
            dd=$(( d7_int - p_d7 ))
            if [ "$dd" -gt 0 ] && [ "$d7_int" -ge 20 ] && [ -n "$d7_reset" ]; then
                eta=$(( (100 - d7_int) * dt / dd ))
                [ "$eta" -lt "$(( d7_reset - now ))" ] && d7_eta=$eta
            fi
        fi
    fi
    if [ "$reanchor" -eq 1 ]; then
        printf '%s:%s:%s' "$h5_int" "$d7_int" "$now" > "$limfile.tmp.$$" && mv "$limfile.tmp.$$" "$limfile"
    fi
fi

# ===== Row 1: identity (repo-aware project, git branch, model, tokens) =====
# ${x##*/} is basename's whole job here and costs no fork. It differs only for
# trailing slashes and the bare "/" — neither of which git or Claude Code emit
# as a path.
if [ -n "$git_root" ]; then
    reponame="${git_root##*/}"
    if [ "$cwd" != "$git_root" ]; then
        dir_name="$reponame/${cwd##*/}"   # repo root + leaf when nested
    else
        dir_name="$reponame"
    fi
else
    d="${cwd:-$PWD}"
    dir_name="${d##*/}"
fi

mc="$dim"  # default to dim if no model
if [ -n "$model" ]; then
    mc=$(model_color "$model")
    model_name="${mc}${model}${reset}"
    [ -n "$tier" ] && model_name="${model_name} ${dim}${tier}${reset}"
    [ "$fast_mode" = "true" ] && model_name="${model_name} ${bright_yellow}${FAST}${reset}"
else
    model_name=""
fi

# Assemble identity: project [branch[*]] model [tier] [⚡] [tokens] |
ident="${mc}${dir_name}${reset}"
if [ -n "$git_branch" ]; then
    if [ -n "$git_dirty" ]; then
        ident="${ident} ${dim}${git_branch}${reset}${yellow}${git_dirty}${reset}"
    else
        ident="${ident} ${dim}${git_branch}${reset}"
    fi
fi
[ -n "$model_name" ] && ident="${ident} ${model_name}"
[ -n "$tok_disp" ] && ident="${ident} ${tokc}${tok_disp}${reset}"
ident="${ident} ${mc}|${reset}"

# ===== Meters: ctx and rate-limit with progress bars =====
ctx_seg=""
lim_seg=""

if [ -n "$ctx" ]; then
    bar=$(bar10 "$ctx_int")

    # Trend-aware: flag a fast climb even before ctx crosses a hard
    # threshold, by comparing against the previous reading for this session.
    trend_glyph=""
    if [ -n "$sid" ]; then
        prevfile="$HOME/.claude/spinnerfeed/$sid.prevctx"
        if [ -f "$prevfile" ]; then
            # Redirect + read is a builtin; $(cat) would fork a shell and a cat
            # for a single short line.
            read -r prev_data < "$prevfile" 2>/dev/null
            prev_ctx="${prev_data%%:*}"
            prev_time="${prev_data#*:}"
            if [ -n "$prev_ctx" ] && [ "$prev_time" != "$prev_data" ]; then
                dt=$(( now - prev_time ))
                dctx=$(( ctx_int - prev_ctx ))
                if [ "$dt" -gt 0 ] && [ "$dt" -lt 60 ] && [ "$dctx" -ge 10 ]; then
                    trend_glyph=" ${bright_yellow}${TRI}${reset}"
                fi
            fi
        fi
        printf '%s:%s' "$ctx_int" "$now" > "$prevfile.tmp.$$" && mv "$prevfile.tmp.$$" "$prevfile"
    fi

    ctx_seg="${cc}${bar} ${ctx_int}%${reset}${trend_glyph}"

    # cache-hit badge: show only when the hit rate is LOW. A high rate is the
    # normal, healthy case and carries no signal; a low one means the prefix was
    # invalidated and this turn re-paid full input price. Amber under 70, red
    # under 40 (near-total miss — a whole window re-sent).
    turn=$(( t_read + t_new + t_in ))
    if [ "$turn" -gt 0 ]; then
        hit=$(awk -v c="$t_read" -v t="$turn" 'BEGIN{printf "%d", (c*100+t/2)/t}')
        if [ "$hit" -lt 40 ]; then
            ctx_seg="${ctx_seg} ${bright}${bright_red}${CYC}${hit}%${reset}"
        elif [ "$hit" -lt 70 ]; then
            ctx_seg="${ctx_seg} ${bright_yellow}${CYC}${hit}%${reset}"
        fi
    fi

    # compact hint: flag when context nears the compaction zone. Percentage-based
    # (not the literal 120k token rule) so it adapts to the window — 80% of a 1M
    # window is far past 120k, which was a 200k-era threshold.
    [ "$ctx_int" -ge 80 ] && ctx_seg="${ctx_seg} ${bright_yellow}${HINT}${reset}"
else
    # No context data yet (session start / just after /clear): muted gray
    # placeholder so it never reads as a real low value.
    ctx_seg="${placeholder}$(bar10 0) --%${reset}"
fi

# Rate-limit meter: 5h percentage bar and compact reset countdown.
if [ -n "$h5_pct" ]; then
    bar=$(bar10 "$h5_int")
    # Reset right after the % (like the ctx segment) so the gradient color never
    # leaks past this bar — the reset-time sub-branch below may be skipped (e.g.
    # resets_at already in the past), and without a reset here the color would
    # bleed into the next line.
    seg="${cb}${bar} ${h5_int}%${reset}"

    # time until the 5h block resets (compact format: ~Nh or ~Nm, colored by urgency)
    if [ -n "$h5_reset" ]; then
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
    fi

    # burn-rate: if the current pace would exhaust the 5h block before it resets
    [ -n "$h5_eta" ] && seg="${seg} ${red}$(fmt_eta "$h5_eta")${reset}"

    # 7-day bar: only show if it's the binding (larger) constraint
    if [ "$d7_int" -gt "$h5_int" ] && [ "$d7_int" -gt 0 ]; then
        bar7=$(bar10 "$d7_int")
        seg="${seg} ${dim}·${reset} ${cb7}${bar7} ${d7_int}%${reset}"
        # weekly reset: show the calendar day/time it rolls over plus a rounded
        # countdown (e.g. "Mon 3PM ~2d"), dimmed since it's day-scale (no
        # minute-level urgency like the 5h block). Under a day left, fall back to
        # hours so it never reads "~0d".
        if [ -n "$d7_reset" ]; then
            d7_day=$(epoch_fmt "$d7_reset" '%a %-I%p')
            seg="${seg} ${dim}${d7_day}"
            d7_sec=$(( d7_reset - now ))
            if [ "$d7_sec" -gt 0 ]; then
                d7_days=$(( (d7_sec + 43200) / 86400 ))  # round to nearest day
                if [ "$d7_days" -ge 1 ]; then
                    seg="${seg} ~${d7_days}d"
                else
                    seg="${seg} ~$(( (d7_sec + 1800) / 3600 ))h"  # round to nearest hour
                fi
            fi
            seg="${seg}${reset}"
        fi
        # burn-rate: if the current pace would exhaust the 7d block before reset
        [ -n "$d7_eta" ] && seg="${seg} ${red}$(fmt_eta "$d7_eta")${reset}"
    fi

    lim_seg="$seg"
else
    # No rate-limit data yet: placeholder matching the ctx segment.
    lim_seg="${placeholder}$(bar10 0) --%${reset}"
fi

# Compound urgency: if 2+ meters are independently critical at once, that's
# worse than any single bar's color communicates on its own — flag it.
critical=0
[ "$ctx_int" -ge 88 ] && critical=$((critical + 1))
[ "$h5_int" -ge 95 ] && critical=$((critical + 1))
[ "$d7_int" -ge 95 ] && critical=$((critical + 1))
warn_seg=""
if [ "$critical" -ge 2 ]; then
    warn_seg="${bright}${bright_red}${WARN}${reset} "
fi

# Build the meter line: [⚠] project model | ctx-bar % │ session-bar % reset
out="${warn_seg}${ident} ${ctx_seg} ${mc}│${reset} ${lim_seg}"

# Trailing blank line adds vertical spacing between the status line and Claude
# Code's mode indicator (e.g. "auto mode on") rendered directly below it.
printf '%b\n' "$out"
