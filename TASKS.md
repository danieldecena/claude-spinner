# claude-spinner — Tasks

## Tasks

- [ ] Attention alerts — post a macOS notification when a session needs you (status=attention)
- [ ] Color-code the row's context % by urgency (green→amber→red as it fills)
- [ ] Add a 7d usage bar in the footer (match the 5h bar)
- [ ] Unify the usage-bar segments — app draws 8, statusLine draws 10
- [ ] Accessibility: VoiceOver labels for rows and the menu-bar label
- [ ] Visually verify the status refresh (title states + footer colors) in a live terminal session

## Completed

- [x] Status refresh — 3-state menu title (working / done-flash / idle grey), concrete-activity rows, model-color + urgency-gradient footer
- [x] Usage footer — 5h + 7d limits with urgency colors; hide cost on Max plan; restore the bar
- [x] Settings moved to right-click menu; panel anchored under the icon (NSStatusItem + NSPopover)
- [x] Menu-bar jitter fix (fixed-width glyph); brighter, higher-contrast title
- [x] One-line dropdown rows; reuse Ghostty window on click (no duplicate processes)
- [x] Stop feed-file leak; atomic status.json writes; background rescan off main thread
- [x] Typed JSON decoding; remove dead LoginItem.swift; extract Constants
