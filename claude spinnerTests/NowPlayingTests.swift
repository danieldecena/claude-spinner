//
//  NowPlayingTests.swift
//  claude spinnerTests
//
//  The rule that matters is that Music is never launched, so most of these are
//  about what is NOT sent. Each "nothing is sent" case has a twin where Music is
//  open and something is: a fake that records every script, and a Music that is
//  never asked for anything, would otherwise pass for one that is never sent
//  anything.
//

import XCTest
@testable import claude_spinner

/// Counts the scripts it is handed, from any thread.
private final class ScriptLog: @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [String] = []
    var reply: ScriptOutcome = .ok("")
    var scripts: [String] { lock.lock(); defer { lock.unlock() }; return sent }
    func record(_ s: String) -> ScriptOutcome { lock.lock(); sent.append(s); lock.unlock(); return reply }
}

@MainActor
final class NowPlayingTests: XCTestCase {
    private let sep = NowPlayingScript.separator

    private func waitUntil(_ seconds: Double = 3, _ condition: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while !condition() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    // MARK: Never launch Music

    func testNothingIsSentWhileMusicIsClosed() {
        let log = ScriptLog()
        let model = NowPlaying(isRunning: { false }, run: log.record)
        model.refresh()
        model.perform(.playPause)
        model.perform(.next)
        model.seek(toFraction: 0.5)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(log.scripts, [], "no Apple Event may reach a Music that is not open")
        XCTAssertEqual(model.status, .notRunning)
    }

    /// The twin: with Music open the same call does send, so the test above is able
    /// to fail.
    func testAScriptIsSentWhenMusicIsOpen() {
        let log = ScriptLog()
        log.reply = .ok("Song\(sep)Artist\(sep)Album\(sep)playing\(sep)10.5\(sep)200")
        let model = NowPlaying(isRunning: { true }, run: log.record)
        model.refresh()
        waitUntil { !log.scripts.isEmpty }
        XCTAssertEqual(log.scripts.first, NowPlayingScript.read)
        waitUntil { if case .track = model.status { return true } else { return false } }
        guard case .track(let track) = model.status else { return XCTFail("expected a track, got \(model.status)") }
        XCTAssertEqual(track.title, "Song")
        XCTAssertTrue(track.isPlaying)
    }

    /// The same guard, inside every script: `is running` asks without launching, so
    /// even a Music that quits between the Swift check and the send is not started.
    func testEveryScriptChecksIsRunningBeforeItTalksToMusic() {
        let scripts = [NowPlayingScript.read, NowPlayingScript.artwork, NowPlayingScript.seek(to: 12)]
            + MusicControl.allCases.map(NowPlayingScript.command)
        for script in scripts {
            let first = script.components(separatedBy: "\n").first ?? ""
            XCTAssertTrue(first.hasPrefix("if application id \"com.apple.Music\" is running then"), first)
            XCTAssertTrue(script.contains("return \"notrunning\""), "the not-running branch answers without sending")
            let tell = script.range(of: "tell application id")
            let guardAt = script.range(of: "is running")
            XCTAssertNotNil(tell); XCTAssertNotNil(guardAt)
            XCTAssertLessThan(guardAt!.lowerBound, tell!.lowerBound, "the guard comes before the tell")
            XCTAssertFalse(script.contains("launch"), "nothing here may launch Music")
            XCTAssertFalse(script.contains("activate"), "nor bring it forward")
        }
    }

    // MARK: Reading

    func testParseKnownShapes() {
        XCTAssertEqual(NowPlayingScript.parse("notrunning"), .notRunning)
        XCTAssertEqual(NowPlayingScript.parse("stopped"), .idle)
        XCTAssertEqual(NowPlayingScript.parse(""), .idle)
        XCTAssertEqual(NowPlayingScript.parse("a\(sep)b"), .idle, "a short answer is not a track")
        let status = NowPlayingScript.parse("Nights\(sep)Frank Ocean\(sep)Blonde\(sep)playing\(sep)61,5\(sep)307,2")
        guard case .track(let t) = status else { return XCTFail("\(status)") }
        XCTAssertEqual(t.subtitle, "Frank Ocean \u{2014} Blonde")
        XCTAssertEqual(t.position, 61.5, accuracy: 0.001, "a comma decimal from the Mac's own locale")
        XCTAssertEqual(t.progress ?? -1, 61.5 / 307.2, accuracy: 0.0001)
    }

    func testPausedIsNotPlayingAndAStreamHasNoProgress() {
        guard case .track(let paused) = NowPlayingScript.parse("T\(sep)A\(sep)B\(sep)paused\(sep)1\(sep)0") else { return XCTFail() }
        XCTAssertFalse(paused.isPlaying)
        XCTAssertNil(paused.progress, "no length is unknown, not zero")
    }

    func testSubtitleDropsWhateverIsMissing() {
        XCTAssertEqual(NowPlayingTrack(title: "t", artist: "A", album: "", isPlaying: true, position: 0, duration: 1).subtitle, "A")
        XCTAssertEqual(NowPlayingTrack(title: "t", artist: "", album: "", isPlaying: true, position: 0, duration: 1).subtitle, "")
    }

    // MARK: Permission and controls

    func testADeniedAutomationPromptIsAStatusNotASilence() {
        let log = ScriptLog()
        log.reply = .denied
        let model = NowPlaying(isRunning: { true }, run: log.record)
        model.refresh()
        waitUntil { model.status == .denied }
        XCTAssertEqual(model.status, .denied)
        XCTAssertNotNil(model.unavailableReason(.next), "a control says why it is off")
    }

    func testControlsAreOffWithAReasonWhenMusicIsClosed() {
        let model = NowPlaying(isRunning: { false }, run: { _ in .failed })
        XCTAssertEqual(model.unavailableReason(.playPause), "Music isn\u{2019}t open.")
        XCTAssertEqual(model.unavailableReason(.next), "Music isn\u{2019}t open.")
    }

    func testAControlIsSentWhileATrackIsLoaded() {
        let log = ScriptLog()
        log.reply = .ok("Song\(sep)A\(sep)B\(sep)playing\(sep)1\(sep)100")
        let model = NowPlaying(isRunning: { true }, run: log.record)
        model.refresh()
        waitUntil { if case .track = model.status { return true } else { return false } }
        XCTAssertNil(model.unavailableReason(.next))
        let before = log.scripts.count
        model.perform(.next)
        waitUntil { log.scripts.contains(NowPlayingScript.command(.next)) }
        XCTAssertTrue(log.scripts.dropFirst(before).contains(NowPlayingScript.command(.next)))
    }

    // MARK: Music that stops answering

    /// A reply from a script that changes as the test asks: first a track, then
    /// failures, then a track again.
    private final class Scripted: @unchecked Sendable {
        private let lock = NSLock()
        private var outcomes: [ScriptOutcome] = []
        private(set) var calls = 0
        func push(_ o: ScriptOutcome) { lock.lock(); outcomes.append(o); lock.unlock() }
        func next(_ source: String) -> ScriptOutcome {
            lock.lock(); defer { lock.unlock() }
            calls += 1
            return outcomes.isEmpty ? .failed : outcomes.removeFirst()
        }
    }

    private var track: String { "Song\(sep)A\(sep)B\(sep)playing\(sep)1\(sep)100" }

    /// One miss is a hiccup: the last track stays, so the strip does not flicker.
    func testASingleFailedReadKeepsTheLastTrack() {
        let script = Scripted()
        script.push(.ok(track)); script.push(.failed)
        let model = NowPlaying(isRunning: { true }, run: script.next)
        model.refresh()
        waitUntil { if case .track = model.status { return true } else { return false } }
        model.refresh()
        waitUntil { script.calls >= 3 }   // the read, its artwork fetch, the failing read
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard case .track = model.status else { return XCTFail("one miss dropped the track: \(model.status)") }
    }

    /// Several in a row mean Music is not answering, which is not the same as the
    /// last thing it said: the status says so instead of showing a stale track.
    func testSeveralFailedReadsInARowAreUnreadableNotAStaleTrack() {
        let script = Scripted()
        script.push(.ok(track))
        let model = NowPlaying(isRunning: { true }, run: script.next)
        model.refresh()
        waitUntil { if case .track = model.status { return true } else { return false } }
        for _ in 0..<NowPlaying.failuresBeforeUnreadable { model.refresh(); RunLoop.current.run(until: Date().addingTimeInterval(0.15)) }
        waitUntil { model.status == .unreadable }
        XCTAssertEqual(model.status, .unreadable)
        XCTAssertEqual(model.unavailableReason(.next), "Music isn\u{2019}t answering.")
    }

    /// And it comes back by itself: the next good read replaces the warning.
    func testAnUnreadableMusicRecoversOnTheNextGoodRead() {
        let script = Scripted()
        let model = NowPlaying(isRunning: { true }, run: script.next)   // every read fails
        for _ in 0..<NowPlaying.failuresBeforeUnreadable { model.refresh(); RunLoop.current.run(until: Date().addingTimeInterval(0.15)) }
        waitUntil { model.status == .unreadable }
        XCTAssertEqual(model.status, .unreadable)
        script.push(.ok(track))
        model.refresh()
        waitUntil { if case .track = model.status { return true } else { return false } }
        guard case .track = model.status else { return XCTFail("did not recover: \(model.status)") }
    }
}
