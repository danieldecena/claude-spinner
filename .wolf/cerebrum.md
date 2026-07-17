# Cerebrum

> OpenWolf's learning memory. Updated automatically as the AI learns from interactions.
> Do not edit manually unless correcting an error.
> Last updated: 2026-06-23

## User Preferences

<!-- How the user likes things done. Code style, tools, patterns, communication. -->

## Key Learnings

- **Project:** claude-spinner
- [2026-07-10] The feed is driven by Claude Code lifecycle hooks + statusLine in `~/.claude/settings.json`. These fire for Claude Code CLI **and** the Claude Desktop app's **Code tab** (same engine), but NOT the Desktop **Chat tab** or claude.ai web chat (different surface, no hooks, no statusLine, no supported observation API). So the spinner can only ever show Claude Code sessions. Don't try to capture Desktop Chat via `~/Library/Logs/Claude/main.log` or `~/Library/Application Support/Claude/` — undocumented, brittle, rejected.
- [2026-07-10] The Xcode project is format 110 (Xcode 27 / objectVersion 110). GitHub-hosted runners (Xcode 26.x) can't open it, so `xcodebuild` CI must run on a self-hosted runner. The `claude spinner/` folder is a synchronized root group — files dropped in it auto-include (a `.sh` auto-bundles into Contents/Resources/) with no pbxproj edit.
- [2026-07-10] Unit tests are hosted in the app; the single-instance guard (`exit(0)` when a second copy launches) kills the test host if a normal app copy is running. Always `killall "claude spinner"` before `xcodebuild test`.
- [2026-07-17] `<id>.status.json` carries `session_name` — Claude Code's generated name for the session, and the only thing distinguishing two sessions in the same cwd. It comes in two shapes (kebab slug `panel-status-truncation-fix`, prose sentence `Set up iTerm2 shell integration`) and is absent on older sessions, so a `projectName` fallback is mandatory. The row shows it via `SessionFeed.displayName`; the cwd lives only in the tooltip now.
- [2026-07-17] Row context is banded on **absolute tokens** (`Color.contextTint`: 100k yellow / 150k amber / 200k red), not percentage — a 1m window makes 200k read as a harmless 20%. Rate-limit gauges still use `Color.usageTint` (percent), which is correct for them.
- [2026-07-17] `run.sh`'s swiftc fallback runs `swiftc` over the sources directly with **no asset-catalog step** (no `actool`), so **an asset catalog colorset would exist in Xcode builds and vanish from the dev loop**. Dark-mode colors are therefore code-defined via `Color.dynamic(light:dark:)` wrapping `NSColor(name:dynamicProvider:)`. NOTE: this was previously recorded as "compiles only the three sources" — that phrasing was both stale and hid a bug (`SetupInstaller.swift` was never added to the list, so the fallback couldn't compile at all; fixed 2026-07-17 by globbing `"claude spinner"/*.swift`). The colorset conclusion is unaffected — the reason is the missing asset pipeline, not the file count.

- [2026-07-17] The user runs Claude Code inside **Zed** (`host` = `dev.zed.Zed`), not only terminals — so "the host is a terminal unless it's VS Code" is a wrong assumption. A GUI editor reports its **own bundle ID** as the host string, which is why `SessionLauncher.resolveBundleID` treats an untabled-but-running bundle ID as itself: it fixes Zed, Cursor, VSCodium and Windsurf at once without hardcoding bundle IDs that are easy to get wrong. Only a `TERM_PROGRAM` value (never a bundle ID) should reach the terminal fallback.
- [2026-07-17] The wrong-window bug family (bug-004/072/091/110) has TWO entry points, and the regression test only guards one. `guiFocusAction` covers the *branch* logic; `hostBundleIDs` is a **table**, and a host missing from it fails silently by falling back to a terminal. When this class recurs, check the table before re-reading the branch.

## Do-Not-Repeat

<!-- Mistakes made and corrected. Each entry prevents the same mistake recurring. -->
<!-- Format: [YYYY-MM-DD] Description of what went wrong and what to do instead. -->

- [2026-07-17] Don't judge the UI from a screenshot without checking the running binary is newer than the last commit. A capture showed the new `UsageHeader` "missing" and nearly sent me hunting a data bug in `fiveHourResetsAt` — the app was just built 6 min before the commit landed. `stat -f %Sm` the binary in DerivedData vs `git log -1 --format=%cd`, and `./run.sh` before capturing.
- [2026-07-17] Don't build a `dynamic`/appearance-aware `Color` inside a function that returns it per call — each call mints a fresh `NSColor`, and SwiftUI compares `Color` by that underlying instance, so two same-band tints compare unequal and `testUsageTintTiers` fails. Define each tint once as a `static let` and have the switch return it.
- [2026-07-17] Never budget a flexible text column to its computed minimum. The Menlo advance figure (~0.602 × size) is an estimate: "running bash" needed 92.4pt by arithmetic and still truncated at 93pt (bug-122, same class as bug-111). Leave ~10pt of slack.
- [2026-07-17] The AppleScript menu-bar click (`click menu bar item 1 of menu bar 2`) silently no-ops on the first call after a fresh app launch, and a second call within the same capture toggles the panel shut again. Click once, sleep ~2s, capture; if the panel isn't there, click once more — never twice in one step.
- [2026-07-17] That AppleScript click only works when the calling terminal has **Accessibility** permission. From a session without it, `osascript` fails with `-1719 (not allowed assistive access)` and `screencapture -R` fails with "could not create image from rect" — the panel is `.transient`, so it cannot be opened or captured programmatically at all. Don't burn turns retrying: capture the full screen for the menu-bar label, and ask the user to open the panel and screenshot it. Never infer panel appearance from the code instead.
- [2026-07-17] SourceKit reports phantom errors in this project (`Cannot find 'FeedWatcher' in scope`, `'main' attribute cannot be used in a module that contains top-level code`, `No such module 'XCTest'`) because scratchpad stub files declare top-level code in the indexed module. They are **indexing artifacts, not build errors** — `xcodebuild` is the authority. Don't chase them.

- [2026-07-10] Never inject demo/test data into the user's live feed dir (`~/.claude/spinnerfeed/`). A static `status.json` written for a UI preview lingered and showed frozen fake usage, read as a bug. Clean up test data immediately, or use a throwaway deleted in the same step.
- [2026-07-10] `emit.sh` (the hook emitter) lives INSIDE `~/.claude/spinnerfeed/`, alongside the session feed files. Any bulk delete of that directory (`clearAll()`) must filter to session files only (`*.state.json` / `*.status.json` / `*.status.txt`); deleting emit.sh silently kills the whole feed ("No active sessions" forever).

## Decision Log

<!-- Significant technical decisions with rationale. Why X was chosen over Y. -->
