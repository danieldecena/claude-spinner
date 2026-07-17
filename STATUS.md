# STATUS

## Confirmed working

- Menu-bar panel tracks live Claude Code sessions via `~/.claude/spinnerfeed/`
  feed files (hooks + statusLine in `~/.claude/settings.json`).
- First-run one-click installer (Install hooks button) writes the scripts and
  back-up-then-merges the hooks/statusLine into settings.json.
- CI: 56 unit tests green; runs on a self-hosted runner (project is Xcode 27
  format 110, which GitHub-hosted runners can't open).
- Row names get every point the model and status columns don't need, and the
  columns are sized once per panel so they still align. Verified on screen:
  `compact-vscode-density`, `statusline-drift-perf` and `scan-jobs-task-runner`
  all render in full at panelWidth 470, where they truncated at 424.
- Panel rows carry the session's own name (`session_name` from status.json,
  falling back to the directory), its context token count banded on absolute
  usage (100k/150k/200k), and sort heaviest-first within each status band.
  The header totals context across all sessions. Legible in both appearances.

- Clicking a row focuses the editor the session actually runs in — including
  Zed and any editor not in `hostBundleIDs`, which previously opened a stray
  Ghostty window (bug-130). **Verified by hand 2026-07-17**: clicking the Zed
  row focused zed and Ghostty never launched. The panel *can* be driven from an
  agent session after all, when the host app has Accessibility permission.
- The panel's gauges and row layout are verified on screen, not just in tests:
  7d at 9% draws a visible sliver, `chg +52%` fills ~72% of its track rather
  than saturating, and `review code and ui` / `needs input` render in full.

## Known broken

- A long tool name draws two ellipses in a row: `running askuserqu……` — the
  status truncates and the animated dots sit right after it.
- `.wolf/buglog.json` has 10 duplicate bug IDs. Two Claude sessions run in this
  repo at once and both mint `max+1` from their own read of the file. Duplicate
  ids are the visible damage; a silently lost entry is the real risk. Needs a
  decision: one file per bug, a lock, or don't run two sessions here (bug-200).

## Scope / by-design limitations

- **Captures Claude Code sessions only** — CLI (terminal/VS Code/Ghostty/iTerm)
  and the Claude **Desktop app's Code tab** (same engine, fires the same
  settings.json hooks). It does NOT capture the Desktop app's **Chat tab** or
  claude.ai web chat: those run no lifecycle hooks and no statusLine, and there
  is no supported API for their live turn state. Wiring to Desktop internals
  (`~/Library/Logs/Claude/main.log`, `~/Library/Application Support/Claude/`,
  or accessibility scraping) was considered and rejected as brittle. To see a
  desktop session in the spinner, use the Code tab.

## Next Up

- Decide how `.wolf/buglog.json` should survive concurrent sessions (bug-200).
- Notarization — blocked on a **Developer ID Application** cert. Only an Apple
  Development cert is installed, which cannot notarize, and notarytool has no
  stored credentials. Needs a paid Developer Program account and an Apple ID.

### 2026-07-17 (row layout)
- Decided: the status column takes its measured width and the name takes the
  remainder, rather than both being fixed. Two fixed columns meant one static
  guess failing in both directions — `done` hoarding 103pt while the name
  truncated, and `running TodoWrite` overrunning the same 103pt. Third bug in
  this family (bug-111/122/138); widening the panel would only move the guess.
- Noted: the ~0.602×size Menlo estimate the old widths were derived from was
  blamed for bug-122. Measuring proved it accurate to two decimals (6.6226 vs
  6.622), so slack is still required for other reasons. `RowLayout.monoAdvance`
  measures the font directly — that removes a hand-rederived constant, not a bug.

### 2026-07-17 (panel gauges)
- Decided: the `chg` gauge scales by square root over the full 0-100 range, not
  linearly over 20 points. Linear saturated past 20, which is where comparing
  magnitudes starts to matter; sqrt keeps single-digit moves apart (the common
  case) and still separates a +52 from a +20. Kept the gauge rather than cutting
  it — the redundancy question resolved once the bar actually carried the value.
- Decided: a low gauge value is de-emphasised by tint alone, never by dimming
  the fill. The track is already a low-opacity secondary, so dimming costs the
  contrast the fill is read against — and for 7d, under 10% is the normal case.

### 2026-07-17 (review session)
- Decided: an unknown host that names a *running* app resolves to itself rather
  than falling back to a terminal. Fixes Zed/Cursor/VSCodium/Windsurf at once
  without hardcoding bundle IDs, and keeps the fallback for `TERM_PROGRAM`
  values, which are never bundle IDs.
- Decided: `run.sh`'s swiftc fallback globs `"claude spinner"/*.swift` rather
  than listing sources. The folder is a synchronized root group, so any literal
  list rots silently behind it — which is exactly how it broke (bug-132).
- Noted: the code-defined dark-mode colors decision below was justified by "the
  fallback compiles only the three sources". That premise was stale. The
  conclusion stands for the real reason — the fallback has no asset-catalog
  step, so a colorset would vanish from the dev loop.

### 2026-07-17
- Decided: the row names the session, not the project — `session_name` is the
  only thing separating two sessions in one directory. The cwd moved to the
  tooltip.
- Decided: context tints band on absolute tokens, not percent — a 1m window
  makes 200k read as a harmless 20%.
- Decided: rows sort by context weight *within* a status band, not globally, so
  a heavy idle session can't outrank one waiting on you.
- Decided: dark-mode colors live in code, not an asset catalog — run.sh's
  swiftc fallback compiles only the three sources and would drop a colorset.

### 2026-07-10
- Decided: keep the spinner scoped to Claude Code sessions; do not observe the
  Desktop Chat tab via unsupported internals. Documented the Code-tab (hooks
  fire) vs Chat-tab (no hooks) distinction.
