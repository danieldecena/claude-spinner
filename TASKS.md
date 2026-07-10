# claude-spinner — Tasks

## Tasks

_None open._

## Completed

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
