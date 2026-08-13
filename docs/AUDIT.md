# Audit — 2026-08-12 (re-run)

Second pass, after the surface-preference work. Every claim below was checked against
`git ls-files`, `git check-ignore`, or the file itself. The first pass's three risks are
re-verified at the bottom rather than restated.

## Blockers

- (none)

## Risks

- [ ] **`STATUS.md:12` says "66 unit tests green"; the suite is 67.** It sits under
  `## Confirmed working`, which is present-tense state, so a stale number reads as a
  current one. This is the *same defect this audit closed an hour ago* at `STATUS.md:15`
  — reintroduced by writing the count into a second place and then updating only the
  first. The fix is the number; the lesson is that a figure worth asserting twice is
  worth asserting once.
  *Not* to be touched: `STATUS.md:218` ("56 unit tests") is inside a dated decision-log
  entry and was true when written.

## Notes

- **`HANDOFF.md:39` lists `FeedWatcher.swift`'s enums and omits `Surface`.** Cosmetic;
  the file was last touched at `4dbffc5`, before the enum existed. Worth a word next
  time HANDOFF is edited, not worth a commit of its own.
- **The `window`-surface early return skips five things, all correctly.** Verified by
  reading the branch, not by assuming: status item creation (the point of the branch),
  button UI, button action wiring, the 2-second placement check, and the screen-parameters
  observer. Each is meaningless without a status item, and `installSettingsMenu()` —
  the one piece that matters in both surfaces — is called inside the branch before the
  return.
- **Every remaining `statusItem` use is nil-safe.** All reach it through optional
  chaining or a guard that returns; `statusItemFrames` returns nil, which makes
  `statusItemIsUnplaced` true, which is what keeps `windowWillClose` from dropping the
  window surface's Dock icon.
- **The `surface` preference matches its neighbours exactly** — `@Published` +
  `didSet` writing `UserDefaults`, read back through `flatMap(init(rawValue:)) ?? default`,
  the same shape as `menuBarMode` and `usagePollingEnabled`, with a test covering the
  absent and unrecognized cases.
- **Working tree clean**, nothing untracked, no stashes, `origin/main` at `0/0`.
- **No secrets.** The OAuth token is still read from the keychain at call time and never
  persisted or logged, in both the app and `reset-notifier/check-reset.sh`.
- **`reset-notifier/` is untouched by this work** and its fixture-driven suite still
  applies — it reads the same feed directory and knows nothing about surfaces.

## Previously closed, re-verified

- `STATUS.md:15` CI test count — now 67, correct.
- `graphify-out/` — 0 tracked files, whole directory in `.gitignore`.
- `CLAUDE.md` — states the macOS 27 floor and warns against globbing
  `DerivedData/claude_spinner-*`.
