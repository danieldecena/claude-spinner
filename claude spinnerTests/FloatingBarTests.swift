//
//  FloatingBarTests.swift
//  claude spinnerTests
//
//  The rules that keep a half-typed reply safe: drafts are per session, and the
//  floating bar never changes who it speaks to while a draft is in its field.
//

import SwiftUI
import XCTest
@testable import claude_spinner

@MainActor
final class FloatingBarTests: XCTestCase {
    /// The plan's hand test, as a test: type in A, switch to B, type, go back to A,
    /// and A's text is intact.
    func testSwitchingSessionsKeepsEachDraft() {
        let drafts = ReplyDrafts()
        drafts.set("first thought", for: "A")
        XCTAssertEqual(drafts.text(for: "B"), "", "B starts empty, A's draft does not carry over")
        drafts.set("other words", for: "B")
        XCTAssertEqual(drafts.text(for: "A"), "first thought")
        XCTAssertEqual(drafts.text(for: "B"), "other words")
    }

    /// Both fields bind the same store, so typing in one is seen in the other.
    func testTwoBindingsToOneSessionShareTheText() {
        let drafts = ReplyDrafts()
        let bar = drafts.binding(for: "A"), card = drafts.binding(for: "A")
        bar.wrappedValue = "hello"
        XCTAssertEqual(card.wrappedValue, "hello")
    }

    func testClearingADraftRemovesItAndWhitespaceIsNotADraft() {
        let drafts = ReplyDrafts()
        drafts.set("x", for: "A")
        XCTAssertTrue(drafts.hasDraft("A"))
        drafts.set("", for: "A")
        XCTAssertFalse(drafts.hasDraft("A"))
        XCTAssertTrue(drafts.drafts.isEmpty, "an emptied field leaves no entry behind")
        drafts.set("  \n ", for: "B")
        XCTAssertFalse(drafts.hasDraft("B"), "spaces alone are not something to protect")
        XCTAssertFalse(drafts.hasDraft(nil))
    }

    private func choose(current: String? = "A", open: String? = nil, attention: String? = "B",
                        working: String? = "C", draft: Bool, exists: Bool = true) -> String? {
        BarTarget.choose(current: current, openSession: open, attention: attention,
                         recentlyWorking: working, currentHasDraft: draft, exists: { _ in exists })
    }

    /// The pair that matters: identical but for the draft. With one the bar holds,
    /// without it the bar moves to the session that needs you.
    func testBarHoldsItsTargetOnlyWhileADraftIsInTheField() {
        XCTAssertEqual(choose(draft: true), "A", "a draft pins the target")
        XCTAssertEqual(choose(draft: false), "B", "no draft: the session that needs you")
    }

    func testAttentionBeatsWorkingAndWorkingIsTheFallback() {
        XCTAssertEqual(choose(current: nil, draft: false), "B")
        XCTAssertEqual(choose(current: nil, attention: nil, draft: false), "C")
        XCTAssertNil(choose(current: nil, attention: nil, working: nil, draft: false))
    }

    /// An open session pane is the user's own choice: it wins even over a draft
    /// held for another session, whose draft stays in the store for when they return.
    func testAnOpenSessionAlwaysWins() {
        XCTAssertEqual(choose(open: "Z", draft: true), "Z")
    }

    /// A draft to a session that has ended cannot be held on to.
    func testADraftDoesNotPinAnEndedSession() {
        XCTAssertEqual(choose(draft: true, exists: false), "B")
    }

    func testWaitingCountsEveryOtherSessionThatNeedsYou() {
        XCTAssertEqual(BarTarget.waiting(attention: ["B", "A"], target: "A"), 1)
        XCTAssertEqual(BarTarget.waiting(attention: ["A"], target: "A"), 0)
        XCTAssertEqual(BarTarget.waiting(attention: ["B", "C"], target: "A"), 2)
        XCTAssertEqual(BarTarget.waiting(attention: [], target: nil), 0)
    }
}
