# First-run one-click installer — design

Date: 2026-07-10

## Context

Claude Spinner only shows sessions when two things are in place: the emitter
script `~/.claude/spinnerfeed/emit.sh` exists, and `~/.claude/settings.json`
wires it into the Claude Code lifecycle hooks (plus a `statusLine` that writes
the per-session `status.json` the app reads for usage). Today the app only
*detects* the missing plumbing — `FeedWatcher.isSetupInstalled` checks for
`emit.sh` + a settings.json reference — and shows a "Setup needed" hint telling
the user to wire it up by hand. A fresh install is therefore dead until the user
manually edits their config.

This feature adds a one-click installer: a button in the "Setup needed" state
that writes the scripts and merges the hooks into `settings.json` safely, so the
app works out of the box.

A prerequisite gap discovered while scoping: `emit.sh` and
`statusline-command.sh` are **not** in the repo or the app bundle — they exist
only in the developer's live `~/.claude/`. The app must carry them to install
them.

## Goals

- One click in the "Setup needed" state fully wires up the feed on a fresh Mac.
- Never clobber existing user config in `settings.json`; changes are reversible.
- Idempotent: clicking when partially/fully installed adds only what's missing.

## Non-goals

- No uninstaller.
- No settings.json diff-preview UI (chose back-up-then-merge over preview).
- No management of unrelated hooks the user already has.

## Design

### 1. Ship the scripts (prerequisite)

Vendor the current live `emit.sh` and `statusline-command.sh` into the repo
under `scripts/`, and add both to the app target's *Copy Bundle Resources* build
phase so they ship inside `claude spinner.app/Contents/Resources/`. These become
the single source of truth for what the installer writes.

Requires an Xcode project (`project.pbxproj`) edit to add the two files as
resources.

### 2. `SetupInstaller` (new file: `claude spinner/SetupInstaller.swift`)

A small enum/namespace with one entry point and one pure helper.

`static func install() -> Result<Void, Error>` performs, in order:

1. Create `~/.claude/spinnerfeed/` if absent.
2. Copy bundled `emit.sh` → `~/.claude/spinnerfeed/emit.sh` and
   `statusline-command.sh` → `~/.claude/statusline-command.sh`; `chmod 0755`.
3. If `~/.claude/settings.json` exists, copy it to
   `settings.json.backup-<epoch>` first.
4. Parse settings.json into `[String: Any]` (or start from `[:]` if the file is
   absent). Call the pure merge helper. Write the result atomically (write to a
   temp file in the same dir, then `FileManager.replaceItemAt`).

`static func mergeSpinnerHooks(into settings: [String: Any]) -> [String: Any]`
— pure, no I/O:

- For each of the 7 hook events — `SessionStart`, `PreToolUse`, `PostToolUse`,
  `UserPromptSubmit`, `Notification`, `SessionEnd`, `Stop` — ensure the event's
  array under `hooks` contains a matcher group whose command is
  `~/.claude/spinnerfeed/emit.sh <Event>`. Append the group only if no existing
  entry already references `emit.sh` for that event (idempotent).
- If `statusLine` is absent, set it to
  `{ "type": "command", "command": "bash ~/.claude/statusline-command.sh" }`.
  Leave any existing `statusLine` untouched.

Hook entry shape mirrors the working config (matcher `""` for the event-wide
hooks; `SessionStart`/`Stop`/`PostToolUse`/`PreToolUse` use `matcher: ""`,
the rest use a bare `hooks` array):

```json
{ "matcher": "", "hooks": [ { "type": "command",
  "command": "~/.claude/spinnerfeed/emit.sh SessionStart" } ] }
```

### 3. UI (`MenuContentView`, "Setup needed" block)

Add an **Install hooks** button beneath the existing hint text. On tap:

- Run `SetupInstaller.install()` on a background queue.
- On `.success`: recompute `FeedWatcher.isSetupInstalled` (currently a `lazy`
  var — change to a recomputable check or add a `refreshSetupState()` that
  re-runs `checkSetupInstalled` and publishes) and show "Installed — restart
  your Claude Code sessions to start the feed." (New sessions pick up the hooks;
  the session that clicked won't retroactively emit.)
- On `.failure`: show the error message and keep the existing manual-paste hint
  as the fallback.

### 4. Format tradeoff

The merge round-trips settings.json via `JSONSerialization`
(`.sortedKeys, .prettyPrinted`), so an existing rich settings.json is reformatted
(keys reordered) — data is preserved and the timestamped backup makes it
reversible. On a genuine first run the file is minimal or absent, so reformatting
is moot. Accepted over a bespoke order-preserving JSON editor.

### 5. Error handling

- settings.json exists but is unparseable JSON → abort before writing anything,
  return `.failure` with a message pointing the user at the manual hint. (Real
  case, handled; do not silently overwrite a malformed file.)
- Script copy failures (permissions) → `.failure` surfaced in the UI.

## Testing

Unit tests for the pure `mergeSpinnerHooks(into:)` in `claude_spinnerTests`
(runs under the new CI):

- Empty settings (`[:]`) → all 7 hook events present + `statusLine` set.
- Already-installed settings → merge is a no-op (idempotent; count unchanged).
- Partial (some events wired, some not) → only the missing events added; a
  pre-existing `statusLine` is left untouched.

Manual verification: temporarily point `HOME`/the target dir at a scratch dir
(or move the live config aside), launch the app so it shows "Setup needed",
click Install, confirm files written + settings.json merged + panel flips to
"No active sessions". Restore the real config after.

## Files touched

- `scripts/emit.sh`, `scripts/statusline-command.sh` — new (vendored).
- `claude spinner.xcodeproj/project.pbxproj` — add the two resources.
- `claude spinner/SetupInstaller.swift` — new.
- `claude spinner/MenuContentView.swift` — Install button in the setup block.
- `claude spinner/FeedWatcher.swift` — make setup state recomputable/publishable.
- `claude spinnerTests/claude_spinnerTests.swift` — merge tests.
