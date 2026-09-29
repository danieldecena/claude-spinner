# STATUS archive

Decision-log entries rotated out of `STATUS.md` to keep it readable.
Append-only; git holds the full history either way.

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
