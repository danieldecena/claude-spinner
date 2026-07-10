# claude-spinner — Handoff

A macOS menu-bar app that mirrors live Claude Code sessions (status, activity, and
account usage) in the menu bar, with a dropdown panel of per-session rows and a
usage footer. Written in SwiftUI + AppKit.

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

### Source files (`claude spinner/`)
- `claude_spinnerApp.swift` — `@main` App (empty `Settings` scene), `AppDelegate`
  owning the `NSStatusItem` + `NSPopover`, the right-click settings menu,
  `MenuBarLabel`, `Spinner` frames, and Color/Font extensions (incl. `claude`,
  `claudeBright`, `menuIdle`, `usageTint`, `contextTint`, `modelTint`).
- `FeedWatcher.swift` — `Constants`, enums (`SessionStatus`, `MenuBarMode`,
  `MenuBarState`), Codable `StateFile`/`StatusFile`, `SessionFeed`, `UsageSnapshot`,
  `SessionRowItem`, and the `FeedWatcher` observable (watch/rescan/prune, state
  derivation, usage getters, actions).
- `MenuContentView.swift` — the dropdown panel: `UsageFooter` and `SessionRow`.
- `claude spinnerTests/claude_spinnerTests.swift` — XCTest over the pure logic.

---

## Build / run

- **Canonical build:** open `claude spinner.xcodeproj` in Xcode, Run (or Archive).
  The app targets **macOS 27** (dev machine).
- **Tests:** Cmd+U in Xcode (or an Xcode connector). CI can't run them (see below).
- **Dev loop used this session (no Xcode available in the agent env):** compile the
  three sources with `xcrun --sdk macosx swiftc -O -target arm64-apple-macos27.0 …`,
  copy the binary into the installed bundle's `Contents/MacOS/`, `codesign --force
  --deep --sign -`, and relaunch. There's also a **Relaunch** item in the app's
  right-click menu.
- **CI** (`.github/workflows/swift.yml`): a `swiftc -typecheck` at macOS 14 — a
  compile check only. A full `xcodebuild archive` is infeasible on GitHub runners
  because the app targets macOS 27; running XCTest needs Xcode. Green as of handoff.

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
- These are also logged in `.wolf/cerebrum.md` (Do-Not-Repeat) and `.wolf/buglog.json`.

---

## Done this session (high level)

Core review fixes (click-to-open, feed-file leak, atomic status.json writes,
main-thread rescan → background + debounce, typed Codable decoding, dead
`LoginItem` removal, `Constants`). Presentation: `NSStatusItem`+`NSPopover` anchored
under the icon, jitter-free fixed-width spinner glyph, brighter title, one-line
concrete-activity rows, 3-state title (working / done-flash / idle-grey), fully-grey
idle rows. Usage footer: model-family color + green→red urgency gradient bars, 5h +
7d, cost hidden (Max), reset as clock time, persisted cache. Right-click menu:
Activity/Usage title toggle, Refresh, Relaunch, Clear All (safe), Quit. Attention
macOS notifications. Collapse duplicate idle rows. Copy Session ID / Path per-row
context menu. Host-aware click routing. Accessibility labels. XCTest suite + a
`pendingScan` race fix.

Full history is in the git log and `TASKS.md` (`## Completed`).

---

## Open / Next up

Board is clear. One known limitation remains, deferred by design:

- Focusing the **exact** terminal tab on click is infeasible — macOS `open` can't
  target the tab running a session. Resolved as far as possible: a click now focuses
  the host app *without* spawning a new window (VS Code opens the folder in place; an
  unknown host focuses the user's terminal). Revisit only if per-terminal scripting
  (iTerm Python API / Terminal AppleScript) is ever worth the fragility.

---

## Working conventions

- TDD for new behavior (red → green → refactor). No Xcode in the agent env, so the
  test runner is a `swiftc` harness (compile `FeedWatcher.swift` + a `main.swift`
  with a `Spinner` stub, assert, run) mirrored into the XCTest file.
- OpenWolf: update `.wolf/anatomy.md`, `.wolf/memory.md`, `.wolf/cerebrum.md`,
  `.wolf/buglog.json`; check them before editing/creating.
- Commits: imperative subject, `Co-Authored-By: Claude <noreply@anthropic.com>`.
