# Swift 6 Isolation Warnings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Outcome, 2026-10-02: executed the same day, and not as written.** Read this
> before the tasks below; they are kept as the record of what was planned.
>
> - The baseline was wrong. CI builds incrementally and its log listed 117
>   warnings; a clean local build listed 152. The 36 it had missed were in
>   `AskInbox.swift`, `GitProbe.swift`, `GitAutomation.swift` and `NewSession.swift`.
>   Count warnings from a clean build, never from a CI log.
> - Task 1 went as written: 152 to 79, the test file from 75 to 2 (`d83d19a`).
> - Tasks 2 to 4 did not. Marking individual functions `nonisolated` moved each
>   warning one call inward (79 became 81). The unit that is wrong about its
>   isolation is the type, so whole namespaces and value types were marked
>   instead, and the count fell to 23, then to 0 with the remaining members
>   handled one by one (`b44955a`).
> - Task 5's four one-offs went as written. The `Text` change was not seen in
>   the app (no session was showing a pick); the old and new forms were rendered
>   offline and are pixel-identical, with a control that differs.
> - A clean build now prints 0 warnings. 401 tests pass.

**Goal:** Take the build from 117 compiler warnings to 0 without changing what the app does.

**Architecture:** The app target compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every declaration is main-actor-isolated unless it says otherwise. The warnings are the places that default is wrong: pure helpers and value types that are used off the main actor (in `Task.detached`, as function values, from the test target). The fix is to say so at the declaration with `nonisolated`, not to change any call site's behaviour. The test target is missing the same default, which alone accounts for 73 of the 117.

**Tech Stack:** Swift 5 language mode on the Swift 6.2 toolchain (Xcode 27), SwiftUI, XCTest. `SWIFT_APPROACHABLE_CONCURRENCY = YES` is already on for every target.

**Spec:** There is no separate spec. The requirement is the compiler's own list: the warnings in CI run `37051872323` at commit `d6ae43d`, inventoried below by kind. The plan argues from that list.

## Global Constraints

- No behaviour change. Every edit is an isolation annotation, a build setting, or a syntactic equivalent. If a step would change what runs on which thread, stop and report instead.
- `MACOSX_DEPLOYMENT_TARGET = 27.0` and `SWIFT_VERSION = 5.0` stay as they are. This plan does not turn on the Swift 6 language mode.
- Never hand-list sources or edit `project.pbxproj` beyond the one setting in Task 1 (sources are a synchronized group).
- Before any local `xcodebuild ... test`: `gh run list --limit 1` must not be `in_progress`, then `killall "claude spinner"` (project `CLAUDE.md`, Test section). The count command below only builds and needs neither.
- Commits: imperative subject, reasoning in the body, new commits only, explicit pathspec (`git commit -- <paths>`), ending with `Co-Authored-By: Claude <noreply@anthropic.com>`.
- If `nonisolated` on a declaration makes the compiler report that its body touches something main-actor-isolated, apply the fallback named in that task. Do not add `@MainActor`, `MainActor.assumeIsolated`, or `@unchecked Sendable` to make an error go away.

**The count command** (used by every task; a clean build, because an incremental one only reports files it recompiled):

```bash
xcodebuild -scheme "claude spinner" clean build-for-testing 2>&1 \
  | grep -E '^/.*: warning: ' | sed -E 's|^.*/claude-spinner/||' | sort -u > /tmp/spinner-warnings.txt
wc -l < /tmp/spinner-warnings.txt
```

Baseline at `d6ae43d`: 116 compile-time lines (the 117th in the CI log is a runtime QoS note from `testRunHonoursItsTimeoutInBothDirections`, which this command does not see and this plan does not touch). Confirm the baseline before Task 1; if it is not 116, the tree has moved and the line numbers below need re-reading.

## Inventory

| Kind | Count | Where | Task |
|------|-------|-------|------|
| Isolated conformance or call used from the nonisolated test target | 73 | `claude spinnerTests/claude_spinnerTests.swift` | 1 |
| Isolated conformance used off the main actor in the app | 5 | `PinnedProjectDetail` 594, `SessionReplier` 183 and 196, `WindowContentView` 1078, `GitProbe` 212 | 2 |
| Isolated static function passed as a function value | 14 | `FeedWatcher`, `HomeDashboard`, `MenuContentView`, `PinnedProjectDetail`, `StatCards`, `WindowContentView` | 3 |
| Isolated static called from `Task.detached`, a `nonisolated` function or an actor | 20 | `GoalClock`, `GraphifyCard`, `PinnedProjectDetail`, `PinnedProjects`, `WindowContentView` | 4 |
| One-offs: a completion handler, a deprecated `Text +`, two needless `try` | 4 | `claude_spinnerApp` 83, `WindowContentView` 1821, tests 2211 and 2728 | 5 |

## File Structure

No files are created. Files modified, and why each:

- `claude spinner.xcodeproj/project.pbxproj`: the test target gains the app target's isolation default (Task 1).
- `PinnedProjectDetail.swift`, `SessionReplier.swift`, `WindowContentView.swift`, `GitProbe.swift`: value types marked `nonisolated` (Task 2).
- `FeedWatcher.swift`, `MenuContentView.swift`, `claude_spinnerApp.swift`, `Suggestion.swift`, `GitAutomation.swift`, `WindowContentView.swift`, `PinnedProjectDetail.swift`: pure helpers marked `nonisolated` (Task 3).
- `GoalClock.swift`, `GraphifyCard.swift`, `NewSession.swift`, `TranscriptReader.swift`, `SessionReplier.swift`, `GitActions.swift`, `Suggestion.swift`, `WindowContentView.swift`: helpers that already run off the main actor marked as such (Task 4).
- `claude_spinnerApp.swift`, `WindowContentView.swift`, `claude spinnerTests/claude_spinnerTests.swift`: the one-offs (Task 5).
- `STATUS.md`, `TASKS.md`: the record (Task 5).

---

### Task 1: Give the test target the app's isolation default

**Files:**
- Modify: `claude spinner.xcodeproj/project.pbxproj` (the two `XCBuildConfiguration` blocks whose `PRODUCT_BUNDLE_IDENTIFIER` is `"decenad.claude-spinnerTests"`)

**Interfaces:**
- Consumes: nothing.
- Produces: a test target whose `XCTestCase` subclasses are main-actor-isolated, so later tasks do not need to touch test call sites.

- [ ] **Step 1: Record the baseline**

Run the count command. Expected: `116`. Keep a copy: `cp /tmp/spinner-warnings.txt /tmp/spinner-warnings-before.txt`.

- [ ] **Step 2: Add the setting to both test configurations**

In each of the two blocks that contain `PRODUCT_BUNDLE_IDENTIFIER = "decenad.claude-spinnerTests";` (Debug and Release; do not touch the `claude-spinnerUITests` blocks), change:

```
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_EMIT_LOC_STRINGS = NO;
```

to:

```
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
				SWIFT_EMIT_LOC_STRINGS = NO;
```

Check it landed twice and only there: `grep -c 'SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor' "claude spinner.xcodeproj/project.pbxproj"` must print `4` (two app, two tests).

- [ ] **Step 3: Count again**

Run the count command. Expected: the lines beginning `claude spinnerTests/` fall from 75 to 2 (the two `try` lines at 2211 and 2728, which Task 5 owns), total `43`. Verify with `grep -c '^claude spinnerTests' /tmp/spinner-warnings.txt`.

If instead the build fails with errors in the test file of the form "call to main actor-isolated ... in a synchronous nonisolated context" on a `static` test helper or a closure passed to `DispatchQueue.global()`, that helper genuinely runs off the main actor: mark that one declaration `nonisolated` and rebuild. Report each one you had to mark.

- [ ] **Step 4: Run the suite**

```bash
gh run list --limit 1          # must not be in_progress
killall "claude spinner" 2>/dev/null
set -o pipefail
xcodebuild -scheme "claude spinner" test | { command -v xcbeautify >/dev/null && xcbeautify || cat; }
```

Expected: `Executed 401 tests, with 0 failures`. A test that now deadlocks or times out is one that blocked the main thread waiting on main-actor work; report it by name rather than marking the test class `nonisolated`.

- [ ] **Step 5: Commit**

```bash
git commit -m "Give the test target the app's main-actor default

The app target isolates everything to the main actor by default and the
test target did not, so every app value type compared in a test was an
isolated conformance used from a nonisolated context: 73 of the build's 116
warnings.

Co-Authored-By: Claude <noreply@anthropic.com>" -- "claude spinner.xcodeproj/project.pbxproj"
```

### Task 2: Mark the value types that leave the main actor

**Files:**
- Modify: `claude spinner/PinnedProjectDetail.swift:571`
- Modify: `claude spinner/SessionReplier.swift:54`
- Modify: `claude spinner/WindowContentView.swift:1090`
- Modify: `claude spinner/GitProbe.swift:210`

**Interfaces:**
- Consumes: nothing.
- Produces: `PinnedProjectDetail.JobStats`, `SessionReplier.Landing`, `TileSpan` and `GitProbe.RemoteRead` usable from any isolation. Names and members unchanged.

Each of these is a plain value (or, for `RemoteRead`, a box already documented as guarded by a dispatch group) that is decoded, compared or constructed inside a detached task or a `Layout` callback.

- [ ] **Step 1: Apply the four edits**

`PinnedProjectDetail.swift`:
```swift
    struct JobStats: Codable, Equatable {
```
becomes
```swift
    nonisolated struct JobStats: Codable, Equatable {
```

`SessionReplier.swift`:
```swift
    enum Landing: Equatable {
```
becomes
```swift
    nonisolated enum Landing: Equatable {
```

`WindowContentView.swift`:
```swift
struct TileSpan: LayoutValueKey {
```
becomes
```swift
nonisolated struct TileSpan: LayoutValueKey {
```

`GitProbe.swift`:
```swift
    private final class RemoteRead: @unchecked Sendable {
```
becomes
```swift
    nonisolated private final class RemoteRead: @unchecked Sendable {
```

- [ ] **Step 2: Count**

Run the count command. Expected: 5 fewer than after Task 1 (38 left), and none of these remain:

```bash
grep -E "JobStats|Landing|TileSpan|GitProbe.swift:212" /tmp/spinner-warnings.txt   # prints nothing
```

Fallback if a member of one of these types now errors as touching main-actor state: that member is the problem, not the type. Report it and leave that one type as it was.

- [ ] **Step 3: Run the suite** (same command and precautions as Task 1 Step 4). Expected: 401 tests, 0 failures.

- [ ] **Step 4: Commit**

```bash
git commit -m "Mark the value types that are used off the main actor

JobStats is decoded in a detached task, Landing is compared on the reply
queue, TileSpan is read inside Layout callbacks and RemoteRead is built on
the probe's queue. None holds main-actor state; the default isolation said
they did.

Co-Authored-By: Claude <noreply@anthropic.com>" -- "claude spinner/PinnedProjectDetail.swift" "claude spinner/SessionReplier.swift" "claude spinner/WindowContentView.swift" "claude spinner/GitProbe.swift"
```

### Task 3: Mark the pure helpers that are passed as function values

**Files:**
- Modify: `claude spinner/FeedWatcher.swift:232, 1399, 2037, 2256`
- Modify: `claude spinner/MenuContentView.swift:587`
- Modify: `claude spinner/claude_spinnerApp.swift` (`static func usageTint`, in `extension Color`)
- Modify: `claude spinner/Suggestion.swift:48, 151`
- Modify: `claude spinner/GitAutomation.swift:39`
- Modify: `claude spinner/WindowContentView.swift:1175, 2260`
- Modify: `claude spinner/PinnedProjectDetail.swift:322`

**Interfaces:**
- Consumes: nothing.
- Produces: the same twelve functions, same signatures, callable from any isolation.

A function written as `xs.map(Self.f)` is handed to `map` as a plain function value, which cannot carry main-actor isolation. Each of these takes values and returns a value.

- [ ] **Step 1: Add `nonisolated` to each declaration**

Insert the word `nonisolated` before `static` (after `private` where present) on exactly these lines. The text after it is unchanged.

| File | Declaration as it is now |
|------|--------------------------|
| `FeedWatcher.swift:232` | `static func pastWord(for session: SessionFeed) -> String {` |
| `FeedWatcher.swift:1399` | `private static func pidAlive(_ pid: Int) -> Bool {` |
| `FeedWatcher.swift:2037` | `static func formatTokens(_ count: Int) -> String {` |
| `FeedWatcher.swift:2256` | `static func modelFamily(_ raw: String) -> String {` |
| `MenuContentView.swift:587` | `static func width(for text: String) -> CGFloat {` |
| `claude_spinnerApp.swift` | `static func usageTint(_ pct: Int) -> Color {` |
| `Suggestion.swift:48` | `static func skill(_ input: Input) -> Suggestion? {` |
| `Suggestion.swift:151` | `static func next(_ input: Input) -> Suggestion? {` |
| `GitAutomation.swift:39` | `static func autoCommitEnabled(settings text: String) -> Bool {` |
| `WindowContentView.swift:1175` | `static func duration(_ seconds: Double) -> String {` |
| `WindowContentView.swift:2260` | `private static func span(_ line: GraphLine) -> Int {` |
| `PinnedProjectDetail.swift:322` | `private static func name(_ path: String) -> String { (path as NSString).lastPathComponent }` |

For example, `FeedWatcher.swift:1399` becomes:

```swift
    private nonisolated static func pidAlive(_ pid: Int) -> Bool {
```

- [ ] **Step 2: Build and apply the fallback where the compiler objects**

Run the count command. Three of these are likely to object, because their bodies read other isolated declarations (`usageTint` returns the `usageRed`/`usageAmber`/`usageYellow`/`usageGreen` statics; `Suggestion.skill` and `Suggestion.next` read `Suggestion`'s own helpers; `width(for:)` reads `RowLayout`'s font constants).

For any function where the build now reports "main actor-isolated ... can not be referenced from a nonisolated context": remove the `nonisolated` you added to that one function and change its call sites from a function value to a closure, which inherits the caller's isolation. The call sites are:

```swift
// StatCards.swift:322
tint: pct.map(Color.usageTint) ?? .label,
// becomes
tint: pct.map { Color.usageTint($0) } ?? .label,

// WindowContentView.swift:57-58
private var suggestion: Suggestion? { suggestionInput.flatMap(Suggestion.next) }
private var skillPick: Suggestion? { suggestionInput.flatMap(Suggestion.skill) }
// become
private var suggestion: Suggestion? { suggestionInput.flatMap { Suggestion.next($0) } }
private var skillPick: Suggestion? { suggestionInput.flatMap { Suggestion.skill($0) } }

// MenuContentView.swift:655-656
var model = models.map(width(for:)).max() ?? 0
var status = statusLabels.map(width(for:)).max() ?? 0
// become
var model = models.map { width(for: $0) }.max() ?? 0
var status = statusLabels.map { width(for: $0) }.max() ?? 0
```

The same closure form is the fallback for any of the other nine, at the sites the Inventory names.

- [ ] **Step 3: Count**

Expected: 14 fewer than after Task 2 (24 left). None of these remain:

```bash
grep -E "pidAlive|pastWord|'duration'|modelFamily|width\(for|formatTokens|'name'|usageTint|'next'|'skill'|autoCommitEnabled|'span'" /tmp/spinner-warnings.txt   # prints nothing
```

- [ ] **Step 4: Run the suite** (as Task 1 Step 4). Expected: 401 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git commit -m "Mark the pure helpers that are passed as function values

A static handed to map or flatMap is a plain function value and cannot
carry the main actor with it. These take values and return values; where a
body does read isolated state, the call site passes a closure instead.

Co-Authored-By: Claude <noreply@anthropic.com>" -- "claude spinner/FeedWatcher.swift" "claude spinner/MenuContentView.swift" "claude spinner/claude_spinnerApp.swift" "claude spinner/Suggestion.swift" "claude spinner/GitAutomation.swift" "claude spinner/WindowContentView.swift" "claude spinner/PinnedProjectDetail.swift" "claude spinner/StatCards.swift"
```

### Task 4: Mark the helpers that already run in detached tasks

**Files:**
- Modify: `claude spinner/GoalClock.swift:62`
- Modify: `claude spinner/GraphifyCard.swift:30`
- Modify: `claude spinner/NewSession.swift:37, 79`
- Modify: `claude spinner/TranscriptReader.swift:42-43, 52, 107, 120` and the `prompts` static below `read`
- Modify: `claude spinner/SessionReplier.swift:112, 118`
- Modify: `claude spinner/GitActions.swift:82`
- Modify: `claude spinner/Suggestion.swift:116, 136`
- Modify: `claude spinner/WindowContentView.swift:2218`

**Interfaces:**
- Consumes: Task 2's `nonisolated` `Landing` (same file as `hasPane`).
- Produces: the same functions and constants, callable from `Task.detached`.

These are called today from `Task.detached { ... }` precisely so that file and process work stays off the main thread. The annotations make the declarations agree with how they are already used.

- [ ] **Step 1: Annotate the functions and constants**

Insert `nonisolated` before `static` (after `private` where present):

| File | Declaration as it is now |
|------|--------------------------|
| `GoalClock.swift:62` | `static func read(pane: String, in dir: URL = stateDir) -> String? {` |
| `GraphifyCard.swift:30` | `static func parse(_ data: Data, topCommunities: Int = 6) -> GraphSummary? {` |
| `NewSession.swift:37` | `static func loadProjects() -> [Project]? {` |
| `NewSession.swift:79` | `static func launch(in dir: String, claudeArgs: [String] = []) -> String? {` |
| `TranscriptReader.swift:52` | `static func read(path: String, tailBytes: Int = TranscriptReader.tailBytes) -> TranscriptSnapshot {` |
| `TranscriptReader.swift:107` | `private static func tail(_ handle: FileHandle, size: Int, bytes: Int) -> TranscriptSnapshot {` |
| `TranscriptReader.swift:120` | `static func parse(_ text: String, droppingFirstLine: Bool) -> TranscriptSnapshot {` |
| `SessionReplier.swift:112` | `static func hasPane(_ session: SessionFeed) -> Bool {` |
| `SessionReplier.swift:118` | `static func paneID(forPID pid: Int) -> String? {` |
| `GitActions.swift:82` | `static let actionTimeout: TimeInterval = 120` |
| `Suggestion.swift:116` | `static func tasksRoot(startingAt cwd: String) -> String? {` |
| `Suggestion.swift:136` | `static func tasks(inTasksFile text: String) -> (open: [String], done: Int) {` |
| `WindowContentView.swift:2218` | `private static let limit = 60` |

- [ ] **Step 2: `TranscriptReader`'s cache**

`read` keeps a cache guarded by its own lock. Mutable static state cannot be `nonisolated` without saying the guard is yours, so in `TranscriptReader.swift` change:

```swift
    private static var cache: [String: (size: Int, tailBytes: Int, snapshot: TranscriptSnapshot)] = [:]
    private static let cacheLock = NSLock()
```

to:

```swift
    // Guarded by `cacheLock` on every read and write, which is what makes the
    // unsafe marker true.
    nonisolated(unsafe) private static var cache: [String: (size: Int, tailBytes: Int, snapshot: TranscriptSnapshot)] = [:]
    nonisolated private static let cacheLock = NSLock()
```

Mark the two size constants the same way: `static let tailBytes = 256 * 1024` becomes `nonisolated static let tailBytes = 256 * 1024`, and likewise `farTailMultiple`, `promptScanLimit` and `promptChunk`. `private static let prompts = PromptTracker()` becomes `nonisolated private static let prompts = PromptTracker()`; if the compiler then requires `PromptTracker` to be `Sendable`, read that class: if every stored property is guarded by a lock or queue it already declares, add `nonisolated` to the class and `@unchecked Sendable` with a one-line comment naming the guard; if it is not guarded, stop and report, because then `read` is racing today and that is a bug to fix, not to annotate.

- [ ] **Step 3: Build and follow the compiler inward**

Run the count command. For each new error of the form "main actor-isolated X can not be referenced from a nonisolated context" inside one of the functions above:

- if X is a `static let` constant or a function that takes and returns values, add `nonisolated` to X and rebuild;
- if X is mutable state or a UI object, remove `nonisolated` from the function you annotated and report it by name. Its detached call site is then wrong today and needs a decision, not an annotation.

Also clear the one actor-context call: in `GoalClock.swift:77` the call `SessionReplier.paneID(forPID: pid)` inside `actor GoalPaneResolver` is covered by the `paneID` annotation above; confirm its line is gone from the list.

- [ ] **Step 4: Count**

Expected: 20 fewer than after Task 3 (4 left). None of these remain:

```bash
grep -E "read\(pane|parse\(_:topCommunities|loadProjects|launch\(in|read\(path|hasPane|paneID|actionTimeout|'limit'|tasksRoot|tasks\(inTasksFile" /tmp/spinner-warnings.txt   # prints nothing
```

- [ ] **Step 5: Run the suite** (as Task 1 Step 4). Expected: 401 tests, 0 failures. `testTranscriptFindsClaudesTextBeyondTheTail` exercises the cache with two tail lengths and must still pass.

- [ ] **Step 6: Commit**

```bash
git commit -m "Mark the helpers that already run in detached tasks

Each of these is called from Task.detached so that file and process work
stays off the main thread, while its declaration still claimed the main
actor. The transcript cache keeps its lock and says so.

Co-Authored-By: Claude <noreply@anthropic.com>" -- "claude spinner/GoalClock.swift" "claude spinner/GraphifyCard.swift" "claude spinner/NewSession.swift" "claude spinner/TranscriptReader.swift" "claude spinner/SessionReplier.swift" "claude spinner/GitActions.swift" "claude spinner/Suggestion.swift" "claude spinner/WindowContentView.swift"
```

### Task 5: The four one-offs, and the record

**Files:**
- Modify: `claude spinner/claude_spinnerApp.swift:83`
- Modify: `claude spinner/WindowContentView.swift:1821`
- Modify: `claude spinnerTests/claude_spinnerTests.swift:2211, 2728`
- Modify: `STATUS.md`, `TASKS.md`

**Interfaces:**
- Consumes: the count from Task 4.
- Produces: a build with 0 warnings and a decision-log entry saying so.

- [ ] **Step 1: The notification completion handler**

`requestAuthorization`'s completion runs on an arbitrary queue and calls an isolated method. In `claude_spinnerApp.swift`:

```swift
            asks.refreshAuthorization()
        }
```

becomes

```swift
            Task { @MainActor in asks.refreshAuthorization() }
        }
```

- [ ] **Step 2: The deprecated `Text +`**

In `WindowContentView.swift`:

```swift
                (Text(command).foregroundStyle(Color.claude) + Text("  \(pick.reason)"))
                    .font(.ui(10)).foregroundStyle(Color.label)
```

becomes

```swift
                Text("\(Text(command).foregroundStyle(Color.claude))  \(pick.reason)")
                    .font(.ui(10)).foregroundStyle(Color.label)
```

- [ ] **Step 3: The two needless `try`**

At `claude_spinnerTests.swift:2211` and `:2728`, the line `        try withTempDir { dir in` becomes `        withTempDir { dir in`. If either enclosing test function is declared `throws` and nothing else in it throws, leave the `throws` (removing it is a separate change).

- [ ] **Step 4: Count**

Run the count command. Expected: `0`, and `/tmp/spinner-warnings.txt` is empty. If it is not, print the file: every remaining line is a site this plan did not list, and each gets reported with its file and line, not fixed by guessing.

- [ ] **Step 5: Look at the one visible change**

Step 2 touched drawn text. `./run.sh`, open the window, select a session whose Skills card shows a pick (an orange command followed by grey reasoning under the chips), and capture the window by id (`screencapture -l <id>`, never a region). The command must still be orange and the reason grey, on one wrapped paragraph.

- [ ] **Step 6: Run the suite** (as Task 1 Step 4). Expected: 401 tests, 0 failures.

- [ ] **Step 7: Record and commit**

Append to the newest dated section of `STATUS.md`'s `## Decision log`:

```markdown
- Decided: the build carries no warnings. 116 isolation warnings were the
  default main-actor isolation being wrong about pure helpers, value types and
  the test target; each now says `nonisolated` at its declaration. A new warning
  is therefore new, and worth reading.
```

In `TASKS.md`, under `## Completed`, add `- [x] Clear the Swift 6 isolation warnings -- <sha of this commit's parent>`.

```bash
git commit -m "Clear the last four warnings

A completion handler that called an isolated method from its own queue, a
Text concatenation deprecated in macOS 26, and two try expressions with
nothing throwing in them.

Co-Authored-By: Claude <noreply@anthropic.com>" -- "claude spinner/claude_spinnerApp.swift" "claude spinner/WindowContentView.swift" "claude spinnerTests/claude_spinnerTests.swift" STATUS.md TASKS.md
```

---

## Not in this plan

- Turning on the Swift 6 language mode. With 0 warnings it becomes a one-line experiment, and it is a separate decision.
- A CI gate on the warning count. Without one the count can grow back; adding one is new machinery and wants its own proof that it fires.
- The runtime QoS note from `testRunHonoursItsTimeoutInBothDirections` (a user-interactive thread waiting on a lower-priority one). It is a priority inversion in that test's harness, not an isolation warning.

## Self-review

- Coverage: 73 + 5 + 14 + 20 + 4 = 116, the baseline. Every row of the Inventory names its task.
- Unverified by the author: none of these edits has been compiled. The site list and the declarations are read from the tree at `d6ae43d` and from CI run `37051872323`; the expected counts after each task are arithmetic on that list. Task 3 Step 2 and Task 4 Steps 2 and 3 exist because some annotations will not compile as first written, and say what to do when they do not.
- Names: `nonisolated` is used as a declaration modifier throughout; the only other spelling is `nonisolated(unsafe)` on the one lock-guarded cache.
