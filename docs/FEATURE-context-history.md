# Feature: per-session context history

## What & why

The detail pane says a session is at `22%` of its window and nothing else. The
question people actually ask it — *is this one about to need a compact, and how
fast did it get here* — needs the shape of that number over time, which the app
does not keep for anything except the account-wide 5h rate limit.

Done looks like: the Context section carries a meter (tokens against the window)
and a single-series area chart of context over the session's life, both on the
existing `contextTint` bands, and the samples behind them survive a relaunch.

## Surface it touches

Changing:

- `claude spinner/FeedWatcher.swift` — a new `ContextSample`, a per-session
  buffer, and one call in the rescan's main-thread block beside
  `updateUsageCache` (`:1073`).
- `claude spinner/WindowContentView.swift` — `SessionDetail` gains a `history`
  parameter, passed at the call site the way `OverviewStrip` already receives
  `feed.usageHistory` (`:52`). Two new views in the Context section.
- `claude spinnerTests/claude_spinnerTests.swift` — sampler rules and chart
  geometry.

Genuinely new: **all of it is new plumbing.** There is no per-session time
series in the app today. `usageHistory` is global, account-scoped, and sampled
only by the usage poller, so nothing here can reuse it. Every per-session
number the pane shows — spend, tokens, cache ratio, lines — is latest-value
only, overwritten on each statusLine write.

## New decisions needed

None. No new dependency; SwiftUI `Path` already draws the existing sparkline.

Decisions taken inline:

- **Scaled 0 to the window, not to the data.** The meter and the chart then
  agree, and a session with a 1M window that has used 20k *should* draw as a
  flat crawl along the bottom — that is the true reading. Auto-zooming to the
  data would make every session look equally full, which is the same failure
  the existing sparkline's fixed 0–100 axis was written to avoid.
- **Time-scaled x, unlike the existing sparkline.** That one is index-based
  (`WindowContentView.swift:553`), so a polling gap silently compresses. A
  session that sat idle for twenty minutes has to read as a flat stretch, not
  as a step. The old chart is not being changed here.
- **Compaction is not smoothed.** A `/compact` or `/clear` drops the token
  count hard; that cliff is the most informative thing on the chart.
- **One series, no legend.** Splitting input and output tokens would make it
  categorical and pull in a legend; not now.
