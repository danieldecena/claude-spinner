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
import ServiceManagement

/// Tunables gathered in one place so behavior isn't scattered across literals.
enum Constants {
    /// Sessions with no update in this long are pruned (in memory and on disk).
    static let staleCutoff: TimeInterval = 12 * 3600
    /// Safety re-scan cadence; backstops any vnode event the source misses.
    static let safetyRescanInterval: TimeInterval = 2.0
    /// Menu-bar glyph animation cadence (~10 fps).
    static let animInterval: TimeInterval = 0.1
    /// A burst of hook writes within this window coalesces into one rescan.
    static let debounceInterval: TimeInterval = 0.1
    /// Timer switches from `Ns` to `Nm Ns` at this many seconds.
    static let minuteRollover = 60
    /// Spinner frame rate used to index the glyph by wall-clock time.
    static let spinnerFPS = 10.0
    /// Dropdown panel width.
    static let panelWidth: CGFloat = 320
    /// Segments in the footer usage bar.
    static let usageBarSegments = 8
    /// Idle rows stay full strength for this long after their last update…
    static let idleFadeStart: TimeInterval = 60
    /// …then fade to `idleMinOpacity` linearly over this span.
    static let idleFadeSpan: TimeInterval = 30 * 60
    static let idleMinOpacity: Double = 0.45
}

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

// MARK: - Feed file schemas

/// `<id>.state.json`, written by emit.sh from lifecycle hooks.
private struct StateFile: Decodable {
    var status: String?
    var tool: String?
    var message: String?
    var cwd: String?
    var turn_start: Double?
    var updated: Double?
    var last_seed: Double?
    var last_duration: Double?
}

/// `<id>.status.json`, the raw statusLine stdin JSON. Only the fields the app
/// renders are declared; unknown keys are ignored. `JSONDecoder` reads JSON
/// integers and floats alike as `Double`, so `used_percentage` needs no special
/// casing the way `JSONSerialization`'s `NSNumber` did.
private struct StatusFile: Decodable {
    struct Model: Decodable { var display_name: String? }
    struct ContextWindow: Decodable { var used_percentage: Double? }
    struct Cost: Decodable { var total_cost_usd: Double? }
    struct Workspace: Decodable { var current_dir: String? }
    struct RateLimits: Decodable {
        struct FiveHour: Decodable {
            var used_percentage: Double?
            var resets_at: Double?
        }
        var five_hour: FiveHour?
    }
    var model: Model?
    var context_window: ContextWindow?
    var cost: Cost?
    var cwd: String?
    var workspace: Workspace?
    var rate_limits: RateLimits?
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
    var costUsd: Double?
    var fiveHourPct: Int?
    var fiveHourResetsAt: Double?
    /// The just-finished turn, for Claude's grey "Sautéed for 5m 18s" done line.
    var lastSeed: Int?
    var lastDuration: Int?


    init(id: String) { self.id = id }

    /// Merge the hook-written state file (status, current tool, turn start).
    fileprivate mutating func applyState(_ s: StateFile) {
        if let st = s.status { status = SessionStatus(rawValue: st) ?? .idle }
        tool = s.tool ?? ""
        message = s.message ?? ""
        if let c = s.cwd, !c.isEmpty { cwd = c }
        turnStart = s.turn_start.map { Date(timeIntervalSince1970: $0) }  // null when idle
        if let up = s.updated { updated = Date(timeIntervalSince1970: up) }
        lastSeed = s.last_seed.map(Int.init)
        lastDuration = s.last_duration.map(Int.init)
    }

    fileprivate mutating func applyStatus(_ s: StatusFile) {
        if let m = s.model?.display_name { model = m }
        if let p = s.context_window?.used_percentage { contextPct = Int(p.rounded()) }
        if let usd = s.cost?.total_cost_usd { costUsd = usd }
        if cwd.isEmpty {
            if let c = s.cwd { cwd = c }
            else if let c = s.workspace?.current_dir { cwd = c }
        }
        if let five = s.rate_limits?.five_hour {
            if let p = five.used_percentage { fiveHourPct = Int(p.rounded()) }
            if let r = five.resets_at { fiveHourResetsAt = r }
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

    var rateLimitText: String? {
        guard let pct = fiveHourPct, let resetsAt = fiveHourResetsAt else { return nil }
        let now = Date().timeIntervalSince1970
        let remaining = max(0, resetsAt - now)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        let resetStr: String
        if hours > 0 {
            resetStr = "\(hours)h\(minutes)m"
        } else {
            resetStr = "\(minutes)m"
        }

        let segments = Constants.usageBarSegments
        let fullBlocks = Int(round(Double(pct) / 100.0 * Double(segments)))
        let filled = String(repeating: "█", count: fullBlocks)
        let empty = String(repeating: "░", count: segments - fullBlocks)
        let bar = filled + empty

        return "\(bar) 5h \(pct)% ↺\(resetStr)"
    }
}

final class FeedWatcher: ObservableObject {
    @Published private(set) var sessions: [SessionFeed] = []

    /// Advances ~10x/sec to animate the menu-bar spinner glyph. Kept as plain
    /// observable state (not a TimelineView in the MenuBarExtra label, which can
    /// collapse the status item to zero size and render it invisible).
    @Published private(set) var glyphPhase = 0

    private let dir: URL
    private var source: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var timer: Timer?
    private var animTimer: Timer?

    /// All disk reads/parses and file pruning happen here, off the main thread.
    private let ioQueue = DispatchQueue(label: "spinnerfeed.io", qos: .utility)
    private var pendingScan: DispatchWorkItem?

    init() {
        dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/spinnerfeed", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        ioQueue.async { [weak self] in self?.performRescan() }
        startWatching()
        // Safety re-scan: catches any directory event the vnode source misses
        // and prunes sessions that ended without firing SessionEnd.
        timer = Timer.scheduledTimer(withTimeInterval: Constants.safetyRescanInterval,
                                     repeats: true) { [weak self] _ in
            self?.scheduleRescan()
        }
        animTimer = Timer.scheduledTimer(withTimeInterval: Constants.animInterval,
                                         repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.menuBarActive {
                self.glyphPhase &+= 1
            }
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
            queue: ioQueue
        )
        src.setEventHandler { [weak self] in self?.scheduleRescan() }
        src.setCancelHandler { [dirFD] in if dirFD >= 0 { close(dirFD) } }
        src.resume()
        source = src
    }

    /// Coalesce a burst of directory events into a single background rescan.
    private func scheduleRescan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performRescan() }
        pendingScan = work
        ioQueue.asyncAfter(deadline: .now() + Constants.debounceInterval, execute: work)
    }

    /// Strip a known feed suffix to recover the session id.
    private func sessionId(from name: String) -> String? {
        for suffix in [".state.json", ".status.json", ".status.txt"] {
            if name.hasSuffix(suffix) { return String(name.dropLast(suffix.count)) }
        }
        return nil
    }

    /// Runs on `ioQueue`: read + parse the directory, prune stale/orphan files
    /// from disk, then publish the live session list back on the main thread.
    private func performRescan() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else {
            DispatchQueue.main.async { [weak self] in self?.sessions = [] }
            return
        }

        var byId: [String: SessionFeed] = [:]
        for url in files {
            let name = url.lastPathComponent
            if name.hasSuffix(".state.json") {
                guard let data = try? Data(contentsOf: url),
                      let sf = try? JSONDecoder().decode(StateFile.self, from: data) else { continue }
                let id = String(name.dropLast(".state.json".count))
                var s = byId[id] ?? SessionFeed(id: id)
                s.applyState(sf)
                byId[id] = s
            } else if name.hasSuffix(".status.json") {
                guard let data = try? Data(contentsOf: url),
                      let sf = try? JSONDecoder().decode(StatusFile.self, from: data) else { continue }
                let id = String(name.dropLast(".status.json".count))
                var s = byId[id] ?? SessionFeed(id: id)
                s.applyStatus(sf)
                byId[id] = s
            }
        }

        // Live = a real session (state file present, so `updated` is set) touched
        // within the cutoff. A status-only entry with no state file has no
        // `updated` and is treated as dead — nil defaults to .distantPast so it
        // never renders as a phantom idle row.
        let cutoff = Date().addingTimeInterval(-Constants.staleCutoff)
        let live = byId.values.filter { ($0.updated ?? .distantPast) > cutoff }
        let liveIds = Set(live.map(\.id))
        // Prune files that belong to no live session, but only once the file
        // itself is older than the cutoff — so a transient read miss or a session
        // mid-startup (status.json written before state.json) is never deleted.
        for url in files {
            guard let id = sessionId(from: url.lastPathComponent), !liveIds.contains(id) else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if (mtime ?? .distantPast) < cutoff {
                try? fm.removeItem(at: url)
            }
        }

        let result = Array(live)
        DispatchQueue.main.async { [weak self] in self?.sessions = result }
    }

    var workingCount: Int { sessions.filter(\.isWorking).count }
    var attentionCount: Int { sessions.filter { $0.status == .attention }.count }

    /// Animated by cycling characters to match the footer spinner.
    var menuBarGlyph: String {
        if menuBarActive {
            return Spinner.frame(at: Date())
        }
        return "✻"
    }

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
        return s >= Constants.minuteRollover ? "\(s / 60)m \(s % 60)s" : "\(s)s"
    }

    /// The live `(22s)` timer suffix for a working session, reconstructed from
    /// turn_start. Kept deliberately terse — just the elapsed time — so the menu
    /// bar stays compact and doesn't shove other items around; the tool/thinking
    /// hint lives in the dropdown row instead.
    private func parenthetical(for s: SessionFeed) -> String {
        guard let start = s.turnStart else { return "" }
        let elapsed = max(0, Int(Date().timeIntervalSince(start)))
        return " (\(Self.formatDuration(elapsed)))"
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

    var globalRateLimitText: String? {
        guard let mostRecent = sessions.filter({ $0.fiveHourPct != nil }).max(by: {
            ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast)
        }) else { return nil }
        return mostRecent.rateLimitText
    }

    var globalModel: String? {
        guard let mostRecent = sessions.filter({ $0.model != nil }).max(by: {
            ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast)
        }) else { return nil }
        return mostRecent.model
    }

    /// Model name trimmed to its family for the compact footer, e.g.
    /// "Opus 4.8 (1M context)" -> "Opus 4.8".
    var globalModelShort: String? {
        globalModel.map { String($0.prefix { $0 != "(" }).trimmingCharacters(in: .whitespaces) }
    }

    /// Total spend across the visible sessions — the footer's live cost figure.
    var globalCost: Double? {
        let costs = sessions.compactMap(\.costUsd)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    // MARK: - Actions

    func clearSession(id: String) {
        let fm = FileManager.default
        try? fm.removeItem(at: dir.appendingPathComponent("\(id).state.json"))
        try? fm.removeItem(at: dir.appendingPathComponent("\(id).status.json"))
        try? fm.removeItem(at: dir.appendingPathComponent("\(id).status.txt"))
        scheduleRescan()
    }

    func clearAll() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files {
            try? fm.removeItem(at: url)
        }
        scheduleRescan()
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to toggle launch at login: \(error)")
            }
        }
    }
}
