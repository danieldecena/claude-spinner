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
import CoreGraphics

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
    /// Fixed width of a row's trailing slot — the host chip at rest, the ✕ clear
    /// button on hover. Shared so the footer can right-align its countdown to the
    /// same column as the row times above it.
    static let rowTrailingSlot: CGFloat = 26
    /// Shared track width for every footer gauge (5h / 7d / chg) so the bars are
    /// identical in size, kept short enough that the model name, all three gauges,
    /// and the reset countdown fit within the compact 320px panel without clipping.
    static let usageTrackWidth: CGFloat = 16
    /// Idle rows stay full strength for this long after their last update…
    static let idleFadeStart: TimeInterval = 60
    /// …then fade to `idleMinOpacity` linearly over this span.
    static let idleFadeSpan: TimeInterval = 30 * 60
    static let idleMinOpacity: Double = 0.45
    /// After a turn finishes, the menu title flashes the past-tense word for this
    /// long, then goes quiet grey.
    static let doneFlashDuration: TimeInterval = 5
    /// At/over this 5h utilization, the menu-bar usage % pulses red as a warning.
    static let usageAlarmPct = 90
    /// How far back the "chg" trend gauge looks; older samples are trimmed.
    static let usageTrendWindow: TimeInterval = 3 * 3600
    /// Collapse samples closer together than this so mashing manual Refresh can't
    /// flood the trend window with near-duplicate points.
    static let usageSampleMinGap: TimeInterval = 2 * 60
    /// A drop at least this large between consecutive samples can only be the 5h
    /// window resetting, not usage organically falling — utilization never drops
    /// this fast on its own. The trend only compares samples since the most
    /// recent such reset, so it never reports a misleading giant negative.
    static let usageResetDropThreshold = 20
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

/// "Needs you" words for the menu-bar attention title — the same seeded-so-stable
/// idea as SpinnerWords: one word per pause, changing on the next one.
enum AttentionWords {
    static let all = ["Waiting", "Awaiting", "Yielding", "Pausing", "Hovering",
                      "Poised", "Lingering", "Holding", "Wondering", "Expecting"]

    /// Seeded by when the session entered attention so it stays put during the pause
    /// and changes the next time a session stops for you.
    static func word(for session: SessionFeed) -> String {
        let seed = session.updated.map { Int($0.timeIntervalSince1970) } ?? abs(session.id.hashValue)
        return all[((seed % all.count) + all.count) % all.count]
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
    var pid: Double?
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
    /// Classified once when `host` is set (not recomputed by the row every 0.1s
    /// TimelineView tick) — the row just reads this stored value.
    var hostTag: HostTag?
    /// PID of the owning `claude` process (captured by emit.sh), so a session whose
    /// process died without a SessionEnd can be pruned. nil when not captured.
    var pid: Int?
    var turnStart: Date?
    var updated: Date?
    var model: String?
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
        if let h = s.host, !h.isEmpty { host = h; hostTag = HostTag.from(h) }
        if let p = s.pid { pid = Int(p) }
        turnStart = s.turn_start.map { Date(timeIntervalSince1970: $0) }  // null when idle
        if let up = s.updated { updated = Date(timeIntervalSince1970: up) }
        lastSeed = s.last_seed.map(Int.init)
        lastDuration = s.last_duration.map(Int.init)
    }

    fileprivate mutating func applyStatus(_ s: StatusFile) {
        if let m = s.model?.display_name { model = m }
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

/// One timestamped 5h-utilization poll result, kept for the "chg" trend gauge.
struct UsageSample: Codable {
    var pct: Int
    var at: Double  // epoch seconds
}

/// One dropdown row — a single session, or a collapsed group of never-worked
/// idle sessions sharing a directory.
struct SessionRowItem: Identifiable {
    let id: String
    let session: SessionFeed
    let ids: [String]
    var count: Int { ids.count }
}

/// Polls Anthropic's API for the account's live 5h/7d rate-limit utilization,
/// using the OAuth token Claude Code stores in the login keychain. Unlike the
/// statusLine feed (which only refreshes during an interactive TUI session), this
/// gives live usage in ANY session — one minimal `max_tokens: 1` request per poll
/// (~1 token), reading the numbers straight from the response's
/// `anthropic-ratelimit-unified-*` headers.
final class UsagePoller {
    struct Result {
        var fiveHourPct: Int
        var sevenDayPct: Int
        var fiveHourResetsAt: Double?
        var sevenDayResetsAt: Double?
        var overageBlocked: Bool
        var fetchedAt: Date
    }

    /// Interval between polls. Modest: usage moves slowly and each poll is a
    /// (tiny) billable request.
    static let pollInterval: TimeInterval = 5 * 60
    /// Skip polling once the user has been idle this long — nobody's consuming, so
    /// the numbers aren't moving; the next input resumes it.
    static let pauseAfterIdle: TimeInterval = 10 * 60

    private let session = URLSession(configuration: .ephemeral)
    private let onUpdate: (Result) -> Void
    private let onAuthExpired: () -> Void
    private var timer: Timer?

    init(onUpdate: @escaping (Result) -> Void, onAuthExpired: @escaping () -> Void) {
        self.onUpdate = onUpdate
        self.onAuthExpired = onAuthExpired
    }

    func start() {
        poll(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) {
            [weak self] _ in self?.poll(force: false)
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refreshNow() { poll(force: true) }

    /// Seconds since the last user input, across the whole session (keyboard/mouse).
    private static var userIdleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: CGEventType(rawValue: ~0)!)
    }

    /// Pure header→Result parse, so the mapping is unit-testable without a network
    /// round-trip. Keys are the lowercased response header names.
    static func parse(headers: [String: String], now: Date) -> Result? {
        // isFinite guards against a malformed "inf"/"nan" header value, which
        // Double.init parses successfully but Int(...).rounded() would then trap on.
        func num(_ key: String) -> Double? {
            headers[key].flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
        }
        guard let u5 = num("anthropic-ratelimit-unified-5h-utilization"),
              let u7 = num("anthropic-ratelimit-unified-7d-utilization") else { return nil }
        return Result(
            fiveHourPct: Int((u5 * 100).rounded()),
            sevenDayPct: Int((u7 * 100).rounded()),
            fiveHourResetsAt: num("anthropic-ratelimit-unified-5h-reset"),
            sevenDayResetsAt: num("anthropic-ratelimit-unified-7d-reset"),
            overageBlocked: headers["anthropic-ratelimit-unified-overage-status"] == "rejected",
            fetchedAt: now)
    }

    /// Read Claude Code's stored OAuth token from the login keychain via the
    /// `security` tool (avoids bundling keychain entitlements). May prompt for
    /// access on first use; returns nil if unavailable, so usage falls back to the
    /// statusLine/cache path.
    private func oauthToken() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    private func poll(force: Bool) {
        // Skip scheduled polls while the machine is idle; a manual refresh (force)
        // or the launch poll always runs.
        if !force && Self.userIdleSeconds > Self.pauseAfterIdle { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self, let token = self.oauthToken() else { return }
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 1,
                "messages": [["role": "user", "content": "."]],
            ])
            let task = self.session.dataTask(with: req) { [weak self] _, response, _ in
                guard let self, let http = response as? HTTPURLResponse else { return }
                if http.statusCode == 401 {
                    DispatchQueue.main.async { self.onAuthExpired() }
                    return
                }
                // Non-2xx (rate-limited, transient server error): ignore this poll,
                // let the next timer tick retry — no rapid hammering.
                guard (200..<300).contains(http.statusCode) else { return }
                var headers: [String: String] = [:]
                for (k, v) in http.allHeaderFields {
                    if let ks = k as? String, let vs = v as? String { headers[ks.lowercased()] = vs }
                }
                guard let result = Self.parse(headers: headers, now: Date()) else { return }
                DispatchQueue.main.async { self.onUpdate(result) }
            }
            task.resume()
        }
    }
}

final class FeedWatcher: ObservableObject {
    @Published private(set) var sessions: [SessionFeed] = [] {
        // Recompute the usage-bearing session once per publish, not on every footer
        // tick — the 1s countdown + glyph ticks read usage ~7x/sec (review #5).
        didSet { usageSession = Self.pickUsageSession(sessions) }
    }
    /// Cached snapshot of `usageSession`, refreshed by `sessions`' didSet.
    private var usageSession: SessionFeed?

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
    /// Recent 5h utilization samples (oldest→newest), each stamped with when it
    /// was polled, backing the footer's "chg" trend gauge. Persisted so the trend
    /// survives relaunch; trimmed to `Constants.usageTrendWindow`.
    @Published private(set) var usageHistory: [UsageSample] = []

    /// Live account usage from the API poller (preferred over the statusLine feed
    /// because it refreshes in any session, not just an interactive TUI one).
    @Published private(set) var pollUsage: UsagePoller.Result?
    /// Set when the poller hits an auth failure (expired token), so the footer can
    /// explain why live usage stopped updating; cleared on the next good poll.
    @Published private(set) var usageError: String?
    private var poller: UsagePoller?
    /// Whether to poll the API for live usage; persisted, on by default.
    @Published var usagePollingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(usagePollingEnabled, forKey: "usagePollingEnabled")
            usagePollingEnabled ? poller?.start() : stopPolling()
        }
    }

    /// All disk reads/parses and file pruning happen here, off the main thread.
    private let ioQueue = DispatchQueue(label: "spinnerfeed.io", qos: .utility)
    private var pendingScan: DispatchWorkItem?

    init() {
        menuBarMode = UserDefaults.standard.string(forKey: "menuBarMode")
            .flatMap(MenuBarMode.init(rawValue:)) ?? .activity
        cachedUsage = UserDefaults.standard.data(forKey: "usageSnapshot")
            .flatMap { try? JSONDecoder().decode(UsageSnapshot.self, from: $0) }
        usageHistory = UserDefaults.standard.data(forKey: "usageHistory")
            .flatMap { try? JSONDecoder().decode([UsageSample].self, from: $0) } ?? []
        // Default on; the key is absent on first launch, so read with a default.
        usagePollingEnabled = (UserDefaults.standard.object(forKey: "usagePollingEnabled") as? Bool) ?? true
        dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/spinnerfeed", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        ioQueue.async { [weak self] in self?.performRescan() }
        startWatching()
        poller = UsagePoller(
            onUpdate: { [weak self] result in self?.applyPollResult(result) },
            onAuthExpired: { [weak self] in
                self?.usageError = "Usage auth expired — run any terminal Claude session to refresh"
            })
        if usagePollingEnabled { poller?.start() }
        // Safety re-scan: catches any directory event the vnode source misses
        // and prunes sessions that ended without firing SessionEnd.
        timer = Timer.scheduledTimer(withTimeInterval: Constants.safetyRescanInterval,
                                     repeats: true) { [weak self] _ in
            self?.scheduleRescan()
        }
        animTimer = Timer.scheduledTimer(withTimeInterval: Constants.animInterval,
                                         repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.menuBarActive || self.usageAlarm {
                self.glyphPhase &+= 1
            }
        }
    }

    deinit {
        source?.cancel()
        timer?.invalidate()
        animTimer?.invalidate()
        poller?.stop()
    }

    private func stopPolling() { poller?.stop() }

    /// Force an immediate usage poll (right-click → Refresh).
    func refreshUsage() { poller?.refreshNow() }

    /// Store a fresh poll result and persist it to the usage cache so it survives
    /// relaunch and Clear All. Runs on main.
    private func applyPollResult(_ result: UsagePoller.Result) {
        pollUsage = result
        usageError = nil
        let snap = UsageSnapshot(fiveHourPct: result.fiveHourPct,
                                 fiveHourResetsAt: result.fiveHourResetsAt,
                                 sevenDayPct: result.sevenDayPct,
                                 model: cachedUsage?.model,
                                 savedAt: result.fetchedAt.timeIntervalSince1970)
        cachedUsage = snap
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: "usageSnapshot")
        }
        recordUsageSample(result.fiveHourPct, at: result.fetchedAt)
    }

    /// Append a timestamped 5h sample for the "chg" trend gauge and persist it.
    /// Collapses samples less than `usageSampleMinGap` apart (mashing manual
    /// Refresh can't flood the trend window with near-duplicate points), and
    /// trims anything older than `usageTrendWindow` so the buffer reflects an
    /// actual recent span rather than an arbitrary poll count.
    private func recordUsageSample(_ pct: Int, at: Date) {
        let now = at.timeIntervalSince1970
        if let last = usageHistory.last, now - last.at < Constants.usageSampleMinGap { return }
        usageHistory.append(UsageSample(pct: pct, at: now))
        usageHistory.removeAll { now - $0.at > Constants.usageTrendWindow }
        if let data = try? JSONEncoder().encode(usageHistory) {
            UserDefaults.standard.set(data, forKey: "usageHistory")
        }
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
        let recent = byId.values.filter { ($0.updated ?? .distantPast) > cutoff }
        // Prune an idle session whose owning claude process has died without firing
        // SessionEnd (e.g. the terminal was force-quit). Restricted to idle sessions
        // with a captured pid, so a live/working session is never dropped on a bad
        // or missing pid — the process check only ever *removes* a truly-dead one.
        let deadPidIds = Set(recent.filter {
            $0.status == .idle && ($0.pid.map { !Self.pidAlive($0) } ?? false)
        }.map(\.id))
        let live = recent.filter { !deadPidIds.contains($0.id) }
        let liveIds = Set(live.map(\.id))
        // Prune files that belong to no live session only once the file itself is
        // older than the cutoff — including a dead-pid session's files. A pid check
        // can be wrong (a synced/remote ~/.claude, or a hook subshell pid rather
        // than the claude parent), so a dead-pid row still disappears from the
        // panel immediately, but its files get the same grace period as every
        // other prune reason: a transient read miss or a mid-startup session is
        // never deleted, and a wrongly-flagged session's data survives long enough
        // to recover on its next real update.
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

    /// True if a process with this pid currently exists. `kill(pid, 0)` sends no
    /// signal — it just probes existence: 0 = alive, EPERM = alive but owned by
    /// another user (still counts), ESRCH = gone.
    private static func pidAlive(_ pid: Int) -> Bool {
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }

    /// True when the feed plumbing is in place: the emitter script exists and
    /// settings.json wires it into the hooks. When false, no session will ever
    /// appear — so the panel shows a setup hint instead of a bare "No active
    /// sessions". Computed once (on refresh) and cached — the empty-panel view can
    /// re-render up to 10x/sec (the menu-bar glyph pulse ticks even with no
    /// sessions, e.g. a usage alarm), and this does real disk I/O.
    private(set) lazy var isSetupInstalled: Bool = Self.checkSetupInstalled(dir: dir)

    private static func checkSetupInstalled(dir: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("emit.sh").path)
        else { return false }
        let settings = dir.deletingLastPathComponent().appendingPathComponent("settings.json")
        guard let text = try? String(contentsOf: settings, encoding: .utf8) else { return false }
        return text.contains("emit.sh")
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
            // Attach the "Focus session" action and the host to activate on tap.
            content.categoryIdentifier = NotificationConfig.attentionCategory
            content.userInfo = ["host": s.host]
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
            // One word keeps the menu-bar title tight; the row carries the detail.
            // Seeded per lead session so it stays put during the pause and alternates.
            guard let lead = sortedSessions.first(where: { $0.status == .attention }) else { return "" }
            let extra = attentionCount > 1 ? " +\(attentionCount - 1)" : ""
            return "\(AttentionWords.word(for: lead))…\(extra)"
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

    /// In usage mode, the 5h window is at/over the red threshold — the menu-bar %
    /// pulses to flag that a rate limit is imminent even while nothing's running.
    var usageAlarm: Bool {
        menuBarMode == .usage && (usageFiveHourPct ?? 0) >= Constants.usageAlarmPct
    }

    static func formatDuration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= Constants.minuteRollover ? "\(s / 60)m \(s % 60)s" : "\(s)s"
    }

    /// Animated "thinking" dots for an actively-working row's time slot — a
    /// looping "." → ".." → "" cycle instead of a numeric elapsed timer, since a
    /// live count of seconds is less useful than a signal that work is ongoing.
    /// Pure/date-driven so every row's dots stay in phase with each other.
    static func workingDots(at date: Date, phaseDuration: TimeInterval = 0.5) -> String {
        let phase = Int((date.timeIntervalSinceReferenceDate / phaseDuration).rounded(.down))
        switch ((phase % 3) + 3) % 3 {
        case 0: return "."
        case 1: return ".."
        default: return ""
        }
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
        // Collapse idle sessions by directory — but keep finished "done" sessions in
        // a SEPARATE bucket from never-worked idles (key prefix), so a fresher
        // never-worked session can't become the representative and hide a finished
        // turn. Each bucket's representative is the freshest of its own kind.
        var groups: [String: [SessionFeed]] = [:]
        var order: [String] = []
        for s in sorted(sessions) {
            guard s.status == .idle else {
                items.append(SessionRowItem(id: s.id, session: s, ids: [s.id]))
                continue
            }
            let key = (s.lastDuration != nil ? "done:" : "idle:") + s.cwd
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(s)
        }
        for key in order {
            let group = groups[key]!
            let rep = group.max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }!
            items.append(SessionRowItem(id: key, session: rep, ids: group.map(\.id)))
        }
        return items
    }

    /// The session whose status feed carries the account-wide rate-limit numbers
    /// (any recent session has them; they're not per-project). Cached in
    /// `usageSession` and refreshed only when `sessions` changes.
    private static func pickUsageSession(_ sessions: [SessionFeed]) -> SessionFeed? {
        sessions
            .filter { $0.fiveHourPct != nil || $0.sevenDayPct != nil }
            .max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }
    }

    // Usage prefers live API-poll data, then a live session's statusLine numbers,
    // then the persisted snapshot — so it stays live in any session (poller) and
    // still survives Clear All / statusLine-less sessions (cache).
    var hasUsage: Bool { pollUsage != nil || usageSession != nil || cachedUsage != nil }
    var usageFiveHourPct: Int? { pollUsage?.fiveHourPct ?? usageSession?.fiveHourPct ?? cachedUsage?.fiveHourPct }
    var usageSevenDayPct: Int? { pollUsage?.sevenDayPct ?? usageSession?.sevenDayPct ?? cachedUsage?.sevenDayPct }
    private var fiveHourResetsAt: Double? {
        pollUsage?.fiveHourResetsAt ?? usageSession?.fiveHourResetsAt ?? cachedUsage?.fiveHourResetsAt
    }
    var usageFiveHourReset: String? { Self.formatReset(fiveHourResetsAt) }
    /// The 5h reset as a relative countdown, e.g. "3h29m".
    var usageFiveHourResetRelative: String? { Self.formatResetRelative(fiveHourResetsAt) }

    /// Signed change in 5h utilization across the retained sample window (up to
    /// `Constants.usageTrendWindow`): how many points it has climbed (+) or fallen
    /// (−). Reset-aware — the 5h window resetting drops utilization sharply, which
    /// is not a real "usage fell" event, so the trend only compares samples since
    /// the most recent such drop. nil until there are ≥2 samples since that point.
    var usageFiveHourTrend: Int? { Self.trend(from: usageHistory) }

    /// Pure trend derivation, extracted so reset-detection is unit-testable
    /// without a live poller. Finds the most recent reset-sized drop and only
    /// diffs samples from there onward; falls back to the whole window if no
    /// reset occurred within it.
    static func trend(from samples: [UsageSample]) -> Int? {
        guard let lastResetIndex = samples.indices.dropFirst().last(where: {
            samples[$0].pct < samples[$0 - 1].pct - Constants.usageResetDropThreshold
        }) else {
            guard samples.count >= 2 else { return nil }
            return samples.last!.pct - samples.first!.pct
        }
        guard lastResetIndex < samples.count - 1 else { return nil }
        return samples.last!.pct - samples[lastResetIndex].pct
    }

    /// The 7d window's reset instant (only the poller carries it).
    private var sevenDayResetsAt: Double? { pollUsage?.sevenDayResetsAt }
    var usageSevenDayReset: String? { Self.formatResetDay(sevenDayResetsAt) }

    /// Tooltip for the footer countdown — both windows' reset clock times when
    /// known, e.g. "5h resets at 2:00 AM · 7d resets at Mon".
    var usageResetTooltip: String {
        var parts: [String] = []
        if let f = usageFiveHourReset { parts.append("5h resets at \(f)") }
        if let s = usageSevenDayReset { parts.append("7d resets at \(s)") }
        return parts.joined(separator: " · ")
    }

    /// When the shown usage was last refreshed. The poll's fetch time is the true
    /// freshness; the statusLine path falls back to the session/cache timestamp.
    var usageUpdatedAt: Date? {
        pollUsage?.fetchedAt ?? usageSession?.updated ?? cachedUsage.map { Date(timeIntervalSince1970: $0.savedAt) }
    }
    /// True when usage hasn't refreshed recently (polling off/failing, or no live
    /// statusLine) — the footer dims to signal the numbers may be behind.
    var usageIsStale: Bool {
        guard let t = usageUpdatedAt else { return false }
        return Date().timeIntervalSince(t) > Constants.usageStaleAfter
    }
    /// Tooltip line, e.g. "Usage as of 10:14 PM (1h24m ago)".
    var usageAsOfString: String {
        guard let t = usageUpdatedAt else { return "No usage data yet" }
        return "Usage as of \(Self.resetTimeFormatter.string(from: t)) (\(Self.compactAge(since: t)) ago)"
    }

    /// Genuinely blocked: a window is maxed out AND the account can't buy overage.
    /// The `overage-status: rejected` header alone is NOT a problem — it's the
    /// normal setting for plans that don't allow overage (e.g. Max), so treating
    /// it as "blocked" fires a false alarm at every utilization level.
    var usageOverageBlocked: Bool {
        guard pollUsage?.overageBlocked == true else { return false }
        return (usageFiveHourPct ?? 0) >= 100 || (usageSevenDayPct ?? 0) >= 100
    }

    /// A short, urgent footer note when polling can't refresh (auth expired) or the
    /// account is blocked on overage — nil when usage is flowing normally. The full
    /// sentence lives in `usageNoticeDetail` for the tooltip.
    var usageNotice: String? {
        if usageOverageBlocked { return "blocked" }
        if usageError != nil { return "expired" }
        return nil
    }
    var usageNoticeDetail: String {
        if usageOverageBlocked { return "Account is out of credits — usage is blocked (overage rejected)." }
        return usageError ?? ""
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

    /// Weekday + time for a multi-day window, e.g. "Mon 2:00 AM" — a bare clock
    /// time would misread for a reset up to 7 days out.
    private static let resetDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE j:mm")
        return f
    }()

    private static func formatResetDay(_ resetsAt: Double?) -> String? {
        guard let resetsAt else { return nil }
        return resetDayFormatter.string(from: Date(timeIntervalSince1970: resetsAt))
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
