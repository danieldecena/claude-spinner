# claude-spinner

macOS menu-bar app (Swift / SwiftUI, Xcode project) that shows a live panel of
running Claude Code sessions — model, status, context tokens, rate-limit gauges —
driven by the `~/.claude/spinnerfeed/` feed files that the hooks and `statusLine`
in `~/.claude/settings.json` emit.

> Session state is split per the standard convention: **`STATUS.md`** (confirmed
> working / known broken / next up) and **`TASKS.md`** (titles only). `HANDOFF.md`
> is the longer-form handoff. This file is the static how-it-works reference.

## Build & run

Needs **macOS 27** and **full Xcode 27**. `xcodebuild -version` must work;
Command Line Tools alone takes `run.sh`'s `swiftc` fallback, which then needs
an existing `/Applications/claude spinner.app`. `xcbeautify` is optional
(`brew install xcbeautify`); `run.sh` and the test pipe use it when present.

```bash
./run.sh          # build (xcodebuild if full Xcode, else swiftc fallback) + relaunch
```

`run.sh` derives the built `.app` from `BUILT_PRODUCTS_DIR` (DerivedData hash is
not fixed) and `killall`s the running copy before relaunching. Launch through it
rather than globbing `DerivedData/claude_spinner-*` — more than one such directory
exists, so a glob can hand you a months-old build that runs without complaint.

After launch the panel stays empty until **Install hooks** in the app. That
writes `~/.claude/spinnerfeed/emit.sh` and merges hooks / statusLine into
`~/.claude/settings.json`.

`MACOSX_DEPLOYMENT_TARGET = 27.0`. That is a hard floor, not a default: there is
no backward-compatibility story, and an older machine fails at compile time.

## Test

```bash
killall "claude spinner" 2>/dev/null   # UI-focus tests fail against a live instance
set -o pipefail
xcodebuild -scheme "claude spinner" test | { command -v xcbeautify >/dev/null && xcbeautify || cat; }
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

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
