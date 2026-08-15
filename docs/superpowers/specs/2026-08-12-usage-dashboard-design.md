# Usage Dashboard — design

**Date:** 2026-08-12
**Status:** approved in brainstorming; implementation plan at
`docs/superpowers/plans/2026-08-12-usage-dashboard.md`

## Problem

claude-spinner answers "what is happening right now". Everything it knows is
instantaneous, and its entire memory is one number — 5h utilization — sampled every
two minutes and discarded after three hours (`usageHistory`, `FeedWatcher.swift:589`).
There is no history, no cost, no attribution, and no chart anywhere in the app.

## Outcome

A second, resizable **Claude Usage** window showing where tokens and money went over
time, by day, by model, by project — backed by a store that outlives the transcript
files it reads. The menu-bar app is untouched: same panel, same popover, same
surfaces. The dashboard is additive.

## The data

`~/.claude/projects/<slug>/<session>.jsonl` — 1,686 files, ~648 MB, 223k lines,
27 days. Assistant lines carry `timestamp`, `message.model`, `cwd`, `gitBranch`,
`sessionId`, `requestId`, and `message.usage` with all four token classes.

Three measured facts shape the design. The first two were verified twice —
independently, on different files:

1. **One API response is written as N lines, each repeating the identical full
   `usage` payload.** Corpus-wide: 49,534 assistant lines → 23,937 unique
   `message.id`. Spot-check on `ddf42b72…jsonl`: 728 lines → 349 ids, naive output
   429,233 vs deduped 182,135. **Summing per line inflates totals ~2.4×.** Dedupe on
   `message.id` is correctness, not optimization.
2. **All cache creation is `ephemeral_1h`** — corpus 113,685,160 of 113,685,160,
   spot-check 5,513,295 vs 0 for 5m. 1h writes bill at **2× base input**, not 1.25×.
   Getting this wrong understates cost by ~$300 on this corpus.
3. **`usage.iterations` is always length 1** and repeats the top-level output count.
   Do not sum it.

Also: 138 lines are `<synthetic>` with zero usage and a UUID in place of a `msg_` id —
skip them. No `usage` appears on any non-assistant line. Timestamps are uniform
24-char ISO8601 `Z`.

**Retention.** `~/bin/prune-transcripts.sh` deletes live `.jsonl` past 30 days, but it
gzips into `~/Archive/claude-transcripts` first and only `rm`s on success; `mkdir -p`
creates that tree on demand. So future history is recoverable, but the corpus already
starts at 2026-07-17 and nothing older exists. Every day before the store ships is a
day of history that can never be recovered — the argument for landing the store before
the charts.

## Decisions

- **Own SQLite store, not a `ccusage` shell-out.** `ccusage` re-parses 648 MB per run,
  keeps nothing after pruning, and mixes in Gemini CLI usage. The store's whole purpose
  is to outlive the files.
- **No `cost` column.** Cost is tokens × a price table that will be edited; storing it
  would freeze a wrong number into history and make a price correction a migration.
  Aggregates are ~160 rows; pricing is applied in Swift.
- **`INSERT OR IGNORE` on `message_id`** makes every re-ingest idempotent — which is
  what lets the watermark logic be aggressive without being dangerous. Worst case of a
  corrupted watermark is a slow pass, never a wrong total.
- **Date-aware price table.** `claude-sonnet-5` is at introductory $2/$10 through
  2026-08-31 and this corpus straddles that. A flat table overstates Sonnet by ~$81
  today and goes silently wrong on 2026-09-01.
- **Unknown models price to `nil`, not $0**, and surface as an explicit "unpriced"
  bucket. Silent zeros are how a cost dashboard becomes a lie.
- **Label it "list-price equivalent".** These tokens came from a Max subscription;
  they were not invoiced per token. Presenting ~$3,079 as "spent" would be misleading.
- **Cost is the unifying axis.** Cache reads are 3.74 *billion* tokens against 18
  million output — 200:1. A single stacked token chart renders everything else as a
  sliver. Token composition gets its own percentage-stacked chart instead.
- **Its own window**, opened from the Spinner menu. The panel takes no risk.

## Constraints

- **No SPM/CocoaPods.** `run.sh`'s fallback compiles with bare `swiftc` globbing
  `"claude spinner"/*.swift`; a package dependency silently breaks that dev loop.
  `import SQLite3` and `import Charts` both typecheck under plain `swiftc` — verified.
- Sources are an Xcode **synchronized group**: new `.swift` files join the target with
  no `pbxproj` edit.
- **Logic that can be pure and static is.** No test in the 67-test suite constructs a
  `FeedWatcher`. Unlike `FeedWatcher`, `UsageStore` and `UsageIngestor` take injectable
  paths so they *can* be built in a test.
- `ENABLE_APP_SANDBOX = NO`, so reading `~/.claude/projects` and writing Application
  Support is unproblematic.

## Known defect this work must fix

`windowWillClose(_:)` (`claude_spinnerApp.swift:171`) unconditionally sets
`.accessory`. It was written when only one window existed. Adding a second window that
shares `self` as delegate means closing the dashboard yanks the Dock icon out from
under the panel — the exact state the panel window exists to prevent. It must be
guarded on `mainWindow` identity in the same slice that adds the dashboard window.

## Risks

1. **Swift JSON throughput is the one unmeasured number.** A Python equivalent reads
   all 592 MB and parses 49,534 assistant lines in ~0.7 s warm. Budget 5–30 s cold for
   Swift. Escalation ladder if slow: confirm the msg-id prescan short-circuits, then
   slice to the `"message"` sub-object before parsing, then hand-scan the `"usage"`
   span — all behind `TranscriptParser.row(fromLine:)` so internals swap without
   touching callers or tests.
2. **Cost ≠ bill.** See the labelling decision above.
3. **Prices drift** and these models are new; the date-aware table is not optional.
4. **`SQLITE_TRANSIENT`** — binding Swift strings with the default `STATIC` is the
   standard crash in hand-rolled SQLite3 Swift wrappers. Bind every string transient.

## Out of scope

Richer per-session detail and control actions (focus / interrupt / send input) were
part of the original ask and are deliberately excluded. They are a different risk class
and get their own spec.
