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
- [2026-07-17] The buglog id is minted by the **OpenWolf PostToolUse hook** (`.wolf/hooks/post-write.js` → `autoDetectBugFix`), not just by hand — and Claude Code runs the **project-local** copy (`.claude/settings.json` points at `$CLAUDE_PROJECT_DIR/.wolf/hooks/post-write.js`), which is git-tracked, so it's editable and persists. The same racy `bugs.length+1` also ships in the global `openwolf` npm package (`node_modules/openwolf/dist/...`), so every OpenWolf project has this bug; fixing it upstream means editing compiled `dist` JS (fragile). bug-200 was fixed project-locally: exclusive lockfile around the read-modify-write + `max+1` ids. `writeJSON` in `shared.js` was already atomic (tmp+rename), so the file never corrupts — the bug was purely lost-updates from unserialized RMW.
- [2026-07-17] To reproduce a concurrency bug you need a **real barrier**, not just a fan-out. Spawning 25 `node` hook processes did NOT surface the buglog race because process-startup jitter (~80ms) serialized their millisecond critical sections. Giving every worker a common *future* start instant (`Atomics.wait` until `now+500ms`) forced genuine overlap, and the old pattern then lost 15 of 20 writes. A plain parallel test can pass a broken implementation.
- [2026-07-17] SwiftUI's `Text` has **no clip-without-ellipsis truncation mode** — `.truncationMode(.head/.middle/.tail)` all draw a `…`. So when a truncating label sits next to another trailing element (here the fixed working-dots slot in the status column), its `…` collides with that element and reads as doubled (`running askuserqu……`, bug-201). Fix: pre-truncate the string in code to the available width and never let `Text` truncate. `RowLayout.fit(_:toWidth:)` does this — Menlo is monospaced so `Int((width - statusSlack) / monoAdvance)` is the exact char budget; leave `statusSlack` headroom so SwiftUI has slack and won't reach for the glyph. `truncationMode` stays only as a dead backstop.

- [2026-07-18] The two 5h-usage sources disagree on scale: statusLine payload `rate_limits.five_hour.used_percentage` is 0-100, while the API header `anthropic-ratelimit-unified-5h-utilization` is a 0-1 fraction (×100 needed). Both `resets_at`/`-5h-reset` are epoch seconds. `reset-notifier/check-reset.sh` normalises both; anything else consuming both paths must too.
- [2026-07-18] Portable stat mtime must be GNU-first: `stat -c %Y || stat -f %m`. The BSD-first order breaks on Linux because GNU stat treats `-f %m FILE` as a *successful* filesystem-status call (multi-line output), so the fallback never fires (bug-153). Same class as the `date -r`/`date -d @` dual, but there the failing branch actually fails.

## Do-Not-Repeat

<!-- Mistakes made and corrected. Each entry prevents the same mistake recurring. -->
<!-- Format: [YYYY-MM-DD] Description of what went wrong and what to do instead. -->

- [2026-07-17] Don't de-emphasise a low value by dimming its fill — the track is already a low-opacity secondary, so a dimmed fill loses contrast against the thing it's supposed to be read against, and "low" becomes "absent" (bug-135). Tint and a minimum sliver keep it quiet without erasing it. Ask which value the band is COMMON for: 7d sits under 10% most of the week, so the dimmed branch was the default rendering, not the exception.
- [2026-07-17] Don't scale a magnitude gauge linearly over a range narrower than the value's own (bug-136). `min(fullScale, x)/fullScale` looks like a clamp but is a saturation: past fullScale every value draws identically and the gauge stops comparing exactly where the differences matter. Square-root over the value's real range keeps low-end resolution and still separates the top. The number beside the bar is not a defence — if the bar can't be read, it isn't a gauge.
- [2026-07-17] SwiftUI's `.opacity(0)` hides a view but keeps it hit-testable (bug-137). An invisible `.background` Button is a live target under everything drawn over it. Pair `.opacity(0)` with `.allowsHitTesting(false)` whenever the view is decorative or shortcut-only; `keyboardShortcut` fires regardless, since shortcuts don't route through hit testing.

- [2026-07-17] **Never `git add -A` in this repo.** Stage explicit paths. This project routinely has several Claude sessions live at once (the spinner panel exists to show them), so the worktree is shared: `git add -A` staged another session's in-progress `SetupInstaller.swift` and tests into a commit about panel verification (bug-139). Before staging, run `git status` and check for files this session never touched. Note this misfired twice — the first lesson was filed as "bundles unrelated fixes", which didn't generalise to "another agent is editing this worktree right now".
- [2026-07-17] When adding a token to `HostTag.from`'s `contains` chain, check its LENGTH first. The existing tokens ("vscode", "windsurf", "cursor") are long enough to self-disambiguate; a 3-letter `contains("zed")` claims "customized" too — and the editor branch runs BEFORE the terminal branch, so a false match also short-circuits the ghostty/iterm checks. Match short tokens exactly (`==` / `hasPrefix`), not by substring (bug-133).
- [2026-07-17] Deleting a dead accessor is only half the removal: grep what WROTE the field it read. Dropping `usageModelId` left `StatusFile.Model.id -> SessionFeed.modelId -> UsageSnapshot.modelId` as a pure write path, still parsed and still serialised to UserDefaults every poll, read by nothing (bug-134). Remove the chain, not the tail.
- [2026-07-17] **"Unit-green" is not "verified" for anything visual — go and look.** Three findings today existed only on screen: the 7d fill dimmed to invisibility, the column jag from per-row sizing (bug-140, which passed all 56 tests because each row's arithmetic was individually right — alignment is a property of the SET of rows), and the Zed click that had been unit-green through five regressions. Build (`./run.sh`), open the panel, capture, and read it before reporting any UI change as done.
- [2026-07-17] Don't judge the UI from a screenshot without checking the running binary is newer than the last commit. A capture showed the new `UsageHeader` "missing" and nearly sent me hunting a data bug in `fiveHourResetsAt` — the app was just built 6 min before the commit landed. `stat -f %Sm` the binary in DerivedData vs `git log -1 --format=%cd`, and `./run.sh` before capturing.
- [2026-07-17] Don't build a `dynamic`/appearance-aware `Color` inside a function that returns it per call — each call mints a fresh `NSColor`, and SwiftUI compares `Color` by that underlying instance, so two same-band tints compare unequal and `testUsageTintTiers` fails. Define each tint once as a `static let` and have the switch return it.
- [2026-07-17] Never budget a flexible text column to its computed minimum. "running bash" needed 92.4pt by arithmetic and still truncated at 93pt (bug-122, same class as bug-111). Leave ~4-10pt of slack. NOTE: this was blamed on the ~0.602 × size Menlo estimate being inexact — measuring proved it accurate to 2dp (6.6226 vs 6.622 at size 11), so the estimate was never the problem and slack is needed for other reasons. `RowLayout.monoAdvance` now measures NSFont directly, which removes the constant but does NOT remove the need for slack.
- [2026-07-17] When two adjacent columns are both fixed-width, the split between them is a guess re-applied to every row — and it fails in BOTH directions at once: the bounded column hoards space it never uses while the unbounded one truncates, and the bounded column's own long tail still overruns (bug-111/122/138 are all this). Fix the class, not the instance: let the column with the bounded vocabulary take its measured width and hand the remainder to the unbounded one. Widening the panel just moves the guess.
- [2026-07-17] The AppleScript menu-bar click (`click menu bar item 1 of menu bar 2`) silently no-ops on the first call after a fresh app launch, and a second call within the same capture toggles the panel shut again. Click once, sleep ~2s, capture; if the panel isn't there, click once more — never twice in one step.
- [2026-07-17] That AppleScript click only works when the calling **host app** has Accessibility permission — it's the host's permission that matters, not the project's. From Zed (which has it) the panel opens, captures, and clicks fine; from a host without it, `osascript` fails `-1719 (not allowed assistive access)`. CORRECTED: this entry previously said the `.transient` panel "cannot be opened or captured programmatically at all" and to always ask the user — that generalised one un-permissioned host into a law, and it would have stopped the Zed click being verified at all. **Probe first** (`osascript -e 'tell application "System Events" to return name of first process whose frontmost is true'`); only fall back to asking the user if the probe actually fails.
- [2026-07-17] `screencapture -R` fails on the `.transient` panel ("could not create image from rect"), but plain full-screen `screencapture -x -o` works fine — crop the PNG afterwards with PIL. The panel moves between captures because the menu-bar title changes width, so re-locate it in each capture rather than reusing coordinates.
- [2026-07-17] Never `click at {x,y}` blind. The panel closes on focus loss, and a stale coordinate then lands on whatever is underneath — a click meant for a row hit a control in the user's Safari toolbar. Capture and confirm the target is actually on screen at those coordinates in THIS capture before clicking.
- [2026-07-17] SourceKit reports phantom errors in this project (`Cannot find 'FeedWatcher' in scope`, `'main' attribute cannot be used in a module that contains top-level code`, `No such module 'XCTest'`) because scratchpad stub files declare top-level code in the indexed module. They are **indexing artifacts, not build errors** — `xcodebuild` is the authority. Don't chase them.

- [2026-07-10] Never inject demo/test data into the user's live feed dir (`~/.claude/spinnerfeed/`). A static `status.json` written for a UI preview lingered and showed frozen fake usage, read as a bug. Clean up test data immediately, or use a throwaway deleted in the same step.
- [2026-07-10] `emit.sh` (the hook emitter) lives INSIDE `~/.claude/spinnerfeed/`, alongside the session feed files. Any bulk delete of that directory (`clearAll()`) must filter to session files only (`*.state.json` / `*.status.json` / `*.status.txt`); deleting emit.sh silently kills the whole feed ("No active sessions" forever).

## Decision Log

<!-- Significant technical decisions with rationale. Why X was chosen over Y. -->

### 2026-07-18 — menu-bar labels need their own tick
`glyphPulse`/`glyphPhase` only advance while `menuBarActive || usageAlarm`, so any
menu-bar text derived from `Date()` at read time freezes when nothing is running.
A countdown is most useful in exactly that idle state — give it its own published
tick (`minuteTick`, 60s) rather than assuming the spinner animation re-renders you.

### 2026-07-18 — the test runner is not broken for the unit target
`xcodebuild test -scheme "claude spinner" -destination 'platform=macOS'` bootstrapped
and passed 61/61 twice, with `killall "claude spinner"` first. The recorded "Early
unexpected exit ... before establishing connection" failure did not reproduce. Only
the unit target ran; the UI target remains unverified.

### 2026-07-18 — read the buglog before declaring a bug imaginary
A reported `xcodebuild test` bootstrap failure was closed as "not a real failure"
after the suite went green. It went green because every run started with
`killall "claude spinner"` — the documented workaround for **bug-094**, whose entry
was already on file. The single-instance guard `exit(0)`s the app-hosted test host
when another copy is running; that is still true. Green-after-workaround is not
evidence a bug does not exist. The OpenWolf rule ("BEFORE fixing any bug: read
buglog.json") exists for exactly this; skipping it cost a wrong STATUS.md entry
that had to be corrected twice.
