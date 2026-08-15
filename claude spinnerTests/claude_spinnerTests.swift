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
                    updated: Date? = nil, lastDuration: Int? = nil,
                    tokens: Int? = nil) -> SessionFeed {
        var s = SessionFeed(id: id)
        s.status = status; s.cwd = cwd; s.updated = updated; s.lastDuration = lastDuration
        s.contextInputTokens = tokens
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

    /// Spare width lands on the name *up to the cap*. This test asserted the
    /// uncapped rule until 2026-08-12 — at `panelWidth` 470 every one of these cases
    /// now sits at `maxNameWidth`, so the old strict inequalities were the first
    /// thing the cap broke. What still has to hold is that the name flexes with the
    /// space available, which shows below the cap.
    func testSpareWidthGoesToTheNameUpToTheCap() {
        let short = RowLayout.columns(statusLabels: ["done"], models: ["opus"],
                                      panelWidth: Constants.panelWidth)
        let long = RowLayout.columns(statusLabels: ["running bash"], models: ["opus"],
                                     panelWidth: Constants.panelWidth)
        XCTAssertEqual(short.name, RowLayout.maxNameWidth)
        XCTAssertEqual(long.name, RowLayout.maxNameWidth)
        XCTAssertGreaterThan(long.name, 105, "still beats the old fixed 105pt column")

        // Below the cap the original rule is intact: a longer status and a wider
        // model word each take from the name.
        let narrow = Constants.panelMinWidth
        XCTAssertGreaterThan(
            RowLayout.columns(statusLabels: ["done"], models: ["opus"], panelWidth: narrow).name,
            RowLayout.columns(statusLabels: ["running bash"], models: ["opus"], panelWidth: narrow).name)
        XCTAssertGreaterThan(
            RowLayout.columns(statusLabels: ["done"], models: ["opus"], panelWidth: narrow).name,
            RowLayout.columns(statusLabels: ["done"], models: ["sonnet"], panelWidth: narrow).name)
    }

    /// The name's floor wins, and the model gives way before the status does.
    func testNameFloorHoldsAndModelGivesWayFirst() {
        let c = RowLayout.columns(
            statusLabels: ["running " + String(repeating: "x", count: 200)],
            models: ["sonnet"], panelWidth: Constants.panelWidth)
        XCTAssertEqual(c.name, RowLayout.minNameWidth)
        XCTAssertEqual(c.model, 0)
        XCTAssertGreaterThan(c.status, 0)
    }

    /// The columns must never exceed the row's budget. They no longer have to *fill*
    /// it: since the name is capped at `maxNameWidth`, a row with short labels leaves
    /// slack, which `SessionRow`'s `maxWidth: .infinity` status column absorbs. The
    /// assertion is therefore `<=`, not `==` — the equality held only while the name
    /// swallowed every spare point.
    func testColumnsNeverOverrunTheirBudget() {
        let budget = Constants.panelWidth - Constants.rowFixedColumns
        for label in ["done", "needs input", "running bash", "running TodoWrite",
                      "running " + String(repeating: "x", count: 200)] {
            for model in ["opus", "sonnet", ""] {
                let c = RowLayout.columns(statusLabels: [label], models: [model],
                                          panelWidth: Constants.panelWidth)
                XCTAssertLessThanOrEqual(c.name + c.model + RowLayout.dotsSlot + c.status,
                                         budget + 0.01,
                                         "\"\(label)\"/\"\(model)\" overruns the row")
                XCTAssertGreaterThanOrEqual(c.name, RowLayout.minNameWidth, "name floor broken")
                XCTAssertLessThanOrEqual(c.name, RowLayout.maxNameWidth, "name cap broken")
            }
        }
    }

    /// A long tool name still claims the slack the cap frees, rather than it being
    /// lost: the widest status label this panel can hold grows past what it would
    /// have had when the name took everything.
    func testFreedWidthIsAvailableToTheStatusColumn() {
        let short = RowLayout.columns(statusLabels: ["done"], models: ["opus"],
                                      panelWidth: Constants.panelWidth)
        let long = RowLayout.columns(statusLabels: ["running TodoWrite"], models: ["opus"],
                                     panelWidth: Constants.panelWidth)
        XCTAssertGreaterThan(long.status, short.status)
        XCTAssertLessThanOrEqual(long.name, RowLayout.maxNameWidth)
    }

    /// An empty panel has nothing to measure, so the name takes the whole remaining
    /// budget — capped, like every other case.
    func testEmptyPanelStillProducesASaneBudget() {
        let c = RowLayout.columns(statusLabels: [], models: [],
                                  panelWidth: Constants.panelWidth)
        XCTAssertEqual(c.model, 0)
        XCTAssertEqual(c.name, min(RowLayout.maxNameWidth,
                                   Constants.panelWidth - Constants.rowFixedColumns - RowLayout.dotsSlot))
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

    /// At the narrowest clamped width the row budget still holds: the name keeps its
    /// floor, the model sheds before the status, and the columns sum to the budget.
    func testColumnsHoldAtMinWidth() {
        let c = RowLayout.columns(
            statusLabels: ["running " + String(repeating: "x", count: 200)],
            models: ["sonnet"], panelWidth: Constants.panelMinWidth)
        XCTAssertEqual(c.name, RowLayout.minNameWidth)
        XCTAssertGreaterThanOrEqual(c.model, 0)
        XCTAssertGreaterThanOrEqual(c.status, 0)
        XCTAssertEqual(c.name + c.model + RowLayout.dotsSlot + c.status,
                       Constants.panelMinWidth - Constants.rowFixedColumns, accuracy: 0.01)
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
