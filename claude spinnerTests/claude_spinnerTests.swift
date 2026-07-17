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
}
