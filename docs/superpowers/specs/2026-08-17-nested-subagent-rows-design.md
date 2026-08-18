# Nested subagent rows — design

## Context

Daniel asked for subagent sessions to appear as indented children under the
parent row, carrying the subagent's own live datapoints (status, tool,
progress bar, time, model, etc.) — not as sibling top-level rows, and not as
a collapsed `×N` count. Queued in `TASKS.md` as a sketch that hook payloads
already carry `agent_id`/`agent_type` and that `emit.sh` should write
per-subagent feed files tagged with the parent session.

Investigation (this session, 2026-08-17) confirms the TASKS.md *shape* and
corrects the implied identity model.

### What hooks actually send

Official hooks doc (`https://code.claude.com/docs/en/hooks`, fetched
2026-08-17, Claude Code v2.1.x):

- `session_id` on every event is the **parent** session. Subagents do not
  get their own session id. Common input fields add `agent_id` (present
  **only** when the hook fires inside a subagent) and `agent_type` (the
  agent name, e.g. `Explore`, `general-purpose`, `python-reviewer`).
- Dedicated events exist: `SubagentStart` (`agent_id`, `agent_type`) and
  `SubagentStop` (`agent_id`, `agent_type`, `agent_transcript_path`,
  `last_assistant_message`). `SubagentStop.transcript_path` is the parent
  transcript; `agent_transcript_path` is
  `~/.claude/projects/…/<parent>/subagents/agent-<id>.jsonl`.
- Settings-file hooks run inside subagents. When a subagent calls a tool,
  `PreToolUse`/`PostToolUse` fire the same configured hooks as the main
  thread, with `agent_id`/`agent_type` filled in. A `Stop` hook in
  subagent frontmatter is converted to `SubagentStop` at runtime.
- `agent_id` is **not** set for a top-level `claude --agent` session;
  those only get `agent_type`. Correlation must key on `agent_id`, not
  `agent_type`.

Live transcripts on this machine match the docs, not a sibling-session
model:

- Parent
  `~/.claude/projects/-Users-home-developer-headwaynurse-website/4c4a5566-8047-4e79-bec6-880766482873.jsonl`
  fires three parallel `Agent` tools in one assistant message
  (`subagent_type: Explore`, each with a `description`).
- Each child transcript lives at
  `<parent>/subagents/agent-<hex>.jsonl`. Every child line carries
  `isSidechain: true`, `agentId: <hex>`,
  `sessionId: 4c4a5566-8047-4e79-bec6-880766482873` (the **parent**),
  `attributionAgent: Explore`, and its own `message.model` (parent was
  `claude-fable-5`; children were `claude-opus-5`).
- Nested subagents exist. A music-session child
  `agent-a8ed94d68d050c287` (`spawnDepth: 1`) launched Explore; the
  grandchild's `*.meta.json` is
  `{"agentType":"Explore","parentAgentId":"a8ed94d68d050c287","spawnDepth":2,…}`.
  Grandchildren are still **siblings on disk** under the same
  `subagents/` folder. `parentAgentId` / `spawnDepth` live in that
  sidecar, **not** in hook stdin.

### What the feed does today

`emit.sh` keys only on `.session_id` and writes
`~/.claude/spinnerfeed/<session_id>.state.json`. Child
`PreToolUse`/`PostToolUse` events therefore **overwrite the parent file**
with the child's current tool — the parent row flickers to whatever the
loudest subagent is doing, and there is no child row. Confirmed: the
headway session above has one state file and one status file, both keyed
on the parent UUID; no child files exist.

`SubagentStart` is not in `SetupInstaller.hookEvents` and is not wired to
`emit.sh` in live `~/.claude/settings.json`. `SubagentStop` is registered
only for `cc-status`, not `emit.sh`. Child lifecycle events currently
never reach the feed except as the parent-file clobber above.

`statusLine` writes `<session_id>.status.json`. Subagents have no TUI
status line of their own; they share the parent's `session_id`, so even
if a statusLine tick ran in a subagent it would clobber the parent.
Claude Code has a separate `subagentStatusLine` setting (agent-panel
rows; stdin is a **batch** `tasks[]` with `id`, `type`, `status`,
`description`, `model`, `tokenCount`, `cwd`) — TUI-only, same limitation
as `statusLine`, and not installed here. Do not depend on it for v1.

PID: `emit.sh` walks up to the owning `claude` process. A subagent hook
is a subprocess of that same process (sidechain, not a second `claude`).
A child's captured pid is the **parent's** pid. PID pruning therefore
cannot detect a finished child — the process is still alive until the
parent dies. `FeedWatcher.performRescan` also only PID-prunes **idle**
sessions, so a parent killed mid-`running Agent` already stays until
`staleCutoff` (existing behaviour, unchanged).

As of Claude Code v2.1.198, subagents run in the **background by
default**. The parent can `Stop` (idle, `last_duration` set) while
children are still working. Any grouping that idle-collapses a parent
the moment it goes idle would hide or flatten live children.

This app tracks Claude Code sessions only (`STATUS.md` scope). Cursor
cloud/Task-tool subagents are out of scope.

## Decisions

- **Identity:** one feed file per subagent, same `state.json` schema as
  today, not an array of children inside the parent file. Parallel
  subagents would race on a single parent write (that is already the
  live bug). `FeedWatcher.performRescan` already maps one file → one
  `SessionFeed`. Parent `SessionEnd`'s existing `rm -f "$dir/$sid".*`
  glob then deletes children for free if they are named
  `$sid.<agent_id>.state.json`.
- **Correlation:** filename
  `~/.claude/spinnerfeed/<parent_session_id>.<agent_id>.state.json`,
  plus the same three fields persisted **inside** the JSON
  (`session_id` = parent, `parent_session_id` = parent, `agent_id`,
  `agent_type`). The app groups on the JSON field, not by parsing the
  filename — the filename is uniqueness + SessionEnd glob, not the
  schema. `agent_id` is the child key; `agent_type` is the display
  name. A top-level `--agent` session has `agent_type` but no
  `agent_id` and stays a root row.
- **Lifecycle:** any hook event whose stdin has a non-empty `agent_id`
  reads/writes the child file and never the parent file. `SubagentStart`
  creates the child (`status=thinking`, todos reset). Child
  `PreToolUse`/`PostToolUse`/`Notification` update it (upsert if
  `SubagentStart` was missed). `SubagentStop` marks idle and records
  `last_duration`, and does **not** delete the file. Parent `SessionEnd`
  glob removes parent + children. A child-flavoured `SessionEnd` (should
  not fire; guard anyway) deletes only the child file.
- **Idle-collapse:** children never enter the cwd buckets. A root with
  any live children is never collapsed, even if the root itself is idle
  (background-subagent case). Working/attention children stay individual
  under that root.
- **UI:** flat `[SessionRowItem]` with `depth: 0|1`. Children reuse
  `SessionRow` as a full 2-line row (todo bar + status), indented 16pt,
  uniform height with parents. No compact one-liner in v1 — the last
  feature made every row two lines for a reason (no per-row height
  jitter), and the user asked for the subagent's datapoints, which live
  on line 2. Visual depth is capped at 1: grandchildren flatten under
  the same parent (hook stdin has no `parent_agent_id`). No Divider
  between a parent and its children; Dividers only between depth-0
  items. Wrap the session list in a `ScrollView` — nested rows make
  overflow of `panelDefaultHeight` (320) likely, and the list currently
  does not scroll.
- **Datapoints:** children get status, tool, todo bar, elapsed/done
  time, click-to-focus (parent host/pid/cwd). They do **not** get model,
  context tokens, or a host chip — those come from `status.json` /
  `modelDisplay` fallback / host classification, none of which are
  honest for a child. Empty slots stay reserved so columns still align.
  Name is `agent_type`; if two siblings share a type, suffix the last 4
  of `agent_id`.
- **Bundled `emit.sh`:** the live copy and
  `claude spinner/Scripts/emit.sh` stay byte-identical. Last feature
  shipped dead on fresh installs because only the live copy was updated.
  `SetupInstaller.hookEvents` gains `SubagentStart` and `SubagentStop`.

**User-decision flag (recommended default above):** full 2-line child vs
compact 1-line child. Planning should proceed on 2-line. Revisit only if
a live panel with 6+ parallel children is too tall even with the new
scroll.

### Rejected alternatives

- **Array of children inside the parent `state.json`.** Parallel
  `PreToolUse` from three Explores would last-write-wins the whole
  parent document, including the parent's own status. The current
  atomic temp+mv pattern is per-file; it does not compose inside one
  JSON object without a lockfile, which this feed has never needed.
- **Child's own UUID `session_id` / sibling `.state.json` keyed like a
  root.** Contradicted by every hook example and every live child
  transcript: `session_id` is the parent. Inventing a new id would
  desync from `SessionEnd` (`$sid.*` would miss the child) and from
  `agent_transcript_path`.
- **Filename-only correlation without JSON fields.**
  `sessionId(from:)` already treats the whole prefix as an id, which is
  fine for uniqueness, but grouping, prune, and tests need an explicit
  `parent_session_id` on `SessionFeed`. Filename conventions rot; a
  field does not.
- **Drive children from `subagentStatusLine`.** That command is a TUI
  agent-panel painter, batched, tick-based, and absent on VS Code /
  Desktop Code-tab / SDK sessions — the same gap `HANDOFF.md` already
  records for `statusLine`. Hooks fire in all of those. v2 may *fill
  in* child model/tokens from it; v1 must not require it.
- **Read `*.meta.json` / transcripts for `description` / `spawnDepth`.**
  Third data source, async lag (hooks doc already warns transcripts
  lag), and a different schema. `description` is a nice name but is not
  on `SubagentStart` stdin. Capture it with `jq` **if present**; do not
  parse sidecar files.
- **Visual depth > 1.** Hook stdin has no parent-agent pointer.
  Reconstructing a tree from Agent-tool ordering races with the three-
  at-once pattern this machine actually uses. Flatten.
- **PID-prune finished children.** Child pid == parent pid. A finished
  child's process is still alive. `SubagentStop` is the complete signal.
- **Vanish children on `SubagentStop`.** The parent often continues;
  seeing `explore done 12s` under a still-working parent is the point.
  Files go away on parent `SessionEnd` or `staleCutoff`.
- **Reuse `Color.usageTint` for "subagent is working".** That gradient
  means urgency (high = bad). Children use the same `.claude` working
  tint as parents.

## Data flow

```
Claude Code
  ├─ parent PreToolUse Agent          → emit.sh PreToolUse
  │     stdin: session_id=P, no agent_id
  │     write: P.state.json  status=tool tool=Agent
  │
  ├─ SubagentStart                    → emit.sh SubagentStart
  │     stdin: session_id=P, agent_id=A, agent_type=Explore
  │     write: P.A.state.json  parent_session_id=P, status=thinking
  │
  ├─ child PreToolUse Grep            → emit.sh PreToolUse
  │     stdin: session_id=P, agent_id=A, tool_name=Grep
  │     write: P.A.state.json  status=tool tool=Grep
  │     (P.state.json untouched)
  │
  ├─ child PostToolUse TodoWrite      → emit.sh PostToolUse
  │     write: P.A.state.json  todo_total/todo_done from tool_input
  │
  ├─ SubagentStop                     → emit.sh SubagentStop
  │     write: P.A.state.json  status=idle last_duration=…
  │
  ├─ parent Stop                      → emit.sh Stop
  │     write: P.state.json    status=idle  (children kept)
  │
  └─ parent SessionEnd                → emit.sh SessionEnd
        rm -f "$dir/$P".*     # parent state/status + P.A.state.json

statusLine (parent TUI only)
  └─ write: P.status.json     # never a child file

FeedWatcher.performRescan
  └─ each *.state.json → SessionFeed (id = filename stem)
     applyState; applyStatus only when a matching .status.json exists
     PID-prune idle roots whose claude pid is dead
     prune child files whose parent is gone AND child is idle
     publish [SessionFeed]

FeedWatcher.displayItems
  └─ peel parent_session_id != nil into a map keyed by parent
     existing sort+idle-collapse on roots only
     roots with children never collapse
     emit depth-0 item, then each child as depth-1 item

MenuContentView
  └─ ForEach(displayItems) SessionRow(depth:)
     indent 16pt × depth; skip Divider when next.depth == 1
     ScrollView around the list
```

Hook event → file mapping in `emit.sh`:

| Event | `agent_id` empty | `agent_id` set |
|---|---|---|
| `SessionStart` | reset parent file | reset **child** file (defensive; not expected) |
| `UserPromptSubmit` | parent thinking | child thinking |
| `PreToolUse` / `PostToolUse` / `Notification` | parent | child |
| `Stop` | parent idle + last_duration | treat as `SubagentStop` |
| `SubagentStart` | ignore (no child id) | create/reset child, thinking |
| `SubagentStop` | ignore | child idle + last_duration |
| `SessionEnd` | `rm -f "$dir/$sid".*` | `rm -f` **only** `$dir/$sid.$agent_id.state.json` |

`TodoWrite` capture stays as it is, and runs against whichever file this
event is writing.

## Component design

### `StateFile` / `SessionFeed` (`FeedWatcher.swift`)

Add optional fields, all absent-means-nil (no `0` / `""` sentinels for
"not a child"):

```swift
// StateFile
var parent_session_id: String?
var agent_id: String?
var agent_type: String?

// SessionFeed
var parentSessionId: String?
var agentId: String?
var agentType: String?
var isChild: Bool { parentSessionId != nil }
```

`applyState` assigns them the same way as `lastSeed` — `nil` in JSON
stays `nil` on the struct. `displayName` for a child is `agentType`
(fallback `"subagent"`), with the last-4 `agentId` suffix when
`displayItems` detects a duplicate type under the same parent. Do not
fall back to `projectName` (that is the parent's folder and would make
three Explores indistinguishable from the parent and each other).

`modelDisplay(for:)` today falls back to "any session's model, then the
usage cache". A child with no `status.json` would **lie** and show the
parent's (or a sibling's) model. Skip the fallback when `session.isChild`
and return `session.model` only (nil in v1).

### `SessionRowItem`

```swift
struct SessionRowItem: Identifiable {
    let id: String
    let session: SessionFeed
    let ids: [String]
    var count: Int { ids.count }
    var depth: Int          // 0 root, 1 child
}
```

`ids` on a root includes the root plus every currently-attached child
id, so `clear(item)` on the parent removes child files too (today it
loops `item.ids` and deletes `\(id).state.json` / `.status.json`). A
child item's `ids` is `[child.id]` only. `count` / `×N` is still the
idle-collapse badge and stays 1 for any child and for any root that has
children (those roots are not collapsed).

### `displayItems(from:)` algorithm

Replace the current single-pass "working stay individual, idle collapse
by cwd" loop with:

1. Partition: `children` = sessions where `parentSessionId != nil`;
   `roots` = the rest.
2. Index children by `parentSessionId`. Drop a child whose parent is
   not in `roots` onto a synthetic-root path: if the child `isWorking`
   or `.attention`, emit it as depth 0 (orphan still live); if idle,
   skip (parent gone, child's job is over).
3. Run today's idle-collapse **only** over roots that have **no**
   children in the index. Roots with children always emit as an
   individual depth-0 item, whatever their own status.
4. After emitting a depth-0 item that has children, append those
   children as depth-1 items, sorted with the existing `sorted`
   comparator (attention, working, idle; then tokens — nil sorts as 0;
   then recency).
5. Return the flat list. `ForEach` is unchanged aside from `depth`.

Existing tests
(`testDisplayItemsSeparatesDoneFromNeverWorkedIdle` and siblings) stay
valid for all-root fixtures. New fixtures cover: working child under
idle parent; two Explores; child not collapsed with a never-worked idle
in the same cwd; orphan idle child dropped; orphan working child
promoted.

### `SessionRow` (`MenuContentView.swift`)

Add `var depth: Int { item.depth }`. Outer `VStack` gets
`.padding(.leading, CGFloat(depth) * Constants.childRowIndent)` with
`childRowIndent = 16`. Line 1 already budgets against `panelWidth`;
indent steals from the **name** column only — pass
`columns.name - CGFloat(depth) * indent` into `fitName`, keep model /
ctx / time / chip frames so child times still line up under parent
times.

Child-specific omissions (honest empty, not a lie):

| Column | Child |
|---|---|
| glyph | same spinner / star as parent |
| name | `agent_type` (+ suffix if duplicate) |
| model | empty `Text("")` in the existing frame |
| ctx tokens | empty in the 30pt frame |
| time | same elapsed / done / attention rules |
| host chip | hide the tag; keep the hover `✕` so a child can be cleared alone |
| line 2 bar | same `TodoProgressBar` via `todoProgress` (reserved 0%) |
| line 2 status | child's tool / thinking / done |
| tap | `SessionLauncher.focus` with the child's host/pid/cwd (copied from the parent by `emit.sh`) |
| VoiceOver | own `.accessibilityElement(children: .ignore)` label: `"subagent \(displayName), \(statusLabel) \(timeText)"` plus todo if present. Parent label gains `", \(n) subagents"` when `item.ids.count > 1` and `depth == 0` |

Do not reuse `Color.usageTint`. Working children use `.claude`.

### Menu bar

`menuBarState(for:)` keeps scanning **all** sessions, including
children, so a background Explore keeps the glyph spinning after the
parent `Stop`s. `workingCount` / `attentionCount` used for the `+N`
suffix should count **roots only**, or one parent with three children
reads as four sessions. `justFinished` / done-flash lead word: roots
only, so a child's 5s done-flash does not hijack the title.

### Prune / clear / SessionEnd

- `performRescan` live set is still "has `updated` within
  `staleCutoff`". Add: drop an idle child whose `parentSessionId` is
  not in that live set; delete its file under the same mtime grace as
  other prunes. Do not PID-prune children (pid is the parent's).
- `clear(item)` already deletes by `item.ids`. With ids including
  children, clearing a parent cleans them. Also delete
  `"\(id).status.json"` for children (will not exist; harmless).
- `sessionId(from:)` already returns the full stem
  (`<uuid>.<agent_id>`), so `clearAll` and the stale-file walker keep
  working. Do not special-case dotted names.
- `emit.sh` `SessionEnd` glob `$dir/$sid.*` already matches
  `$sid.<agent>.state.json`. Leave that glob. The new `agent_id` branch
  must not reach it.

### Panel height

`Constants.panelDefaultHeight = 320`. A 2-line row is ~36–40pt
(`.padding(.vertical, 7)` × 2 + two line-heights + 2pt VStack
spacing). One parent + three children ≈ 160pt of rows plus header and
footer — fits 320. One parent + eight children does not. The popover
currently sizes to content with no `ScrollView`; the standalone window
clamps a remembered frame to 320 and would clip.

Wrap the session `VStack` in `ScrollView(.vertical)` with a max height
derived from the status-item screen's `visibleFrame` (popover) and
`frame(maxHeight: .infinity)` inside the window (`fillsWidth`). Do not
raise `panelDefaultHeight` as a substitute for scrolling.

### `RowLayout.columns`

Still sized once per panel from the displayed rows' status labels and
models. Pass **all** items, including children: a child `running
mcp__…` should still widen the status column so parent and child status
align. Child model strings are empty and do not widen the model column.
Line 2's `secondRowLeadingInset` (20) plus child indent (16) is 36pt —
update the line-2 budget for depth-1 rows, or (simpler) always budget
line 2 against `panelWidth - 2*rowHorizontalPadding -
secondRowLeadingInset - childRowIndent` so a child status cannot
overflow. Uniform budget is worth 16pt of unused status width on
roots.

## emit.sh changes

Live: `~/.claude/spinnerfeed/emit.sh`. Bundled:
`claude spinner/Scripts/emit.sh`. Identical bytes.

After reading `sid` / `tool` / `msg`, also:

```sh
agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty')
agent_type=$(printf '%s' "$input" | jq -r '.agent_type // empty')
# optional, persist if the hook ever sends it; empty is fine
agent_desc=$(printf '%s' "$input" | jq -r '.description // .tool_input.description // empty')
```

Sanitize `agent_id` to `[A-Za-z0-9_-]` (hook values observed:
`a639953774a9953ac` and docs example `agent-abc123`). If `agent_id` is
non-empty after sanitize:

```sh
parent_sid="$sid"
f="$dir/$sid.$agent_id.state.json"
```

else `parent_sid=""` and `f="$dir/$sid.state.json"` as today.

Carry-forward block gains `prev` reads for the new fields from `$f`
(same `jq -r '.field // empty'` pattern as `prev_todo_total`). On
`SubagentStart` / child `SessionStart`, reset todos and turn like
today's `SessionStart`, and set `agent_type` from this event.

`case` gains:

```
SubagentStart)  status=thinking; turn_start="$now"; last_seed=""; last_duration=""; todo_total=""; todo_done="" ;;
SubagentStop)   # same body as Stop
```

`SessionEnd` arm:

```
SessionEnd)
    if [ -n "$agent_id" ]; then
        rm -f "$dir/$sid.$agent_id".state.json
    else
        rm -f "$dir/$sid".*
    fi
    exit 0 ;;
```

Final `jq -n` object gains:

```
parent_session_id: (if $psid == "" then null else $psid end),
agent_id:          (if $aid == "" then null else $aid end),
agent_type:        (if $atype == "" then null else $atype end),
```

`session_id` in the JSON stays the **parent** UUID in both files (the
hook's `session_id`). The child's identity on disk is the filename
stem; the child's identity in Swift is that stem plus
`parentSessionId`.

Pid / host / cwd carry onto the child file from the same walk / env /
stdin as today. That is how click-to-focus on a child reaches the
parent editor without a second process.

## File-by-file change list

### App repo (`~/developer/claude-spinner`)

- **`claude spinner/Scripts/emit.sh`** — byte-identical to the live
  copy after the changes above. Never edit one without the other.
- **`claude spinner/SetupInstaller.swift`** —
  `hookEvents` becomes
  `SessionStart, PreToolUse, PostToolUse, UserPromptSubmit,
  Notification, SessionEnd, Stop, SubagentStart, SubagentStop`.
  `mergeSpinnerHooks` already appends any missing event; no merge-logic
  change. Existing installs pick up the two new events on the next
  **Install hooks** (idempotent). Live `~/.claude/settings.json` on this
  machine currently has `SubagentStop` for `cc-status` only; merge will
  add an `emit.sh SubagentStop` group beside it, not replace it.
- **`claude spinner/FeedWatcher.swift`** — `StateFile` / `SessionFeed`
  fields; `applyState`; `SessionRowItem.depth`; `displayItems`;
  `modelDisplay` child guard; `workingCount`/`attentionCount` root
  filter; child prune in `performRescan`; `Constants.childRowIndent`.
  `applyStateJSONForTest` already decodes via `StateFile` — new fields
  come for free once `StateFile` has them.
- **`claude spinner/MenuContentView.swift`** — `SessionRow` indent,
  child omissions, parent accessibility child-count, Divider skip,
  `ScrollView` around the session list, line-2 budget includes indent.
- **`claude spinnerTests/claude_spinnerTests.swift`** — extend `mk`
  with `parentSessionId` / `agentType`; grouping tests as listed below;
  `applyStateJSONForTest` nil-vs-present for the new fields; bundled
  emit.sh substring checks for `parent_session_id`, `SubagentStart`,
  `agent_id` (keep the todo checks). `testMergeAddsAllHookEvents…`
  already iterates `hookEvents`, so SubagentStart/Stop coverage is
  automatic once the array grows.
- **Do not** change `statusline-command.sh` in v1. It keys on
  `session_id` and would clobber the parent if pointed at a subagent.

### Live hooks repo (`~/.claude`)

- **`spinnerfeed/emit.sh`** — same bytes as the bundled copy.
- **`spinnerfeed/test.sh`** — extend the existing fixture harness
  (do not replace the todo cases):
  - `PreToolUse` with `agent_id` writes
    `$sid.$agent_id.state.json`, leaves `$sid.state.json` untouched.
  - `SubagentStart` creates the child with `parent_session_id`,
    `agent_type`, `todo_*` null.
  - Child `PostToolUse TodoWrite` updates the **child** todos, not the
    parent.
  - `SubagentStop` sets child `status=idle` and a numeric
    `last_duration`; parent file still present.
  - Parent `SessionEnd` removes parent state/status **and** the child
    file (`$sid.*` glob).
  - Child-flavoured `SessionEnd` (stdin has `agent_id`) removes only
    the child file.
  - `PreToolUse` **without** `agent_id` still writes the parent file
    (regression for today's roots).
- **`settings.json`** — not edited by the app except via
  `SetupInstaller`. After shipping, this machine needs **Install hooks**
  (or a hand-added `emit.sh SubagentStart` / `SubagentStop` group) for
  the create/complete events. Child rows still appear from
  `PreToolUse`/`PostToolUse` alone once `emit.sh` branches on
  `agent_id`, which those events already invoke.

### Not touched

`TASKS.md`, `STATUS.md`, `HANDOFF.md` (planning/SDD pass updates
those). No new Swift file — sources are a synchronized group, but this
fits in `FeedWatcher.swift` / `MenuContentView.swift`. Cursor Task-tool
sessions: out of scope.

## Build sequence

Ordered for a later SDD plan. Tests first in each slice (the previous
feature's `applyStateJSONForTest` / `spinnerfeed/test.sh` seams).

1. **emit.sh child files + fixture tests** (`~/.claude` repo). Can
   start immediately. Red: test.sh cases above against current emit.sh
   (they fail). Green: agent_id branch, SubagentStart/Stop arms,
   SessionEnd guard. Commit in `~/.claude`.
2. **Bundled emit.sh parity** (app repo). Copy the live script over
   `claude spinner/Scripts/emit.sh`. Extend
   `testBundledEmitScriptCapturesTodoProgress` (rename or add) so the
   bundled copy must contain `parent_session_id`, `SubagentStart`, and
   `agent_id`. Can run in parallel with (3) once the live script is
   stable, but **must** land in the same app commit as any Swift that
   expects the new fields, or a fresh Install hooks would write a
   script the app does not yet understand (harmless) / the reverse
   (app understands fields the script never writes — silent empty
   children). Prefer one app commit that includes bundled script +
   Swift + tests.
3. **SetupInstaller.hookEvents** (app repo, same commit as 2). Two
   strings. Existing merge tests cover them.
4. **Feed model + `displayItems`** (app repo). `StateFile` /
   `SessionFeed` / `SessionRowItem.depth` / grouping / prune /
   `modelDisplay` guard / menu-bar root counts. XCTest only; no UI yet.
   Depends on (2) only for the bundled-script test, not for Swift.
   **Can be parallel with (1)** using hand-written JSON fixtures via
   `applyStateJSONForTest` and `mk(...)`.
5. **SessionRow + ScrollView** (app repo). Indent, omissions,
   accessibility, Divider skip, line-2 indent budget. Depends on (4).
   Hand-check: three parallel Explores under one working parent; parent
   Stop with children still running; click child focuses the parent
   host; VoiceOver reads parent and each child.
6. **Install hooks on this machine** so live `settings.json` gains
   `SubagentStart`/`SubagentStop` emit.sh entries. After (1)+(2). Until
   then, children still appear on first child tool call via the already-
   wired PreToolUse path.

(1) is the only `~/.claude` commit. (2–5) are the app repo. (4) can
overlap (1). (5) waits on (4). (6) is a local settings merge, not a
code task, but it is required for the thinking-before-first-tool child
row and for `SubagentStop` done-flash.

## Testing

Production seams, not mirrors: `applyStateJSONForTest` for decode;
`FeedWatcher.displayItems(from:)` / `menuBarState(for:)` for grouping
and the glyph; real `emit.sh` via `spinnerfeed/test.sh`.

Swift cases to add (names indicative):

- `testApplyStateDecodesParentAndAgentFields` — JSON with
  `parent_session_id` / `agent_id` / `agent_type` maps through
  `applyStateJSONForTest`; missing keys stay `nil`.
- `testDisplayItemsNestsWorkingChildUnderIdleParent` — background-
  subagent case; parent not in an idle `×N` bucket.
- `testDisplayItemsDoesNotCollapseChildWithSameCwdIdle` — never-worked
  idle root in the same cwd as a child's cwd does not absorb the child.
- `testDisplayItemsFlattensTwoExploresUnderOneParent` — order is parent
  then both children; both `depth == 1`.
- `testDisplayItemsDropsIdleOrphanChild` /
  `testDisplayItemsPromotesWorkingOrphanChild`.
- `testMenuBarStaysWorkingWhenOnlyChildrenWork` — parent idle, child
  `.tool` → `.working`; `workingCount` remains 0 if we count roots only
  (assert whichever rule is implemented).
- `testModelDisplaySkipsFallbackForChild`.
- Bundled emit.sh contains `parent_session_id` and `SubagentStart`.
- `testMergeAddsAllHookEventsToEmptySettings` — already loops
  `hookEvents`; will fail until SubagentStart/Stop are in the array
  **and** the expected command list matches. No new merge test needed
  beyond the array change.

`killall "claude spinner"` before `xcodebuild test` (app-hosted suite).

Do not test `TodoProgressBar` math again except where a child row would
skip the bar (it must not). Do not add a UI-test target.

## Non-goals

- Cursor cloud / Cursor Task-tool subagents.
- A new feed format, lockfile, or SQLite store.
- Wiring `subagentStatusLine` or giving children a `.status.json`
  (v2 candidate for model + tokenCount).
- Parsing transcripts or `*.meta.json` for `description` / `spawnDepth`
  / `parentAgentId`.
- Visual nesting deeper than one level.
- A compact one-line child variant (flagged above; not v1).
- Changing idle-collapse of **root** sessions that have no children.
- Changing PID pruning of roots.
- Per-child usage gauges, cost, or rate-limit chips (account-wide, not
  per subagent).
- Focusing a subagent's "session" as a distinct editor — there isn't
  one; click focuses the parent host.
- Auto-merging `~/.claude/settings.json` outside SetupInstaller.
  Shipping emit.sh is not the same as registering SubagentStart/Stop;
  Install hooks is the path.

## Risks / open items

Keep this list short; the rest is decided from evidence.

1. **2-line vs compact child (user).** Recommended: 2-line, with
   `ScrollView`. Revisit if a live 6+ child panel is too tall.
2. **Finished-child dwell.** Spec keeps child files until parent
   `SessionEnd` / 12h cutoff, so a done parent can still show three grey
   `explore done 12s` rows. If that is noisy in practice, a later pass
   can hide idle children once the parent is idle and outside the
   done-flash window — a display-items filter, not a new emit.sh
   behaviour.
3. **`description` as a better name.** Not on `SubagentStart` stdin
   today. emit.sh will persist `.description` if it ever appears; the
   row prefers `agent_type` until then. Do not block on this.
4. **This machine's settings.json** will not fire `SubagentStart` /
   `SubagentStop` into emit.sh until Install hooks (or a hand edit).
   PreToolUse already will. Planning should treat "re-run Install
   hooks" as a documented verification step, not optional polish — the
   last feature's silent-failure was exactly "bundled script / live
   wiring diverged".
5. **`subagentStatusLine` as v2.** Honest child model + tokenCount,
   TUI-only. Do not sneak it into v1; it is a second writer and a
   second installer surface (`SetupInstaller` does not know that key).
