# STATUS archive

Decision-log entries rotated out of `STATUS.md` to keep it readable.
Append-only; git holds the full history either way.

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
