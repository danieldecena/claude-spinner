# claude-spinner — Tasks

## Tasks

- [ ] Confirm the policy round-trip by hand — right-click the icon while it is
  placed, Open Window, close it, expect `lsappinfo` to read `type="UIElement"`

Notarization was dropped 2026-07-21 (needs a paid Developer Program account;
not being pursued) — the app ships as a locally-built, ad-hoc-signed `.app`
via `run.sh`.

## Completed

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
Plan approved 2026-08-12 21:10.

Sessions start in "plan" (permissions.defaultMode in
~/.claude/settings.json). Bypass is reachable in the Shift+Tab cycle only
when launched via `cb` (--allow-dangerously-skip-permissions); `yolo`
(--dangerously-skip-permissions) starts in bypass outright.

Only if Claude Code actually closed:

    claude --resume f8daf528-bf4c-46c0-b864-f0725780c45f

(`-c` resumes the most recent session; bare `--resume` opens a searchable picker.)
<!-- /resume-footer -->
