//
//  NowPlaying.swift
//
//  What the Music app is playing, and a remote for it (claude-spinner-playback
//  slices 1 and 2). Spinner is a remote, not a second player: it asks the Music
//  app over Apple Events and never plays anything itself.
//
//  The rule everything here serves: **never launch Music.** An Apple Event sent
//  to an app that is not running starts it, so nothing is sent unless Music is
//  already open -- checked in Swift before the call, and checked again inside the
//  script with `is running`, which asks without launching, for the instant
//  between the two.
//

import AppKit
import Combine

nonisolated struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    /// Seconds.
    var position: Double
    var duration: Double

    /// "Artist — Album", or whichever of the two there is.
    var subtitle: String { [artist, album].filter { !$0.isEmpty }.joined(separator: " \u{2014} ") }

    /// 0...1, nil when the length is not known (a stream).
    var progress: Double? {
        duration > 0 ? min(1, max(0, position / duration)) : nil
    }
}

nonisolated enum NowPlayingStatus: Equatable {
    /// Music is not open. Nothing was asked of it.
    case notRunning
    /// The user refused Automation for Spinner.
    case denied
    /// Music is open with nothing loaded.
    case idle
    case track(NowPlayingTrack)
}

nonisolated enum MusicControl: String, CaseIterable, Identifiable {
    case playPause, previous, next
    var id: String { rawValue }

    var title: String {
        switch self {
        case .playPause: return "Play or pause"
        case .previous: return "Previous track"
        case .next: return "Next track"
        }
    }

    var symbol: String {
        switch self {
        case .playPause: return "playpause.fill"
        case .previous: return "backward.fill"
        case .next: return "forward.fill"
        }
    }

    /// The AppleScript verb. `playpause` toggles; a `previous track` pressed a few
    /// seconds in restarts the song, as it does in Music itself.
    var verb: String {
        switch self {
        case .playPause: return "playpause"
        case .previous: return "previous track"
        case .next: return "next track"
        }
    }
}

/// How a script run ended. `denied` is -1743, errAEEventNotPermitted.
nonisolated enum ScriptOutcome: Equatable {
    case ok(String)
    case denied
    case failed
}

nonisolated enum NowPlayingScript {
    static let bundleID = "com.apple.Music"
    static let separator = "\u{1F}"

    /// Wraps a body so it only runs while Music is open. `is running` does not
    /// launch the app, which is the whole point of asking it here and not just in
    /// Swift.
    static func guarded(_ body: String) -> String {
        """
        if application id "\(bundleID)" is running then
            tell application id "\(bundleID)"
        \(body)
            end tell
        else
            return "notrunning"
        end if
        """
    }

    static let read = guarded("""
                if player state is stopped then return "stopped"
                set t to current track
                set d to ASCII character 31
                return (name of t) & d & (artist of t) & d & (album of t) & d & ((player state) as text) & d & ((player position) as text) & d & ((duration of t) as text)
        """)

    static func command(_ control: MusicControl) -> String {
        guarded("        \(control.verb)\n        return \"ok\"")
    }

    static func seek(to seconds: Double) -> String {
        guarded("        set player position to \(String(format: "%.2f", max(0, seconds)))\n        return \"ok\"")
    }

    /// The cover as raw bytes, which `NSImage(data:)` reads. `raw data`, not `data`:
    /// the latter is a picture object that has no bytes to hand over.
    static let artwork = guarded("""
                if player state is stopped then return ""
                return raw data of artwork 1 of current track
        """)

    // MARK: Parsing

    /// Turns the read script's answer into a status. Pure, so the shapes it has to
    /// survive are tested without Music.
    static func parse(_ text: String) -> NowPlayingStatus {
        switch text {
        case "notrunning": return .notRunning
        case "stopped", "": return .idle
        default: break
        }
        let parts = text.components(separatedBy: separator)
        guard parts.count == 6 else { return .idle }
        func number(_ s: String) -> Double {
            // The script writes numbers with the Mac's own decimal separator.
            Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        return .track(NowPlayingTrack(
            title: parts[0], artist: parts[1], album: parts[2],
            isPlaying: parts[3] == "playing",
            position: number(parts[4]), duration: number(parts[5])))
    }

    /// What Music's own track-change notification carries (`com.apple.Music.playerInfo`).
    /// It has no position, so a notification only says it is time to ask.
    static func isPlayerInfo(_ name: Notification.Name) -> Bool {
        name.rawValue == "com.apple.Music.playerInfo"
    }
}

@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()

    @Published private(set) var status: NowPlayingStatus = .notRunning
    @Published private(set) var artwork: NSImage?
    /// The cover's mean colour, for the bar's tint. nil with no cover.
    @Published private(set) var artworkAverage: BarTint.RGB?

    private let isRunning: () -> Bool
    private let run: (String) -> ScriptOutcome
    private var artworkKey = ""
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    /// `isRunning` and `run` are injectable so a test can prove, with a fake, that
    /// a Music that is not open is never sent a thing.
    init(isRunning: @escaping () -> Bool = NowPlaying.musicIsOpen,
         run: @escaping (String) -> ScriptOutcome = NowPlaying.runScript) {
        self.isRunning = isRunning
        self.run = run
    }

    nonisolated static func musicIsOpen() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: NowPlayingScript.bundleID).isEmpty
    }

    // MARK: Lifecycle

    /// Listens for Music's own track-change broadcast and for it opening or
    /// quitting, and ticks once a second while it is open so the position moves.
    func start() {
        guard observers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == NowPlayingScript.bundleID else { return }
                Task { @MainActor in self?.refresh() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        refresh()
    }

    /// The once-a-second tick asks only while Music is open and playing: a paused
    /// or closed Music has nothing that moves, so there is nothing to poll.
    private func tick() {
        guard isRunning() else {
            if status != .notRunning { status = .notRunning; artwork = nil; artworkAverage = nil }
            return
        }
        if case .track(let t) = status, t.isPlaying { refresh() }
    }

    // MARK: Reading

    func refresh() {
        guard isRunning() else {
            if status != .notRunning { status = .notRunning }
            artwork = nil
            artworkAverage = nil
            return
        }
        let run = self.run
        Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) { run(NowPlayingScript.read) }.value
            await MainActor.run { self?.apply(outcome) }
        }
    }

    private func apply(_ outcome: ScriptOutcome) {
        switch outcome {
        case .denied: status = .denied
        case .failed: break   // keep what was last known rather than flicker
        case .ok(let text):
            let next = NowPlayingScript.parse(text)
            if next != status { status = next }
            if case .track(let t) = next { loadArtworkIfNeeded(for: t) } else { artwork = nil; artworkAverage = nil; artworkKey = "" }
        }
    }

    private func loadArtworkIfNeeded(for track: NowPlayingTrack) {
        let key = track.title + "\u{1F}" + track.album
        guard key != artworkKey, isRunning() else { return }
        artworkKey = key
        let run = self.run
        Task { [weak self] in
            let image = await Task.detached(priority: .utility) { () -> NSImage? in
                guard case .ok(let encoded) = run(NowPlayingScript.artwork),
                      let data = Data(base64Encoded: encoded) else { return nil }
                return NSImage(data: data)
            }.value
            await MainActor.run {
                guard self?.artworkKey == key else { return }
                self?.artwork = image
                self?.artworkAverage = image.flatMap(BarTint.average(of:))
            }
        }
    }

    // MARK: Controlling

    /// Why a control cannot be used right now, in words, or nil. Pressed while
    /// Music is closed it is disabled with this and not sent.
    func unavailableReason(_ control: MusicControl? = nil) -> String? {
        switch status {
        case .notRunning: return "Music isn\u{2019}t open."
        case .denied: return "Allow Spinner to control Music in System Settings."
        case .idle: return control == .playPause ? nil : "Nothing is playing."
        case .track: return nil
        }
    }

    func perform(_ control: MusicControl) {
        guard isRunning(), unavailableReason(control) == nil else { return }
        send(NowPlayingScript.command(control))
    }

    func seek(toFraction fraction: Double) {
        guard isRunning(), case .track(let t) = status, t.duration > 0 else { return }
        send(NowPlayingScript.seek(to: t.duration * min(1, max(0, fraction))))
    }

    private func send(_ source: String) {
        let run = self.run
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { run(source) }.value
            await MainActor.run {
                if outcome == .denied { self?.status = .denied }
                self?.refresh()
            }
        }
    }

    // MARK: The real runner

    nonisolated static func runScript(_ source: String) -> ScriptOutcome {
        guard let script = NSAppleScript(source: source) else { return .failed }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743 is errAEEventNotPermitted: the Automation prompt was refused.
            return (error[NSAppleScript.errorNumber] as? Int) == -1743 ? .denied : .failed
        }
        // Artwork comes back as bytes, everything else as text; bytes are handed on
        // as base64 so one type carries both.
        // 'tdta' is how Music hands back `raw data`: the image's own bytes. Checked
        // before the string coercion, which would read them as text.
        if result.descriptorType == 0x7464_7461 {
            return .ok(result.data.base64EncodedString())
        }
        return .ok(result.stringValue ?? "")
    }
}
