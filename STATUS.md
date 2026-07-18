# STATUS

## Confirmed working

- Menu-bar panel tracks live Claude Code sessions via `~/.claude/spinnerfeed/`
  feed files (hooks + statusLine in `~/.claude/settings.json`).
- First-run one-click installer (Install hooks button) writes the scripts and
  back-up-then-merges the hooks/statusLine into settings.json.
- CI: 57 unit tests green; runs on a self-hosted runner (project is Xcode 27
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
- A long tool name no longer draws two ellipses. `RowLayout.fit` pre-truncates
  the status label to its column so SwiftUI never adds its own tail `…` beside
  the animated dots. Verified on screen with a throwaway 51-char MCP tool
  (`running mcp__claude_ai_Google_Calendar__list_events`): the cut row's trailing
  marker is identical to the un-truncatable `running bash…` / `thinking…` rows
  (dots only). bug-201.
- `.wolf/buglog.json` no longer races between concurrent sessions. The OpenWolf
  auto-logger (`.wolf/hooks/post-write.js`) now serializes its read-modify-write
  behind an exclusive lockfile and mints ids as `max+1` (strictly above every id
  present). Proven with a barrier-synchronized 20-way race: the old
  `length+1`/no-lock pattern lost 15 of 20 writes; the locked version kept 20/20
  with unique ids. bug-200. (The 10 *historical* duplicate ids are left as-is —
  they're referenced in commits/STATUS/cerebrum, so renumbering would break refs.)

## Known broken

- (none — the double-ellipsis and buglog-race items were both fixed 2026-07-17)

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

- Notarization — blocked on a **Developer ID Application** cert. Only an Apple
  Development cert is installed, which cannot notarize, and notarytool has no
  stored credentials. Needs a paid Developer Program account and an Apple ID.

### 2026-07-18 (usage reset countdown)
- Decided: the menu-bar usage title carries the countdown (`5h 4% · 4h50m`), not
  just the clock time the panel footer already shows. The footer answers "when",
  which needs the panel open; the menu bar answers "how long", which is the
  question a bare percentage provokes and the one worth paying title width for.
- Decided: the countdown gets its own 60s `minuteTick` rather than riding the
  spinner's animation timer. That timer only advances while working or alarming,
  which is precisely when the countdown does NOT need to move — an idle session
  watching its limit recover would have seen a frozen number.
- Decided: an unknown reset instant drops the countdown rather than showing `0m`.
  The statusLine feed carries a percentage with no `resets_at`, so zero would be
  a confident wrong answer where absence is honest.
- Noted: `xcodebuild test` passed 61/61 on the unit target today, twice, with the
  app killed first — the recorded runner-bootstrap failure did not reproduce. The
  UI target was not exercised, so that half stays open.

### 2026-07-17 (buglog concurrency, bug-200)
- Decided: serialize the buglog write behind a lockfile rather than move to
  one-file-per-bug. The append is a millisecond critical section and the file is
  already written atomically (tmp+rename), so a lock closes the race with the
  smallest change and keeps every reader (pre-write, session-start, the digest)
  pointed at one file. Per-bug files were the more robust option but would have
  rewritten the format across several third-party hooks.
- Decided: the id is `max(numeric ids)+1`, not `bugs.length+1`. length trailed
  the true max (the log already had gaps and dups) and could even land back on an
  existing id; max+1 is strictly greater than every id present, so it can't reuse.
- Noted: the fix lands in the *project-local* `.wolf/hooks/post-write.js` (the
  copy `.claude/settings.json` actually invokes). The identical `length+1` lives
  in the global openwolf npm package too, so every OpenWolf project shares this
  bug — a separate upstream concern, not fixed here.
- Noted: verified by a barrier-synchronized race (common future start instant to
  defeat node-startup jitter) — the naive 25-way full-hook test did NOT reproduce
  the race because startup stagger serialized the writers. Concurrency bugs need
  a real barrier to surface; a plain fan-out can pass a broken implementation.

### 2026-07-17 (status truncation)
- Decided: the status label is cut to its column *in code* (`RowLayout.fit`),
  not left to SwiftUI's `.truncationMode(.tail)`. SwiftUI Text has no
  clip-without-ellipsis mode, so a clamped long tool name got its own `…` — which
  landed right against the fixed working-dots slot and read as `running askuserqu……`.
  Pre-truncating to the column width minus `statusSlack` (Menlo is monospaced, so
  the fit is exact) guarantees SwiftUI never reaches for the glyph; the dots are
  the only trailing signal. `truncationMode(.tail)` stays as a dead backstop (bug-201).
- Noted: this was invisible to the 56-tests-green build — the arithmetic column
  math was right; the collision only exists on screen. Confirmed by staging a
  throwaway 51-char MCP row and comparing its trailing marker to `running bash…`
  (which cannot truncate): identical, so no doubled ellipsis. Same "go and look"
  lesson as bug-140, now applied.

### 2026-07-17 (row layout, cont.)
- Decided: row columns are sized once per panel, from the widest label in each,
  not per row. Per-row sizing (4a6ccb7) fixed truncation but jagged the grid —
  every row's model/status began at a different x. Sizing to the set keeps the
  columns aligned AND hands the names every spare point; the bounded cost is
  that one long-tool row narrows every name (bug-140).
- Decided: the model column joins the name/status budget. It was the same static
  split, smaller — 46pt fixed holding "opus" (27pt). With it folded in, only
  170pt of a row is fixed, which makes panelWidth a free knob; set to 470.
- Noted: bug-140 passed all 56 unit tests. Each row's arithmetic was correct in
  isolation; alignment is a property of the SET of rows and nothing checked it.
  Three findings today came only from looking at the panel (the dimmed 7d bar,
  this jag, the Zed click) — "unit-green" is not "verified" for anything visual.

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
