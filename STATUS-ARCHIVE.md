# STATUS archive

Decision-log entries rotated out of `STATUS.md` to keep it readable.
Append-only; git holds the full history either way.

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

### 2026-09-04 (filling the window)
- Noted: the pane looked empty because the statusLine writes 45 fields to
  `<id>.status.json` every few seconds and `StatusFile` decoded 8. Nothing new
  had to be plumbed; the rest was already on disk.
- Decided: the dollar figure never leads and is labelled `api-equivalent, not
  billed`. `cost.total_cost_usd` is API list pricing; on a Max plan it is a burn
  proxy and charging language is simply false. The 5h/7d windows lead instead.
- Decided: rate-limit windows are account-wide, so the overview takes the
  freshest reading. Summing three sessions reporting 49% would say 147% of a
  five-hour window.
- Decided: totals stay nil when nothing has reported rather than summing to a
  confident $0.00 over sessions whose statusLine has not run.
- **Fixed a real misclassification.** `emit.sh` mapped every `Notification`
  event to `.attention`, and `idle_prompt` is one — it fires 60s after a turn
  *ends* if you have not typed. A finished session therefore sat in the same
  orange "needs input" row as one holding a permission prompt. `emit.sh` now
  records `notification_type`; `isBlockedOnYou` excludes `idle_prompt`, and the
  "Claude needs you" banner no longer fires for it.
- **Fixed the gate that shipped backwards.** The reply box and every slash
  command asked `status == .idle`, but `.attention` means the session is sitting
  at its prompt waiting on a person — exactly when typing works. They were
  disabled on the one session you most want to answer. Now `isAtPrompt`, i.e.
  not working. Tightening it exposed a second: the delivery check watched for
  the status leaving `idle`, which `.attention` satisfies, so a session already
  in attention would have reported a turn that never started. It now waits for
  `thinking` or `tool`.
- Decided: the transcript is read as a bounded 256KB tail, parsed backwards, and
  the first line after a seek is dropped — landing mid-record yields another
  record's tail, not a truncated one to recover. Files here are 4.7MB and are
  appended to while being read.
- Decided: every action button is enabled or states its reason. The commonest
  one, "not in a tmux pane", is permanent rather than temporary, so a silently
  greyed control would read as a broken app.

### 2026-09-04 (answer from the notification)
- Decided: the round-trip needs no keystroke injection. A `PreToolUse` hook on
  `AskUserQuestion` receives the full `questions` array and returns `allow`
  paired with `updatedInput` carrying an `answers` object; `PermissionRequest`
  takes `decision{behavior}`. Both are first-party and work in any terminal, VS
  Code, or the Desktop Code tab. Command hooks default to a 600 s timeout, so a
  hook can genuinely wait for a person.
- Decided: `ask.sh` never exits 2. On `PreToolUse` that routes as a deny, which
  would turn "you weren't at the machine" into "the tool was refused". Timeout
  and `passthrough` both print nothing and exit 0, so the terminal prompt takes
  over — the documented behaviour for a timed-out command hook.
- Decided: `pgrep` gates the whole thing before the ask file is written. Without
  it every tool call stalls for the full deadline whenever the app is closed.
- Decided: multi-question and `multiSelect` asks pass through to the terminal. A
  banner has one tap and cannot express either; the window pane shows them.
- Decided: the installer's idempotency key is `(script, matcher)`, not "anything
  of ours on this event". Keyed the old way, a machine that installed before
  `ask.sh` existed already had `emit.sh` on `PreToolUse`, so the event looked
  complete and the answer hook would never have been added.
- Noted: notification authorization is **denied** on this machine, found only
  because the end-to-end check looked at the screen. Every intermediate signal
  was green — category registered, request added with `hasError: 0`, banner
  withdrawn on the deadline — because `add()` reports acceptance, never
  presentation. Reading the status needed `os_log` with an explicit public
  format; NSLog's Swift bridge redacts interpolated values to `<private>`, so
  the first attempt at logging it was unreadable.
- Decided: free-text reply is tmux-only and says so. Measured rather than
  assumed — writing to another process's `/dev/ttysNNN` is output-only, and
  `TIOCSTI` returns EPERM on this macOS even against a pty the caller owns.
  Delivery is confirmed by the session's state leaving `idle`, never by
  `send-keys`' exit status, which proves only that keys reached a pane's buffer.
- Decided: the done-turn alert is off by default and gated on the host app not
  being frontmost. Every turn of every session ends; a turn finishing in the
  window you are watching does not need announcing.
- Noted: `windowDidResize` no longer writes `panelWidth`. That coupling existed
  only because the window hosted the popover panel, and leaving it would make
  resizing the window reflow the menu-bar dropdown.
- Noted: `emit.sh` never carried `message` forward, so every state file on disk
  held an empty string and the attention banner read as a bare project name.

### 2026-08-17 (nested subagent rows)
- Decided: subagents share the parent's `session_id`; they are not sibling
  sessions. `emit.sh` keys child files on hook `agent_id` as
  `<parent>.<agent_id>.state.json` with `parent_session_id` inside the JSON.
  An array of children inside the parent file was rejected — parallel
  Explores would race on one write (that was already the live bug: child
  `PreToolUse` overwrote the parent's current tool).
- Decided: visual depth 1, full 2-line child (todo bar + status), 16pt
  indent. Grandchildren flatten under the same parent (hook stdin has no
  `parent_agent_id`). Omit model, context tokens, and host chip — those
  would be the parent's numbers. Keep time, tool, todo bar, click-to-focus
  on the parent editor.
- Decided: a parent with children is never idle-collapsed, even after the
  children finish. Finished-child dwell until parent `SessionEnd` / 12h
  cutoff is a later display filter if the panel gets noisy.
- Noted: `item.ids` includes children so clearing the parent cascades;
  the `×N` badge therefore cannot key off `ids.count`. It keys off
  `subagentCount == 0 && count > 1` (idle-collapse groups only).
- Noted: bundled `Scripts/emit.sh` stayed byte-identical to the live copy
  (content-parity test now also asserts `parent_session_id` / `SubagentStart`).
  SetupInstaller gained those two hook events; Install hooks was run on
  this machine so live `settings.json` actually fires them.

### 2026-08-15 (todo-progress-bar)
- Decided: a 10-box `□□□□□□□□□□ --%` completion bar per session, sourced from
  TodoWrite counts captured by `emit.sh` on `PostToolUse` (no prior progress
  signal existed anywhere in the feed). Lives on a second row under every
  session row, reserved at 0% before any TodoWrite call rather than hidden.
- Decided: flat tint (`Color.claude`), not `Color.usageTint` — that gradient
  reads high-percentage as dangerous (rate-limit urgency), backwards for task
  completion where 100% is the good outcome.
- Live scope change mid-build (user's direct request): the existing status/
  activity text moved from row line 1 to line 2, next to the bar.
- Final whole-branch review (opus) caught what no per-task review could: the
  app bundles its own copy of `emit.sh` (`claude spinner/Scripts/emit.sh`),
  installed fresh by `SetupInstaller` — it never got the todo-capture change,
  so the feature was dead on any fresh install and a re-install on this
  machine would have silently downgraded the working live script. Fixed by
  syncing the bundled copy plus a content-parity test. Also fixed: a stale
  RowLayout column budget that clamped names/erased the model column after
  status moved lines; unclamped box-fill math that could crash the app on an
  out-of-range state-file value; dead accessibility on the bar (collapsed by
  the row's own `.ignore`); no fixed frame on the percent text (caused a
  frame-to-frame divider jitter synced to the working-dots animation,
  confirmed by measuring divider position across frames pre/post fix).
- Noted: every task's `xcodebuild test` run was independently re-verified by
  the controller (not just SourceKit editor diagnostics, which were noisy/
  stale throughout and safely ignored) — except the final fix wave's, cut
  short by the `/goal` landing reserve. Closed by the scoped re-review below.
- Scoped re-review of the fix wave (opus, `70700d1..236491e`): all 7 findings
  ADDRESSED, no new Critical/Important breakage. Independently re-ran
  `xcodebuild test` (82/82) and rebuilt+ran the app with synthetic
  multi-session data — a 12-frame pixel-diff of the row-list column showed
  zero drift, corroborating the jitter fix (finding #7) beyond the diff.
  Found and fixed one residual: `FeedWatcher.swift`'s `panelMinWidth` comment
  still cited the pre-fix budget formula (`5ddb652`).
  Two caveats the re-review flagged and did not close:
  (a) it could not get a clean capture with `todo_done` actively toggling
  (desktop contamination mid-test), so the jitter fix for that specific
  live-changing-count case is reasoned from SwiftUI's HStack-max-sizing
  semantics, not directly observed;
  (b) no `claude spinner` process was running when the re-review started, so
  it could not confirm the user's "second row still has an issue" report
  (screen recording, since vanished) was against a build containing this fix
  at all. Plan closed via `finishing-a-development-branch`; SDD workspace
  deleted.
- Noted: no further jitter complaint surfaced across several screenshots
  taken since (`f60c862`) — the user moved on to a separate, unrelated
  window-sizing bug (below) without re-flagging it. Treating the jitter fix
  as holding unless it recurs; the toggling-todo-count live scenario the
  re-review couldn't cleanly capture is still technically unobserved.

### 2026-08-15 (standalone window dead space)
- Decided: `MenuContentView`'s `fillsWidth` frame needs `maxHeight: .infinity,
  alignment: .top`, not just `maxWidth: .infinity`. Without it, NSHostingView
  centers content shorter than the window instead of pinning it to the top —
  a window dragged (or remembered) taller than its content showed equal dead
  space above and below the rows, not just below. Found from a screenshot of
  the standalone window; confirmed fixed on screen after the change (content
  flush to the top edge).
- Decided: `showMainWindow` shrinks an oversized remembered frame back to
  `panelWidth` × the new `panelDefaultHeight` constant (320, matching the
  existing hardcoded default) on whichever axis overran, keeping the
  remembered position. A remembered width beyond `panelWidth` is pure waste
  (`RowLayout.maxNameWidth` caps how much a row can use anyway); a remembered
  height beyond content is the same on the other axis. Root cause of both
  screenshots: a stale ~573×1900 remembered frame left over from the
  re-review's earlier `resize_window` synthetic testing.
- Noted: caught mid-diagnosis that `defaults delete com.danieldecena.
  claude-spinner ...` targeted the wrong bundle id — the app's actual id is
  `decenad.claude-spinner` (confirmed via `osascript -e 'id of app...'`).
  The first "fix" attempt looked like it did nothing because of this, not
  because the code fix was wrong.
- Noted: attempted a full-screen `screencapture` to verify the fix and it
  caught the user's live video call in frame. Deleted that screenshot and
  other stale capture artifacts immediately, stopped taking full-screen
  captures, and asked the user to screenshot the app themselves for the rest
  of this verification. `System Events` reports 0 AX windows for the popover
  surface, so there was no safe way to target just that window either.

### 2026-08-12 (chosen surface)
- Decided: two states, not three. An explicit "Menu bar" preference must still
  fall back to the window when placement fails — otherwise the preference can
  lock the user out of their own app — which makes it behaviourally identical to
  an "Auto" state. Shipping both would have been a label, not a behaviour.
- Decided: the Window surface creates **no** status item, rather than creating one
  and ignoring it. It is then deterministic by construction instead of by
  fallback, and it returns a slot to a menu bar that was full enough to drop us.
- Decided: `statusItem` becomes a real `Optional`. The nil case then falls out
  correctly with no new guards — `statusItemFrames` returns nil, so
  `statusItemIsUnplaced` reads true, so `windowWillClose` declines to drop back to
  `.accessory`, so the window surface cannot lose the Dock icon that is its only
  way back.
- Decided: the switch applies on next launch, said out loud in the submenu.
  Tearing down and rebuilding a live status item is machinery this doesn't need.
- Noted: verified by relaunching into each surface. Window — `menu bar 2` does not
  exist for the process at all, which is stronger evidence than a hidden item;
  window up, Foreground, Spinner menu installed. Menu bar — one status item, the
  usual `(-1, 1090)`, fallback window, "Show in > Menu bar" checked.
- Noted: a verification pass was run against the **wrong binary** first. There are
  two `DerivedData/claude_spinner-*` directories and a glob with `head -1` picked
  a Jul 17 build, which produced a coherent-looking but meaningless result (no
  window, no policy change, status item present). `run.sh` resolves
  `BUILT_PRODUCTS_DIR` properly — launch through it rather than globbing.

### 2026-08-12 (status-item fallback hardened)
- Decided: placement is detected by comparing the status item window's **top edge**
  to its screen's, not by measuring down from `NSStatusBar.system.thickness`. On a
  notched display the visual menu bar is ~37pt while thickness still reports 24, so
  the old `maxY - thickness - 1` cutoff had a 1pt margin and would have read a
  correctly placed item as unplaced. A placed item is flush to the screen top
  whatever the bar's height. Now `Constants.statusItemIsUnplaced(itemFrame:
  screenFrame:)` — pure, so both halves are testable on a machine whose bar is full.
- Decided: drop the `maxX < screen.minX` clause. It could not fire — `window.screen`
  is by definition the screen the window most overlaps, so a window entirely left of
  that screen's left edge is a contradiction. The observed case (x=-1, width 131)
  never tripped it either; the minY clause did all the work.
- Decided: the settings menu gets a second host. Every control (mode, Launch at
  Login, Live usage, Refresh, Relaunch, Clear All Sessions) hung off
  `menu.popUp(in: button)` — anchored to a button parked off-screen — so an
  unplaced item made all of them unreachable. One builder (`populateSettingsMenu`)
  now fills both the status-item popup and a "Spinner" submenu in `.regular`'s main
  menu, repopulating via `NSMenuDelegate.menuNeedsUpdate` so its checkmarks don't
  go stale.
- Decided: install that menu at **launch**, not at the `.regular` flip. Appending to
  `NSApp.mainMenu` immediately after `setActivationPolicy(.regular)` did not stick —
  verified on a running instance whose main menu had no Spinner item. An .accessory
  app's menu bar is never drawn, so an early install costs nothing.
- Decided: `.regular` is reversible now, but only when there is a placed status item
  to fall back to. `windowWillClose` restores `.accessory` in that case and
  deliberately does not when the item is unplaced — dropping the Dock icon there is
  what left the app unreachable in the first place.
- Decided: re-check placement on `didChangeScreenParametersNotification` instead of
  polling, and open the fallback window **once**. The check also runs on every
  display change, and an unplaced item is a persistent state, so re-fronting would
  steal focus each time a monitor is plugged in.
- Decided: the window title carries the menu-bar readout (`Claude Spinner · 5h 44%
  · 4h4m`). With the item unplaced, `MenuBarLabel` renders into a button nobody can
  see, so the title is the only place that figure appears. The animated glyph is
  left out on purpose — a title bar redrawing at spinner FPS is noise.
- Noted: both halves observed live, which the original fix never had. Unplaced —
  item at AX `(-1, 1090)`, fallback window opened, app `Foreground`. Placed — item
  at `(1390, 8)`, no window, app stayed `UIElement`. The `osascript` probe over
  `menu bar 2` reports the item's real position independently of the app's own
  detector; use it rather than trusting the verdict.
- Noted: one branch is **unverified** — `windowWillClose` restoring `.accessory`
  with a *placed* item. Reaching it needs the window open while the item is placed,
  and neither route works from a script: `applicationShouldHandleReopen` never fires
  for an .accessory app (no Dock icon to click), and the status item's popped-up
  NSMenu is not exposed to Accessibility, so the "Open Window" entry can't be
  driven. Confirm by hand: right-click the icon, Open Window, close it, and check
  `lsappinfo info <pid>` reads `type="UIElement"`.

### 2026-07-21 (OpenWolf decommission + notarization dropped)
- Decided: don't notarize. It needs a paid Developer Program account, which
  isn't being pursued; the ad-hoc-signed `run.sh` build is the intended
  distribution. Removed the task from TASKS.md and Next Up.
- Decided: decommission OpenWolf in this repo — it was uninstalled globally
  (CLI/daemon 2026-07-19, global advisory hooks 2026-07-21), but this repo's
  project-local copy was missed. Removed the 6-hook block from
  `.claude/settings.json` (SessionStart/Read/Write/Stop) and deleted
  `.wolf/hooks/`. The hooks fired `node` on every Read/Write/Stop (5-10s
  timeouts) and rewrote tracked `.wolf/anatomy.md` / `buglog.json` as a side
  effect of ordinary edits. The `.wolf/*.md`/`.json` data files are kept as
  frozen reference, per the global openwolf deprecation rule.

### 2026-07-18 (usage reset countdown)
- Decided: the menu-bar usage title carries the countdown (`5h 4% · 4h50m`), not
  just the clock time the panel footer already shows. The footer answers "when",
  which needs the panel open; the menu bar answers "how long", which is the
  question a bare percentage provokes and the one worth paying title width for.
- Decided: the countdown gets its own 60s `minuteTick` rather than riding the
  spinner's animation timer. That timer only advances while working or alarming,
  which is precisely when the countdown does NOT need to move — an idle session
  watching its limit recover would have seen a frozen number.
- Decided: an unknown reset instant drops the countdown rather than showing `0m`.
  The statusLine feed carries a percentage with no `resets_at`, so zero would be
  a confident wrong answer where absence is honest.
- Noted: `xcodebuild test` passed 61/61 on the unit target today, twice, with the
  app killed first — the recorded runner-bootstrap failure did not reproduce. The
  UI target was not exercised, so that half stays open.

### 2026-07-17 (buglog concurrency, bug-200)
- Decided: serialize the buglog write behind a lockfile rather than move to
  one-file-per-bug. The append is a millisecond critical section and the file is
  already written atomically (tmp+rename), so a lock closes the race with the
  smallest change and keeps every reader (pre-write, session-start, the digest)
  pointed at one file. Per-bug files were the more robust option but would have
  rewritten the format across several third-party hooks.
- Decided: the id is `max(numeric ids)+1`, not `bugs.length+1`. length trailed
  the true max (the log already had gaps and dups) and could even land back on an
  existing id; max+1 is strictly greater than every id present, so it can't reuse.
- Noted: the fix lands in the *project-local* `.wolf/hooks/post-write.js` (the
  copy `.claude/settings.json` actually invokes). The identical `length+1` lives
  in the global openwolf npm package too, so every OpenWolf project shares this
  bug — a separate upstream concern, not fixed here.
- Noted: verified by a barrier-synchronized race (common future start instant to
  defeat node-startup jitter) — the naive 25-way full-hook test did NOT reproduce
  the race because startup stagger serialized the writers. Concurrency bugs need
  a real barrier to surface; a plain fan-out can pass a broken implementation.

### 2026-07-17 (status truncation)
- Decided: the status label is cut to its column *in code* (`RowLayout.fit`),
  not left to SwiftUI's `.truncationMode(.tail)`. SwiftUI Text has no
  clip-without-ellipsis mode, so a clamped long tool name got its own `…` — which
  landed right against the fixed working-dots slot and read as `running askuserqu……`.
  Pre-truncating to the column width minus `statusSlack` (Menlo is monospaced, so
  the fit is exact) guarantees SwiftUI never reaches for the glyph; the dots are
  the only trailing signal. `truncationMode(.tail)` stays as a dead backstop (bug-201).
- Noted: this was invisible to the 56-tests-green build — the arithmetic column
  math was right; the collision only exists on screen. Confirmed by staging a
  throwaway 51-char MCP row and comparing its trailing marker to `running bash…`
  (which cannot truncate): identical, so no doubled ellipsis. Same "go and look"
  lesson as bug-140, now applied.

### 2026-07-17 (row layout, cont.)
- Decided: row columns are sized once per panel, from the widest label in each,
  not per row. Per-row sizing (4a6ccb7) fixed truncation but jagged the grid —
  every row's model/status began at a different x. Sizing to the set keeps the
  columns aligned AND hands the names every spare point; the bounded cost is
  that one long-tool row narrows every name (bug-140).
- Decided: the model column joins the name/status budget. It was the same static
  split, smaller — 46pt fixed holding "opus" (27pt). With it folded in, only
  170pt of a row is fixed, which makes panelWidth a free knob; set to 470.
- Noted: bug-140 passed all 56 unit tests. Each row's arithmetic was correct in
  isolation; alignment is a property of the SET of rows and nothing checked it.
  Three findings today came only from looking at the panel (the dimmed 7d bar,
  this jag, the Zed click) — "unit-green" is not "verified" for anything visual.

### 2026-07-17 (row layout)
- Decided: the status column takes its measured width and the name takes the
  remainder, rather than both being fixed. Two fixed columns meant one static
  guess failing in both directions — `done` hoarding 103pt while the name
  truncated, and `running TodoWrite` overrunning the same 103pt. Third bug in
  this family (bug-111/122/138); widening the panel would only move the guess.
- Noted: the ~0.602×size Menlo estimate the old widths were derived from was
  blamed for bug-122. Measuring proved it accurate to two decimals (6.6226 vs
  6.622), so slack is still required for other reasons. `RowLayout.monoAdvance`
  measures the font directly — that removes a hand-rederived constant, not a bug.

### 2026-07-17 (panel gauges)
- Decided: the `chg` gauge scales by square root over the full 0-100 range, not
  linearly over 20 points. Linear saturated past 20, which is where comparing
  magnitudes starts to matter; sqrt keeps single-digit moves apart (the common
  case) and still separates a +52 from a +20. Kept the gauge rather than cutting
  it — the redundancy question resolved once the bar actually carried the value.
- Decided: a low gauge value is de-emphasised by tint alone, never by dimming
  the fill. The track is already a low-opacity secondary, so dimming costs the
  contrast the fill is read against — and for 7d, under 10% is the normal case.

### 2026-07-17 (review session)
- Decided: an unknown host that names a *running* app resolves to itself rather
  than falling back to a terminal. Fixes Zed/Cursor/VSCodium/Windsurf at once
  without hardcoding bundle IDs, and keeps the fallback for `TERM_PROGRAM`
  values, which are never bundle IDs.
- Decided: `run.sh`'s swiftc fallback globs `"claude spinner"/*.swift` rather
  than listing sources. The folder is a synchronized root group, so any literal
  list rots silently behind it — which is exactly how it broke (bug-132).
- Noted: the code-defined dark-mode colors decision below was justified by "the
  fallback compiles only the three sources". That premise was stale. The
  conclusion stands for the real reason — the fallback has no asset-catalog
  step, so a colorset would vanish from the dev loop.

### 2026-07-17
- Decided: the row names the session, not the project — `session_name` is the
  only thing separating two sessions in one directory. The cwd moved to the
  tooltip.
- Decided: context tints band on absolute tokens, not percent — a 1m window
  makes 200k read as a harmless 20%.
- Decided: rows sort by context weight *within* a status band, not globally, so
  a heavy idle session can't outrank one waiting on you.
- Decided: dark-mode colors live in code, not an asset catalog — run.sh's
  swiftc fallback compiles only the three sources and would drop a colorset.

### 2026-07-10
- Decided: keep the spinner scoped to Claude Code sessions; do not observe the
  Desktop Chat tab via unsupported internals. Documented the Code-tab (hooks
  fire) vs Chat-tab (no hooks) distinction.

### 2026-09-29 (sloped context line observed, seeded)
- Observed: the detail chart draws a climbing line. A fake session (feed files
  under a throwaway id, 200k window, 151,294 tokens) plus a seeded
  `contextHistory` of 20 samples rising 20k -> 143.5k over 40 min: the Window
  surface's CONTEXT block read `75%` and the chart rose left to right from
  `41m ago` to `1m ago`, top label `150k`. Screenshot 14:31.
- Decided: a seeded session is a valid input for this check. The open question
  was the rendering path (does a slope draw), not whether real sessions climb;
  the app appended its own live sample (151,294) on top of the seed, so the read
  path was the real one.
- Cleanup observed: deleting the fake feed files made the next rescan drop the
  id from `contextHistory` (3 keys -> 2, id absent), confirming
  `recordContextSamples` prunes departed sessions.
- Observed, same technique: all four identity hues. Three fake sessions
  (Sonnet + `web`, Haiku + Ghostty, Fable + `com.microsoft.VSCode`) put
  `4 opus 1 fable 1 haiku 1 sonnet` in the header's models bar as four distinct
  segments, and each row drew its model word and host pill in its own hue:
  `fable`/`vsc` indigo, `sonnet`/`web` cyan, `haiku`/`trm` jade. Captured with
  `screencapture -l <window id>`, which reads the panel even while another app
  covers it; AX could not scroll the panel, so fakes were removed one at a time
  to bring each row into view.
- Found: a session with no statusLine of its own borrows the most recently
  updated session's model (`modelDisplay`, by design since the fallback went
  in). With the Haiku fake newest, the idle claude-in-safari desktop row flipped
  from `opus` to `haiku`. On a one-model machine this never shows; in a mixed
  fleet the borrowed tag is a guess drawn like a fact.
- Decided (Daniel): mark the borrowed tag as a guess rather than blank it.
  `FeedWatcher.modelTag` appends `?` when `session.model` is nil and the row
  draws it at 0.55 opacity. Observed after relaunch: both claude-in-safari
  desktop rows read `opus?` in a lighter purple, the Ghostty session `opus`
  solid.
- Decided (Daniel): the header's models bar keeps borrowed models apart too.
  `SessionBreakdown.byModel` now takes `modelTag`, so a borrowed `opus?` is its
  own segment at 0.55 opacity instead of adding to the real opus count.
  Observed after relaunch (15:50, popover captured by window id): `2 opus
  2 opus?`, the second segment lighter. 249 tests, 0 failures.

### 2026-09-29 (policy round-trip observed; the surface precondition)

- Decided: the placed-status-item policy round-trip is closed. On the menuBar
  surface a window open reads `type="Foreground"` and after closing it reads
  `type="UIElement"`, with 0 windows remaining (12:47).
- The first attempt read Foreground after the close, which looked like a bug.
  The cause was the persisted `surface` default, which was `window`: that
  surface creates no status item, so `windowWillClose` treats it as unplaced and
  keeps the Dock icon by design. Any check of this path has to confirm
  `defaults read decenad.claude-spinner surface` is `menuBar` first. It was
  switched to `menuBar` for the test and left there.
- In this shell `log` is a zsh function, so `log show` silently runs something
  else and returns nothing. Use `/usr/bin/log`.

### 2026-09-29 (usage totals from ccusage; the Dock bounce)

- Decided: today / week / active-block totals come from `ccusage`, polled every
  10 min (a daily scan costs ~11s wall, ~90s CPU), shown as one line in the
  panel footer (today + week) and as an "All sessions" `StatSection` in the
  window overview (today, week, block). They count every transcript, ended
  sessions included, which nothing else in the app does.
- Decided: never `--offline`, and cost is `$?` whenever any model with tokens
  came back at $0.00. ccusage's price lookup is intermittent: the same query a
  minute apart returned $154 and $1.84, the low run pricing only haiku. The
  block shows tokens only; its JSON has no per-model breakdown to check its
  dollar figure against. A poll that comes back unpriced retries once.
- Decided: the ask Dock bounce is `.informationalRequest` (one bounce), not
  `.criticalRequest` (bounces until activated). Asked for 2026-09-29.
- Not observed on screen: the window's "All sessions" section. This machine's
  window sat in Stage Manager's strip, and raising it by script captured the
  thumbnail twice. Tests pin the parse (239, 0 failures); the rendering is unseen.
- Fixed: the Figma dark copies' near-black text. The 2026-09-16 guess was right:
  100 of 122 text runs in the three dark frames had per-range fills bound to
  **Light** variables, which a whole-node swap never reads. Rebound each run to
  the same-named Dark variable, plus 23 Light-bound shape fills/strokes; a
  recount found 0 Light-bound runs left. Panel · Dark screenshot looked at
  (light text on dark ground); Window · Dark rests on the recount only. Two
  Figma calls, under the Starter cap.
- Decided: no Dock bounce at all on an ask; one bounce was still too much. The
  first fix never ran: the live app was the Sep 15 `/Applications` copy, which a
  login item relaunched, because `run.sh` launched DerivedData and never
  installed. `run.sh` now installs over `/Applications`. Observed: the installed
  dylib has 0 `requestUserAttention` strings against 1 in the Sep 15 backup.

### 2026-09-29 (window 5h/7d unified; test host exempt from single-instance)
- Decided: the window's overview strip reads `feed.usageFiveHourPct` /
  `usageSevenDayPct` (poll -> freshest session -> cached snapshot), the same
  chain as the menu bar, instead of its own freshest-session pick. Observed
  after `run.sh`: strip `45% of 5h · 47% of 7d`, matching the cached snapshot
  (45/47). The fallback leg (no live session carrying rate limits) is reasoned
  from the shared chain, not observed.
- Fixed: `-only-testing` runs failed at bootstrap ("test runner exited with
  code 0 before establishing connection", exit 65) whenever the installed app
  was running: the test host is a second copy, and the single-instance guard
  `exit(0)`s it. The guard now skips when `XCTestConfigurationFilePath` is set.
  Pair observed beside live pid 40771: with the fix, two single-test runs exit
  0 and the live app survives; with it reverted, exit 65 with that error. Full
  suite 249/0. Something relaunches the app ~4s after `killall` (parent
  launchd, no LaunchAgent or ~/bin script found); source unidentified. It did
  not recur at 15:03: after the full suite's `killall` the app stayed down
  over a minute. BTM shows the login item disabled, and nothing in hooks or
  ~/bin opens the app, so a sibling `run.sh` is the likelier cause (unconfirmed).

### 2026-09-29 (unreadable-remote rendering observed, seeded)
- Observed: the Git card's "couldn't tell" path. A throwaway repo on branch
  `feature`, upstream `origin/feature`, origin `file:///nonexistent/...`
  (`ls-remote` exit 128; `gh pr view` exit 1, "no known GitHub host"), plus a
  fake feed session with that cwd. The card read `remote unknown`, `pr unknown`
  and kept all five actions on screen greyed, each reason printed underneath
  (push: "The remote couldn't be read, so there is nothing to compare
  against."). Screenshot 14:54. The real repo's card in the same window read
  `in sync` / `none` / "no actions available", the settled control.
- Cleanup observed: deleting the fake feed file dropped the row on the next
  rescan (14:54:29 capture).
- Found: the gh failure here was not a network one, yet the card says "GitHub
  couldn't be reached". `prFailure` maps every non-"no PR" stderr to `.unknown`,
  so a non-GitHub remote reads as an outage forever. Harmless on this machine
  (every remote is GitHub); noted, not fixed.

### 2026-09-29 (detail tiles equal per row, not across the grid)
- Decided: the stat grid equalises card heights per row with a custom
  `TileGrid` Layout, replacing the grid-wide tallest-card PreferenceKey. The
  global rule stretched Git and Session to the Context chart's height, half
  empty; per-row keeps every row reading as equal tiles without that dead
  space. LazyVGrid can't do it (cells keep their own height), and six cards
  gain nothing from laziness. Seen on screen: the Git/Session row is now
  roughly two thirds the height of Cost/Context, with no empty band.

### 2026-09-29 (Clear/Compact landing observed live; git action timeout)
- Observed against a throwaway `claude` in a detached tmux pane, keys sent
  exactly as the app sends them: neither `/clear` nor `/compact` fires
  UserPromptSubmit, so the file never reads "thinking" and every working Clear
  or Compact was reported as "never started a turn". `/clear` deleted the old
  sid's files about 0.9s after Enter and a new sid appeared idle; `/compact`
  left the file idle until SessionStart rewrote it about 10s later with
  `turn_start` and `last_seed` null.
- Decided: key the landing check on what was typed (`SessionReplier.Landing`):
  Clear = the pre-send file is gone (15s), Compact = the file changed from its
  pre-send contents to that SessionStart shape (180s, since compaction is a
  model call), anything else = thinking/tool (4s). No baseline means not
  observed. The Swift path was unit-tested on the recorded shapes, not
  re-run end to end through the app's button.
- Fixed: push/pull/merge ran on the status probe's 8s timeout and were
  terminated on expiry; a merge could be killed after GitHub had merged. They
  now get 120s, and the timeout message says the action may have partly run.

### 2026-09-29 (five review fixes: usage chain, banners, probe, AppleScript)
- A read-only bug hunt over FeedWatcher / app / GitProbe found five defects;
  each was re-read against its callers before fixing.
- Fixed: `pollUsage` heads the 5h/7d chain but was never cleared, so turning
  polling off, a 401, or a missing Keychain token froze the last polled number
  over live statusLine values. It is now cleared on stop and on auth expiry, and
  a missing token reports as expired instead of returning silently. Reasoned,
  not observed (toggling it needs the UI).
- Fixed: `notifiedDone` started empty, so a relaunch with notify-on-done on
  bannered every session already finished. The first scan now only seeds it.
  Reasoned: the preference is off here and was left off.
- Fixed: `updateUsageCache` stamped `savedAt` with the scan time every 2s, so
  hours-old numbers read as fresh and overwrote newer poll snapshots. It now
  uses the session's `updated` and never goes backwards. Observed: after
  `run.sh` the snapshot carried the launch poll's fractional stamp, then an
  integer session epoch 21s old, not a scan-time stamp.
- Fixed: GitProbe read its pipe buffers even when the reader threads had not
  finished (a grandchild holding the pipe), returning a partial answer as whole.
  Now nil, which the card renders as unknown.
- Fixed: folder names went raw into AppleScript string literals. Observed with
  osacompile: `a"b` and `end\` fail raw and compile escaped; `plain-app`
  compiles both ways. (The first run of that check compiled an empty file and
  passed everything: the snippet lacked `import Foundation`.)
- Full suite 249/0, run beside the live app.
