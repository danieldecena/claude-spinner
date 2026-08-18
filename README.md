# claude-spinner

macOS menu-bar app that shows a live panel of running Claude Code sessions
(model, status, context tokens, rate-limit gauges). It reads
`~/.claude/spinnerfeed/` files written by Claude Code hooks and `statusLine`.

## Prerequisites

- macOS 27 and full Xcode 27 (`xcodebuild -version` must work)
- Optional: `brew install xcbeautify` for prettier build and test logs

Command Line Tools alone takes `run.sh`'s `swiftc` fallback, which then needs
an existing `/Applications/claude spinner.app` bundle.

## Build and run

```bash
./run.sh
```

After launch the panel stays empty until you click **Install hooks** in the
app. That writes `~/.claude/spinnerfeed/emit.sh` and merges hooks / statusLine
into `~/.claude/settings.json`.

## Test

```bash
killall "claude spinner" 2>/dev/null
set -o pipefail
xcodebuild -scheme "claude spinner" test | { command -v xcbeautify >/dev/null && xcbeautify || cat; }
```

How it works: [`CLAUDE.md`](CLAUDE.md). Live project state: [`STATUS.md`](STATUS.md).
