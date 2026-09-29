# STATUS

## Confirmed working

- The window detail pane carries the whole statusLine payload, not the eight
  fields the app used to decode: spend (labelled api-equivalent, since nothing
  here is billed on a Max plan), wall vs API time, lines changed, context and
  window size, prompt-cache hit ratio and warmth, effort, thinking, model id,
  Claude Code version and repo. An overview strip totals them and leads with the
  5h/7d rate-limit windows, which are the only numbers that can actually stop a
  Max session.
- `TranscriptReader` shows what a session is *doing* — the last thing Claude
  said, what you last asked, and what it just ran — read from the last 256KB of
  its own transcript. Observed on screen 2026-09-04 against a live 4.7MB file.
- The Context section carries a meter and a chart, both scaled to the window so
  they mean the same thing: how close this session is to needing a compact, and
  how fast it got there. Behind them is the app's first per-session time series
  -- `contextHistory`, sampled on each rescan, only when the count actually
  moves, capped at 240 points and dropped when the session goes away. Both
  observed on screen 2026-09-15 against `fix-dock-passwords-icon` (24 samples,
  98,834 -> 160,939 on a 1M window): the meter fills ~16% and the chart draws a
  1.5pt line with its tinted area fill, flat along the floor. Flat is correct
  there, not a failure -- 0.099 to 0.157 of a 1M window is a 1.6pt rise inside a
  28pt frame. What separates "flat" from "not drawing" is the *absence* of the
  `no context history yet` fallback text, which is what `ContextTrend` renders
  when `unitPoints` returns nil.
- Six session actions under the reply field: Interrupt, Compact and Clear
  through the tmux pane, Reveal folder / Open transcript / Copy session id
  locally. Each is enabled or carries a stated reason.
- The Git card states what the repo can do rather than a row of greyed
  buttons. An action with a finished answer ("already in sync", "#3 is
  already open") is not drawn at all; one whose state could not be read stays
  on screen greyed with its reason printed underneath. Five rows -- branch,
  changes, remote, pr, checks -- each carry their own age, because the local
  half is read every 5s and the network half every 90s, and Refresh forces
  the network half early. Merge runs `gh pr merge --squash --delete-branch`
  and is offered only when gh reports the PR mergeable, reviewed and passing.

- Notifications reach you. Authorization was denied for the app's whole life
  until 2026-09-15; granted, a posted ask clears the entitlement check, runs the
  full `usernotificationsd` pipeline and lands in `destinations=[notices]`. Both
  surfaces carry the denied notice for the case where it is off again, and the
  read refreshes whenever the app becomes active.
- Questions and permission prompts can be answered without going back to the
  terminal. `ask.sh` blocks on `PreToolUse`/`AskUserQuestion` and
  `PermissionRequest`, the app renders the request, and the answer returns as
  `allow` + `updatedInput` (or `decision{behavior}`). Proven end to end on
  2026-09-04: a click in the window produced
  `{"permissionDecision":"allow","updatedInput":{...,"answers":{"Which surface
  should own the reply field?":"Window only"}}}` from a live hook.
- The window is its own UI now — sidebar grouped Needs you / Working / Idle, and
  a detail pane carrying the full question with every option *and its
  description*, session stats, subagents, and a reply field. Observed on screen
  2026-09-04.

- Menu-bar panel tracks live Claude Code sessions via `~/.claude/spinnerfeed/`
  feed files (hooks + statusLine in `~/.claude/settings.json`).
- The app survives macOS refusing to place the status item (a full menu bar,
  which a notched display reaches early). It detects the unplaced item by frame,
  opens the panel as a real window titled with the live readout, and hangs the
  full settings menu off a "Spinner" main-menu submenu so nothing is stranded
  behind an icon that isn't there.   Both placed and unplaced observed live
  2026-08-12.
- First-run one-click installer (Install hooks button) writes the scripts and
  back-up-then-merges the hooks/statusLine into settings.json.
- CI actually runs now: 221 unit tests green on a self-hosted macOS runner
  registered 2026-09-15 (`~/Tools/actions-runner`, kept alive by the LaunchAgent
  `svc.sh install` wrote). Before that no runner had ever been registered, so
  every run queued until GitHub cancelled it at the 24h await-runner limit.
  GitHub-hosted images are not an option on this account: they refuse jobs
  outright over a billing block. See the 2026-09-15 decision log.
- Both session lists group by project, with anything blocked on a person pinned
  above. Section headers carry the session count and the section's context
  added up (untinted -- separate windows, so a summed 210k is not one session's
  210k). Sidebar observed on screen 2026-09-15.
- Which surface the app presents is a choice, not luck. `Show in` (Menu bar /
  Window, persisted, default Menu bar) sits in the settings menu; Window creates
  no status item at all, Menu bar keeps the automatic window fallback.
- Row names get every point the model and status columns don't need, and the
  columns are sized once per panel so they still align. Verified on screen:
  `compact-vscode-density`, `statusline-drift-perf` and `scan-jobs-task-runner`
  all render in full at panelWidth 470, where they truncated at 424.
- Panel rows carry the session's own name (`session_name` from status.json,
  falling back to the directory), its context token count banded on absolute
  usage (100k/150k/200k), and sort heaviest-first within each status band.
  The header totals context across all sessions. Legible in both appearances.
- Each row carries a 10-box `□□□□□□□□□□ --%` task-completion bar (TodoWrite
  counts via `emit.sh`), with the session's status/activity text beside it on
  a second line. Verified on screen across several rebuilds.
- Subagent sessions nest under their parent as indented 2-line rows (todo
  bar + that child's own tool/status). Child hook events write
  `<parent>.<agent_id>.state.json` and no longer overwrite the parent file.
  Verified on screen against a live parent+Explore; 95 unit tests green.
- The standalone window (right-click icon → Open Window) pins its content to
  the top and shrinks an oversized/stale remembered frame back to
  panelWidth × panelDefaultHeight on open, on whichever axis overran.
  Verified on screen: a window carrying a leftover 573×1900ish remembered
  frame from earlier automated testing now opens flush, no dead space above,
  below, or past the row content.

- Clicking a row focuses the editor the session actually runs in — including
  Zed and any editor not in `hostBundleIDs`, which previously opened a stray
  Ghostty window (bug-130). **Verified by hand 2026-07-17**: clicking the Zed
  row focused zed and Ghostty never launched. The panel *can* be driven from an
  agent session after all, when the host app has Accessibility permission.
- The panel's gauges and row layout are verified on screen, not just in tests:
  7d at 9% draws a visible sliver, `chg +52%` fills ~72% of its track rather
  than saturating, and `review code and ui` / `needs input` render in full.
- A long tool name no longer draws two ellipses. `RowLayout.fit` pre-truncates
  the status label to its column so SwiftUI never adds its own tail `…` beside
  the animated dots. Verified on screen with a throwaway 51-char MCP tool
  (`running mcp__claude_ai_Google_Calendar__list_events`): the cut row's trailing
  marker is identical to the un-truncatable `running bash…` / `thinking…` rows
  (dots only). bug-201.
- `.wolf/buglog.json` no longer races between concurrent sessions. The OpenWolf
  auto-logger (`.wolf/hooks/post-write.js`) now serializes its read-modify-write
  behind an exclusive lockfile and mints ids as `max+1` (strictly above every id
  present). Proven with a barrier-synchronized 20-way race: the old
  `length+1`/no-lock pattern lost 15 of 20 writes; the locked version kept 20/20
  with unique ids. bug-200. (The 10 *historical* duplicate ids are left as-is —
  they're referenced in commits/STATUS/cerebrum, so renumbering would break refs.)

## Known broken

- Nothing known broken.

## Scope / by-design limitations

- **Captures Claude Code sessions only** — CLI (terminal/VS Code/Ghostty/iTerm)
  and the Claude **Desktop app's Code tab** (same engine, fires the same
  settings.json hooks). It does NOT capture the Desktop app's **Chat tab** or
  claude.ai web chat: those run no lifecycle hooks and no statusLine, and there
  is no supported API for their live turn state. Wiring to Desktop internals
  (`~/Library/Logs/Claude/main.log`, `~/Library/Application Support/Claude/`,
  or accessibility scraping) was considered and rejected as brittle. To see a
  desktop session in the spinner, use the Code tab.

## Next Up

The palette is the current work, and the identity colours closed its last
gap. What is left is two hand-checks, both `[you]` in `TASKS.md`: the
placed-status-item policy round-trip (not scriptable, see the 2026-08-12
decision log), and a context line with a visible slope. Two runtime cases stay
unobserved and are named in the decision log: the unreadable-remote rendering
from the Git work, and three of the four identity hues -- every session on this
machine is Opus in a desktop app, so only purple has been seen. The panel's
project sections were observed on screen 2026-09-28 and are no longer open.

The app ships as a locally-built, ad-hoc-signed `.app` via `run.sh`.

## Decision log

### 2026-09-28 (the palette work, and both appearances looked at)

- The light theme was a tinted dark theme. Measured against the app's real
  grounds -- `#ffffff` light and `#1e1f20` dark, sampled from the running app
  rather than assumed -- all 18 colours fell short of the 4.5:1 body text needs
  in light and 11 of 18 missed even the 3:1 a graphical mark needs, while dark
  passed everywhere at 5.79 or better. The pattern is light values nudged down
  from the dark ones instead of derived for a white surface.
- The largest single fault was not the accent but `claudeDim`, the accent at
  65%, which composited to 2.29:1 on white and carried about half the window's
  text. A neutral grey would have passed and cost the app its warmth; the hue
  was darkened instead, so the label/value pair the mono columns are built on
  survives. Labels now draw in `label`; `claudeDim` is left for the two
  translucent container fills, which owe nothing to the text threshold.
- The accent then moved to the Decena Apps design system's clay, shared with
  wa-fish-map and the footage library, which clears 4.5:1 where the old
  `#C26B3D` measured 3.84.
- Observed 2026-09-28 at 2088px, both appearances, by capturing the panel
  window by id (`screencapture -o -l`) rather than by rect -- a rect capture
  picked up another app's window sitting over it, and that was caught by
  looking at the image, not by the exit code. Dark: labels, section heads and
  both slice 2 strings read in clay against the values' white. Light: the same
  pair separates, labels a dark clay on white. The appearance toggle itself was
  confirmed by sampling the background (255,255,255 in light; 38,38,40 before
  and after), not by trusting the `System Events` call -- two per-app overrides
  failed silently on 2026-09-20 and the same class of mistake was available here.
- Not verified on screen: the sole remaining check is numeric. The ratio maths
  is pinned against pairs the WCAG spec fixes (21:1, 1:1, and `#767676`'s
  canonical 4.5) so the threshold assertions cannot both pass on a function
  returning 21 for everything, and each threshold test was mutation-verified.

### 2026-09-28 (the identity colours, re-hued rather than darkened)

- The eight `model-*` / `host-*` colours were the palette's last failures, 2.31:1
  to 3.41:1 in light. They are text, and the host tag's real ground is its own
  hue at 16% over the pane, not the pane -- a stricter surface, so that composite
  is what both the derivation and the tests measure. The test reads the 16% from
  `Ink.chipTint`, the same constant `MenuContentView` fills the chip with, so it
  cannot measure a number the app does not draw.
- Holding hue and darkening for a white ground was tried first and abandoned: it
  put Haiku at `#438443`, 12/255 from the re-derived `usageGreen`, and VS Code at
  `#1d66be`, 17/255 from `attention`. That is exactly the collision a status
  palette exists to prevent, and no test would have caught it. Daniel chose the
  re-hue.
- Four hues now, each shared by a model and the host it sits beside: purple 275
  (Opus / app), cyan 198 (Sonnet / web), jade 163 (Haiku / trm), indigo 244
  (Fable / VS Code). The column and the printed word say which of the two a tint
  belongs to, so the colour does not have to. Nearest identity-to-status pair is
  48/255 (jade to `usageGreen`); nearest identity pair 38 (purple to indigo, in
  dark). The model hues no longer match the statusLine's green and blue -- that
  is the price, taken deliberately.
- Both new tests were proved able to fail, with the mutation asserted applied
  before each run and reverted after: the old green fails contrast at 2.10, and
  the darkened old hue fails separation, naming "jade light sits on usageGreen"
  at 12.3. 234 tests, 0 failures.
- Observed on screen 2026-09-28 in both appearances. The panel is the surface
  that draws these, and this machine runs `surface = window`, which creates no
  status item at all -- so the preference was flipped to `menuBar`, the status
  item pressed through `AXExtrasMenuBar`, the popover captured by window id, and
  the preference put back to `window` afterwards. Sampled at the glyph core:
  light `#9859D0` against `#8F39CD` pure, dark `#BE9BE1` against `#B983E0` --
  both the antialiased blend of the intended value toward the ground, and the
  two are plainly different values, which is what rules out one appearance's
  branch being served to the other.
- Not observed: only purple appeared. Every session on screen was Opus in a
  desktop app, so cyan, jade and indigo are asserted numerically and drawn from
  the same four constants, but have not been seen. The light ground was also not
  white -- the popover is translucent material over the desktop and measured
  mid-grey, so the 4.5:1 figures remain the optimistic ones, as the README says.

### 2026-09-20 (dark appearance looked at; slice 3 is smaller than written)

- Found: the unchecked `Fix dark-copy text still bound to Light colors` is a
  **Figma** fault, not a Swift one. It sits inside the Figma task block, and the
  2026-09-16 entry below already records it: the dark screen copies show
  near-black text on labels inside component instances, the rebind having missed
  per-range text fills. Every colour in `claude_spinnerApp.swift:672-745` goes
  through `dynamic(light:dark:)`. So slice 3 is not blocked on Swift colour
  bindings, as the plan's open question assumed. The real consequence is
  narrower: the Figma dark frames cannot serve as slice 3's dark reference, so
  that slice is checked on screen instead of against the spec.
- Observed 2026-09-20 06:01 in dark: no near-black text anywhere in the app --
  labels, values, Git rows, empty states and both slice 2 strings all read
  correctly. Two per-app appearance overrides were tried first and both silently
  failed (`AppleInterfaceStyle` in the app's domain, then in the argument
  domain); the first screenshots were still light. Caught by sampling the
  background rather than trusting the override -- RGB(255,255,255) against the
  RGB(30,31,32) of the real dark run. The system appearance was toggled with
  permission and restored, both confirmed by reading the setting back.
- Found, and it shrinks slice 3: the plan's problem 5 says "Reveal and Copy carry
  borders; Interrupt, Compact, Clear and Open transcript do not" -- six buttons
  in two treatments. On this build all six carry the same capsule, and what
  separates them is the enabled/disabled fill, which is already the
  one-class-two-states outcome slice 3 was written to produce. The plan was
  written from a screenshot and that reading does not survive the running app.
  What is real is the truncation: `Reveal fol…`, `Open trans…` and `Copy sessi…`
  all clip on a window with spare width. Treat the remaining claim -- "disabled
  is signalled by text colour alone" -- as unverified until looked at.

### 2026-09-20 (UI pass slice 2: the two contradicting sentences)

Branch `design-system-pass-2026-09-20`, off `main` at 6895886. The branch named
in the request did not exist -- the ten Figma-pass commits all went to `main`
directly -- so it was created rather than assumed.

- Decided: the overview strip's `— of 5h` becomes `no current 5h reading`
  (c5d615a). The dash was not only a broken sentence: it was tinted
  `usageTint(fiveHour ?? 0)`, so a window that had never reported drew in the
  green of untouched headroom. `StatFormat.usagePercent` now separates unknown
  from a real zero, mirroring `lines(added:removed:)` beside it.
- Found on screen, and it changed the copy: this machine has no live 5h reading,
  so the empty branch actually drew -- and the first wording, `no usage data yet`
  (chosen to match the panel), sat directly above a sparkline plotting 240
  retained samples peaking at 37%. That is the same fault the slice exists to
  remove, made worse: the old dash was ambiguous, an explicit sentence is a
  claim. The string is scoped to the live window instead. The panel keeps its own
  wording, where no history is drawn beside it.
- Decided: the Git card's `Nothing to do here right now.` becomes
  `no actions available`. The condition is `offered.isEmpty` -- the action-button
  list -- which never consults the rows above, so five populated rows could sit
  under a sentence saying there was nothing here. The condition is untouched;
  only the scope and wording were wrong. It was also the app's only
  sentence-cased empty state.
- Observed 2026-09-20 05:39, both against the running build: the `home` session
  (main, clean, in sync, 47 untracked, no PR -- the state that settles every
  action) draws `no actions available` under four populated rows, and the
  overview strip draws `no current 5h reading` above the sparkline. Neither was
  taken from a build log; the build's own `Build Succeeded` line is the wrapper's
  word, so the product was confirmed by mtime and the rendering by screenshot.
- Verified the new test can fail: `usagePercent` mutated to reject zero fails at
  the `a real reading of zero` assertion (rc=65), and passes once reverted. The
  nil case alone would have been satisfied by a formatter returning nil for
  everything. 229 tests, 0 failures.

- Found, not fixed -- for slice 5: `OverviewStrip` derives its percentages from
  `FeedWatcher.Overview`, which reads live session feeds only, while
  `usageFiveHourPct` / `usageSevenDayPct` resolve poll -> session -> cache. The
  cache currently holds 7d = 8.05% that the window therefore cannot show, so the
  menu bar and the window can disagree about the same account-wide number. Slice
  5 already owns the window's rate-limit panels and reset times (`Overview`
  carries no reset at all), so it belongs there rather than widening this slice.

### 2026-09-16 (Swift aligned to the spec; stale ask cards fixed)
- Decided: the five Swift slices follow the palette and type scale in
  `~/.claude/plans/iridescent-tinkering-frog.md`, since the Figma file itself was
  unreadable (the Starter cap still refused the first call this session). State
  colors cc96705, one Notice style 30e2514, sidebar glyph plus spoken status
  e0313c4, type scale 63b3383, git/stat empty states 741259c. All 223+ tests pass
  after each one; none of the new visuals has been looked at on screen yet.
- Decided: stale ask cards get two fixes (64752a0). ask.sh traps EXIT/HUP/INT/TERM,
  and the inbox drops asks whose hook pid is gone, rescanning every 5s because a
  killed process makes no directory event. The script test fails with the traps
  stripped and passes with them.
- Found: the installed `~/.claude/spinnerfeed/ask.sh` had a `$2` pgrep override
  (2026-09-15) that was in no commit. Daniel chose to merge it: ported to the repo
  (8aeb629), installed, synced in `~/.claude` (72c98ab). XCTest cannot see
  processes through pgrep, so that gate was checked from a shell both ways.

### 2026-09-16 (UI review; unified Figma spec, cut short by the Starter limit)
- Decided: Figma is the spec the Swift UI gets fixed to, not a mirror of it. A
  review found the panel and window disagree on every state color (needs-you blue
  vs red, working orange vs system accent, idle grey vs dim orange), one red
  covering rate limits, setup, notifications-off and asks, nine Menlo sizes, about
  26 hardcoded RGBs with duplicates, color-only sidebar status, and blank
  loading and error states. The spec fixes each; the file's "Code vs spec" table
  lists them with file:line.
- Decided: color only for state and usage. Model names go plain, host chips go
  neutral, the spinner glyph replaces the sidebar dot, every detail group is a
  card, and errors get their own notice style.
- File: https://www.figma.com/design/atOtbz9apX1vGrBVOARRMs (Personal drafts).
  Pages Tokens, Components, Screens. Light and Dark variable collections, 16
  component sets, panel (sessions, empty, setup) and window in light, dark copies,
  conflict log.
- Starter plan limits hit, each costing a call: no Menlo or SF Mono in Figma's
  cloud renderer (JetBrains Mono stands in; Swift keeps Menlo), 3 pages per file,
  1 mode per collection (so Light and Dark are separate collections, and dark
  screens are copies rebound by name), and SF Symbols render 0pt wide (plain
  glyphs stand in). The MCP refused call 11: the cap arrived after 10 calls,
  not the documented "up to 20".
- Known broken in the file: the dark copies still show near-black text on some
  labels inside component instances (row names, ask prompt, notice text, stat
  values). The swap reported 68 swapped / 0 missed, so the unswapped fills
  likely sit in per-range text fills it never read. Unverified; the fix script
  was the refused call.
- Also found: a stale ask card persists when ask.sh is killed before its own
  cleanup (no exit trap; the app never checks the pid). Tracked in TASKS.md.

### 2026-09-15 (notifications granted; the feature rings for the first time)
- Daniel allowed notifications in System Settings. The on-activation re-read
  then logged `authorization re-read status=2 allowed=1` -- the known-GOOD input
  the earlier entry said was missing. Until now every recorded read was a
  denial, which a detector that always reads denied would have produced
  identically; this is the first time the pair exists.
- It needed an activation to fire, and none had happened since the switch was
  flipped: the read still said `status=1` four minutes after. That is the design
  working, not a lag -- but it means the notice clears when you next come back to
  the app, not the instant you grant.
- Proved the whole path, not just the flag. Wrote a real ask file into
  `spinnerfeed/asks/`; `usernotificationsd` logged `Entitlement check success`,
  ran the pipeline to `NotificationRequest: Completed`, and filed it under
  `destinations=[notices]`. Daniel then pressed a button on the banner and the
  app wrote `{"behavior":"allow","answers":{"Did this banner reach you?":"Yes"}}`.
  Banner -> button -> answer file, which is the feature.
- Not observed, and worth saying: the notice *disappearing* from the window.
  Hearthstone held the screen full-screen on its own Space, which also shrank
  the window's `CGWindowList` entry to 80x137 while Accessibility still read
  996x1106 -- so no capture of that window could be trusted. The flag it renders
  from is confirmed `true`; the pixels are not.

### 2026-09-15 (the notice reaches both surfaces)
- Fixed the first of the two surfacing gaps found earlier today.
  `NotificationsNotice` is its own view now, drawn by the panel and by the
  window sidebar, so the state that silences every banner is readable from the
  surface this machine is actually set to. Observed on screen: amber text and
  an Open Settings button under the overview strip, captured by window id
  because a foreground app kept winning the raise.
- Decided the guard against a third instance is a source-text test, not a
  convention. `SetupBanner` was stranded in the panel once and the notice after
  it; `testBothSurfacesDrawTheSharedNotices` reads both view files and asserts
  each names both. Proved it fails first: with the window's line deleted it
  reports exactly the stranding it is there to catch.
- Found a second, quieter half of the same bug: authorization was read once at
  launch, and the notice's own button sends you to System Settings to change
  it. So the notice would keep claiming notifications are off for the rest of
  the session, on the path it creates itself. Re-read in
  `applicationDidBecomeActive` now.
- That re-read is logged on purpose. While the answer stays `false` it changes
  nothing on screen, so a refresh that never runs and one that runs and finds
  the same denial are the same picture; the log line is the only thing that
  separates them. Observed: `authorization re-read status=1 allowed=0`, three
  lines per launch, and the third has no caller but `didBecomeActive`.
- Still unobserved, deliberately not claimed: the notice *clearing*. That needs
  the switch flipped, which is the top `[you]` task, and granting is the only
  input that distinguishes a working re-read from one that always reads denied.
- Merged. `notification-answers` went to `main` as `21afc3d` (PR #3, squash,
  branch deleted both sides); 222 tests green on the merged tree, and the `test`
  check passed on the self-hosted runner -- the first PR on this repo whose
  check ran rather than queueing. The three `[you]` hand-checks survive the
  merge unchanged: they test surfaces that shipped, not the branch.

### 2026-09-15 (context chart observed; two surfacing gaps)
- Observed: the context chart draws. Window surface, `fix-dock-passwords-icon`,
  24 persisted samples reloaded from `UserDefaults` at launch. Line and area
  both present; shape is a flat crawl along the floor.
- Decided: read the chart's liveness off the fallback, not the slope. Every
  session on this machine is Opus 1M and none has passed ~18%, so a correct
  chart and a dead one both look flat. `ContextTrend` renders the literal text
  `no context history yet` when `ContextChart.unitPoints` returns nil, so that
  string's absence is the observation; the slope is not. A visibly climbing line
  stays unobserved and needs a session past ~50% of its window.
- Found: two things are only reachable from a surface you may not be on. The
  notifications-denied notice lives in `MenuContentView` alone, so in Window
  mode (the current setting) there is no readout of the very state that is the
  top open task. Same shape for the placed-status-item round-trip, which cannot
  start until `Show in` is flipped back to Menu bar -- `lsappinfo` reads
  `type="Foreground"` in Window mode because no status item is ever created.
- Found: `showMainWindow()` opens the window at launch but does not raise it. A
  relaunch left the window behind a full-screen-ish terminal, and
  `tell application id ... to activate` did not bring it forward; only
  `System Events` + `AXRaise` did. Mistook that for "the window never opened"
  until the AX window list showed it at 816,55 all along.

### 2026-09-15 (CI had never run; project grouping; icon)
- Found: PR #3's red check was never a test failure. `gh api
  .../actions/runners` returned `total_count: 0` -- the workflow had required
  `[self-hosted, macOS]` since it was written and no runner was ever registered.
  Five runs on this branch each sat in the queue and were cancelled at exactly
  `24h0m`, annotated "exceeded the maximum execution time while awaiting a
  runner". The suite was green the whole time, locally.
- Decided: check the workflow's own premise before acting on it. Its header
  claimed hosted images ship Xcode 26.x and cannot open this project's
  `objectVersion 110`. A throwaway probe on macos-latest/26/15 could not test
  that at all: every hosted job failed in ~6s with zero steps and the annotation
  "The job was not started because recent account payments have failed or your
  spending limit needs to be increased." So the Xcode-format claim stays
  **unverified**, and the header now says so rather than asserting it.
- The probe's useful output was the contrast, not the answer it was after: a
  hosted job is refused in 6s while a self-hosted job in the same repo queues
  normally for 24h. That places the billing block on hosted minutes alone, which
  is what made registering a runner viable without touching billing.
- Noted: the workflow header omitted the binding constraint. Every configuration
  sets `MACOSX_DEPLOYMENT_TARGET = 27.0` and the tests are hosted in the app, so
  a runner needs macOS 27 at RUNTIME, not merely Xcode 27 installed. Recorded in
  the workflow now.
- Found: the sidebar's row order was not a bad sort but no sort. `rescan`
  publishes `sessions = Array(byId.values)` and Swift leaves dictionary
  iteration order undefined, so rows re-shuffled on every scan.
- Decided: `projectSections` keys only on values that do not tick -- project
  name, session name, id. Sorting on tokens or `updated` would have replaced an
  arbitrary order with a slower-moving one, which is the same bug with a longer
  period.
- Decided: a blocked session is listed under "Needs you" only, not also under
  its project. The sidebar tags rows with the session id for `List` selection
  and two rows sharing a tag is undefined. Section counts follow the rows each
  section actually lists.
- Proved the churn test can fail before trusting it: with the sort removed it
  reports `["c","a"]` against `["a","c"]` -- the dictionary order leaking
  through, which is the bug's own signature. Restored after.
- Unobserved, deliberately not claimed: the panel's project sections were never
  seen on screen. The panel needs the menu-bar surface (this machine is set to
  `window`), and repeated capture attempts were defeated by other live sessions
  stealing focus and Spaces. Covered by tests and a clean build only.

### 2026-09-04 (per-session context history)
- Asked for more graphs and data points; scoped to the detail pane and to
  context growth. The inventory that preceded it is the finding worth keeping:
  **the app had no per-session time series at all.** `usageHistory` is global,
  account-scoped and sampled only by the usage poller, and every per-session
  number in the pane -- spend, tokens, cache ratio, lines -- is latest-value
  only, overwritten on each statusLine write. So this was new plumbing, not a
  new view over data already held.
- Decided: sample only when the token count changes. A flat line through an idle
  session would push the informative part of the curve out of a capped buffer,
  and the chart is time-scaled, so a gap between two points already draws the
  idle stretch.
- Decided: a change inside the 15s min gap rewrites the last point rather than
  being dropped. Dropping it would hold a stale count on screen through a fast
  turn, and the count is the thing being plotted.
- Decided: scaled 0 to the window, not to the data, for both the meter and the
  chart. A 1M-window session holding 20k should draw as a flat crawl; auto-zoom
  would make it look as full as 190k on a 200k window. Same reasoning as the
  existing sparkline's fixed 0-100 axis.
- Decided: x is time-scaled, unlike `Sparkline`, which is index-based and so
  compresses a polling gap into an ordinary step. The old chart was left alone.
- Observed: the sampler works end to end. After a relaunch, UserDefaults held
  six samples for this session with rising token counts, gaps of 17-143s, no
  duplicate values, and no entry for sessions that report no context.
- Not done: **the meter and the chart have never been seen rendered.** The unit
  tests cover the geometry both ways, but every attempt to screenshot the window
  failed on machine state, not on the code -- a BetterDisplay "Virtual 16:9"
  5120x2880 display reports as present, is DISCONNECTED, will not reconnect, is
  display 1, and is where AppKit places the window. On it the window is invisible
  to `screencapture` (black), to Accessibility (0 windows), and to the user. The
  window's saved frame was restored to what it was. Left as a `[you]` check.

### 2026-09-04 (the Git card said things that were not true)
- Reported as "confusing, not sure it's accurate when available": three of the
  four buttons greyed in a healthy repo. The values were right, but the reasons
  were invisible (a `.help` tooltip nobody hovers for) and, worse, sometimes
  false. `sync` and `pr` ran on a 90-second TTL that nothing invalidated when
  HEAD moved, so for up to a minute and a half after a commit the card read
  `in sync` and Push refused with "Already in sync with the remote." The cache
  is keyed by directory, so a branch switch carried the previous branch's PR
  and sync forward for the rest of that window.
- Decided: the remote decision moves after the local read. A changed `headSHA`
  or branch forces it, and a branch switch clears `sync`/`pr`/mergeability
  first so a read that then fails says unknown rather than mislabelling the new
  branch. Observed: committing `eaf5cad` flipped `remote` to `ahead 1` and made
  Push appear within one poll, against 90s before.
- Decided: `unavailableReason` returns the sentence *and* whether it is
  settled. A settled block hides its button, since the rows above already say
  "clean" / "in sync" / "#3 open"; an unreadable one keeps the button greyed
  with the reason printed on the page. Absence now means "nothing to do" and
  grey means "couldn't tell" — the distinction the report was actually about.
  This is why "hide unavailable actions" is safe: without the split, a failed
  probe would delete a control silently.
- The post-action `invalidate` moved into the view, ordered ahead of its own
  re-read. As two unordered actor hops the read could win and return the
  pre-action entry, which is the "still says ahead 1 after a push" symptom the
  `invalidate` doc comment claims to prevent.
- `gh` is resolved against `/opt/homebrew/bin` then `/usr/local/bin`. A missing
  binary used to fail the run, map to `.unknown`, and blame GitHub for a tool
  that was never installed.
- Correction, found while verifying: the new `checks` row read `checks failing`
  off `mergeStateStatus == UNSTABLE`, while `gh pr checks` reported no checks
  at all on the branch. UNSTABLE covers any non-passing status, pending
  included. Now `checks not passing` (`aa339f2`) — a false claim in the row
  whose entire purpose is not making false claims.
- Also caught by an assertion rather than by luck: a test helper typed
  `PRState?` read `.none` as `Optional.none`, so the "no PR" merge case
  silently re-tested the mergeable default. `PRState` has a case called `none`;
  never take it through an optional parameter.
- Not done: the unreadable-remote rendering was never observed on screen. The
  predicate is covered both ways by unit tests, but the greyed-plus-inline-
  reason path has only been reasoned about. Toggling wifi would have disturbed
  three other live sessions, and the throwaway-repo probe was denied.
- 202 unit tests green, including a mergeable snapshot that yields no block, so
  the merge gate is shown to pass and not only to block.

### 2026-09-04 (closing the runtime-verification gaps)
- The permission card names what it is asking about. `AskRequest` now decodes
  `tool_input` (string fields only; a non-object one leaves it empty rather than
  throwing, since a decode failure loses a request the hook is still blocked on),
  and `toolSubject` returns the first of `command`, `file_path`, `url`, `pattern`,
  `query`, `path`, `prompt`, capped at 600 chars. The notification body carries it
  too. Observed against live `ask.sh` runs: Bash rendered
  `rm -rf /tmp/verify-probe-dir`, Read rendered the full path, and a payload whose
  only fields were non-strings fell back to the old `Run TodoWrite?`. A click
  returned `decision{behavior:"allow"}` and an answer file returned `"deny"`, both
  exit 0 with `asks/` empty afterwards.
- The window opens with nothing focused -- `makeFirstResponder(nil)` after
  `makeKeyAndOrderFront`. `AXFocusedUIElement` read `AXWindow` on two separate
  launches, and two characters typed at the frontmost window landed nowhere while
  the reply field still rendered its placeholder.
- Decided: the "Pull is disabled by untracked files" finding was a misdiagnosis,
  the second one this branch has produced after the installer-reformatting task.
  `GitParse.porcelain` files `??` lines under `untracked` and `isDirty` reads only
  `dirty`/`staged`, so the gate could not have seen the untracked file; the tooltip
  observed proves `dirty > 0`, and that session had just made a tracked edit to
  watch the pane update live. The real defect was adjacent: `isDirty` answered
  ahead of the sync switch, so an in-sync repo with a dirty tree was told to commit
  or stash -- which reads as a promise that pulling would then work. Sync answers
  first now; the dirty gate survives inside `.remoteAhead`, where it is the only
  state a pull would otherwise run in. Proven by re-introducing the old ordering:
  the new test failed with the commit-or-stash sentence, and passed once restored.
- Not done: reading the Pull tooltip in the running app. Selecting a session by
  synthetic click kept missing -- the sidebar re-sorts live under the pointer and a
  stray click opened System Settings -- and the string is a pure function already
  pinned by a test with a demonstrated failing case, so this was dropped rather
  than chased further.

### 2026-09-04 (runtime verification)
- Verified by running the app rather than the suite. `ask.sh` was driven as a
  real hook with live payloads and answered by clicking the window: a
  single-select question returned `permissionDecision:"allow"` with `answers`
  keyed on the question text (`"Cold brew"`), and a `PermissionRequest` returned
  `decision{behavior:"deny"}`. Both exit 0 and leave `asks/` empty.
- The fall-through matrix holds. Timeout, `multiSelect`, two questions, missing
  `session_id`, non-JSON stdin and app-not-running all exit 0 with empty stdout,
  and the four decidable without waiting return in 0s. Nothing exits 2. Malformed
  stdin does leak a `jq: parse error` to stderr.
- The GIT pane updates live: a tracked edit moved `changes` from `1 untracked` to
  `1 modified, 1 untracked` with no restart, and every disabled control was
  confirmed to carry a true reason in its tooltip (mid-turn, in sync, PR already
  open, uncommitted changes).
- Found: the permission card renders only `Run \(ask.toolName)?`. `ask.sh` writes
  `tool_input` into the ask file but `AskRequest` has no `toolInput` field, so the
  window asks you to approve a command it does not show. Probed with
  `rm -rf /tmp/verify-probe-dir` and got Allow/Deny with no command text. This is
  the one place the window is worse than the terminal prompt it replaces.
- Found: the reply field takes first responder on window open — confirmed via
  `AXFocusedUIElement` immediately after launch — and mid-run held a stray `ui`
  nobody typed deliberately. Keystrokes aimed at anything else land in a box whose
  Send types into a running session. It does not survive relaunch, which is the
  only thing keeping it harmless.
- Found: Pull is disabled by untracked files. With a clean tree except `.local/`,
  the tooltip reads "There are uncommitted changes. Commit or stash them first."
  An untracked file does not block `git pull`, so Pull is permanently greyed on
  this repo.
- Not exercised: the Install-hooks banner (gated on `!feed.isSetupInstalled`, and
  the hooks are installed — driving it means uninstalling from the live
  `settings.json`) and Send on the reply field (it would have typed into this
  session's own pane).

### 2026-09-04 (installer diff)
- Investigated and dropped: "SetupInstaller reformats settings.json". It already
  writes `.prettyPrinted, .sortedKeys`, so its output is deterministic. The
  428/406 diff on first install was one-time normalisation -- the file carried 86
  unsorted objects because Claude Code's own writer does not sort, and the
  install sorted all of them at once. A semantic diff confirmed exactly two
  additions, 23 deny and 9 allow rules unchanged. It can recur only after Claude
  Code rewrites the file, and installs are rare, so an order-preserving encoder
  is not worth writing.
- Verified while installing: `ask.sh` had never run on this machine. The control
  that installs it lived only in `MenuContentView`, unreachable under
  `surface = window` where the app has no status item, so every permission
  prompt arrived with nothing to press.
