# claude-spinner — Tasks

## Tasks

Remaining open items:

- [ ] Verify the Zed fix by hand — click a Zed session's row; it must focus the running Zed window, not open a Ghostty one. Unit-green only; this branch has regressed 4x (bug-004/072/091/110) and can't be driven without Accessibility permission.
- [ ] Name column truncates while the status column idles — rows show `continue from…` / `review code an…`. Status text is bounded (`thinking`, `needs input`, `done`, `running <tool>`); session names are unbounded prose. The flexible column should be the name, not the status. Requires rederiving the whole `Constants.panelWidth` budget.
- [ ] 7d gauge reads as empty below 10% — `UsageGauge` dims the fill to 35% opacity under 10%, so an 8% bar is indistinguishable from an unfilled track and the label does all the work.
- [ ] `chg` gauge saturates at ≥20 points — `+52%` and `+20%` render identically. Also partly redundant with the 5h number beside it; decide whether it earns a third of the footer.
- [ ] Settle the invisible ⌘Q button (`MenuContentView.swift:94`) — `.opacity(0)` stays hit-testable in SwiftUI, so a real quit button sits at the panel's centre behind the rows. Likely unreachable, but `.allowsHitTesting(false)` is free and removes the guess.
- [ ] Notarization — needs an Apple Developer cert; can't be done in the agent env.

## Completed

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
