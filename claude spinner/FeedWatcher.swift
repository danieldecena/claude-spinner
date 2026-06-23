//
//  FeedWatcher.swift
//  claude spinner
//
//  Watches ~/.claude/spinnerfeed/ and merges each session's two feed files
//  (<id>.state.json from hooks, <id>.status.json from the statusLine script)
//  into one observable list of sessions.
//

import Foundation
import Observation

enum SessionStatus: String {
    case idle, thinking, tool, attention
}

/// Claude-flavored spinner words. The real per-turn word lives in the closed
/// binary, so we pick our own — seeded by turn_start so it stays put during a
/// turn and changes on the next one, the way the terminal spinner behaves.
enum SpinnerWords {
    /// (present gerund, past tense) so the done line reads naturally, e.g.
    /// "Sautéing" → "Sautéed for 5m 18s".
    static let all: [(ing: String, ed: String)] = [
        ("Calculating", "Calculated"), ("Flummoxing", "Flummoxed"), ("Brewing", "Brewed"),
        ("Pondering", "Pondered"), ("Conjuring", "Conjured"), ("Noodling", "Noodled"),
        ("Percolating", "Percolated"), ("Ruminating", "Ruminated"), ("Marinating", "Marinated"),
        ("Finagling", "Finagled"), ("Wrangling", "Wrangled"), ("Cogitating", "Cogitated"),
        ("Tinkering", "Tinkered"), ("Whirring", "Whirred"), ("Computing", "Computed"),
        ("Scheming", "Schemed"), ("Puzzling", "Puzzled"), ("Mulling", "Mulled"),
        ("Spelunking", "Spelunked"), ("Hatching", "Hatched"), ("Simmering", "Simmered"),
        ("Churning", "Churned"), ("Vibing", "Vibed"), ("Decoding", "Decoded"),
        ("Untangling", "Untangled"), ("Sautéing", "Sautéed"),
    ]

    private static func index(_ seed: Int) -> Int {
        ((seed % all.count) + all.count) % all.count
    }

    /// Present-tense word for an active turn, seeded by turn_start so it stays
    /// stable during the turn and changes on the next one.
    static func word(for session: SessionFeed) -> String {
        let seed = session.turnStart.map { Int($0.timeIntervalSince1970) }
            ?? abs(session.id.hashValue)
        return all[index(seed)].ing
    }

    /// Past-tense word for a finished turn, seeded by the saved last_seed so it
    /// matches the word that was shown while that turn ran.
    static func pastWord(for session: SessionFeed) -> String {
        let seed = session.lastSeed ?? abs(session.id.hashValue)
        return all[index(seed)].ed
    }
}

struct SessionFeed: Identifiable {
    let id: String
    var status: SessionStatus = .idle
    var tool: String = ""
    var message: String = ""
    var cwd: String = ""
    var turnStart: Date?
    var updated: Date?
    var model: String?
    var contextPct: Int?
    /// The just-finished turn, for Claude's grey "Sautéed for 5m 18s" done line.
    var lastSeed: Int?
    var lastDuration: Int?

    init(id: String) { self.id = id }

    /// Merge the hook-written state file (status, current tool, turn start).
    mutating func applyState(_ o: [String: Any]) {
        if let s = o["status"] as? String { status = SessionStatus(rawValue: s) ?? .idle }
        tool = o["tool"] as? String ?? ""
        message = o["message"] as? String ?? ""
        if let c = o["cwd"] as? String, !c.isEmpty { cwd = c }
        if let ts = o["turn_start"] as? Double {
            turnStart = Date(timeIntervalSince1970: ts)
        } else {
            turnStart = nil   // null when idle
        }
        if let up = o["updated"] as? Double { updated = Date(timeIntervalSince1970: up) }
        lastSeed = (o["last_seed"] as? Double).map(Int.init)
        lastDuration = (o["last_duration"] as? Double).map(Int.init)
    }

    /// Merge the statusLine-written file (model, context %, cwd fallback).
    mutating func applyStatus(_ o: [String: Any]) {
        if let m = (o["model"] as? [String: Any])?["display_name"] as? String { model = m }
        if cwd.isEmpty {
            if let c = o["cwd"] as? String {
                cwd = c
            } else if let ws = o["workspace"] as? [String: Any],
                      let c = ws["current_dir"] as? String {
                cwd = c
            }
        }
        if let cw = o["context_window"] as? [String: Any],
           let p = cw["used_percentage"] as? Double {
            contextPct = Int(p.rounded())
        }
    }

    var isWorking: Bool { status == .thinking || status == .tool }

    var projectName: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "session" : name
    }

    /// Home-relative path the way the terminal shows it, e.g. `~/apply`.
    var displayPath: String {
        guard !cwd.isEmpty else { return "session" }
        let home = NSHomeDirectory()
        if cwd == home { return "~" }
        if cwd.hasPrefix(home + "/") { return "~" + cwd.dropFirst(home.count) }
        return cwd
    }
}

@Observable
final class FeedWatcher {
    private(set) var sessions: [SessionFeed] = []

    /// Advances ~10x/sec to animate the menu-bar spinner glyph. Kept as plain
    /// observable state (not a TimelineView in the MenuBarExtra label, which can
    /// collapse the status item to zero size and render it invisible).
    private(set) var glyphPhase = 0

    private let dir: URL
    private var source: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var timer: Timer?
    private var animTimer: Timer?

    init() {
        dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/spinnerfeed", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        rescan()
        startWatching()
        // Safety re-scan: catches any directory event the vnode source misses
        // and prunes sessions that ended without firing SessionEnd.
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.rescan()
        }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.glyphPhase &+= 1
        }
    }

    deinit {
        source?.cancel()
        timer?.invalidate()
        animTimer?.invalidate()
    }

    // Atomic mv from the hook scripts replaces directory entries, so watching
    // the directory vnode for writes is enough to catch every feed update.
    private func startWatching() {
        dirFD = open(dir.path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.rescan() }
        src.setCancelHandler { [dirFD] in if dirFD >= 0 { close(dirFD) } }
        src.resume()
        source = src
    }

    private func rescan() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else {
            sessions = []
            return
        }

        var byId: [String: SessionFeed] = [:]
        for url in files {
            let name = url.lastPathComponent
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if name.hasSuffix(".state.json") {
                let id = String(name.dropLast(".state.json".count))
                var s = byId[id] ?? SessionFeed(id: id)
                s.applyState(obj)
                byId[id] = s
            } else if name.hasSuffix(".status.json") {
                let id = String(name.dropLast(".status.json".count))
                var s = byId[id] ?? SessionFeed(id: id)
                s.applyStatus(obj)
                byId[id] = s
            }
        }

        // Drop sessions that crashed without SessionEnd cleanup (no update in 12h).
        let cutoff = Date().addingTimeInterval(-12 * 3600)
        sessions = byId.values.filter { ($0.updated ?? .distantFuture) > cutoff }
    }

    var workingCount: Int { sessions.filter(\.isWorking).count }
    var attentionCount: Int { sessions.filter { $0.status == .attention }.count }

    /// A single static glyph — animated by pulsing opacity, not by cycling
    /// characters (different asterisk glyphs fall back to a non-Menlo font of
    /// varying width and jitter the whole menu-bar item).
    var menuBarGlyph: String { "✻" }

    /// 0.4–1.0 opacity pulse for the active glyph, driven by the 10 Hz phase.
    var glyphPulse: Double {
        let phase = Double(glyphPhase % 12) / 12.0
        return 0.4 + 0.6 * (0.5 + 0.5 * cos(phase * 2 * .pi))
    }

    /// The text after the glyph: `Calculating… (22s · still thinking)` while
    /// working, the grey `Sautéed for 5m 18s` done line when finished, or empty
    /// when idle with no history. Uses Menlo's monospaced digits, so the only
    /// width changes are digit-count rollovers — never per-animation-frame.
    var menuBarBody: String {
        if attentionCount > 0 {
            let extra = attentionCount > 1 ? " +\(attentionCount - 1)" : ""
            return "Waiting for you…\(extra)"
        }
        let working = sortedSessions.filter(\.isWorking)
        if let lead = working.first {
            let word = SpinnerWords.word(for: lead)
            let extra = working.count > 1 ? " +\(working.count - 1)" : ""
            return "\(word)…\(parenthetical(for: lead))\(extra)"
        }
        if let done = sortedSessions.first(where: { $0.lastDuration != nil }),
           let dur = done.lastDuration {
            return "\(SpinnerWords.pastWord(for: done)) for \(Self.formatDuration(dur))"
        }
        return ""
    }

    /// Orange while working or needing attention, grey for the idle/done line.
    var menuBarActive: Bool { workingCount > 0 || attentionCount > 0 }

    static func formatDuration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 60 ? "\(s / 60)m \(s % 60)s" : "\(s)s"
    }

    /// The live `(22s · hint)` suffix for a working session, reconstructed from
    /// turn_start — the timer the terminal spinner shows, recreated client-side.
    private func parenthetical(for s: SessionFeed) -> String {
        guard let start = s.turnStart else { return "" }
        let elapsed = max(0, Int(Date().timeIntervalSince(start)))
        let timer = elapsed >= 60 ? "\(elapsed / 60)m \(elapsed % 60)s" : "\(elapsed)s"
        let hint: String
        switch s.status {
        case .tool: hint = s.tool.isEmpty ? "running" : "running \(s.tool)"
        case .thinking: hint = elapsed >= 30 ? "still thinking" : "thinking"
        default: hint = ""
        }
        return hint.isEmpty ? " (\(timer))" : " (\(timer) · \(hint))"
    }

    /// Most-urgent first: attention, then working, then idle; newest within each.
    var sortedSessions: [SessionFeed] {
        sessions.sorted { a, b in
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            return (a.updated ?? .distantPast) > (b.updated ?? .distantPast)
        }
    }

    private func rank(_ s: SessionFeed) -> Int {
        switch s.status {
        case .attention: return 0
        case .thinking, .tool: return 1
        case .idle: return 2
        }
    }
}
