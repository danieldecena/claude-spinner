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

## Do-Not-Repeat

<!-- Mistakes made and corrected. Each entry prevents the same mistake recurring. -->
<!-- Format: [YYYY-MM-DD] Description of what went wrong and what to do instead. -->

- [2026-07-10] Never inject demo/test data into the user's live feed dir (`~/.claude/spinnerfeed/`). A static `status.json` written for a UI preview lingered and showed frozen fake usage, read as a bug. Clean up test data immediately, or use a throwaway deleted in the same step.
- [2026-07-10] `emit.sh` (the hook emitter) lives INSIDE `~/.claude/spinnerfeed/`, alongside the session feed files. Any bulk delete of that directory (`clearAll()`) must filter to session files only (`*.state.json` / `*.status.json` / `*.status.txt`); deleting emit.sh silently kills the whole feed ("No active sessions" forever).

## Decision Log

<!-- Significant technical decisions with rationale. Why X was chosen over Y. -->
