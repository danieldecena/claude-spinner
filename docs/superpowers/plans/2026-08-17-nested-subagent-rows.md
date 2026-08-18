# Nested Subagent Rows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each Claude Code subagent as an indented child row under its parent in the claude-spinner panel, with the subagent's own live datapoints, instead of clobbering the parent feed file.

**Architecture:** Subagents share the parent's `session_id`; hook stdin carries `agent_id` / `agent_type` only inside a subagent. `emit.sh` already keys only on `session_id`, so child `PreToolUse` overwrites the parent `.state.json` today. Route any event with a non-empty `agent_id` to `~/.claude/spinnerfeed/<parent>.<agent_id>.state.json`, tagged with `parent_session_id`. The app decodes those fields, groups children under the parent in `displayItems`, and reuses `SessionRow` at `depth: 1` (16pt indent, full 2-line row).

**Tech Stack:** POSIX `sh` + `jq` (emit.sh), Swift/SwiftUI + XCTest (claude-spinner app)

**Spec:** `docs/superpowers/specs/2026-08-17-nested-subagent-rows-design.md`

## Global Constraints

- **Two separate git repositories are touched.** Task 1 lives in the `~/.claude` repo (tip `fdc06dd`; that tree is dirty with unrelated `settings.json` / skill edits — commit **only** `spinnerfeed/emit.sh` and `spinnerfeed/test.sh`). Tasks 2–4 live in `~/developer/claude-spinner` (tip `02b1487`; also dirty with unrelated workflow/docs/run.sh edits — commit **only** the files this plan names). Never combine the two repos in one commit.
- `MACOSX_DEPLOYMENT_TARGET = 27.0` — no backward-compat code paths.
- Build/relaunch only via `./run.sh` from `~/developer/claude-spinner`. Run `killall "claude spinner"` before `xcodebuild test` (app-hosted tests `exit(0)` if a copy is already running).
- Sources under `claude spinner/` are a synchronized Xcode group — this plan adds no new Swift files.
- No new field defaults to `0` / `""` where `nil` is "not yet known". `parent_session_id` / `agent_id` / `agent_type` are `null` on root files.
- The bundled `claude spinner/Scripts/emit.sh` must stay **byte-identical** to `~/.claude/spinnerfeed/emit.sh`. Last feature shipped dead on fresh installs because only the live copy was updated.
- Test seams exercise production code (`applyStateJSONForTest`, `displayItems(from:)`, `menuBarState(for:)`, real `emit.sh` via `test.sh`) — no hand-mirrors of `applyState`.
- Do not reuse `Color.usageTint` for "subagent is working". Children use the same `.claude` working tint as parents.
- Do not edit `statusline-command.sh`, parse transcripts / `*.meta.json`, or wire `subagentStatusLine` (v2). Cursor Task-tool subagents are out of scope.
- Visual nesting is depth 1. Grandchildren flatten under the same parent (hook stdin has no `parent_agent_id`).

## File Structure

| File | Responsibility |
|---|---|
| `~/.claude/spinnerfeed/emit.sh` | Route `agent_id` events to a child state file; create/reset on `SubagentStart`; idle on `SubagentStop`; parent `SessionEnd` glob-deletes children. |
| `~/.claude/spinnerfeed/test.sh` | Fixture harness for emit.sh (existing todo cases stay; child-file cases added). |
| `claude spinner/Scripts/emit.sh` | Byte-identical bundled copy installed by SetupInstaller. |
| `claude spinner/SetupInstaller.swift` | `hookEvents` gains `SubagentStart` / `SubagentStop`. |
| `claude spinner/FeedWatcher.swift` | Decode parent/agent fields; `SessionRowItem.depth` / `subagentCount`; grouping, orphan prune, menu-bar root counts, `modelDisplay` child guard. |
| `claude spinner/MenuContentView.swift` | Indent, host-chip omission, Divider skip, line-2 indent budget, ScrollView, VoiceOver. |
| `claude spinnerTests/claude_spinnerTests.swift` | Decode, grouping, menu-bar, bundled-script, installer, line-2 budget. |

---

### Task 1: emit.sh — child state files

**Files:**
- Modify: `/Users/home/.claude/spinnerfeed/emit.sh`
- Modify: `/Users/home/.claude/spinnerfeed/test.sh`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: a child file `~/.claude/spinnerfeed/<sid>.<agent_id>.state.json` whose JSON has `session_id` = parent UUID, `parent_session_id` = parent UUID, `agent_id`, `agent_type`, plus the existing status/tool/todo/pid/host fields. Parent `SessionEnd` deletes `$dir/$sid.*`. Task 2 decodes the three new fields.

- [ ] **Step 1: Append the failing child-file cases to test.sh**

Keep the existing todo cases (1–4) and helpers (`run`, `field`, `check`) unchanged. `field` already takes a filename stem, so `field s1.a1 parent_session_id` reads `s1.a1.state.json`. Add an `exists` helper and the new cases **after** case 4, before the summary `echo`.

Replace `/Users/home/.claude/spinnerfeed/test.sh` with this complete file:

```bash
#!/bin/bash
# test.sh — fixture-driven tests for emit.sh (todo counts + subagent child files).
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

field() { # field <stem> <name> — reads a field from <stem>.state.json.
  jq -r ".$2 // \"null\"" "$TMP/.claude/spinnerfeed/$1.state.json" 2>/dev/null
}

exists() { # exists <filename> — "yes" / "no" under the temp feed dir.
  if [ -f "$TMP/.claude/spinnerfeed/$1" ]; then echo "yes"; else echo "no"; fi
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

# 5. PreToolUse with agent_id writes the child file and leaves the parent untouched.
run SessionStart "{\"session_id\":\"p1\"}"
run PreToolUse "{\"session_id\":\"p1\",\"agent_id\":\"a1\",\"agent_type\":\"Explore\",\"tool_name\":\"Grep\"}"
check "child file created" "$(exists p1.a1.state.json)" "yes"
check "child status is tool" "$(field p1.a1 status)" "tool"
check "child tool is Grep" "$(field p1.a1 tool)" "Grep"
check "child parent_session_id" "$(field p1.a1 parent_session_id)" "p1"
check "child agent_id" "$(field p1.a1 agent_id)" "a1"
check "child agent_type" "$(field p1.a1 agent_type)" "Explore"
check "child session_id is the parent" "$(field p1.a1 session_id)" "p1"
check "parent status still idle" "$(field p1 status)" "idle"
check "parent has no parent_session_id" "$(field p1 parent_session_id)" "null"
check "parent has no agent_id" "$(field p1 agent_id)" "null"

# 6. SubagentStart creates the child with thinking + null todos.
run SubagentStart "{\"session_id\":\"p1\",\"agent_id\":\"a2\",\"agent_type\":\"general-purpose\"}"
check "SubagentStart status thinking" "$(field p1.a2 status)" "thinking"
check "SubagentStart parent_session_id" "$(field p1.a2 parent_session_id)" "p1"
check "SubagentStart agent_type" "$(field p1.a2 agent_type)" "general-purpose"
check "SubagentStart todo_total null" "$(field p1.a2 todo_total)" "null"
check "SubagentStart todo_done null" "$(field p1.a2 todo_done)" "null"

# 7. Child PostToolUse TodoWrite updates the CHILD todos, not the parent.
child_todos='[{"content":"c","status":"completed","activeForm":"c"},{"content":"d","status":"pending","activeForm":"d"}]'
run PostToolUse "{\"session_id\":\"p1\",\"agent_id\":\"a2\",\"agent_type\":\"general-purpose\",\"tool_name\":\"TodoWrite\",\"tool_input\":{\"todos\":$child_todos}}"
check "child todo_total" "$(field p1.a2 todo_total)" "2"
check "child todo_done" "$(field p1.a2 todo_done)" "1"
check "parent todo_total unchanged" "$(field p1 todo_total)" "null"

# 8. SubagentStop marks the child idle with a numeric last_duration; parent stays.
run SubagentStop "{\"session_id\":\"p1\",\"agent_id\":\"a2\",\"agent_type\":\"general-purpose\"}"
check "SubagentStop status idle" "$(field p1.a2 status)" "idle"
check "SubagentStop last_duration numeric" "$(field p1.a2 last_duration | grep -E '^[0-9]+$' >/dev/null && echo numeric || echo missing)" "numeric"
check "parent still present after SubagentStop" "$(exists p1.state.json)" "yes"

# 9. Child-flavoured SessionEnd removes only that child file.
run SessionEnd "{\"session_id\":\"p1\",\"agent_id\":\"a2\"}"
check "child SessionEnd removes child" "$(exists p1.a2.state.json)" "no"
check "child SessionEnd keeps parent" "$(exists p1.state.json)" "yes"
check "child SessionEnd keeps sibling" "$(exists p1.a1.state.json)" "yes"

# 10. Parent SessionEnd glob-removes parent state/status AND remaining children.
run SessionEnd "{\"session_id\":\"p1\"}"
check "parent SessionEnd removes parent state" "$(exists p1.state.json)" "no"
check "parent SessionEnd removes remaining child" "$(exists p1.a1.state.json)" "no"

# 11. PreToolUse without agent_id still writes the parent (root regression).
run PreToolUse "{\"session_id\":\"p2\",\"tool_name\":\"Bash\"}"
check "root PreToolUse writes parent" "$(field p2 status)" "tool"
check "root PreToolUse writes no child" "$(exists p2.a1.state.json)" "no"

# 12. SubagentStart without agent_id is ignored (must not clobber the parent).
run SessionStart "{\"session_id\":\"p3\"}"
run SubagentStart "{\"session_id\":\"p3\"}"
check "SubagentStart without agent_id leaves parent idle" "$(field p3 status)" "idle"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
```

- [ ] **Step 2: Run it to confirm the new cases fail**

Run: `/Users/home/.claude/spinnerfeed/test.sh`

Expected: cases 1–4 still PASS (todo capture is already shipped). Cases 5–12 FAIL: current emit.sh keys only on `session_id`, so a `PreToolUse` with `agent_id` overwrites `p1.state.json` (`parent status still idle` fails), never creates `p1.a1.state.json`, and `SubagentStart` / `SubagentStop` hit the `*) exit 0` arm. `test.sh` exits non-zero.

- [ ] **Step 3: Implement the child-file branch in emit.sh**

Replace `/Users/home/.claude/spinnerfeed/emit.sh` with this complete script. Behaviour for events with an empty `agent_id` is unchanged (same parent path, same todo capture, same pid/host walk). The new work is: sanitize `agent_id`, point `$f` at the child file when it is set, add `SubagentStart`/`SubagentStop` arms, branch `SessionEnd`, persist the three new JSON fields.

```sh
#!/bin/sh
# Menubar feed emitter — called by Claude Code lifecycle hooks.
# Usage: emit.sh <EVENT>      (hook JSON arrives on stdin)
# Writes one state file per session: ~/.claude/spinnerfeed/<session_id>.state.json
# Paired with <session_id>.status.json, written by the statusLine script.
# Events whose stdin carries agent_id (a subagent) write
# ~/.claude/spinnerfeed/<session_id>.<agent_id>.state.json instead, and never
# touch the parent file.

event="$1"
dir="$HOME/.claude/spinnerfeed"
mkdir -p "$dir"

input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -z "$sid" ] && exit 0

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty')
agent_type=$(printf '%s' "$input" | jq -r '.agent_type // empty')
# Filename-safe. Observed values are hex (`a639953774a9953ac`) and docs
# examples like `agent-abc123`. Anything else is stripped; an empty result
# is treated as a root event so we never write a junk path.
agent_id=$(printf '%s' "$agent_id" | tr -cd 'A-Za-z0-9_-')

if [ -n "$agent_id" ]; then
    parent_sid="$sid"
    f="$dir/$sid.$agent_id.state.json"
else
    parent_sid=""
    f="$dir/$sid.state.json"
fi

now=$(date +%s)
cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty')
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
msg=$(printf '%s' "$input" | jq -r '.message // empty')

# turn_start must survive across PreToolUse/PostToolUse within one turn, so carry
# the previous values forward unless this event (re)starts or ends the turn.
# last_seed / last_duration capture the just-finished turn so the app can show
# Claude's grey "Sautéed for 5m 18s" done line until the next prompt.
prev_ts=$(jq -r '.turn_start // empty' "$f" 2>/dev/null)
prev_seed=$(jq -r '.last_seed // empty' "$f" 2>/dev/null)
prev_dur=$(jq -r '.last_duration // empty' "$f" 2>/dev/null)
prev_todo_total=$(jq -r '.todo_total // empty' "$f" 2>/dev/null)
prev_todo_done=$(jq -r '.todo_done // empty' "$f" 2>/dev/null)
prev_agent_type=$(jq -r '.agent_type // empty' "$f" 2>/dev/null)

last_seed="$prev_seed"
last_duration="$prev_dur"
todo_total="$prev_todo_total"
todo_done="$prev_todo_done"
[ -z "$agent_type" ] && agent_type="$prev_agent_type"

# Host app the session runs in, so the menubar can open the right one on click.
# __CFBundleIdentifier is inherited from the launching GUI app (Claude desktop,
# VS Code, iTerm2, Ghostty, Terminal); TERM_PROGRAM is the terminal fallback.
# Carry the previous value forward if this event's env doesn't expose it.
host="${__CFBundleIdentifier:-${TERM_PROGRAM:-}}"
[ -z "$host" ] && host=$(jq -r '.host // empty' "$f" 2>/dev/null)

# Walk up from this hook to the owning `claude` process and record its pid, so the
# app can prune a session whose process died without firing SessionEnd (e.g. the
# terminal was killed). Match the executable basename exactly — the full path holds
# ".claude/…", which a substring match would false-hit. Carry the previous pid
# forward if the walk comes up empty this event.
pid=""
p="$PPID"
i=0
while [ "$p" -gt 1 ] && [ "$i" -lt 12 ]; do
    line=$(ps -o ppid=,comm= -p "$p" 2>/dev/null)
    [ -z "$line" ] && break
    ppid=$(printf '%s' "$line" | awk '{print $1}')
    comm=$(printf '%s' "$line" | awk '{$1=""; sub(/^ /,""); print}')
    case "${comm##*/}" in claude) pid="$p"; break ;; esac
    p="$ppid"
    i=$((i + 1))
done
[ -z "$pid" ] && pid=$(jq -r '.pid // empty' "$f" 2>/dev/null)

case "$event" in
    SessionStart)     status=idle;      turn_start=""; last_seed=""; last_duration=""; todo_total=""; todo_done="" ;;
    UserPromptSubmit) status=thinking;  turn_start="$now"; last_seed=""; last_duration="" ;;
    PreToolUse)       status=tool;      turn_start="$prev_ts" ;;
    PostToolUse)      status=thinking;  turn_start="$prev_ts" ;;
    Notification)     status=attention; turn_start="$prev_ts" ;;
    SubagentStart)
        [ -z "$agent_id" ] && exit 0
        status=thinking; turn_start="$now"; last_seed=""; last_duration=""; todo_total=""; todo_done="" ;;
    Stop|SubagentStop)
        [ "$event" = "SubagentStop" ] && [ -z "$agent_id" ] && exit 0
        status=idle
        if [ -n "$prev_ts" ]; then
            last_seed="$prev_ts"
            last_duration=$(( now - prev_ts ))
        fi
        turn_start="" ;;
    SessionEnd)
        if [ -n "$agent_id" ]; then
            rm -f "$dir/$sid.$agent_id.state.json"
        else
            rm -f "$dir/$sid".*
        fi
        exit 0 ;;
    *) exit 0 ;;
esac

if [ "$event" = "PostToolUse" ] && [ "$tool" = "TodoWrite" ]; then
    todos_json=$(printf '%s' "$input" | jq -c '.tool_input.todos // []')
    todo_total=$(printf '%s' "$todos_json" | jq 'length')
    todo_done=$(printf '%s' "$todos_json" | jq '[.[] | select(.status == "completed")] | length')
fi

tmp="$f.tmp.$$"
jq -n \
    --arg sid "$sid" --arg status "$status" --arg tool "$tool" \
    --arg cwd "$cwd" --arg msg "$msg" --arg ts "$turn_start" --arg now "$now" \
    --arg ls "$last_seed" --arg ld "$last_duration" --arg host "$host" \
    --arg pid "$pid" --arg tt "$todo_total" --arg td "$todo_done" \
    --arg psid "$parent_sid" --arg aid "$agent_id" --arg atype "$agent_type" \
    '{
        session_id:        $sid,
        status:            $status,
        tool:              $tool,
        cwd:               $cwd,
        message:           $msg,
        host:              $host,
        pid:               (if $pid == "" then null else ($pid | tonumber) end),
        turn_start:        (if $ts == "" then null else ($ts | tonumber) end),
        todo_total:        (if $tt == "" then null else ($tt | tonumber) end),
        todo_done:         (if $td == "" then null else ($td | tonumber) end),
        last_seed:         (if $ls == "" then null else ($ls | tonumber) end),
        last_duration:     (if $ld == "" then null else ($ld | tonumber) end),
        parent_session_id: (if $psid == "" then null else $psid end),
        agent_id:          (if $aid == "" then null else $aid end),
        agent_type:        (if $atype == "" then null else $atype end),
        updated:           ($now | tonumber)
    }' > "$tmp" 2>/dev/null && mv "$tmp" "$f"

exit 0
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `/Users/home/.claude/spinnerfeed/test.sh`

Expected: `N passed, 0 failed` (N is 10 todo checks + the new child checks; currently 10 + 24 = 34) and exit 0. Every case in 5–12 must PASS, including `parent status still idle` after a child `PreToolUse`.

- [ ] **Step 5: Commit (in the ~/.claude repo only)**

```bash
cd /Users/home/.claude
git add spinnerfeed/emit.sh spinnerfeed/test.sh
git commit -m "$(cat <<'EOF'
Capture subagent hooks into per-agent state files

Events whose stdin carries agent_id now write
<parent>.<agent_id>.state.json and leave the parent file alone, so a
child PreToolUse no longer overwrites the parent's current tool.
SubagentStart/Stop create and complete those files; parent SessionEnd
still glob-deletes $sid.*.
EOF
)"
```

Do **not** `git add` `settings.json` or anything else that is already dirty on this repo.

---

### Task 2: Decode child fields and nest them in displayItems

**Files:**
- Modify: `/Users/home/developer/claude-spinner/claude spinner/FeedWatcher.swift`
- Modify: `/Users/home/developer/claude-spinner/claude spinnerTests/claude_spinnerTests.swift`

**Interfaces:**
- Consumes: child `.state.json` shape from Task 1 (`parent_session_id` / `agent_id` / `agent_type` strings or `null`).
- Produces: `SessionFeed.parentSessionId` / `agentId` / `agentType` / `isChild`; `SessionRowItem.depth` (`0` root, `1` child) and `subagentCount`; `FeedWatcher.displayItems(from:)` emits a parent then its children; `modelDisplay(for:among:cached:)` returns only `session.model` for children (no sibling/cache fallback). Task 4 reads `depth` / `subagentCount` / `isChild`.

- [ ] **Step 1: Write the failing tests**

In `claude spinnerTests/claude_spinnerTests.swift`, extend the existing `mk` helper (currently at lines 16–23) so later fixtures can tag children without breaking any existing call site — new parameters default to `nil`:

```swift
    /// Build a bare session fixture for the pure-derivation tests.
    private func mk(_ id: String, _ status: SessionStatus, cwd: String = "/x",
                    updated: Date? = nil, lastDuration: Int? = nil,
                    tokens: Int? = nil,
                    parentSessionId: String? = nil,
                    agentId: String? = nil,
                    agentType: String? = nil) -> SessionFeed {
        var s = SessionFeed(id: id)
        s.status = status; s.cwd = cwd; s.updated = updated; s.lastDuration = lastDuration
        s.contextInputTokens = tokens
        s.parentSessionId = parentSessionId
        s.agentId = agentId
        s.agentType = agentType
        return s
    }
```

This will not compile until Task 2 Step 3 adds the three properties — that is the intended red. Insert the new tests immediately after `testDisplayItemsKeepsDistinctDirsSeparate` (after line 231):

```swift
    func testApplyStateDecodesParentAndAgentFields() throws {
        var s = SessionFeed(id: "p.a1")
        XCTAssertNil(s.parentSessionId)
        XCTAssertNil(s.agentId)
        XCTAssertNil(s.agentType)
        XCTAssertFalse(s.isChild)
        try s.applyStateJSONForTest("""
        {"parent_session_id":"p","agent_id":"a1","agent_type":"Explore"}
        """)
        XCTAssertEqual(s.parentSessionId, "p")
        XCTAssertEqual(s.agentId, "a1")
        XCTAssertEqual(s.agentType, "Explore")
        XCTAssertTrue(s.isChild)
    }

    func testApplyStateLeavesParentAndAgentFieldsNilWhenAbsent() throws {
        var s = SessionFeed(id: "p")
        try s.applyStateJSONForTest("{}")
        XCTAssertNil(s.parentSessionId)
        XCTAssertNil(s.agentId)
        XCTAssertNil(s.agentType)
        XCTAssertFalse(s.isChild)
    }

    func testDisplayItemsNestsWorkingChildUnderIdleParent() {
        let now = Date()
        let items = FeedWatcher.displayItems(from: [
            mk("p", .idle, cwd: "/home", updated: now, lastDuration: 10),
            mk("p.a1", .tool, cwd: "/home", updated: now,
               parentSessionId: "p", agentId: "a1", agentType: "Explore"),
            mk("other", .idle, cwd: "/home", updated: now.addingTimeInterval(-5)),
        ])
        // Idle parent with a live child is NOT folded into the never-worked
        // idle:/home bucket with `other`.
        XCTAssertEqual(items.map(\.id), ["p", "p.a1", "idle:/home"])
        XCTAssertEqual(items[0].depth, 0)
        XCTAssertEqual(items[0].subagentCount, 1)
        XCTAssertEqual(items[0].ids, ["p", "p.a1"])
        XCTAssertEqual(items[1].depth, 1)
        XCTAssertEqual(items[1].ids, ["p.a1"])
        XCTAssertEqual(items[1].session.displayName, "Explore")
    }

    func testDisplayItemsDoesNotCollapseChildWithSameCwdIdle() {
        let now = Date()
        let items = FeedWatcher.displayItems(from: [
            mk("p", .thinking, cwd: "/x", updated: now),
            mk("p.a1", .idle, cwd: "/x", updated: now, lastDuration: 4,
               parentSessionId: "p", agentId: "a1", agentType: "Explore"),
            mk("idle-root", .idle, cwd: "/x", updated: now),
        ])
        XCTAssertEqual(items.map(\.id), ["p", "p.a1", "idle:/x"])
        XCTAssertEqual(items[1].depth, 1)
        XCTAssertEqual(items[2].count, 1)
    }

    func testDisplayItemsFlattensTwoExploresUnderOneParent() {
        let now = Date()
        let items = FeedWatcher.displayItems(from: [
            mk("p", .thinking, cwd: "/p", updated: now),
            mk("p.aaa1xxxx", .tool, cwd: "/p", updated: now,
               parentSessionId: "p", agentId: "aaa1xxxx", agentType: "Explore"),
            mk("p.bbb2yyyy", .attention, cwd: "/p", updated: now,
               parentSessionId: "p", agentId: "bbb2yyyy", agentType: "Explore"),
        ])
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].id, "p")
        XCTAssertEqual(items[0].depth, 0)
        XCTAssertEqual(items[0].subagentCount, 2)
        XCTAssertEqual(items[1].depth, 1)
        XCTAssertEqual(items[2].depth, 1)
        // Duplicate agent_type: last 4 of agentId disambiguates.
        let childNames = Set(items.dropFirst().map(\.session.displayName))
        XCTAssertEqual(childNames, ["Explore xxxx", "Explore yyyy"])
    }

    func testDisplayItemsDropsIdleOrphanChild() {
        let now = Date()
        let items = FeedWatcher.displayItems(from: [
            mk("orphan", .idle, cwd: "/x", updated: now, lastDuration: 3,
               parentSessionId: "missing", agentId: "a1", agentType: "Explore"),
        ])
        XCTAssertTrue(items.isEmpty)
    }

    func testDisplayItemsPromotesWorkingOrphanChild() {
        let now = Date()
        let items = FeedWatcher.displayItems(from: [
            mk("orphan", .tool, cwd: "/x", updated: now,
               parentSessionId: "missing", agentId: "a1", agentType: "Explore"),
        ])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "orphan")
        XCTAssertEqual(items[0].depth, 0)
        XCTAssertEqual(items[0].session.displayName, "Explore")
    }

    func testExcludingOrphanIdleChildrenKeepsAttachedAndWorkingOrphans() {
        let now = Date()
        let parent = mk("p", .idle, updated: now)
        let attached = mk("p.a1", .idle, updated: now, lastDuration: 2,
                          parentSessionId: "p", agentId: "a1", agentType: "Explore")
        let idleOrphan = mk("gone.a2", .idle, updated: now, lastDuration: 2,
                            parentSessionId: "gone", agentId: "a2", agentType: "Explore")
        let workingOrphan = mk("gone.a3", .tool, updated: now,
                               parentSessionId: "gone", agentId: "a3", agentType: "Explore")
        let kept = FeedWatcher.excludingOrphanIdleChildren([parent, attached, idleOrphan, workingOrphan])
        XCTAssertEqual(Set(kept.map(\.id)), ["p", "p.a1", "gone.a3"])
    }

    func testMenuBarStaysWorkingWhenOnlyChildrenWork() {
        let now = Date()
        let parent = mk("p", .idle, updated: now, lastDuration: 10)
        let child = mk("p.a1", .tool, updated: now,
                       parentSessionId: "p", agentId: "a1", agentType: "Explore")
        XCTAssertEqual(FeedWatcher.menuBarState(for: [parent, child], now: now), .working)
        XCTAssertEqual(FeedWatcher.rootWorkingCount([parent, child]), 0)
        XCTAssertEqual(FeedWatcher.rootWorkingCount([
            mk("p", .tool, updated: now), child
        ]), 1)
    }

    func testMenuBarDoneFlashIgnoresChild() {
        let now = Date()
        let parent = mk("p", .idle, updated: now.addingTimeInterval(-30))
        let child = mk("p.a1", .idle, updated: now, lastDuration: 4,
                       parentSessionId: "p", agentId: "a1", agentType: "Explore")
        XCTAssertEqual(FeedWatcher.menuBarState(for: [parent, child], now: now), .idle)
    }

    func testModelDisplaySkipsFallbackForChild() {
        var child = mk("p.a1", .tool, parentSessionId: "p", agentId: "a1", agentType: "Explore")
        var sibling = mk("p", .thinking)
        sibling.model = "Opus"
        XCTAssertNil(FeedWatcher.modelDisplay(for: child, among: [sibling, child], cached: "Sonnet"))
        child.model = "Haiku"
        XCTAssertEqual(FeedWatcher.modelDisplay(for: child, among: [sibling, child], cached: "Sonnet"), "Haiku")
        XCTAssertEqual(FeedWatcher.modelDisplay(for: sibling, among: [sibling, child], cached: "Sonnet"), "Opus")
    }
```

- [ ] **Step 2: Compile the tests to confirm they fail**

```bash
killall "claude spinner" 2>/dev/null
cd /Users/home/developer/claude-spinner
xcodebuild -scheme "claude spinner" test
```

Expected: compile errors on `parentSessionId` / `agentId` / `agentType` / `isChild` / `SessionRowItem.depth` / `subagentCount` / `excludingOrphanIdleChildren` / `rootWorkingCount` / `modelDisplay(for:among:cached:)` — those symbols do not exist yet. Do not "fix" the tests to compile against the old API.

- [ ] **Step 3: Add the fields, grouping, and guards**

In `claude spinner/FeedWatcher.swift`:

**`StateFile`** (currently lines 231–244) — add three optional strings after `todo_done`:

```swift
    var todo_total: Double?
    var todo_done: Double?
    var parent_session_id: String?
    var agent_id: String?
    var agent_type: String?
```

**`SessionFeed`** (after `todoDone`, currently line 304) — add:

```swift
    var todoTotal: Int?
    var todoDone: Int?
    var parentSessionId: String?
    var agentId: String?
    var agentType: String?
    var isChild: Bool { parentSessionId != nil }
```

**`applyState`** (after the todo assignments, currently lines 320–321) — add:

```swift
        todoTotal = s.todo_total.map(Int.init)
        todoDone = s.todo_done.map(Int.init)
        parentSessionId = s.parent_session_id
        agentId = s.agent_id
        agentType = s.agent_type
```

**`displayName`** (currently line 363) — children use `agentType`, not the parent's folder name. `displayItems` may also set `sessionName` to a disambiguated value (duplicate Explores); that still wins via `sessionName ??`:

```swift
    var displayName: String {
        if isChild { return sessionName ?? agentType ?? "subagent" }
        return sessionName ?? projectName
    }
```

**`SessionRowItem`** (currently lines 409–414) — add `depth` and `subagentCount` with defaults so existing `SessionRowItem(id:session:ids:)` call sites still compile:

```swift
struct SessionRowItem: Identifiable {
    let id: String
    let session: SessionFeed
    let ids: [String]
    var count: Int { ids.count }
    /// 0 = root row, 1 = nested subagent. Visual nesting is capped at 1.
    var depth: Int = 0
    /// How many subagent child ids are included in `ids` (0 for collapsed
    /// idle groups, which also have `ids.count > 1`).
    var subagentCount: Int = 0
}
```

**Replace `displayItems(from:)`** (currently lines 1045–1068) with:

```swift
    static func childDisplayName(for child: SessionFeed, siblings: [SessionFeed]) -> String {
        let base = child.agentType ?? "subagent"
        let dup = siblings.filter { ($0.agentType ?? "subagent") == base }.count > 1
        guard dup, let aid = child.agentId, aid.count >= 4 else { return base }
        return "\(base) \(String(aid.suffix(4)))"
    }

    /// Drop an idle child whose parent is not in the live set. Working /
    /// attention orphans stay (the panel promotes them to depth 0). Roots
    /// always stay. Pure so prune is testable without I/O; `performRescan`
    /// uses this on the in-memory live set, after which the existing mtime
    /// walker deletes files that dropped out.
    static func excludingOrphanIdleChildren(_ sessions: [SessionFeed]) -> [SessionFeed] {
        let rootIds = Set(sessions.filter { $0.parentSessionId == nil }.map(\.id))
        return sessions.filter { s in
            guard let parent = s.parentSessionId else { return true }
            if rootIds.contains(parent) { return true }
            return s.isWorking || s.status == .attention
        }
    }

    static func displayItems(from sessions: [SessionFeed]) -> [SessionRowItem] {
        var childrenByParent: [String: [SessionFeed]] = [:]
        var roots: [SessionFeed] = []
        for s in sessions {
            if let parent = s.parentSessionId {
                childrenByParent[parent, default: []].append(s)
            } else {
                roots.append(s)
            }
        }

        var items: [SessionRowItem] = []
        var groups: [String: [SessionFeed]] = [:]
        var order: [String] = []

        func appendChildren(of parent: SessionFeed) {
            let kids = childrenByParent[parent.id] ?? []
            let named = kids.map { child -> SessionFeed in
                var c = child
                c.sessionName = childDisplayName(for: child, siblings: kids)
                return c
            }
            for child in sorted(named) {
                items.append(SessionRowItem(id: child.id, session: child, ids: [child.id], depth: 1))
            }
        }

        for s in sorted(roots) {
            let kids = childrenByParent[s.id] ?? []
            if !kids.isEmpty {
                items.append(SessionRowItem(
                    id: s.id, session: s,
                    ids: [s.id] + kids.map(\.id),
                    depth: 0, subagentCount: kids.count))
                appendChildren(of: s)
                continue
            }
            guard s.status == .idle else {
                items.append(SessionRowItem(id: s.id, session: s, ids: [s.id], depth: 0))
                continue
            }
            let key = (s.lastDuration != nil ? "done:" : "idle:") + s.cwd
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(s)
        }
        for key in order {
            let group = groups[key]!
            let rep = group.max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }!
            items.append(SessionRowItem(id: key, session: rep, ids: group.map(\.id), depth: 0))
        }

        let rootIds = Set(roots.map(\.id))
        let orphans = sessions.filter { child in
            guard let p = child.parentSessionId else { return false }
            return !rootIds.contains(p) && (child.isWorking || child.status == .attention)
        }
        for child in sorted(orphans) {
            var c = child
            let siblings = orphans.filter { $0.parentSessionId == child.parentSessionId }
            c.sessionName = childDisplayName(for: child, siblings: siblings)
            items.append(SessionRowItem(id: c.id, session: c, ids: [c.id], depth: 0))
        }
        return items
    }
```

**`performRescan`** — after `let live = recent.filter { !deadPidIds.contains($0.id) }` (currently line 813), filter orphans so they drop out of the published list and become eligible for the existing mtime file-delete walker. Do **not** PID-prune children specially (child pid == parent pid):

```swift
        let live = Self.excludingOrphanIdleChildren(
            recent.filter { !deadPidIds.contains($0.id) })
```

**`workingCount` / `attentionCount`** (currently lines 919–920) — `+N` in the menu-bar title counts roots only, so one parent with three Explores does not read as four sessions:

```swift
    var workingCount: Int { Self.rootWorkingCount(sessions) }
    var attentionCount: Int { sessions.filter { $0.parentSessionId == nil && $0.status == .attention }.count }

    static func rootWorkingCount(_ sessions: [SessionFeed]) -> Int {
        sessions.filter { $0.parentSessionId == nil && $0.isWorking }.count
    }
```

**`menuBarState(for:)`** (currently lines 951–959) — attention and working still scan **all** sessions (a background Explore keeps the glyph spinning after the parent `Stop`s). Done-flash scans **roots only**, so a child's 5s `done` does not hijack the title:

```swift
    static func menuBarState(for sessions: [SessionFeed], now: Date) -> MenuBarState {
        if sessions.contains(where: { $0.status == .attention }) { return .attention }
        if sessions.contains(where: { $0.isWorking }) { return .working }
        let cutoff = now.addingTimeInterval(-Constants.doneFlashDuration)
        if sessions.contains(where: {
            $0.parentSessionId == nil
                && $0.status == .idle && $0.lastDuration != nil
                && ($0.updated ?? .distantPast) > cutoff
        }) { return .doneFlash }
        return .idle
    }
```

**`justFinished`** (currently lines 938–943) — same root filter, used by the done-flash lead word:

```swift
        return sessions
            .filter {
                $0.parentSessionId == nil
                    && $0.status == .idle && $0.lastDuration != nil
                    && ($0.updated ?? .distantPast) > cutoff
            }
            .max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }
```

**`modelDisplay`** (currently lines 1268–1273) — extract a static so tests hit production code. Children skip the "any session / cache" fallback (that would show the parent's model and lie):

```swift
    static func modelDisplay(for session: SessionFeed, among sessions: [SessionFeed], cached: String?) -> String? {
        if session.isChild { return session.model }
        return session.model
            ?? sessions.filter { $0.model != nil && !$0.isChild }
                .max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }?.model
            ?? cached
    }

    func modelDisplay(for session: SessionFeed) -> String? {
        Self.modelDisplay(for: session, among: sessions, cached: cachedUsage?.model)
    }
```

- [ ] **Step 4: Run the tests and make sure they pass**

```bash
killall "claude spinner" 2>/dev/null
cd /Users/home/developer/claude-spinner
xcodebuild -scheme "claude spinner" test
```

Expected: `** TEST SUCCEEDED **`. Existing `testDisplayItemsSeparatesDoneFromNeverWorkedIdle` / `CollapsesDoneByDirectory` / `KeepsDistinctDirsSeparate` still pass (all-root fixtures, `depth` defaults to 0). Ignore SourceKit "cannot find type" editor diagnostics — they are known stale noise; only `xcodebuild test` counts.

- [ ] **Step 5: Commit (claude-spinner repo only)**

```bash
cd /Users/home/developer/claude-spinner
git add "claude spinner/FeedWatcher.swift" "claude spinnerTests/claude_spinnerTests.swift"
git commit -m "$(cat <<'EOF'
Nest subagent SessionFeeds under their parent row

Decode parent_session_id/agent_id/agent_type, group children in
displayItems (depth 1, never idle-collapsed), skip the model fallback
for children, and keep the menu-bar glyph spinning on child activity
without counting children in the +N suffix.
EOF
)"
```

Do not add the unrelated dirty files (`.github/workflows/swift.yml`, `run.sh`, `STATUS.md`, etc.).

---

### Task 3: Bundled emit.sh parity + SubagentStart/Stop installer

**Files:**
- Modify: `/Users/home/developer/claude-spinner/claude spinner/Scripts/emit.sh` (overwrite with the Task 1 live copy)
- Modify: `/Users/home/developer/claude-spinner/claude spinner/SetupInstaller.swift`
- Modify: `/Users/home/developer/claude-spinner/claude spinnerTests/claude_spinnerTests.swift`

**Interfaces:**
- Consumes: the Task 1 live `emit.sh` bytes.
- Produces: bundled copy byte-identical to live; `SetupInstaller.hookEvents` includes `SubagentStart` and `SubagentStop`. `testMergeAddsAllHookEventsToEmptySettings` already iterates `hookEvents`, so it covers the new events once the array grows. Fresh **Install hooks** is what actually registers those events in live `~/.claude/settings.json` (Task 4's hand-check).

- [ ] **Step 1: Write the failing tests**

Extend `testBundledEmitScriptCapturesTodoProgress` (currently lines 111–121) so the bundled copy must contain the child-file branch, not just todo capture. Keep the todo assertions. Add a dedicated hook-events test next to `testMergeAddsAllHookEventsToEmptySettings`.

Replace the bundled-script test body with:

```swift
    func testBundledEmitScriptCapturesTodoProgress() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let scriptURL = testFile
            .deletingLastPathComponent()               // claude spinnerTests/
            .deletingLastPathComponent()                // repo root
            .appendingPathComponent("claude spinner/Scripts/emit.sh")
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("todo_total"),
                      "bundled Scripts/emit.sh is missing todo-capture logic — sync it from ~/.claude/spinnerfeed/emit.sh")
        XCTAssertTrue(contents.contains("todo_done"))
        XCTAssertTrue(contents.contains("parent_session_id"),
                      "bundled Scripts/emit.sh is missing the subagent child-file branch — sync it from ~/.claude/spinnerfeed/emit.sh")
        XCTAssertTrue(contents.contains("SubagentStart"))
        XCTAssertTrue(contents.contains("agent_id"))
    }

    func testHookEventsIncludeSubagentLifecycle() {
        XCTAssertTrue(SetupInstaller.hookEvents.contains("SubagentStart"))
        XCTAssertTrue(SetupInstaller.hookEvents.contains("SubagentStop"))
    }
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
killall "claude spinner" 2>/dev/null
cd /Users/home/developer/claude-spinner
xcodebuild -scheme "claude spinner" test
```

Expected: `testBundledEmitScriptCapturesTodoProgress` fails on `parent_session_id` (bundled copy is still the todo-only script). `testHookEventsIncludeSubagentLifecycle` fails because `hookEvents` is `SessionStart, PreToolUse, PostToolUse, UserPromptSubmit, Notification, SessionEnd, Stop`.

- [ ] **Step 3: Copy the live script and add the two hook events**

```bash
cp /Users/home/.claude/spinnerfeed/emit.sh "/Users/home/developer/claude-spinner/claude spinner/Scripts/emit.sh"
```

Confirm they match:

```bash
diff -q /Users/home/.claude/spinnerfeed/emit.sh "/Users/home/developer/claude-spinner/claude spinner/Scripts/emit.sh"
```

Expected: no output (identical). If they differ, stop — Task 1's live copy is the source of truth; recopy.

In `claude spinner/SetupInstaller.swift` line 21–24, replace `hookEvents` with:

```swift
    static let hookEvents = [
        "SessionStart", "PreToolUse", "PostToolUse",
        "UserPromptSubmit", "Notification", "SessionEnd", "Stop",
        "SubagentStart", "SubagentStop",
    ]
```

`mergeSpinnerHooks` already appends any missing event; no merge-logic change. Existing installs pick up the two new events on the next **Install hooks** (idempotent). Live `~/.claude/settings.json` currently has `SubagentStop` for `cc-status` only; merge will add an `emit.sh SubagentStop` group beside it, not replace it.

- [ ] **Step 4: Run the tests and make sure they pass**

```bash
killall "claude spinner" 2>/dev/null
cd /Users/home/developer/claude-spinner
xcodebuild -scheme "claude spinner" test
```

Expected: `** TEST SUCCEEDED **`. `testMergeAddsAllHookEventsToEmptySettings` now also asserts an emit.sh command for `SubagentStart` and `SubagentStop`. `testMergeIsIdempotent` still requires exactly one emit.sh entry per event.

- [ ] **Step 5: Commit**

```bash
cd /Users/home/developer/claude-spinner
git add "claude spinner/Scripts/emit.sh" "claude spinner/SetupInstaller.swift" "claude spinnerTests/claude_spinnerTests.swift"
git commit -m "$(cat <<'EOF'
Sync bundled emit.sh and register SubagentStart/Stop

The live ~/.claude copy gained per-agent child files; the bundled
script SetupInstaller writes on a fresh install has to match, or the
feature is dead for anyone who isn't already on this machine. Hook
event list grows by SubagentStart/Stop so Install hooks actually
fires those events into emit.sh.
EOF
)"
```

---

### Task 4: Indent nested rows, skip parent/child dividers, scroll the list

**Files:**
- Modify: `/Users/home/developer/claude-spinner/claude spinner/FeedWatcher.swift` (add `Constants.childRowIndent` and `Constants.panelListMaxHeight` only)
- Modify: `/Users/home/developer/claude-spinner/claude spinner/MenuContentView.swift`
- Modify: `/Users/home/developer/claude-spinner/claude spinnerTests/claude_spinnerTests.swift`

**Interfaces:**
- Consumes: `SessionRowItem.depth` / `subagentCount`, `SessionFeed.isChild`, `FeedWatcher.modelDisplay(for:)` already returning nil for children (Task 2).
- Produces: a 16pt-indented 2-line child `SessionRow`; no Divider between a parent and its children; line-2 status budget always charges `childRowIndent`; session list wrapped in `ScrollView`; VoiceOver labels for parent child-count and each child.

- [ ] **Step 1: Write the failing layout tests**

Add `Constants.childRowIndent` references in the line-2 budget test. This will not compile until Step 3 adds the constant — intended red.

Replace `testLine2StatusNeverOverrunsItsBudget` (currently lines 385–394) with a version that charges the indent, and add a test that the indent is 16:

```swift
    func testChildRowIndentIsSixteen() {
        XCTAssertEqual(Constants.childRowIndent, 16)
    }

    /// Line 2's status must never exceed what that line actually has, once the
    /// todo bar, the gap, the working-dots slot, and the child indent (charged
    /// on every row so a depth-1 status cannot overflow) are accounted for.
    func testLine2StatusNeverOverrunsItsBudget() {
        let line2Budget = Constants.panelWidth - 2 * RowLayout.rowHorizontalPadding
            - RowLayout.secondRowLeadingInset - Constants.childRowIndent
            - TodoProgressBar.width
            - RowLayout.todoStatusGap - RowLayout.dotsSlot
        for label in ["done", "needs input", "running bash", "running TodoWrite",
                      "running " + String(repeating: "x", count: 200)] {
            let c = RowLayout.columns(statusLabels: [label], models: ["opus"], panelWidth: Constants.panelWidth)
            XCTAssertLessThanOrEqual(c.status, max(0, line2Budget) + 0.01, "\"\(label)\" overruns line 2")
        }
    }
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
killall "claude spinner" 2>/dev/null
cd /Users/home/developer/claude-spinner
xcodebuild -scheme "claude spinner" test
```

Expected: compile error `childRowIndent` not found on `Constants`, **or** (if someone added the constant without updating `columns`) `testLine2StatusNeverOverrunsItsBudget` fails because the production budget is 16pt larger than the test's new formula.

- [ ] **Step 3: Indent, omissions, Divider, ScrollView, accessibility**

In `claude spinner/FeedWatcher.swift` `Constants`, after `panelMinWidth` (currently line 48), add:

```swift
    /// Horizontal inset applied once per nesting depth (visual depth is 1).
    /// Also charged on every row's line-2 status budget so a child status
    /// cannot overflow; roots donate 16pt of unused status width.
    static let childRowIndent: CGFloat = 16
    /// Ceiling for the popover's session list. A 2-line row is ~40pt; this
    /// is about six rows, after which the list scrolls instead of growing
    /// the popover off the screen. The standalone window uses
    /// `maxHeight: .infinity` instead (the window itself is the viewport).
    static let panelListMaxHeight: CGFloat = 240
```

In `RowLayout.columns` (`MenuContentView.swift`, currently lines 549–555), charge the indent on line 2:

```swift
        let line2Width = panelWidth - 2 * rowHorizontalPadding - secondRowLeadingInset
            - Constants.childRowIndent
        let statusBudget = max(0, line2Width - TodoProgressBar.width - todoStatusGap - dotsSlot)
        status = min(status, statusBudget)
```

In `MenuContentView.body`, replace the inner session `VStack` (currently lines 82–93) with a ScrollView that skips Dividers before depth-1 rows:

```swift
                    let list = VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                            SessionRow(feed: feed, item: item, now: context.date, columns: columns)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            if index < rows.count - 1 && rows[index + 1].depth == 0 {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                    ScrollView(.vertical, showsIndicators: true) {
                        list
                    }
                    .frame(maxHeight: fillsWidth ? .infinity : Constants.panelListMaxHeight)
                    .animation(.easeInOut(duration: 0.2), value: rows.map(\.id))
```

Keep the existing `.padding(.top, 6)` on the `TimelineView`.

In `SessionRow.body`, indent the outer `VStack` and steal that width from the name column only. Right after `private var session: SessionFeed { item.session }`, add:

```swift
    private var indent: CGFloat { CGFloat(item.depth) * Constants.childRowIndent }
```

On the outer `VStack(alignment: .leading, spacing: 2) { ... }`, add `.padding(.leading, indent)` **before** the existing `.textCase(.lowercase)` (so the padding is inside the hit/hover target).

Change the name column's `fitName` / `.frame(width:)` (currently lines 588–604) so the indent comes out of the name, not the model/time/chip:

```swift
                    Text(RowLayout.fitName(item.count > 1 ? session.projectName : session.displayName,
                                           toWidth: columns.name - indent - RowLayout.countBadgeWidth(item.count)))
                        .font(.claudeMono(11))
                        .foregroundStyle(nameColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if item.count > 1 {
                        Text("×\(item.count)")
                            .font(.claudeMono(11))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .frame(width: max(0, columns.name - indent), alignment: .leading)
```

Hide the host-chip **tag** on children (emit.sh copies the parent's host, so showing `vsc`/`trm` would imply the child is a distinct host). Keep the hover `✕` so a child can be cleared alone. Replace the `else if let tag = session.hostTag` branch (currently around line 660) with:

```swift
                        } else if !session.isChild, let tag = session.hostTag {
```

`feed.modelDisplay(for: session)` already returns nil for children (Task 2), and children have no `status.json` so `contextTokens` is already `""` — those slots stay reserved and empty. Do not add a second hiding path for them.

Replace `accessibilityLabelText` (currently lines 877–884) with:

```swift
    private var accessibilityLabelText: String {
        if session.isChild {
            var text = "subagent \(session.displayName), \(statusLabel) \(timeText)"
            if session.todoTotal != nil {
                text += ", task progress \(session.todoProgress.done) of \(session.todoProgress.total)"
            }
            return text
        }
        var text = "\(session.displayName), \(statusLabel) \(timeText)"
        if !contextTokens.isEmpty { text += ", \(contextTokens) context tokens" }
        if session.todoTotal != nil {
            text += ", task progress \(session.todoProgress.done) of \(session.todoProgress.total)"
        }
        if item.subagentCount > 0 {
            text += ", \(item.subagentCount) subagents"
        }
        return text
    }
```

Do not use `item.ids.count > 1` for that suffix — collapsed idle groups also have `ids.count > 1`. `subagentCount` is 0 for those.

Working children keep `statusColor` / `tint` as `.claude` (existing `.thinking`/`.tool` branch). Do not introduce `Color.usageTint`.

- [ ] **Step 4: Run the tests and make sure they pass**

```bash
killall "claude spinner" 2>/dev/null
cd /Users/home/developer/claude-spinner
xcodebuild -scheme "claude spinner" test
```

Expected: `** TEST SUCCEEDED **`. `testLine2StatusNeverOverrunsItsBudget` and `testChildRowIndentIsSixteen` pass. Then rebuild and launch:

```bash
cd /Users/home/developer/claude-spinner
./run.sh
```

- [ ] **Step 5: Install hooks on this machine (required verification, not polish)**

The live `~/.claude/settings.json` currently fires `emit.sh` for SessionStart / PreToolUse / PostToolUse / UserPromptSubmit / Notification / SessionEnd / Stop, but **not** `SubagentStart` / `SubagentStop`. Child rows still appear on the first child tool call via the already-wired `PreToolUse` path (Task 1). Create/complete events (thinking-before-first-tool, and the done-flash on `SubagentStop`) need the new events registered.

In the running app: right-click the icon → the settings menu → **Install hooks** (or the Setup-needed panel button if hooks look missing). That merge is idempotent and will add `emit.sh SubagentStart` / `emit.sh SubagentStop` beside the existing `cc-status` `SubagentStop` group.

Hand-check against a session that actually launches subagents (three parallel Explores is the shape this machine uses):

1. Parent row stays on `running Agent` (or thinking) — it must **not** flicker to `running Grep` / whatever the child is doing.
2. Each subagent appears indented underneath, named `explore` (or `explore abcd` if two share a type), full 2-line row (empty todo bar at 0% until that child calls TodoWrite).
3. No Divider between parent and children; Dividers still separate top-level sessions.
4. Parent `Stop` with children still running: parent goes `done`, children keep spinning, menu-bar glyph stays working.
5. Click a child row focuses the **parent** editor (same host/pid/cwd).
6. Hover `✕` on a child clears only that child; `✕` on the parent clears parent + children.
7. A list taller than ~240pt in the popover scrolls; the standalone window (Open Window) still pins content to the top and scrolls inside the window.

If no live subagent is running, the fixture tests are the gate; the hand-check is still required before calling the plan done, because the last feature's silent failure was exactly "tests green, live wiring diverged".

- [ ] **Step 6: Commit**

```bash
cd /Users/home/developer/claude-spinner
git add "claude spinner/FeedWatcher.swift" "claude spinner/MenuContentView.swift" "claude spinnerTests/claude_spinnerTests.swift"
git commit -m "$(cat <<'EOF'
Indent nested subagent rows and scroll the session list

Depth-1 rows reuse SessionRow at 16pt, skip the host chip, and share
a ScrollView so a parent with many children cannot grow the popover
off screen. Line 2's status budget charges the indent on every row
so a child status cannot overflow.
EOF
)"
```

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|---|---|
| Per-subagent `state.json`, not an array in the parent | 1 |
| Filename `<parent>.<agent_id>.state.json` + JSON `parent_session_id`/`agent_id`/`agent_type` | 1, 2 |
| `agent_id` events never write the parent file | 1 (test 5) |
| `SubagentStart` create / `SubagentStop` idle / parent `SessionEnd` glob | 1 (tests 6, 8, 10) |
| Child `TodoWrite` updates child todos | 1 (test 7) |
| Top-level `--agent` (type, no id) stays a root | 1 (empty `agent_id` path) |
| Idle-collapse never swallows a child or a parent that has children | 2 |
| Orphan idle dropped, orphan working promoted | 2 |
| `modelDisplay` no fallback for children | 2 |
| Menu bar: glyph scans children, `+N` counts roots, done-flash roots only | 2 |
| Bundled emit.sh byte-identical + content-parity test | 3 |
| `SetupInstaller.hookEvents` += SubagentStart/Stop | 3 |
| Full 2-line child, 16pt indent, depth cap 1 | 4 |
| Omit model / ctx / host chip; keep time, tool, todo bar, click-to-focus | 2 (model) + 4 (chip) + 1 (host copied onto child file) |
| VoiceOver child label + parent `, N subagents` (not collapsed-group `ids.count`) | 4 |
| No Divider between parent and children | 4 |
| ScrollView + `panelListMaxHeight` | 4 |
| Line-2 budget charges indent | 4 |
| Re-run Install hooks | 4 Step 5 |
| No `Color.usageTint` for children | 4 (existing `.claude` branch) |
| No `subagentStatusLine` / transcript parse / compact 1-line variant | non-goals, not tasked |

Open spec items left as later display filters, not this plan: finished-child dwell (keep until parent end), `description` as a better name, `subagentStatusLine` for honest child model/tokens.
