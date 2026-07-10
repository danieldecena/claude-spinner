# claude-spinner — Tasks

## Tasks

Remaining from the "apply all" improvement batch (poller hardening + menu title DONE):

- [ ] Host tag on rows — small color-coded tag left of the time: vsc=VSCode (blue), trm=terminal (green), web=website (cyan), app=desktop app (purple), from `session.host`
- [ ] Surface poller state in footer — show `usageError` (auth expired) and `pollUsage.overageBlocked` (out of credits) subtly; both already parsed in FeedWatcher
- [ ] PID pruning — capture the claude PID in `~/.claude/spinnerfeed/emit.sh` (walk up from $PPID to the process whose command contains "claude"; write `pid`), prune sessions whose pid is dead (`kill(pid,0)`) on the 2s rescan. CAUTION: only prune idle sessions with a captured pid; a wrong/ephemeral pid would wrongly remove a live session — test capture first
- [ ] Menu-bar urgency — flash/pulse the usage % red at 90%+ in usage mode
- [ ] Notification action — add a "Focus session" button to the attention notification (UNNotificationAction + category)
- [ ] 7-day reset in tooltip + a small usage sparkline (needs a persisted ring buffer of poll samples)
- [ ] Cache `usageSession` per publish (review #5) — it re-scans `sessions` ~7x/sec in the footer tick
- [ ] `openSession` data-driven table (review) — collapse the 4 identical `["-b", bundleid]` focus arms
- [ ] First-run setup check — detect whether the spinner hooks + statusline are installed; show a warning/one-click fix. (Notarization needs an Apple Developer cert — can't be done in the agent env; note for the canonical build.)
- [ ] Test `UsagePoller.parse(headers:now:)` — add harness + XCTest cases (pure, network-free)

## Completed

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
