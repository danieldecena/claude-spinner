//
//  MailCardTests.swift
//  claude spinnerTests
//
//  The Mail card's status-file parsing, its age label, and the failure and
//  missing-file cases. Fixtures are strings and temp files; nothing here runs
//  the real scan or touches ~/.claude.
//

import XCTest
@testable import claude_spinner

final class MailCardTests: XCTestCase {

    private let goodJSON = """
    {"updated": "2026-10-02T15:23:59.589354-07:00", "days": 3,
     "counts": {"act": 7, "reply": 2, "ci": 1, "finance": 19},
     "threads": 104, "unread": 49,
     "by_account": {"gmail10": 97, "icloud": 14, "gmail11": 0},
     "no_inbox_files": ["gmail11"], "parse_failures": 4, "ok": true}
    """

    private func temp(_ name: String = "mail.status.json") -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mailcard-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent(name)
    }

    func testParsesAGoodStatusFile() {
        guard case .ok(let s) = MailStatusFile.parse(Data(goodJSON.utf8)) else {
            return XCTFail("expected .ok")
        }
        XCTAssertEqual(s.urgent, 7)
        XCTAssertEqual(s.thisWeek, 2)
        XCTAssertEqual(s.ci, 1)
        XCTAssertEqual(s.finance, 19)
        XCTAssertEqual(s.unread, 49)
        XCTAssertEqual(s.parseFailures, 4)
        XCTAssertEqual(s.noInboxFiles, ["gmail11"])
        XCTAssertEqual(MailStatusFile.countsLine(s), "7 urgent · 2 this week · 1 CI · 19 finance")
        // 15:23:59 at -07:00 is 22:23:59 UTC; the microseconds are dropped.
        XCTAssertEqual(s.updated, ISO8601DateFormatter().date(from: "2026-10-02T22:23:59Z"))
    }

    func testUnknownUnreadStaysNilNotZero() {
        let json = goodJSON.replacingOccurrences(of: "\"unread\": 49", with: "\"unread\": null")
        guard case .ok(let s) = MailStatusFile.parse(Data(json.utf8)) else { return XCTFail("expected .ok") }
        XCTAssertNil(s.unread)
    }

    func testOkFalseCarriesTheReasonAndNoCounts() {
        let json = #"{"ok": false, "updated": "2026-10-02T15:00:00-07:00", "error": "mail store not readable"}"#
        guard case .failed(let error, let updated) = MailStatusFile.parse(Data(json.utf8)) else {
            return XCTFail("expected .failed")
        }
        XCTAssertEqual(error, "mail store not readable")
        XCTAssertNotNil(updated)
    }

    func testGarbageAndShapeMismatchesAreNoDataYet() {
        XCTAssertEqual(MailStatusFile.parse(Data("not json".utf8)), .none)
        XCTAssertEqual(MailStatusFile.parse(Data()), .none)
        XCTAssertEqual(MailStatusFile.parse(Data("[1,2]".utf8)), .none)
        XCTAssertEqual(MailStatusFile.parse(Data(#"{"ok": true}"#.utf8)), .none)
        XCTAssertEqual(MailStatusFile.parse(Data(#"{"counts": {}}"#.utf8)), .none)
    }

    func testMissingFileIsNoDataYet() {
        XCTAssertEqual(MailStatusFile.load(from: temp()), .none)
    }

    func testLoadReadsATempFile() throws {
        let url = temp()
        try goodJSON.write(to: url, atomically: true, encoding: .utf8)
        guard case .ok(let s) = MailStatusFile.load(from: url) else { return XCTFail("expected .ok") }
        XCTAssertEqual(s.finance, 19)
    }

    func testUpdatedLabel() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func label(_ ago: TimeInterval) -> String { MailStatusFile.updatedLabel(now.addingTimeInterval(-ago), now: now) }
        XCTAssertEqual(MailStatusFile.updatedLabel(nil, now: now), "never")
        XCTAssertEqual(label(5), "updated just now")
        XCTAssertEqual(label(12 * 60 + 20), "updated 12 min ago")
        XCTAssertEqual(label(3 * 3600 + 5), "updated 3 h ago")
        XCTAssertEqual(label(2 * 86_400), "updated 2 d ago")
        XCTAssertEqual(label(-30), "updated just now", "a clock a little ahead must not print a negative age")
    }

    func testStatusFileIsNotASessionFeedFile() {
        // FeedWatcher prunes any "<id>.status.json" older than its cutoff; the
        // Mail card's file must be exempt or it deletes itself.
        XCTAssertEqual(MailStatusFile.defaultURL().lastPathComponent, "mail.status.json")
    }

    func testScanFailureSurfacesExitCodeAndStderr() throws {
        let script = temp("fail.py")
        try "import sys\nsys.stderr.write('boom\\n')\nsys.exit(3)\n".write(to: script, atomically: true, encoding: .utf8)
        let result = MailStatusFile.runScan(script: script, statusFile: temp())
        XCTAssertEqual(result, MailRefreshError(message: "scan exited 3: boom"))
    }

    func testScanSuccessAndMissingScript() throws {
        let script = temp("ok.py")
        try "print('x' * 1000)\n".write(to: script, atomically: true, encoding: .utf8)
        XCTAssertNil(MailStatusFile.runScan(script: script, statusFile: temp()))
        XCTAssertEqual(MailStatusFile.runScan(script: temp("nope.py"), statusFile: temp()),
                       MailRefreshError(message: "mail_scan.py not found"))
    }
}
