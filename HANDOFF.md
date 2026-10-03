# claude-spinner — Handoff

A macOS app that mirrors live Claude Code sessions (status, activity, account
usage) and lets you act on them: a menu-bar dropdown for a glance, and a window for
everything that does not fit in one (answer a question or a multi-question form,
reply, watch a project, resume a past session, and see what the Music app is
playing). SwiftUI + AppKit, macOS 27 only.

Repo: https://github.com/danieldecena/claude-spinner (private). Runs live as
`/Applications/claude spinner.app`.

---

## How it works (architecture)

Two independent feeds, both under `~/.claude/spinnerfeed/`:

1. **Hook feed → `<id>.state.json`** — written by `~/.claude/spinnerfeed/emit.sh`,
   invoked from Claude Code lifecycle hooks (SessionStart, UserPromptSubmit,
   PreToolUse, PostToolUse, Notification, Stop, SessionEnd — wired in
   `~/.claude/settings.json`). Carries `status`, `tool`, `cwd`, `host`, `message`,
   `turn_start`, `last_seed`, `last_duration`, `updated`. Drives **sessions +
   activity**.
2. **StatusLine feed → `<id>.status.json`** — written by
   `~/.claude/statusline-command.sh` (the CC statusLine command), which dumps the
   raw statusLine stdin JSON. Carries `model`, `context_window.used_percentage`,
   `rate_limits.five_hour/seven_day`. Drives **usage** (only written when a session
   renders a status line — i.e. an interactive TUI session, not `--output-format
   stream-json` / SDK sessions).

The app (`FeedWatcher`) watches the directory with a `DispatchSource` vnode source
+ a 2s safety timer, reads/parses off a background `ioQueue`, and publishes
`[SessionFeed]` on the main thread. Usage is cached to `UserDefaults`
(`UsageSnapshot`) so it survives Clear All and statusLine-less sessions.

### Surfaces

- **Menu-bar dropdown** (`MenuContentView.swift`): per-session rows and a usage footer.
- **The window** (`WindowContentView.swift` and the files it hosts), opened on Home:
  a full-height see-through sidebar (sessions grouped by project, pinned projects,
  each project's TASKS.md), and a detail pane that is Home, the App Kit showcase, a
  pinned project's page, or one session.
- **A floating reply bar** over the detail pane: it speaks to the open session, else
  the one that needs you, else the most recently working, keeps a draft per session,
  and shows what Music is playing while Music is open.
- **Answering from the app**: a single question is answered by typing its digit into
  the terminal box; a multi-question or multi-select ask is held in the
  `PreToolUse` hook (`Scripts/ask.sh`) and answered from the card. The Allow/Deny card
  for `AskUserQuestion` does not exist.

`docs/WIREFRAMES.md` draws every surface as text, labelled with the struct and file
that draws it; read it before a layout change and update it in the same commit.

### Source files (`claude spinner/`)

Feeds and state
- `claude_spinnerApp.swift` -- `@main`, `AppDelegate` (status item, popover, main
  window), `MenuBarTitle`, `Spinner` frames, the palette (`Color.Ink`) and `Font.ui`.
- `FeedWatcher.swift` -- `Constants`, `SessionFeed`, `UsageSnapshot`, and the
  `FeedWatcher` observable (watch, rescan, prune, state derivation).
- `TranscriptReader.swift`, `GoalClock.swift`, `SystemStats.swift` -- what a session
  said and ran, timed `/goal` runs, CPU/memory/disk.
- `SetupInstaller.swift`, `SetupBanner.swift` -- first-run **Install hooks**.

The window
- `WindowContentView.swift` -- window shell, `SessionSidebar` (+ `SidebarScrim`,
  `SidebarGlyph`, `SidebarRowChrome`), `SessionDetail` + `PaneFit`, `AskCard` /
  `AskFormCard`, `ConversationCard`, `ReplyBox`, `WindowToolbar`, `ActionBar`.
- `HomeDashboard.swift`, `MailCard.swift`, `CalendarCard.swift`, `DraftReplies.swift`,
  `GraphifyCard.swift`, `StatCards.swift` -- the Home tab and the cards on it.
- `PinnedProjects.swift`, `PinnedProjectDetail.swift` -- the pinned pages;
  `TopPicks.swift` (hero cards), `SessionShelf.swift` (recent sessions),
  `ArtifactView.swift` (live artifact pages, pop-outs).
- `FloatingBar.swift` (`BarTarget`, `ReplyDrafts`, `ReplySend`, the bar),
  `MusicStrip.swift`, `NowPlaying.swift` (Apple Events to Music, never launches it),
  `BarTint.swift` (cover tint).
- `AskInbox.swift` + `Scripts/ask.sh` -- the ask files, the hook that answers them,
  and notifications for them. `Scripts/emit.sh` and `Scripts/statusline-command.sh`
  are the feed writers.
- `SessionReplier.swift`, `SessionActions.swift`, `NewSession.swift`,
  `SkillShortcuts.swift`, `Suggestion.swift`, `Git*.swift` -- acting on a session.
- `Notice.swift`, `NotificationsNotice.swift` -- inline notices.
- `AppKitShowcase.swift`, `AppKitMusicComponents.swift`, `AppKitTokens.swift` -- the
  App Kit design system tab. The last two are **generated**: change App Kit and run
  `./sync-appkit.sh`, never edit them by hand (`sync-appkit.sh --check` flags drift).

### Tests (`claude spinnerTests/`)
`claude_spinnerTests.swift` (feed, asks, hooks, palette contrast) plus one file per
newer area: `PinnedProjectsTests`, `CalendarCardTests`, `MailCardTests`,
`DraftRepliesTests`, `FloatingBarTests` (drafts and the no-switch rule),
`NowPlayingTests` (nothing is sent while Music is closed), `BarTintTests`,
`MusicAccentProofTests` (red accent measurements and renders). Sources are a
synchronized group: a new `.swift` file joins its target with no project edit.

---

## Build / run

- **Canonical build:** `./run.sh` (xcodebuild when full Xcode is selected, else
  a `swiftc` fallback that copies into `/Applications/claude spinner.app`).
  The app targets **macOS 27** (hard floor). Cursor debug uses a preLaunchTask
  that resolves `BUILT_PRODUCTS_DIR` the same way; do not hardcode a DerivedData
  hash.
- **Tests:** `killall "claude spinner"` then `xcodebuild -scheme "claude spinner" test`
  (optional `xcbeautify` on the pipe). Unit target only; UITests are skipped in
  the shared scheme. Cmd+U in Xcode still works.
- **CI** (`.github/workflows/swift.yml`): self-hosted macOS runner, real
  `xcodebuild test` (not `swiftc -typecheck`). GitHub-hosted runners cannot open
  Xcode 27 format 110. Green as of handoff.

---

## Gotchas / non-obvious

- **`emit.sh` lives inside the feed dir.** Any bulk delete of `~/.claude/spinnerfeed/`
  must skip non-feed files — `clearAll()` filters to `*.state.json`/`*.status.json`/
  `*.status.txt` (`sessionId(from:) != nil`). Deleting `emit.sh` kills the whole
  feed ("No active sessions" forever).
- **Never inject demo data into the live feed dir** — a static `status.json` written
  for a preview lingers and shows frozen fake usage. Clean up test data in the same
  step.
- **Usage needs a statusLine-rendering session.** VS Code extension / SDK sessions
  (`--output-format stream-json`) fire hooks but don't render a status line, so no
  usage. The `UsageSnapshot` cache bridges the gap once any TUI session writes it.
- **Host detection** uses `__CFBundleIdentifier` (fallback `TERM_PROGRAM`) captured
  by `emit.sh`; the row click routes to that host (VS Code/Ghostty/Terminal open the
  folder; iTerm2 + Claude desktop are just focused).

---

---

## Open / Next up

- Focusing the **exact** terminal tab on click is infeasible (`open` cannot target
  the tab running a session). Deferred by design.
- Trends (cache-hit and wall/API history) are parked: the Usage card of rings already
  shows every scalar, and the saved-history format change is a migration risk.
- Not yet seen live: a tinted bar (the cover tint falls back to plain glass for bright
  covers, so it needs a dark cover, which means changing the user's track) and
  play/pause/previous/next (they change what the user is listening to). A form
  answered with a draft in the bar, and the light appearance of the pinned page and the
  bar, were seen on 2026-10-03.
- After installing a build with a new signing identity, macOS may ask again for
  Calendars and Automation (Ghostty, Music).
- Decisions and the reasoning behind them are in `STATUS.md`; titles of what is done
  are in `TASKS.md`.

---

## Working conventions

- TDD for new behavior (red → green → refactor). Tests run with
  `xcodebuild -scheme "claude spinner" test` after `killall "claude spinner"`.
  The old agent-env `swiftc` harness is gone.
- State lives in `STATUS.md` (decision log for findings and reasoning) and
  `TASKS.md` (titles only). `.wolf/` is frozen legacy from the retired OpenWolf
  setup: do not read or update it.
- Commits: imperative subject, `Co-Authored-By: Claude <noreply@anthropic.com>`.
