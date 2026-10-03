//
//  claude_spinnerTests.swift
//  claude spinnerTests
//
//  Unit tests over the app's pure logic (no I/O, no UI): session display
//  derivation, spinner-word seeding, and duration formatting.
//

import XCTest
import SwiftUI
import UserNotifications
@testable import claude_spinner

final class claude_spinnerTests: XCTestCase {

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

    // MARK: - SessionFeed display derivation

    func testDisplayPathIsHomeRelative() {
        var s = SessionFeed(id: "a")
        let home = NSHomeDirectory()
        s.cwd = home + "/Developer/apply"
        XCTAssertEqual(s.displayPath, "~/Developer/apply")
        s.cwd = home
        XCTAssertEqual(s.displayPath, "~")
        s.cwd = "/tmp/outside"
        XCTAssertEqual(s.displayPath, "/tmp/outside")
        s.cwd = ""
        XCTAssertEqual(s.displayPath, "session")
    }

    func testProjectNameIsLastPathComponent() {
        var s = SessionFeed(id: "a")
        s.cwd = NSHomeDirectory() + "/Developer/claude-spinner"
        XCTAssertEqual(s.projectName, "claude-spinner")
        s.cwd = ""
        XCTAssertEqual(s.projectName, "session")
    }

    func testIsWorking() {
        var s = SessionFeed(id: "a")
        s.status = .thinking; XCTAssertTrue(s.isWorking)
        s.status = .tool;     XCTAssertTrue(s.isWorking)
        s.status = .idle;     XCTAssertFalse(s.isWorking)
        s.status = .attention; XCTAssertFalse(s.isWorking)
    }

    func testApplyStateDecodesTodoCounts() throws {
        var s = SessionFeed(id: "x")
        XCTAssertNil(s.todoTotal)
        XCTAssertNil(s.todoDone)
        try s.applyStateJSONForTest("""
        {"todo_total":3,"todo_done":1}
        """)
        XCTAssertEqual(s.todoTotal, 3)
        XCTAssertEqual(s.todoDone, 1)
    }

    func testApplyStateLeavesTodoCountsNilWhenAbsent() throws {
        var s = SessionFeed(id: "x")
        try s.applyStateJSONForTest("{}")
        XCTAssertNil(s.todoTotal)
        XCTAssertNil(s.todoDone)
    }

    // MARK: - End-to-end join: real state JSON -> SessionFeed.todoProgress -> todoSummary

    /// The real call site is `session.todoSummary` on `SessionRow`'s second line.
    /// This is the one test that walks the whole path a real feed file takes.
    func testTodoProgressEndToEndFromDecodedStateJSON() throws {
        var s = SessionFeed(id: "x")
        try s.applyStateJSONForTest("""
        {"todo_total":3,"todo_done":1}
        """)
        let progress = s.todoProgress
        XCTAssertEqual(progress.total, 3)
        XCTAssertEqual(progress.done, 1)
        XCTAssertEqual(s.todoSummary, "todos 1/3")
    }

    /// A session with no todos yet decodes to nil counts, which `todoProgress`
    /// coalesces to `(0, 0)` — and the row draws no todo text at all, not `0/0`.
    func testTodoProgressEndToEndWithNoTodosYet() throws {
        var s = SessionFeed(id: "x")
        try s.applyStateJSONForTest("{}")
        let progress = s.todoProgress
        XCTAssertEqual(progress.total, 0)
        XCTAssertEqual(progress.done, 0)
        XCTAssertNil(s.todoSummary)
    }

    // MARK: - Bundled Scripts/emit.sh stays in sync with the live spinnerfeed copy

    /// This repo bundles its own copy of `emit.sh` (installed to
    /// `~/.claude/spinnerfeed/emit.sh` by `SetupInstaller`), separate from that
    /// live copy in the `~/.claude` repo. The bundled copy predated todo capture
    /// entirely and drifted out of sync once; this is a cheap content-parity smoke
    /// check, not a full diff, so that drift can't happen silently again.
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
        XCTAssertTrue(contents.contains("notification_type"),
                      "bundled Scripts/emit.sh must record which notification fired — "
                      + "without it idle_prompt is indistinguishable from a real block")
        XCTAssertTrue(contents.contains("prev_msg"),
                      "bundled Scripts/emit.sh is missing the message carry-forward — the "
                      + "attention banner falls back to a bare project name without it")
    }

    /// Same content-parity smoke check for the answer hook. The three shapes
    /// asserted here are the ones whose absence would be silent: without the
    /// pgrep gate every tool call stalls for the deadline when the app is shut,
    /// and without `passthrough` a dismissed banner never falls back.
    func testBundledAskScriptKeepsItsFallbacks() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let scriptURL = testFile
            .deletingLastPathComponent()               // claude spinnerTests/
            .deletingLastPathComponent()                // repo root
            .appendingPathComponent("claude spinner/Scripts/ask.sh")
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("pgrep -x \"${2:-claude spinner}\""),
                      "ask.sh must not write an ask file with no app to answer it")
        XCTAssertTrue(contents.contains("passthrough"))
        XCTAssertTrue(contents.contains("lsappinfo front"),
                      "ask.sh must leave the question to the terminal when it is frontmost")
        XCTAssertTrue(contents.contains("trap "),
                      "ask.sh must remove its ask file when stopped, or the card goes stale")
        XCTAssertTrue(contents.contains("multiSelect"),
                      "ask.sh must pass multiSelect questions through to the terminal")
        XCTAssertTrue(contents.contains("tool_input:"),
                      "ask.sh must copy tool_input into the ask file; the permission card "
                      + "reads it to show the command, and drops silently back to the tool "
                      + "name without it")
        // Comments are stripped first: the script says "must never exit 2" in
        // prose, and matching that would make this pass for the wrong reason.
        let code = contents.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
        XCTAssertFalse(code.contains("exit 2"),
                       "exit 2 reads as a deny on PreToolUse — the fallback must be exit 0")
    }

    /// Both surfaces must draw the shared notices, and neither is reachable from
    /// the other: the panel needs a status item, the window needs `surface =
    /// window`. `SetupBanner` was already stranded in the panel once and
    /// `NotificationsNotice` after it, so this asserts the source of each view
    /// names both rather than waiting for the third time.
    func testBothSurfacesDrawTheSharedNotices() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()               // claude spinnerTests/
            .deletingLastPathComponent()                // repo root
            .appendingPathComponent("claude spinner")
        for surface in ["MenuContentView.swift", "WindowContentView.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(surface), encoding: .utf8)
            XCTAssertTrue(source.contains("NotificationsNotice()"),
                          "\(surface) never says notifications are off — on that surface "
                          + "every banner is a silent no-op with nothing on screen to say so")
            XCTAssertTrue(source.contains("SetupBanner("),
                          "\(surface) offers no way to install the hooks")
        }
    }

    func testHookEventsIncludeSubagentLifecycle() {
        XCTAssertTrue(SetupInstaller.hookEvents.contains("SubagentStart"))
        XCTAssertTrue(SetupInstaller.hookEvents.contains("SubagentStop"))
    }

    // MARK: - Spinner words (seeded, stable, present/past paired)

    func testSpinnerWordSeedingIsStableAndPaired() {
        var s = SessionFeed(id: "x")
        s.turnStart = Date(timeIntervalSince1970: 8)   // seed 8 -> index 8 -> "Marinating"
        s.lastSeed = 8
        XCTAssertEqual(SpinnerWords.word(for: s), "Marinating")
        XCTAssertEqual(SpinnerWords.pastWord(for: s), "Marinated")
        XCTAssertEqual(SpinnerWords.word(for: s), SpinnerWords.word(for: s)) // stable
    }

    // MARK: - Duration formatting

    func testFormatDuration() {
        XCTAssertEqual(FeedWatcher.formatDuration(0), "0s")
        XCTAssertEqual(FeedWatcher.formatDuration(5), "5s")
        XCTAssertEqual(FeedWatcher.formatDuration(59), "59s")
        XCTAssertEqual(FeedWatcher.formatDuration(60), "1m 0s")
        XCTAssertEqual(FeedWatcher.formatDuration(125), "2m 5s")
        XCTAssertEqual(FeedWatcher.formatDuration(-3), "0s")
    }

    /// The row's context column is 30pt — ~4 characters of Menlo 10 — so no input
    /// may render wider than that, which is why the k/M units carry no decimals.
    func testFormatTokens() {
        XCTAssertEqual(FeedWatcher.formatTokens(0), "0")
        XCTAssertEqual(FeedWatcher.formatTokens(999), "999")
        XCTAssertEqual(FeedWatcher.formatTokens(69_598), "70k")
        XCTAssertEqual(FeedWatcher.formatTokens(212_400), "212k")
        XCTAssertEqual(FeedWatcher.formatTokens(999_499), "999k")
        XCTAssertEqual(FeedWatcher.formatTokens(999_500), "1.0M")
        XCTAssertEqual(FeedWatcher.formatTokens(1_240_000), "1.2M")
        XCTAssertEqual(FeedWatcher.formatTokens(12_000_000), "12M")
    }

    /// `done` can come from a state file written by a different process/repo, so
    /// it is never trusted to sit inside `0...total`.
    func testTodoSummaryClampsOutOfRangeDone() throws {
        var s = SessionFeed(id: "x")
        try s.applyStateJSONForTest(#"{"todo_total":3,"todo_done":5}"#)
        XCTAssertEqual(s.todoSummary, "todos 3/3")
        try s.applyStateJSONForTest(#"{"todo_total":3,"todo_done":-2}"#)
        XCTAssertEqual(s.todoSummary, "todos 0/3")
    }

    func testCompactAge() {
        let t = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(FeedWatcher.compactAge(since: t.addingTimeInterval(-45), now: t), "45s")
        XCTAssertEqual(FeedWatcher.compactAge(since: t.addingTimeInterval(-600), now: t), "10m")
        XCTAssertEqual(FeedWatcher.compactAge(since: t.addingTimeInterval(-3660), now: t), "1h1m")
        XCTAssertEqual(FeedWatcher.compactAge(since: t.addingTimeInterval(-7200), now: t), "2h")
    }

    // MARK: - Row grouping (displayItems)

    func testDisplayItemsSeparatesDoneFromNeverWorkedIdle() {
        let now = Date()
        let items = FeedWatcher.displayItems(from: [
            mk("a", .idle, cwd: "/home", updated: now, lastDuration: 10),        // done
            mk("b", .idle, cwd: "/home", updated: now.addingTimeInterval(-5)),   // never-worked
            mk("b2", .idle, cwd: "/home", updated: now.addingTimeInterval(-9)),  // never-worked
            mk("c", .thinking, cwd: "/proj", updated: now),                      // working
        ])
        // working row + a done group + a never-worked idle group — the done turn is
        // NOT hidden behind the fresher never-worked sessions in the same dir.
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.first?.session.status, .thinking)               // working sorts first
        let done = items.first { $0.id == "done:/home" }
        XCTAssertEqual(done?.count, 1)
        XCTAssertEqual(done?.session.id, "a")
        XCTAssertNotNil(done?.session.lastDuration)
        let idle = items.first { $0.id == "idle:/home" }
        XCTAssertEqual(idle?.count, 2)                                       // b + b2
    }

    func testDisplayItemsCollapsesDoneByDirectory() {
        let now = Date()
        let items = FeedWatcher.displayItems(from: [
            mk("d1", .idle, cwd: "/r", updated: now, lastDuration: 30),
            mk("d2", .idle, cwd: "/r", updated: now.addingTimeInterval(-10), lastDuration: 120),
        ])
        XCTAssertEqual(items.count, 1)
        let done = items.first { $0.id == "done:/r" }
        XCTAssertEqual(done?.count, 2)
        XCTAssertEqual(done?.session.id, "d1")                               // freshest rep
    }

    func testDisplayItemsKeepsDistinctDirsSeparate() {
        let now = Date()
        let items = FeedWatcher.displayItems(from: [
            mk("a", .idle, cwd: "/one", updated: now),
            mk("b", .idle, cwd: "/two", updated: now),
        ])
        XCTAssertEqual(items.count, 2)
    }

    // MARK: - Nested subagent rows (parent_session_id / agent_id / agent_type)

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

    func testDisplayItemsSortsPromotedOrphanWithWorkingSessions() {
        let now = Date()
        let items = FeedWatcher.displayItems(from: [
            mk("idle-a", .idle, cwd: "/home", updated: now, lastDuration: 5),
            mk("idle-b", .idle, cwd: "/home", updated: now.addingTimeInterval(-1), lastDuration: 3),
            mk("working-root", .thinking, cwd: "/other", updated: now),
            mk("orphan", .tool, cwd: "/x", updated: now.addingTimeInterval(-1),
               parentSessionId: "missing", agentId: "a1", agentType: "Explore"),
        ])
        XCTAssertEqual(items.map(\.id), ["working-root", "orphan", "done:/home"])
        XCTAssertEqual(items[1].depth, 0)
        XCTAssertEqual(items[1].session.displayName, "Explore")
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

    func testExcludingDeadPidIdleKeepsIdleChildSharingParentsDeadPid() {
        let now = Date()
        var parent = mk("p", .thinking, cwd: "/x", updated: now)
        parent.pid = 4242
        var child = mk("p.a1", .idle, cwd: "/x", updated: now, lastDuration: 2,
                       parentSessionId: "p", agentId: "a1", agentType: "Explore")
        child.pid = 4242
        let kept = FeedWatcher.excludingDeadPidIdle([parent, child], pidAlive: { _ in false })
        XCTAssertEqual(Set(kept.map(\.id)), ["p", "p.a1"])
        let items = FeedWatcher.displayItems(from: kept)
        XCTAssertEqual(items.map(\.id), ["p", "p.a1"])
        XCTAssertEqual(items.last?.depth, 1)
    }

    func testAWorkingSessionWhoseProcessIsGoneStopsBeingWorking() {
        let now = Date()
        var dead = mk("d", .tool, cwd: "/x", updated: now.addingTimeInterval(-600))
        dead.pid = 4242
        XCTAssertTrue(FeedWatcher.excludingDeadPidIdle([dead], pidAlive: { _ in false }, now: now).isEmpty,
                      "a terminal closed mid-tool left the row claiming to run for 12 hours")
    }

    func testAWorkingSessionIsKeptWhileItsPidCouldStillBeMisread() {
        let now = Date()
        // Inside the grace: a session that started seconds ago may have captured
        // a hook subshell's pid rather than claude's, and must not be dropped.
        var fresh = mk("f", .tool, cwd: "/x", updated: now.addingTimeInterval(-10))
        fresh.pid = 4242
        XCTAssertEqual(FeedWatcher.excludingDeadPidIdle([fresh], pidAlive: { _ in false }, now: now).map(\.id),
                       ["f"])
        // And the known-good input: stale, but the process is there, so it is
        // simply a long tool call.
        var stale = mk("s", .tool, cwd: "/x", updated: now.addingTimeInterval(-600))
        stale.pid = 4242
        XCTAssertEqual(FeedWatcher.excludingDeadPidIdle([stale], pidAlive: { _ in true }, now: now).map(\.id),
                       ["s"])
    }

    func testASessionThatHasWanderedStillBelongsToWhereItStarted() {
        // The real case: this session started in the repo and a Bash `cd` moved
        // its reported cwd into a subfolder of ~/.claude.
        XCTAssertEqual(
            SessionFeed.startCwd(
                transcriptPath: "/Users/home/.claude/projects/-Users-home-developer-claude-spinner/s.jsonl",
                cwd: "/Users/home/developer/claude-spinner/claude spinner"),
            "/Users/home/developer/claude-spinner")
        // A dot in the path is a "-" in the folder name, like a slash.
        XCTAssertEqual(
            SessionFeed.startCwd(transcriptPath: "/p/-Users-home--claude/s.jsonl",
                                 cwd: "/Users/home/.claude/spinnerfeed"),
            "/Users/home/.claude")
    }

    func testAWanderedSessionIsNeverGuessedAHome() {
        // Walked clean out of the tree it started in: there is nothing to match,
        // and the caller falls back to the cwd rather than inventing a project.
        XCTAssertNil(SessionFeed.startCwd(transcriptPath: "/p/-Users-home-developer-elsewhere/s.jsonl",
                                          cwd: "/tmp/scratch"))
        XCTAssertNil(SessionFeed.startCwd(transcriptPath: nil, cwd: "/Users/home/developer/claude-spinner"))
        // A path that cannot be shortened answers the walk with itself. Without
        // the guard this did not fail, it hung, and the test host was killed
        // mid-run with no failing assertion to read.
        XCTAssertNil(SessionFeed.startCwd(transcriptPath: "/p/-x/s.jsonl", cwd: "//"))
        XCTAssertNil(SessionFeed.startCwd(transcriptPath: "/p/-x/s.jsonl", cwd: "relative"))
        // The known-good input: a session that never moved resolves to its own cwd.
        XCTAssertEqual(
            SessionFeed.startCwd(transcriptPath: "/p/-Users-home-developer-claude-spinner/s.jsonl",
                                 cwd: "/Users/home/developer/claude-spinner"),
            "/Users/home/developer/claude-spinner")
    }

    func testASessionWaitingOnYouIsNeverPrunedOnItsPid() {
        let now = Date()
        // Waiting is silence by definition, and dropping the row takes the
        // "Claude needs you" banner with it.
        var waiting = mk("w", .attention, cwd: "/x", updated: now.addingTimeInterval(-7200))
        waiting.pid = 4242
        XCTAssertEqual(FeedWatcher.excludingDeadPidIdle([waiting], pidAlive: { _ in false }, now: now).map(\.id),
                       ["w"])
    }

    func testAWorkingOrphanChildStopsBeingWorkingOnceItGoesQuiet() {
        let now = Date()
        let fresh = mk("gone.a1", .tool, cwd: "/x", updated: now,
                       parentSessionId: "gone", agentId: "a1", agentType: "Explore")
        let quiet = mk("gone.a2", .tool, cwd: "/x", updated: now.addingTimeInterval(-600),
                       parentSessionId: "gone", agentId: "a2", agentType: "Explore")
        let waiting = mk("gone.a3", .attention, cwd: "/x", updated: now.addingTimeInterval(-600),
                         parentSessionId: "gone", agentId: "a3", agentType: "Explore")
        let kept = FeedWatcher.excludingOrphanIdleChildren([fresh, quiet, waiting], now: now)
        XCTAssertEqual(Set(kept.map(\.id)), ["gone.a1", "gone.a3"],
                       "a subagent cannot outlive its session, but a live one must survive the rule")
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

    func testABorrowedModelTagIsMarkedAsAGuess() {
        var reporting = mk("a", .thinking)
        reporting.model = "Haiku 4.5"
        let silent = mk("b", .idle)
        XCTAssertEqual(FeedWatcher.modelTag(for: reporting, among: [reporting, silent], cached: nil), "Haiku")
        XCTAssertEqual(FeedWatcher.modelTag(for: silent, among: [reporting, silent], cached: nil), "Haiku?")
        XCTAssertEqual(FeedWatcher.modelTag(for: silent, among: [silent], cached: "Opus 5.5"), "Opus?")
        XCTAssertNil(FeedWatcher.modelTag(for: silent, among: [silent], cached: nil))
    }

    // MARK: - menuBarState transitions

    func testMenuBarStateTransitions() {
        let now = Date()
        XCTAssertEqual(FeedWatcher.menuBarState(for: [], now: now), .idle)
        XCTAssertEqual(FeedWatcher.menuBarState(for: [mk("w", .tool, updated: now)], now: now), .working)
        XCTAssertEqual(FeedWatcher.menuBarState(
            for: [mk("w", .tool, updated: now), mk("a", .attention, updated: now)], now: now), .attention)
        XCTAssertEqual(FeedWatcher.menuBarState(
            for: [mk("d", .idle, updated: now, lastDuration: 4)], now: now), .doneFlash)
        XCTAssertEqual(FeedWatcher.menuBarState(
            for: [mk("d", .idle, updated: now.addingTimeInterval(-30), lastDuration: 4)], now: now), .idle)
        XCTAssertEqual(FeedWatcher.menuBarState(for: [mk("i", .idle, updated: now)], now: now), .idle)
    }

    func testSortedOrdersByRankThenTokensThenRecency() {
        let now = Date()
        let sorted = FeedWatcher.sorted([
            mk("i", .idle, updated: now),
            mk("w", .tool, updated: now.addingTimeInterval(-100)),
            mk("a", .attention, updated: now.addingTimeInterval(-200)),
        ])
        XCTAssertEqual(sorted.map(\.id), ["a", "w", "i"])
    }

    /// Rank wins outright: a waiting session outranks any amount of context.
    func testSortedRanksAttentionAboveHeavierWorkingSession() {
        let now = Date()
        let sorted = FeedWatcher.sorted([
            mk("heavy", .tool, updated: now, tokens: 900_000),
            mk("light", .attention, updated: now, tokens: 1_000),
        ])
        XCTAssertEqual(sorted.map(\.id), ["light", "heavy"])
    }

    /// Within one band, heaviest context first.
    func testSortedOrdersByTokensWithinABand() {
        let now = Date()
        let sorted = FeedWatcher.sorted([
            mk("mid", .tool, updated: now, tokens: 150_000),
            mk("big", .tool, updated: now, tokens: 400_000),
            mk("none", .tool, updated: now),
            mk("small", .tool, updated: now, tokens: 20_000),
        ])
        // A session with no reported context sorts as 0 — last, not first.
        XCTAssertEqual(sorted.map(\.id), ["big", "mid", "small", "none"])
    }

    /// Recency still breaks ties when the token counts match.
    func testSortedFallsBackToRecencyOnEqualTokens() {
        let now = Date()
        let sorted = FeedWatcher.sorted([
            mk("old", .tool, updated: now.addingTimeInterval(-100), tokens: 50_000),
            mk("new", .tool, updated: now, tokens: 50_000),
        ])
        XCTAssertEqual(sorted.map(\.id), ["new", "old"])
    }

    // MARK: - Project sections

    /// Wrap sessions the way the sidebar does: one depth-0 row each.
    private func rows(_ sessions: [SessionFeed]) -> [SessionRowItem] {
        sessions.map { SessionRowItem(id: $0.id, session: $0, ids: [$0.id], depth: 0) }
    }

    private func named(_ id: String, _ status: SessionStatus, cwd: String,
                       name: String? = nil, tokens: Int? = nil) -> SessionFeed {
        var s = mk(id, status, cwd: cwd, tokens: tokens)
        s.sessionName = name
        return s
    }

    /// The regression this whole feature exists for. `rescan` builds `sessions` from
    /// a dictionary's `values`, whose order Swift does not define, so the same set
    /// arrives in a different order on every scan. Sections must not move with it.
    func testProjectSectionsAreIdenticalUnderAnyInputOrder() {
        let a = named("a", .tool, cwd: "/w/alpha", name: "one")
        let b = named("b", .tool, cwd: "/w/beta", name: "two")
        let c = named("c", .idle, cwd: "/w/alpha", name: "three")
        let forward = FeedWatcher.projectSections(rows([a, b, c]))
        let shuffled = FeedWatcher.projectSections(rows([c, a, b]))
        let reversed = FeedWatcher.projectSections(rows([b, c, a]))
        XCTAssertEqual(forward.map(\.id), shuffled.map(\.id))
        XCTAssertEqual(forward.map(\.id), reversed.map(\.id))
        XCTAssertEqual(forward.map { $0.items.map(\.id) }, shuffled.map { $0.items.map(\.id) })
        XCTAssertEqual(forward.map { $0.items.map(\.id) }, reversed.map { $0.items.map(\.id) })
    }

    func testProjectSectionsAreAlphabeticalByProjectThenSessionName() {
        let sections = FeedWatcher.projectSections(rows([
            named("z", .tool, cwd: "/w/zebra", name: "z1"),
            named("m2", .tool, cwd: "/w/alpha", name: "second"),
            named("m1", .tool, cwd: "/w/alpha", name: "first"),
        ]))
        XCTAssertEqual(sections.map(\.title), ["alpha", "zebra"])
        XCTAssertEqual(sections[0].items.map(\.id), ["m1", "m2"])
    }

    func testProjectSectionsByRecencyPutNewestActivityFirst() {
        let now = Date()
        func at(_ id: String, cwd: String, ago: TimeInterval) -> SessionFeed {
            var s = named(id, .tool, cwd: cwd, name: id)
            s.updated = now.addingTimeInterval(-ago)
            return s
        }
        let input = rows([
            at("a-old", cwd: "/w/alpha", ago: 300),
            at("z-new", cwd: "/w/zebra", ago: 10),
            at("a-new", cwd: "/w/alpha", ago: 60),
        ])
        let sections = FeedWatcher.projectSections(input, byRecency: true)
        XCTAssertEqual(sections.map(\.title), ["zebra", "alpha"])
        XCTAssertEqual(sections[1].items.map(\.id), ["a-new", "a-old"])
        // The default is untouched: the panel still sorts by name.
        XCTAssertEqual(FeedWatcher.projectSections(input).map(\.title), ["alpha", "zebra"])
    }

    /// Pinned on top, and listed once — the sidebar tags rows by session id, so the
    /// same session appearing under its project too would duplicate a selection tag.
    func testNeedsYouIsPinnedFirstAndNotRepeatedUnderItsProject() {
        var blocked = named("b", .attention, cwd: "/w/alpha", name: "blocked")
        blocked.notificationType = "permission_prompt"
        let sections = FeedWatcher.projectSections(rows([
            named("w", .tool, cwd: "/w/alpha", name: "working"), blocked,
        ]))
        XCTAssertEqual(sections.map(\.title), ["Needs you", "alpha"])
        XCTAssertEqual(sections[0].items.map(\.id), ["b"])
        XCTAssertEqual(sections[1].items.map(\.id), ["w"])
    }

    /// An `asks` entry pins a session even when its own status has not flipped.
    func testNeedsYouIncludesSessionsWithAPendingAsk() {
        let sections = FeedWatcher.projectSections(
            rows([named("q", .tool, cwd: "/w/alpha", name: "asking")]), asked: ["q"])
        XCTAssertEqual(sections.map(\.title), ["Needs you", ])
    }

    /// An idle_prompt is not blocked on anyone, so nothing gets pinned and the
    /// section is omitted rather than drawn empty.
    func testNeedsYouIsOmittedWhenNothingIsBlocked() {
        var finished = named("f", .attention, cwd: "/w/alpha", name: "done")
        finished.notificationType = "idle_prompt"
        let sections = FeedWatcher.projectSections(rows([finished]))
        XCTAssertEqual(sections.map(\.title), ["alpha"])
    }

    /// A collapsed idle row stands for several sessions; a subagent row is not a
    /// session of its own.
    func testSessionCountExpandsCollapsedRowsAndIgnoresSubagents() {
        let parent = named("p", .tool, cwd: "/w/alpha", name: "parent")
        let child = mk("kid", .tool, cwd: "/w/alpha", parentSessionId: "p")
        let collapsed = SessionRowItem(id: "idle:/w/alpha",
                                       session: named("i1", .idle, cwd: "/w/alpha", name: "idle"),
                                       ids: ["i1", "i2", "i3"], depth: 0)
        let sections = FeedWatcher.projectSections([
            SessionRowItem(id: "p", session: parent, ids: ["p", "kid"], depth: 0, subagentCount: 1),
            SessionRowItem(id: "kid", session: child, ids: ["kid"], depth: 1),
            collapsed,
        ])
        XCTAssertEqual(sections.count, 1)
        // 1 parent (its child ids don't count) + 3 collapsed idles.
        XCTAssertEqual(sections[0].sessionCount, 4)
    }

    /// A worktree subagent's cwd is `.../agent-<id>`; grouped by it, the panel drew
    /// an `AGENT-<ID>` section counting 0 (seen 2026-09-30).
    func testAWorktreeSubagentStaysInItsParentsSection() {
        let parent = named("p", .tool, cwd: "/w/alpha", name: "parent")
        let kid = mk("kid", .tool, cwd: "/w/alpha/.claude/worktrees/agent-a40ebd7", parentSessionId: "p")
        let sections = FeedWatcher.projectSections([
            SessionRowItem(id: "p", session: parent, ids: ["p", "kid"], depth: 0, subagentCount: 1),
            SessionRowItem(id: "kid", session: kid, ids: ["kid"], depth: 1),
        ])
        XCTAssertEqual(sections.map(\.title), ["alpha"])
        XCTAssertEqual(sections[0].items.map(\.id), ["p", "kid"])
    }

    /// Review finding on f300f26: left in the project section, a waiting parent's
    /// subagent nested under the root before it ("a" here).
    func testAWaitingSessionsSubagentGoesWithItIntoNeedsYou() {
        let other = named("a", .tool, cwd: "/w/alpha", name: "a-first")
        let parent = named("p", .tool, cwd: "/w/alpha", name: "parent")
        let kid = mk("kid", .tool, cwd: "/w/alpha/.claude/worktrees/agent-1", parentSessionId: "p")
        let sections = FeedWatcher.projectSections([
            SessionRowItem(id: "a", session: other, ids: ["a"], depth: 0),
            SessionRowItem(id: "p", session: parent, ids: ["p", "kid"], depth: 0, subagentCount: 1),
            SessionRowItem(id: "kid", session: kid, ids: ["kid"], depth: 1),
        ], asked: ["p"])
        XCTAssertEqual(sections.map(\.id), ["needs-you", "project:alpha"])
        XCTAssertEqual(sections[0].items.map(\.id), ["p", "kid"])
        XCTAssertEqual(sections[0].sessionCount, 1)
        XCTAssertEqual(sections[1].items.map(\.id), ["a"])
    }

    func testContextTotalSumsAndIsNilWhenNothingReported() {
        let withTokens = FeedWatcher.projectSections(rows([
            named("a", .tool, cwd: "/w/alpha", name: "a", tokens: 40_000),
            named("b", .tool, cwd: "/w/alpha", name: "b", tokens: 60_000),
        ]))
        XCTAssertEqual(withTokens[0].contextTotal, 100_000)

        let without = FeedWatcher.projectSections(rows([
            named("c", .tool, cwd: "/w/alpha", name: "c"),
        ]))
        XCTAssertNil(without[0].contextTotal)
    }

    /// Children stay directly under the parent they are indented beneath, even
    /// though the roots around them get re-sorted.
    func testChildrenStayAttachedToTheirParentAfterSorting() {
        let zed = named("z", .tool, cwd: "/w/alpha", name: "zed")
        let kid = mk("kid", .tool, cwd: "/w/alpha", parentSessionId: "z")
        let abe = named("a", .tool, cwd: "/w/alpha", name: "abe")
        let sections = FeedWatcher.projectSections([
            SessionRowItem(id: "z", session: zed, ids: ["z", "kid"], depth: 0, subagentCount: 1),
            SessionRowItem(id: "kid", session: kid, ids: ["kid"], depth: 1),
            SessionRowItem(id: "a", session: abe, ids: ["a"], depth: 0),
        ])
        XCTAssertEqual(sections[0].items.map(\.id), ["a", "z", "kid"])
    }

    // MARK: - Color tier boundaries

    func testUsageTintTiers() {
        // Four bands with boundaries at 50, 75, 90.
        XCTAssertEqual(Color.usageTint(0), Color.usageTint(49))       // green band
        XCTAssertNotEqual(Color.usageTint(49), Color.usageTint(50))   // -> yellow
        XCTAssertEqual(Color.usageTint(50), Color.usageTint(74))      // yellow band
        XCTAssertNotEqual(Color.usageTint(74), Color.usageTint(75))   // -> amber
        XCTAssertEqual(Color.usageTint(75), Color.usageTint(89))      // amber band
        XCTAssertNotEqual(Color.usageTint(89), Color.usageTint(90))   // -> red
        XCTAssertEqual(Color.usageTint(90), Color.usageTint(100))     // red band
    }

    /// Every status label fits — the bug-111/122 class, checked as arithmetic
    /// rather than by eye. "running TodoWrite" is the long tail that truncated
    /// even under the old fixed 103pt slot.
    func testEveryStatusLabelFitsItsColumn() {
        for label in ["done", "idle", "thinking", "needs input", "running",
                      "running bash", "running Edit", "running TodoWrite"] {
            for model in ["opus", "sonnet", "haiku", ""] {
                let c = RowLayout.columns(statusLabels: [label], models: [model],
                                          panelWidth: Constants.panelWidth)
                XCTAssertGreaterThanOrEqual(
                    c.status, CGFloat(label.count) * RowLayout.monoAdvance,
                    "\"\(label)\" truncates beside \"\(model)\"")
                XCTAssertGreaterThanOrEqual(
                    c.model, CGFloat(model.count) * RowLayout.monoAdvance,
                    "\"\(model)\" truncates")
            }
        }
    }

    /// The panel sizes each column to its widest row, so the columns align.
    func testColumnsAreSizedToTheWidestRow() {
        let mixed = RowLayout.columns(statusLabels: ["done", "running bash"],
                                      models: ["opus", "sonnet"],
                                      panelWidth: Constants.panelWidth)
        let widest = RowLayout.columns(statusLabels: ["running bash"], models: ["sonnet"],
                                       panelWidth: Constants.panelWidth)
        XCTAssertEqual(mixed, widest)
    }

    /// Spare width lands on the name *up to the cap*. Status no longer competes
    /// for it at all post-fix-2 — it moved to line 2 with the context meter — so a
    /// longer status label leaves line 1's name/model split completely untouched;
    /// only the model word still takes from the name, and only below the cap.
    func testSpareWidthGoesToTheNameUpToTheCap() {
        let short = RowLayout.columns(statusLabels: ["done"], models: ["opus"],
                                      panelWidth: Constants.panelWidth)
        let long = RowLayout.columns(statusLabels: ["running bash"], models: ["opus"],
                                     panelWidth: Constants.panelWidth)
        XCTAssertEqual(short.name, RowLayout.maxNameWidth)
        XCTAssertEqual(long.name, RowLayout.maxNameWidth)
        XCTAssertEqual(short.name, long.name, "line 1's name no longer depends on line 2's status")
        XCTAssertGreaterThan(long.name, 105, "still beats the old fixed 105pt column")

        // Below the cap, a wider model word still takes from the name — this is
        // narrow enough that neither model saturates the cap.
        let narrow: CGFloat = 260
        let opusName = RowLayout.columns(statusLabels: ["done"], models: ["opus"], panelWidth: narrow).name
        let sonnetName = RowLayout.columns(statusLabels: ["done"], models: ["sonnet"], panelWidth: narrow).name
        XCTAssertLessThan(opusName, RowLayout.maxNameWidth, "test width chosen to sit below the cap")
        XCTAssertGreaterThan(opusName, sonnetName)

        // A longer status at the same narrow width leaves the name exactly alone.
        let opusNameLongStatus = RowLayout.columns(statusLabels: ["running bash"], models: ["opus"],
                                                    panelWidth: narrow).name
        XCTAssertEqual(opusName, opusNameLongStatus)
    }

    /// The name's floor wins on line 1, and the model is the one that gives way —
    /// status can't touch this anymore since it's budgeted entirely on line 2.
    func testNameFloorHoldsAndModelGivesWayOnLineOne() {
        let hugeModel = "m" + String(repeating: "x", count: 200)
        let c = RowLayout.columns(statusLabels: ["done"], models: [hugeModel], panelWidth: Constants.panelWidth)
        XCTAssertEqual(c.name, RowLayout.minNameWidth)
        XCTAssertEqual(c.model, Constants.panelWidth - Constants.rowFixedColumns - RowLayout.minNameWidth)
        XCTAssertGreaterThan(c.status, 0, "line 2's status is untouched by line 1's squeeze")
    }

    /// Line 1's columns must never exceed its own budget (`rowFixedColumns`
    /// doesn't include status or the context meter — those live on line 2 now).
    func testLine1ColumnsNeverOverrunTheirBudget() {
        let budget = Constants.panelWidth - Constants.rowFixedColumns
        for model in ["opus", "sonnet", "haiku", "", "m" + String(repeating: "x", count: 200)] {
            let c = RowLayout.columns(statusLabels: ["done"], models: [model], panelWidth: Constants.panelWidth)
            XCTAssertLessThanOrEqual(c.name + c.model, budget + 0.01, "\"\(model)\" overruns line 1")
            XCTAssertGreaterThanOrEqual(c.name, RowLayout.minNameWidth, "name floor broken")
            XCTAssertLessThanOrEqual(c.name, RowLayout.maxNameWidth, "name cap broken")
        }
    }

    func testChildRowIndentIsSixteen() {
        XCTAssertEqual(Constants.childRowIndent, 16)
    }

    /// Line 2's status must never exceed what that line actually has, once the
    /// context meter, the gaps, the working-dots slot, and the child indent (charged
    /// on every row so a depth-1 status cannot overflow) are accounted for.
    func testLine2StatusNeverOverrunsItsBudget() {
        let line2Budget = Constants.panelWidth - 2 * RowLayout.rowHorizontalPadding
            - RowLayout.secondRowLeadingInset - Constants.childRowIndent
            - RowLayout.contextSlot
            - 3 * RowLayout.lineTwoGap - RowLayout.dotsSlot
        for label in ["done", "needs input", "running bash", "running TodoWrite",
                      "running " + String(repeating: "x", count: 200)] {
            let c = RowLayout.columns(statusLabels: [label], models: ["opus"], panelWidth: Constants.panelWidth)
            XCTAssertLessThanOrEqual(c.status, max(0, line2Budget) + 0.01, "\"\(label)\" overruns line 2")
        }
    }

    /// Status is sized purely from its own line-2 budget now — a longer label
    /// simply claims more of that budget, not "freed" slack from a shorter name
    /// (that coupling existed pre-fix-2 and no longer does).
    func testStatusWidthReflectsItsOwnLabelNotTheNameColumn() {
        let short = RowLayout.columns(statusLabels: ["done"], models: ["opus"],
                                      panelWidth: Constants.panelWidth)
        let long = RowLayout.columns(statusLabels: ["running TodoWrite"], models: ["opus"],
                                     panelWidth: Constants.panelWidth)
        XCTAssertGreaterThan(long.status, short.status)
        XCTAssertLessThanOrEqual(long.name, RowLayout.maxNameWidth)
        XCTAssertEqual(long.name, short.name, "line 1's name doesn't depend on line 2's status at all")
    }

    /// An empty panel has nothing to measure on either line — line 1's name takes
    /// the whole remaining budget (capped), line 2's status is empty.
    func testEmptyPanelStillProducesASaneBudget() {
        let c = RowLayout.columns(statusLabels: [], models: [],
                                  panelWidth: Constants.panelWidth)
        XCTAssertEqual(c.model, 0)
        XCTAssertEqual(c.name, min(RowLayout.maxNameWidth, Constants.panelWidth - Constants.rowFixedColumns))
        XCTAssertEqual(c.status, 0)
    }

    /// The clamp keeps the panel on screen: capped at the preferred width, floored
    /// at `panelMinWidth`, and reduced by the margin in between.
    func testFittedPanelWidthClampsToScreen() {
        XCTAssertEqual(Constants.fittedPanelWidth(visibleWidth: nil), Constants.panelWidth)
        XCTAssertEqual(Constants.fittedPanelWidth(visibleWidth: 1440), Constants.panelWidth)
        XCTAssertEqual(Constants.fittedPanelWidth(visibleWidth: 400),
                       400 - Constants.panelScreenMargin)
        XCTAssertEqual(Constants.fittedPanelWidth(visibleWidth: 200), Constants.panelMinWidth)
    }

    /// A name that fits is untouched; one that doesn't ends in `..` and still fits
    /// the column. The pair matters: a truncator that always cuts is as wrong as one
    /// that never does.
    func testFitNameCutsOnlyWhenItMustAndMarksTheCut() {
        let wide: CGFloat = 400
        XCTAssertEqual(RowLayout.fitName("bin", toWidth: wide), "bin")

        let narrow = RowLayout.maxNameWidth
        let long = "claude-spinner-dashboard"
        let cut = RowLayout.fitName(long, toWidth: narrow)
        XCTAssertNotEqual(cut, long)
        XCTAssertTrue(cut.hasSuffix(".."))
        XCTAssertLessThanOrEqual(RowLayout.width(for: cut), narrow)
        // The cut keeps as much of the name as the column can hold.
        XCTAssertTrue(long.hasPrefix(cut.dropLast(2)))
    }

    /// A column too narrow to hold even the marker returns the name unchanged rather
    /// than a string that is nothing but dots.
    func testFitNameLeavesUnusablyNarrowColumnsAlone() {
        XCTAssertEqual(RowLayout.fitName("bin", toWidth: 4), "bin")
        XCTAssertEqual(RowLayout.fitName("bin", toWidth: 0), "bin")
    }

    /// The name column is capped now, and the cap is what the row honours.
    func testColumnsCapTheNameWidth() {
        let c = RowLayout.columns(statusLabels: ["idle"], models: ["opus"],
                                  panelWidth: Constants.panelWidth)
        XCTAssertLessThanOrEqual(c.name, RowLayout.maxNameWidth)
    }

    /// Only a grouped row pays for the `×N` badge.
    func testCountBadgeWidthIsChargedOnlyWhenGrouped() {
        XCTAssertEqual(RowLayout.countBadgeWidth(1), 0)
        XCTAssertGreaterThan(RowLayout.countBadgeWidth(2), 0)
        XCTAssertGreaterThan(RowLayout.countBadgeWidth(10), RowLayout.countBadgeWidth(2))
    }

    /// Parent `ids` include children so `clear()` cascades, but that is not an
    /// idle-collapse group. The `×N` badge keys off `showsCountBadge`, not `count`.
    func testCountBadgeIsIdleCollapseOnly() {
        let now = Date()
        let parent = FeedWatcher.displayItems(from: [
            mk("p", .thinking, cwd: "/p", updated: now),
            mk("p.a1", .tool, cwd: "/p", updated: now,
               parentSessionId: "p", agentId: "a1", agentType: "Explore"),
            mk("p.a2", .idle, cwd: "/p", updated: now, lastDuration: 2,
               parentSessionId: "p", agentId: "a2", agentType: "Plan"),
        ])[0]
        XCTAssertEqual(parent.count, 3)
        XCTAssertEqual(parent.subagentCount, 2)
        XCTAssertFalse(parent.showsCountBadge)

        let collapsed = FeedWatcher.displayItems(from: [
            mk("a", .idle, cwd: "/home", updated: now, lastDuration: 5),
            mk("b", .idle, cwd: "/home", updated: now.addingTimeInterval(-1), lastDuration: 3),
        ])[0]
        XCTAssertEqual(collapsed.count, 2)
        XCTAssertEqual(collapsed.subagentCount, 0)
        XCTAssertTrue(collapsed.showsCountBadge)

        let single = FeedWatcher.displayItems(from: [
            mk("w", .thinking, cwd: "/x", updated: now),
        ])[0]
        XCTAssertFalse(single.showsCountBadge)

        let orphan = FeedWatcher.displayItems(from: [
            mk("orphan", .tool, cwd: "/x", updated: now,
               parentSessionId: "missing", agentId: "a1", agentType: "Explore"),
        ])[0]
        XCTAssertFalse(orphan.showsCountBadge)
    }

    /// Regression guard for the 2026-08-15 second-row jitter: the working-dots
    /// `Text` needs a real, positive fixed height (not just width), or its empty
    /// phase can size shorter than its non-empty phases and the whole row (and
    /// everything below it) pulses in place every ~0.5s. A font's ascender sits
    /// above the baseline and its descender below, so this is the one measured
    /// constant in the file where a naive sum would double-count -- subtracting
    /// (descender is already negative) is deliberate, not a typo.
    func testLineHeightIsPositiveAndAtLeastTheFontSize() {
        XCTAssertGreaterThan(RowLayout.lineHeight, 11,
                             "line height should be at least the 11pt font size")
    }

    /// The stored surface preference round-trips, and anything else -- an absent key
    /// on first launch, a value from a future version -- lands on the menu bar rather
    /// than on a surface the user never chose. Mirrors the `?? .menuBar` in `init`.
    func testSurfacePreferenceDefaultsToMenuBar() {
        XCTAssertEqual(Surface(rawValue: "menuBar"), .menuBar)
        XCTAssertEqual(Surface(rawValue: "window"), .window)

        let absent: String? = nil
        XCTAssertEqual(absent.flatMap(Surface.init(rawValue:)) ?? .menuBar, .menuBar)
        let unknown: String? = "sidebar"
        XCTAssertEqual(unknown.flatMap(Surface.init(rawValue:)) ?? .menuBar, .menuBar)
    }

    /// The unplaced case, at the geometry actually measured on 2026-08-12: the item
    /// parked 1090pt below the bar at x=-1 on a 1512x982 screen.
    func testStatusItemUnplacedDetectsAParkedItem() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let parked = CGRect(x: -1, y: 982 - 1090 - 20, width: 131, height: 20)
        XCTAssertTrue(Constants.statusItemIsUnplaced(itemFrame: parked, screenFrame: screen))
    }

    /// The other half of the pair: a placed item must read as placed, or the fallback
    /// window opens over a perfectly good menu bar icon. The notched case is the one
    /// the previous `NSStatusBar.system.thickness` cutoff got wrong -- there the bar
    /// is ~37pt tall while thickness still reports 24.
    func testStatusItemUnplacedAcceptsAPlacedItem() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let placed = CGRect(x: 1200, y: 982 - 24, width: 131, height: 24)
        XCTAssertFalse(Constants.statusItemIsUnplaced(itemFrame: placed, screenFrame: screen))

        let notched = CGRect(x: 1200, y: 982 - 37, width: 131, height: 37)
        XCTAssertFalse(Constants.statusItemIsUnplaced(itemFrame: notched, screenFrame: screen))
    }

    /// The slack absorbs rounding on a scaled display and nothing wider.
    func testStatusItemUnplacedHonoursTheSlack() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        func item(droppedBy drop: CGFloat) -> CGRect {
            CGRect(x: 1200, y: 982 - 24 - drop, width: 131, height: 24)
        }
        XCTAssertFalse(Constants.statusItemIsUnplaced(
            itemFrame: item(droppedBy: Constants.statusItemPlacementSlack),
            screenFrame: screen))
        XCTAssertTrue(Constants.statusItemIsUnplaced(
            itemFrame: item(droppedBy: Constants.statusItemPlacementSlack + 1),
            screenFrame: screen))
    }

    /// A second display sits above or beside the main one, so the top edge that
    /// matters is that screen's -- not the origin's.
    func testStatusItemUnplacedUsesTheItemsOwnScreen() {
        let secondary = CGRect(x: 1512, y: 200, width: 1920, height: 1080)
        let placed = CGRect(x: 3000, y: 200 + 1080 - 24, width: 131, height: 24)
        XCTAssertFalse(Constants.statusItemIsUnplaced(itemFrame: placed, screenFrame: secondary))
    }

    /// At the narrowest clamped width, line 1's budget still holds when the squeeze
    /// comes from a giant model word: the name keeps its floor and the model sheds
    /// exactly enough to protect it.
    func testLine1ColumnsHoldAtMinWidthWithAGiantModel() {
        let c = RowLayout.columns(
            statusLabels: ["done"],
            models: ["m" + String(repeating: "x", count: 200)], panelWidth: Constants.panelMinWidth)
        XCTAssertEqual(c.name, RowLayout.minNameWidth)
        XCTAssertEqual(c.model, Constants.panelMinWidth - Constants.rowFixedColumns - RowLayout.minNameWidth)
        XCTAssertEqual(c.name + c.model, Constants.panelMinWidth - Constants.rowFixedColumns, accuracy: 0.01)
    }

    /// And at that same narrow width, line 2's status still clamps to its own
    /// budget independent of line 1 — a giant status label doesn't touch the
    /// name/model split, only its own line.
    func testLine2StatusHoldsAtMinWidthWithAGiantStatus() {
        let c = RowLayout.columns(
            statusLabels: ["running " + String(repeating: "x", count: 200)],
            models: ["sonnet"], panelWidth: Constants.panelMinWidth)
        XCTAssertEqual(c.name, RowLayout.maxNameWidth, "model is short, so name saturates the cap")
        let line2Budget = Constants.panelMinWidth - 2 * RowLayout.rowHorizontalPadding
            - RowLayout.secondRowLeadingInset - Constants.childRowIndent
            - RowLayout.contextSlot
            - 3 * RowLayout.lineTwoGap - RowLayout.dotsSlot
            - RowLayout.evidenceSlot
        XCTAssertEqual(c.status, max(0, line2Budget), accuracy: 0.01)
    }

    /// A tool name too long for its column is cut to fit here, so SwiftUI's own
    /// tail `…` never renders beside the animated working-dots (the `running
    /// askuserqu……` double-ellipsis bug). The cut leaves `statusSlack` of
    /// headroom, and a label that already fits passes through untouched.
    func testLongStatusLabelIsPreTruncatedToItsColumn() {
        let long = "running mcp__claude_ai_Google_Calendar__list_events"
        let c = RowLayout.columns(statusLabels: [long], models: ["opus"],
                                  panelWidth: Constants.panelWidth)
        let w = c.status

        let fitted = RowLayout.fit(long, toWidth: w)
        XCTAssertLessThan(fitted.count, long.count, "long label should be cut")
        // Fits with headroom — SwiftUI won't reach for its `…` and collide with the dots.
        XCTAssertLessThanOrEqual(CGFloat(fitted.count) * RowLayout.monoAdvance,
                                 w - RowLayout.statusSlack)

        // A label that already fits is returned verbatim.
        XCTAssertEqual(RowLayout.fit("running bash", toWidth: w), "running bash")
        XCTAssertEqual(RowLayout.fit("done", toWidth: w), "done")
    }

    /// The label the layout measures must be the label the row draws.
    func testStatusLabelMatchesWhatTheRowShows() {
        var s = SessionFeed(id: "a")
        s.status = .attention;  XCTAssertEqual(s.statusLabel, "needs input")
        s.status = .thinking;   XCTAssertEqual(s.statusLabel, "thinking")
        s.status = .tool; s.tool = "bash"; XCTAssertEqual(s.statusLabel, "running bash")
        s.tool = "";            XCTAssertEqual(s.statusLabel, "running")
        s.status = .idle;       XCTAssertEqual(s.statusLabel, "idle")
        s.lastDuration = 5;     XCTAssertEqual(s.statusLabel, "done")
    }

    func testTrendGaugeDoesNotSaturateAboveTwentyPoints() {
        // The bug: a linear 20-point scale drew +20 and +52 identically.
        let twenty = TrendGauge.fillFraction(delta: 20)
        let fiftyTwo = TrendGauge.fillFraction(delta: 52)
        XCTAssertGreaterThan(fiftyTwo, twenty)
        // Separated by enough of the 45pt track to read as different bars.
        XCTAssertGreaterThan((fiftyTwo - twenty) * Constants.usageTrackWidth, 8)
    }

    func testTrendGaugeFillIsSignAgnosticAndClamped() {
        XCTAssertEqual(TrendGauge.fillFraction(delta: -30),
                       TrendGauge.fillFraction(delta: 30))     // magnitude only
        XCTAssertEqual(TrendGauge.fillFraction(delta: 0), 0)
        XCTAssertEqual(TrendGauge.fillFraction(delta: 100), 1)
        XCTAssertEqual(TrendGauge.fillFraction(delta: 250), 1) // clamped, not >1
    }

    func testTrendGaugeKeepsResolutionAtSmallDeltas() {
        // Square root's payoff: single-digit moves stay apart rather than all
        // collapsing onto the 3pt minimum sliver.
        let three = TrendGauge.fillFraction(delta: 3)
        let eight = TrendGauge.fillFraction(delta: 8)
        XCTAssertGreaterThan((eight - three) * Constants.usageTrackWidth, 2)
    }

    func testContextTokensIsNilUntilReported() {
        XCTAssertNil(mk("a", .tool).contextTokens)
        XCTAssertEqual(mk("a", .tool, tokens: 0).contextTokens, 0)
        var s = mk("a", .tool, tokens: 100)
        s.contextOutputTokens = 25
        XCTAssertEqual(s.contextTokens, 125)
    }

    /// Banded on absolute tokens, not percentage — 200k is heavy on a 1m window too.
    func testContextTintTiers() {
        XCTAssertEqual(Color.contextTint(0), Color.contextTint(99_999))          // green band
        XCTAssertNotEqual(Color.contextTint(99_999), Color.contextTint(100_000)) // -> yellow
        XCTAssertEqual(Color.contextTint(100_000), Color.contextTint(149_999))   // yellow band
        XCTAssertNotEqual(Color.contextTint(149_999), Color.contextTint(150_000))// -> amber
        XCTAssertEqual(Color.contextTint(150_000), Color.contextTint(199_999))   // amber band
        XCTAssertNotEqual(Color.contextTint(199_999), Color.contextTint(200_000))// -> red
        XCTAssertEqual(Color.contextTint(200_000), Color.contextTint(999_999))   // red band
    }

    // MARK: - UsagePoller.parse (pure header -> Result mapping)

    /// Utilization is a 0.0–1.0 fraction; parse scales to a rounded percentage.
    func testParseMapsUtilizationToPercent() {
        let now = Date(timeIntervalSince1970: 42)
        let r = UsagePoller.parse(headers: [
            "anthropic-ratelimit-unified-5h-utilization": "0.42",
            "anthropic-ratelimit-unified-7d-utilization": "0.8",
        ], now: now)
        XCTAssertEqual(r?.fiveHourPct, 42)
        XCTAssertEqual(r?.sevenDayPct, 80)
        XCTAssertEqual(r?.fetchedAt, now)               // now echoes through unchanged
    }

    /// (u * 100).rounded() rounds to nearest, ties away from zero.
    func testParseRounding() {
        func pct(_ u5: String, _ u7: String) -> (Int?, Int?) {
            let r = UsagePoller.parse(headers: [
                "anthropic-ratelimit-unified-5h-utilization": u5,
                "anthropic-ratelimit-unified-7d-utilization": u7,
            ], now: Date())
            return (r?.fiveHourPct, r?.sevenDayPct)
        }
        XCTAssertEqual(pct("0.005", "0.004").0, 1)      // 0.5 -> away from zero -> 1
        XCTAssertEqual(pct("0.005", "0.004").1, 0)      // 0.4 -> 0
    }

    /// Either utilization key missing means the whole parse fails (nil).
    func testParseReturnsNilWhenUtilizationMissing() {
        let now = Date()
        XCTAssertNil(UsagePoller.parse(headers: [
            "anthropic-ratelimit-unified-7d-utilization": "0.5",
        ], now: now))                                   // no 5h
        XCTAssertNil(UsagePoller.parse(headers: [
            "anthropic-ratelimit-unified-5h-utilization": "0.5",
        ], now: now))                                   // no 7d
        XCTAssertNil(UsagePoller.parse(headers: [:], now: now))
    }

    /// overageBlocked is true only for the exact "rejected" status.
    func testParseOverageBlocked() {
        func blocked(_ status: String?) -> Bool? {
            var h = [
                "anthropic-ratelimit-unified-5h-utilization": "0.1",
                "anthropic-ratelimit-unified-7d-utilization": "0.1",
            ]
            if let status { h["anthropic-ratelimit-unified-overage-status"] = status }
            return UsagePoller.parse(headers: h, now: Date())?.overageBlocked
        }
        XCTAssertEqual(blocked("rejected"), true)
        XCTAssertEqual(blocked("allowed"), false)
        XCTAssertEqual(blocked(nil), false)             // absent -> not blocked
    }

    /// Reset instants pass through as-is; absent -> nil.
    func testParseResetInstants() {
        let withResets = UsagePoller.parse(headers: [
            "anthropic-ratelimit-unified-5h-utilization": "0.1",
            "anthropic-ratelimit-unified-7d-utilization": "0.1",
            "anthropic-ratelimit-unified-5h-reset": "1000",
            "anthropic-ratelimit-unified-7d-reset": "2000",
        ], now: Date())
        XCTAssertEqual(withResets?.fiveHourResetsAt, 1000)
        XCTAssertEqual(withResets?.sevenDayResetsAt, 2000)

        let noResets = UsagePoller.parse(headers: [
            "anthropic-ratelimit-unified-5h-utilization": "0.1",
            "anthropic-ratelimit-unified-7d-utilization": "0.1",
        ], now: Date())
        XCTAssertNil(noResets?.fiveHourResetsAt)
        XCTAssertNil(noResets?.sevenDayResetsAt)
    }

    // MARK: - HostTag (host string -> row chip bucket)

    func testHostTagClassifiesKnownHosts() {
        XCTAssertEqual(HostTag.from("com.microsoft.VSCode"), .vsc)
        XCTAssertEqual(HostTag.from("vscode"), .vsc)
        XCTAssertEqual(HostTag.from("Cursor"), .vsc)
        XCTAssertEqual(HostTag.from("dev.zed.Zed"), .vsc)          // __CFBundleIdentifier
        XCTAssertEqual(HostTag.from("dev.zed.Zed-Preview"), .vsc)
        XCTAssertEqual(HostTag.from("zed"), .vsc)                 // TERM_PROGRAM
        XCTAssertEqual(HostTag.from("com.mitchellh.ghostty"), .trm)
        XCTAssertEqual(HostTag.from("Apple_Terminal"), .trm)
        XCTAssertEqual(HostTag.from("iTerm.app"), .trm)
        XCTAssertEqual(HostTag.from("com.anthropic.claudefordesktop"), .app)
        XCTAssertEqual(HostTag.from("claude.ai"), .web)
    }

    func testHostTagUnknownAndEmptyReturnNil() {
        XCTAssertNil(HostTag.from(""))
        XCTAssertNil(HostTag.from("some.unknown.bundle"))
    }

    /// "zed" is short enough to appear inside unrelated hosts, and the editor branch
    /// runs before the terminal one — so it must match exactly, not by `contains`.
    func testHostTagDoesNotClaimEveryHostContainingZed() {
        XCTAssertNil(HostTag.from("com.example.customized"))
        XCTAssertEqual(HostTag.from("com.zedterm.ghostty"), .trm)
    }

    // MARK: - SessionLauncher.resolveBundleID (host string -> app to focus)

    private let never: (String) -> Bool = { _ in false }
    private let always: (String) -> Bool = { _ in true }

    func testResolveBundleIDPrefersTheKnownTable() {
        XCTAssertEqual(SessionLauncher.resolveBundleID(
            host: "vscode", fallback: "com.apple.Terminal", isRunning: never),
            "com.microsoft.VSCode")
        XCTAssertEqual(SessionLauncher.resolveBundleID(
            host: "dev.zed.Zed", fallback: "com.apple.Terminal", isRunning: never),
            "dev.zed.Zed")
    }

    /// The Zed regression: a GUI editor missing from the table reports its own
    /// bundle ID as the host, so it must resolve to itself rather than taking the
    /// terminal fallback and opening a new Ghostty window (bug-072/091/110 class).
    func testResolveBundleIDFocusesAnUntabledEditorThatIsRunning() {
        XCTAssertEqual(SessionLauncher.resolveBundleID(
            host: "com.todesktop.230313mzl4w4u92",  // Cursor, not in the table
            fallback: "com.mitchellh.ghostty", isRunning: always),
            "com.todesktop.230313mzl4w4u92")
    }

    func testResolveBundleIDFallsBackForUnplaceableHosts() {
        // A TERM_PROGRAM value is never a bundle ID, so nothing is running under it.
        XCTAssertEqual(SessionLauncher.resolveBundleID(
            host: "some_unknown_term", fallback: "com.mitchellh.ghostty", isRunning: never),
            "com.mitchellh.ghostty")
        XCTAssertEqual(SessionLauncher.resolveBundleID(
            host: "", fallback: "com.apple.Terminal", isRunning: always),
            "com.apple.Terminal")
    }

    // MARK: - UsageFailure (why usage stopped refreshing)

    /// The header word must tell an expired token apart from a dropped connection:
    /// one needs the user to act, the other clears itself on the next poll.
    func testUsageFailureDistinguishesAuthFromTransient() {
        XCTAssertEqual(UsageFailure.authExpired.notice, "expired")
        XCTAssertEqual(UsageFailure.transient("offline").notice, "error")
        XCTAssertTrue(UsageFailure.transient("HTTP 529").detail.contains("HTTP 529"))
    }

    // MARK: - FeedWatcher.trend (reset-aware 5h delta)

    private func sample(_ pct: Int, _ at: Double) -> UsageSample { UsageSample(pct: pct, at: at) }

    func testTrendPlainClimb() {
        XCTAssertEqual(FeedWatcher.trend(from: [sample(79, 0), sample(89, 300)]), 10)
    }

    func testTrendIgnoresPreResetValueWhenNothingFollowsTheReset() {
        // A reset drop with no sample after it isn't a meaningful trend yet.
        XCTAssertNil(FeedWatcher.trend(from: [sample(90, 0), sample(5, 300)]))
    }

    func testTrendDiffsFromTheResetPointNotTheWindowStart() {
        XCTAssertEqual(FeedWatcher.trend(from: [sample(90, 0), sample(5, 300), sample(12, 600)]), 7)
    }

    func testTrendSmallDipIsNotMistakenForAReset() {
        XCTAssertEqual(FeedWatcher.trend(from: [sample(50, 0), sample(55, 300), sample(48, 600)]), -2)
    }

    func testTrendNeedsAtLeastTwoSamples() {
        XCTAssertNil(FeedWatcher.trend(from: []))
        XCTAssertNil(FeedWatcher.trend(from: [sample(80, 0)]))
    }

    // MARK: - FeedWatcher.workingDots (animated working-row indicator)

    func testWorkingDotsCyclesThreePhases() {
        let d0 = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(FeedWatcher.workingDots(at: d0), ".")
        XCTAssertEqual(FeedWatcher.workingDots(at: d0.addingTimeInterval(0.5)), "..")
        XCTAssertEqual(FeedWatcher.workingDots(at: d0.addingTimeInterval(1.0)), "")
        XCTAssertEqual(FeedWatcher.workingDots(at: d0.addingTimeInterval(1.5)), ".")
    }

    // MARK: - SessionLauncher.guiFocusAction (running instance wins over path launch)

    /// Regression guard for bug-072/073/091: a running VS Code/Ghostty/Claude-Desktop
    /// must be activated in place, NOT relaunched with a path (which opens a new window).
    /// This ordering has silently regressed every time the focus branch was refactored.
    func testGUIFocusActivatesRunningInstanceEvenWhenCwdIsSet() {
        XCTAssertEqual(SessionLauncher.guiFocusAction(isRunning: true, cwd: "/some/proj"), .activateRunning)
        XCTAssertEqual(SessionLauncher.guiFocusAction(isRunning: true, cwd: ""), .activateRunning)
    }

    /// A path launch (new window) is used only when the app isn't already running.
    func testGUIFocusLaunchesWithPathOnlyWhenNotRunning() {
        XCTAssertEqual(SessionLauncher.guiFocusAction(isRunning: false, cwd: "/some/proj"), .openPath)
        XCTAssertEqual(SessionLauncher.guiFocusAction(isRunning: false, cwd: ""), .launchBare)
    }

    // MARK: - Session actions

    private func actionable(pid: Int? = 7190,
                            status: SessionStatus = .idle,
                            cwd: String = "/tmp/proj",
                            transcript: String? = "/tmp/t.jsonl") -> SessionFeed {
        var s = SessionFeed(id: "sid")
        s.pid = pid
        s.status = status
        s.cwd = cwd
        s.stats.transcriptPath = transcript
        return s
    }

    /// Not "is it disabled" but "does it say why". A greyed-out button with no
    /// reason is what makes people click twice and assume the app is broken —
    /// and the commonest reason here is permanent, not temporary.
    func testTypedActionsExplainThemselvesWithoutAPane() {
        for action in [SessionAction.interrupt, .compact, .clear] {
            XCTAssertEqual(
                SessionActions.unavailableReason(action, session: actionable(), hasPane: false),
                "That session isn't in a tmux pane, so there's nowhere to type.",
                "\(action.title) must say why it can't run")
        }
    }

    /// Interrupt is the one action FOR a running turn; the other two type at the
    /// prompt and need it free. Getting this backwards would offer /clear
    /// mid-turn and interrupt with nothing running.
    func testInterruptAndTheSlashCommandsWantOppositeStates() {
        let running = actionable(status: .tool)
        XCTAssertNil(SessionActions.unavailableReason(.interrupt, session: running, hasPane: true))
        XCTAssertEqual(SessionActions.unavailableReason(.clear, session: running, hasPane: true),
                       "That session is mid-turn — wait for it to finish.")

        let idle = actionable(status: .idle)
        XCTAssertEqual(SessionActions.unavailableReason(.interrupt, session: idle, hasPane: true),
                       "Nothing is running to interrupt.")
        XCTAssertNil(SessionActions.unavailableReason(.clear, session: idle, hasPane: true))
    }

    /// The bug this exists for: `.attention` means the session is sitting at its
    /// prompt waiting on a person, which is exactly when typing works. Gating on
    /// `status == .idle` greyed out the slash commands — and the reply box —
    /// on the one session you most want to answer.
    func testASessionWaitingOnYouCanBeTypedInto() {
        let waiting = actionable(status: .attention)
        XCTAssertTrue(waiting.isAtPrompt)
        XCTAssertNil(SessionActions.unavailableReason(.clear, session: waiting, hasPane: true))
        XCTAssertNil(SessionActions.unavailableReason(.compact, session: waiting, hasPane: true))
    }

    func testAWorkingSessionIsNotAtItsPrompt() {
        for status in [SessionStatus.thinking, .tool] {
            var s = SessionFeed(id: "s")
            s.status = status
            XCTAssertFalse(s.isAtPrompt, "\(status) is mid-turn")
        }
    }

    /// The local actions touch only this Mac, so a missing pane is irrelevant to
    /// them — but missing data is not.
    func testLocalActionsIgnoreThePaneAndCheckTheirOwnInputs() {
        XCTAssertNil(SessionActions.unavailableReason(.copySessionID,
                                                      session: actionable(pid: nil),
                                                      hasPane: false))
        XCTAssertEqual(SessionActions.unavailableReason(.revealCWD,
                                                        session: actionable(cwd: ""),
                                                        hasPane: true),
                       "This session has no working directory yet.")
        XCTAssertEqual(SessionActions.unavailableReason(.openTranscript,
                                                        session: actionable(transcript: nil),
                                                        hasPane: true),
                       "No transcript yet — the statusLine hasn't reported.")
    }

    /// The two that throw away unrecoverable context must confirm, and they sit
    /// a few pixels from Interrupt, which must not.
    func testOnlyTheContextDiscardingActionsConfirm() {
        XCTAssertTrue(SessionAction.clear.isDestructive)
        XCTAssertTrue(SessionAction.compact.isDestructive)
        XCTAssertNotNil(SessionAction.clear.confirmation)
        XCTAssertFalse(SessionAction.interrupt.isDestructive)
        XCTAssertNil(SessionAction.interrupt.confirmation)
    }

    /// Interrupt cancels a turn rather than submitting anything, so it must send
    /// no text at all — a stray Enter would submit whatever was in the prompt.
    func testInterruptTypesNothing() {
        XCTAssertNil(SessionAction.interrupt.promptText)
        XCTAssertEqual(SessionAction.compact.promptText, "/compact")
        XCTAssertEqual(SessionAction.clear.promptText, "/clear")
    }

    // MARK: - TranscriptReader

    /// Records in the real shapes the transcript actually uses, taken from a
    /// live file rather than invented.
    private var transcriptLines: [String] {[
        #"{"type":"ai-title","aiTitle":"spinner-notification-feedback-loop","sessionId":"s"}"#,
        #"{"type":"last-prompt","lastPrompt":"why is it 90$ i have max plan?","sessionId":"s"}"#,
        #"{"type":"permission-mode","permissionMode":"bypassPermissions","sessionId":"s"}"#,
        #"{"type":"assistant","gitBranch":"notification-answers","version":"2.1.260","timestamp":"2026-09-04T06:40:00.000Z","message":{"usage":{"cache_read_input_tokens":379956,"cache_creation_input_tokens":3027,"output_tokens":1410,"output_tokens_details":{"thinking_tokens":386}},"content":[{"type":"thinking","thinking":"weighing it"},{"type":"text","text":"That is not a bill."},{"type":"tool_use","name":"Bash"}]}}"#,
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}"#,
    ]}

    private func lastPrompt(_ lines: [String]) -> String? {
        TranscriptReader.parse(lines.joined(separator: "\n"), droppingFirstLine: false).lastPrompt
    }

    /// Shapes from the 2026-09-30 transcript where the card read "/compact" through
    /// a later /goal and three mid-turn questions: the stale record came last.
    func testATypedSlashCommandBeatsAStaleLastPromptRecord() {
        XCTAssertEqual(lastPrompt([
            #"{"type":"user","message":{"role":"user","content":"<command-message>goal</command-message>\n<command-name>/goal</command-name>\n<command-args>120</command-args>"}}"#,
            #"{"type":"user","isMeta":true,"message":{"role":"user","content":"You are operating in FULL AUTONOMOUS mode."}}"#,
            #"{"type":"last-prompt","lastPrompt":"/compact"}"#,
        ]), "/goal 120")
    }

    func testAPromptTypedMidTurnIsTheLastPrompt() {
        XCTAssertEqual(lastPrompt([
            #"{"type":"user","message":{"role":"user","content":"<command-name>/goal</command-name>"}}"#,
            #"{"type":"attachment","attachment":{"type":"queued_command","prompt":"wheres goal indicator","origin":{"kind":"human"}}}"#,
            #"{"type":"attachment","attachment":{"type":"queued_command","prompt":"<task-notification>done</task-notification>","origin":{"kind":"task-notification"}}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"last-prompt","lastPrompt":"/compact"}"#,
        ]), "wheres goal indicator")
    }

    private func transcriptFile(_ lines: [String]) -> String {
        let path = NSTemporaryDirectory() + "prompt-\(UUID().uuidString).jsonl"
        FileManager.default.createFile(atPath: path, contents: Data((lines.joined(separator: "\n") + "\n").utf8))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    private func append(_ text: String, to path: String) {
        let h = FileHandle(forWritingAtPath: path)!
        h.seekToEndOfFile(); h.write(Data(text.utf8)); h.closeFile()
    }

    /// Screenshots pushed the real prompt 2 MB back while the stale record kept
    /// landing inside the tail; the tail alone read "/compact".
    func testATypedPromptBehindTheTailStillWins() {
        let filler = #"{"type":"assistant","message":{"content":[{"type":"text","text":""# + String(repeating: "x", count: 4000) + #""}]}}"#
        let path = transcriptFile(
            [#"{"type":"user","message":{"role":"user","content":"<command-name>/goal</command-name>\n<command-args>120</command-args>"}}"#]
            + Array(repeating: filler, count: 10)
            + [#"{"type":"last-prompt","lastPrompt":"/compact"}"#])
        XCTAssertEqual(TranscriptReader.read(path: path, tailBytes: 2048).lastPrompt, "/goal 120")
    }

    /// A prompt with a pasted image can be one record longer than a scan chunk:
    /// over two, so one whole chunk falls inside it and holds no newline.
    func testATypedPromptLongerThanAScanChunkIsStillFound() {
        let image = String(repeating: "A", count: 2 * TranscriptReader.promptChunk + 500_000)
        let path = transcriptFile([
            #"{"type":"user","message":{"role":"user","content":"older"}}"#,
            #"{"type":"attachment","attachment":{"type":"queued_command","prompt":[{"type":"text","text":"look at this"},{"type":"image","data":""# + image + #""}],"origin":{"kind":"human"}}}"#,
            #"{"type":"last-prompt","lastPrompt":"/compact"}"#,
        ])
        XCTAssertEqual(TranscriptReader.read(path: path, tailBytes: 2048).lastPrompt, "look at this")
    }

    func testAPromptAppendedLaterIsPickedUpAndAHalfWrittenOneWaits() {
        let path = transcriptFile([#"{"type":"user","message":{"role":"user","content":"first"}}"#])
        XCTAssertEqual(TranscriptReader.read(path: path).lastPrompt, "first")
        let record = #"{"type":"attachment","attachment":{"type":"queued_command","prompt":"second","origin":{"kind":"human"}}}"#
        append(String(record.prefix(30)), to: path)
        XCTAssertEqual(TranscriptReader.read(path: path).lastPrompt, "first", "half a record is not read yet")
        append(String(record.dropFirst(30)) + "\n", to: path)
        XCTAssertEqual(TranscriptReader.read(path: path).lastPrompt, "second")
    }

    /// Shapes the review found in real transcripts: a `!` command is the prompt,
    /// its output and app-injected notices are not.
    func testAShellCommandIsAPromptButItsOutputIsNot() {
        XCTAssertEqual(lastPrompt([
            #"{"type":"user","message":{"role":"user","content":"<bash-input>git status</bash-input>"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<bash-stdout>On branch main</bash-stdout><bash-stderr></bash-stderr>"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<ci-monitor-event>CI passed</ci-monitor-event>"}}"#,
            #"{"type":"user","message":{"role":"user","content":"The app was quit while you were working. Please continue from where you left off."}}"#,
        ]), "! git status")
    }

    func testHarnessUserRecordsAreNotPrompts() {
        XCTAssertEqual(lastPrompt([
            #"{"type":"last-prompt","lastPrompt":"fix the chart"}"#,
            #"{"type":"user","message":{"role":"user","content":"[Request interrupted by user]"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<local-command-stdout>Compacted</local-command-stdout>"}}"#,
            #"{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued"}}"#,
        ]), "fix the chart", "with no typed prompt in the tail, the record is the fallback")
    }

    func testTranscriptParsePullsOutWhatTheSessionIsDoing() {
        let snap = TranscriptReader.parse(transcriptLines.joined(separator: "\n"),
                                          droppingFirstLine: false)
        XCTAssertEqual(snap.title, "spinner-notification-feedback-loop")
        XCTAssertEqual(snap.lastPrompt, "why is it 90$ i have max plan?")
        XCTAssertEqual(snap.permissionMode, "bypassPermissions")
        XCTAssertEqual(snap.lastAssistantText, "That is not a bill.")
        XCTAssertEqual(snap.lastThinking, "weighing it")
        XCTAssertEqual(snap.gitBranch, "notification-answers")
        XCTAssertEqual(snap.cacheReadTokens, 379_956)
        XCTAssertEqual(snap.thinkingTokens, 386)
        XCTAssertFalse(snap.isEmpty)
    }

    /// Wrapped up = the newest of {a /wrap-up, an edit} is the wrap-up. The
    /// typed command and the Skill tool both count; Bash (wrap-up's own
    /// commits) does not undo it.
    func testTranscriptKnowsWhenTheSessionWrappedUp() {
        let typed = #"{"type":"user","message":{"role":"user","content":"<command-message>wrap-up</command-message>\n<command-name>/wrap-up</command-name>"}}"#
        let skill = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"wrap-up"}}]}}"#
        let edit = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}"#
        let bash = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#
        func wrapped(_ lines: [String]) -> Bool {
            TranscriptReader.parse(lines.joined(separator: "\n"), droppingFirstLine: false).wrappedUp
        }
        XCTAssertTrue(wrapped([edit, typed, bash]))
        XCTAssertTrue(wrapped([edit, skill]))
        XCTAssertFalse(wrapped([typed, bash, edit]))
        XCTAssertFalse(wrapped([edit, bash]))
        XCTAssertFalse(wrapped(transcriptLines))
    }

    /// A turn of eight Bash calls filled the line with "Bash · Bash · Bash …"
    /// and said less than one count does.
    func testTranscriptCollapsesRunsOfTheSameTool() {
        let runs = (0..<8).map { _ in
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#
        } + [#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}"#]
        let snap = TranscriptReader.parse(runs.joined(separator: "\n"), droppingFirstLine: false)
        XCTAssertEqual(snap.recentTools, ["Edit", "Bash ×8"])
    }

    /// Newest first. Reading forwards would leave "last" holding the oldest
    /// value in the window, which is wrong in a way nothing else would catch.
    func testTranscriptTakesTheNewestToolFirst() {
        let snap = TranscriptReader.parse(transcriptLines.joined(separator: "\n"),
                                          droppingFirstLine: false)
        XCTAssertEqual(snap.recentTools.first, "Edit")
    }

    /// Seeking into the middle of a file lands mid-record, and that fragment is
    /// another record's tail rather than a truncated one to recover. Dropping it
    /// is the whole reason `droppingFirstLine` exists.
    func testTranscriptDropsThePartialFirstLineAfterASeek() {
        let text = (["ache_read_input_tokens\":1}}}"] + transcriptLines).joined(separator: "\n")
        let kept = TranscriptReader.parse(text, droppingFirstLine: true)
        XCTAssertEqual(kept.title, "spinner-notification-feedback-loop")

        // And without the flag the fragment is simply unparseable, never fatal.
        let sloppy = TranscriptReader.parse(text, droppingFirstLine: false)
        XCTAssertEqual(sloppy.title, "spinner-notification-feedback-loop")
    }

    /// A transcript that hasn't been written yet is a normal state for a session
    /// that just started, not an error.
    func testTranscriptReadsMissingFileAsEmptyRatherThanFailing() {
        let snap = TranscriptReader.read(path: "/nonexistent/transcript.jsonl")
        XCTAssertTrue(snap.isEmpty)
    }

    func testTranscriptToleratesGarbageLines() {
        let snap = TranscriptReader.parse("not json\n{\n" + transcriptLines[0],
                                          droppingFirstLine: false)
        XCTAssertEqual(snap.title, "spinner-notification-feedback-loop")
    }

    // MARK: - idle_prompt is not a question

    private func attention(_ type: String?, message: String = "") -> SessionFeed {
        var s = SessionFeed(id: "s")
        s.status = .attention
        s.notificationType = type
        s.message = message
        return s
    }

    /// The bug: emit.sh maps every Notification event to .attention, and
    /// idle_prompt is one of them — it fires 60s after a turn ENDS if you
    /// haven't typed. A finished session sat in the same orange row as one
    /// holding a permission prompt, with no way to tell which wanted an answer.
    func testAnIdlePromptIsNotBlockedOnYou() {
        XCTAssertFalse(attention("idle_prompt").isBlockedOnYou)
        XCTAssertTrue(attention("permission_prompt").isBlockedOnYou)
        XCTAssertTrue(attention("agent_needs_input").isBlockedOnYou)
        // Older feed files carry no type at all; assume it wants something.
        XCTAssertTrue(attention(nil).isBlockedOnYou)
    }

    func testAttentionSummarySaysWhichKindOfWaitingItIs() {
        XCTAssertEqual(attention("idle_prompt").attentionSummary,
                       "Finished — waiting at the prompt, nothing to answer")
        XCTAssertEqual(attention("permission_prompt").attentionSummary,
                       "Waiting for permission to run a tool")
        XCTAssertEqual(attention("permission_prompt", message: "Claude needs your permission to use Bash").attentionSummary,
                       "Claude needs your permission to use Bash")
        XCTAssertNil(SessionFeed(id: "s").attentionSummary, "not waiting at all")
    }

    /// emit.sh writes idle_prompt 60s after any finished turn, so counting every
    /// .attention as "needs you" lit the fleet bar for sessions nobody owed.
    func testFleetBarCountsOnlyBlockedSessionsAsNeedsYou() {
        func counts(_ s: [SessionFeed]) -> [String: Int] {
            Dictionary(uniqueKeysWithValues: SessionBreakdown.byStatus(s).map { ($0.label, $0.count) })
        }
        XCTAssertEqual(counts([attention("idle_prompt")]), ["idle": 1])
        XCTAssertEqual(counts([attention("permission_prompt")]), ["needs you": 1])
    }

    // MARK: - Which session the window opens on

    private func root(_ id: String, model: String? = nil,
                      updated: Date? = nil,
                      status: SessionStatus = .idle) -> SessionFeed {
        var s = SessionFeed(id: id)
        s.model = model
        s.updated = updated
        s.status = status
        return s
    }

    /// The bug this exists for: opening on whatever sorted first showed a
    /// session with no statusLine, so the pane rendered two rows and read as
    /// broken while a fully-reported session sat one row below.
    func testWindowOpensOnASessionThatHasSomethingToShow() {
        let picked = WindowContentView.defaultSelection(roots: [
            root("bare", model: nil, updated: Date()),
            root("reported", model: "Opus 5", updated: Date().addingTimeInterval(-60)),
        ], asks: [])
        XCTAssertEqual(picked?.id, "reported")
    }

    /// The Home tab is not a session, so the pane must not fall through to one:
    /// doing that would put a session's toolbar and probes behind the dashboard.
    func testTheHomeTagResolvesToNoSession() {
        let roots = [root("reported", model: "Opus 5", updated: Date())]
        XCTAssertNil(WindowContentView.resolveSelection(HomeTab.tag, roots: roots, asks: []))
        XCTAssertTrue(HomeTab.isHomeTag(HomeTab.tag))
        XCTAssertFalse(HomeTab.isHomeTag(PinnedProject.jobSearch.tag))
        XCTAssertFalse(HomeTab.isHomeTag("reported"))
        // A real id still resolves, so the dashboard's rows can open a session.
        XCTAssertEqual(WindowContentView.resolveSelection("reported", roots: roots, asks: [])?.id,
                       "reported")
    }

    /// The App Kit showcase is not a session either. Without its own nil case it
    /// falls through to `defaultSelection`, and the detail pane still shows the
    /// showcase -- so the bug would be invisible on screen while a session's
    /// toolbar and probes ran behind it.
    func testTheAppKitTagResolvesToNoSession() {
        let roots = [root("reported", model: "Opus 5", updated: Date())]
        XCTAssertNil(WindowContentView.resolveSelection(AppKitTab.tag, roots: roots, asks: []))
        XCTAssertTrue(AppKitTab.isTag(AppKitTab.tag))
        XCTAssertFalse(AppKitTab.isTag(HomeTab.tag))
        XCTAssertFalse(HomeTab.isHomeTag(AppKitTab.tag))
        XCTAssertFalse(AppKitTab.isTag("reported"))
        XCTAssertEqual(WindowContentView.resolveSelection("reported", roots: roots, asks: [])?.id,
                       "reported")
    }

    /// The hoist is a string match on a section id, so it is tested against a
    /// session that should hoist AND one that should not -- a constant that
    /// matched nothing would look identical to one that matched correctly from
    /// the "no home group on screen" side.
    func testTheHomeGroupIsTheSectionForASessionAtTheHomeDirectory() {
        var home = root("h", updated: Date())
        home.cwd = NSHomeDirectory()
        var other = root("o", updated: Date())
        other.cwd = NSHomeDirectory() + "/developer/claude-spinner"
        let sections = FeedWatcher.projectSections(
            [home, other].map { SessionRowItem(id: $0.id, session: $0, ids: [$0.id], depth: 0) },
            asked: [], byRecency: true)
        let hoisted = sections.filter { HomeTab.isHomeSection($0.id) }
        XCTAssertEqual(hoisted.count, 1)
        XCTAssertEqual(hoisted.first?.items.first?.session.id, "h")
        XCTAssertEqual(sections.filter { !HomeTab.isHomeSection($0.id) }.count, 1)
        XCTAssertFalse(HomeTab.isHomeSection("project:claude-spinner"))
    }

    func testWaitingBeatsRecency() {
        let picked = WindowContentView.defaultSelection(roots: [
            root("reported", model: "Opus 5", updated: Date()),
            root("stuck", model: nil, updated: .distantPast, status: .attention),
        ], asks: [])
        XCTAssertEqual(picked?.id, "stuck")
    }

    /// With nothing reported anywhere, still open on something rather than an
    /// empty pane.
    func testFallsBackToTheMostRecentWhenNothingHasReported() {
        let picked = WindowContentView.defaultSelection(roots: [
            root("old", updated: Date().addingTimeInterval(-600)),
            root("new", updated: Date()),
        ], asks: [])
        XCTAssertEqual(picked?.id, "new")
        XCTAssertNil(WindowContentView.defaultSelection(roots: [], asks: []))
    }

    /// Four sidebar rows all reading "session" name nothing.
    func testUnnamedSessionsStayDistinguishable() {
        XCTAssertEqual(root("abcdef123456").distinctName, "session abcdef")
        var named = root("abcdef123456")
        named.cwd = "/Users/home/developer/claude-spinner"
        XCTAssertEqual(named.distinctName, "claude-spinner")
    }

    // MARK: - Overview totals

    private func costed(_ id: String, usd: Double?, tokens: Int?) -> SessionFeed {
        var s = SessionFeed(id: id)
        s.stats.costUSD = usd
        s.contextInputTokens = tokens
        return s
    }

    func testOverviewSumsRootSessions() {
        let out = FeedWatcher.overview(for: [
            costed("a", usd: 23.87, tokens: 300_000),
            costed("b", usd: 2.13, tokens: 50_000),
        ])
        XCTAssertEqual(out.sessions, 2)
        XCTAssertEqual(try XCTUnwrap(out.spendUSD), 26.00, accuracy: 0.001)
        XCTAssertEqual(out.contextTokens, 350_000)
    }

    /// The case that would otherwise print "$0.00 today" over sessions whose
    /// statusLine simply hasn't run. Nothing reported is unknown, not zero.
    func testOverviewTotalsAreNilWhenNothingHasReported() {
        let out = FeedWatcher.overview(for: [
            costed("a", usd: nil, tokens: nil),
            costed("b", usd: nil, tokens: nil),
        ])
        XCTAssertEqual(out.sessions, 2)
        XCTAssertNil(out.spendUSD)
        XCTAssertNil(out.contextTokens)
    }

    /// A partial report is still a real total — it just isn't everything.
    func testOverviewSumsWhatItHasWhenOnlySomeReported() {
        let out = FeedWatcher.overview(for: [
            costed("a", usd: 5, tokens: nil),
            costed("b", usd: nil, tokens: 1_000),
        ])
        XCTAssertEqual(out.spendUSD, 5)
        XCTAssertEqual(out.contextTokens, 1_000)
    }

    /// The rate-limit windows are account-wide: every session reports the same
    /// pair, so the freshest reading is the answer. Summing them would report
    /// 250% of a 5h window across three sessions. A newer session with no
    /// statusLine must not shadow an older one that has the numbers.
    func testRateLimitsAreTakenFreshRatherThanSummed() {
        var old = root("old", updated: Date().addingTimeInterval(-600))
        old.fiveHourPct = 40
        old.sevenDayPct = 30
        var new = root("new", updated: Date().addingTimeInterval(-60))
        new.fiveHourPct = 49
        new.sevenDayPct = 34
        let bare = root("bare", updated: Date())
        let out = FeedWatcher.pickUsageSession([old, new, bare])
        XCTAssertEqual(out?.fiveHourPct, 49)
        XCTAssertEqual(out?.sevenDayPct, 34)
    }

    /// Subagents share their parent's numbers; counting them would double the
    /// spend and treble the session count.
    func testOverviewIgnoresSubagents() {
        var child = costed("child", usd: 99, tokens: 99)
        child.parentSessionId = "a"
        let out = FeedWatcher.overview(for: [costed("a", usd: 1, tokens: 1), child])
        XCTAssertEqual(out.sessions, 1)
        XCTAssertEqual(out.spendUSD, 1)
    }

    // MARK: - Detail-pane stats

    func testMoneyKeepsCentsSoASessionNeverReadsAsFree() {
        XCTAssertEqual(StatFormat.money(23.877466), "$23.88")
        XCTAssertEqual(StatFormat.money(0.004), "$0.00")
        XCTAssertEqual(StatFormat.money(0.42), "$0.42")
    }

    func testDurationDropsToTheLargestUsefulUnit() {
        XCTAssertEqual(StatFormat.duration(2660.3), "44m 20s")
        XCTAssertEqual(StatFormat.duration(7325), "2h 2m")
        XCTAssertEqual(StatFormat.duration(9), "9s")
    }

    func testCompactCountShortensTheContextWindow() {
        XCTAssertEqual(StatFormat.compactCount(1_000_000), "1M")
        XCTAssertEqual(StatFormat.compactCount(200_000), "200k")
        XCTAssertEqual(StatFormat.compactCount(512), "512")
    }

    /// "+0 −0" claims a measurement that was never taken; one side known is
    /// still a real diff.
    func testLineDiffIsNilOnlyWhenNeitherSideIsKnown() {
        XCTAssertNil(StatFormat.lines(added: nil, removed: nil))
        XCTAssertEqual(StatFormat.lines(added: 369, removed: 131), "+369 −131")
        XCTAssertEqual(StatFormat.lines(added: 5, removed: nil), "+5 −0")
    }

    /// An unreported rate limit and a rate limit of zero are different facts. The
    /// zero case is the one that matters: a formatter returning nil for everything
    /// would satisfy the nil assertion on its own.
    // MARK: - Palette contrast

    /// WCAG 2.1 relative luminance and contrast ratio, on the sRGB triples the app
    /// actually draws. Kept in the tests rather than the app: nothing at runtime
    /// needs to measure a colour, and shipping maths only a test calls is dead
    /// weight in the binary.
    private func relativeLuminance(_ c: (Double, Double, Double)) -> Double {
        func channel(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
    }

    private func contrastRatio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let (la, lb) = (relativeLuminance(a), relativeLuminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// A host tag's ground: its own hue at `chipTint` over the pane, which is what
    /// MenuContentView fills the chip with.
    private func chip(_ c: (Double, Double, Double), on ground: (Double, Double, Double)) -> (Double, Double, Double) {
        let a = Color.Ink.chipTint
        return (c.0 * a + ground.0 * (1 - a), c.1 * a + ground.1 * (1 - a), c.2 * a + ground.2 * (1 - a))
    }

    /// The ratio maths itself, against pairs whose answer is fixed by the spec.
    /// Without this the two assertions below could both pass on a function that
    /// returned 21 for everything.
    func testContrastRatioAgreesWithKnownPairs() {
        let white = (1.0, 1.0, 1.0), black = (0.0, 0.0, 0.0)
        XCTAssertEqual(contrastRatio(white, black), 21.0, accuracy: 0.01, "the maximum")
        XCTAssertEqual(contrastRatio(white, white), 1.0, accuracy: 0.001, "a colour on itself")
        // #767676 on white is the canonical 4.5:1 boundary value.
        XCTAssertEqual(contrastRatio((0.463, 0.463, 0.463), white), 4.5, accuracy: 0.1)
    }

    /// Every status colour is drawn as a mark -- a gauge fill, a dot, a sparkline --
    /// so each owes 3:1 against the surface it sits on, in both appearances.
    /// Measured 2026-09-20: the light halves of green, yellow and amber were at
    /// 2.49, 1.97 and 2.42 because the light theme had been derived from the dark
    /// one rather than for a light ground.
    func testEveryStatusMarkClearsThreeToOne() {
        for mark in Color.Ink.marks {
            let light = contrastRatio(mark.light, Color.Ink.groundLight)
            let dark = contrastRatio(mark.dark, Color.Ink.groundDark)
            XCTAssertGreaterThanOrEqual(light, 3.0, "\(mark.name) light is \(light)")
            XCTAssertGreaterThanOrEqual(dark, 3.0, "\(mark.name) dark is \(dark)")
        }
    }

    /// A ring segment is a mark, so it owes 3:1 against the card it is drawn on.
    /// Measured 2026-10-01: the first light magenta and aqua were at 2.62 and
    /// 2.74, which only the printed key under each ring had been covering -- and
    /// that key had just moved into a hover popover, where it is not visible
    /// relief. The ground here is the card, not the pane: that is what a ring
    /// sits on.
    func testEveryRingSegmentClearsThreeToOneOnTheCard() {
        for segment in Color.Ink.segments {
            let light = contrastRatio(segment.light, Color.Ink.cardLight)
            let dark = contrastRatio(segment.dark, Color.Ink.cardDark)
            XCTAssertGreaterThanOrEqual(light, 3.0, "\(segment.name) light is \(light)")
            XCTAssertGreaterThanOrEqual(dark, 3.0, "\(segment.name) dark is \(dark)")
        }
        // The known-bad pair the re-step replaced: the assertion above has to
        // fail for these, or it is not measuring anything.
        XCTAssertLessThan(contrastRatio((0.910, 0.482, 0.643), Color.Ink.cardLight), 3.0)
        XCTAssertLessThan(contrastRatio((0.106, 0.686, 0.478), Color.Ink.cardLight), 3.0)
    }

    /// `series1` is a mark too -- the cache ring's arc and every bar in the Graph
    /// card -- so it owes the same 3:1 on the card it is drawn on.
    func testTheSeriesHueClearsThreeToOneOnTheCard() {
        XCTAssertGreaterThanOrEqual(
            contrastRatio(Color.Ink.series1Light, Color.Ink.cardLight), 3.0)
        XCTAssertGreaterThanOrEqual(
            contrastRatio(Color.Ink.series1Dark, Color.Ink.cardDark), 3.0)
    }

    /// The label ink carries body text at 10-11px, so it owes 4.5:1, not 3:1.
    /// The accent now clears it too (clay, about 5.2:1 on white), which retired
    /// the guard that asserted it did not; it is held to the same floor instead,
    /// so a later re-tint back toward #C26B3D (3.84:1) fails here.
    func testLabelInkClearsBodyTextContrast() {
        XCTAssertGreaterThanOrEqual(
            contrastRatio(Color.Ink.labelLight, Color.Ink.groundLight), 4.5)
        XCTAssertGreaterThanOrEqual(
            contrastRatio(Color.Ink.labelDark, Color.Ink.groundDark), 4.5)
        XCTAssertGreaterThanOrEqual(
            contrastRatio(Color.Ink.claudeLight, Color.Ink.groundLight), 4.5)
        XCTAssertLessThan(
            contrastRatio((0.76, 0.42, 0.24), Color.Ink.groundLight), 4.5,
            "the old accent is the known-bad input; if it passes, the check measures nothing")
    }

    /// The popover draws its own off-white ground, a shade darker than the white
    /// every other figure here is measured on, so the text inks are re-measured on
    /// it. Attention is text there too: the "Needs you" heading.
    func testTextInksClearBodyTextContrastOnThePanelGround() {
        for (name, ink) in [("label", Color.Ink.labelLight), ("attention", Color.Ink.attentionLight),
                            ("claude", Color.Ink.claudeLight)] {
            let ratio = contrastRatio(ink, Color.Ink.panelGroundLight)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) on the panel ground is \(ratio)")
        }
        XCTAssertLessThan(
            contrastRatio((0.76, 0.42, 0.24), Color.Ink.panelGroundLight), 4.5,
            "the old accent is the known-bad input")
    }

    /// The detail pane's section cards sit a step off the pane in both appearances,
    /// and every row label and header is drawn on them, so the text inks are
    /// re-measured on the card rather than the pane.
    func testTextInksClearBodyTextContrastOnTheCard() {
        for (name, light, dark) in [("label", Color.Ink.labelLight, Color.Ink.labelDark),
                                    ("claude", Color.Ink.claudeLight, Color.Ink.claudeDark)] {
            let l = contrastRatio(light, Color.Ink.cardLight)
            let d = contrastRatio(dark, Color.Ink.cardDark)
            XCTAssertGreaterThanOrEqual(l, 4.5, "\(name) on the light card is \(l)")
            XCTAssertGreaterThanOrEqual(d, 4.5, "\(name) on the dark card is \(d)")
        }
        XCTAssertLessThan(
            contrastRatio((0.76, 0.42, 0.24), Color.Ink.cardLight), 4.5,
            "the old accent is the known-bad input")
    }

    /// Orange means working and nothing else, so the label ink must not read as
    /// the accent. The old clay label (#9A4429) is the known-bad input.
    func testLabelInkIsNotTheAccent() {
        func separation(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
            let d = (a.0 - b.0, a.1 - b.1, a.2 - b.2)
            return (d.0 * d.0 + d.1 * d.1 + d.2 * d.2).squareRoot() * 255
        }
        func chroma(_ c: (Double, Double, Double)) -> Double {
            (max(c.0, c.1, c.2) - min(c.0, c.1, c.2)) * 255
        }
        XCTAssertLessThan(chroma(Color.Ink.labelLight), 20)
        XCTAssertLessThan(chroma(Color.Ink.labelDark), 20)
        XCTAssertGreaterThan(separation(Color.Ink.labelDark, Color.Ink.claudeDark), 40)
        XCTAssertGreaterThan(chroma((0.604, 0.267, 0.161)), 20, "the old clay label is the known-bad input")
    }

    /// The model word and the host tag are text, and the tag sits on a `chipTint`
    /// fill of its own hue -- a lighter ground in light and a lighter one in dark
    /// than the pane, so the composite is the stricter surface and the one measured.
    /// Every identity colour owes 4.5:1 against it. The values these replaced
    /// measured 2.04 to 2.88 there, which is why the old ones are the known-bad
    /// input below rather than a comment.
    func testEveryIdentityColourClearsBodyTextContrastOnItsChip() {
        for hue in Color.Ink.identity {
            let light = contrastRatio(hue.light, chip(hue.light, on: Color.Ink.groundLight))
            let dark = contrastRatio(hue.dark, chip(hue.dark, on: Color.Ink.groundDark))
            XCTAssertGreaterThanOrEqual(light, 4.5, "\(hue.name) light is \(light)")
            XCTAssertGreaterThanOrEqual(dark, 4.5, "\(hue.name) dark is \(dark)")
        }
        // Haiku's old green, the worst of the eight. A check that cannot fail is
        // not a check: if this passes, the loop above is measuring nothing.
        let old = (0.45, 0.72, 0.45)
        XCTAssertLessThan(
            contrastRatio(old, chip(old, on: Color.Ink.groundLight)), 4.5,
            "the old identity green is the known-bad input")
    }

    /// A status colour is reserved: it says how urgent something is, and no identity
    /// colour may be near it, or a tinted word cannot be read without already
    /// knowing which question it answers. Darkening the old hues for a white ground
    /// put Haiku 12/255 from usageGreen and the VS Code blue 17 from attention, so
    /// contrast alone is not the whole constraint -- this is the other half.
    func testNoIdentityColourSitsOnAStatusColour() {
        func separation(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
            let d = (a.0 - b.0, a.1 - b.1, a.2 - b.2)
            return (d.0 * d.0 + d.1 * d.1 + d.2 * d.2).squareRoot() * 255
        }
        for hue in Color.Ink.identity {
            for mark in Color.Ink.marks + [("label", Color.Ink.labelLight, Color.Ink.labelDark)] {
                let light = separation(hue.light, mark.light)
                let dark = separation(hue.dark, mark.dark)
                XCTAssertGreaterThan(light, 40, "\(hue.name) light sits on \(mark.name)")
                XCTAssertGreaterThan(dark, 40, "\(hue.name) dark sits on \(mark.name)")
            }
        }
        // The pair that made this rule: Haiku darkened at its old hue.
        XCTAssertLessThan(
            separation((0.263, 0.518, 0.263), Color.Ink.usageGreenLight), 40,
            "the colliding green is the known-bad input")
    }

    func testUsageHeadlineSeparatesUnknownFromZero() {
        XCTAssertNil(StatFormat.usageHeadline(nil), "no window has reported")
        XCTAssertEqual(StatFormat.usageHeadline(0)?.text, "0%", "a real reading of zero")
        XCTAssertEqual(StatFormat.usageHeadline(93)?.text, "93%")
        // The level is what the caller tints by, so it has to track the reading
        // rather than defaulting -- tinting 93% by 0 is the original bug.
        XCTAssertEqual(StatFormat.usageHeadline(93)?.level, 93)
    }

    /// A ratio against a missing or zero denominator is a made-up number.
    func testApiShareNeedsBothHalves() {
        var stats = SessionDetailStats()
        stats.apiSeconds = 2105
        XCTAssertNil(stats.apiShare, "no wall time to divide by")
        stats.wallSeconds = 0
        XCTAssertNil(stats.apiShare, "zero denominator")
        stats.wallSeconds = 2660
        XCTAssertEqual(try XCTUnwrap(stats.apiShare), 0.791, accuracy: 0.001)
    }

    /// Decoded straight from a real statusLine payload, so the field names are
    /// tested against the shape the script actually writes.
    func testStatusDecodesTheFullStatusLinePayload() throws {
        let json = """
        {"model":{"display_name":"Opus 5 (1M context)","id":"claude-opus-5[1m]"},
         "session_name":"spinner-notification-answers","version":"2.1.260",
         "effort":{"level":"high"},"thinking":{"enabled":true},
         "output_style":{"name":"default"},"exceeds_200k_tokens":true,
         "transcript_path":"/tmp/t.jsonl",
         "workspace":{"current_dir":"/Users/home/developer/claude-spinner",
                      "repo":{"host":"github.com","owner":"danieldecena","name":"claude-spinner"}},
         "cost":{"total_cost_usd":23.877466,"total_duration_ms":2660308,
                 "total_api_duration_ms":2105017,"total_lines_added":369,
                 "total_lines_removed":131},
         "context_window":{"total_input_tokens":300000,"total_output_tokens":8706,
                           "context_window_size":1000000,"used_percentage":34},
         "prompt_cache":{"hit_ratio":0.9892967697353634,"warm":true,"ttl":"1h",
                         "requests":129,"misses":0}}
        """
        var session = SessionFeed(id: "s1")
        try session.applyStatusJSONForTest(json)

        XCTAssertEqual(session.stats.costUSD, 23.877466)
        XCTAssertEqual(session.stats.linesAdded, 369)
        XCTAssertEqual(session.stats.contextUsedPercent, 34)
        XCTAssertEqual(session.stats.contextWindowSize, 1_000_000)
        XCTAssertEqual(session.stats.cacheWarm, true)
        XCTAssertEqual(session.stats.cacheTTL, "1h")
        XCTAssertEqual(session.stats.effort, "high")
        XCTAssertEqual(session.stats.thinking, true)
        XCTAssertEqual(session.stats.modelID, "claude-opus-5[1m]")
        XCTAssertEqual(session.stats.claudeVersion, "2.1.260")
        XCTAssertEqual(session.stats.repo, "danieldecena/claude-spinner")
        XCTAssertEqual(session.stats.exceeds200k, true)
        XCTAssertEqual(session.contextTokens, 308_706)
    }

    /// A statusLine that reports nothing beyond the basics must leave every new
    /// field nil rather than defaulting to zero — the detail pane drops nil rows
    /// and would otherwise show a fabricated $0.00 and 0% cache hit rate.
    func testAThinStatusPayloadLeavesTheNewFieldsUnknown() throws {
        var session = SessionFeed(id: "s1")
        try session.applyStatusJSONForTest(#"{"model":{"display_name":"Opus 5"}}"#)
        XCTAssertEqual(session.model, "Opus 5")
        XCTAssertNil(session.stats.costUSD)
        XCTAssertNil(session.stats.cacheHitRatio)
        XCTAssertNil(session.stats.contextUsedPercent)
        XCTAssertNil(session.stats.repo)
    }

    // MARK: - Done-turn notifications

    private func finishedSession(id: String = "s1", host: String = "com.mitchellh.ghostty") -> SessionFeed {
        var s = SessionFeed(id: id)
        s.status = .idle
        s.lastDuration = 42
        s.host = host
        return s
    }

    func testAFinishedTurnNotifiesWhenYouAreLookingElsewhere() {
        XCTAssertTrue(FeedWatcher.shouldNotifyDone(
            session: finishedSession(),
            frontmostBundleID: "com.apple.Safari",
            alreadyNotified: []))
    }

    /// The gate that makes this bearable: a turn finishing in the window you are
    /// already watching does not need announcing — you saw it.
    func testAFinishedTurnIsSilentInTheAppYouAreAlreadyIn() {
        XCTAssertFalse(FeedWatcher.shouldNotifyDone(
            session: finishedSession(host: "com.mitchellh.ghostty"),
            frontmostBundleID: "com.mitchellh.ghostty",
            alreadyNotified: []))
    }

    func testAFinishedTurnNotifiesOnlyOnce() {
        XCTAssertFalse(FeedWatcher.shouldNotifyDone(
            session: finishedSession(),
            frontmostBundleID: "com.apple.Safari",
            alreadyNotified: ["s1"]))
    }

    /// A subagent finishing is not a turn finishing, and a session that is idle
    /// without having run anything (a fresh SessionStart) never "finished".
    func testOnlyRootSessionsThatActuallyRanATurnNotify() {
        var child = finishedSession()
        child.parentSessionId = "parent"
        XCTAssertFalse(FeedWatcher.shouldNotifyDone(
            session: child, frontmostBundleID: nil, alreadyNotified: []))

        var neverRan = finishedSession()
        neverRan.lastDuration = nil
        XCTAssertFalse(FeedWatcher.shouldNotifyDone(
            session: neverRan, frontmostBundleID: nil, alreadyNotified: []))
    }

    // MARK: - SessionReplier (typing into a pane)

    /// Real `tmux list-panes -a -F '#{pane_tty} #{pane_id}'` output from this
    /// machine, so the parse is tested against the shape it actually meets.
    private let paneListing = """
    /dev/ttys005 %10 22489
    /dev/ttys001 %9 7183
    /dev/ttys003 %5 96677
    """

    func testPaneLookupJoinsOnTheControllingTTY() {
        // `ps -o tty=` prints the bare name; tmux prints the device path.
        XCTAssertEqual(SessionReplier.paneID(forTTY: "ttys001", in: paneListing), "%9")
        XCTAssertEqual(SessionReplier.paneID(forTTY: "/dev/ttys001", in: paneListing), "%9")
        XCTAssertEqual(SessionReplier.paneID(forTTY: "ttys005", in: paneListing), "%10")
    }

    /// The known-bad half. A session outside tmux has no pane, and that must
    /// resolve to nothing rather than to the first or nearest row — sending to
    /// the wrong pane types into another agent's prompt.
    func testPaneLookupFindsNothingForASessionOutsideTmux() {
        XCTAssertNil(SessionReplier.paneID(forTTY: "ttys099", in: paneListing))
        XCTAssertNil(SessionReplier.paneID(forTTY: "", in: paneListing))
        XCTAssertNil(SessionReplier.paneID(forTTY: "ttys001", in: ""))
    }

    /// A partial match must not count: ttys00 is a prefix of ttys001 and names a
    /// different device.
    func testPaneLookupRequiresAWholeDeviceMatch() {
        XCTAssertNil(SessionReplier.paneID(forTTY: "ttys00", in: paneListing))
        XCTAssertNil(SessionReplier.paneID(forTTY: "ttys0011", in: paneListing))
    }

    /// send-keys exiting 0 says the keys reached a pane's buffer, never that
    /// Claude was foreground in it. The turn starting is the observation, so
    /// prove the watcher distinguishes both inputs.
    func testTurnStartedIsObservedOnlyWhenTheStatusLeavesIdle() throws {
        try withTempDir { dir in
            let file = dir.appendingPathComponent("sid.state.json")
            try Data(#"{"status":"idle"}"#.utf8).write(to: file)
            XCTAssertFalse(SessionReplier.observeTurnStarted(
                sessionID: "sid", feedDir: dir, timeout: 0.3, poll: 0.05))

            // `.attention` is not a started turn either — it is the state the
            // session was already in when the keys were sent, so accepting it
            // would report delivery for a pane that swallowed them.
            try Data(#"{"status":"attention"}"#.utf8).write(to: file)
            XCTAssertFalse(SessionReplier.observeTurnStarted(
                sessionID: "sid", feedDir: dir, timeout: 0.3, poll: 0.05))

            try Data(#"{"status":"thinking"}"#.utf8).write(to: file)
            XCTAssertTrue(SessionReplier.observeTurnStarted(
                sessionID: "sid", feedDir: dir, timeout: 0.3, poll: 0.05))
        }
    }

    /// A missing state file is "not observed", not a crash and not a pass.
    func testTurnStartedIsNotObservedWithNoStateFile() throws {
        withTempDir { dir in
            XCTAssertFalse(SessionReplier.observeTurnStarted(
                sessionID: "absent", feedDir: dir, timeout: 0.2, poll: 0.05))
        }
    }

    /// End to end through the real runner: a pane made here resolves to its
    /// own id, and a pid in no pane resolves to nil rather than a guess.
    func testPaneIDResolvesALivePaneThroughTheRunner() throws {
        guard let tmux = SessionReplier.tmuxPaths.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { throw XCTSkip("no tmux on this machine") }
        let made = try XCTUnwrap(GitProbe.run(tmux, ["new-session", "-d", "-P", "-F", "#{pane_id} #{pane_pid}",
                                                    "-s", "spinner-test-\(UUID().uuidString.prefix(8))",
                                                    "sleep 30"], in: "/"))
        let fields = made.out.split(separator: " ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        XCTAssertEqual(fields.count, 2)
        defer { _ = GitProbe.run(tmux, ["kill-pane", "-t", fields[0]], in: "/") }

        XCTAssertEqual(SessionReplier.paneID(forPID: try XCTUnwrap(Int(fields[1]))), fields[0])
        XCTAssertNil(SessionReplier.paneID(forPID: Int(ProcessInfo.processInfo.processIdentifier)))
    }

    func testLandingIsChosenByWhatWasTyped() {
        XCTAssertEqual(SessionReplier.Landing(typed: "/clear"), .cleared)
        XCTAssertEqual(SessionReplier.Landing(typed: "/compact"), .compacted)
        XCTAssertEqual(SessionReplier.Landing(typed: "/compact keep the plan"), .compacted)
        XCTAssertEqual(SessionReplier.Landing(typed: "/clearly not a command"), .turnStarted)
        XCTAssertEqual(SessionReplier.Landing(typed: "please /clear the cache"), .turnStarted)
        // Built-ins that start no turn can't be seen landing, and say so.
        XCTAssertEqual(SessionReplier.Landing(typed: "/model sonnet"), .unobservable)
        XCTAssertEqual(SessionReplier.Landing(typed: "/effort xhigh"), .unobservable)
        XCTAssertEqual(SessionReplier.Landing(typed: "/autofix-pr"), .unobservable)
        XCTAssertFalse(SessionReplier.canObserve("/model sonnet"))
        XCTAssertTrue(SessionReplier.canObserve("/wrap-up"))
        XCTAssertFalse(SessionReplier.landed(.unobservable, baseline: nil, current: nil))
    }

    /// Shapes recorded from a live pane 2026-09-29: after a turn the file
    /// carries last_seed; SessionStart rewrites it idle with both turn fields
    /// null. Neither built-in ever passes through "thinking".
    func testBuiltInCommandsLandOnTheirOwnSignalNotThinking() {
        let afterTurn = Data(#"{"status":"idle","turn_start":null,"last_seed":1790720321,"updated":1790720329}"#.utf8)
        let restarted = Data(#"{"status":"idle","turn_start":null,"last_seed":null,"updated":1790720340}"#.utf8)
        let thinking = Data(#"{"status":"thinking","turn_start":1790720330,"last_seed":null}"#.utf8)

        XCTAssertTrue(SessionReplier.landed(.cleared, baseline: afterTurn, current: nil))
        XCTAssertFalse(SessionReplier.landed(.cleared, baseline: afterTurn, current: afterTurn))
        // No baseline: a file that was never there is not a cleared session.
        XCTAssertFalse(SessionReplier.landed(.cleared, baseline: nil, current: nil))

        XCTAssertTrue(SessionReplier.landed(.compacted, baseline: afterTurn, current: restarted))
        XCTAssertFalse(SessionReplier.landed(.compacted, baseline: afterTurn, current: afterTurn))
        XCTAssertFalse(SessionReplier.landed(.compacted, baseline: afterTurn, current: thinking))
        XCTAssertFalse(SessionReplier.landed(.compacted, baseline: afterTurn, current: nil))
        XCTAssertFalse(SessionReplier.landed(.compacted, baseline: nil, current: restarted))

        // The old check, which is what reported every working Clear as failed.
        XCTAssertFalse(SessionReplier.landed(.turnStarted, baseline: afterTurn, current: restarted))
        XCTAssertTrue(SessionReplier.landed(.turnStarted, baseline: nil, current: thinking))
    }

    /// A /compact on a session too short to compact leaves the state file alone
    /// and says so only in the transcript. Lines copied from a real refusal,
    /// 2026-09-30 (Claude Code 2.1.285).
    func testARefusedCompactEndsTheWaitWithClaudeCodesOwnWords() throws {
        let refusal = #"{"type":"system","subtype":"local_command","content":"<local-command-stdout>Not enough messages to compact.</local-command-stdout>","commandRun":{"command":"compact","args":""}}"#
        let ran = #"{"type":"system","subtype":"local_command","content":"<local-command-stdout>Compacted (ctrl+o to see full summary)</local-command-stdout>","commandRun":{"command":"compact","args":""}}"#
        let other = #"{"type":"system","subtype":"local_command","content":"<local-command-stdout>Set model to opus</local-command-stdout>","commandRun":{"command":"model","args":"opus"}}"#
        let prompt = #"{"type":"user","message":{"role":"user","content":"<command-name>/compact</command-name>"}}"#

        XCTAssertEqual(SessionReplier.compactRefusal(in: Data((prompt + "\n" + refusal + "\n").utf8)),
                       "Not enough messages to compact.")
        XCTAssertNil(SessionReplier.compactRefusal(in: Data((prompt + "\n" + ran + "\n").utf8)))
        XCTAssertNil(SessionReplier.compactRefusal(in: Data((other + "\n").utf8)))
        XCTAssertNil(SessionReplier.compactRefusal(in: Data()))

        // End to end: the state file never moves, the refusal lands in the
        // transcript, and the wait ends on it instead of running out the clock.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let state = Data(#"{"status":"idle","turn_start":null,"last_seed":1790720321}"#.utf8)
        try state.write(to: dir.appendingPathComponent("s.state.json"))
        let transcript = dir.appendingPathComponent("t.jsonl")
        let earlier = Data((refusal + "\n").utf8)  // an old refusal, before the send
        try earlier.write(to: transcript)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            let h = try? FileHandle(forWritingTo: transcript)
            _ = try? h?.seekToEnd()
            try? h?.write(contentsOf: Data((prompt + "\n" + refusal + "\n").utf8))
            try? h?.close()
        }
        let start = Date()
        let result = SessionReplier.observe(.compacted, sessionID: "s", feedDir: dir, baseline: state,
                                            transcriptTail: (transcript, UInt64(earlier.count)),
                                            timeout: 10, poll: 0.05)
        if case .failure(let f) = result { XCTAssertEqual(f, .refused("Not enough messages to compact.")) }
        else { XCTFail("expected a refusal, got \(result)") }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)

        // The same wait with nothing appended reads only past the offset, so
        // the earlier refusal is not mistaken for this one.
        let quiet = SessionReplier.observe(.compacted, sessionID: "s", feedDir: dir, baseline: state,
                                           transcriptTail: (transcript, UInt64(try Data(contentsOf: transcript).count)),
                                           timeout: 0.5, poll: 0.05)
        if case .failure(let f) = quiet { XCTAssertEqual(f, .notObserved) }
        else { XCTFail("expected not observed, got \(quiet)") }
    }

    // MARK: - AskInbox (the notification round-trip)

    private func makeAsk(kind: String = "question",
                         req: String = "sid-1-2",
                         labels: [String] = ["Alpha", "Beta"]) -> AskRequest {
        let options = labels.map { "{\"label\":\"\($0)\",\"description\":\"d\"}" }
            .joined(separator: ",")
        let json = """
        {"req":"\(req)","kind":"\(kind)","session_id":"sid","cwd":"/tmp/proj",
         "created":1,"tool_name":"Bash",
         "questions":[{"question":"Which one?","header":"Pick","options":[\(options)]}]}
        """
        return try! JSONDecoder().decode(AskRequest.self, from: Data(json.utf8))
    }

    /// A tap resolves through the action identifier alone, so an id that doesn't
    /// round-trip is a button that silently does nothing — indistinguishable from
    /// a notification nobody touched.
    func testActionIdentifierRoundTrips() {
        let id = AskInbox.actionID(req: "sid-1-2", choice: AskInbox.optionChoice(1))
        let parsed = AskInbox.parseAction(id)
        XCTAssertEqual(parsed?.req, "sid-1-2")
        XCTAssertEqual(parsed?.choice, "opt1")
    }

    /// The built-in default and dismiss identifiers must not parse as ours, or
    /// merely dismissing a banner would answer the question.
    func testParseActionRejectsForeignIdentifiers() {
        XCTAssertNil(AskInbox.parseAction(UNNotificationDefaultActionIdentifier))
        XCTAssertNil(AskInbox.parseAction(UNNotificationDismissActionIdentifier))
        XCTAssertNil(AskInbox.parseAction(NotificationConfig.focusAction))
    }

    func testChoiceMapsToTheOptionLabel() {
        let req = makeAsk()
        XCTAssertEqual(AskInbox.answer(for: "opt0", in: req), .option("Alpha"))
        XCTAssertEqual(AskInbox.answer(for: "opt1", in: req), .option("Beta"))
        XCTAssertEqual(AskInbox.answer(for: "allow", in: makeAsk(kind: "permission")), .allow)
        XCTAssertEqual(AskInbox.answer(for: "deny", in: makeAsk(kind: "permission")), .deny)
    }

    /// An index past the end must resolve to nothing rather than crash or pick a
    /// neighbour: a stale banner can outlive the ask file it was built from.
    func testChoiceOutOfRangeResolvesToNoAnswer() {
        XCTAssertNil(AskInbox.answer(for: "opt9", in: makeAsk()))
        XCTAssertNil(AskInbox.answer(for: "nonsense", in: makeAsk()))
    }

    // MARK: - Stale asks

    func testHookPIDIsTheLastFieldOfTheRequestID() {
        XCTAssertEqual(AskInbox.hookPID("3f2a-9c1e-1726500000-4242"), 4242)
        XCTAssertNil(AskInbox.hookPID("no-pid-here"))
        XCTAssertNil(AskInbox.hookPID(""))
    }

    /// Both halves: a request whose hook is gone is dropped, one whose hook is
    /// alive is kept, and one with no readable pid is kept rather than guessed dead.
    private func makeQuestionAsk(waits: Bool?, created: Double = 100,
                                 pid: String = "null") -> AskRequest {
        let waitsField = waits.map { ",\"waits\":\($0)" } ?? ""
        let json = """
        {"req":"sid-100-7","kind":"question","session_id":"sid","cwd":"/tmp/proj",
         "created":\(created)\(waitsField),"session_pid":\(pid),
         "questions":[{"question":"Which one?","options":[{"label":"Alpha"},{"label":"Beta"}]}]}
        """
        return try! JSONDecoder().decode(AskRequest.self, from: Data(json.utf8))
    }

    /// Files written before questions stopped blocking have no `waits`; they
    /// did wait, so they keep the hook-pid rules.
    func testAskWithoutWaitsFieldIsBlocking() {
        XCTAssertTrue(makeQuestionAsk(waits: nil).blocking)
        XCTAssertTrue(makeQuestionAsk(waits: true).blocking)
        XCTAssertFalse(makeQuestionAsk(waits: false).blocking)
        XCTAssertEqual(makeQuestionAsk(waits: false, pid: "4242").sessionPID, 4242)
    }

    /// A question's hook exits at once by design, so its dead pid must not read
    /// as an orphan -- or every card would vanish on the first rescan.
    func testOrphanedKeepsNonWaitingQuestions() {
        let blocking = makeQuestionAsk(waits: true)
        let question = makeQuestionAsk(waits: false)
        let orphans = AskInbox.orphaned([blocking, question], isAlive: { _ in false })
        XCTAssertEqual(orphans.map(\.waits), [true])
    }

    private func state(_ status: String, tool: String = "", updated: Double) -> Data {
        Data(#"{"status":"\#(status)","tool":"\#(tool)","updated":\#(updated)}"#.utf8)
    }

    /// Each way a question's box can still be up, and each way it is over.
    func testSettledReadsTheSessionState() {
        let ask = makeQuestionAsk(waits: false, created: 100)
        XCTAssertTrue(AskInbox.settled(ask, state: nil), "no state file: the session ended")
        XCTAssertFalse(AskInbox.settled(ask, state: state("tool", tool: "AskUserQuestion", updated: 101)))
        XCTAssertFalse(AskInbox.settled(ask, state: state("attention", updated: 130)),
                       "a Notification while the box waits is not an answer")
        XCTAssertFalse(AskInbox.settled(ask, state: state("thinking", updated: 100)),
                       "a write from the same second can predate the tool call")
        XCTAssertTrue(AskInbox.settled(ask, state: state("thinking", updated: 101)))
        XCTAssertTrue(AskInbox.settled(ask, state: state("tool", tool: "Bash", updated: 105)))
        XCTAssertTrue(AskInbox.settled(ask, state: state("idle", updated: 105)))
        XCTAssertFalse(AskInbox.settled(ask, state: Data("not json".utf8)),
                       "an unreadable state is not evidence the box closed")
        let owned = makeQuestionAsk(waits: false, created: 100, pid: "4242")
        let open = state("tool", tool: "AskUserQuestion", updated: 101)
        XCTAssertTrue(AskInbox.settled(owned, state: open, isAlive: { _ in false }),
                      "a killed session leaves its state on the tool, so its pid has to say it is over")
        XCTAssertFalse(AskInbox.settled(owned, state: open, isAlive: { $0 == 4242 }))
    }

    /// The terminal numbers options from 1; a digit picks at once.
    func testDigitIsTheOptionsOneBasedPosition() {
        let ask = makeQuestionAsk(waits: false)
        XCTAssertEqual(AskInbox.digit(for: .option("Alpha"), in: ask), "1")
        XCTAssertEqual(AskInbox.digit(for: .option("Beta"), in: ask), "2")
        XCTAssertNil(AskInbox.digit(for: .option("Gamma"), in: ask))
        XCTAssertNil(AskInbox.digit(for: .allow, in: ask))
    }

    // MARK: - Forms: several questions, or several answers to one

    private func makeFormAsk() -> AskRequest {
        let json = """
        {"req":"sid-100-7","kind":"question","session_id":"sid","cwd":"/tmp/proj",
         "created":100,"waits":true,"session_pid":null,
         "questions":[{"question":"Pick a color?","options":[{"label":"Red"},{"label":"Green"}]},
                      {"question":"Pick toppings?","multiSelect":true,
                       "options":[{"label":"Ham"},{"label":"Olives"},{"label":"Corn"}]}]}
        """
        return try! JSONDecoder().decode(AskRequest.self, from: Data(json.utf8))
    }

    /// Both halves: the two shapes that are forms, and the one that is not.
    func testIsFormIsSeveralQuestionsOrAMultiSelect() {
        XCTAssertTrue(makeFormAsk().isForm)
        let oneMulti = try! JSONDecoder().decode(AskRequest.self, from: Data("""
        {"req":"sid-100-7","kind":"question","session_id":"sid","cwd":"/tmp","created":1,"waits":true,
         "questions":[{"question":"q","multiSelect":true,"options":[{"label":"a"}]}]}
        """.utf8))
        XCTAssertTrue(oneMulti.isForm)
        XCTAssertFalse(makeQuestionAsk(waits: false).isForm)
        XCTAssertFalse(makePermissionAsk(toolInput: "{}").isForm)
    }

    /// A single-select question holds one pick; a multi-select toggles each.
    func testToggleReplacesASinglePickAndTogglesAMultiPick() {
        var picks = AskForm.toggle("Red", at: 0, multi: false, in: [:])
        picks = AskForm.toggle("Green", at: 0, multi: false, in: picks)
        XCTAssertEqual(picks[0], ["Green"])
        picks = AskForm.toggle("Olives", at: 1, multi: true, in: picks)
        picks = AskForm.toggle("Ham", at: 1, multi: true, in: picks)
        XCTAssertEqual(picks[1], ["Ham", "Olives"])
        picks = AskForm.toggle("Olives", at: 1, multi: true, in: picks)
        XCTAssertEqual(picks[1], ["Ham"])
        XCTAssertEqual(picks[0], ["Green"], "another question's picks are untouched")
    }

    /// Labels come out in the question's option order, not click order, joined
    /// the way the 2026-10-02 probe showed Claude Code expects.
    func testFormAnswersJoinPicksInOptionOrder() {
        let questions = makeFormAsk().questions ?? []
        let answers = AskForm.answers(for: questions, picks: [0: ["Green"], 1: ["Olives", "Ham"]])
        XCTAssertEqual(answers, ["Pick a color?": "Green", "Pick toppings?": "Ham, Olives"])
    }

    /// No answers until every question has a pick, and a label that is not one
    /// of the question's options does not count as one.
    func testFormAnswersNeedAPickForEveryQuestion() {
        let questions = makeFormAsk().questions ?? []
        XCTAssertNil(AskForm.answers(for: questions, picks: [:]))
        XCTAssertNil(AskForm.answers(for: questions, picks: [0: ["Green"]]))
        XCTAssertNil(AskForm.answers(for: questions, picks: [0: ["Green"], 1: []]))
        XCTAssertNil(AskForm.answers(for: questions, picks: [0: ["Blue"], 1: ["Ham"]]))
        XCTAssertNotNil(AskForm.answers(for: questions, picks: [0: ["Green"], 1: ["Ham"]]))
    }

    /// The file ask.sh reads back: allow, plus every answer.
    func testWriteCarriesAFormsAnswers() throws {
        try withTempDir { dir in
            let ask = makeFormAsk()
            try Data("{}".utf8).write(to: dir.appendingPathComponent("\(ask.req).ask.json"))
            let answers = ["Pick a color?": "Green", "Pick toppings?": "Ham, Olives"]
            XCTAssertTrue(AskInbox.write(.form(answers), for: ask, in: dir))
            let data = try Data(contentsOf: dir.appendingPathComponent("\(ask.req).answer.json"))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["behavior"] as? String, "allow")
            XCTAssertEqual(object["answers"] as? [String: String], answers)
        }
    }

    /// A banner button would answer the first question only, and the hook would
    /// then print nothing. A form's banner opens the session; a single
    /// question's banner still carries its options.
    func testAFormsBannerOffersNoOptionButtons() {
        let form = AskInbox.categories(for: [makeFormAsk()])
        XCTAssertEqual(form.first?.actions.map(\.title), ["Open session"])
        let single = AskInbox.categories(for: [makeQuestionAsk(waits: false)])
        XCTAssertEqual(single.first?.actions.map(\.title), ["Alpha", "Beta", "Open session"])
    }

    func testOrphanedDropsOnlyRequestsWhoseHookIsGone() {
        let live = makeAsk(req: "sid-1-100")
        let dead = makeAsk(req: "sid-1-200")
        let unknown = makeAsk(req: "sid-1-x")
        let orphans = AskInbox.orphaned([live, dead, unknown], isAlive: { $0 == 100 })
        XCTAssertEqual(orphans.map(\.req), ["sid-1-200"])
    }

    /// An answer the app wrote after its hook died has no reader; one whose hook
    /// is alive is about to be read and must stay.
    func testOrphanedAnswersDropOnlyDeadHooksAnswers() {
        let names = ["sid-1-100.answer.json", "sid-1-200.answer.json",
                     "sid-1-200.ask.json", "sid-1-x.answer.json", ".sid-1-200.answer.tmp-u"]
        XCTAssertEqual(AskInbox.orphanedAnswers(names, isAlive: { $0 == 100 }),
                       ["sid-1-200.answer.json"])
    }

    func testIsAliveSeparatesThisProcessFromAReapedOne() throws {
        XCTAssertTrue(AskInbox.isAlive(getpid()))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()
        XCTAssertFalse(AskInbox.isAlive(child.processIdentifier))
    }

    /// The trap itself, run for real: ask.sh is stopped while it waits, the way
    /// Claude Code stops it when the prompt is answered in the terminal, and must
    /// take its ask file with it. Asserts the file appeared first, or a script
    /// that bailed at the pgrep gate would pass this without reaching the wait.
    func testAskScriptRemovesItsFileWhenStopped() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("claude spinner/Scripts/ask.sh")
        try withTempDir { home in
            let asks = home.appendingPathComponent(".claude/spinnerfeed/asks")
            // The pgrep gate is not what this tests, and the test host is not
            // reliably visible to pgrep, so a stub stands in for "the app is up".
            let bin = home.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let pgrep = bin.appendingPathComponent("pgrep")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: pgrep)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pgrep.path)
            let hook = Process()
            hook.executableURL = URL(fileURLWithPath: "/bin/sh")
            hook.arguments = ["-x", script.path, "permission"]
            let trace = Pipe()
            hook.standardError = trace
            hook.environment = ["HOME": home.path, "PATH": "\(bin.path):/usr/bin:/bin",
                                "SPINNER_ASK_TIMEOUT": "30"]
            let stdin = Pipe()
            hook.standardInput = stdin
            try hook.run()
            stdin.fileHandleForWriting.write(Data(#"{"session_id":"sid","tool_name":"Bash"}"#.utf8))
            try stdin.fileHandleForWriting.close()

            func askFiles() -> [String] {
                ((try? FileManager.default.contentsOfDirectory(atPath: asks.path)) ?? [])
                    .filter { $0.hasSuffix(".ask.json") }
            }
            let deadline = Date().addingTimeInterval(5)
            while askFiles().isEmpty && Date() < deadline { usleep(50_000) }
            if askFiles().count != 1 {
                hook.terminate(); hook.waitUntilExit()
                let err = String(data: trace.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                XCTFail("precondition: ask.sh reached its wait\n\(err)")
                return
            }

            hook.terminate()
            hook.waitUntilExit()
            XCTAssertEqual(askFiles(), [], "a stopped hook must not leave its ask behind")
        }
    }

    /// The frontmost guard, run both ways against a stubbed `lsappinfo`: with the
    /// session's terminal in front the hook must exit at once without an ask
    /// file (so the terminal draws its own box), and with anything else in front
    /// it must reach the wait. The second half is what shows the first isn't a
    /// guard that always exits.
    func testAskScriptLeavesThePermissionToAFrontmostTerminal() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("claude spinner/Scripts/ask.sh")
        for (host, expectAsk) in [("com.example.term", false), ("com.example.other", true)] {
            try withTempDir { home in
                let asks = home.appendingPathComponent(".claude/spinnerfeed/asks")
                let bin = home.appendingPathComponent("bin")
                try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
                let stubs = ["pgrep": "#!/bin/sh\nexit 0\n",
                             "lsappinfo": "#!/bin/sh\n[ \"$1\" = front ] && echo ASN:0x0-0x1 && exit 0\n"
                                 + "echo '    bundleID=\"com.example.term\"'\n"]
                for (name, body) in stubs {
                    let url = bin.appendingPathComponent(name)
                    try Data(body.utf8).write(to: url)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                }
                let hook = Process()
                hook.executableURL = URL(fileURLWithPath: "/bin/sh")
                hook.arguments = [script.path, "permission"]
                hook.environment = ["HOME": home.path, "PATH": "\(bin.path):/usr/bin:/bin:/opt/homebrew/bin",
                                    "SPINNER_ASK_TIMEOUT": "30", "__CFBundleIdentifier": host]
                let stdin = Pipe()
                hook.standardInput = stdin
                try hook.run()
                stdin.fileHandleForWriting.write(Data(
                    #"{"session_id":"sid","tool_name":"Bash"}"#.utf8))
                try stdin.fileHandleForWriting.close()

                func askFiles() -> [String] {
                    ((try? FileManager.default.contentsOfDirectory(atPath: asks.path)) ?? [])
                        .filter { $0.hasSuffix(".ask.json") }
                }
                let deadline = Date().addingTimeInterval(5)
                if expectAsk {
                    while askFiles().isEmpty && Date() < deadline { usleep(50_000) }
                    XCTAssertEqual(askFiles().count, 1, "a terminal in the background must hand the ask to the app")
                    hook.terminate()
                } else {
                    while hook.isRunning && Date() < deadline { usleep(50_000) }
                    XCTAssertFalse(hook.isRunning, "a frontmost terminal must get the permission prompt at once")
                    XCTAssertEqual(askFiles(), [])
                    if hook.isRunning { hook.terminate() }
                }
                hook.waitUntilExit()
            }
        }
    }

    /// The Allow/Deny card for a question, removed. Run both ways with the
    /// terminal behind: AskUserQuestion must exit at once with no ask file, and
    /// Bash must still reach the wait, or this is a guard that always exits.
    func testAskScriptLeavesAQuestionsPermissionToTheQuestionHook() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("claude spinner/Scripts/ask.sh")
        for (tool, expectAsk) in [("AskUserQuestion", false), ("Bash", true)] {
            try withTempDir { home in
                let asks = home.appendingPathComponent(".claude/spinnerfeed/asks")
                let bin = home.appendingPathComponent("bin")
                try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
                let stubs = ["pgrep": "#!/bin/sh\nexit 0\n",
                             "lsappinfo": "#!/bin/sh\n[ \"$1\" = front ] && echo ASN:0x0-0x1 && exit 0\n"
                                 + "echo '    bundleID=\"com.example.other\"'\n"]
                for (name, body) in stubs {
                    let url = bin.appendingPathComponent(name)
                    try Data(body.utf8).write(to: url)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                }
                let hook = Process()
                hook.executableURL = URL(fileURLWithPath: "/bin/sh")
                hook.arguments = [script.path, "permission"]
                hook.environment = ["HOME": home.path, "PATH": "\(bin.path):/usr/bin:/bin:/opt/homebrew/bin",
                                    "SPINNER_ASK_TIMEOUT": "30", "__CFBundleIdentifier": "com.example.term"]
                let stdin = Pipe()
                let out = Pipe()
                hook.standardInput = stdin
                hook.standardOutput = out
                try hook.run()
                stdin.fileHandleForWriting.write(Data(
                    #"{"session_id":"sid","tool_name":"\#(tool)","tool_input":{"questions":[{"question":"q","options":[{"label":"a"}]}]}}"#.utf8))
                try stdin.fileHandleForWriting.close()

                func askFiles() -> [String] {
                    ((try? FileManager.default.contentsOfDirectory(atPath: asks.path)) ?? [])
                        .filter { $0.hasSuffix(".ask.json") }
                }
                let deadline = Date().addingTimeInterval(5)
                if expectAsk {
                    while askFiles().isEmpty && Date() < deadline { usleep(50_000) }
                    XCTAssertEqual(askFiles().count, 1, "any other tool must still be handed to the app")
                    hook.terminate()
                } else {
                    while hook.isRunning && Date() < deadline { usleep(50_000) }
                    XCTAssertFalse(hook.isRunning, "a question's permission must not wait for the app")
                    XCTAssertEqual(askFiles(), [])
                    if hook.isRunning { hook.terminate() }
                    XCTAssertEqual(out.fileHandleForReading.readDataToEndOfFile(), Data(),
                                   "printing a decision here would answer the permission")
                }
                hook.waitUntilExit()
            }
        }
    }

    /// A question never blocks: whatever is in front, the hook returns at once
    /// so the terminal draws its box, and leaves a non-waiting ask behind for the
    /// card. The frontmost stub says the terminal is NOT in front, the case where
    /// the old hook blocked, so a fast exit here is the new behaviour and not the
    /// frontmost guard firing.
    func testAskScriptHandsAQuestionOverWithoutWaiting() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("claude spinner/Scripts/ask.sh")
        try withTempDir { home in
            let asks = home.appendingPathComponent(".claude/spinnerfeed/asks")
            let bin = home.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let stubs = ["pgrep": "#!/bin/sh\nexit 0\n",
                         "lsappinfo": "#!/bin/sh\n[ \"$1\" = front ] && echo ASN:0x0-0x1 && exit 0\n"
                             + "echo '    bundleID=\"com.example.other\"'\n"]
            for (name, body) in stubs {
                let url = bin.appendingPathComponent(name)
                try Data(body.utf8).write(to: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            let hook = Process()
            hook.executableURL = URL(fileURLWithPath: "/bin/sh")
            hook.arguments = [script.path, "question"]
            hook.environment = ["HOME": home.path, "PATH": "\(bin.path):/usr/bin:/bin:/opt/homebrew/bin",
                                "SPINNER_ASK_TIMEOUT": "30", "__CFBundleIdentifier": "com.example.term"]
            let stdin = Pipe()
            let out = Pipe()
            hook.standardInput = stdin
            hook.standardOutput = out
            try hook.run()
            stdin.fileHandleForWriting.write(Data(
                #"{"session_id":"sid","tool_input":{"questions":[{"question":"q","options":[{"label":"a"}]}]}}"#.utf8))
            try stdin.fileHandleForWriting.close()

            let deadline = Date().addingTimeInterval(5)
            while hook.isRunning && Date() < deadline { usleep(50_000) }
            XCTAssertFalse(hook.isRunning, "a question must not wait for the app")
            if hook.isRunning { hook.terminate() }
            hook.waitUntilExit()
            XCTAssertEqual(hook.terminationStatus, 0)
            XCTAssertEqual(out.fileHandleForReading.readDataToEndOfFile(), Data(),
                           "a question hook must print nothing, or it decides the tool call")

            let names = ((try? FileManager.default.contentsOfDirectory(atPath: asks.path)) ?? [])
                .filter { $0.hasSuffix(".ask.json") }
            XCTAssertEqual(names.count, 1, "the ask file must outlive the hook for the card")
            guard let name = names.first else { return }
            let req = try JSONDecoder().decode(AskRequest.self,
                                               from: Data(contentsOf: asks.appendingPathComponent(name)))
            XCTAssertEqual(req.waits, false)
            XCTAssertFalse(req.blocking)
            XCTAssertEqual(req.question?.options?.first?.label, "a")
        }
    }

    private static let formPayload =
        #"{"session_id":"sid","tool_input":{"questions":[{"question":"Pick a color?","options":[{"label":"Red"},{"label":"Green"}]},{"question":"Pick toppings?","multiSelect":true,"options":[{"label":"Ham"},{"label":"Olives"}]}]}}"#

    /// Runs ask.sh in question mode on the two-question form with `front` as the
    /// frontmost app, feeds it `answer` once its ask file appears, and returns
    /// what it printed. `ask` is the decoded ask file, nil if none was written.
    private func runFormHook(front: String, answer: String?) throws
        -> (stdout: String, status: Int32, ask: AskRequest?, waited: Bool) {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("claude spinner/Scripts/ask.sh")
        var result: (String, Int32, AskRequest?, Bool) = ("", -1, nil, false)
        try withTempDir { home in
            let asks = home.appendingPathComponent(".claude/spinnerfeed/asks")
            let bin = home.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let stubs = ["pgrep": "#!/bin/sh\nexit 0\n",
                         "lsappinfo": "#!/bin/sh\n[ \"$1\" = front ] && echo ASN:0x0-0x1 && exit 0\n"
                             + "echo '    bundleID=\"\(front)\"'\n"]
            for (name, body) in stubs {
                let url = bin.appendingPathComponent(name)
                try Data(body.utf8).write(to: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            let hook = Process()
            hook.executableURL = URL(fileURLWithPath: "/bin/sh")
            hook.arguments = [script.path, "question"]
            hook.environment = ["HOME": home.path, "PATH": "\(bin.path):/usr/bin:/bin:/opt/homebrew/bin",
                                "SPINNER_ASK_TIMEOUT": "30", "__CFBundleIdentifier": "com.example.term"]
            let stdin = Pipe()
            let out = Pipe()
            hook.standardInput = stdin
            hook.standardOutput = out
            try hook.run()
            stdin.fileHandleForWriting.write(Data(Self.formPayload.utf8))
            try stdin.fileHandleForWriting.close()

            func askNames() -> [String] {
                ((try? FileManager.default.contentsOfDirectory(atPath: asks.path)) ?? [])
                    .filter { $0.hasSuffix(".ask.json") }
            }
            var deadline = Date().addingTimeInterval(5)
            while askNames().isEmpty && hook.isRunning && Date() < deadline { usleep(50_000) }
            var ask: AskRequest?
            var waited = false
            if let name = askNames().first {
                ask = try JSONDecoder().decode(AskRequest.self,
                                               from: Data(contentsOf: asks.appendingPathComponent(name)))
                waited = hook.isRunning
                if let answer, let req = ask?.req {
                    try Data(answer.utf8).write(to: asks.appendingPathComponent("\(req).answer.json"))
                }
            }
            deadline = Date().addingTimeInterval(5)
            while hook.isRunning && Date() < deadline { usleep(50_000) }
            if hook.isRunning { hook.terminate() }
            hook.waitUntilExit()
            result = (String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                      hook.terminationStatus, ask, waited)
        }
        return result
    }

    /// At the terminal, a form is the terminal's: no ask file, nothing printed.
    func testAskScriptLeavesAFormToAFrontmostTerminal() throws {
        let run = try runFormHook(front: "com.example.term", answer: nil)
        XCTAssertNil(run.ask)
        XCTAssertEqual(run.stdout, "")
        XCTAssertEqual(run.status, 0)
    }

    /// With the terminal behind, the hook waits on the app and turns a complete
    /// answer into the PreToolUse decision that answers the call.
    func testAskScriptReturnsTheAppsAnswersForAForm() throws {
        let run = try runFormHook(
            front: "com.example.other",
            answer: #"{"behavior":"allow","answers":{"Pick a color?":"Green","Pick toppings?":"Ham, Olives"}}"#)
        XCTAssertTrue(run.waited, "precondition: the hook was still waiting when its ask file appeared")
        XCTAssertEqual(run.ask?.kind, .question)
        XCTAssertEqual(run.ask?.blocking, true)
        XCTAssertEqual(run.ask?.questions?.count, 2)
        XCTAssertEqual(run.status, 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any])
        let specific = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(specific["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(specific["permissionDecision"] as? String, "allow")
        let updated = try XCTUnwrap(specific["updatedInput"] as? [String: Any])
        XCTAssertEqual((updated["questions"] as? [Any])?.count, 2)
        XCTAssertEqual(updated["answers"] as? [String: String],
                       ["Pick a color?": "Green", "Pick toppings?": "Ham, Olives"])
    }

    /// Anything short of one answer per question must not decide the call: the
    /// terminal box is the fallback, and a half-answered form would skip it.
    func testAskScriptPrintsNothingForAnIncompleteOrDeclinedForm() throws {
        for answer in [#"{"behavior":"allow","answers":{"Pick a color?":"Green"}}"#,
                       #"{"behavior":"allow"}"#,
                       #"{"behavior":"passthrough"}"#,
                       #"{"behavior":"deny"}"#] {
            let run = try runFormHook(front: "com.example.other", answer: answer)
            XCTAssertTrue(run.waited, "precondition: the hook reached its wait for \(answer)")
            XCTAssertEqual(run.stdout, "", "printed a decision for \(answer)")
            XCTAssertEqual(run.status, 0)
        }
    }

    // MARK: - What the permission is actually for
    //
    // The card used to render `Run Bash?` and nothing else, because `ask.sh`
    // wrote `tool_input` and `AskRequest` never declared it. These pin the
    // decode, the key order, and every shape that has to fall back rather than
    // throw — a request that fails to decode disappears from the window while
    // the hook is still blocked on it.

    private func makePermissionAsk(toolInput: String) -> AskRequest {
        let json = """
        {"req":"sid-1-2","kind":"permission","session_id":"sid","cwd":"/tmp/proj",
         "created":1,"tool_name":"Bash","tool_input":\(toolInput)}
        """
        return try! JSONDecoder().decode(AskRequest.self, from: Data(json.utf8))
    }

    func testPermissionSubjectIsTheCommandNotTheDescription() {
        let ask = makePermissionAsk(
            toolInput: #"{"command":"rm -rf /tmp/verify-probe-dir","description":"clean up"}"#)
        XCTAssertEqual(ask.toolSubject, "rm -rf /tmp/verify-probe-dir")
    }

    func testPermissionSubjectFallsThroughToAPath() {
        XCTAssertEqual(makePermissionAsk(toolInput: #"{"file_path":"/a/b.swift"}"#).toolSubject,
                       "/a/b.swift")
        XCTAssertEqual(makePermissionAsk(toolInput: #"{"url":"https://example.com"}"#).toolSubject,
                       "https://example.com")
    }

    /// The order is the contract: an Edit carries both a path and, for some
    /// tools, a command. Whichever is listed first must win every time, or the
    /// card shows a different field depending on dictionary iteration.
    func testPermissionSubjectPrefersTheCommand() {
        let ask = makePermissionAsk(toolInput: #"{"file_path":"/a/b","command":"ls /a"}"#)
        XCTAssertEqual(ask.toolSubject, "ls /a")
    }

    /// The known-bad inputs. Each has to decode into a usable request and simply
    /// carry no subject — the card then falls back to the tool name it always had.
    func testPermissionSubjectIsNilWhenNothingNamesIt() {
        XCTAssertNil(makePermissionAsk(toolInput: #"{"timeout":5000,"nested":{"command":"x"}}"#)
            .toolSubject)
        XCTAssertNil(makePermissionAsk(toolInput: #"{"command":"   "}"#).toolSubject)
        XCTAssertNil(makePermissionAsk(toolInput: "null").toolSubject)
        // Not an object at all. Must not throw: ask files written before this
        // field existed, and anything unexpected, still have to reach the window.
        XCTAssertNil(makePermissionAsk(toolInput: #""just a string""#).toolSubject)
        XCTAssertNil(makeAsk(kind: "permission").toolSubject)   // no tool_input key
    }

    func testPermissionSubjectIsCappedForALongCommand() {
        let long = String(repeating: "x", count: 5000)
        let subject = makePermissionAsk(toolInput: #"{"command":"\#(long)"}"#).toolSubject
        XCTAssertEqual(subject?.count, AskRequest.subjectLimit + 1)
        XCTAssertTrue(subject?.hasSuffix("…") ?? false)
    }

    /// The banner had the same gap: "claude-spinner — Bash" is not a thing you
    /// can decide about.
    func testPermissionBannerNamesTheCommand() {
        let ask = makePermissionAsk(toolInput: #"{"command":"rm -rf /tmp/probe"}"#)
        XCTAssertEqual(AskInbox.notificationText(ask).body, "proj — rm -rf /tmp/probe")
        XCTAssertEqual(AskInbox.notificationText(makeAsk(kind: "permission")).body, "proj — Bash")
    }

    func testCategoriesCarryOneActionPerOptionPlusFocus() {
        let cats = AskInbox.categories(for: [makeAsk(labels: ["Alpha", "Beta", "Gamma"])])
        XCTAssertEqual(cats.count, 1)
        XCTAssertEqual(cats[0].identifier, AskInbox.categoryID("sid-1-2"))
        XCTAssertEqual(cats[0].actions.map(\.title), ["Alpha", "Beta", "Gamma", "Open session"])
    }

    func testPermissionCategoryIsAllowDeny() {
        let cats = AskInbox.categories(for: [makeAsk(kind: "permission")])
        XCTAssertEqual(cats[0].actions.map(\.title), ["Allow", "Deny", "Open session"])
    }

    /// The known-good half: an answer written against a live ask file lands, and
    /// carries the label keyed on the question's own text — the shape
    /// AskUserQuestion requires back in `updatedInput`.
    func testWritingAnAnswerForALiveRequest() throws {
        try withTempDir { dir in
            let req = makeAsk()
            try Data("{}".utf8).write(to: dir.appendingPathComponent("\(req.req).ask.json"))

            XCTAssertTrue(AskInbox.write(.option("Beta"), for: req, in: dir))

            let data = try Data(contentsOf: dir.appendingPathComponent("\(req.req).answer.json"))
            let out = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(out["behavior"] as? String, "allow")
            XCTAssertEqual((out["answers"] as? [String: String])?["Which one?"], "Beta")
        }
    }

    /// The known-bad half, and the one that matters: once ask.sh hits its
    /// deadline it deletes the ask file and Claude Code shows its own prompt. A
    /// write after that must report false rather than leave a file nothing reads
    /// — reporting success here would claim an answer reached a session it never
    /// touched.
    func testWritingAnAnswerForAnExpiredRequestFails() throws {
        withTempDir { dir in
            let req = makeAsk()
            XCTAssertFalse(AskInbox.write(.option("Alpha"), for: req, in: dir))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("\(req.req).answer.json").path))
        }
    }

    func testDenyCarriesNoAnswersObject() throws {
        try withTempDir { dir in
            let req = makeAsk(kind: "permission")
            try Data("{}".utf8).write(to: dir.appendingPathComponent("\(req.req).ask.json"))
            XCTAssertTrue(AskInbox.write(.deny, for: req, in: dir))
            let data = try Data(contentsOf: dir.appendingPathComponent("\(req.req).answer.json"))
            let out = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(out["behavior"] as? String, "deny")
            XCTAssertNil(out["answers"])
        }
    }

    /// Reads the file ask.sh actually writes, oldest first.
    func testReadDecodesAskFilesInCreationOrder() throws {
        try withTempDir { dir in
            for (req, created) in [("b", 20), ("a", 10)] {
                let json = """
                {"req":"\(req)","kind":"question","session_id":"s","cwd":"/tmp/p",
                 "created":\(created),"questions":[{"question":"Q","header":"H",
                 "options":[{"label":"L","description":"d"}]}]}
                """
                try Data(json.utf8).write(to: dir.appendingPathComponent("\(req).ask.json"))
            }
            // A stray file that isn't an ask must not decode into the queue.
            try Data("not json".utf8).write(to: dir.appendingPathComponent("junk.txt"))
            let found = AskInbox.read(from: dir)
            XCTAssertEqual(found.map(\.req), ["a", "b"])
            XCTAssertEqual(found.first?.question?.options?.first?.label, "L")
        }
    }

    // MARK: - SetupInstaller.mergeSpinnerHooks (settings.json merge)

    /// Casts the emit.sh command out of a merged settings dict for one event.
    private func emitCommands(_ settings: [String: Any], _ event: String) -> [String] {
        guard let hooks = settings["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return [] }
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
            .filter { $0.contains("emit.sh") }
    }

    func testMergeAddsAllHookEventsToEmptySettings() {
        let merged = SetupInstaller.mergeSpinnerHooks(into: [:])
        for event in SetupInstaller.hookEvents {
            XCTAssertEqual(emitCommands(merged, event), ["~/.claude/spinnerfeed/emit.sh \(event)"],
                           "expected one emit.sh entry for \(event)")
        }
        let statusLine = merged["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["command"] as? String, "bash ~/.claude/statusline-command.sh")
    }

    func testMergeIsIdempotent() {
        let once = SetupInstaller.mergeSpinnerHooks(into: [:])
        let twice = SetupInstaller.mergeSpinnerHooks(into: once)
        for event in SetupInstaller.hookEvents {
            XCTAssertEqual(emitCommands(twice, event).count, 1, "\(event) must not duplicate")
        }
    }

    func testMergePreservesExistingStatusLineAndOtherKeys() {
        let existing: [String: Any] = [
            "model": "opus",
            "statusLine": ["type": "command", "command": "my-custom-statusline"],
        ]
        let merged = SetupInstaller.mergeSpinnerHooks(into: existing)
        XCTAssertEqual(merged["model"] as? String, "opus")
        let statusLine = merged["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["command"] as? String, "my-custom-statusline") // untouched
        XCTAssertEqual(emitCommands(merged, "SessionStart").count, 1)             // still wired
    }

    func testMergeOnlyAddsMissingEvents() {
        // SessionStart already wired by hand; the rest are missing.
        let existing: [String: Any] = [
            "hooks": ["SessionStart": [
                ["matcher": "", "hooks": [["type": "command",
                  "command": "~/.claude/spinnerfeed/emit.sh SessionStart"]]]
            ]]
        ]
        let merged = SetupInstaller.mergeSpinnerHooks(into: existing)
        XCTAssertEqual(emitCommands(merged, "SessionStart").count, 1)  // not duplicated
        XCTAssertEqual(emitCommands(merged, "Stop").count, 1)          // added
    }

    func testAnUnrelatedEmitScriptDoesNotCountAsInstalled() {
        // Another tool's emit.sh on Stop, and ours spelled as an absolute path
        // on SessionStart. Only the second is ours.
        let existing: [String: Any] = [
            "hooks": [
                "Stop": [["matcher": "", "hooks": [["type": "command",
                          "command": "~/bin/emit.sh Stop"]]]],
                "SessionStart": [["matcher": "", "hooks": [["type": "command",
                                  "command": NSHomeDirectory() + "/.claude/spinnerfeed/emit.sh SessionStart"]]]],
            ]
        ]
        let merged = SetupInstaller.mergeSpinnerHooks(into: existing)
        XCTAssertEqual(commands(merged, "Stop", "spinnerfeed/emit.sh").count, 1)          // added
        XCTAssertEqual(commands(merged, "Stop", "~/bin/emit.sh").count, 1)                // left alone
        XCTAssertEqual(commands(merged, "SessionStart", "spinnerfeed/emit.sh").count, 1)  // not duplicated
    }

    /// Commands on one event whose text mentions `script`, whatever the matcher.
    private func commands(_ settings: [String: Any], _ event: String, _ script: String) -> [String] {
        guard let hooks = settings["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return [] }
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
            .filter { $0.contains(script) }
    }

    func testMergeAddsTheAnswerHooks() {
        let merged = SetupInstaller.mergeSpinnerHooks(into: [:])
        XCTAssertEqual(commands(merged, "PreToolUse", "ask.sh"),
                       ["~/.claude/spinnerfeed/ask.sh question"])
        XCTAssertEqual(commands(merged, "PermissionRequest", "ask.sh"),
                       ["~/.claude/spinnerfeed/ask.sh permission"])
        // The question handler must carry its matcher, or it fires on every tool.
        let groups = (merged["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        let askGroup = groups?.first { group in
            (group["hooks"] as? [[String: Any]])?
                .contains { ($0["command"] as? String)?.contains("ask.sh") == true } == true
        }
        XCTAssertEqual(askGroup?["matcher"] as? String, "AskUserQuestion")
        // And a ceiling above the deadline ask.sh enforces itself.
        let entry = (askGroup?["hooks"] as? [[String: Any]])?.first
        XCTAssertEqual(entry?["timeout"] as? Int, 600)
    }

    /// The regression the per-script idempotency key exists for: a machine that
    /// installed before ask.sh existed has emit.sh already wired on PreToolUse.
    /// Keyed on "anything of ours", that group made the whole event look done
    /// and the answer hook was silently never added.
    func testMergeAddsAskHookToSettingsThatAlreadyHaveEmit() {
        let existing: [String: Any] = [
            "hooks": ["PreToolUse": [
                ["matcher": "", "hooks": [["type": "command",
                  "command": "~/.claude/spinnerfeed/emit.sh PreToolUse"]]]
            ]]
        ]
        let merged = SetupInstaller.mergeSpinnerHooks(into: existing)
        XCTAssertEqual(commands(merged, "PreToolUse", "emit.sh").count, 1, "not duplicated")
        XCTAssertEqual(commands(merged, "PreToolUse", "ask.sh").count, 1, "added alongside")
    }

    /// A group written without a "matcher" key at all — settings.json in the
    /// wild has both forms — must read as the empty matcher, not as unmatched.
    func testMergeTreatsMissingMatcherAsEmpty() {
        let existing: [String: Any] = [
            "hooks": ["Notification": [
                ["hooks": [["type": "command",
                  "command": "~/.claude/spinnerfeed/emit.sh Notification"]]]
            ]]
        ]
        let merged = SetupInstaller.mergeSpinnerHooks(into: existing)
        XCTAssertEqual(commands(merged, "Notification", "emit.sh").count, 1, "must not duplicate")
    }

    func testMergeIsIdempotentForTheAnswerHooks() {
        let once = SetupInstaller.mergeSpinnerHooks(into: [:])
        let twice = SetupInstaller.mergeSpinnerHooks(into: once)
        XCTAssertEqual(commands(twice, "PreToolUse", "ask.sh").count, 1)
        XCTAssertEqual(commands(twice, "PermissionRequest", "ask.sh").count, 1)
    }

    // MARK: - SetupInstaller.copyExecutable (script replacement)
    //
    // Exercised in a throwaway temp dir, never against ~/.claude: the installer's
    // real destination is the user's live config and feed dir.

    /// Temp dir seeded with a src/dst pair; removed when `body` returns.
    private func withTempDir(_ body: (URL) throws -> Void) rethrows {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("copyexec-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private func backups(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.contains(".backup-") }.sorted()
    }

    func testCopyExecutablePreservesADifferingDestination() throws {
        try withTempDir { dir in
            let src = dir.appendingPathComponent("src.sh")
            let dst = dir.appendingPathComponent("statusline-command.sh")
            try "bundled".write(to: src, atomically: true, encoding: .utf8)
            try "hand-edited, must survive".write(to: dst, atomically: true, encoding: .utf8)

            try SetupInstaller.copyExecutable(from: src, to: dst, now: Date(timeIntervalSince1970: 1000))

            XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "bundled")
            XCTAssertEqual(backups(in: dir), ["statusline-command.sh.backup-1000"])
            let saved = dir.appendingPathComponent("statusline-command.sh.backup-1000")
            XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8),
                           "hand-edited, must survive")
        }
    }

    func testCopyExecutableDoesNotBackUpAnIdenticalDestination() throws {
        try withTempDir { dir in
            let src = dir.appendingPathComponent("src.sh")
            let dst = dir.appendingPathComponent("statusline-command.sh")
            try "same bytes".write(to: src, atomically: true, encoding: .utf8)
            try "same bytes".write(to: dst, atomically: true, encoding: .utf8)

            // install() is safe to re-run; a no-op re-run must not litter.
            try SetupInstaller.copyExecutable(from: src, to: dst, now: Date(timeIntervalSince1970: 1000))
            try SetupInstaller.copyExecutable(from: src, to: dst, now: Date(timeIntervalSince1970: 2000))

            XCTAssertEqual(backups(in: dir), [])
            XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "same bytes")
        }
    }

    func testCopyExecutableIsExecutableAndHandlesAFreshDestination() throws {
        try withTempDir { dir in
            let src = dir.appendingPathComponent("src.sh")
            let dst = dir.appendingPathComponent("statusline-command.sh")
            try "bundled".write(to: src, atomically: true, encoding: .utf8)

            try SetupInstaller.copyExecutable(from: src, to: dst)

            XCTAssertEqual(backups(in: dir), [])  // nothing to preserve
            let perms = try FileManager.default
                .attributesOfItem(atPath: dst.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(perms?.int16Value, 0o755)
        }
    }

    // MARK: - Menu-bar usage title (reset countdown)

    func testResetCountdownFormatsHoursAndMinutes() {
        XCTAssertEqual(FeedWatcher.resetCountdown(secondsRemaining: 3 * 3600 + 29 * 60), "3h29m")
        XCTAssertEqual(FeedWatcher.resetCountdown(secondsRemaining: 43 * 60), "43m")
        XCTAssertEqual(FeedWatcher.resetCountdown(secondsRemaining: 2 * 3600), "2h0m")
    }

    func testResetCountdownClampsAPastReset() {
        // A stale snapshot can hold a reset instant that has already passed; it
        // must read as "0m", never as a negative countdown.
        XCTAssertEqual(FeedWatcher.resetCountdown(secondsRemaining: -500), "0m")
    }

    func testUsageTitleAppendsTheCountdown() {
        XCTAssertEqual(FeedWatcher.usageTitle(pct: 70, countdown: "2h14m"), "5h 70% \u{00B7} 2h14m")
    }

    func testUsageTitleOmitsAnUnknownCountdown() {
        // The statusLine feed carries a percentage but no resets_at.
        XCTAssertEqual(FeedWatcher.usageTitle(pct: 70, countdown: nil), "5h 70%")
    }

    // MARK: - Git parsing

    func testPorcelainCountsWorktreeStagedAndUntrackedSeparately() {
        // " M" worktree-only, "M " staged-only, "MM" both, "??" untracked.
        let out = " M a.swift\nM  b.swift\nMM c.swift\n?? d.swift\n?? e.swift\n"
        let r = GitParse.porcelain(out)
        XCTAssertEqual(r.dirty, 2)      // a and c
        XCTAssertEqual(r.staged, 2)     // b and c
        XCTAssertEqual(r.untracked, 2)  // d and e
    }

    func testPorcelainOfACleanTreeIsAllZero() {
        // The known-good input: an empty porcelain must not be read as anything
        // but clean, or every clean repo would look busy.
        let r = GitParse.porcelain("")
        XCTAssertEqual(r.dirty, 0)
        XCTAssertEqual(r.staged, 0)
        XCTAssertEqual(r.untracked, 0)
    }

    func testLsRemoteMatchesTheRefExactlyNotBySuffix() {
        let out = "aaa111\trefs/heads/feature/main\nbbb222\trefs/heads/main\n"
        // A suffix match would return aaa111 here, because it comes first.
        XCTAssertEqual(GitParse.lsRemote(out, branch: "main"), "bbb222")
        XCTAssertEqual(GitParse.lsRemote(out, branch: "feature/main"), "aaa111")
    }

    func testLsRemoteReturnsNilWhenTheBranchIsAbsent() {
        XCTAssertNil(GitParse.lsRemote("aaa111\trefs/heads/main\n", branch: "nope"))
    }

    func testSyncStatesCoverEveryBranchOfTheDecision() {
        XCTAssertEqual(GitParse.sync(local: "a", remote: "b", hasUpstream: false,
                                     haveRemoteObject: false, remoteIsAncestor: false,
                                     aheadCount: 0), .noUpstream)
        XCTAssertEqual(GitParse.sync(local: "a", remote: "a", hasUpstream: true,
                                     haveRemoteObject: true, remoteIsAncestor: true,
                                     aheadCount: 0), .inSync)
        // The remote SHA isn't in this clone: how far behind is unknowable
        // without fetching, so it must not be rendered as a number.
        XCTAssertEqual(GitParse.sync(local: "a", remote: "b", hasUpstream: true,
                                     haveRemoteObject: false, remoteIsAncestor: false,
                                     aheadCount: 0), .remoteAhead)
        XCTAssertEqual(GitParse.sync(local: "a", remote: "b", hasUpstream: true,
                                     haveRemoteObject: true, remoteIsAncestor: true,
                                     aheadCount: 3), .ahead(3))
        XCTAssertEqual(GitParse.sync(local: "a", remote: "b", hasUpstream: true,
                                     haveRemoteObject: true, remoteIsAncestor: false,
                                     aheadCount: 0), .diverged)
    }

    func testSyncIsUnknownWhenTheRemoteReadFailed() {
        // A failed ls-remote must render as unknown, never as in-sync. Defaulting
        // an unread value to "everything matches" is the fabricated-empty failure.
        XCTAssertEqual(GitParse.sync(local: "a", remote: nil, hasUpstream: true,
                                     haveRemoteObject: false, remoteIsAncestor: false,
                                     aheadCount: 0), .unknown)
    }

    func testPRJSONParsesEachState() {
        func parse(_ json: String) -> PRState? { GitParse.pr(json: Data(json.utf8)) }
        XCTAssertEqual(parse(#"{"number":7,"state":"OPEN","isDraft":false,"url":"u"}"#),
                       .open(number: 7, url: "u", draft: false))
        XCTAssertEqual(parse(#"{"number":7,"state":"OPEN","isDraft":true,"url":"u"}"#),
                       .open(number: 7, url: "u", draft: true))
        XCTAssertEqual(parse(#"{"number":8,"state":"MERGED","isDraft":false,"url":"u"}"#),
                       .merged(number: 8, url: "u"))
        XCTAssertEqual(parse(#"{"number":9,"state":"CLOSED","isDraft":false,"url":"u"}"#),
                       .closed(number: 9, url: "u"))
        XCTAssertNil(parse("not json"))
    }

    func testGhFailureTellsNoPRApartFromUnreachable() {
        // The known-bad: gh naming the absence in its own words.
        XCTAssertEqual(GitParse.prFailure(stderr: "no pull requests found for branch \"x\""),
                       PRState.none)
        // The known-good pair: every other failure must stay unknown, because a
        // 404 and a dead network are the same exit code.
        XCTAssertEqual(GitParse.prFailure(stderr: "error connecting to api.github.com"),
                       PRState.unknown)
        XCTAssertEqual(GitParse.prFailure(stderr: "gh: authentication required"),
                       PRState.unknown)
    }

    // MARK: - Git action availability

    private func snap(branch: String? = "feat",
                      dirty: Int = 0, staged: Int = 0, untracked: Int = 0,
                      sync: SyncState = .ahead(2),
                      pr: PRState = .none,
                      defaultBranch: Bool = false,
                      detached: Bool = false,
                      merge: MergeReadiness = MergeReadiness(),
                      ghInstalled: Bool = true) -> GitSnapshot {
        var s = GitSnapshot()
        s.branch = branch; s.dirty = dirty; s.staged = staged; s.untracked = untracked
        s.sync = sync; s.pr = pr; s.isDefaultBranch = defaultBranch; s.detached = detached
        s.merge = merge; s.ghInstalled = ghInstalled
        return s
    }

    /// A PR that GitHub says is genuinely ready. The known-GOOD input: without
    /// it the merge tests below can't tell a gate that works from one that
    /// always blocks.
    private func mergeable(_ number: Int = 3) -> GitSnapshot {
        snap(pr: .open(number: number, url: "u", draft: false),
             merge: MergeReadiness(mergeable: "MERGEABLE", state: "CLEAN", review: "APPROVED"))
    }


    // MARK: - Per-session context history

    private func samples(_ pairs: [(Int, Double)]) -> [ContextSample] {
        pairs.map { ContextSample(tokens: $0.0, at: $0.1) }
    }

    /// The known-GOOD case first: a real gap and a real change appends.
    func testAContextSampleIsAppendedWhenTheCountMovesAfterTheGap() {
        let out = FeedWatcher.appending(tokens: 200, at: 100, to: samples([(100, 0)]))
        XCTAssertEqual(out, samples([(100, 0), (200, 100)]))
    }

    /// An unchanged count appends nothing. Sampling it would fill the buffer with
    /// a flat line during an idle session and push out the part of the curve that
    /// has something to say.
    func testAnUnchangedContextCountAppendsNothing() {
        let existing = samples([(100, 0)])
        XCTAssertEqual(FeedWatcher.appending(tokens: 100, at: 9_999, to: existing), existing)
    }

    /// Inside the gap the newest value replaces the last point rather than being
    /// dropped. Dropping it would hold a stale token count on screen through a
    /// fast-moving turn, and the count is what the chart is about.
    func testAChangeInsideTheGapCorrectsTheLastPointInPlace() {
        let out = FeedWatcher.appending(tokens: 175, at: 5, to: samples([(100, 0)]))
        XCTAssertEqual(out, samples([(175, 0)]), "timestamp stays, value updates")
    }

    func testTheFirstSampleIsAlwaysTaken() {
        XCTAssertEqual(FeedWatcher.appending(tokens: 42, at: 0, to: []), samples([(42, 0)]))
    }

    func testTheContextBufferIsCappedAndDropsTheOldestFirst() {
        var buffer: [ContextSample] = []
        for i in 0..<(Constants.contextHistoryMax + 30) {
            buffer = FeedWatcher.appending(tokens: i + 1, at: Double(i) * 60, to: buffer)
        }
        XCTAssertEqual(buffer.count, Constants.contextHistoryMax)
        XCTAssertEqual(buffer.last?.tokens, Constants.contextHistoryMax + 30)
        XCTAssertEqual(buffer.first?.tokens, 31, "the oldest points go, not the newest")
    }

    func testAContextBufferSurvivesACodingRoundTrip() {
        let original = ["a": samples([(1, 0), (2, 60)])]
        let data = try! JSONEncoder().encode(original)
        XCTAssertEqual(try! JSONDecoder().decode([String: [ContextSample]].self, from: data),
                       original)
    }

    // MARK: - Tile grid

    /// Beside a sibling in an HStack, the stack probes the grid with an infinite
    /// width; converting that to a column count trapped and took the app down
    /// when the Job Search tab opened (2026-09-30).
    @MainActor func testATileGridBesideASiblingLaysOutWithoutTrapping() {
        let view = HStack(alignment: .top, spacing: 16) {
            TileGrid(minimum: 220, spacing: 12) {
                Color.red.frame(height: 40)
                Color.blue.frame(height: 40)
            }
            .frame(maxWidth: .infinity)
            Color.green.frame(width: 280, height: 40)
        }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 300)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.fittingSize.width.isFinite)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    // MARK: - System stats

    private func ticks(_ user: UInt32, _ system: UInt32, _ idle: UInt32, _ nice: UInt32 = 0) -> SystemStats.CPUTicks {
        .init(user: user, system: system, idle: idle, nice: nice)
    }

    func testCPUShareIsBusyOverTotalBetweenSamples() {
        // 30 user + 10 system busy, 60 idle: 40 of 100 ticks.
        XCTAssertEqual(SystemStats.cpuShare(from: ticks(100, 50, 400), to: ticks(130, 60, 460))!, 0.4, accuracy: 1e-9)
        // All idle is a real zero, not an unknown.
        XCTAssertEqual(SystemStats.cpuShare(from: ticks(1, 1, 1), to: ticks(1, 1, 51))!, 0, accuracy: 1e-9)
    }

    func testCPUShareIsUnknownWithoutAUsableBaseline() {
        XCTAssertNil(SystemStats.cpuShare(from: nil, to: ticks(1, 1, 1)))
        XCTAssertNil(SystemStats.cpuShare(from: ticks(1, 1, 1), to: nil))
        // No time elapsed.
        XCTAssertNil(SystemStats.cpuShare(from: ticks(5, 5, 5), to: ticks(5, 5, 5)))
        // A counter that went backwards is a wrap or a reset, not a negative load.
        XCTAssertNil(SystemStats.cpuShare(from: ticks(100, 50, 400), to: ticks(90, 60, 460)))
    }

    func testCPUSplitAddsUpToTheShareAndCountsNiceAsUser() {
        // 30 user + 5 nice, 10 system, 55 idle, of 100 ticks.
        let split = SystemStats.cpuSplit(from: ticks(100, 50, 400, 10), to: ticks(130, 60, 455, 15))!
        XCTAssertEqual(split.user, 0.35, accuracy: 1e-9)
        XCTAssertEqual(split.system, 0.10, accuracy: 1e-9)
        let whole = SystemStats.cpuShare(from: ticks(100, 50, 400, 10), to: ticks(130, 60, 455, 15))!
        XCTAssertEqual(split.user + split.system, whole, accuracy: 1e-9)
    }

    func testCPUSplitRefusesWhatTheShareRefuses() {
        XCTAssertNil(SystemStats.cpuSplit(from: nil, to: ticks(1, 1, 1)))
        XCTAssertNil(SystemStats.cpuSplit(from: ticks(5, 5, 5), to: ticks(5, 5, 5)))
        XCTAssertNil(SystemStats.cpuSplit(from: ticks(100, 50, 400), to: ticks(90, 60, 460)))
    }

    func testMemoryAndDiskSharesAreUnknownWhenUnread() {
        XCTAssertEqual(SystemStats.share(used: 8, of: 16)!, 0.5, accuracy: 1e-9)
        XCTAssertNil(SystemStats.share(used: nil, of: 16))
        XCTAssertNil(SystemStats.share(used: 8, of: 0))
        XCTAssertEqual(SystemStats.diskShare(total: 1000, available: 250)!, 0.75, accuracy: 1e-9)
        XCTAssertNil(SystemStats.diskShare(total: nil, available: 250))
        XCTAssertNil(SystemStats.diskShare(total: 1000, available: nil))
        XCTAssertNil(SystemStats.diskShare(total: 0, available: 0))
    }

    /// The real reads, on this machine: the second CPU sample must produce a
    /// share, and memory and disk must read as shares of something. This is the
    /// known-good input the arithmetic tests above cannot be.
    @MainActor func testTheLiveSamplerReadsThisMachine() async throws {
        let stats = SystemStats()
        stats.start()
        defer { stats.stop() }
        XCTAssertNil(stats.cpu, "the first sample has no baseline")
        try await Task.sleep(for: .seconds(2.5))
        let cpu = try XCTUnwrap(stats.cpu)
        XCTAssertTrue((0...1).contains(cpu))
        let memory = try XCTUnwrap(stats.memory)
        XCTAssertTrue(memory > 0 && memory <= 1)
        let disk = try XCTUnwrap(stats.disk)
        XCTAssertTrue(disk > 0 && disk <= 1)
    }

    func testGigabytesAreBinaryWithOneDecimalBelowAHundred() {
        XCTAssertEqual(StatFormat.gigabytes(8_589_934_592), "8.0 GB")
        XCTAssertEqual(StatFormat.gigabytes(UInt64(212) * 1_073_741_824), "212 GB")
    }

    /// The Usage card's five rings in one row must lay out at a finite size.
    @MainActor func testTheWideUsageCardLaysOut() {
        let card = OverviewStrip(fiveHour: 40, sevenDay: 87, usageStale: false, usageHelp: "",
                                 fiveHourElapsed: 0.5, sevenDayElapsed: 0.7,
                                 fiveHourReset: "2h37m", sevenDayReset: "Mon 3:00 PM")
        let host = NSHostingView(rootView: card)
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 300)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.fittingSize.width.isFinite)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    // MARK: - Sparkline spoken value

    /// VoiceOver hears the line's endpoints, since the shape itself says nothing.
    func testTheSparklineSpeaksItsStartAndNow() {
        let history = [UsageSample(pct: 12, at: 0), UsageSample(pct: 30, at: 60),
                       UsageSample(pct: 41, at: 120)]
        XCTAssertEqual(Sparkline.spokenValue(history), "41 percent now, from 12 percent")
        XCTAssertEqual(Sparkline.spokenValue([UsageSample(pct: 7, at: 0)]), "7 percent")
        XCTAssertEqual(Sparkline.spokenValue([]), "no usage history yet")
    }

    // MARK: - Context chart geometry

    func testContextPointsAreScaledByTimeNotByIndex() {
        // Two minutes of work, then a twenty-minute silence, then one more point.
        // Index spacing would draw the silence as one ordinary step.
        let points = ContextChart.unitPoints(samples([(0, 0), (50, 120), (100, 1_320)]),
                                             window: 100)!
        XCTAssertEqual(points[0].x, 0, accuracy: 0.0001)
        XCTAssertEqual(points[1].x, 120.0 / 1_320.0, accuracy: 0.0001)
        XCTAssertEqual(points[2].x, 1, accuracy: 0.0001)
        XCTAssertLessThan(points[1].x, 0.25, "the idle stretch must dominate the width")
    }

    /// y is the share of the window, flipped so 0 is the top of the box.
    func testContextPointsAreScaledToTheWindowAndClamped() {
        let points = ContextChart.unitPoints(
            samples([(0, 0), (50_000, 10), (400_000, 20)]), window: 200_000)!
        XCTAssertEqual(points[0].y, 1, accuracy: 0.0001)
        XCTAssertEqual(points[1].y, 0.75, accuracy: 0.0001)
        XCTAssertEqual(points[2].y, 0, accuracy: 0.0001, "over the window clamps, never draws above")
    }

    /// A compaction is a cliff, and the cliff is the point of the chart.
    func testACompactionDropsTheLineRatherThanBeingSmoothed() {
        let points = ContextChart.unitPoints(
            samples([(180_000, 0), (190_000, 60), (12_000, 120)]), window: 200_000)!
        XCTAssertEqual(points[1].y, 0.05, accuracy: 0.0001)
        XCTAssertEqual(points[2].y, 0.94, accuracy: 0.0001)
    }

    func testAContextChartNeedsTwoPointsAndAWindow() {
        XCTAssertNil(ContextChart.unitPoints(samples([(1, 0)]), window: 100),
                     "one sample is a dot, not a trend")
        XCTAssertNil(ContextChart.unitPoints([], window: 100))
        XCTAssertNil(ContextChart.unitPoints(samples([(1, 0), (2, 1)]), window: nil),
                     "no window is no scale; an invented one makes every session look full")
        XCTAssertNil(ContextChart.unitPoints(samples([(1, 0), (2, 1)]), window: 0))
    }

    /// The row spark's ceiling is the red band's floor, so "pinned to the top"
    /// and "tinted red" mean the same thing. One token under must not be red.
    func testTheRowSparkCeilingIsTheRedBandFloor() {
        XCTAssertEqual(Color.contextTint(ContextSpark.heavyFloor), Color.usageRed)
        XCTAssertNotEqual(Color.contextTint(ContextSpark.heavyFloor - 1), Color.usageRed)
    }

    /// The ruled band lines must sit exactly where the tints change, no more and
    /// no fewer. Scanning the whole range catches a floor that was moved in one
    /// place and not the other, and one that was added to only one of them.
    /// Known-bad: a busy subagent counted as its own working session, or the
    /// counts not adding up to the top-level sessions. Known-good: one of each
    /// status, most urgent first.
    func testTheStatusBreakdownCountsTopLevelSessionsOnly() {
        let sessions = [
            mk("a", .attention), mk("b", .tool), mk("c", .idle),
            mk("c1", .thinking, parentSessionId: "c"),
        ]
        let segments = SessionBreakdown.byStatus(sessions)
        XCTAssertEqual(segments.map(\.label), ["needs you", "working", "idle"])
        XCTAssertEqual(segments.map(\.count), [1, 1, 1])
        XCTAssertEqual(segments.map(\.tint), [.attention, .claude, .label])
        XCTAssertEqual(SessionBreakdown.byStatus([mk("a", .idle), mk("b", .idle)]).map(\.label), ["idle"],
                       "an empty status is left out, not drawn as a zero-width segment")
    }

    /// A session with no model reading is a "?" segment, never dropped: the
    /// model bar must cover the same sessions as the status bar.
    func testTheModelBreakdownKeepsSessionsWithoutAModel() {
        var a = mk("a", .idle); a.model = "Opus 5.5"
        var b = mk("b", .idle); b.model = "Opus 5.5 (1M context)"
        var c = mk("c", .idle); c.model = "Fable 5.1"
        let d = mk("d", .idle)
        let segments = SessionBreakdown.byModel([a, b, c, d], model: \.model)
        XCTAssertEqual(segments.map(\.label), ["opus", "?", "fable"])
        XCTAssertEqual(segments.map(\.count), [2, 1, 1])
        XCTAssertEqual(segments.map(\.tint), [.modelTint("Opus"), .label, .modelTint("Fable")])
        XCTAssertEqual(segments.map(\.count).reduce(0, +),
                       SessionBreakdown.byStatus([a, b, c, d]).map(\.count).reduce(0, +))
    }

    /// A borrowed model is a guess: it gets its own dim "opus?" segment and is
    /// never added to the sessions that reported opus themselves.
    func testTheModelBreakdownKeepsBorrowedModelsApart() {
        var a = mk("a", .idle); a.model = "Opus 5.5"; a.updated = Date()
        let b = mk("b", .idle)
        let c = mk("c", .idle)
        let sessions = [a, b, c]
        let segments = SessionBreakdown.byModel(sessions) {
            FeedWatcher.modelTag(for: $0, among: sessions, cached: nil)
        }
        XCTAssertEqual(segments.map(\.label), ["opus?", "opus"])
        XCTAssertEqual(segments.map(\.count), [2, 1])
        XCTAssertEqual(segments.map(\.tint), [.modelTint("Opus").opacity(0.55), .modelTint("Opus")])
    }

    func testChartBandLinesAreWhereTheTintsChange() {
        var contextSteps: [Int] = []
        for tokens in stride(from: 1_000, through: 300_000, by: 1_000)
        where Color.contextTint(tokens) != Color.contextTint(tokens - 1_000) {
            contextSteps.append(tokens)
        }
        XCTAssertEqual(contextSteps, ContextChart.bandFloors)
    }

    /// A buffer persisted before 7d was recorded must still load.
    func testAUsageSampleWithoutSevenDayDecodes() throws {
        let old = try JSONDecoder().decode([UsageSample].self,
                                           from: Data(#"[{"pct":12,"at":5}]"#.utf8))
        XCTAssertEqual(old.first?.pct, 12)
        XCTAssertNil(old.first?.sevenDayPct)
    }

    /// Samples that share a timestamp would divide by zero on the span.
    func testIdenticalTimestampsFallBackToEvenSpacing() {
        let points = ContextChart.unitPoints(samples([(0, 7), (50, 7), (100, 7)]), window: 100)!
        XCTAssertEqual(points.map(\.x), [0, 0.5, 1])
    }

    // MARK: - Blocked, and whether that is the final answer

    /// The flag the "Nothing to do" line is drawn from. Only settled blocks
    /// count towards it. Get this backwards and "couldn't reach GitHub" is
    /// reported as nothing to do.
    func testOnlyFinishedAnswersAreSettled() {
        XCTAssertEqual(GitActions.unavailableReason(.push, snapshot: snap(sync: .inSync))?.settled, true)
        XCTAssertEqual(GitActions.unavailableReason(.pull, snapshot: snap(sync: .inSync))?.settled, true)
        XCTAssertEqual(GitActions.unavailableReason(
            .createPR, snapshot: snap(pr: .open(number: 3, url: "u", draft: false)))?.settled, true)
        XCTAssertEqual(GitActions.unavailableReason(.openPR, snapshot: snap(pr: .none))?.settled, true)

        // Every "we couldn't tell" stays visible.
        XCTAssertEqual(GitActions.unavailableReason(.push, snapshot: snap(sync: .unknown))?.settled, false)
        XCTAssertEqual(GitActions.unavailableReason(.pull, snapshot: snap(sync: .unknown))?.settled, false)
        XCTAssertEqual(GitActions.unavailableReason(.openPR, snapshot: snap(pr: .unknown))?.settled, false)
        XCTAssertEqual(GitActions.unavailableReason(.createPR, snapshot: snap(pr: .unknown))?.settled, false)
        // Diverged is settled as a fact but needs a person, and hiding the
        // button would hide the only place that says so.
        XCTAssertEqual(GitActions.unavailableReason(.push, snapshot: snap(sync: .diverged))?.settled, false)
    }

    func testAMissingGHBlamesGHAndNotTheNetwork() {
        let s = snap(pr: .unknown, ghInstalled: false)
        for action in [GitAction.openPR, .createPR, .merge] {
            let block = GitActions.unavailableReason(action, snapshot: s)
            XCTAssertEqual(block?.settled, false)
            XCTAssertTrue(block?.reason.contains("gh CLI") == true,
                          "\(action.title) must name gh, not the network")
        }
        // Purely local actions are unaffected by gh being absent.
        XCTAssertNil(GitActions.unavailableReason(.push, snapshot: snap(sync: .ahead(1), ghInstalled: false)))
    }

    // MARK: - Merge

    func testMergeIsOfferedOnlyForAPRGitHubCallsReady() {
        XCTAssertNil(GitActions.unavailableReason(.merge, snapshot: mergeable()))
    }

    func testMergeRefusesEveryStateGitHubCallsUnready() {
        // Not `PRState?`. `PRState` has a case called `none`, so an optional
        // parameter reads `.none` as nil and the case quietly tests the default
        // instead of the state it names.
        func blocked(_ m: MergeReadiness,
                     _ pr: PRState = .open(number: 3, url: "u", draft: false)) -> GitActions.Block? {
            GitActions.unavailableReason(.merge, snapshot: snap(pr: pr, merge: m))
        }
        // Conflicts, failing checks, behind, and protected are all final.
        XCTAssertEqual(blocked(MergeReadiness(mergeable: "CONFLICTING", state: "DIRTY", review: "APPROVED"))?.settled, true)
        XCTAssertEqual(blocked(MergeReadiness(mergeable: "MERGEABLE", state: "UNSTABLE", review: "APPROVED"))?.settled, true)
        XCTAssertEqual(blocked(MergeReadiness(mergeable: "MERGEABLE", state: "BEHIND", review: "APPROVED"))?.settled, true)
        XCTAssertEqual(blocked(MergeReadiness(mergeable: "MERGEABLE", state: "BLOCKED", review: "APPROVED"))?.settled, true)
        // Reviews.
        XCTAssertEqual(blocked(MergeReadiness(mergeable: "MERGEABLE", state: "BLOCKED", review: "REVIEW_REQUIRED"))?.settled, true)
        XCTAssertEqual(blocked(MergeReadiness(mergeable: "MERGEABLE", state: "CLEAN", review: "CHANGES_REQUESTED"))?.settled, true)
        // A draft, and a PR that isn't open.
        XCTAssertNotNil(blocked(MergeReadiness(mergeable: "MERGEABLE", state: "DRAFT", review: ""),
                                .open(number: 3, url: "u", draft: true)))
        XCTAssertNotNil(blocked(MergeReadiness(mergeable: "MERGEABLE", state: "CLEAN", review: ""), .none))
        XCTAssertNotNil(blocked(MergeReadiness(mergeable: "MERGEABLE", state: "CLEAN", review: ""),
                                .merged(number: 3, url: "u")))
    }

    /// The half that isn't a refusal. Mergeability GitHub hasn't computed yet
    /// must not read as a refusal -- it is an absent answer, and the button has
    /// to stay on screen saying so.
    func testUncomputedMergeabilityIsNotARefusal() {
        let pending = snap(pr: .open(number: 3, url: "u", draft: false),
                           merge: MergeReadiness(mergeable: "UNKNOWN", state: "UNKNOWN", review: ""))
        XCTAssertEqual(GitActions.unavailableReason(.merge, snapshot: pending)?.settled, false)

        let noFields = snap(pr: .open(number: 3, url: "u", draft: false))
        XCTAssertEqual(GitActions.unavailableReason(.merge, snapshot: noFields)?.settled, false)
    }

    func testMergeNamesItsMethodAndCleanupExplicitly() {
        // `gh pr merge` with no method prompts, and a subprocess with no
        // terminal would sit there until the timeout.
        XCTAssertEqual(GitActions.command(.merge, snapshot: mergeable())?.args,
                       ["pr", "merge", "3", "--squash", "--delete-branch"])
        XCTAssertTrue(GitAction.merge.confirmation?.contains("delete the branch") == true)
    }

    func testMergeRefusesADirtyCheckout() {
        let ready = MergeReadiness(mergeable: "MERGEABLE", state: "CLEAN", review: "APPROVED")
        let pr = PRState.open(number: 3, url: "u", draft: false)
        // Tracked changes, modified or staged, would fail gh's post-merge checkout.
        XCTAssertEqual(GitActions.unavailableReason(.merge, snapshot: snap(dirty: 1, pr: pr, merge: ready))?.settled, true)
        XCTAssertEqual(GitActions.unavailableReason(.merge, snapshot: snap(staged: 1, pr: pr, merge: ready))?.settled, true)
        // Untracked files don't block a checkout, so they don't block the merge.
        XCTAssertNil(GitActions.unavailableReason(.merge, snapshot: snap(untracked: 2, pr: pr, merge: ready)))
    }

    func testMergeIsPinnedToTheConfirmedPR() {
        // Unpinned, gh picks the PR from the branch checked out when it runs,
        // not the one the button was confirmed against.
        XCTAssertEqual(GitActions.command(.merge, snapshot: mergeable(41))?.args.prefix(3),
                       ["pr", "merge", "41"])
        // No open PR in the snapshot means nothing to pin to, so nothing runs.
        XCTAssertNil(GitActions.command(.merge, snapshot: snap(pr: .none)))
        XCTAssertNil(GitActions.command(.merge, snapshot: snap(pr: .merged(number: 41, url: "u"))))
    }

    func testRunHonoursItsTimeoutInBothDirections() {
        // The same 1s child must be cut off under a short budget and allowed to
        // finish under a long one -- one side alone can't tell a working timeout
        // from one that always or never fires.
        XCTAssertNil(GitProbe.run("/bin/sleep", ["1"], in: "/", timeout: 0.2))
        XCTAssertEqual(GitProbe.run("/bin/sleep", ["1"], in: "/", timeout: 5)?.status, 0)
        XCTAssertGreaterThan(GitActions.actionTimeout, GitProbe.timeout)
    }

    func testMergeReadinessParsesGHsFieldsAndToleratesTheirAbsence() {
        let full = #"{"number":3,"state":"OPEN","isDraft":false,"url":"u","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED"}"#
        let r = GitParse.mergeReadiness(json: Data(full.utf8))
        XCTAssertEqual(r.mergeable, "MERGEABLE")
        XCTAssertEqual(r.state, "CLEAN")
        XCTAssertEqual(r.review, "APPROVED")
        XCTAssertEqual(r.label, "checks passing, approved")

        // An older gh, or a repo the token can't see merge state for: the
        // fields are simply absent, which must stay nil rather than default.
        let bare = GitParse.mergeReadiness(json: Data(#"{"number":3,"state":"OPEN"}"#.utf8))
        XCTAssertNil(bare.mergeable)
        XCTAssertNil(bare.state)
        XCTAssertNil(bare.label)
    }

    // MARK: - Freshness

    func testAgeIsNilUntilSomethingHasActuallyBeenRead() {
        let now = Date()
        XCTAssertNil(StatFormat.age(.distantPast, now: now))
        XCTAssertEqual(StatFormat.age(now.addingTimeInterval(-3), now: now), "3s ago")
        XCTAssertEqual(StatFormat.age(now.addingTimeInterval(-90), now: now), "1m ago")
        XCTAssertEqual(StatFormat.age(now.addingTimeInterval(-7200), now: now), "2h ago")
    }

    /// A failed GitHub read used to render as no row at all, which looks exactly
    /// like a branch that has no PR.
    func testAnUnreadablePRStillDrawsARow() {
        XCTAssertEqual(PRState.unknown.label, "unknown")
        XCTAssertEqual(PRState.none.label, "none")
    }

    func testPullRefusesADirtyTreeAndAllowsACleanOne() {
        // The pair that proves the guard fires rather than always firing.
        XCTAssertNotNil(GitActions.unavailableReason(
            .pull, snapshot: snap(dirty: 1, sync: .remoteAhead)))
        XCTAssertNil(GitActions.unavailableReason(
            .pull, snapshot: snap(sync: .remoteAhead)))
    }

    func testPullNeverOffersToReconcileADivergedBranch() {
        XCTAssertNotNil(GitActions.unavailableReason(.pull, snapshot: snap(sync: .diverged)))
    }

    /// Untracked files must never gate Pull. Filed as "Pull is disabled by
    /// untracked files" off a tooltip read while the tree also had a tracked
    /// edit; the gate only ever saw tracked changes. Pinned in the direction the
    /// report got wrong, so the misreading can't be re-introduced as a fix.
    func testPullIgnoresUntrackedFiles() {
        XCTAssertNil(GitActions.unavailableReason(
            .pull, snapshot: snap(untracked: 40, sync: .remoteAhead)))
    }

    /// A dirty tree with nothing to pull has to say so. "Commit or stash them
    /// first" reads as a promise that Pull unlocks afterwards, and it does not.
    func testPullReasonNamesTheSyncStateBeforeTheDirtyTree() {
        XCTAssertEqual(GitActions.unavailableReason(.pull, snapshot: snap(dirty: 1, sync: .inSync))?.reason,
                       "Already up to date with the remote.")
        XCTAssertEqual(GitActions.unavailableReason(.pull, snapshot: snap(staged: 1, sync: .ahead(2)))?.reason,
                       "Nothing to pull; this branch is ahead of the remote.")
    }

    func testPushIsOfferedWhenAheadAndRefusedWhenBehindOrDiverged() {
        XCTAssertNil(GitActions.unavailableReason(.push, snapshot: snap(sync: .ahead(1))))
        XCTAssertNotNil(GitActions.unavailableReason(.push, snapshot: snap(sync: .remoteAhead)))
        XCTAssertNotNil(GitActions.unavailableReason(.push, snapshot: snap(sync: .diverged)))
        XCTAssertNotNil(GitActions.unavailableReason(.push, snapshot: snap(sync: .inSync)))
    }

    func testPushIsOfferedForABranchThatHasNoUpstreamYet() {
        XCTAssertNil(GitActions.unavailableReason(.push, snapshot: snap(sync: .noUpstream)))
    }

    func testFirstPushSetsTheUpstreamAndLaterPushesDoNot() {
        let cmd = GitActions.command(.push, snapshot: snap(sync: .noUpstream))
        XCTAssertEqual(cmd?.args, ["push", "--set-upstream", "origin", "feat"])
        XCTAssertEqual(GitActions.command(.push, snapshot: snap(sync: .ahead(1)))?.args, ["push"])
    }

    func testPullIsAlwaysFastForwardOnly() {
        // The whole safety story of the button. If this argument ever goes
        // missing, Pull silently becomes a merge or a rebase.
        XCTAssertEqual(GitActions.command(.pull, snapshot: snap(sync: .remoteAhead))?.args,
                       ["pull", "--ff-only"])
    }

    func testCreatePRIsRefusedOnTheDefaultBranchAndWhenOneIsOpen() {
        XCTAssertNotNil(GitActions.unavailableReason(
            .createPR, snapshot: snap(branch: "main", defaultBranch: true)))
        XCTAssertNotNil(GitActions.unavailableReason(
            .createPR, snapshot: snap(pr: .open(number: 3, url: "u", draft: false))))
        XCTAssertNil(GitActions.unavailableReason(.createPR, snapshot: snap()))
    }

    func testCreatePRWaitsWhenGitHubCouldNotBeReached() {
        // Unknown is not none. Offering to create a second PR because the first
        // couldn't be seen is the "not found is not absence" failure.
        XCTAssertNotNil(GitActions.unavailableReason(.createPR, snapshot: snap(pr: .unknown)))
    }

    func testOpenPRNeedsAnActualPR() {
        XCTAssertNotNil(GitActions.unavailableReason(.openPR, snapshot: snap(pr: .none)))
        XCTAssertNotNil(GitActions.unavailableReason(.openPR, snapshot: snap(pr: .unknown)))
        XCTAssertNil(GitActions.unavailableReason(
            .openPR, snapshot: snap(pr: .open(number: 3, url: "u", draft: false))))
    }

    func testDetachedHeadOffersNeitherPushNorPR() {
        let d = snap(branch: nil, detached: true)
        XCTAssertNotNil(GitActions.unavailableReason(.push, snapshot: d))
        XCTAssertNotNil(GitActions.unavailableReason(.createPR, snapshot: d))
    }

    func testOnlyOpenPRSkipsConfirmation() {
        XCTAssertNil(GitAction.openPR.confirmation)
        for action in [GitAction.push, .createPR, .pull, .merge] {
            XCTAssertNotNil(action.confirmation, "\(action.title) must confirm first")
        }
    }

    func testFirstLineSkipsBlankLeadingOutput() {
        XCTAssertEqual(GitActions.firstLine("\n\n  Everything up-to-date\nnoise\n"),
                       "Everything up-to-date")
        XCTAssertNil(GitActions.firstLine("   \n\n"))
    }

    func testACleanSnapshotIsNotDirty() {
        XCTAssertFalse(snap().isDirty)
        XCTAssertTrue(snap(dirty: 1).isDirty)
        XCTAssertTrue(snap(staged: 1).isDirty)
        // Untracked alone is not dirt: a deny-by-default ignore file leaves a
        // permanent untracked population that must not read as work in progress.
        var untrackedOnly = snap()
        untrackedOnly.untracked = 22
        XCTAssertFalse(untrackedOnly.isDirty)
    }

    // MARK: - Git probe, end to end

    /// Everything above tests parsers against canned strings, which cannot tell
    /// a working probe from one that never runs a command. This builds a real
    /// repository and reads it, so the subprocess plumbing -- cwd, PATH, the
    /// pipe draining -- is exercised rather than assumed. No network: a repo
    /// with no remote settles on `.noUpstream`.
    func testProbeReadsARealRepositoryOnDisk() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spinner-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.path

        func git(_ args: [String]) throws {
            let r = GitProbe.run("/usr/bin/git", args, in: path)
            let status = try XCTUnwrap(r?.status, "git \(args.first ?? "") did not run")
            XCTAssertEqual(status, 0, "git \(args.joined(separator: " ")): \(r?.err ?? "")")
        }

        try git(["init", "--initial-branch=trunk"])
        try git(["config", "user.email", "t@example.com"])
        try git(["config", "user.name", "Test"])
        try "one\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "a.txt"])
        try git(["commit", "-m", "first"])

        // One tracked modification, one staged addition, one untracked file --
        // so a probe that merely returns an empty snapshot cannot pass.
        try "two\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b\n".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try git(["add", "b.txt"])
        try "c\n".write(to: root.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)

        let probed = await GitProbe.shared.snapshot(for: path)
        let snap = try XCTUnwrap(probed, "probe returned nil for a real repository")
        XCTAssertEqual(snap.branch, "trunk")
        XCTAssertFalse(snap.detached)
        XCTAssertEqual(snap.dirty, 1)
        XCTAssertEqual(snap.staged, 1)
        XCTAssertEqual(snap.untracked, 1)
        XCTAssertTrue(snap.isDirty)
        XCTAssertEqual(snap.sync, .noUpstream)
        // Dirty plus no upstream: Pull must refuse, Push must be offered.
        XCTAssertNotNil(GitActions.unavailableReason(.pull, snapshot: snap))
        XCTAssertNil(GitActions.unavailableReason(.push, snapshot: snap))
    }

    /// The other half of the pair: a directory that is not a repository must
    /// produce nil, so the detail pane drops the section instead of drawing
    /// a row of unknowns. Without this, a probe that returns an empty snapshot
    /// for everything would pass the test above.
    func testProbeReturnsNilForADirectoryThatIsNotARepository() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spinner-nogit-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snap = await GitProbe.shared.snapshot(for: root.path)
        XCTAssertNil(snap)
    }

    // MARK: - Resting evidence

    private func resting(status: SessionStatus = .idle,
                         notification: String? = nil,
                         total: Int? = nil, done: Int? = nil,
                         updated: Date? = Date(timeIntervalSinceNow: -120)) -> SessionFeed {
        var s = SessionFeed(id: "r")
        s.status = status
        s.notificationType = notification
        s.todoTotal = total
        s.todoDone = done
        s.updated = updated
        return s
    }

    func testRestingEvidenceLeadsWithOpenTodos() {
        let s = resting(total: 8, done: 5)
        XCTAssertEqual(s.restingEvidence(now: Date()), "3 todos open · idle 2m 0s")
    }

    func testRestingEvidenceSaysOneTodoInTheSingular() {
        XCTAssertEqual(resting(total: 4, done: 3).restingEvidence(now: Date()),
                       "1 todo open · idle 2m 0s")
    }

    func testRestingEvidenceReportsAFullyDoneList() {
        XCTAssertEqual(resting(total: 5, done: 5).restingEvidence(now: Date()),
                       "5/5 todos · idle 2m 0s")
    }

    func testRestingEvidenceOmitsTodosWhenNoneWereRecorded() {
        XCTAssertEqual(resting().restingEvidence(now: Date()), "idle 2m 0s")
    }

    func testRestingEvidenceOmitsAgeRatherThanInventingZero() {
        // No stamp in the feed. "idle 0s" would read as "just now" for a session
        // last seen an hour ago -- a value fabricated from a missing read.
        XCTAssertEqual(resting(total: 3, done: 1, updated: nil).restingEvidence(now: Date()),
                       "2 todos open")
        XCTAssertNil(resting(updated: nil).restingEvidence(now: Date()))
    }

    func testRestingEvidenceIsNilForAWorkingSession() {
        XCTAssertNil(resting(status: .thinking).restingEvidence(now: Date()))
        XCTAssertNil(resting(status: .tool).restingEvidence(now: Date()))
    }

    func testRestingEvidenceIsNilWhenSomethingIsActuallyBlockedOnYou() {
        // The known-bad input: a real permission prompt is not resting.
        XCTAssertNil(resting(status: .attention, notification: "permission_prompt")
            .restingEvidence(now: Date()))
    }

    func testRestingEvidenceStillFiresForTheSixtySecondIdleNudge() {
        // The known-good pair for the guard above. idle_prompt means the turn
        // ended and nobody typed, which is precisely a resting session -- without
        // this case, a guard that always returned nil would pass the test above.
        XCTAssertEqual(resting(status: .attention, notification: "idle_prompt")
            .restingEvidence(now: Date()), "idle 2m 0s")
    }

    func testPanelDropsTodosBecauseTheBarAlreadyDrawsThem() {
        XCTAssertEqual(resting(total: 8, done: 5).restingEvidence(now: Date(),
                                                                 includeTodos: false),
                       "idle 2m 0s")
    }

    // MARK: - Git tones

    func testGitTonesReadSettledPendingAndBroken() {
        XCTAssertEqual(SyncState.inSync.tone, .good)
        XCTAssertEqual(SyncState.ahead(2).tone, .pending)
        XCTAssertEqual(SyncState.diverged.tone, .bad)
        // Not reachable is not in sync.
        XCTAssertEqual(SyncState.unknown.tone, .neutral)
        XCTAssertEqual(PRState.none.tone, .neutral)
        XCTAssertEqual(PRState.open(number: 3, url: "u", draft: false).tone, .good)
    }

    /// The worst verdict wins: passing checks don't hide a conflict.
    func testMergeToneTakesTheWorstVerdict() {
        XCTAssertEqual(MergeReadiness(mergeable: "CONFLICTING", state: "CLEAN", review: "APPROVED").tone, .bad)
        XCTAssertEqual(MergeReadiness(mergeable: "MERGEABLE", state: "CLEAN", review: "REVIEW_REQUIRED").tone, .warn)
        XCTAssertEqual(MergeReadiness(mergeable: "MERGEABLE", state: "CLEAN", review: "").tone, .good)
        XCTAssertEqual(MergeReadiness().tone, .neutral)
    }

    func testUntrackedAloneDoesNotReadAsPendingWork() {
        var snap = GitSnapshot()
        XCTAssertEqual(snap.changesTone, .good)
        snap.untracked = 4
        XCTAssertEqual(snap.changesTone, .neutral)
        snap.dirty = 1
        XCTAssertEqual(snap.changesTone, .pending)
    }

    func testCIParseTellsNoRunsFromUnknown() {
        XCTAssertEqual(GitParse.ci(json: Data("[]".utf8)), .none)
        XCTAssertEqual(GitParse.ci(json: Data("not json".utf8)), .unknown)
        let passed = GitParse.ci(json: Data(#"[{"status":"completed","conclusion":"success","workflowName":"CI","url":"u"}]"#.utf8))
        XCTAssertEqual(passed, .finished(workflow: "CI", conclusion: "success", url: "u"))
        XCTAssertEqual(passed.tone, .good)
        XCTAssertEqual(passed.label, "CI passed")
        let running = GitParse.ci(json: Data(#"[{"status":"in_progress","conclusion":"","workflowName":"CI","url":"u"}]"#.utf8))
        XCTAssertEqual(running.tone, .pending)
        let failed = GitParse.ci(json: Data(#"[{"status":"completed","conclusion":"failure","workflowName":"CI","url":"u"}]"#.utf8))
        XCTAssertEqual(failed.tone, .bad)
    }

    func testNewGitActionsRunTheRightCommands() {
        var snap = GitSnapshot()
        snap.sync = .inSync
        XCTAssertEqual(GitActions.command(.fetch, snapshot: snap)?.args, ["fetch", "--prune"])
        XCTAssertEqual(GitActions.command(.openCI, snapshot: snap)?.args, ["browse", "--actions"])
        XCTAssertNil(GitActions.unavailableReason(.fetch, snapshot: snap))
        snap.sync = .noUpstream
        XCTAssertEqual(GitActions.unavailableReason(.fetch, snapshot: snap)?.settled, true)
        snap.ghInstalled = false
        XCTAssertNotNil(GitActions.unavailableReason(.openCI, snapshot: snap))
    }

    func testGitGraphParseReadsParentsAndRefs() {
        let out = "aaa\tbbb ccc\tHEAD -> main, origin/main\tMerge it\t1000\nbbb\t\t\tRoot\t900\n"
        let commits = GitGraph.parse(out)
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits[0].parents, ["bbb", "ccc"])
        XCTAssertEqual(commits[0].refs, ["HEAD -> main", "origin/main"])
        XCTAssertEqual(commits[1].parents, [])
        XCTAssertEqual(commits[1].committedAt, Date(timeIntervalSince1970: 900))
    }

    /// A straight history is one lane with a line from each commit to the next.
    func testGraphLayoutKeepsALinearHistoryInOneLane() {
        let rows = GitGraph.layout([.init(sha: "c", parents: ["b"]),
                                    .init(sha: "b", parents: ["a"]),
                                    .init(sha: "a", parents: [])])
        XCTAssertEqual(rows.map(\.column), [0, 0, 0])
        XCTAssertEqual(rows[0].edges, [GraphEdge(from: 0, to: 0)])
        XCTAssertEqual(rows[2].edges, [])
    }

    /// m merges f into main: m's second parent opens lane 1, the feature commit
    /// sits there, and both lanes converge back on the fork point.
    func testGraphLayoutBranchesAndConvergesAMerge() {
        let rows = GitGraph.layout([.init(sha: "m", parents: ["b", "f"]),
                                    .init(sha: "f", parents: ["a"]),
                                    .init(sha: "b", parents: ["a"]),
                                    .init(sha: "a", parents: [])])
        XCTAssertEqual(rows.map(\.column), [0, 1, 0, 0])
        XCTAssertEqual(Set(rows[0].edges), [GraphEdge(from: 0, to: 0), GraphEdge(from: 0, to: 1)])
        // f and b are both waiting on a; b's row is where lane 1 bends back into 0.
        XCTAssertEqual(Set(rows[2].edges), [GraphEdge(from: 0, to: 0), GraphEdge(from: 1, to: 0)])
        XCTAssertEqual(rows.map(\.width).max(), 2)
    }

    private func linear(_ n: Int, refs: [Int: [String]] = [:]) -> [GraphRow] {
        GitGraph.layout((0..<n).map { i in
            GraphCommit(sha: "c\(i)", parents: i + 1 < n ? ["c\(i + 1)"] : [], refs: refs[i] ?? [])
        })
    }

    /// The card passes `newest: fit - 1, maxLines: fit`: a tall card is all
    /// commits down to one trailing fold, never more lines than it measured.
    func testCondenseFillsTheRowsTheCardHasRoomFor() {
        let lines = GitGraph.condense(linear(30), remotes: [], newest: 14, maxLines: 15)
        XCTAssertEqual(shape(lines), (0..<14).map { "c\($0)" } + ["+16"])
    }

    private func shape(_ lines: [GraphLine]) -> [String] {
        lines.map {
            switch $0 {
            case .commit(let row): return row.commit.sha
            case .gap(let count, _): return "+\(count)"
            }
        }
    }

    /// A pushed straight history keeps the newest three and folds the rest.
    func testCondenseFoldsAPushedStraightHistory() {
        let rows = linear(10, refs: [0: ["HEAD -> main", "origin/main"]])
        let lines = GitGraph.condense(rows, remotes: ["origin"])
        XCTAssertEqual(shape(lines), ["c0", "c1", "c2", "+7"])
        XCTAssertEqual(lines[3].edges, [GraphEdge(from: 0, to: 0)])
    }

    /// Commits above the remote ref are unpushed and stay; the ref's own commit
    /// stays for its label. A local "feature/x" is not mistaken for a remote.
    func testCondenseKeepsUnpushedCommitsAndRefs() {
        let rows = linear(8, refs: [0: ["HEAD -> main"], 3: ["origin/main"], 5: ["feature/x"]])
        XCTAssertEqual(shape(GitGraph.condense(rows, remotes: ["origin"], newest: 1)),
                       ["c0", "c1", "c2", "c3", "+1", "c5", "+2"])
    }

    /// No remote ref in view: nothing counts as unpushed, or nothing would fold.
    func testCondenseWithoutRemotesStillFolds() {
        XCTAssertEqual(shape(GitGraph.condense(linear(6), remotes: [], newest: 1)), ["c0", "+5"])
    }

    /// Merges and fork points are landmarks; the plain commit between them folds.
    func testCondenseKeepsMergesAndForkPoints() {
        let rows = GitGraph.layout([.init(sha: "m", parents: ["b", "f"]),
                                    .init(sha: "f", parents: ["a"]),
                                    .init(sha: "b", parents: ["a"]),
                                    .init(sha: "a", parents: ["z"]),
                                    .init(sha: "z", parents: [])])
        XCTAssertEqual(shape(GitGraph.condense(rows, remotes: [], newest: 1)), ["m", "+2", "a", "+1"])
    }

    func testCondenseCapsTheLineCount() {
        let refs = Dictionary(uniqueKeysWithValues: (0..<30).map { ($0, ["tag: v\($0)"]) })
        XCTAssertEqual(GitGraph.condense(linear(30, refs: refs), remotes: [], maxLines: 10).count, 10)
    }

    /// The window's pane is App Kit's ground now, and the cards sit lighter than it.
    func testLabelAndMarksClearContrastOnThePane() {
        XCTAssertGreaterThanOrEqual(contrastRatio(Color.Ink.labelLight, Color.Ink.paneLight), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(Color.Ink.labelDark, Color.Ink.paneDark), 4.5)
        for mark in Color.Ink.marks {
            XCTAssertGreaterThanOrEqual(contrastRatio(mark.light, Color.Ink.paneLight), 3, "\(mark.name) light")
            XCTAssertGreaterThanOrEqual(contrastRatio(mark.dark, Color.Ink.paneDark), 3, "\(mark.name) dark")
        }
        for (light, dark) in [(Color.Ink.series1Light, Color.Ink.series1Dark)] {
            XCTAssertGreaterThanOrEqual(contrastRatio(light, Color.Ink.cardLight), 3, "series1 on the card, light")
            XCTAssertGreaterThanOrEqual(contrastRatio(dark, Color.Ink.cardDark), 3, "series1 on the card, dark")
        }
    }

    // MARK: - Logic fixes

    func testPaceIsNotJudgedInTheFirstMomentsOfAWindow() {
        XCTAssertFalse(StatFormat.aheadOfPace(pct: 1, elapsed: 0.005), "1% just after a reset")
        XCTAssertTrue(StatFormat.aheadOfPace(pct: 40, elapsed: 0.2))
        XCTAssertFalse(StatFormat.aheadOfPace(pct: 10, elapsed: 0.2))
        XCTAssertFalse(StatFormat.aheadOfPace(pct: 30, elapsed: 0.2, margin: 0.15), "inside the margin")
    }

    func testNumstatSumsAddedAndRemovedAndSkipsBinaries() {
        XCTAssertEqual(GitParse.numstatLines("10\t2\ta.swift\n-\t-\timg.png\n3\t0\tb.md\n"), 15)
        XCTAssertEqual(GitParse.numstatLines(""), 0)
    }

    /// Claude's last sentence sits further back than the cheap tail when a turn
    /// filled it with tool output; the reader looks again for that field.
    func testTranscriptFindsClaudesTextBeyondTheTail() throws {
        let said = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Far back."}]}}"#
        let tool = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#
        let filler = #"{"type":"user","message":{"content":"\#(String(repeating: "x", count: 4000))"}}"#
        let lines = [said] + Array(repeating: filler, count: 20) + [tool]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("far-tail-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        // The setup has to put the text outside the first tail, or this proves nothing.
        let data = try Data(contentsOf: url)
        XCTAssertNil(TranscriptReader.parse(String(decoding: data.suffix(20_000), as: UTF8.self),
                                            droppingFirstLine: true).lastAssistantText)
        XCTAssertEqual(TranscriptReader.read(path: url.path, tailBytes: 20_000).lastAssistantText, "Far back.")
        XCTAssertNil(TranscriptReader.read(path: url.path, tailBytes: 2_000).lastAssistantText,
                     "beyond even the far tail stays not recorded")
    }

    // MARK: - Critique helpers

    func testShownRefsDropOnlyTheRemoteHead() {
        XCTAssertEqual(GitGraph.shownRefs(["HEAD -> main", "origin/main", "origin/HEAD"]),
                       ["HEAD -> main", "origin/main"])
        XCTAssertEqual(GitGraph.shownRefs(["tag: v1"]), ["tag: v1"])
        XCTAssertEqual(GitGraph.shownRefs([]), [])
    }

    /// Working and blocked subagents stay listed; idle and finished ones are
    /// counted, including one sitting at an idle prompt, which asks nothing.
    func testSubagentSplitListsLiveOnesAndCountsTheRest() {
        let now = Date()
        var idlePrompt = mk("c", .attention, updated: now, parentSessionId: "p")
        idlePrompt.notificationType = "idle_prompt"
        var permission = mk("d", .attention, updated: now, parentSessionId: "p")
        permission.notificationType = "permission_prompt"
        let split = SubagentSplit([mk("a", .tool, updated: now, parentSessionId: "p"),
                                   mk("b", .idle, updated: now, parentSessionId: "p"),
                                   idlePrompt, permission,
                                   mk("e", .thinking, updated: now, parentSessionId: "p")], now: now)
        XCTAssertEqual(split.live.map(\.id), ["a", "d", "e"])
        XCTAssertEqual(split.finished.map(\.id), ["b", "c"])
        XCTAssertTrue(SubagentSplit([]).finished.isEmpty)
    }

    /// Finished ones drop out after 30 minutes; live ones stay whatever their age,
    /// and one with no timestamp is not counted as recent.
    func testFinishedSubagentsAgeOutAfterHalfAnHour() {
        let now = Date(timeIntervalSince1970: 10_000)
        let split = SubagentSplit([mk("recent", .idle, updated: now.addingTimeInterval(-29 * 60), parentSessionId: "p"),
                                   mk("stale", .idle, updated: now.addingTimeInterval(-31 * 60), parentSessionId: "p"),
                                   mk("undated", .idle, parentSessionId: "p"),
                                   mk("live", .tool, updated: now.addingTimeInterval(-3_600), parentSessionId: "p")],
                                  now: now)
        XCTAssertEqual(split.finished.map(\.id), ["recent"])
        XCTAssertEqual(split.live.map(\.id), ["live"])
    }

    /// Only the missing-PR reason is hidden; gh missing and auto-merge disallowed
    /// still show with no PR open.
    func testAutoMergeCaptionHidesOnlyTheMissingPR() {
        XCTAssertTrue(GitAutomation.autoMergeLacksOnlyAPR(repo { $0.ghInstalled = true; $0.pr = .none }))
        XCTAssertFalse(GitAutomation.autoMergeLacksOnlyAPR(repo { $0.ghInstalled = false; $0.pr = .none }))
        XCTAssertFalse(GitAutomation.autoMergeLacksOnlyAPR(repo {
            $0.ghInstalled = true; $0.autoMergeAllowed = false; $0.pr = .none }))
        XCTAssertFalse(GitAutomation.autoMergeLacksOnlyAPR(repo {
            $0.ghInstalled = true; $0.pr = .open(number: 3, url: "u", draft: false) }))
    }

    // MARK: - Pane fit

    func testPaneFitGivesLeftoverHeightToTheTopRowWhenItFits() {
        let fit = PaneFit.fit(available: 900, ideal: 700)
        XCTAssertEqual(fit.scale, 1)
        XCTAssertEqual(fit.extra, 200)
    }

    func testPaneFitShrinksATallPaneAndHandsOutNothing() {
        let fit = PaneFit.fit(available: 600, ideal: 800)
        XCTAssertEqual(fit.scale, 0.75, accuracy: 0.0001)
        XCTAssertEqual(fit.extra, 0)
    }

    func testPaneFitStopsAtTheFloorAndScrolls() {
        let fit = PaneFit.fit(available: 100, ideal: 1000)
        XCTAssertEqual(fit.scale, PaneFit.floor)
        XCTAssertEqual(fit.extra, 0)
        XCTAssertTrue(fit.scrolls)
        XCTAssertFalse(PaneFit.fit(available: 600, ideal: 800).scrolls, "fits by shrinking")
        XCTAssertFalse(PaneFit.fit(available: 900, ideal: 700).scrolls)
    }

    func testContextTintFollowsTheWindowShareWhenKnown() {
        XCTAssertEqual(Color.contextPercent(tokens: 500_000, window: 1_000_000), 50)
        XCTAssertEqual(Color.contextTint(tokens: 210_000, window: 1_000_000), Color.usageTint(21))
        XCTAssertNotEqual(Color.contextTint(tokens: 210_000, window: 1_000_000), Color.contextTint(210_000),
                          "210k is red by tokens, green by share of 1M")
        XCTAssertEqual(Color.contextTint(tokens: 210_000, window: nil), Color.contextTint(210_000))
    }

    /// Before the first layout there is no ideal to fit against.
    func testPaneFitWithNoIdealYetDrawsAtFullSize() {
        XCTAssertEqual(PaneFit.fit(available: 900, ideal: 0).scale, 1)
        XCTAssertEqual(PaneFit.fit(available: 900, ideal: 0).extra, 0)
    }

    // MARK: - Column buckets

    // MARK: - Suggestion

    private func suggestionInput(_ configure: (inout Suggestion.Input) -> Void = { _ in }) -> Suggestion.Input {
        var input = Suggestion.Input(git: nil, contextPercent: nil, contextTokens: 100_000, atPrompt: true,
                                     idleFor: 0, fiveHourPct: nil, fiveHourElapsed: nil,
                                     installed: ["/wrap-up", "/git-push", "/start-up"])
        configure(&input)
        return input
    }

    private func skillInput(_ configure: (inout Suggestion.Input) -> Void) -> Suggestion.Input {
        suggestionInput {
            $0.installed = ["/wrap-up", "/start-up", "/simplify", "/goal", "/clear"]
            $0.contextTokens = 60_000
            configure(&$0)
        }
    }

    private func picked(_ input: Suggestion.Input) -> String? {
        guard case .command(let c)? = Suggestion.skill(input)?.action else { return nil }
        return c
    }

    /// Each rule fires on its own facts, in priority order.
    func testSkillPickFollowsTheSessionsState() {
        XCTAssertEqual(picked(skillInput { $0.contextPercent = 90 }), "/wrap-up")
        XCTAssertEqual(picked(skillInput { $0.contextPercent = 70 }), "/compact")
        XCTAssertEqual(picked(skillInput { $0.contextTokens = 160_000 }), "/wrap-up")
        XCTAssertEqual(picked(skillInput { $0.contextTokens = 160_000; $0.wrappedUp = true
                                           $0.git = self.repo { _ in } }), "/clear")
        XCTAssertEqual(picked(skillInput { $0.contextTokens = 160_000; $0.wrappedUp = true
                                           $0.git = self.repo { $0.dirty = 1 } }), "/wrap-up")
        XCTAssertEqual(picked(skillInput { $0.contextTokens = 160_000; $0.wrappedUp = true
                                           $0.git = self.repo { $0.sync = .ahead(1) } }), "/wrap-up")
        XCTAssertEqual(picked(skillInput { $0.contextTokens = 120_000 }), "/compact")
        // A working session is not told to wrap up on size alone; over 85% still is.
        XCTAssertNil(picked(skillInput { $0.contextTokens = 160_000; $0.atPrompt = false }))
        XCTAssertEqual(picked(skillInput { $0.contextPercent = 90; $0.atPrompt = false }), "/wrap-up")
        XCTAssertEqual(picked(skillInput { $0.idleFor = 40 * 60 }), "/wrap-up")
        XCTAssertEqual(picked(skillInput { $0.contextTokens = 5_000 }), "/start-up")
        XCTAssertEqual(picked(skillInput { $0.todoTotal = 3; $0.todoDone = 3; $0.git = self.repo { $0.dirty = 2 } }),
                       "/wrap-up")
        XCTAssertEqual(picked(skillInput { $0.git = self.repo { $0.dirty = 2; $0.dirtyLines = 240 } }), "/simplify")
        XCTAssertEqual(picked(skillInput { $0.projectOpenTasks = 4 }), "/goal")
        XCTAssertEqual(picked(skillInput { $0.todoTotal = 3; $0.todoDone = 1 }), "/goal")
        XCTAssertEqual(picked(skillInput { $0.idleFor = 12 * 60; $0.linesChanged = 30; $0.git = self.repo { _ in } }),
                       "/wrap-up")
    }

    /// Known-good: a mid-sized, committed, taskless session picks nothing, and
    /// the rules that need a dirty tree or an idle prompt don't fire without one.
    func testSkillPickStaysQuietWithoutAReason() {
        XCTAssertNil(picked(skillInput { _ in }))
        XCTAssertNil(picked(skillInput { $0.linesChanged = 240; $0.git = self.repo { _ in } }))
        XCTAssertNil(picked(skillInput { $0.projectOpenTasks = 4; $0.atPrompt = false }))
        XCTAssertNil(picked(skillInput { $0.projectOpenTasks = 4; $0.todoTotal = 2; $0.todoDone = 2 }))
        XCTAssertNil(picked(skillInput { $0.git = self.repo { $0.dirty = 1; $0.dirtyLines = 240 }
                                         $0.installed = ["/wrap-up"] }))
        // A big session with a small uncommitted diff has nothing to simplify.
        XCTAssertNil(picked(skillInput { $0.linesChanged = 600; $0.git = self.repo { $0.dirty = 1; $0.dirtyLines = 3 } }))
        XCTAssertNil(picked(skillInput { $0.todoTotal = 3; $0.todoDone = 1; $0.atPrompt = false }))
        XCTAssertNil(picked(skillInput { $0.contextTokens = 120_000; $0.atPrompt = false }))
        XCTAssertNil(picked(skillInput { $0.contextTokens = 90_000 }))
        XCTAssertNil(picked(skillInput { $0.idleFor = 12 * 60; $0.linesChanged = 30; $0.git = self.repo { $0.dirty = 1 } }))
        XCTAssertNil(picked(skillInput { $0.idleFor = 12 * 60; $0.linesChanged = 30
                                         $0.git = self.repo { $0.sync = .ahead(2) } }))
        XCTAssertNil(picked(skillInput { $0.idleFor = 12 * 60; $0.git = self.repo { _ in } }))
        XCTAssertNil(picked(skillInput { $0.idleFor = 5 * 60; $0.linesChanged = 30; $0.git = self.repo { _ in } }))
    }

    func testOpenTasksStopAtCompleted() {
        let text = "## Tasks\n- [ ] a\n- [x] b\n  - [ ] c\n## Completed\n- [ ] stale\n"
        XCTAssertEqual(Suggestion.openTasks(inTasksFile: text), 2)
        XCTAssertNil(Suggestion.openTasks(inTasksFile: "## Tasks\n- [x] done\n"))
    }

    private func repo(_ configure: (inout GitSnapshot) -> Void) -> GitSnapshot {
        var snap = GitSnapshot()
        snap.branch = "main"
        snap.upstream = "origin/main"
        snap.isDefaultBranch = true
        snap.sync = .inSync
        snap.pr = .none
        snap.ci = .finished(workflow: "CI", conclusion: "success", url: "u")
        configure(&snap)
        return snap
    }

    /// Known-good: a clean, synced, green repo with a light context suggests nothing.
    func testNothingToSuggestForASettledSession() {
        XCTAssertNil(Suggestion.next(suggestionInput { $0.git = self.repo { _ in } }))
    }

    func testFailedCIOutranksEverythingElse() {
        let s = Suggestion.next(suggestionInput {
            $0.contextPercent = 90
            $0.git = self.repo { $0.ci = .finished(workflow: "CI", conclusion: "failure", url: "u"); $0.sync = .ahead(2) }
        })
        XCTAssertEqual(s?.action, .git(.openCI))
    }

    func testContextSuggestsCompactThenWrapUp() {
        XCTAssertEqual(Suggestion.next(suggestionInput { $0.contextPercent = 65 })?.action, .command("/compact"))
        XCTAssertEqual(Suggestion.next(suggestionInput { $0.contextPercent = 90 })?.action, .command("/wrap-up"))
    }

    func testUnpushedCommitsSuggestPushAndDirtyIdleSuggestsGitPush() {
        XCTAssertEqual(Suggestion.next(suggestionInput { $0.git = self.repo { $0.sync = .ahead(1) } })?.action,
                       .git(.push))
        let dirty = Suggestion.next(suggestionInput { $0.git = self.repo { $0.dirty = 3 } })
        XCTAssertEqual(dirty?.action, .command("/git-push"))
        // Not while Claude is mid-turn: typing would land in the middle of it.
        XCTAssertNil(Suggestion.next(suggestionInput { $0.atPrompt = false; $0.git = self.repo { $0.dirty = 3 } }))
    }

    /// A skill that isn't installed is never suggested.
    func testUninstalledSkillIsSkipped() {
        let s = Suggestion.next(suggestionInput {
            $0.installed = []
            $0.git = self.repo { $0.dirty = 3 }
        })
        XCTAssertNil(s)
    }

    func testFeatureBranchWithoutPRSuggestsCreatePR() {
        let s = Suggestion.next(suggestionInput {
            $0.git = self.repo { $0.branch = "feature"; $0.upstream = "origin/feature"; $0.isDefaultBranch = false }
        })
        XCTAssertEqual(s?.action, .git(.createPR))
    }

    // MARK: - Session config

    func testConfigCommandsAndCurrentModel() {
        XCTAssertEqual(SessionConfig.modelCommand("sonnet"), "/model sonnet")
        XCTAssertEqual(SessionConfig.effortCommand("xhigh"), "/effort xhigh")
        XCTAssertTrue(SessionConfig.isCurrent("opus", model: "Opus 5.5"))
        XCTAssertFalse(SessionConfig.isCurrent("sonnet", model: "Opus 5.5"))
        XCTAssertFalse(SessionConfig.isCurrent("opus", model: nil))
        // The costs are said before the switch, not discovered after it.
        XCTAssertTrue(SessionConfig.modelConfirmation("Sonnet").contains("default for new sessions"))
        XCTAssertTrue(SessionConfig.modelConfirmation("Sonnet").contains("uncached"))
    }

    // MARK: - Git automation

    private let settingsSample = """
    {
      "hooks": {
        "Stop": [
          {
            "matcher": "",
            "hooks": [
              {
                "type": "command",
                "command": "~/bin/context-stamp.sh"
              },
              {
                "type": "command",
                "command": "bash ~/.claude/bin/auto-push.sh"
              }
            ]
          }
        ]
      }
    }
    """

    /// Known-good round trip: on inserts one entry that still parses, off takes
    /// it back out to the original text byte for byte.
    func testAutoCommitHookRoundTripsAsATextEdit() throws {
        let on = try XCTUnwrap(GitAutomation.enablingAutoCommit(in: settingsSample))
        XCTAssertTrue(GitAutomation.autoCommitEnabled(settings: on))
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(on.utf8)) as? [String: Any])
        XCTAssertTrue(on.contains("        \"command\": \"bash ~/bin/auto-commit.sh\""))
        // Already on: nothing to insert.
        XCTAssertNil(GitAutomation.enablingAutoCommit(in: on))
        let off = try XCTUnwrap(GitAutomation.disablingAutoCommit(in: on))
        XCTAssertEqual(off, settingsSample)
        XCTAssertNil(GitAutomation.disablingAutoCommit(in: settingsSample))
    }

    /// Without the auto-push anchor there is no safe place to put it.
    func testAutoCommitNeedsTheAutoPushAnchor() {
        XCTAssertNil(GitAutomation.enablingAutoCommit(in: #"{"hooks": {}}"#))
    }

    func testAutoMergeParseKeepsUnknownApartFromOff() {
        XCTAssertEqual(GitParse.autoMerge(json: Data(#"{"autoMergeRequest":null}"#.utf8)), false)
        XCTAssertEqual(GitParse.autoMerge(json: Data(#"{"autoMergeRequest":{"mergeMethod":"SQUASH"}}"#.utf8)), true)
        XCTAssertNil(GitParse.autoMerge(json: Data(#"{"number":3}"#.utf8)))
    }

    func testAutoPROnlyForAPushedFeatureBranchWithoutAPR() {
        var snap = GitSnapshot()
        snap.branch = "feature"
        snap.sync = .inSync
        snap.pr = .none
        XCTAssertTrue(GitAutomation.shouldCreatePR(snap))
        snap.pr = .unknown
        XCTAssertFalse(GitAutomation.shouldCreatePR(snap), "unknown is not none")
        snap.pr = .none
        snap.sync = .ahead(1)
        XCTAssertFalse(GitAutomation.shouldCreatePR(snap), "not pushed yet")
        snap.sync = .inSync
        snap.isDefaultBranch = true
        XCTAssertFalse(GitAutomation.shouldCreatePR(snap))
    }

    func testAutoFixNeedsAnOpenPR() {
        var snap = GitSnapshot()
        snap.pr = .none
        XCTAssertNotNil(GitAutomation.autoFixUnavailableReason(snap))
        snap.pr = .open(number: 2, url: "u", draft: false)
        XCTAssertNil(GitAutomation.autoFixUnavailableReason(snap))
        XCTAssertTrue(GitAutomation.autoFixConfirmation.contains("under your GitHub account"))
    }

    func testAutoMergeCommands() {
        var snap = GitSnapshot()
        XCTAssertNil(GitAutomation.autoMergeCommand(enable: true, snapshot: snap))
        snap.pr = .open(number: 7, url: "u", draft: false)
        XCTAssertEqual(GitAutomation.autoMergeCommand(enable: true, snapshot: snap)?.args,
                       ["pr", "merge", "7", "--auto", "--squash", "--delete-branch"])
        XCTAssertEqual(GitAutomation.autoMergeCommand(enable: false, snapshot: snap)?.args,
                       ["pr", "merge", "7", "--disable-auto"])
    }

    // MARK: - Skill shortcuts

    /// Built-ins always show; a skill or command shows only when its file exists.
    func testShortcutsHideWhatIsNotInstalled() {
        let dir = URL(fileURLWithPath: "/c")
        let installed: Set<String> = ["/c/skills/wrap-up/SKILL.md", "/c/commands/goal.md"]
        let names = SkillShortcut.available(claudeDir: dir, exists: installed.contains).map(\.name)
        XCTAssertEqual(names, ["wrap-up", "compact", "clear", "code-review", "simplify", "goal"])
        let none = SkillShortcut.available(claudeDir: dir, exists: { _ in false }).map(\.name)
        XCTAssertEqual(none, ["compact", "clear", "code-review", "simplify"])
    }

    /// The two mail skills are curated, plain (not built-in) skill chips, and
    /// each shows only when its own SKILL.md is installed.
    func testMailShortcutsAreCuratedAndGatedOnInstall() {
        let email = SkillShortcut.curated.first { $0.name == "email" }
        let recruiter = SkillShortcut.curated.first { $0.name == "recruiter-mail" }
        XCTAssertEqual(email?.command, "/email")
        XCTAssertEqual(email?.label, "email")
        XCTAssertEqual(email?.symbol, "envelope")
        XCTAssertEqual(email?.blurb, "Scan Gmail + Apple Mail for action items")
        XCTAssertEqual(recruiter?.command, "/recruiter-mail")
        XCTAssertEqual(recruiter?.label, "recruiter-mail")
        XCTAssertEqual(recruiter?.symbol, "person.crop.circle.badge.questionmark")
        XCTAssertEqual(recruiter?.blurb, "Triage recruiter and interview messages")
        for chip in [email, recruiter] {
            XCTAssertEqual(chip?.builtIn, false)
            XCTAssertEqual(chip?.group, .skill)
            XCTAssertNil(chip?.sessionAction)
        }
        let dir = URL(fileURLWithPath: "/c")
        let both: Set<String> = ["/c/skills/email/SKILL.md", "/c/skills/recruiter-mail/SKILL.md"]
        let found = SkillShortcut.available(claudeDir: dir, exists: both.contains).map(\.name)
        XCTAssertTrue(found.contains("email") && found.contains("recruiter-mail"))
        let onlyEmail = SkillShortcut.available(claudeDir: dir, exists: ["/c/skills/email/SKILL.md"].contains).map(\.name)
        XCTAssertTrue(onlyEmail.contains("email"))
        XCTAssertFalse(onlyEmail.contains("recruiter-mail"))
        let none = SkillShortcut.available(claudeDir: dir, exists: { _ in false }).map(\.name)
        XCTAssertFalse(none.contains("email") || none.contains("recruiter-mail"))
    }

    /// The card's /clear and /compact ask first, like the toolbar's; skills don't.
    func testDestructiveShortcutsConfirm() {
        let confirming = SkillShortcut.curated.filter { $0.sessionAction?.isDestructive == true }.map(\.name)
        XCTAssertEqual(confirming, ["compact", "clear"])
        XCTAssertEqual(SkillShortcut.curated.first { $0.name == "clear" }?.sessionAction?.confirmation,
                       SessionAction.clear.confirmation)
    }

    /// Fetch, Open CI and Open repo are the quiet row; the rest are state actions.
    func testGitToolsAreTheAlwaysRunnableActions() {
        XCTAssertEqual(GitAction.allCases.filter(\.isTool), [.fetch, .openCI, .openRepo])
    }

    /// A clone of a bundle file rejects every push, so Push is settled-hidden
    /// even when ahead; the same ahead branch on GitHub can push (known-good).
    func testABundleRemoteCannotBePushed() {
        var snap = GitSnapshot()
        snap.branch = "main"
        snap.upstream = "origin/main"
        snap.sync = .ahead(1)
        snap.pr = .none
        snap.remoteURL = "/Users/home/Tools/osmo.bundle"
        XCTAssertEqual(GitActions.unavailableReason(.push, snapshot: snap)?.settled, true)
        XCTAssertEqual(GitActions.unavailableReason(.createPR, snapshot: snap)?.settled, true)
        XCTAssertNil(GitActions.unavailableReason(.fetch, snapshot: snap))
        snap.remoteURL = "https://github.com/danieldecena/osmo-footage-library.git"
        XCTAssertNil(GitActions.unavailableReason(.push, snapshot: snap))
    }

    /// "true false" -> private, auto-merge off; a failed or odd read is nil,
    /// never false.
    func testRepoSettingsParse() {
        XCTAssertTrue(GitParse.repoSettings("true false\n") == (true, false))
        XCTAssertTrue(GitParse.repoSettings("false true") == (false, true))
        XCTAssertTrue(GitParse.repoSettings("true null") == (true, nil))
        XCTAssertTrue(GitParse.repoSettings("") == (nil, nil))
    }

    /// The self-enable fires only on a PR that reads off and can take it:
    /// unread (nil) is not "off", and a dirty tree or a draft holds it back.
    func testAutoMergeEnablesItselfOnlyWhenReadOffAndEligible() {
        var snap = GitSnapshot()
        snap.pr = .open(number: 7, url: "u", draft: false)
        snap.autoMerge = false
        XCTAssertTrue(GitAutomation.shouldEnableAutoMerge(snap))
        snap.autoMerge = nil
        XCTAssertFalse(GitAutomation.shouldEnableAutoMerge(snap), "unread is not off")
        snap.autoMerge = true
        XCTAssertFalse(GitAutomation.shouldEnableAutoMerge(snap))
        snap.autoMerge = false
        snap.pr = .open(number: 7, url: "u", draft: true)
        XCTAssertFalse(GitAutomation.shouldEnableAutoMerge(snap))
        snap.pr = .none
        XCTAssertFalse(GitAutomation.shouldEnableAutoMerge(snap))
    }

    /// One claim per PR, shared by the card and the watcher, so the two never
    /// both fire and a hand-off is not undone on the next tick.
    @MainActor func testAutoMergeIsClaimedOncePerPR() {
        let top = "/tmp/claim-\(UUID().uuidString)"
        XCTAssertTrue(AutoPRWatcher.shared.claimAutoMerge(toplevel: top, number: 7))
        XCTAssertFalse(AutoPRWatcher.shared.claimAutoMerge(toplevel: top, number: 7))
        XCTAssertTrue(AutoPRWatcher.shared.claimAutoMerge(toplevel: top, number: 8))
    }

    /// GitHub's own setting is the first blocker; unread (nil) is not "off", and
    /// an open PR on a repo that allows it can be switched on (known-good).
    func testAutoMergeSaysWhyItCantBeUsed() {
        var snap = GitSnapshot()
        snap.pr = .open(number: 7, url: "u", draft: false)
        snap.autoMergeAllowed = false
        XCTAssertEqual(GitAutomation.autoMergeUnavailableReason(snap)?.hasPrefix("GitHub has auto-merge off"), true)
        snap.autoMergeAllowed = nil
        XCTAssertNil(GitAutomation.autoMergeUnavailableReason(snap))
        snap.autoMergeAllowed = true
        XCTAssertNil(GitAutomation.autoMergeUnavailableReason(snap))
        snap.pr = .none
        XCTAssertEqual(GitAutomation.autoMergeUnavailableReason(snap), "There is no open PR on this branch.")
    }

    /// A clean, pushed default branch dims both git skills; work to act on lights them.
    func testGitSkillsIdleOnACleanPushedTree() {
        let push = SkillShortcut.curated.first { $0.name == "git-push" }!
        let review = SkillShortcut.curated.first { $0.name == "code-review" }!
        var snap = GitSnapshot()
        snap.sync = .inSync
        snap.isDefaultBranch = true
        XCTAssertNotNil(SkillShortcut.idleReason(push, snapshot: snap))
        XCTAssertNotNil(SkillShortcut.idleReason(review, snapshot: snap))
        XCTAssertNil(SkillShortcut.idleReason(push, snapshot: nil))

        snap.sync = .ahead(2)
        XCTAssertNil(SkillShortcut.idleReason(push, snapshot: snap))
        XCTAssertNotNil(SkillShortcut.idleReason(review, snapshot: snap))

        snap.sync = .inSync
        snap.dirty = 1
        XCTAssertNil(SkillShortcut.idleReason(push, snapshot: snap))
        XCTAssertNil(SkillShortcut.idleReason(review, snapshot: snap))

        snap.dirty = 0
        snap.isDefaultBranch = false
        XCTAssertNil(SkillShortcut.idleReason(review, snapshot: snap))
        let simplify = SkillShortcut.curated.first { $0.name == "simplify" }!
        XCTAssertNil(SkillShortcut.idleReason(simplify, snapshot: snap))
    }

    /// A namespaced command is found in its subdirectory and labelled without
    /// the namespace.
    func testSuperpowerShortcutsResolveTheirSubdirectory() {
        let dir = URL(fileURLWithPath: "/c")
        let installed: Set<String> = ["/c/commands/superpower/debug.md"]
        let found = SkillShortcut.available(claudeDir: dir, exists: installed.contains)
            .filter { $0.group == .superpower }
        XCTAssertEqual(found.map(\.command), ["/superpower:debug"])
        XCTAssertEqual(found.first?.label, "debug")
    }

    func testGitShortcutsAreGroupedApart() {
        let git = SkillShortcut.curated.filter { $0.group == .git }.map(\.name)
        XCTAssertEqual(git, ["code-review", "git-push"])
        XCTAssertEqual(SkillShortcut.curated.filter { $0.group == .tasks }.map(\.name), ["todo"])
    }

    func testNewSessionListsYourProjectsOnDisk() {
        let json = Data(#"""
        {"projects": {
          "zeta": {"path": "~/developer/zeta"},
          "Alpha": {"path": "/abs/alpha", "third_party_owner": null},
          "vendor": {"path": "~/developer/vendor", "third_party_owner": "someone"},
          "gone": {"path": "~/developer/gone"},
          "nopath": {}
        }}
        """#.utf8)
        let dirs: Set<String> = ["/h/developer/zeta", "/abs/alpha", "/h/developer/vendor"]
        let found = NewSession.projects(registryJSON: json, home: "/h", isDirectory: dirs.contains)
        XCTAssertEqual(found?.map(\.name), ["Alpha", "zeta"])
        XCTAssertEqual(found?.last?.path, "/h/developer/zeta")
        // Unreadable is unknown, not an empty list.
        XCTAssertNil(NewSession.projects(registryJSON: nil, home: "/h", isDirectory: dirs.contains))
        XCTAssertNil(NewSession.projects(registryJSON: Data("{}".utf8), home: "/h", isDirectory: dirs.contains))
        XCTAssertEqual(NewSession.projects(registryJSON: Data(#"{"projects":{}}"#.utf8), home: "/h",
                                           isDirectory: dirs.contains), [])
    }

    func testNewSessionScriptQuotesThePath() {
        let script = NewSession.appleScript(for: #"/tmp/a "b"\c"#)
        XCTAssertTrue(script.contains(#"set initial working directory of cfg to "/tmp/a \"b\"\\c""#))
        XCTAssertTrue(script.contains(#"set command of cfg to "/bin/zsh -lic claude""#))
    }

    /// Arguments have to reach `claude` intact through the shell that `zsh -lic`
    /// runs. Checked by running the command string through sh with a stand-in
    /// `claude` that prints each argument, using a prompt with every character
    /// that breaks a naive quote.
    func testNewSessionCommandDeliversArgumentsIntact() throws {
        XCTAssertEqual(NewSession.command(claudeArgs: []), "/bin/zsh -lic claude")

        let prompt = #"it's a "test" $HOME `x` \n"#
        let command = NewSession.command(claudeArgs: ["--resume", prompt])
        let prefix = "/bin/zsh -lic "
        XCTAssertTrue(command.hasPrefix(prefix))
        // sh -c "<the -c string zsh would get>", with `claude` replaced by a printer.
        let line = String(command.dropFirst(prefix.count))
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", "claude() { for a in \"$@\"; do printf '[%s]' \"$a\"; done; }; eval \(line)"]
        let out = Pipe()
        sh.standardOutput = out
        try sh.run()
        sh.waitUntilExit()
        let printed = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(printed, "[--resume][\(prompt)]")
    }

    func testNewSessionScriptCarriesTheCommand() {
        let script = NewSession.appleScript(for: "/tmp/p", claudeArgs: ["-c"])
        XCTAssertTrue(script.contains(#"set command of cfg to "/bin/zsh -lic 'claude '\\''-c'\\'''""#), script)
    }

    func testTasksFileListsOpenTitlesAndCountsDoneEverywhere() {
        let text = """
        # Tasks
        ## Active
        - [ ] Ship the Tasks card
        - [x] Fix the refused compact -- 4dc133b
          - [ ]   Indented follow-up
        ## Completed
        - [ ] Stale item below Completed
        - [X] Old one
        """
        let tasks = Suggestion.tasks(inTasksFile: text)
        XCTAssertEqual(tasks.open, ["Ship the Tasks card", "Indented follow-up"])
        XCTAssertEqual(tasks.done, 2)
        XCTAssertEqual(Suggestion.openTasks(inTasksFile: text), 2)
        XCTAssertTrue(Suggestion.tasks(inTasksFile: "").open.isEmpty)
        XCTAssertNil(Suggestion.openTasks(inTasksFile: "- [x] all done"))
    }

    // MARK: - Usage visuals

    func testWindowElapsedPlacesNowInsideTheWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fiveHours: TimeInterval = 5 * 3600
        // Reset in 1h of a 5h window: 80% through.
        XCTAssertEqual(FeedWatcher.windowElapsed(resetsAt: 1_000_000 + 3600, length: fiveHours, now: now)!,
                       0.8, accuracy: 0.0001)
        XCTAssertNil(FeedWatcher.windowElapsed(resetsAt: nil, length: fiveHours, now: now))
        // Already reset: stale, not "100% through".
        XCTAssertNil(FeedWatcher.windowElapsed(resetsAt: 1_000_000 - 1, length: fiveHours, now: now))
        XCTAssertNil(FeedWatcher.windowElapsed(resetsAt: 1_000_000 + fiveHours + 60, length: fiveHours, now: now))
    }

    // MARK: - UsageTotalsPoller.parse (ccusage JSON -> Result)

    private let activeBlock = Data("""
        {"blocks":[{"isActive":true,"totalTokens":5000,"projection":{"totalTokens":9000,"remainingMinutes":104}}]}
        """.utf8)
    private let noBlock = Data(#"{"blocks":[]}"#.utf8)

    /// Known-good: today is the matching period row, week sums every row.
    func testTotalsParseSumsWeekAndPicksToday() {
        let daily = Data("""
            {"daily":[{"period":"2026-09-28","totalTokens":1000,"totalCost":3.25,
                       "modelBreakdowns":[{"outputTokens":1000,"cost":3.25}]},
                      {"period":"2026-09-29","totalTokens":500,"totalCost":1.5,
                       "modelBreakdowns":[{"outputTokens":500,"cost":1.5},{"outputTokens":0,"cost":0}]}]}
            """.utf8)
        let r = UsageTotalsPoller.parse(daily: daily, blocks: activeBlock, today: "2026-09-29", now: Date())
        XCTAssertEqual(r?.todayTokens, 500)
        XCTAssertEqual(r?.todayCost, 1.5)
        XCTAssertEqual(r?.weekTokens, 1500)
        XCTAssertEqual(r?.weekCost, 4.75)
        XCTAssertEqual(r?.block?.tokens, 5000)
        XCTAssertEqual(r?.block?.projectedTokens, 9000)
        XCTAssertEqual(r?.block?.remainingMinutes, 104)
        XCTAssertEqual(r?.days, [.init(period: "2026-09-28", tokens: 1000),
                                 .init(period: "2026-09-29", tokens: 500)])
    }

    /// The 2026-09-29 flake: a model with tokens but $0 means ccusage failed to
    /// price it, so that day's and the week's cost are unknown, not low. Tokens
    /// stay, and a clean day in the same week keeps no cost of its own either.
    func testTotalsParseUnpricedModelMakesCostUnknown() {
        let daily = Data("""
            {"daily":[{"period":"a","totalTokens":10,"totalCost":1.84,
                       "modelBreakdowns":[{"outputTokens":5,"cost":1.84},{"cacheReadTokens":5,"cost":0}]},
                      {"period":"b","totalTokens":4,"totalCost":2,
                       "modelBreakdowns":[{"outputTokens":4,"cost":2}]}]}
            """.utf8)
        let r = UsageTotalsPoller.parse(daily: daily, blocks: noBlock, today: "b", now: Date())
        XCTAssertNil(r?.weekCost)
        XCTAssertEqual(r?.todayCost, 2)
        XCTAssertEqual(r?.weekTokens, 14)
        let unpricedToday = UsageTotalsPoller.parse(daily: daily, blocks: noBlock, today: "a", now: Date())
        XCTAssertNil(unpricedToday?.todayCost)
    }

    /// Output that isn't ccusage's shape is a failure, never a zero.
    func testTotalsParseRejectsMalformed() {
        let good = Data(#"{"daily":[]}"#.utf8)
        XCTAssertNil(UsageTotalsPoller.parse(daily: Data("not json".utf8), blocks: noBlock, today: "x", now: Date()))
        XCTAssertNil(UsageTotalsPoller.parse(daily: good, blocks: Data("{}".utf8), today: "x", now: Date()))
        XCTAssertNil(UsageTotalsPoller.parse(daily: Data(#"{"daily":[{"period":"x"}]}"#.utf8),
                                             blocks: noBlock, today: "x", now: Date()))
    }

    /// An empty week is an observed zero, distinct from a failed parse.
    func testTotalsParseEmptyDailyIsZero() {
        let r = UsageTotalsPoller.parse(daily: Data(#"{"daily":[]}"#.utf8), blocks: noBlock, today: "x", now: Date())
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.todayTokens, 0)
        XCTAssertEqual(r?.weekCost, 0)
    }

    /// No active block leaves the block nil while day/week survive.
    func testTotalsParseNoActiveBlock() {
        let daily = Data(#"{"daily":[{"period":"d","totalTokens":7,"totalCost":0.5,"modelBreakdowns":[{"outputTokens":7,"cost":0.5}]}]}"#.utf8)
        let r = UsageTotalsPoller.parse(daily: daily, blocks: noBlock, today: "d", now: Date())
        XCTAssertEqual(r?.todayTokens, 7)
        XCTAssertNil(r?.block)
    }

    // MARK: - Graph card

    private func graphJSON(_ communities: [String: Int], links: Int = 2,
                           commit: String? = "abc1234") -> Data {
        var nodes: [[String: Any]] = []
        for (name, count) in communities {
            for _ in 0..<count { nodes.append(["id": "n", "community_name": name]) }
        }
        var root: [String: Any] = ["nodes": nodes,
                                   "links": Array(repeating: ["source": "a", "target": "b"], count: links)]
        if let commit { root["built_at_commit"] = commit }
        return try! JSONSerialization.data(withJSONObject: root)
    }

    func testGraphSummaryCountsAndRanksCommunities() {
        let summary = try! XCTUnwrap(GraphSummary.parse(
            graphJSON(["Equatable": 5, "FeedWatcher": 3, "Tiny": 1]), topCommunities: 2))
        XCTAssertEqual(summary.nodes, 9)
        XCTAssertEqual(summary.links, 2)
        XCTAssertEqual(summary.builtAtCommit, "abc1234")
        // Largest first, and cut to the top N.
        XCTAssertEqual(summary.communities.map(\.name), ["Equatable", "FeedWatcher"])
        XCTAssertEqual(summary.communities.map(\.count), [5, 3])
    }

    /// A node with no community is counted in `nodes` but into no bar: an
    /// "unknown" bar the size of everything unclustered would say nothing.
    func testGraphSummaryLeavesUnclusteredNodesOutOfTheBars() {
        let data = try! JSONSerialization.data(withJSONObject: [
            "nodes": [["id": "a", "community_name": "One"], ["id": "b"], ["id": "c", "community_name": ""]],
            "links": [],
        ])
        let summary = try! XCTUnwrap(GraphSummary.parse(data))
        XCTAssertEqual(summary.nodes, 3)
        XCTAssertEqual(summary.communities.map(\.name), ["One"])
    }

    /// Anything that is not a graph is nil, never a summary of zeroes -- a card
    /// reading "0 nodes" would be a claim about the repo rather than about the
    /// read. An empty graph is a different case and does summarise.
    func testGraphSummaryRefusesWhatIsNotAGraph() {
        XCTAssertNil(GraphSummary.parse(Data("not json".utf8)))
        XCTAssertNil(GraphSummary.parse(Data("[1,2,3]".utf8)))
        XCTAssertNil(GraphSummary.parse(Data(#"{"links":[]}"#.utf8)))
        XCTAssertNil(GraphSummary.parse(Data(#"{"nodes":[]}"#.utf8)))
        let empty = try! XCTUnwrap(GraphSummary.parse(Data(#"{"nodes":[],"links":[]}"#.utf8)))
        XCTAssertEqual(empty.nodes, 0)
        XCTAssertTrue(empty.communities.isEmpty)
        XCTAssertNil(empty.builtAtCommit)
    }

    func testGraphPathIsInsideTheRepoRoot() {
        XCTAssertEqual(GraphSummary.path(forRepo: "/x/y"), "/x/y/graphify-out/graph.json")
    }

    // MARK: - Menu bar title

    func testMenuBarTitleKeepsTheGlyphInAFixedSlot() {
        func content(_ glyph: String, _ text: String?) -> MenuBarTitle.Content {
            MenuBarTitle.Content(glyph: glyph, glyphColor: .white, text: text, textColor: .white, spoken: "")
        }
        let narrow = MenuBarTitle.attributed(content("✶", "Working… 12s"))
        let wide = MenuBarTitle.attributed(content("✶✶", "Working… 12s"))
        XCTAssertEqual(narrow.string, "\t✶\tWorking… 12s")
        // The whole point of the tab stops: a wider glyph, the same width.
        XCTAssertEqual(narrow.size().width, wide.size().width, accuracy: 0.01)
        // The control: the same two glyphs without the stops do differ, or the
        // assertion above could not fail.
        let font = NSFont(name: "Menlo", size: 15)!
        XCTAssertNotEqual(NSAttributedString(string: "✶", attributes: [.font: font]).size().width,
                          NSAttributedString(string: "✶✶", attributes: [.font: font]).size().width)
        // No text, no second tab.
        XCTAssertEqual(MenuBarTitle.attributed(content("✻", nil)).string, "\t✻")
    }

    func testMenuBarContentComparesEqualOnlyWhenItDrawsTheSame() {
        let a = MenuBarTitle.Content(glyph: "✻", glyphColor: .white, text: "38%", textColor: .white, spoken: "x")
        var b = a
        XCTAssertEqual(a, b)
        b.glyph = "✺"
        XCTAssertNotEqual(a, b)
    }

    // MARK: - TileGrid packing

    func testACardThatDrewNothingTakesNoRow() {
        // The control: the same three spans with every card drawn occupy two
        // rows, so a test that always reported one row would fail here.
        let drawn = TileGrid.pack(spans: [3, 3, 3], heights: [100, 100, 100], columns: 3)
        XCTAssertEqual(drawn.count, 3)

        let absent = TileGrid.pack(spans: [3, 3, 3], heights: [100, 0, 100], columns: 3)
        XCTAssertEqual(absent.count, 2, "an empty tile must not pack a row of its own")
        XCTAssertEqual(absent.flatMap { $0 }.map(\.index), [0, 2])
    }

    func testCardsFillARowBeforeWrapping() {
        let packed = TileGrid.pack(spans: [1, 2, 1, 1], heights: [10, 10, 10, 10], columns: 3)
        XCTAssertEqual(packed.map { $0.map(\.index) }, [[0, 1], [2, 3]])
        XCTAssertEqual(packed[0].map(\.column), [0, 1])
        XCTAssertEqual(packed[1].map(\.column), [0, 1])
    }

    func testARowsLastCardTakesTheColumnsLeftOverWhenAsked() {
        // The control: without the flag the two-wide card leaves column 2 bare.
        let bare = TileGrid.pack(spans: [1, 2, 2, 1], heights: [10, 10, 10, 10], columns: 3)
        XCTAssertEqual(bare.map { $0.map(\.span) }, [[1, 2], [2, 1]])
        XCTAssertEqual(TileGrid.pack(spans: [2, 2], heights: [10, 10], columns: 3).map { $0.map(\.span) },
                       [[2], [2]])

        let filled = TileGrid.pack(spans: [2, 2, 1], heights: [10, 10, 10], columns: 3, fillsRows: true)
        XCTAssertEqual(filled.map { $0.map(\.span) }, [[3], [2, 1]], "alone in its row, a card takes the row")
        XCTAssertEqual(filled.map { $0.map(\.column) }, [[0], [0, 2]])
        // A full row is left as it was packed.
        XCTAssertEqual(TileGrid.pack(spans: [1, 2], heights: [10, 10], columns: 3, fillsRows: true)
                        .map { $0.map(\.span) }, [[1, 2]])
    }

    func testASpanWiderThanTheGridIsClampedToIt() {
        let packed = TileGrid.pack(spans: [9], heights: [10], columns: 3)
        XCTAssertEqual(packed.first?.first?.span, 3)
    }

    func testLeftoverHeightGoesToTheLastRow() {
        let placed = TileGrid.placedHeights(rows: [100, 100], spacing: 12, available: 400)
        XCTAssertEqual(placed, [100, 288], "212 of slack belongs to the last row alone")
        XCTAssertEqual(placed.reduce(0, +) + 12, 400, accuracy: 0.001)
    }

    func testAGridSizedToItsContentKeepsEveryRowHeight() {
        // The known-good input: without it, a helper that always stretched the
        // last row would pass the test above and still be wrong everywhere else.
        let exact = TileGrid.placedHeights(rows: [100, 100], spacing: 12, available: 212)
        XCTAssertEqual(exact, [100, 100])
        let squeezed = TileGrid.placedHeights(rows: [100, 100], spacing: 12, available: 50)
        XCTAssertEqual(squeezed, [100, 100], "a grid given less than it needs scrolls, it does not shrink")
    }

    // MARK: - GoalClock

    private func goalLine(remaining: Int, minutes: Int, now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> GoalClock? {
        GoalClock.parse("\(Int(now.timeIntervalSince1970) + remaining) \(minutes)\n", now: now)
    }

    func testGoalClockMidRun() {
        let clock = goalLine(remaining: 87 * 60 + 30, minutes: 120)
        XCTAssertEqual(clock?.minutesLeft, 87)
        XCTAssertEqual(clock?.originalMinutes, 120)
        XCTAssertEqual(clock?.isLanding, false)
        XCTAssertEqual(clock?.isOverrun, false)
        XCTAssertEqual(clock?.label, "GOAL  87 min left")
    }

    func testGoalClockReserveBoundary() {
        // 100 minutes reserves 10.
        XCTAssertEqual(goalLine(remaining: 11 * 60, minutes: 100)?.isLanding, false)
        XCTAssertEqual(goalLine(remaining: 11 * 60, minutes: 100)?.label, "GOAL  11 min left")
        XCTAssertEqual(goalLine(remaining: 10 * 60 + 59, minutes: 100)?.isLanding, true)
        XCTAssertEqual(goalLine(remaining: 10 * 60, minutes: 100)?.label, "GOAL  landing, 10 min left")
        XCTAssertEqual(goalLine(remaining: 9 * 60, minutes: 100)?.label, "GOAL  landing, 9 min left")
    }

    func testGoalClockReserveFloorsAtOneMinute() {
        // 5 minutes would reserve 0 by division; the floor is 1.
        XCTAssertEqual(goalLine(remaining: 60, minutes: 5)?.reserveMinutes, 1)
        XCTAssertEqual(goalLine(remaining: 60, minutes: 5)?.isLanding, true)
        XCTAssertEqual(goalLine(remaining: 2 * 60, minutes: 5)?.isLanding, false)
    }

    func testGoalClockUnderAMinuteIsNeverZero() {
        let clock = goalLine(remaining: 59, minutes: 30)
        XCTAssertEqual(clock?.label, "GOAL  landing, <1 min left")
        XCTAssertEqual(clock?.isOverrun, false)
    }

    func testGoalClockOverrun() {
        XCTAssertEqual(goalLine(remaining: 0, minutes: 30)?.label, "GOAL  over by <1 min")
        XCTAssertEqual(goalLine(remaining: -90, minutes: 30)?.label, "GOAL  over by 1 min")
        let clock = goalLine(remaining: -7 * 60, minutes: 30)
        XCTAssertEqual(clock?.isOverrun, true)
        XCTAssertEqual(clock?.isLanding, false)
        XCTAssertEqual(clock?.label, "GOAL  over by 7 min")
    }

    func testGoalClockStaleFileIsUnknownNotOverrun() {
        XCTAssertNil(goalLine(remaining: -GoalClock.staleAfter, minutes: 30))
        XCTAssertNotNil(goalLine(remaining: -GoalClock.staleAfter + 60, minutes: 30))
    }

    func testGoalClockRejectsMalformedAndAcceptsWellFormed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let future = Int(now.timeIntervalSince1970) + 3600
        // Known-BAD: each must be unknown, never a clock.
        for bad in [nil, "", "   \n", "abc", "\(future)", "\(future) 60 7", "\(future) sixty",
                    "soon 60", "\(future) -60", "\(future) 0", "-5 60", "\(future) 6.5"] as [String?] {
            XCTAssertNil(GoalClock.parse(bad, now: now), "\(bad ?? "nil") should be unknown")
        }
        // Known-GOOD: the same parser must yield a value, or the rejections prove nothing.
        XCTAssertEqual(GoalClock.parse("\(future) 60", now: now)?.minutesLeft, 60)
        XCTAssertEqual(GoalClock.parse("\(future)\t60\n", now: now)?.minutesLeft, 60)
        XCTAssertEqual(GoalClock.parse("  \(future)  60  ", now: now)?.originalMinutes, 60)
    }

    func testGoalClockRefreshWaitLandsOnTheNextMinuteBoundary() {
        XCTAssertEqual(goalLine(remaining: 87 * 60 + 30, minutes: 120)?.secondsUntilLabelChanges, 31)
        XCTAssertEqual(goalLine(remaining: 87 * 60, minutes: 120)?.secondsUntilLabelChanges, 61)
        XCTAssertEqual(goalLine(remaining: -(60 + 20), minutes: 120)?.secondsUntilLabelChanges, 41)
    }

    func testGoalDeadlineFileMissingIsNilAndPresentIsRead() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("goal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(GoalDeadlineFile.read(pane: "%3", in: dir))
        try "1800000000 30\n".write(to: dir.appendingPathComponent("goal-deadline-%3"), atomically: true, encoding: .utf8)
        XCTAssertEqual(GoalDeadlineFile.read(pane: "%3", in: dir), "1800000000 30\n")
        XCTAssertNil(GoalDeadlineFile.read(pane: "%4", in: dir))
    }

}
