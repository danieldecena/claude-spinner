//
//  FeedWatcher.swift
//  claude spinner
//
//  Watches ~/.claude/spinnerfeed/ and merges each session's two feed files
//  (<id>.state.json from hooks, <id>.status.json from the statusLine script)
//  into one observable list of sessions.
//

import Foundation
import Combine
import Observation
import ServiceManagement
import UserNotifications
import AppKit
import CoreGraphics
import Darwin

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
    /// Dropdown panel's preferred/max width. Only `rowFixedColumns` of a row is
    /// actually fixed; name and model divide the rest of line 1, and status divides
    /// line 2 against its own budget (see `RowLayout`), so this is a free knob —
    /// widening it goes straight to the session name, which is the one column
    /// holding unbounded prose. Clamped down to the status item's screen
    /// `visibleFrame` at show time by `fittedPanelWidth`.
    static let panelWidth: CGFloat = 470
    /// Default open height for the standalone window, and the ceiling a stale
    /// remembered frame gets clamped back to — same "shrink to fit" treatment
    /// `showMainWindow` gives an oversized remembered width.
    static let panelDefaultHeight: CGFloat = 320
    /// The window is its own surface now, not the panel with more room, so it
    /// gets sizes that suit a sidebar and a detail pane rather than a dropdown.
    static let windowDefaultWidth: CGFloat = 900
    static let windowDefaultHeight: CGFloat = 560
    static let windowMinWidth: CGFloat = 620
    static let windowMinHeight: CGFloat = 360
    /// Floor the clamp never drops below. Line 1's row budget goes negative under
    /// ~206 (`rowFixedColumns` 136 + `RowLayout.minNameWidth` 70) and the footer's
    /// fixed-size gauges want ~340; 360 keeps `columns()` arithmetic positive
    /// without a defensive clamp, and no real display's `visibleFrame` is this
    /// narrow, so the floor is never actually reached.
    static let panelMinWidth: CGFloat = 360
    /// Clearance kept between the panel's edge and the screen edge when clamping.
    static let panelScreenMargin: CGFloat = 16
    /// Horizontal inset applied once per nesting depth (visual depth is 1).
    /// Also charged on every row's line-2 status budget so a child status
    /// cannot overflow; roots donate 16pt of unused status width.
    static let childRowIndent: CGFloat = 16
    /// Ceiling for the popover's session list. A 2-line row is ~40pt; this
    /// is about six rows, after which the list scrolls instead of growing
    /// the popover off the screen. The standalone window uses
    /// `maxHeight: .infinity` instead (the window itself is the viewport).
    static let panelListMaxHeight: CGFloat = 240

    /// The panel width to use given the status item's screen width, clamped so the
    /// panel never overruns the screen edge (the far-right-of-menu-bar clip) nor
    /// shrinks below the layout floor. Pure so the clamp is testable without a view;
    /// `nil` (screen unknown at first show) degrades to the unclamped preferred width.
    static func fittedPanelWidth(visibleWidth: CGFloat?) -> CGFloat {
        guard let visibleWidth else { return panelWidth }
        return min(panelWidth, max(panelMinWidth, visibleWidth - panelScreenMargin))
    }

    /// Tolerance on the top-edge match below. Small because the two edges are
    /// meant to be equal — this absorbs rounding on a scaled display, nothing more.
    static let statusItemPlacementSlack: CGFloat = 2

    /// True when AppKit never gave the status item a slot in the menu bar. macOS
    /// reports no error for this: a full menu bar silently drops the item and parks
    /// it somewhere off the bar, so the frame is the only observable signal
    /// (observed 2026-08-12: 1090pt below the bar, at x=-1).
    ///
    /// Compares top edges rather than measuring the bar's thickness. A placed item's
    /// window is flush to the top of its screen whatever the bar's height, which
    /// matters on a notched display — there the visual menu bar is ~37pt while
    /// `NSStatusBar.system.thickness` still reports 24, so a thickness-derived
    /// cutoff reads a correctly placed item as unplaced.
    ///
    /// Pure so both the placed and unplaced cases are testable without a live menu
    /// bar — this machine's bar is full, so the placed case cannot be staged on it.
    static func statusItemIsUnplaced(itemFrame: CGRect, screenFrame: CGRect) -> Bool {
        abs(itemFrame.maxY - screenFrame.maxY) > statusItemPlacementSlack
    }
    /// The genuinely fixed part of a row: padding 20 + glyph 15 + four 5pt gaps
    /// + trailing 81 (time 48, chip 29, one 4pt gap). Context moved to line 2's
    /// meter. Every figure here is derived from the 11pt row font, so changing
    /// that means rederiving them.
    static let rowFixedColumns: CGFloat = 136
    /// Fixed width of a row's trailing slot — the host chip at rest, the ✕ clear
    /// button on hover. Shared so the footer can right-align its countdown to the
    /// same column as the row times above it.
    static let rowTrailingSlot: CGFloat = 29
    /// Shared track width for every footer gauge (5h / 7d / trend) so the bars are
    /// identical in size, kept short enough that all three fit within the panel
    /// without clipping.
    static let usageTrackWidth: CGFloat = 45
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
    /// How far back the "trend" gauge looks; older samples are trimmed.
    static let usageTrendWindow: TimeInterval = 3 * 3600
    /// Collapse samples closer together than this so mashing manual Refresh can't
    /// flood the trend window with near-duplicate points.
    static let usageSampleMinGap: TimeInterval = 2 * 60
    /// A drop at least this large between consecutive samples can only be the 5h
    /// window resetting, not usage organically falling — utilization never drops
    /// this fast on its own. The trend only compares samples since the most
    /// recent such reset, so it never reports a misleading giant negative.
    static let usageResetDropThreshold = 20
    /// Collapse context samples closer together than this. A busy turn rewrites
    /// the statusLine far faster than the chart can show, and every rescan would
    /// otherwise append a point.
    static let contextSampleMinGap: TimeInterval = 15
    /// Points kept per session. At the gap above that is over an hour of solid
    /// work, and far longer in practice since an unchanged count appends nothing.
    static let contextHistoryMax = 240
    /// Usage older than this is flagged stale in the footer — no statusLine session
    /// has refreshed it recently (the only source of the 5h/7d percentages).
    static let usageStaleAfter: TimeInterval = 15 * 60
    /// How often the menu-bar reset countdown re-renders. The countdown's finest
    /// unit is the minute, so a faster tick would redraw the status item without
    /// ever changing its text.
    static let countdownTickInterval: TimeInterval = 60
}

/// What the menu-bar title displays: live activity, or the 5h usage limit.
enum MenuBarMode: String {
    case activity, usage
}

/// Which surface the app presents. `menuBar` is the status item, falling back to
/// the window when macOS refuses to place it -- so this preference can never lock
/// the user out. `window` skips the status item entirely, which is not only
/// deterministic but hands a slot back to a menu bar that was full enough to drop
/// it in the first place.
enum Surface: String {
    case menuBar, window
}

/// Why live usage stopped refreshing. The two cases need different words: an
/// expired token is the user's problem and stays broken until they act, while a
/// dropped connection or a 5xx clears itself on the next poll. Collapsing both
/// into "expired" told people their auth had died every time the wifi blinked.
enum UsageFailure: Equatable {
    case authExpired
    case transient(String)

    /// The short word shown in the header next to the warning triangle.
    var notice: String {
        switch self {
        case .authExpired: return "expired"
        case .transient:   return "error"
        }
    }

    /// The full sentence behind the header's tooltip.
    var detail: String {
        switch self {
        case .authExpired:
            return "Usage auth expired — run any terminal Claude session to refresh."
        case .transient(let message):
            return "Usage isn't refreshing: \(message). Retrying on the next poll."
        }
    }
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
    var notification_type: String?
    var cwd: String?
    var host: String?
    var pid: Double?
    var turn_start: Double?
    var updated: Double?
    var last_seed: Double?
    var last_duration: Double?
    var todo_total: Double?
    var todo_done: Double?
    var parent_session_id: String?
    var agent_id: String?
    var agent_type: String?
}

/// `<id>.status.json`, the raw statusLine stdin JSON. Only the fields the app
/// renders are declared; unknown keys are ignored. `JSONDecoder` reads JSON
/// integers and floats alike as `Double`, so `used_percentage` needs no special
/// casing the way `JSONSerialization`'s `NSNumber` did.
private struct StatusFile: Decodable {
    struct Model: Decodable {
        var display_name: String?
        var id: String?
    }
    struct Workspace: Decodable {
        struct Repo: Decodable {
            var owner: String?
            var name: String?
        }
        var current_dir: String?
        var repo: Repo?
    }
    struct RateLimits: Decodable {
        struct Window: Decodable {
            var used_percentage: Double?
            var resets_at: Double?
        }
        var five_hour: Window?
        var seven_day: Window?
    }
    struct ContextWindow: Decodable {
        var total_input_tokens: Int?
        var total_output_tokens: Int?
        var context_window_size: Int?
        var used_percentage: Double?
    }
    struct Cost: Decodable {
        var total_cost_usd: Double?
        var total_duration_ms: Double?
        var total_api_duration_ms: Double?
        var total_lines_added: Int?
        var total_lines_removed: Int?
    }
    struct PromptCache: Decodable {
        var hit_ratio: Double?
        var warm: Bool?
        var ttl: String?
        var requests: Int?
        var misses: Int?
    }
    struct Named: Decodable { var name: String? }
    struct Effort: Decodable { var level: String? }
    struct Thinking: Decodable { var enabled: Bool? }
    var model: Model?
    var cwd: String?
    var session_name: String?
    var workspace: Workspace?
    var rate_limits: RateLimits?
    var context_window: ContextWindow?
    var cost: Cost?
    var prompt_cache: PromptCache?
    var output_style: Named?
    var effort: Effort?
    var thinking: Thinking?
    var version: String?
    var transcript_path: String?
    var exceeds_200k_tokens: Bool?
}

/// Everything the statusLine reports that isn't a number the rows already draw.
/// Grouped rather than flattened onto `SessionFeed`: these arrive together, are
/// all optional for the same reason (no statusLine has run yet), and are read
/// together by the one view that shows them.
struct SessionDetailStats: Equatable {
    var costUSD: Double?
    var wallSeconds: Double?
    var apiSeconds: Double?
    var linesAdded: Int?
    var linesRemoved: Int?

    var contextWindowSize: Int?
    var contextUsedPercent: Int?
    var exceeds200k: Bool?

    var cacheHitRatio: Double?
    var cacheWarm: Bool?
    var cacheTTL: String?
    var cacheRequests: Int?
    var cacheMisses: Int?

    var modelID: String?
    var effort: String?
    var thinking: Bool?
    var outputStyle: String?
    var claudeVersion: String?
    var repo: String?
    var transcriptPath: String?

    /// How much of the turn was spent waiting on the API rather than on tools
    /// and everything else. nil unless both halves are known — a ratio against a
    /// missing denominator is a made-up number.
    var apiShare: Double? {
        guard let apiSeconds, let wallSeconds, wallSeconds > 0 else { return nil }
        return apiSeconds / wallSeconds
    }
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
    /// Claude Code's generated name for the session. Two forms occur in the wild —
    /// a kebab slug (`panel-status-truncation-fix`) and a prose sentence (`Set up
    /// iTerm2 shell integration`) — and older sessions have neither.
    var sessionName: String?
    var fiveHourPct: Int?
    var fiveHourResetsAt: Double?
    var sevenDayPct: Int?
    /// The just-finished turn, for Claude's grey "Sautéed for 5m 18s" done line.
    var lastSeed: Int?
    var lastDuration: Int?
    var contextInputTokens: Int?
    var contextOutputTokens: Int?
    var todoTotal: Int?
    var todoDone: Int?
    var stats = SessionDetailStats()
    /// Which notification put this session in `.attention`. `idle_prompt` means
    /// Claude *finished* and you haven't typed for 60s; everything else means
    /// something is actually blocked on you. Nil for older feed files.
    var notificationType: String?
    var parentSessionId: String?
    var agentId: String?
    var agentType: String?
    var isChild: Bool { parentSessionId != nil }

    init(id: String) { self.id = id }

    /// Merge the hook-written state file (status, current tool, turn start).
    fileprivate mutating func applyState(_ s: StateFile) {
        if let st = s.status { status = SessionStatus(rawValue: st) ?? .idle }
        notificationType = s.notification_type
        tool = s.tool ?? ""
        message = s.message ?? ""
        if let c = s.cwd, !c.isEmpty { cwd = c }
        if let h = s.host, !h.isEmpty { host = h; hostTag = HostTag.from(h) }
        if let p = s.pid { pid = Int(p) }
        turnStart = s.turn_start.map { Date(timeIntervalSince1970: $0) }  // null when idle
        if let up = s.updated { updated = Date(timeIntervalSince1970: up) }
        lastSeed = s.last_seed.map(Int.init)
        lastDuration = s.last_duration.map(Int.init)
        todoTotal = s.todo_total.map(Int.init)
        todoDone = s.todo_done.map(Int.init)
        parentSessionId = s.parent_session_id
        agentId = s.agent_id
        agentType = s.agent_type
    }

    #if DEBUG
    /// Test-only seam — decodes real JSON into the (private) `StateFile` and
    /// runs it through the actual `applyState`, so tests exercise production
    /// code rather than a hand-written mirror of it. `StateFile`/`applyState`
    /// are private/fileprivate to this file, so this has to live here too.
    mutating func applyStateJSONForTest(_ json: String) throws {
        let s = try JSONDecoder().decode(StateFile.self, from: Data(json.utf8))
        applyState(s)
    }

    mutating func applyStatusJSONForTest(_ json: String) throws {
        let s = try JSONDecoder().decode(StatusFile.self, from: Data(json.utf8))
        applyStatus(s)
    }
    #endif

    fileprivate mutating func applyStatus(_ s: StatusFile) {
        if let m = s.model?.display_name { model = m }
        if let n = s.session_name, !n.isEmpty { sessionName = n }
        if cwd.isEmpty {
            if let c = s.cwd { cwd = c }
            else if let c = s.workspace?.current_dir { cwd = c }
        }
        if let five = s.rate_limits?.five_hour {
            if let p = five.used_percentage { fiveHourPct = Int(p.rounded()) }
            if let r = five.resets_at { fiveHourResetsAt = r }
        }
        if let p = s.rate_limits?.seven_day?.used_percentage { sevenDayPct = Int(p.rounded()) }
        if let ctx = s.context_window {
            contextInputTokens = ctx.total_input_tokens
            contextOutputTokens = ctx.total_output_tokens
            stats.contextWindowSize = ctx.context_window_size
            stats.contextUsedPercent = ctx.used_percentage.map { Int($0.rounded()) }
        }
        if let c = s.cost {
            stats.costUSD = c.total_cost_usd
            stats.wallSeconds = c.total_duration_ms.map { $0 / 1000 }
            stats.apiSeconds = c.total_api_duration_ms.map { $0 / 1000 }
            stats.linesAdded = c.total_lines_added
            stats.linesRemoved = c.total_lines_removed
        }
        if let pc = s.prompt_cache {
            stats.cacheHitRatio = pc.hit_ratio
            stats.cacheWarm = pc.warm
            stats.cacheTTL = pc.ttl
            stats.cacheRequests = pc.requests
            stats.cacheMisses = pc.misses
        }
        stats.modelID = s.model?.id ?? stats.modelID
        stats.effort = s.effort?.level ?? stats.effort
        stats.thinking = s.thinking?.enabled ?? stats.thinking
        stats.outputStyle = s.output_style?.name ?? stats.outputStyle
        stats.claudeVersion = s.version ?? stats.claudeVersion
        stats.transcriptPath = s.transcript_path ?? stats.transcriptPath
        stats.exceeds200k = s.exceeds_200k_tokens ?? stats.exceeds200k
        if let repo = s.workspace?.repo, let name = repo.name {
            stats.repo = [repo.owner, name].compactMap { $0 }.joined(separator: "/")
        }
    }

    var isWorking: Bool { status == .thinking || status == .tool }

    /// Whether the prompt is free to type into.
    ///
    /// Not `status == .idle`. A session in `.attention` is *waiting on you* --
    /// it is sitting at the prompt, which is exactly when typing works. Gating
    /// on idle alone disabled the reply box and the slash commands on the one
    /// session you most want to answer.
    var isAtPrompt: Bool { !isWorking }

    /// Whether anything is actually blocked on a person.
    ///
    /// `emit.sh` maps every Notification event to `.attention`, and `idle_prompt`
    /// is one of them — it fires 60 seconds after a turn ends if you haven't
    /// typed. Treating that as "needs input" put a finished session in the same
    /// orange row as one holding a permission prompt, with no way to tell which
    /// deserved an answer.
    var isBlockedOnYou: Bool {
        status == .attention && notificationType != "idle_prompt"
    }

    /// One line saying what the session wants, or nothing if it wants nothing.
    var attentionSummary: String? {
        guard status == .attention else { return nil }
        switch notificationType {
        case "idle_prompt":
            return "Finished — waiting at the prompt, nothing to answer"
        case "permission_prompt":
            return message.isEmpty ? "Waiting for permission to run a tool" : message
        case .none:
            return message.isEmpty ? "Waiting on you" : message
        default:
            return message.isEmpty ? "Waiting on you" : message
        }
    }

    /// What the feed observed about a session that is sitting still, or nil
    /// when it isn't sitting still.
    ///
    /// Deliberately not a verdict. Whether a session is safe to clear turns on
    /// whether the reasoning in its context is written down anywhere, and no
    /// feed file can see that. What the feed can say is how long it has rested
    /// and whether it left todos open, so that is all this says. A row reading
    /// "safe to clear" above three open todos would be the same defect as a
    /// cost figure that reads as a bill.
    ///
    /// `includeTodos` is false on the panel's second line, which falls back to
    /// `todoSummary` in the same slot when there is no resting evidence.
    func restingEvidence(now: Date, includeTodos: Bool = true) -> String? {
        guard !isWorking, !isBlockedOnYou else { return nil }
        var parts: [String] = []
        if includeTodos, let total = todoTotal, total > 0 {
            let open = total - (todoDone ?? 0)
            if open > 0 {
                parts.append("\(open) todo\(open == 1 ? "" : "s") open")
            } else {
                parts.append("\(total)/\(total) todos")
            }
        }
        // Omitted, never rendered as zero, when the feed carries no stamp:
        // "idle 0s" on a session last seen an hour ago is an invented reading.
        if let updated {
            let age = max(0, Int(now.timeIntervalSince(updated)))
            parts.append("idle \(FeedWatcher.formatDuration(age))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    var projectName: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "session" : name
    }

    /// What a row calls this session: its generated name when there is one — the only
    /// thing telling two sessions in the same directory apart — falling back to the
    /// directory. The cwd stays in the row's tooltip either way.
    var displayName: String {
        if isChild { return sessionName ?? agentType ?? "subagent" }
        return sessionName ?? projectName
    }

    /// `displayName`, but never the bare word "session".
    ///
    /// A session with no generated name and no cwd — one whose statusLine hasn't
    /// reported yet — falls all the way through to `projectName`'s "session"
    /// placeholder, and a sidebar of four rows reading "session / session" tells
    /// you nothing and hides which is which. The id prefix is ugly but it is at
    /// least distinguishing, and it disappears the moment a statusLine lands.
    var distinctName: String {
        let name = displayName
        guard name == "session" else { return name }
        return "session \(id.prefix(6))"
    }

    /// Context tokens in play, or nil when the statusLine hasn't reported a window
    /// yet — which the row draws as an empty column rather than a misleading `0`.
    var contextTokens: Int? {
        guard contextInputTokens != nil || contextOutputTokens != nil else { return nil }
        return (contextInputTokens ?? 0) + (contextOutputTokens ?? 0)
    }

    /// The `(total, done)` pair `todoSummary` actually draws, coalesced from
    /// the optional decoded counts. The real call site (`SessionRow`) and its
    /// tests should both go through this rather than each inlining `?? 0` —
    /// the value the bar renders and the value tested must be the same one.
    var todoProgress: (total: Int, done: Int) {
        (todoTotal ?? 0, todoDone ?? 0)
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

/// One session's context size at a moment.
///
/// Separate from `UsageSample` on purpose: that one is an account-wide rate
/// limit sampled by the poller, this is per session and arrives with the
/// statusLine. Nothing about them is shared but the shape.
struct ContextSample: Codable, Equatable {
    var tokens: Int
    var at: Double  // epoch seconds
}

/// One timestamped 5h-utilization poll result, kept for the footer "trend" gauge.
struct UsageSample: Codable {
    var pct: Int
    var at: Double  // epoch seconds
    /// The 7d window at the same poll, for the window's history chart. Optional
    /// because samples persisted before it was recorded decode without it, and
    /// a missing reading must not draw as 0%.
    var sevenDayPct: Int? = nil
}

/// One dropdown row — a single session, or a collapsed group of never-worked
/// idle sessions sharing a directory.
struct SessionRowItem: Identifiable {
    let id: String
    let session: SessionFeed
    let ids: [String]
    var count: Int { ids.count }
    /// 0 = root row, 1 = nested subagent. Visual nesting is capped at 1.
    var depth: Int = 0
    /// How many subagent child ids are included in `ids` (0 for collapsed
    /// idle groups, which also have `ids.count > 1`).
    var subagentCount: Int = 0
    /// Idle-collapse `×N` badge. A parent with subagent children also has
    /// `count > 1` (child ids ride on `ids` so `clear()` cascades), but that
    /// is not a grouped idle row.
    var showsCountBadge: Bool { subagentCount == 0 && count > 1 }
}

/// One section of either session list: a project, or the pinned "Needs you" group.
struct ProjectSection: Identifiable {
    let id: String          // "needs-you", or "project:<name>"
    let title: String
    let items: [SessionRowItem]
    /// Sessions this section lists, expanding a collapsed idle row's `×N` and
    /// ignoring nested subagent rows.
    let sessionCount: Int
    /// The section's context tokens added together, or nil when nothing in it has
    /// reported a window. Untinted at the call sites for the same reason
    /// `totalContextTokens` is: these are separate windows, so a summed 210k is not
    /// the same "heavy" as one 210k session.
    let contextTotal: Int?
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
    private let onError: (String) -> Void
    private var timer: Timer?

    init(onUpdate: @escaping (Result) -> Void, onAuthExpired: @escaping () -> Void, onError: @escaping (String) -> Void) {
        self.onUpdate = onUpdate
        self.onAuthExpired = onAuthExpired
        self.onError = onError
    }

    func start() {
        // Reassigning `timer` would drop the old one without invalidating it, so a
        // double-start would leave an orphaned timer polling forever.
        stop()
        poll(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) {
            [weak self] _ in self?.poll(force: false)
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refreshNow() { poll(force: true) }

    /// Seconds since the last user input, across the whole session (keyboard/mouse).
    static var userIdleSeconds: Double {
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
            guard let self else { return }
            // No token reads the same as an expired one: both are fixed by
            // signing in, and a silent return froze the last number on screen.
            guard let token = self.oauthToken() else {
                DispatchQueue.main.async { self.onAuthExpired() }
                return
            }
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
            let task = self.session.dataTask(with: req) { [weak self] _, response, error in
                guard let self else { return }
                if let error = error {
                    DispatchQueue.main.async { self.onError(error.localizedDescription) }
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    DispatchQueue.main.async { self.onError("Invalid response") }
                    return
                }
                if http.statusCode == 401 {
                    DispatchQueue.main.async { self.onAuthExpired() }
                    return
                }
                // Non-2xx (rate-limited, transient server error): ignore this poll,
                // let the next timer tick retry — no rapid hammering.
                guard (200..<300).contains(http.statusCode) else {
                    DispatchQueue.main.async { self.onError("HTTP \(http.statusCode)") }
                    return
                }
                var headers: [String: String] = [:]
                for (k, v) in http.allHeaderFields {
                    if let ks = k as? String, let vs = v as? String { headers[ks.lowercased()] = vs }
                }
                guard let result = Self.parse(headers: headers, now: Date()) else {
                    DispatchQueue.main.async { self.onError("Parse failure") }
                    return
                }
                DispatchQueue.main.async { self.onUpdate(result) }
            }
            task.resume()
        }
    }
}

/// Today's, this week's and the active 5h block's token/spend totals, read from
/// `ccusage` (which scans every transcript, ended sessions included). Spend is
/// api-equivalent, not billed on Max.
///
/// ccusage's price lookup is intermittent: observed 2026-09-29, the same query
/// a minute apart returned $154 and $1.84, the low run pricing only haiku and
/// every opus/sonnet row at $0.00. So cost is nil (unknown) whenever a model
/// with tokens came back at zero, and the block carries tokens only -- its JSON
/// has no per-model breakdown to check its dollar figure against.
final class UsageTotalsPoller {
    struct Block {
        var tokens: Int
        var projectedTokens: Int?
        var remainingMinutes: Int?
    }
    /// One `daily` row, kept for the week chart rather than summed away.
    struct Day: Equatable {
        var period: String  // yyyy-MM-dd
        var tokens: Int
    }
    struct Result {
        var todayTokens: Int
        var todayCost: Double?
        var weekTokens: Int
        var weekCost: Double?
        var block: Block?
        var fetchedAt: Date
        var days: [Day] = []
    }

    /// Long: a daily scan costs ~11s wall and ~90s CPU across every transcript.
    static let pollInterval: TimeInterval = 10 * 60
    static let executable = "/opt/homebrew/bin/ccusage"
    /// Without `--offline` a run waits on a network price fetch; a hung one
    /// would hold `inFlight` forever and freeze the totals until relaunch.
    /// Generous: a live scan under build load has taken over 2 min.
    static let runTimeout: TimeInterval = 5 * 60

    private let onUpdate: (Result) -> Void
    private let onError: (String) -> Void
    private var timer: Timer?
    /// A slow scan must not stack a second one behind it. Main-thread only.
    private var inFlight = false
    /// A forced poll that arrived mid-scan; run it once the scan lands.
    private var pendingForce = false

    init(onUpdate: @escaping (Result) -> Void, onError: @escaping (String) -> Void) {
        self.onUpdate = onUpdate
        self.onError = onError
    }

    func start() {
        stop()
        poll(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) {
            [weak self] _ in self?.poll(force: false)
        }
    }

    func stop() { timer?.invalidate(); timer = nil; pendingForce = false }

    func refreshNow() { poll(force: true) }

    /// Pure JSON→Result parse. Nil means the output wasn't the shape ccusage
    /// documents, never "no usage": an empty `daily` is an observed zero.
    static func parse(daily: Data, blocks: Data, today: String, now: Date) -> Result? {
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        guard let d = try? JSONSerialization.jsonObject(with: daily) as? [String: Any],
              let rows = d["daily"] as? [[String: Any]],
              let b = try? JSONSerialization.jsonObject(with: blocks) as? [String: Any],
              let blockRows = b["blocks"] as? [[String: Any]] else { return nil }
        var result = Result(todayTokens: 0, todayCost: 0, weekTokens: 0, weekCost: 0,
                            block: nil, fetchedAt: now)
        for row in rows {
            guard let period = row["period"] as? String,
                  let tokens = num(row["totalTokens"]),
                  let cost = num(row["totalCost"]) else { return nil }
            let priced = isPriced(row)
            result.days.append(Day(period: period, tokens: Int(tokens)))
            result.weekTokens += Int(tokens)
            result.weekCost = priced ? result.weekCost.map { $0 + cost } : nil
            if period == today {
                result.todayTokens += Int(tokens)
                result.todayCost = priced ? result.todayCost.map { $0 + cost } : nil
            }
        }
        if let row = blockRows.first(where: { $0["isActive"] as? Bool == true }) {
            guard let tokens = num(row["totalTokens"]) else { return nil }
            let projection = row["projection"] as? [String: Any]
            result.block = Block(tokens: Int(tokens),
                                 projectedTokens: num(projection?["totalTokens"]).map { Int($0) },
                                 remainingMinutes: num(projection?["remainingMinutes"]).map { Int($0) })
        }
        return result
    }

    /// A day's cost is trustworthy only if every model that used tokens got a
    /// price. No breakdown at all means there is nothing to check it against.
    static func isPriced(_ row: [String: Any]) -> Bool {
        guard let models = row["modelBreakdowns"] as? [[String: Any]] else { return false }
        return models.allSatisfy { m in
            let used = ["inputTokens", "outputTokens", "cacheCreationTokens", "cacheReadTokens"]
                .contains { ((m[$0] as? NSNumber)?.intValue ?? 0) > 0 }
            return !used || ((m["cost"] as? NSNumber)?.doubleValue ?? 0) > 0
        }
    }

    /// Runs ccusage and returns stdout, or an error message. No `--offline`: its
    /// cached price table predates current models and prices them at $0.00.
    private static func run(_ args: [String]) -> (Data?, String?) {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return (nil, "ccusage not found") }
        // GitProbe.run bounds the drain after exit: ccusage's node wrapper spawns
        // the native binary with inherited stdio and never forwards SIGTERM, so a
        // hung child would otherwise hold stdout open past the kill forever.
        guard let r = GitProbe.run(executable, args, in: "/", timeout: runTimeout) else {
            return (nil, "ccusage timed out after \(Int(runTimeout))s")
        }
        guard r.status == 0 else { return (nil, "ccusage exit \(r.status)") }
        return (Data(r.out.utf8), nil)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func poll(force: Bool) {
        if inFlight { pendingForce = pendingForce || force; return }
        if !force && UsagePoller.userIdleSeconds > UsagePoller.pauseAfterIdle { return }
        inFlight = true
        let now = Date()
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let since = Self.dayFormatter.string(from: weekStart).replacingOccurrences(of: "-", with: "")
        let today = Self.dayFormatter.string(from: now)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let (daily, err1) = Self.run(["daily", "--json", "--since", since])
            let (blocks, err2) = daily == nil ? (nil, nil) : Self.run(["blocks", "--active", "--json"])
            func parse(_ daily: Data?) -> Result? {
                daily.flatMap { d in blocks.flatMap { Self.parse(daily: d, blocks: $0, today: today, now: Date()) } }
            }
            let result = parse(daily)
            // No retry for an unpriced run: the prices are parsed but nothing
            // displays them, and the retry was a second full transcript scan for
            // a figure no surface reads.
            var err = err1 ?? err2
            if result == nil { err = err ?? "unreadable output" }
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                if let result { self.onUpdate(result) } else { self.onError(err ?? "unreadable output") }
                if self.pendingForce { self.pendingForce = false; self.poll(force: true) }
            }
        }
    }
}

/// Just the spinner's phase, observed by the menu-bar label alone.
final class GlyphClock: ObservableObject {
    @Published var phase = 0
}

final class FeedWatcher: ObservableObject {
    @Published private(set) var sessions: [SessionFeed] = [] {
        // Recompute the usage-bearing session once per publish, not on every footer
        // tick — the 1s countdown + glyph ticks read usage ~7x/sec (review #5).
        didSet { usageSession = Self.pickUsageSession(sessions) }
    }
    /// Cached snapshot of `usageSession`, refreshed by `sessions`' didSet.
    private var usageSession: SessionFeed?

    /// The panel width in effect for the current open, clamped to the status item's
    /// screen by `AppDelegate` at show time. Drives the SwiftUI panel frame and the
    /// per-row column budget so rows reflow instead of clipping off the screen edge.
    @Published private(set) var panelWidth: CGFloat = Constants.panelWidth
    /// Set the clamped panel width for the next/current open. Guarded so a repeat
    /// open at the same width (the common case — the display rarely moves) doesn't
    /// trigger a needless SwiftUI relayout.
    func setPanelWidth(_ width: CGFloat) {
        if panelWidth != width { panelWidth = width }
    }

    /// Advances ~10x/sec to animate the menu-bar spinner glyph. Kept as plain
    /// observable state (not a TimelineView in the MenuBarExtra label, which can
    /// collapse the status item to zero size and render it invisible).
    /// The menu-bar spinner's 10 Hz tick, held apart from the feed: the window's
    /// views observe the feed, and a tick published from it re-evaluated the
    /// whole window ten times a second while anything was working.
    let glyphClock = GlyphClock()
    private var glyphPhase: Int { glyphClock.phase }

    /// Advances once a minute purely to re-render the menu-bar reset countdown.
    /// The countdown is derived from `Date()` at read time, so without a periodic
    /// nudge it would freeze whenever nothing else published — which is exactly
    /// the idle case the countdown is most useful in.
    @Published private(set) var minuteTick = 0

    /// What the menu-bar title shows; persisted across launches.
    @Published var menuBarMode: MenuBarMode {
        didSet { UserDefaults.standard.set(menuBarMode.rawValue, forKey: "menuBarMode") }
    }

    /// Which surface to present; persisted, read once at launch. Changing it takes
    /// effect on the next launch -- tearing down and rebuilding a status item
    /// mid-run is machinery this doesn't need.
    @Published var surface: Surface {
        didSet { UserDefaults.standard.set(surface.rawValue, forKey: "surface") }
    }

    private let dir: URL
    /// Where the state files live. `SessionReplier` watches one to confirm a
    /// reply actually landed.
    var feedDirectory: URL { dir }
    private var source: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var timer: Timer?
    private var animTimer: Timer?
    private var countdownTimer: Timer?
    /// Session ids already alerted for attention, so each pause notifies once.
    private var notifiedAttention: Set<String> = []
    /// Same, for finished turns. Separate set: a session alternates between the
    /// two all day and one set would suppress the other.
    private var notifiedDone: Set<String> = []
    /// False until the first scan lands. That scan only seeds `notifiedDone`:
    /// every session on disk at launch finished its turn before we were
    /// watching, and a relaunch used to banner each one.
    private var doneSeeded = false
    /// Alert when a turn finishes, not only when Claude is stuck. Off by default
    /// -- every turn of every session ends, so this is the noisy one.
    @Published var notifyOnDone: Bool {
        didSet { UserDefaults.standard.set(notifyOnDone, forKey: "notifyOnDone") }
    }
    /// Last-known usage, so it survives Clear All / statusLine-less sessions.
    private var cachedUsage: UsageSnapshot?
    /// Recent 5h utilization samples (oldest→newest), each stamped with when it
    /// was polled, backing the footer's "trend" gauge. Persisted so the trend
    /// survives relaunch; trimmed to `Constants.usageTrendWindow`.
    @Published private(set) var usageHistory: [UsageSample] = []
    /// Context size over time, per session id. The app's first per-session time
    /// series -- every other number in the detail pane is latest-value only.
    @Published private(set) var contextHistory: [String: [ContextSample]] = [:]

    /// Live account usage from the API poller (preferred over the statusLine feed
    /// because it refreshes in any session, not just an interactive TUI one).
    @Published private(set) var pollUsage: UsagePoller.Result?
    /// Set when the poller can't refresh usage, so the header can explain why the
    /// numbers stopped moving; cleared on the next good poll and when polling is
    /// turned off (a notice about polling failing is meaningless once it's off).
    @Published private(set) var usageFailure: UsageFailure?
    private var poller: UsagePoller?
    /// Today/week/block totals from ccusage. On failure the last good value stays
    /// (dimmed once stale) and `usageTotalsError` says why; it never becomes zero.
    @Published private(set) var usageTotals: UsageTotalsPoller.Result?
    @Published private(set) var usageTotalsError: String?
    private var totalsPoller: UsageTotalsPoller?
    /// Whether to poll the API for live usage; persisted, on by default.
    @Published var usagePollingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(usagePollingEnabled, forKey: "usagePollingEnabled")
            usagePollingEnabled ? poller?.start() : stopPolling()
            usagePollingEnabled ? totalsPoller?.start() : totalsPoller?.stop()
        }
    }
    /// All disk reads/parses and file pruning happen here, off the main thread.
    private let ioQueue = DispatchQueue(label: "spinnerfeed.io", qos: .utility)
    private var pendingScan: DispatchWorkItem?

    init() {
        menuBarMode = UserDefaults.standard.string(forKey: "menuBarMode")
            .flatMap(MenuBarMode.init(rawValue:)) ?? .activity
        surface = UserDefaults.standard.string(forKey: "surface")
            .flatMap(Surface.init(rawValue:)) ?? .menuBar
        cachedUsage = UserDefaults.standard.data(forKey: "usageSnapshot")
            .flatMap { try? JSONDecoder().decode(UsageSnapshot.self, from: $0) }
        usageHistory = UserDefaults.standard.data(forKey: "usageHistory")
            .flatMap { try? JSONDecoder().decode([UsageSample].self, from: $0) } ?? []
        contextHistory = UserDefaults.standard.data(forKey: "contextHistory")
            .flatMap { try? JSONDecoder().decode([String: [ContextSample]].self, from: $0) } ?? [:]
        // Spend history was recorded with no reader (dropped 2026-09-30); clear
        // what earlier builds left behind.
        UserDefaults.standard.removeObject(forKey: "spendHistory")
        // Default on; the key is absent on first launch, so read with a default.
        usagePollingEnabled = (UserDefaults.standard.object(forKey: "usagePollingEnabled") as? Bool) ?? true
        notifyOnDone = (UserDefaults.standard.object(forKey: "notifyOnDone") as? Bool) ?? false
        dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/spinnerfeed", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        isSetupInstalled = Self.checkSetupInstalled(dir: dir)
        ioQueue.async { [weak self] in self?.performRescan() }
        startWatching()
        poller = UsagePoller(
            onUpdate: { [weak self] result in self?.applyPollResult(result) },
            onAuthExpired: { [weak self] in self?.usageFailure = .authExpired; self?.pollUsage = nil },
            onError: { [weak self] message in self?.usageFailure = .transient(message) })
        if usagePollingEnabled { poller?.start() }
        totalsPoller = UsageTotalsPoller(
            onUpdate: { [weak self] result in self?.usageTotals = result; self?.usageTotalsError = nil },
            onError: { [weak self] message in self?.usageTotalsError = message })
        if usagePollingEnabled { totalsPoller?.start() }
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
                self.glyphClock.phase &+= 1
            }
        }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: Constants.countdownTickInterval,
                                              repeats: true) { [weak self] _ in
            self?.minuteTick &+= 1
        }
    }

    deinit {
        source?.cancel()
        timer?.invalidate()
        animTimer?.invalidate()
        countdownTimer?.invalidate()
        poller?.stop()
        totalsPoller?.stop()
    }

    private func stopPolling() {
        poller?.stop()
        // Nothing is polling now, so a "usage isn't refreshing" notice is both true
        // and useless — and it would otherwise pin itself in the header forever,
        // since only a successful poll clears it.
        usageFailure = nil
        // A result that will never refresh again must not outrank the live
        // statusLine numbers, which it would forever as the head of the chain.
        pollUsage = nil
    }

    /// Force an immediate usage poll (right-click → Refresh).
    func refreshUsage() { poller?.refreshNow(); totalsPoller?.refreshNow() }

    /// Store a fresh poll result and persist it to the usage cache so it survives
    /// relaunch and Clear All. Runs on main.
    private func applyPollResult(_ result: UsagePoller.Result) {
        pollUsage = result
        usageFailure = nil
        let snap = UsageSnapshot(fiveHourPct: result.fiveHourPct,
                                 fiveHourResetsAt: result.fiveHourResetsAt,
                                 sevenDayPct: result.sevenDayPct,
                                 model: cachedUsage?.model,
                                 savedAt: result.fetchedAt.timeIntervalSince1970)
        cachedUsage = snap
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: "usageSnapshot")
        }
        recordUsageSample(result.fiveHourPct, sevenDay: result.sevenDayPct, at: result.fetchedAt)
    }

    /// Append a timestamped 5h sample for the "trend" gauge and persist it.
    /// Collapses samples less than `usageSampleMinGap` apart (mashing manual
    /// Refresh can't flood the trend window with near-duplicate points), and
    /// trims anything older than `usageTrendWindow` so the buffer reflects an
    /// actual recent span rather than an arbitrary poll count.
    private func recordUsageSample(_ pct: Int, sevenDay: Int, at: Date) {
        let now = at.timeIntervalSince1970
        if let last = usageHistory.last, now - last.at < Constants.usageSampleMinGap { return }
        usageHistory.append(UsageSample(pct: pct, at: now, sevenDayPct: sevenDay))
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
        let live = Self.excludingOrphanIdleChildren(
            Self.excludingDeadPidIdle(recent, pidAlive: Self.pidAlive))
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
            self?.notifyDone(result)
            self?.updateUsageCache(result)
            self?.recordContextSamples(result)
            self?.sessions = result
        }
    }

    /// True if a process with this pid currently exists, belongs to the current user,
    /// and is a Claude or Node process (guards against recycled PIDs).
    private static func pidAlive(_ pid: Int) -> Bool {
        // Lightweight existence probe
        if kill(pid_t(pid), 0) != 0 { return false }
        
        var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX))
        let len = proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count))
        guard len > 0 else {
            // EPERM or other failure means it is likely owned by another user (recycled)
            return false
        }
        let path = String(cString: buffer).lowercased()
        return path.contains("claude") || path.contains("node")
    }

    /// True when the feed plumbing is in place: the emitter script exists and
    /// settings.json wires it into the hooks. When false, no session will ever
    /// appear — so the panel shows a setup hint instead of a bare "No active
    /// sessions". Computed once (on refresh) and cached — the empty-panel view can
    /// re-render up to 10x/sec (the menu-bar glyph pulse ticks even with no
    /// sessions, e.g. a usage alarm), and this does real disk I/O.
    @Published private(set) var isSetupInstalled: Bool = false

    /// Re-check whether the feed plumbing is installed and publish the result.
    /// Called after the one-click installer runs so the panel updates in place.
    func refreshSetupState() {
        isSetupInstalled = Self.checkSetupInstalled(dir: dir)
    }

    /// Per-script, not "anything of ours". A machine that installed before
    /// ask.sh existed has emit.sh in both places, so a check for emit.sh alone
    /// reports a complete install and the answer hooks silently never arrive.
    private static func checkSetupInstalled(dir: URL) -> Bool {
        let scripts = ["emit.sh", "ask.sh"]
        for script in scripts
        where !FileManager.default.fileExists(atPath: dir.appendingPathComponent(script).path) {
            return false
        }
        let settings = dir.deletingLastPathComponent().appendingPathComponent("settings.json")
        guard let text = try? String(contentsOf: settings, encoding: .utf8) else { return false }
        return scripts.allSatisfy { text.contains($0) }
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
        // Stamp with the session's own time, not the scan's: every 2s rescan
        // re-saved an idle session's hours-old numbers as "just now", and
        // overwrote a fresher poll snapshot with them.
        let savedAt = (s.updated ?? Date()).timeIntervalSince1970
        if let cached = cachedUsage, cached.savedAt >= savedAt { return }
        let snap = UsageSnapshot(fiveHourPct: s.fiveHourPct, fiveHourResetsAt: s.fiveHourResetsAt,
                                 sevenDayPct: s.sevenDayPct, model: s.model,
                                 savedAt: savedAt)
        cachedUsage = snap
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: "usageSnapshot")
        }
    }

    /// Append each live session's context size, and forget the sessions that are
    /// gone. Runs on main, once per rescan.
    ///
    /// Dropping a departed session's buffer here rather than on a timer means the
    /// history has exactly the same lifetime as the row it belongs to: a session
    /// pruned at `staleCutoff` takes its curve with it, and nothing accumulates
    /// for ids that will never render again.
    private func recordContextSamples(_ newSessions: [SessionFeed]) {
        let now = Date().timeIntervalSince1970
        var history = contextHistory
        let liveIds = Set(newSessions.map(\.id))
        history = history.filter { liveIds.contains($0.key) }
        for session in newSessions {
            guard let tokens = session.contextTokens else { continue }
            history[session.id] = Self.appending(tokens: tokens, at: now,
                                                 to: history[session.id] ?? [])
        }
        guard history != contextHistory else { return }
        contextHistory = history
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "contextHistory")
        }
    }

    /// Pure, so the three rules below are testable without a feed directory.
    ///
    /// An unchanged count appends nothing at all. Sampling it would fill the
    /// buffer with a flat line during an idle session and push out the part of
    /// the curve that has something to say -- and the chart is time-scaled, so
    /// the flat stretch is drawn from the gap between two points anyway.
    static func appending(tokens: Int, at now: Double,
                          to samples: [ContextSample]) -> [ContextSample] {
        if let last = samples.last {
            if last.tokens == tokens { return samples }
            if now - last.at < Constants.contextSampleMinGap {
                // Within the gap, correct the last point rather than skipping the
                // value. Skipping would hold a stale token count on screen for a
                // fast-moving turn; the count is what the chart is about.
                var out = samples
                out[out.count - 1] = ContextSample(tokens: tokens, at: last.at)
                return out
            }
        }
        var out = samples
        out.append(ContextSample(tokens: tokens, at: now))
        if out.count > Constants.contextHistoryMax {
            out.removeFirst(out.count - Constants.contextHistoryMax)
        }
        return out
    }

    /// Post a macOS notification the first time each session enters attention, so
    /// the user is pulled back without watching the menu bar. Runs on main.
    private func notifyAttention(_ newSessions: [SessionFeed]) {
        // Only sessions actually blocked on a person. An `idle_prompt` says a
        // turn ended and you haven't typed — the done-turn alert covers that,
        // and banner-ing it as "Claude needs you" is simply untrue.
        let attentionNow = Set(newSessions.filter(\.isBlockedOnYou).map(\.id))
        for id in attentionNow.subtracting(notifiedAttention) {
            guard let s = newSessions.first(where: { $0.id == id }) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Claude needs you"
            content.body = s.message.isEmpty ? s.projectName : "\(s.projectName) — \(s.message)"
            content.sound = .default
            // Attach the "Focus session" action and the host to activate on tap.
            content.categoryIdentifier = NotificationConfig.attentionCategory
            content.userInfo = [
                "host": s.host,
                "pid": s.pid ?? 0,
                "cwd": s.cwd
            ]
            let request = UNNotificationRequest(identifier: "attention-\(id)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
        // A banner saying "needs you" is false the moment you answer in the
        // terminal; pull it rather than leave it on screen for its own timeout.
        let resolved = notifiedAttention.subtracting(attentionNow)
        if !resolved.isEmpty {
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: resolved.map { "attention-\($0)" })
        }
        notifiedAttention = attentionNow
    }

    /// Whether a just-finished turn is worth a banner.
    ///
    /// Pure so both gates are testable. The frontmost one is what keeps this from
    /// being unbearable: a turn finishing in the window you are already looking
    /// at does not need to be announced -- you watched it happen.
    static func shouldNotifyDone(session: SessionFeed,
                                 frontmostBundleID: String?,
                                 alreadyNotified: Set<String>) -> Bool {
        guard session.parentSessionId == nil,
              session.status == .idle,
              session.lastDuration != nil,
              !alreadyNotified.contains(session.id)
        else { return false }
        guard let frontmostBundleID, !session.host.isEmpty else { return true }
        return frontmostBundleID != session.host
    }

    /// Post one banner per finished turn, for the sessions you are not watching.
    private func notifyDone(_ newSessions: [SessionFeed]) {
        // Track every finished session either way, so turning the preference on
        // doesn't immediately fire for turns that ended while it was off.
        let finished = Set(newSessions.filter {
            $0.parentSessionId == nil && $0.status == .idle && $0.lastDuration != nil
        }.map(\.id))
        defer { notifiedDone = finished; doneSeeded = true }
        guard notifyOnDone, doneSeeded else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for session in newSessions where Self.shouldNotifyDone(session: session,
                                                               frontmostBundleID: frontmost,
                                                               alreadyNotified: notifiedDone) {
            let content = UNMutableNotificationContent()
            content.title = "Claude finished"
            content.body = session.displayName
            content.sound = .default
            content.categoryIdentifier = NotificationConfig.attentionCategory
            content.userInfo = ["host": session.host, "pid": session.pid ?? 0, "cwd": session.cwd]
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "done-\(session.id)",
                                      content: content, trigger: nil))
        }
    }

    /// Totals across every root session, for the window's overview strip.
    ///
    /// Pure and static so the awkward part is testable: a session whose
    /// statusLine hasn't reported contributes nothing, and if *none* has
    /// reported the total stays nil rather than becoming a confident zero.
    struct Overview: Equatable {
        var sessions: Int = 0
        var working: Int = 0
        var waiting: Int = 0
        var spendUSD: Double?
        var contextTokens: Int?
        var linesAdded: Int?
        var linesRemoved: Int?
    }

    static func overview(for sessions: [SessionFeed]) -> Overview {
        let roots = sessions.filter { $0.parentSessionId == nil }
        var out = Overview()
        out.sessions = roots.count
        out.working = roots.filter(\.isWorking).count
        out.waiting = roots.filter { $0.status == .attention }.count

        // `compactMap` then "is it empty" rather than `reduce(0)`: summing an
        // empty list gives 0, which renders as "$0.00 spent today" when the
        // truth is that nothing has reported yet.
        func total<T: AdditiveArithmetic>(_ values: [T]) -> T? {
            values.isEmpty ? nil : values.reduce(.zero, +)
        }
        out.spendUSD = total(roots.compactMap(\.stats.costUSD))
        out.contextTokens = total(roots.compactMap(\.contextTokens))
        out.linesAdded = total(roots.compactMap(\.stats.linesAdded))
        out.linesRemoved = total(roots.compactMap(\.stats.linesRemoved))
        return out
    }

    var overview: Overview { Self.overview(for: sessions) }

    var workingCount: Int { Self.rootWorkingCount(sessions) }
    var attentionCount: Int { sessions.filter { $0.parentSessionId == nil && $0.status == .attention }.count }

    static func rootWorkingCount(_ sessions: [SessionFeed]) -> Int {
        sessions.filter { $0.parentSessionId == nil && $0.isWorking }.count
    }

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
            .filter {
                $0.parentSessionId == nil
                    && $0.status == .idle && $0.lastDuration != nil
                    && ($0.updated ?? .distantPast) > cutoff
            }
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
            $0.parentSessionId == nil
                && $0.status == .idle && $0.lastDuration != nil
                && ($0.updated ?? .distantPast) > cutoff
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
    /// Status rank first — a session waiting on you outranks any amount of context —
    /// then heaviest context first within the band, then freshest. A session with no
    /// reported context sorts as 0, below every session that has one.
    static func sorted(_ sessions: [SessionFeed]) -> [SessionFeed] {
        sessions.sorted { a, b in
            if rank(a.status) != rank(b.status) { return rank(a.status) < rank(b.status) }
            let (at, bt) = (a.contextTokens ?? 0, b.contextTokens ?? 0)
            if at != bt { return at > bt }
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

    static func childDisplayName(for child: SessionFeed, siblings: [SessionFeed]) -> String {
        let base = child.agentType ?? "subagent"
        let dup = siblings.filter { ($0.agentType ?? "subagent") == base }.count > 1
        guard dup, let aid = child.agentId, aid.count >= 4 else { return base }
        return "\(base) \(String(aid.suffix(4)))"
    }

    /// Drop idle root sessions whose captured pid is dead. Children are
    /// exempt — their pid is the parent's, so a dead pid would otherwise
    /// vanish finished children while a working parent stays until
    /// `staleCutoff`. `pidAlive` is injected so tests don't probe the
    /// process table. Pure; `performRescan` uses this before
    /// `excludingOrphanIdleChildren`.
    static func excludingDeadPidIdle(_ sessions: [SessionFeed], pidAlive: (Int) -> Bool) -> [SessionFeed] {
        sessions.filter { s in
            guard !s.isChild, s.status == .idle, let pid = s.pid else { return true }
            return pidAlive(pid)
        }
    }

    /// Drop an idle child whose parent is not in the live set. Working /
    /// attention orphans stay (the panel promotes them to depth 0). Roots
    /// always stay. Pure so prune is testable without I/O; `performRescan`
    /// uses this on the in-memory live set, after which the existing mtime
    /// walker deletes files that dropped out.
    static func excludingOrphanIdleChildren(_ sessions: [SessionFeed]) -> [SessionFeed] {
        let rootIds = Set(sessions.filter { $0.parentSessionId == nil }.map(\.id))
        return sessions.filter { s in
            guard let parent = s.parentSessionId else { return true }
            if rootIds.contains(parent) { return true }
            return s.isWorking || s.status == .attention
        }
    }

    /// Pure row-grouping used by the panel — extracted so grouping is unit-testable
    /// without I/O. Attention/working sessions stay individual; idle ones (done and
    /// never-worked) collapse by directory onto the freshest, with a count. Children
    /// (parent_session_id set) nest immediately under their parent row at depth 1
    /// and are never folded into an idle collapse group; an orphaned working/attention
    /// child (parent no longer live) is promoted to a depth-0 row of its own.
    static func displayItems(from sessions: [SessionFeed]) -> [SessionRowItem] {
        var childrenByParent: [String: [SessionFeed]] = [:]
        var roots: [SessionFeed] = []
        for s in sessions {
            if let parent = s.parentSessionId {
                childrenByParent[parent, default: []].append(s)
            } else {
                roots.append(s)
            }
        }

        var items: [SessionRowItem] = []
        // Collapse idle sessions by directory — but keep finished "done" sessions in
        // a SEPARATE bucket from never-worked idles (key prefix), so a fresher
        // never-worked session can't become the representative and hide a finished
        // turn. Each bucket's representative is the freshest of its own kind.
        var groups: [String: [SessionFeed]] = [:]
        var order: [String] = []

        func appendChildren(of parent: SessionFeed) {
            let kids = childrenByParent[parent.id] ?? []
            let named = kids.map { child -> SessionFeed in
                var c = child
                c.sessionName = childDisplayName(for: child, siblings: kids)
                return c
            }
            for child in sorted(named) {
                items.append(SessionRowItem(id: child.id, session: child, ids: [child.id], depth: 1))
            }
        }

        let rootIds = Set(roots.map(\.id))
        let orphans = sessions.filter { child in
            guard let p = child.parentSessionId else { return false }
            return !rootIds.contains(p) && (child.isWorking || child.status == .attention)
        }
        let namedOrphans: [SessionFeed] = orphans.map { child in
            var c = child
            let siblings = orphans.filter { $0.parentSessionId == child.parentSessionId }
            c.sessionName = childDisplayName(for: child, siblings: siblings)
            return c
        }

        for s in sorted(roots + namedOrphans) {
            let kids = childrenByParent[s.id] ?? []
            if !kids.isEmpty {
                items.append(SessionRowItem(
                    id: s.id, session: s,
                    ids: [s.id] + kids.map(\.id),
                    depth: 0, subagentCount: kids.count))
                appendChildren(of: s)
                continue
            }
            guard s.status == .idle else {
                items.append(SessionRowItem(id: s.id, session: s, ids: [s.id], depth: 0))
                continue
            }
            let key = (s.lastDuration != nil ? "done:" : "idle:") + s.cwd
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(s)
        }
        for key in order {
            let group = groups[key]!
            let rep = group.max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }!
            items.append(SessionRowItem(id: key, session: rep, ids: group.map(\.id), depth: 0))
        }
        return items
    }

    /// Both session lists grouped into project sections, with anything blocked on a
    /// person pinned above them.
    ///
    /// The ordering keys here are deliberately ones that DO NOT TICK — project name,
    /// then session name, then id. The sidebar used to render `sessions` in arrival
    /// order, and `rescan` builds that array from a dictionary's `values`, whose
    /// iteration order Swift does not define; the rows therefore reshuffled on every
    /// rescan. Sorting on anything live (tokens, timestamps) would have replaced an
    /// arbitrary order with a merely slower-moving one.
    ///
    /// `byRecency` is the window sidebar's opt-out, asked for by name: projects by
    /// their newest session, rows newest first, so the top row is always the
    /// latest activity. It does move as sessions report -- that is the point --
    /// but ties still fall to the id, so it never reshuffles on a rescan alone.
    /// The panel keeps the non-ticking order above.
    ///
    /// A blocked session appears in "Needs you" ONLY, not also under its project:
    /// the sidebar tags rows with the session id for `List` selection, and two rows
    /// sharing a tag is undefined. Section counts follow the rows each section lists.
    static func projectSections(_ items: [SessionRowItem],
                                asked: Set<String> = [],
                                byRecency: Bool = false) -> [ProjectSection] {
        func needsYou(_ item: SessionRowItem) -> Bool {
            item.session.isBlockedOnYou || asked.contains(item.session.id)
        }

        var sections: [ProjectSection] = []
        // A waiting session's subagents go with it: left behind, they were nested
        // under whichever root preceded them in the project section, or made a
        // section of their own with no root at all.
        var waiting: [SessionRowItem] = []
        var parentWaits = false
        for item in items {
            if item.depth == 0 { parentWaits = needsYou(item) }
            if parentWaits { waiting.append(item) }
        }
        if !waiting.isEmpty {
            sections.append(makeSection(id: "needs-you", title: "Needs you",
                                        items: ordered(waiting, byRecency: byRecency)))
        }

        let waitingIds = Set(waiting.map(\.id))
        var byProject: [String: [SessionRowItem]] = [:]
        // A child rides with its parent's project, not its own row's grouping: a
        // subagent in a worktree has a cwd of its own (`agent-<id>`), which made
        // an extra section counting 0 sessions. Children follow their parent in
        // `items`, so the last root seen is the parent.
        var parentProject: String?
        for item in items {
            if item.depth == 0 { parentProject = item.session.projectName }
            guard !waitingIds.contains(item.id) else { continue }
            byProject[item.depth == 0 ? item.session.projectName
                                      : parentProject ?? item.session.projectName,
                      default: []].append(item)
        }
        func newest(_ name: String) -> Date {
            byProject[name]!.compactMap(\.session.updated).max() ?? .distantPast
        }
        let names = byProject.keys.sorted { a, b in
            if byRecency, newest(a) != newest(b) { return newest(a) > newest(b) }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        for name in names {
            sections.append(makeSection(id: "project:" + name, title: name,
                                        items: ordered(byProject[name]!, byRecency: byRecency)))
        }
        return sections
    }

    /// Roots alphabetically (or newest first), each followed by its own nested
    /// children in the order `displayItems` already put them in — re-sorting
    /// children would split them from the parent they are indented under.
    private static func ordered(_ items: [SessionRowItem], byRecency: Bool) -> [SessionRowItem] {
        var childrenOf: [String: [SessionRowItem]] = [:]
        var roots: [SessionRowItem] = []
        var lastRoot: String?
        for item in items {
            if item.depth == 0 {
                roots.append(item)
                lastRoot = item.id
            } else if let parent = lastRoot {
                childrenOf[parent, default: []].append(item)
            }
        }
        let sortedRoots = roots.sorted { a, b in
            let (au, bu) = (a.session.updated ?? .distantPast, b.session.updated ?? .distantPast)
            if byRecency, au != bu { return au > bu }
            let (an, bn) = (a.session.distinctName, b.session.distinctName)
            if an != bn { return an.localizedStandardCompare(bn) == .orderedAscending }
            return a.id < b.id
        }
        return sortedRoots.flatMap { [$0] + (childrenOf[$0.id] ?? []) }
    }

    private static func makeSection(id: String, title: String, items: [SessionRowItem]) -> ProjectSection {
        // A collapsed idle row stands for several sessions; a parent row's `count`
        // includes its subagent ids, which are not sessions of their own here.
        let count = items.filter { $0.depth == 0 }
            .reduce(0) { $0 + ($1.showsCountBadge ? $1.count : 1) }
        let tokens = items.compactMap { $0.session.contextTokens }
        return ProjectSection(id: id, title: title, items: items,
                              sessionCount: count,
                              contextTotal: tokens.isEmpty ? nil : tokens.reduce(0, +))
    }


    /// The session whose status feed carries the account-wide rate-limit numbers
    /// (any recent session has them; they're not per-project). Cached in
    /// `usageSession` and refreshed only when `sessions` changes.
    static func pickUsageSession(_ sessions: [SessionFeed]) -> SessionFeed? {
        sessions
            .filter { $0.fiveHourPct != nil || $0.sevenDayPct != nil }
            .max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }
    }

    // Usage prefers live API-poll data, then a live session's statusLine numbers,
    // then the persisted snapshot — so it stays live in any session (poller) and
    // still survives Clear All / statusLine-less sessions (cache).
    var hasUsage: Bool { pollUsage != nil || usageSession != nil || cachedUsage != nil }

    /// Every session's context tokens added together — the one number no single row
    /// can show. nil when nothing has reported a context window yet. Deliberately
    /// untinted: these are separate windows, so a 210k sum across three light
    /// sessions is not the same "heavy" as one 210k session.
    var totalContextTokens: Int? {
        let counts = sessions.compactMap(\.contextTokens)
        return counts.isEmpty ? nil : counts.reduce(0, +)
    }
    var usageFiveHourPct: Int? { pollUsage?.fiveHourPct ?? usageSession?.fiveHourPct ?? cachedUsage?.fiveHourPct }
    var usageSevenDayPct: Int? { pollUsage?.sevenDayPct ?? usageSession?.sevenDayPct ?? cachedUsage?.sevenDayPct }
    /// A row's context token count, e.g. `212k`. Rounded to whole units so it never
    /// exceeds 4 characters — its column is 30pt and must not grow.
    static func formatTokens(_ count: Int) -> String {
        // Not 1_000_000: anything from 999_500 up rounds to "1000k", a 5th character.
        if count >= 999_500 {
            let m = Double(count) / 1_000_000.0
            return m >= 10 ? "\(Int(m.rounded()))M" : String(format: "%.1fM", m)
        }
        if count >= 1_000 {
            return "\(Int((Double(count) / 1_000.0).rounded()))k"
        }
        return "\(count)"
    }

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

    /// How far through each limit window we are, for the pace marker.
    var usageFiveHourElapsed: Double? {
        Self.windowElapsed(resetsAt: fiveHourResetsAt, length: 5 * 3600, now: Date())
    }
    var usageSevenDayElapsed: Double? {
        Self.windowElapsed(resetsAt: sevenDayResetsAt, length: 7 * 86400, now: Date())
    }

    /// 0 at the window's start, 1 at its reset. nil when the reset has already
    /// passed (a stale reading) or sits further out than one window: either way
    /// there is no honest position to mark.
    static func windowElapsed(resetsAt: Double?, length: TimeInterval, now: Date) -> Double? {
        guard let resetsAt else { return nil }
        let left = resetsAt - now.timeIntervalSince1970
        guard left >= 0, left <= length else { return nil }
        return 1 - left / length
    }

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

    /// One totals row: a label and its value, e.g. `today` / `329M`.
    struct TotalsRow: Hashable { let label: String; let value: String }

    /// ccusage totals as rows: today, week, then the active block. Tokens only:
    /// the dollar figures ccusage prices these at are not charged on a Max plan,
    /// and a running total in dollars beside them read as if they were.
    /// Empty until the first scan lands; `usageTotalsStatus` covers that gap.
    var usageTotalsRows: [TotalsRow] {
        guard let t = usageTotals else { return [] }
        var rows = [TotalsRow(label: "today", value: Self.formatTokens(t.todayTokens)),
                    TotalsRow(label: "week", value: Self.formatTokens(t.weekTokens))]
        if let b = t.block {
            var value = Self.formatTokens(b.tokens)
            if let p = b.projectedTokens { value += " → \(Self.formatTokens(p))" }
            if let m = b.remainingMinutes { value += " · \(m / 60)h\(m % 60)m left" }
            rows.append(TotalsRow(label: "block", value: value))
        }
        return rows
    }
    /// Shown in place of the rows before the first scan, after a failed one, or with polling off.
    var usageTotalsStatus: String {
        if !usagePollingEnabled { return "usage totals off" }
        return usageTotalsError.map { "usage totals unavailable (\($0))" } ?? "usage totals loading"
    }
    var usageTotalsIsStale: Bool {
        guard let t = usageTotals?.fetchedAt else { return false }
        return Date().timeIntervalSince(t) > Constants.usageStaleAfter + UsageTotalsPoller.pollInterval
    }
    var usageTotalsTooltip: String {
        var s = "ccusage totals, in tokens."
        if let t = usageTotals?.fetchedAt {
            s += " As of \(Self.resetTimeFormatter.string(from: t)) (\(Self.compactAge(since: t)) ago)."
        }
        if let e = usageTotalsError { s += " Last refresh failed: \(e)." }
        return s
    }

    /// Genuinely blocked: a window is maxed out AND the account can't buy overage.
    /// The `overage-status: rejected` header alone is NOT a problem — it's the
    /// normal setting for plans that don't allow overage (e.g. Max), so treating
    /// it as "blocked" fires a false alarm at every utilization level.
    var usageOverageBlocked: Bool {
        guard pollUsage?.overageBlocked == true else { return false }
        return (usageFiveHourPct ?? 0) >= 100 || (usageSevenDayPct ?? 0) >= 100
    }

    /// A short, urgent header note when the account is blocked on overage or polling
    /// can't refresh — nil when usage is flowing normally. The full sentence lives in
    /// `usageNoticeDetail` for the tooltip.
    var usageNotice: String? {
        if usageOverageBlocked { return "blocked" }
        return usageFailure?.notice
    }
    var usageNoticeDetail: String {
        if usageOverageBlocked { return "Account is out of credits — usage is blocked (overage rejected)." }
        return usageFailure?.detail ?? ""
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
    private static func formatResetRelative(_ resetsAt: Double?, now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        return resetCountdown(secondsRemaining: resetsAt - now.timeIntervalSince1970)
    }

    /// Pure countdown formatting, extracted so the menu-bar title can be tested
    /// without a live clock or a poller.
    static func resetCountdown(secondsRemaining: Double) -> String {
        let remaining = Int(max(0, secondsRemaining))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        return hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)m"
    }

    /// The menu-bar title in usage mode: the 5h utilization plus how long until
    /// that window resets, e.g. "5h 70% · 2h14m". Without the countdown the
    /// percentage reads as a fixed level rather than one that recovers on a clock.
    /// The countdown is dropped (not zero-filled) when no reset instant is known,
    /// since the statusLine feed carries a percentage but no `resets_at`.
    static func usageTitle(pct: Int, countdown: String?) -> String {
        guard let countdown else { return "5h \(pct)%" }
        return "5h \(pct)% · \(countdown)"
    }

    /// Menu-bar usage title for the current state; nil when there's no usage data
    /// yet and the title should fall back to the activity word.
    var usageMenuBarTitle: String? {
        guard let pct = usageFiveHourPct else { return nil }
        return Self.usageTitle(pct: pct, countdown: usageFiveHourResetRelative)
    }

    /// Trims a raw model name like "Opus 4.8 (1M context)" down to just the
    /// family word "Opus", for compact per-row display.
    static func modelFamily(_ raw: String) -> String {
        let short = String(raw.prefix { $0 != "(" }).trimmingCharacters(in: .whitespaces)
        return short.split(separator: " ").first.map(String.init) ?? short
    }

    /// Best-known model name for a row's tag: the session's own statusLine model
    /// when it's reported one, else the most recently seen model across any
    /// session, else the persisted cache — so every row shows a model tag even
    /// before its own statusLine has written (e.g. a never-worked idle session).
    static func modelDisplay(for session: SessionFeed, among sessions: [SessionFeed], cached: String?) -> String? {
        if session.isChild { return session.model }
        return session.model
            ?? sessions.filter { $0.model != nil && !$0.isChild }
                .max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }?.model
            ?? cached
    }

    func modelDisplay(for session: SessionFeed) -> String? {
        Self.modelDisplay(for: session, among: sessions, cached: cachedUsage?.model)
    }

    /// The family word a row draws, with a trailing "?" when the model was
    /// borrowed from another session or the cache rather than reported by this
    /// one. Desktop sessions never write a statusLine, so on a mixed fleet the
    /// borrowed word is a guess and must not read like a fact.
    static func modelTag(for session: SessionFeed, among sessions: [SessionFeed], cached: String?) -> String? {
        guard let raw = modelDisplay(for: session, among: sessions, cached: cached) else { return nil }
        return modelFamily(raw) + (session.model == nil ? "?" : "")
    }

    func modelTag(for session: SessionFeed) -> String? {
        Self.modelTag(for: session, among: sessions, cached: cachedUsage?.model)
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
