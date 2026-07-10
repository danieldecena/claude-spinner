# Cerebrum

> OpenWolf's learning memory. Updated automatically as the AI learns from interactions.
> Do not edit manually unless correcting an error.
> Last updated: 2026-06-23

## User Preferences

<!-- How the user likes things done. Code style, tools, patterns, communication. -->

## Key Learnings

- **Project:** claude-spinner

## Do-Not-Repeat

<!-- Mistakes made and corrected. Each entry prevents the same mistake recurring. -->
<!-- Format: [YYYY-MM-DD] Description of what went wrong and what to do instead. -->

- [2026-07-10] Never inject demo/test data into the user's live feed dir (`~/.claude/spinnerfeed/`). A static `status.json` written for a UI preview lingered and showed frozen fake usage, read as a bug. Clean up test data immediately, or use a throwaway deleted in the same step.
- [2026-07-10] `emit.sh` (the hook emitter) lives INSIDE `~/.claude/spinnerfeed/`, alongside the session feed files. Any bulk delete of that directory (`clearAll()`) must filter to session files only (`*.state.json` / `*.status.json` / `*.status.txt`); deleting emit.sh silently kills the whole feed ("No active sessions" forever).

## Decision Log

<!-- Significant technical decisions with rationale. Why X was chosen over Y. -->
