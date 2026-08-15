# Todo Progress Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each session's TodoWrite completion as a 10-box `□□□□□□□□□□  --%` bar on a second line under its row in the claude-spinner panel.

**Architecture:** `emit.sh` (a Claude Code hook script) captures `TodoWrite` calls on `PostToolUse`, counts total/completed items, and carries the counts forward in `<id>.state.json` like every other piece of hook-derived state. The Swift app decodes the two new fields into `SessionFeed` and renders them as a new `TodoProgressBar` view stacked under the existing row `HStack`.

**Tech Stack:** POSIX `sh` + `jq` (emit.sh), Swift/SwiftUI + XCTest (claude-spinner app)

**Spec:** `docs/superpowers/specs/2026-08-14-todo-progress-bar-design.md`

## Global Constraints

- **Two separate git repositories are touched.** `~/.claude/spinnerfeed/emit.sh` and its new `test.sh` live in the `~/.claude` repo (currently clean, tip `8c5359f`). Everything else (Swift sources, Swift tests, this plan, the spec) lives in `~/developer/claude-spinner`. Commit each task's changes in the repo it actually touched — never combine the two in one commit.
- `MACOSX_DEPLOYMENT_TARGET = 27.0` (claude-spinner `CLAUDE.md`) — no backward-compat code paths.
- Build/relaunch the app only via `./run.sh` from `~/developer/claude-spinner`; run `killall "claude spinner"` before `xcodebuild test` (UI-focus tests fail against a live instance).
- Sources under `claude spinner/` are a synchronized Xcode group — a new `.swift` file needs no `pbxproj` edit, but this plan adds no new Swift files, only edits to `MenuContentView.swift` and `FeedWatcher.swift`.
- No new fields default to `0` where `nil` is the correct "not yet known" value — follow the existing `contextTokens`/`lastDuration` optional pattern throughout.

---

### Task 1: emit.sh — capture and carry forward todo counts

**Files:**
- Modify: `~/.claude/spinnerfeed/emit.sh:21-93`
- Create: `~/.claude/spinnerfeed/test.sh`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `<id>.state.json` gains two fields, `todo_total` (number or `null`) and `todo_done` (number or `null`), which Task 2 decodes.

- [ ] **Step 1: Write the failing test file**

Create `~/.claude/spinnerfeed/test.sh`, same fixture-driven shape as
`~/developer/claude-spinner/reset-notifier/test.sh` (a `fresh_case`/`run`/
`check` harness against a temp dir, no network):

```bash
#!/bin/bash
# test.sh — fixture-driven tests for emit.sh's todo-count tracking.
set -u

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SRC_DIR/emit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

# run <event> <json> — invokes emit.sh against the temp feed dir.
run() {
  event="$1"; json="$2"
  HOME="$TMP" printf '%s' "$json" | HOME="$TMP" "$SCRIPT" "$event"
}

field() { # field <session_id> <name> — reads a field from the written state file.
  jq -r ".$2 // \"null\"" "$TMP/.claude/spinnerfeed/$1.state.json" 2>/dev/null
}

check() { # check <name> <got> <expected>
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1)); echo "PASS: $1"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $1 (expected '$3', got '$2')"
  fi
}

mkdir -p "$TMP/.claude/spinnerfeed"

# 1. TodoWrite PostToolUse with 3 todos, 1 completed -> counts recorded.
todos='[{"content":"a","status":"completed","activeForm":"a"},{"content":"b","status":"in_progress","activeForm":"b"},{"content":"c","status":"pending","activeForm":"c"}]'
run PostToolUse "{\"session_id\":\"s1\",\"tool_name\":\"TodoWrite\",\"tool_input\":{\"todos\":$todos}}"
check "todo_total recorded" "$(field s1 todo_total)" "3"
check "todo_done recorded" "$(field s1 todo_done)" "1"

# 2. A later, unrelated PostToolUse carries both forward unchanged.
run PostToolUse "{\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_input\":{}}"
check "todo_total carried forward" "$(field s1 todo_total)" "3"
check "todo_done carried forward" "$(field s1 todo_done)" "1"

# 3. SessionStart resets both to null.
run SessionStart "{\"session_id\":\"s1\"}"
check "todo_total reset on SessionStart" "$(field s1 todo_total)" "null"
check "todo_done reset on SessionStart" "$(field s1 todo_done)" "null"

# 4. A second TodoWrite completely overwrites (not adds to) the prior counts.
todos2='[{"content":"x","status":"completed","activeForm":"x"},{"content":"y","status":"completed","activeForm":"y"}]'
run PostToolUse "{\"session_id\":\"s1\",\"tool_name\":\"TodoWrite\",\"tool_input\":{\"todos\":$todos2}}"
check "second TodoWrite overwrites total" "$(field s1 todo_total)" "2"
check "second TodoWrite overwrites done" "$(field s1 todo_done)" "2"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
```

```bash
chmod +x ~/.claude/spinnerfeed/test.sh
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `~/.claude/spinnerfeed/test.sh`
Expected: FAIL on every `todo_total`/`todo_done` check (emit.sh doesn't write those fields yet, so `field` reads `null`/empty for all of them, including the "carried forward" and "overwrites" cases).

- [ ] **Step 3: Add todo capture to emit.sh**

In `~/.claude/spinnerfeed/emit.sh`, after the existing carry-forward block
(current lines 25-30, `prev_ts`/`prev_seed`/`prev_dur`), add:

```sh
prev_todo_total=$(jq -r '.todo_total // empty' "$f" 2>/dev/null)
prev_todo_done=$(jq -r '.todo_done // empty' "$f" 2>/dev/null)
todo_total="$prev_todo_total"
todo_done="$prev_todo_done"
```

In the `case "$event" in` block (current lines 58-73), extend the
`SessionStart` arm to also reset the new fields — it currently reads:

```sh
    SessionStart)     status=idle;      turn_start=""; last_seed=""; last_duration="" ;;
```

change to:

```sh
    SessionStart)     status=idle;      turn_start=""; last_seed=""; last_duration=""; todo_total=""; todo_done="" ;;
```

Immediately after the `case` block closes (current line 73, before `tmp="$f.tmp.$$"` at line 75), add:

```sh
if [ "$event" = "PostToolUse" ] && [ "$tool" = "TodoWrite" ]; then
    todos_json=$(printf '%s' "$input" | jq -c '.tool_input.todos // []')
    todo_total=$(printf '%s' "$todos_json" | jq 'length')
    todo_done=$(printf '%s' "$todos_json" | jq '[.[] | select(.status == "completed")] | length')
fi
```

Finally, extend the closing `jq -n` write (current lines 76-93) to pass
and emit the two new fields — add to the `--arg` list:

```sh
    --arg tt "$todo_total" --arg td "$todo_done" \
```

and add two lines inside the `jq -n` object literal, alongside
`turn_start`:

```sh
        todo_total:    (if $tt == "" then null else ($tt | tonumber) end),
        todo_done:     (if $td == "" then null else ($td | tonumber) end),
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `~/.claude/spinnerfeed/test.sh`
Expected: `10 passed, 0 failed`

- [ ] **Step 5: Commit (in the `~/.claude` repo)**

```bash
cd ~/.claude
git add spinnerfeed/emit.sh spinnerfeed/test.sh
git commit -m "$(cat <<'EOF'
Capture TodoWrite progress into the spinnerfeed state file

emit.sh now counts a session's todo total/done on PostToolUse and
carries the counts forward like every other hook-derived field, so
claude-spinner can render task-completion progress per row.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Decode todo counts into `SessionFeed`

**Files:**
- Modify: `claude spinner/FeedWatcher.swift:226-311`
- Test: `claude spinnerTests/claude_spinnerTests.swift`

**Interfaces:**
- Consumes: `<id>.state.json`'s `todo_total`/`todo_done` fields (Task 1).
- Produces: `SessionFeed.todoTotal: Int?` and `SessionFeed.todoDone: Int?`, which Task 3/4 render.

- [ ] **Step 1: Write the failing test**

Add to `claude spinnerTests/claude_spinnerTests.swift`, near the other
`SessionFeed`-focused tests (e.g. next to `testIsWorking`):

```swift
func testApplyStateDecodesTodoCounts() {
    var s = SessionFeed(id: "x")
    XCTAssertNil(s.todoTotal)
    XCTAssertNil(s.todoDone)

    let json = """
    {"status":"idle","todo_total":3,"todo_done":1}
    """.data(using: .utf8)!
    let state = try! JSONDecoder().decode(StateFileForTest.self, from: json)
    s.applyStateForTest(state)

    XCTAssertEqual(s.todoTotal, 3)
    XCTAssertEqual(s.todoDone, 1)
}
```

`StateFile` and `applyState` are `private`/`fileprivate` to
`FeedWatcher.swift`, so this test cannot call them directly. Step 3 adds
a `#if DEBUG`-free `internal` test seam — see below — rather than
weakening the production access level. Use exactly this in the test
instead of the snippet above (replace the whole `testApplyStateDecodesTodoCounts` body):

```swift
func testApplyStateDecodesTodoCounts() {
    var s = SessionFeed(id: "x")
    XCTAssertNil(s.todoTotal)
    XCTAssertNil(s.todoDone)
    s.applyTodoCountsForTest(total: 3, done: 1)
    XCTAssertEqual(s.todoTotal, 3)
    XCTAssertEqual(s.todoDone, 1)
}

func testApplyStateLeavesTodoCountsNilWhenAbsent() {
    var s = SessionFeed(id: "x")
    s.applyTodoCountsForTest(total: nil, done: nil)
    XCTAssertNil(s.todoTotal)
    XCTAssertNil(s.todoDone)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `killall "claude spinner" 2>/dev/null; xcodebuild -scheme "claude spinner" test | xcbeautify`
Expected: FAIL — `applyTodoCountsForTest` does not exist yet.

- [ ] **Step 3: Add the fields and a test seam**

In `FeedWatcher.swift`, add to `StateFile` (currently lines 226-237):

```swift
private struct StateFile: Decodable {
    var status: String?
    var tool: String?
    var message: String?
    var cwd: String?
    var host: String?
    var pid: Double?
    var turn_start: Double?
    var updated: Double?
    var last_seed: Double?
    var last_duration: Double?
    var todo_total: Double?
    var todo_done: Double?
}
```

Add to `SessionFeed` (currently lines 268-296), next to
`contextOutputTokens`:

```swift
    var todoTotal: Int?
    var todoDone: Int?
```

In `applyState(_:)` (currently lines 300-311), add at the end of the
method body:

```swift
        todoTotal = s.todo_total.map(Int.init)
        todoDone = s.todo_done.map(Int.init)
```

Add a small internal test seam right after `applyState` (mirrors it
exactly, but with plain `Int?` parameters so the test doesn't need
`StateFile`, which stays `private`):

```swift
    #if DEBUG
    /// Test-only mirror of `applyState`'s todo-count assignment — `StateFile`
    /// is private to this file, so XCTest exercises the same two lines through
    /// this seam instead of constructing a `StateFile` itself.
    mutating func applyTodoCountsForTest(total: Int?, done: Int?) {
        todoTotal = total
        todoDone = done
    }
    #endif
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `killall "claude spinner" 2>/dev/null; xcodebuild -scheme "claude spinner" test | xcbeautify`
Expected: PASS, both new tests green, existing 62/62 (or current count) still green.

- [ ] **Step 5: Commit (in the `claude-spinner` repo)**

```bash
cd ~/developer/claude-spinner
git add "claude spinner/FeedWatcher.swift" "claude spinnerTests/claude_spinnerTests.swift"
git commit -m "$(cat <<'EOF'
Decode todo progress counts into SessionFeed

Adds todo_total/todo_done to StateFile and SessionFeed, mirroring the
existing optional-field pattern (nil means "not yet known", not zero).

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `TodoProgressBar` view and its pure math

**Files:**
- Modify: `claude spinner/MenuContentView.swift` (new view, placed after `TrendGauge`, currently ending at line 323)
- Test: `claude spinnerTests/claude_spinnerTests.swift`

**Interfaces:**
- Consumes: nothing from other tasks (takes plain `total`/`done` Ints — Task 4 wires it to `SessionFeed`).
- Produces: `TodoProgressBar(total:done:)` view, and `TodoProgressBar.percent(total:done:)` / `TodoProgressBar.filledBoxes(total:done:)` static pure functions Task 4's rendering (and this task's tests) call.

- [ ] **Step 1: Write the failing test**

Add to `claude spinnerTests/claude_spinnerTests.swift`, near
`testFormatTokens`:

```swift
func testTodoProgressBarMath() {
    XCTAssertEqual(TodoProgressBar.percent(total: 0, done: 0), 0)
    XCTAssertEqual(TodoProgressBar.filledBoxes(total: 0, done: 0), 0)

    XCTAssertEqual(TodoProgressBar.percent(total: 3, done: 1), 33)
    XCTAssertEqual(TodoProgressBar.filledBoxes(total: 3, done: 1), 3)  // round(10/3) = 3

    XCTAssertEqual(TodoProgressBar.percent(total: 3, done: 3), 100)
    XCTAssertEqual(TodoProgressBar.filledBoxes(total: 3, done: 3), 10)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `killall "claude spinner" 2>/dev/null; xcodebuild -scheme "claude spinner" test | xcbeautify`
Expected: FAIL — `TodoProgressBar` does not exist yet.

- [ ] **Step 3: Implement `TodoProgressBar`**

In `MenuContentView.swift`, add this new view directly after `TrendGauge`
(currently ends line 323, right before the `extension SessionFeed`
block that starts at line 325):

```swift
/// Ten-box task-completion bar shown on a second line under a session row:
/// filled boxes track a session's current TodoWrite list, held at an empty
/// 0% before any TodoWrite call rather than being hidden — so the row's
/// height never changes once a session starts writing todos.
///
/// Deliberately not `Color.usageTint` — that gradient reads high-percentage
/// as *dangerous* (rate-limit/context consumption), which is backwards for
/// task completion, where 100% is the good outcome. One flat "in progress"
/// tint instead, matching the row's own working color.
struct TodoProgressBar: View {
    let total: Int
    let done: Int

    private static let boxCount = 10

    static func percent(total: Int, done: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(done) / Double(total) * 100).rounded())
    }

    static func filledBoxes(total: Int, done: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(done) / Double(total) * Double(boxCount)).rounded())
    }

    private var pct: Int { Self.percent(total: total, done: done) }
    private var filled: Int { Self.filledBoxes(total: total, done: done) }

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

- [ ] **Step 4: Run the test to verify it passes**

Run: `killall "claude spinner" 2>/dev/null; xcodebuild -scheme "claude spinner" test | xcbeautify`
Expected: PASS, new test green, all prior tests still green.

- [ ] **Step 5: Commit**

```bash
cd ~/developer/claude-spinner
git add "claude spinner/MenuContentView.swift" "claude spinnerTests/claude_spinnerTests.swift"
git commit -m "$(cat <<'EOF'
Add TodoProgressBar view

Ten-box completion bar with its percent/filled-box math exposed as
pure static functions so the layout math is unit-tested without
standing up a view. Not wired into SessionRow yet.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Wire `TodoProgressBar` into `SessionRow`

**Files:**
- Modify: `claude spinner/MenuContentView.swift:458-612` (`SessionRow`)

**Interfaces:**
- Consumes: `SessionFeed.todoTotal`/`todoDone` (Task 2), `TodoProgressBar` (Task 3).
- Produces: nothing further — this is the last task.

This task has no new pure logic to unit-test (it is a layout wiring
change), so verification is manual per the project's UI-change
convention (`CLAUDE.md`: "start the dev server ... use the feature in a
browser before reporting the task as complete").

- [ ] **Step 1: Wrap the row body and move the row-level modifiers**

In `MenuContentView.swift`, `SessionRow.body` (currently lines 468-580 is
the `HStack(spacing: 5) { ... }`, followed by the modifier chain at lines
582-611). Change the `var body: some View {` block from:

```swift
    var body: some View {
        // One line: [glyph] project-name ×N  model  status…  ctx%  time  [chip]
        HStack(spacing: 5) {
            Text(glyph)
            // ... existing content, unchanged ...
        }
        // Everything in a row renders lowercase — including hook-supplied text like
        // the attention message and tool names — for one consistent visual voice.
        .textCase(.lowercase)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .opacity(rowOpacity)
        .background(rowHighlight)
        .onHover { hover.isHovering = $0 }
        .onTapGesture {
            openSession()
        }
        .help(rowTooltip)
        .contextMenu {
            // ... existing menu items, unchanged ...
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.displayName), \(statusLabel) \(timeText)\(contextTokens.isEmpty ? "" : ", \(contextTokens) context tokens")")
        .accessibilityHint("Opens this session's app")
        .accessibilityAction(named: "Clear session") { feed.clear(item) }
    }
```

to:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // One line: [glyph] project-name ×N  model  status…  ctx%  time  [chip]
            HStack(spacing: 5) {
                Text(glyph)
                // ... existing content, unchanged ...
            }

            TodoProgressBar(total: session.todoTotal ?? 0, done: session.todoDone ?? 0)
                .padding(.leading, 20)  // aligns under the name column, past the glyph
        }
        // Everything in a row renders lowercase — including hook-supplied text like
        // the attention message and tool names — for one consistent visual voice.
        .textCase(.lowercase)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .opacity(rowOpacity)
        .background(rowHighlight)
        .onHover { hover.isHovering = $0 }
        .onTapGesture {
            openSession()
        }
        .help(rowTooltip)
        .contextMenu {
            // ... existing menu items, unchanged ...
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.displayName), \(statusLabel) \(timeText)\(contextTokens.isEmpty ? "" : ", \(contextTokens) context tokens")")
        .accessibilityHint("Opens this session's app")
        .accessibilityAction(named: "Clear session") { feed.clear(item) }
    }
```

Only the outer wrapper and the new `TodoProgressBar` line change — the
`HStack`'s own content (glyph through the trailing host-chip `ZStack`)
and every modifier's arguments are copied verbatim, not rewritten.

- [ ] **Step 2: Build and run the existing test suite**

Run: `killall "claude spinner" 2>/dev/null; xcodebuild -scheme "claude spinner" test | xcbeautify`
Expected: PASS — this step has no new tests, but must not regress any
existing one (in particular any row-layout test if one measures
`SessionRow` directly — check `claude_spinnerTests.swift` for one before
assuming none exists).

- [ ] **Step 3: Manual verification in the running app**

```bash
cd ~/developer/claude-spinner
./run.sh
```

Open the panel. Confirm:
- Every row now shows a second line: `□□□□□□□□□□ 0%` in a dim/secondary
  tint, for sessions that haven't called TodoWrite.
- In a session that *has* called TodoWrite (this very session has —
  check its row), the bar shows partially/fully filled boxes in the
  working accent color with the correct percentage.
- Row heights are uniform across the whole list (no jump between
  todo/no-todo rows).
- The panel still fits within `feed.panelWidth` — the new line must not
  force horizontal overflow (it's full-width under the row, not a new
  column, so this should hold by construction, but confirm on screen).

- [ ] **Step 4: Commit**

```bash
cd ~/developer/claude-spinner
git add "claude spinner/MenuContentView.swift"
git commit -m "$(cat <<'EOF'
Show TodoProgressBar under every session row

Wires the second line into SessionRow, wrapping the existing one-line
HStack and its row-level modifiers in a VStack. Every row now carries
a task-completion bar, empty at 0% until a session's first TodoWrite.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```
