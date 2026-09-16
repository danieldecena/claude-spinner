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

Notifications work end to end, so the app's last blocking gap is closed. What
is left is two hand-checks, both `[you]` in `TASKS.md`: the placed-status-item
policy round-trip (not scriptable, see the 2026-08-12 decision log), and a
context line with a visible slope. Two runtime cases stay unobserved and are
named in the decision log: the unreadable-remote rendering from the Git work,
and the panel's new project sections.

The app ships as a locally-built, ad-hoc-signed `.app` via `run.sh`.

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
