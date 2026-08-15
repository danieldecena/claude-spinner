# Todo progress bar — design

## Context

Daniel asked for a per-session task-completion bar in the panel, in the
style `□□□□□□□□□□  --%`. Claude Code sessions have no inherent "percent
complete" metric — investigation (this session, 2026-08-14) found nothing
resembling task/todo progress anywhere in `~/.claude/spinnerfeed/`'s two
feed files (`<id>.state.json` from `emit.sh`, `<id>.status.json` from the
statusLine script). The only real N-of-M signal available is a session's
TodoWrite list (`pending`/`in_progress`/`completed` items), and it exists
only inside each session's transcript JSONL today — nothing captures or
persists it into the feed.

Confirmed against the official hooks doc (`get_claude_doc("hooks")`,
`PostToolUse input`, 2026-08-14): a `PostToolUse` hook's `tool_input`
mirrors the tool's actual call arguments, so for `TodoWrite` it is a real
JSON array at `.tool_input.todos`, not the double-encoded string seen in
one transcript sample — no `fromjson` workaround needed.

## Decisions

- **Source:** extend `~/.claude/spinnerfeed/emit.sh` to capture TodoWrite
  state on `PostToolUse`, persist `todo_total`/`todo_done` into
  `<id>.state.json`, carried forward on every other event the same way
  `pid`/`host`/`last_seed` already are, reset to null on `SessionStart`.
- **Placement:** the requested 10-box bar is ~16 monospace characters
  (≈112pt) and does not fit inline in the existing row — the panel is
  470pt wide, 470pt-panel screenshots already show names and status
  truncating. Confirmed with Daniel: the bar goes on a **second line**
  under every row, not conditionally inline.
- **Empty state:** confirmed with Daniel — every row always shows the bar,
  reserved at `□□□□□□□□□□ 0%` before any TodoWrite call, not collapsed.
  This makes every row's height uniform (no per-row height branching).
- **Color:** `Color.usageTint` is an urgency gradient (green = low/safe,
  red = high/danger) built for rate-limit and context consumption, where
  *high* is bad. Task completion is the opposite polarity — 100% done is
  good, not alarming — so reusing it would misread. The bar uses a single
  flat tint instead (`Color.claude` filled, `Color.secondary.opacity`
  track), the same "working" color already used for the row's spinner/name
  tint, with no urgency grading.

## emit.sh changes

Two new carried-forward values, following the existing `prev_seed`/
`prev_dur` pattern (`emit.sh:26-30`):

```sh
prev_todo_total=$(jq -r '.todo_total // empty' "$f" 2>/dev/null)
prev_todo_done=$(jq -r '.todo_done // empty' "$f" 2>/dev/null)
todo_total="$prev_todo_total"
todo_done="$prev_todo_done"
```

`SessionStart` resets them to empty in the same `case` arm that resets
`turn_start`/`last_seed`/`last_duration` (`emit.sh:59`).

After the `case` block, when this event is a `TodoWrite` completion,
recompute both from the hook's own `tool_input` (not the carried-forward
values) — `PostToolUse` fires after every tool, `tool_name` is already
captured into `$tool`:

```sh
if [ "$event" = "PostToolUse" ] && [ "$tool" = "TodoWrite" ]; then
    todos_json=$(printf '%s' "$input" | jq -c '.tool_input.todos // []')
    todo_total=$(printf '%s' "$todos_json" | jq 'length')
    todo_done=$(printf '%s' "$todos_json" | jq '[.[] | select(.status == "completed")] | length')
fi
```

Final `jq -n` write (`emit.sh:76-93`) gains matching args and fields,
same null-vs-number pattern already used for `pid`/`turn_start`:

```
--arg tt "$todo_total" --arg td "$todo_done"
...
todo_total: (if $tt == "" then null else ($tt | tonumber) end),
todo_done:  (if $td == "" then null else ($td | tonumber) end),
```

## Feed model changes (`FeedWatcher.swift`)

- `StateFile` (`FeedWatcher.swift:226-237`): add `var todo_total: Double?`
  and `var todo_done: Double?`, matching the existing all-`Double?`
  convention for this struct.
- `SessionFeed` (`FeedWatcher.swift:268-296`): add `var todoTotal: Int?`
  and `var todoDone: Int?`.
- `applyState(_:)` (`FeedWatcher.swift:300-311`): direct assignment,
  matching `lastSeed`/`lastDuration`:
  `todoTotal = s.todo_total.map(Int.init)`,
  `todoDone = s.todo_done.map(Int.init)`.

## UI (`MenuContentView.swift`)

New view, alongside `UsageGauge`/`TrendGauge`:

```swift
struct TodoProgressBar: View {
    let total: Int
    let done: Int

    private static let boxCount = 10

    private var pct: Int {
        total > 0 ? Int((Double(done) / Double(total) * 100).rounded()) : 0
    }
    private var filled: Int {
        total > 0 ? Int((Double(done) / Double(total) * Double(Self.boxCount)).rounded()) : 0
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Text(String(repeating: "■", count: filled))
                    .foregroundStyle(Color.claude)
                Text(String(repeating: "□", count: Self.boxCount - filled))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
            .font(.claudeMono(11))
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: filled)
            Text("\(pct)%")
                .font(.claudeMono(11)).monospacedDigit()
                .foregroundStyle(total > 0 ? Color.claude : Color.secondary)
        }
        .help(total > 0 ? "Task progress: \(done) of \(total) done" : "No task list yet")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Task progress")
        .accessibilityValue(total > 0 ? "\(done) of \(total) done, \(pct) percent" : "no task list")
    }
}
```

`SessionRow.body` currently is one `HStack(spacing: 5)` (`MenuContentView.
swift:470-580`) carrying all the row-level modifiers directly
(`.textCase`, `.padding`, `.opacity`, `.background`, `.onHover`,
`.onTapGesture`, `.help`, `.contextMenu`, accessibility —
`MenuContentView.swift:582-611`). That `HStack` becomes the first child of
a new `VStack(alignment: .leading, spacing: 2)`, with
`TodoProgressBar(total: session.todoTotal ?? 0, done: session.todoDone ??
0)` as the second child; every row-level modifier moves from the `HStack`
onto the new outer `VStack` unchanged.

## Non-goals

- No inline/compact variant — the second-line placement is the only
  layout, decided above.
- No plan-mode step counter or other progress proxy — TodoWrite is the
  only source being wired up.
- No change to `RowLayout.columns`/`Constants.rowFixedColumns` — the bar
  is a full-width second line, not a column, so it doesn't participate in
  the per-row column budget at all.

## Testing

- `emit.sh`: new fixture-driven cases in a `spinnerfeed/test.sh` (new
  file, same harness shape as `reset-notifier/test.sh` — `fresh_case`,
  `run`, `check` helpers, real `jq`, no network/osascript): a
  `PostToolUse TodoWrite` event with a 3-item todos array (1 completed)
  writes `todo_total: 3, todo_done: 1`; a subsequent unrelated
  `PostToolUse` (different tool) carries both forward unchanged; a
  `SessionStart` resets both to `null`.
- Swift: `TodoProgressBar`'s `pct`/`filled` math extracted as it is
  above (pure, no view dependency needed beyond `total`/`done`) and
  covered by `XCTest` cases in `claude spinnerTests/claude_spinnerTests.
  swift`, following the existing `testFormatDuration`/`testFormatTokens`
  style: 0/0 → 0%/0 filled; 1/3 → 33%/3 filled; 3/3 → 100%/10 filled.
- `StateFile`/`SessionFeed` decode: one new `XCTest` asserting
  `applyState` maps `todo_total`/`todo_done` into `todoTotal`/`todoDone`,
  and that a `StateFile` missing both leaves them `nil` (not `0`).
