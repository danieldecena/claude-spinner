# claude-spinner — Tasks

## Tasks

Remaining open items:

- [ ] Notarization — needs a **Developer ID Application** cert (only an Apple Development cert is installed, which can't notarize) plus notarytool credentials. Needs a paid Developer Program account and the user's Apple ID.
- [ ] Usage view: show remaining time until rate-limit reset alongside the "5h 70%" menu bar readout (requested 2026-07-18). `fiveHourResetsAt` already exists per cerebrum; 7d window may need the same. Verify visually via ./run.sh + capture; test runner currently broken (see home TASKS.md).

## Completed

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
