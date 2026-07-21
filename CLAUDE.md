# claude-spinner

macOS menu-bar app (Swift / SwiftUI, Xcode project) that shows a live panel of
running Claude Code sessions — model, status, context tokens, rate-limit gauges —
driven by the `~/.claude/spinnerfeed/` feed files that the hooks and `statusLine`
in `~/.claude/settings.json` emit.

> Session state is split per the standard convention: **`STATUS.md`** (confirmed
> working / known broken / next up) and **`TASKS.md`** (titles only). `HANDOFF.md`
> is the longer-form handoff. This file is the static how-it-works reference.

## Build & run

```bash
./run.sh          # build (xcodebuild if full Xcode, else swiftc fallback) + relaunch
```

`run.sh` derives the built `.app` from `BUILT_PRODUCTS_DIR` (DerivedData hash is
not fixed) and `killall`s the running copy before relaunching.

## Test

```bash
killall "claude spinner" 2>/dev/null   # UI-focus tests fail against a live instance
xcodebuild -scheme "claude spinner" test | xcbeautify
```

Unit target only — `claude spinnerUITests` is intentionally not in the scheme
(matches CI). CI runs on a **self-hosted** runner: the project is Xcode 27 format
110, which GitHub-hosted runners can't open.

## Gotchas

- **Sources are a synchronized group** — a new `.swift` file auto-joins the Xcode
  target with no `pbxproj` edit. The `swiftc` fallback in `run.sh` globs `"claude
  spinner"/*.swift` for the same reason; never hand-list sources.
- The deployed app at `/Applications/claude spinner.app` is a separate copy —
  `run.sh`'s fallback branch re-signs it in place after building.
- Clicking a panel row focuses the editor the session runs in; that needs
  Accessibility permission for the host app.
