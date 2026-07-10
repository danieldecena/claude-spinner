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
import UserNotifications

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
    static let panelWidth: CGFloat = 360
    /// Idle rows stay full strength for this long after their last update…
    static let idleFadeStart: TimeInterval = 60
    /// …then fade to `idleMinOpacity` linearly over this span.
    static let idleFadeSpan: TimeInterval = 30 * 60
    static let idleMinOpacity: Double = 0.45
    /// After a turn finishes, the menu title flashes the past-tense word for this
    /// long, then goes quiet grey.
    static let doneFlashDuration: TimeInterval = 5
    /// Usage older than this is flagged stale in the footer — no statusLine session
    /// has refreshed it recently (the only source of the 5h/7d percentages).
    static let usageStaleAfter: TimeInterval = 15 * 60
}

/// What the menu-bar title displays: live activity, or the 5h usage limit.
enum MenuBarMode: String {
    case activity, usage
}

/// What the menu-bar label is conveying right now, so the label can color and
/// animate accordingly.
enum MenuBarState {
    case working    // a session is thinking/using a tool — bright, animated
    case attention  // a session needs the user — bright
    case doneFlash  // a turn just finished — grey past-word flash
    case idle       // nothing active — quiet grey icon
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
    var host: String?
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
    struct Workspace: Decodable { var current_dir: String? }
    struct RateLimits: Decodable {
        struct Window: Decodable {
            var used_percentage: Double?
            var resets_at: Double?
        }
        var five_hour: Window?
        var seven_day: Window?
    }
    var model: Model?
    var context_window: ContextWindow?
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
    var host: String = ""
    var turnStart: Date?
    var updated: Date?
    var model: String?
    var contextPct: Int?
    var fiveHourPct: Int?
    var fiveHourResetsAt: Double?
    var sevenDayPct: Int?
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
        if let h = s.host, !h.isEmpty { host = h }
        turnStart = s.turn_start.map { Date(timeIntervalSince1970: $0) }  // null when idle
        if let up = s.updated { updated = Date(timeIntervalSince1970: up) }
        lastSeed = s.last_seed.map(Int.init)
        lastDuration = s.last_duration.map(Int.init)
    }

    fileprivate mutating func applyStatus(_ s: StatusFile) {
        if let m = s.model?.display_name { model = m }
        if let p = s.context_window?.used_percentage { contextPct = Int(p.rounded()) }
        if cwd.isEmpty {
            if let c = s.cwd { cwd = c }
            else if let c = s.workspace?.current_dir { cwd = c }
        }
        if let five = s.rate_limits?.five_hour {
            if let p = five.used_percentage { fiveHourPct = Int(p.rounded()) }
            if let r = five.resets_at { fiveHourResetsAt = r }
        }
        if let p = s.rate_limits?.seven_day?.used_percentage { sevenDayPct = Int(p.rounded()) }
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

    /// Compact "resets in" string for the 5h window, e.g. "2h14m" or "43m".
    var fiveHourResetString: String? {
        guard let resetsAt = fiveHourResetsAt else { return nil }
        let remaining = max(0, resetsAt - Date().timeIntervalSince1970)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        return hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)m"
    }
}

/// Last-known account usage, persisted so the footer/title keep showing it after
/// sessions are cleared or when the current session has no statusLine feed.
struct UsageSnapshot: Codable {
    var fiveHourPct: Int?
    var fiveHourResetsAt: Double?
    var sevenDayPct: Int?
    var model: String?
    var savedAt: Double
}

/// One dropdown row — a single session, or a collapsed group of never-worked
/// idle sessions sharing a directory.
struct SessionRowItem: Identifiable {
    let id: String
    let session: SessionFeed
    let ids: [String]
    var count: Int { ids.count }
}

final class FeedWatcher: ObservableObject {
    @Published private(set) var sessions: [SessionFeed] = []

    /// Advances ~10x/sec to animate the menu-bar spinner glyph. Kept as plain
    /// observable state (not a TimelineView in the MenuBarExtra label, which can
    /// collapse the status item to zero size and render it invisible).
    @Published private(set) var glyphPhase = 0

    /// What the menu-bar title shows; persisted across launches.
    @Published var menuBarMode: MenuBarMode {
        didSet { UserDefaults.standard.set(menuBarMode.rawValue, forKey: "menuBarMode") }
    }

    private let dir: URL
    private var source: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var timer: Timer?
    private var animTimer: Timer?
    /// Session ids already alerted for attention, so each pause notifies once.
    private var notifiedAttention: Set<String> = []
    /// Last-known usage, so it survives Clear All / statusLine-less sessions.
    private var cachedUsage: UsageSnapshot?

    /// All disk reads/parses and file pruning happen here, off the main thread.
    private let ioQueue = DispatchQueue(label: "spinnerfeed.io", qos: .utility)
    private var pendingScan: DispatchWorkItem?

    init() {
        menuBarMode = UserDefaults.standard.string(forKey: "menuBarMode")
            .flatMap(MenuBarMode.init(rawValue:)) ?? .activity
        cachedUsage = UserDefaults.standard.data(forKey: "usageSnapshot")
            .flatMap { try? JSONDecoder().decode(UsageSnapshot.self, from: $0) }
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
    /// Callers come from both the fs-event handler (ioQueue) and the timer/Refresh
    /// (main), so do the debounce bookkeeping on ioQueue to keep `pendingScan`
    /// single-threaded.
    private func scheduleRescan() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.pendingScan?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.performRescan() }
            self.pendingScan = work
            self.ioQueue.asyncAfter(deadline: .now() + Constants.debounceInterval, execute: work)
        }
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
        DispatchQueue.main.async { [weak self] in
            self?.notifyAttention(result)
            self?.updateUsageCache(result)
            self?.sessions = result
        }
    }

    /// Force a re-read of the feed (right-click → Refresh).
    func refresh() { scheduleRescan() }

    /// Snapshot the freshest account usage so it persists past Clear All and
    /// sessions that never render a statusLine. Runs on main.
    private func updateUsageCache(_ newSessions: [SessionFeed]) {
        guard let s = newSessions
            .filter({ $0.fiveHourPct != nil || $0.sevenDayPct != nil })
            .max(by: { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) })
        else { return }
        let snap = UsageSnapshot(fiveHourPct: s.fiveHourPct, fiveHourResetsAt: s.fiveHourResetsAt,
                                 sevenDayPct: s.sevenDayPct, model: s.model,
                                 savedAt: Date().timeIntervalSince1970)
        cachedUsage = snap
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: "usageSnapshot")
        }
    }

    /// Post a macOS notification the first time each session enters attention, so
    /// the user is pulled back without watching the menu bar. Runs on main.
    private func notifyAttention(_ newSessions: [SessionFeed]) {
        let attentionNow = Set(newSessions.filter { $0.status == .attention }.map(\.id))
        for id in attentionNow.subtracting(notifiedAttention) {
            guard let s = newSessions.first(where: { $0.id == id }) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Claude needs you"
            content.body = s.message.isEmpty ? s.projectName : "\(s.projectName) — \(s.message)"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "attention-\(id)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
        notifiedAttention = attentionNow
    }

    var workingCount: Int { sessions.filter(\.isWorking).count }
    var attentionCount: Int { sessions.filter { $0.status == .attention }.count }

    /// The animated spinner while a session is working or waiting on you (the blue
    /// vs orange label color carries which); the resting star when done/idle.
    var menuBarGlyph: String {
        menuBarActive ? Spinner.frame(at: Date()) : Spinner.idle
    }

    /// 0.65–1.0 opacity pulse for the active glyph, driven by the 10 Hz phase.
    /// Floor kept high so the glyph stays clearly visible at the trough.
    var glyphPulse: Double {
        let phase = Double(glyphPhase % 12) / 12.0
        return 0.65 + 0.35 * (0.5 + 0.5 * cos(phase * 2 * .pi))
    }

    /// A session that finished its turn within the done-flash window: idle, has a
    /// last-turn duration, and was updated moments ago. Falls out of the data —
    /// no extra state to track.
    private var justFinished: SessionFeed? {
        let cutoff = Date().addingTimeInterval(-Constants.doneFlashDuration)
        return sessions
            .filter { $0.status == .idle && $0.lastDuration != nil && ($0.updated ?? .distantPast) > cutoff }
            .max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }
    }

    /// The current menu-bar presentation state (drives label text, color, motion).
    var menuBarState: MenuBarState { Self.menuBarState(for: sessions, now: Date()) }

    /// Pure derivation of the menu-bar state — extracted so its transitions are
    /// unit-testable without I/O. Attention wins, then working, then a just-finished
    /// turn's done-flash, else idle.
    static func menuBarState(for sessions: [SessionFeed], now: Date) -> MenuBarState {
        if sessions.contains(where: { $0.status == .attention }) { return .attention }
        if sessions.contains(where: { $0.isWorking }) { return .working }
        let cutoff = now.addingTimeInterval(-Constants.doneFlashDuration)
        if sessions.contains(where: {
            $0.status == .idle && $0.lastDuration != nil && ($0.updated ?? .distantPast) > cutoff
        }) { return .doneFlash }
        return .idle
    }

    /// The text after the glyph. Word-only (no live timer — that changed the label
    /// width every tick and jittered the status item; elapsed time lives in the
    /// dropdown row). Empty when idle so only the glyph shows.
    var menuBarBody: String {
        switch menuBarState {
        case .attention:
            let extra = attentionCount > 1 ? " +\(attentionCount - 1)" : ""
            return "Waiting for you…\(extra)"
        case .working:
            guard let lead = sortedSessions.first(where: \.isWorking) else { return "" }
            let extra = workingCount > 1 ? " +\(workingCount - 1)" : ""
            return "\(SpinnerWords.word(for: lead))…\(extra)"
        case .doneFlash:
            return justFinished.map(SpinnerWords.pastWord(for:)) ?? ""
        case .idle:
            return ""
        }
    }

    /// Bright + pulsing for working/attention; grey/static for done/idle.
    var menuBarActive: Bool {
        menuBarState == .working || menuBarState == .attention
    }

    static func formatDuration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= Constants.minuteRollover ? "\(s / 60)m \(s % 60)s" : "\(s)s"
    }

    /// Most-urgent first: attention, then working, then idle; newest within each.
    var sortedSessions: [SessionFeed] { Self.sorted(sessions) }

    /// Pure sort used by the row list — extracted so it's unit-testable without I/O.
    static func sorted(_ sessions: [SessionFeed]) -> [SessionFeed] {
        sessions.sorted { a, b in
            if rank(a.status) != rank(b.status) { return rank(a.status) < rank(b.status) }
            return (a.updated ?? .distantPast) > (b.updated ?? .distantPast)
        }
    }

    static func rank(_ status: SessionStatus) -> Int {
        switch status {
        case .attention: return 0
        case .thinking, .tool: return 1
        case .idle: return 2
        }
    }

    /// Rows to render: attention/working sessions individually; idle sessions
    /// (both just-finished "done" and never-worked) collapsed by directory into one
    /// row with a count, so a stack of finished `claude-spinner done` sessions reads
    /// as a single `claude-spinner done · 2m 56s ×3` on the freshest of the group.
    var displayItems: [SessionRowItem] { Self.displayItems(from: sessions) }

    /// Pure row-grouping used by the panel — extracted so grouping is unit-testable
    /// without I/O. Attention/working sessions stay individual; idle ones (done and
    /// never-worked) collapse by directory onto the freshest, with a count.
    static func displayItems(from sessions: [SessionFeed]) -> [SessionRowItem] {
        var items: [SessionRowItem] = []
        var idleByDir: [String: [SessionFeed]] = [:]
        var dirOrder: [String] = []
        for s in sorted(sessions) {
            if s.status == .idle {
                if idleByDir[s.cwd] == nil { dirOrder.append(s.cwd) }
                idleByDir[s.cwd, default: []].append(s)
            } else {
                items.append(SessionRowItem(id: s.id, session: s, ids: [s.id]))
            }
        }
        for dir in dirOrder {
            let group = idleByDir[dir]!
            let rep = group.max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }!
            items.append(SessionRowItem(id: "idle:\(dir)", session: rep, ids: group.map(\.id)))
        }
        return items
    }

    /// The session whose status feed carries the account-wide rate-limit
    /// numbers (any recent session has them; they're not per-project).
    private var usageSession: SessionFeed? {
        sessions
            .filter { $0.fiveHourPct != nil || $0.sevenDayPct != nil }
            .max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }
    }

    // Usage prefers a live session's numbers, else the persisted snapshot — so it
    // keeps showing after Clear All or in a session with no statusLine feed.
    var hasUsage: Bool { usageSession != nil || cachedUsage != nil }
    var usageFiveHourPct: Int? { usageSession?.fiveHourPct ?? cachedUsage?.fiveHourPct }
    var usageSevenDayPct: Int? { usageSession?.sevenDayPct ?? cachedUsage?.sevenDayPct }
    var usageFiveHourReset: String? {
        Self.formatReset(usageSession?.fiveHourResetsAt ?? cachedUsage?.fiveHourResetsAt)
    }
    /// The 5h reset as a relative countdown, e.g. "3h29m" — the footer pairs this
    /// with the clock time so the second line reads "resets 2:00 AM · in 3h29m".
    var usageFiveHourResetRelative: String? {
        Self.formatResetRelative(usageSession?.fiveHourResetsAt ?? cachedUsage?.fiveHourResetsAt)
    }

    /// When the shown usage was last refreshed — the freshest live source's update
    /// time, else the persisted snapshot's save time.
    var usageUpdatedAt: Date? {
        usageSession?.updated ?? cachedUsage.map { Date(timeIntervalSince1970: $0.savedAt) }
    }
    /// True when the shown usage is old enough to flag: account usage only refreshes
    /// via a statusLine render, so a long gap means the numbers may be behind.
    var usageIsStale: Bool {
        guard let t = usageUpdatedAt else { return false }
        return Date().timeIntervalSince(t) > Constants.usageStaleAfter
    }
    /// Tooltip line, e.g. "Usage as of 10:14 PM (1h24m ago)".
    var usageAsOfString: String {
        guard let t = usageUpdatedAt else { return "No usage data yet" }
        return "Usage as of \(Self.resetTimeFormatter.string(from: t)) (\(Self.compactAge(since: t)) ago)"
    }

    /// "45s" / "12m" / "1h20m" elapsed since `date`.
    static func compactAge(since date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        let h = s / 3600, m = (s % 3600) / 60
        return m > 0 ? "\(h)h\(m)m" : "\(h)h"
    }

    /// The wall-clock time the 5h window resets, e.g. "2:00 AM" (respects the
    /// user's 12/24h locale). The `resets_at` is a fixed instant, so this is exact.
    private static let resetTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static func formatReset(_ resetsAt: Double?) -> String? {
        guard let resetsAt else { return nil }
        return resetTimeFormatter.string(from: Date(timeIntervalSince1970: resetsAt))
    }

    /// "3h29m" / "43m" left until the given instant. Recomputed each render (the
    /// footer's 1s TimelineView keeps it ticking down).
    private static func formatResetRelative(_ resetsAt: Double?) -> String? {
        guard let resetsAt else { return nil }
        let remaining = max(0, resetsAt - Date().timeIntervalSince1970)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        return hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)m"
    }

    var globalModel: String? {
        let live = sessions.filter { $0.model != nil }
            .max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }?.model
        return live ?? cachedUsage?.model
    }

    /// Model name trimmed to its family for the compact footer, e.g.
    /// "Opus 4.8 (1M context)" -> "Opus 4.8".
    var globalModelShort: String? {
        globalModel.map { String($0.prefix { $0 != "(" }).trimmingCharacters(in: .whitespaces) }
    }

    /// Just the family word (e.g. "Opus"), for the space-tight two-bar footer.
    var globalModelFamily: String? {
        globalModelShort?.split(separator: " ").first.map(String.init)
    }

    // MARK: - Actions

    /// Clear every session backing a row (one session, or a collapsed group).
    func clear(_ item: SessionRowItem) {
        let fm = FileManager.default
        for id in item.ids {
            try? fm.removeItem(at: dir.appendingPathComponent("\(id).state.json"))
            try? fm.removeItem(at: dir.appendingPathComponent("\(id).status.json"))
            try? fm.removeItem(at: dir.appendingPathComponent("\(id).status.txt"))
        }
        scheduleRescan()
    }

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
        // Only session feed files — never emit.sh or anything else living here.
        for url in files where sessionId(from: url.lastPathComponent) != nil {
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
