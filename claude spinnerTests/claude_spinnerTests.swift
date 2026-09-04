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

    // MARK: - End-to-end join: real state JSON -> SessionFeed.todoProgress -> TodoProgressBar

    /// The real call site is `TodoProgressBar(total: session.todoProgress.total,
    /// done: session.todoProgress.done)` in `SessionRow`. Task 2's tests stop at
    /// `SessionFeed.todoTotal`/`todoDone`; Task 3's tests start from bare `Int`s.
    /// This is the one test that walks the whole path a real feed file takes.
    func testTodoProgressEndToEndFromDecodedStateJSON() throws {
        var s = SessionFeed(id: "x")
        try s.applyStateJSONForTest("""
        {"todo_total":3,"todo_done":1}
        """)
        let progress = s.todoProgress
        XCTAssertEqual(progress.total, 3)
        XCTAssertEqual(progress.done, 1)
        XCTAssertEqual(TodoProgressBar.percent(total: progress.total, done: progress.done), 33)
        XCTAssertEqual(TodoProgressBar.filledBoxes(total: progress.total, done: progress.done), 3)
    }

    /// A session with no todos yet decodes to nil counts, which `todoProgress`
    /// coalesces to `(0, 0)` — the bar draws empty, not a crash or a misleading 0%.
    func testTodoProgressEndToEndWithNoTodosYet() throws {
        var s = SessionFeed(id: "x")
        try s.applyStateJSONForTest("{}")
        let progress = s.todoProgress
        XCTAssertEqual(progress.total, 0)
        XCTAssertEqual(progress.done, 0)
        XCTAssertEqual(TodoProgressBar.percent(total: progress.total, done: progress.done), 0)
        XCTAssertEqual(TodoProgressBar.filledBoxes(total: progress.total, done: progress.done), 0)
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
        XCTAssertTrue(contents.contains("pgrep -x \"claude spinner\""),
                      "ask.sh must not write an ask file with no app to answer it")
        XCTAssertTrue(contents.contains("passthrough"))
        XCTAssertTrue(contents.contains("multiSelect"),
                      "ask.sh must pass multiSelect questions through to the terminal")
        // Comments are stripped first: the script says "must never exit 2" in
        // prose, and matching that would make this pass for the wrong reason.
        let code = contents.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
        XCTAssertFalse(code.contains("exit 2"),
                       "exit 2 reads as a deny on PreToolUse — the fallback must be exit 0")
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

    func testTodoProgressBarMath() {
        XCTAssertEqual(TodoProgressBar.percent(total: 0, done: 0), 0)
        XCTAssertEqual(TodoProgressBar.filledBoxes(total: 0, done: 0), 0)

        XCTAssertEqual(TodoProgressBar.percent(total: 3, done: 1), 33)
        XCTAssertEqual(TodoProgressBar.filledBoxes(total: 3, done: 1), 3)  // round(10/3) = 3

        XCTAssertEqual(TodoProgressBar.percent(total: 3, done: 3), 100)
        XCTAssertEqual(TodoProgressBar.filledBoxes(total: 3, done: 3), 10)
    }

    /// `done` can come from a state file written by a different process/repo, so
    /// the Swift layer can't assume it's ever validated against `total`. Before the
    /// clamp, `done > total` sent `filled` past `boxCount` and
    /// `String(repeating:count:)` trapped on the resulting negative count — a
    /// state-file value from another process could crash the whole app.
    func testTodoProgressBarMathClampsOutOfRangeDone() {
        XCTAssertEqual(TodoProgressBar.percent(total: 3, done: 5), 100)
        XCTAssertEqual(TodoProgressBar.filledBoxes(total: 3, done: 5), 10)

        XCTAssertEqual(TodoProgressBar.percent(total: 3, done: -2), 0)
        XCTAssertEqual(TodoProgressBar.filledBoxes(total: 3, done: -2), 0)
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
    /// for it at all post-fix-2 — it moved to line 2 with the todo bar — so a
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
        let narrow: CGFloat = 300
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
    /// doesn't include status or the todo bar — those live on line 2 now).
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
            - TodoProgressBar.width
            - RowLayout.todoStatusGap - RowLayout.dotsSlot
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
        try withTempDir { dir in
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
}
