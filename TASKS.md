# claude-spinner — Tasks

## Tasks

Notarization was dropped 2026-07-21 (needs a paid Developer Program account;
not being pursued) — the app ships as a locally-built, ad-hoc-signed `.app`
via `run.sh`.
- [ ] Watch a refused /compact report on a live short session
- [ ] Watch auto-merge switch itself on for a real open PR
- [ ] Check You asked shows full text on hover in the top row

## Completed

- [x] Hold the wrap-up pick to the prompt when it is size-driven
- [x] Shrink Config to two lines, show action notices in the conversation card, drop the idle line
- [x] Merge You asked, reply and Config into one card
- [x] Style the sidebar as a card like the detail pane
- [x] Move the usage block into a detail card -- 8c7eb4a
- [x] Fill the History card to its height -- aaceb05
- [x] Show question boxes in terminal when it is frontmost -- 85dd8c7
- [x] Stop a hung ccusage scan from freezing the totals poller -- 9387f19
- [x] Retry only the daily ccusage call when unpriced -- 9387f19
- [x] Count only blocked sessions as needs you in the fleet bar -- 5def87c
- [x] Show context tokens on idle rows -- 4301061
- [x] Report a git action that did not report back honestly -- 033feff
- [x] Stop the reply notice claiming a turn for clear and compact -- 64d6b53
- [x] Show usage totals off when polling is disabled -- 9fafa43
- [x] Check the build exists before run-sh replaces the app -- 5147808
- [x] Untrack the regenerable ds-bundle files -- 37a7512
- [x] Record spend over time for a Cost trend chart
- [x] Observe the Cost trend chart on screen
- [x] Observe the sidebar toggle and todo bar on screen
- [x] Feed the todo bar from TaskCreate task lists
- [x] Give push/pull/merge a longer timeout than status probes
- [x] Stop Clear/Compact reporting failure when they worked
- [x] Keep tmux/ps calls off the main thread with a timeout
- [x] Pin the merge to the PR number that was confirmed
- [x] Match installed hooks on script path, not substring
- [x] Delete merged branch design-system-pass-2026-09-20
- [x] Block Merge on uncommitted changes
- [x] Draw detail-pane sections as cards
- [x] Hold the transcript card at one height
- [x] Pin a glass toolbar above the detail pane
- [x] Equalize detail card heights per row
- [x] Authenticate Figma and create the UI spec file -- figma, no commit
- [x] Check Figma has a mono font (Menlo or SF Mono) -- figma, no commit
- [x] Build unified tokens page (state, usage, menubar) -- figma, no commit
- [x] Build components page from SwiftUI views -- figma, no commit
- [x] Build the panel popover screen -- figma, no commit
- [x] Build the window screen -- figma, no commit
- [x] Add dark-mode frames and the conflict log page -- figma, no commit
- [x] Fix dark-copy text still bound to Light colors
- [x] Add ccusage poller for today/week/block totals
- [x] Show usage totals line in the menu footer
- [x] Test ccusage parse (good, malformed, empty, no block)
- [x] [you] Look at the window's All sessions totals section
- [x] Record Figma URL and next Swift fix slices
- [x] Unify state colors across panel and window
- [x] Add one Notice style for info, warning and error
- [x] Label sidebar status and the sparkline
- [x] Cut the type scale to the five spec styles
- [x] Give git loading and empty stats visible states
- [x] Fix stale ask cards (ask.sh exit trap, prune dead pids)
- [x] Say "no current 5h reading" instead of "— of 5h" in the window overview
- [x] Rescope the Git actions empty state to "no actions available"
- [x] Test StatFormat.usagePercent for nil, zero and a real reading
- [x] [you] Confirm the policy round-trip by hand — right-click the icon while it is
  placed, Open Window, close it, expect `lsappinfo` to read `type="UIElement"`
  (not scriptable — status-item context menus aren't reliably reachable via
  AppleScript/System Events; needs a real click)
- [x] Confirm a SLOPED context line renders -- every session on this machine
  is Opus 1M and none has passed ~18%, so the flat-crawl case is the only one ever
  drawn here. Needs a session past ~50% of its window (500k on 1M, or any 200k
  session) to see the line climb on screen
- [x] Observe the cyan, jade and indigo identity hues on screen
- [x] Mark a borrowed model tag as a guess
- [x] Keep borrowed models apart in the models bar
- [x] Neutral ink-label so orange means working only
- [x] Replace todo bar with labelled ctx meter
- [x] Opaque panel ground and blue Needs you header
- [x] Collapse idle rows to one line
- [x] Relabel footer chg gauge as trend
- [x] Draw subagent connector glyph
- [x] Add per-row context sparkline to panel
- [x] Add 5h usage history sparkline to footer
- [x] Add larger context and usage charts to window
- [x] Draw session tree diagram in window
- [x] Add status and model breakdown bar to panel
- [x] Window strip reads the resolved 5h/7d usage
- [x] Let the test host run beside the live app
- [x] Drop the retired OpenWolf convention from HANDOFF
- [x] Drop stale poll usage when polling stops
- [x] Seed finished-turn set before first done banner
- [x] Stamp usage cache with the session's own time
- [x] Git probe returns nil when pipe reads time out
- [x] Escape folder names in AppleScript focus
- [x] Allow notifications for "claude spinner" -- granted 2026-09-15, banner
  answered end to end (hand-check)
- [x] Show the notifications-denied notice on both surfaces -- f2cf7ee
- [x] Re-read notification authorization when the app becomes active -- f2cf7ee
- [x] Confirm the context CHART renders -- observed 2026-09-15, no commit (hand-check)
- [x] Add FeedWatcher.projectSections with stable, non-ticking ordering -- fa8d2b0
- [x] Group the window sidebar by project -- fa8d2b0
- [x] Group the menu-bar panel by project -- fa8d2b0
- [x] Test projectSections, including the input-order regression -- fa8d2b0
- [x] Recolour the app icon to the Claude burst on red -- 9857727
- [x] Correct the CI claim in STATUS.md and log the finding -- 344a9af
- [x] Confirm the context meter renders (chart still open above) -- 344a9af
- [x] Sync the deployed /Applications copy with the current build -- no commit (deploy)

- [x] Probe whether GitHub-hosted macOS images can build this project -- a8c68e1
- [x] Install and register a self-hosted Actions runner on this Mac -- a8c68e1

- [x] Scope the context-history feature in docs -- 1ebd230
- [x] Sample per-session context tokens into a history buffer -- 1ebd230
- [x] Draw the context meter against the window -- 1ebd230
- [x] Draw the context trend on a time-scaled axis -- 1ebd230
- [x] Test the sampler and the chart geometry -- 1ebd230

- [x] Re-read the remote when HEAD or the branch moves -- eaf5cad
- [x] Order the post-action invalidate before the re-read -- eaf5cad
- [x] Split block reasons into settled and unknown -- eaf5cad
- [x] Hide settled actions, grey unknown ones with the reason inline -- eaf5cad
- [x] Show per-row read age and a Refresh button -- eaf5cad
- [x] Add Merge, gated on real mergeability -- eaf5cad
- [x] Resolve gh by path fallback and say so when it is missing -- eaf5cad
- [x] Test the merge gate, the settled flag, and the branch-change re-read -- eaf5cad
- [x] Say checks have not passed, not that they failed -- aa339f2

- [x] Show the command in the permission card -- e089338
- [x] Stop the reply field taking first responder on window open -- caa02e1
- [x] Say the true reason Pull is unavailable -- e089338

- [x] Add SessionFeed.restingEvidence(now:) -- resting-evidence string
- [x] Show resting evidence on panel idle rows
- [x] Show resting evidence in the window detail pane
- [x] Test restingEvidence and the column budget

- [x] Add GitStatus.swift: snapshot model and pure parsers
- [x] Add the per-cwd git prober with cache and timeouts
- [x] Add GitActions: open PR, push, create PR, pull
- [x] Wire the Git section into the window detail pane
- [x] Test the git parsers and availability rules

- [x] Add an overview strip: spend, context, turns, burn sparkline -- b7fe36f
- [x] Build TranscriptReader for what Claude is actually doing -- 6a44b42
- [x] Add session actions: interrupt, compact, clear, reveal, open transcript -- bc8158e

- [x] Decode the rest of the statusLine fields into the detail pane -- 3cc145e

- [x] Write ask.sh, the blocking hook for AskUserQuestion and PermissionRequest -- 62c5703
- [x] Carry `message` forward in emit.sh so the banner body is not empty -- 62c5703
- [x] Install and register ask.sh from SetupInstaller -- 02c060e
- [x] Watch asks/ and post notifications whose buttons are the option labels -- 8f692eb
- [x] Handle notification answers and write the answer file -- 8f692eb
- [x] Add the attention signals: status-item pulse, time-sensitive, guarded bounce, done alert -- 4f10aa9
- [x] Build SessionReplier for free-text reply into a tmux pane -- b9f30f8
- [x] Unit-test the pure pieces and extend the content-parity test -- 4f10aa9
- [x] Build a full window UI beside the menu bar: sidebar, session detail -- 4f10aa9
- [x] Surface pending asks and reply in the window detail pane -- 4f10aa9
- [x] Verify end to end on both a known-good and a known-bad input -- 4f10aa9

- [x] Nest subagent sessions under their parent row — child hooks write
  `<parent>.<agent_id>.state.json`; the panel indents them as 2-line children.
  95 unit tests; done 2026-08-17
- [x] Add a Show in preference so the surface is chosen, not luck — done 2026-08-12
- [x] Fix the stale CI test count in STATUS — done 2026-08-12
- [x] Document the macOS 27 floor and the DerivedData glob trap — done 2026-08-12
- [x] Extract a pure, tested status-item placement predicate — done 2026-08-12
- [x] Log measured frames when placement detection fires — done 2026-08-12
- [x] Re-check status-item placement on display change — done 2026-08-12
- [x] Restore accessory policy when the window closes — done 2026-08-12
- [x] Reach the settings menu from the window — done 2026-08-12
- [x] Show live session status in the window title — done 2026-08-12
- [x] Record the window-fallback decision in STATUS — done 2026-08-12

- [x] Popover clipped off-screen near the right menu-bar edge — panel width is now a runtime `@Published` clamped to the status item's screen `visibleFrame` (`fittedPanelWidth`, floor 360, margin 16) at show time in `togglePopover`; `RowLayout.columns` takes the width so rows reflow/truncate instead of overflowing; `Columns` carries `.status` so `displayStatus` drops the duplicated span math. 62/62 tests (added fittedPanelWidth + min-width column tests). Near-edge visual confirm still needs a hand (drag icon far right, click); done 2026-07-21

- [x] reset-notifier merged from `claude/usage-count-reset-notification-8qtypf` (`c2a9fff`) — launchd agent warns 30 min before each 5h reset, banner-only (no ntfy topic configured). Cherry-picked the feature commit alone; the branch's two bookkeeping commits carried gitignored `.wolf` runtime state that `f20aa61` had removed. Installed and verified: 13/13 notifier tests, 61/61 Swift tests, agent loaded, live dry-run correct. Remote branch deleted (tip `18bd9d0` if it's ever needed back); done 2026-07-18

- [x] `xcodebuild test` runner bootstrap — this is **bug-094**, not a new failure. Unit tests are app-hosted and the single-instance guard `exit(0)`s the test host when a copy of the app is already running. `killall "claude spinner"` first and the suite is 61/61 green (verified twice, 2026-07-18). The "fails on BOTH targets" report was wrong on the second half: `claude spinnerUITests` isn't in the scheme, matching CI. Not a code bug — a launch-order constraint; closed 2026-07-18
- [x] Usage view: menu-bar title now reads `5h 4% · 4h50m` — the 5h percentage plus a countdown to that window's reset. A once-a-minute tick keeps it moving while idle; verified on screen, 61/61 unit tests green; done 2026-07-18

- [x] buglog.json race between concurrent sessions (bug-200) — post-write.js now serializes its read-modify-write behind a lockfile and mints `max+1` ids; proven by a barrier-synced 20-way race (old pattern lost 15/20, new kept 20/20); fixed 2026-07-17
- [x] Long tool name drew a double ellipsis (`running askuserqu……`) — RowLayout.fit pre-truncates the status label so SwiftUI never adds its tail `…` beside the working-dots; verified on screen with a throwaway MCP row; fixed 2026-07-17 (f3638a3, bug-201)
- [x] Verify the Zed fix by hand — verified 2026-07-17: clicking the row focused zed, Ghostty never launched
- [x] Name column truncates while the status column idles — fixed 2026-07-17 (4a6ccb7, bug-138)
- [x] 7d gauge reads as empty below 10% — fixed 2026-07-17 (9c675c5, bug-135)
- [x] `chg` gauge saturates at ≥20 points — fixed 2026-07-17 (ad68451, bug-136)
- [x] Settle the invisible ⌘Q button — fixed 2026-07-17 (a3fcb62, bug-137)

- [x] Fix run.sh's swiftc fallback — it listed three sources literally and never gained SetupInstaller.swift, so the non-Xcode path compiled nothing. Now globs `"claude spinner"/*.swift`, matching the synchronized root group (bug-132)
- [x] Zed sessions launch Ghostty instead of focusing Zed — SessionLauncher.resolveBundleID resolves an untabled-but-running bundle ID to itself, fixing every unlisted editor at once; Zed table entries + HostTag chip (bug-130)
- [x] "expired" shown for every poll failure — UsageFailure enum splits authExpired from transient; stopPolling clears it (bug-131)
- [x] Dead code — removed clearSession/usageModel/usageModelId; wired displayPath into the row tooltip
- [x] UsagePoller.start() leaked a timer on double-start — stop() first
- [x] First-run one-click fix — Install button in the Setup-needed panel: SetupInstaller writes the scripts + back-up-then-merges the hooks/statusLine into ~/.claude/settings.json (tested merge, e2e verified)

- [x] CI — shared scheme + GitHub Actions run the 27 unit tests (real xcodebuild build, UI tests skipped); caught missing import Combine (bug-093)
- [x] Regression test — SessionLauncher.guiFocusAction pure fn + XCTest locks "running host wins over path launch" (bug-072/073/091)
- [x] Host chip (vsc/trm/web/app) RIGHT of the row time, flips to ✕ on hover (one 26px slot)
- [x] Attention row label -> one alternating word (AttentionWords)
- [x] Surface poller state in footer — "blocked"/"expired" notice + tooltip detail
- [x] Footer countdown/notice aligns to the row times by construction (bug-071)
- [x] Fix clicking a session opening a NEW window — activate the running host, no path (bug-072)
- [x] Notification "Focus session" action (ATTENTION category + delegate)
- [x] PID pruning — emit.sh captures pid; FeedWatcher prunes idle dead-pid sessions (kill(pid,0))
- [x] Menu-bar urgency — usage % pulses red at 90%+ in usage mode
- [x] 7-day reset in the countdown tooltip; usage ring buffer persisted
- [x] Cache `usageSession` per publish (review #5) — sessions.didSet
- [x] `openSession` data-driven table — hostBundleIDs
- [x] First-run setup check — "Setup needed" hint when hooks aren't installed
- [x] Test `UsagePoller.parse(headers:now:)` — network-free XCTest + swiftc harness
- [x] Test `HostTag.from` classification

- [x] Testability seam + tests: extracted static displayItems/menuBarState/sorted over [SessionFeed]; swiftc harness + XCTest (usageTint tiers, grouping, menuBarState transitions)
- [x] Footer stale-usage freshness indicator (dim + "Xm old" + as-of tooltip)
- [x] Times right-aligned in their own column; row text lowercased; removed per-row context %

- [x] Unify attention text color — attention tint/statusColor now `.claude`; the orange background wash carries "needs you" without a second, redundant orange
- [x] Footer: show both reset formats — two-line footer, clock time + countdown (`↺ resets 2:00 AM · in 3h29m`)
- [x] Trim the bottom gap — sessions VStack pads top-only, closing the dead space above the footer
- [x] Fix Clear All deleting emit.sh — the hook emitter lives in the feed dir; Clear All wiped it and killed the whole feed. Restored emit.sh; clearAll now only removes session files
- [x] Persist usage — cache the last-known 5h/7d/model snapshot so it survives Clear All and statusLine-less sessions; usage no longer vanishes
- [x] Refresh action — right-click → Refresh (⌘R) forces a feed re-read
- [x] Collapse duplicate idle rows — never-worked idle sessions in the same folder group into one `home idle ×N` row
- [x] Visual verification in a live session — rows, title states, footer confirmed rendering
- [x] Attention alerts — macOS notification when a session enters `attention` (once per pause)
- [x] Menu-bar title mode toggle — right-click → Menu bar shows → Activity / Usage (persisted)
- [x] Color-code the row's context % by urgency (dim → amber → red)
- [x] 7d usage bar in the footer (both windows now show a 6-segment bar)
- [x] Unified bar glyphs — statusLine switched to `█░` to match the app
- [x] Accessibility — VoiceOver labels on rows and the menu-bar label
- [x] Status refresh — 3-state menu title (working / done-flash / idle grey), concrete-activity rows, model-color + urgency-gradient footer
- [x] Usage footer — 5h + 7d limits with urgency colors; hide cost on Max plan; restore the bar
- [x] Settings moved to right-click menu; panel anchored under the icon (NSStatusItem + NSPopover)
- [x] Menu-bar jitter fix (fixed-width glyph); brighter, higher-contrast title
- [x] One-line dropdown rows; reuse Ghostty window on click (no duplicate processes)
- [x] Stop feed-file leak; atomic status.json writes; background rescan off main thread
- [x] Typed JSON decoding; remove dead LoginItem.swift; extract Constants

<!-- resume-footer -->
---
Plan approved 2026-09-30 05:40.

Sessions start in "plan" (permissions.defaultMode in
~/.claude/settings.json). Bypass is reachable in the Shift+Tab cycle only
when launched via `cb` (--allow-dangerously-skip-permissions); `yolo`
(--dangerously-skip-permissions) starts in bypass outright.

Only if Claude Code actually closed:

    claude --resume 97eb3b30-ec31-412d-aea9-7625bafa3db9

(`-c` resumes the most recent session; bare `--resume` opens a searchable picker.)
<!-- /resume-footer -->
