//
//  claude_spinnerTests.swift
//  claude spinnerTests
//
//  Unit tests over the app's pure logic (no I/O, no UI): session display
//  derivation, spinner-word seeding, and duration formatting.
//

import XCTest
@testable import claude_spinner

final class claude_spinnerTests: XCTestCase {

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
}
