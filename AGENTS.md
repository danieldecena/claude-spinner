# AGENTS.md

`claude-spinner` is a **macOS-only** menu-bar app (SwiftUI + AppKit, Xcode
project). See `CLAUDE.md` and `HANDOFF.md` for the architecture and the canonical
build/test/run commands (`./run.sh`, `xcodebuild … test`), all of which require
macOS + Xcode 27.

## Cursor Cloud specific instructions

The Cloud Agent VM is **Linux (Ubuntu x86_64)**. The primary product — the
menu-bar app — **cannot be built, run, or unit-tested here**, and this is a hard
platform limitation, not a setup gap:

- The sources import `AppKit`, `SwiftUI`, `ServiceManagement`, `UserNotifications`,
  `CoreGraphics`, and `Darwin` — Apple frameworks that do not exist on Linux.
- It targets `MACOSX_DEPLOYMENT_TARGET = 27.0` and the project is Xcode 27 format
  (`objectVersion = 110`); the build needs `xcodebuild` / `xcrun --sdk macosx`,
  which are macOS-only. Even GitHub-hosted macOS runners can't open it, so CI uses
  a **self-hosted macOS** runner (`.github/workflows/swift.yml`).
- Do **not** try to install a Swift-for-Linux toolchain to build the app — it
  still can't compile the Apple frameworks above. Build/test the app on macOS
  (Xcode, or `./run.sh`).

What **does** run on this Linux VM is the companion `reset-notifier/` (pure bash,
reads the same `*.status.json` usage feed the app produces):

- Tests: `bash reset-notifier/test.sh` (fixture-driven, no network; notify/push
  channels are stubbed via `NOTIFY_CMD`/`PUSH_CMD`, API disabled via `NO_API=1`).
- Exercise the tool's decision logic without macOS/launchd/network by overriding
  `FEED_DIR`, `STATE_DIR`, `NOW`, and `NO_API=1`, e.g.
  `NOW=$(date +%s) FEED_DIR=… STATE_DIR=… NO_API=1 bash reset-notifier/check-reset.sh --dry-run`.
- `check-reset.sh` depends on `jq` (preinstalled). `reset-notifier/install.sh` is
  macOS-only (launchd `LaunchAgents`) and won't run here.
