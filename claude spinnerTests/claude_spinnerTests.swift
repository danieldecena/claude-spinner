//
//  claude_spinnerTests.swift
//  claude spinnerTests
//
//  Unit tests over the app's pure logic (no I/O, no UI): session display
//  derivation, spinner-word seeding, and duration formatting.
//

import XCTest
import SwiftUI
@testable import claude_spinner

final class claude_spinnerTests: XCTestCase {

    /// Build a bare session fixture for the pure-derivation tests.
    private func mk(_ id: String, _ status: SessionStatus, cwd: String = "/x",
                    updated: Date? = nil, lastDuration: Int? = nil) -> SessionFeed {
        var s = SessionFeed(id: id)
        s.status = status; s.cwd = cwd; s.updated = updated; s.lastDuration = lastDuration
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

    func testSortedOrdersByRankThenRecency() {
        let now = Date()
        let sorted = FeedWatcher.sorted([
            mk("i", .idle, updated: now),
            mk("w", .tool, updated: now.addingTimeInterval(-100)),
            mk("a", .attention, updated: now.addingTimeInterval(-200)),
        ])
        XCTAssertEqual(sorted.map(\.id), ["a", "w", "i"])
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
}
