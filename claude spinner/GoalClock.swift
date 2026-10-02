import Combine
import SwiftUI

/// The time left on a timed `/goal` run, read from the skill's deadline file.
///
/// The file is `~/.claude/state/goal-deadline-<tmux pane id>` holding one line,
/// `<deadline epoch seconds> <original minutes>`. Anything else parses to nil,
/// and nil means *unknown*: a missing or garbled file must never render as
/// "0 min left" or as expired, which would read as a verdict about the run.
nonisolated struct GoalClock: Equatable {
    /// Positive while time remains, negative once the deadline has passed.
    let remainingSeconds: Int
    let originalMinutes: Int

    /// A deadline this long gone belongs to a session that was killed before it
    /// could delete its file, not to a run that is still overrunning.
    static let staleAfter = 24 * 60 * 60

    /// The skill lands the run with a tenth of the time still unspent.
    var reserveMinutes: Int { max(1, originalMinutes / 10) }
    var isOverrun: Bool { remainingSeconds <= 0 }
    /// Whole minutes left, floored; 0 while under a minute remains.
    var minutesLeft: Int { max(0, remainingSeconds / 60) }
    var overrunMinutes: Int { max(0, -remainingSeconds / 60) }
    var isLanding: Bool { !isOverrun && minutesLeft <= reserveMinutes }

    var label: String {
        if isOverrun {
            return overrunMinutes == 0 ? "GOAL  over by <1 min" : "GOAL  over by \(overrunMinutes) min"
        }
        let left = minutesLeft == 0 ? "<1 min left" : "\(minutesLeft) min left"
        return isLanding ? "GOAL  landing, \(left)" : "GOAL  \(left)"
    }

    /// Seconds until `label` can next change: the remaining time crossing a
    /// whole minute. A second of margin so the wake lands past the boundary.
    var secondsUntilLabelChanges: Double {
        let into = ((remainingSeconds % 60) + 60) % 60
        return Double(into == 0 ? 60 : into) + 1
    }

    static func parse(_ text: String?, now: Date) -> GoalClock? {
        guard let text else { return nil }
        let fields = text.split(whereSeparator: \.isWhitespace)
        guard fields.count == 2,
              let deadline = Int(fields[0]), deadline > 0,
              let minutes = Int(fields[1]), minutes > 0
        else { return nil }
        let remaining = deadline - Int(now.timeIntervalSince1970.rounded(.down))
        guard remaining > -staleAfter else { return nil }
        return GoalClock(remainingSeconds: remaining, originalMinutes: minutes)
    }
}

/// The file and pane side of the goal clock, kept out of `GoalClock` so its
/// tests never touch the real state directory.
nonisolated enum GoalDeadlineFile {
    static let stateDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/state")

    /// nil when the file is absent or unreadable: unknown, not "no goal".
    static func read(pane: String, in dir: URL = stateDir) -> String? {
        try? String(contentsOf: dir.appendingPathComponent("goal-deadline-\(pane)"), encoding: .utf8)
    }
}

/// Session to pane, cached: resolving shells out to ps and tmux. Only a found
/// pane is kept, so a lookup that failed is retried rather than remembered as
/// "not in tmux".
actor GoalPaneResolver {
    static let shared = GoalPaneResolver()
    private var panes: [String: String] = [:]

    func pane(sessionID: String, pid: Int) -> String? {
        let key = "\(sessionID)|\(pid)"
        if let known = panes[key] { return known }
        guard let found = SessionReplier.paneID(forPID: pid) else { return nil }
        panes[key] = found
        return found
    }
}

/// Which sessions are on a timed `/goal` run, for the sidebar and the Home
/// dashboard. The detail pane reads one session's clock on its own cadence --
/// this is the all-sessions view of the same files, at a coarser 20s, because a
/// row only shows whether there is a run, not how long is left.
@MainActor final class GoalWatcher: ObservableObject {
    @Published private(set) var goals: [String: GoalClock] = [:]

    static let interval: TimeInterval = 20

    /// One pass. Sessions with no pid, no pane or no file are simply absent from
    /// the result -- unknown, never an entry saying "no run".
    static func read(_ sessions: [(id: String, pid: Int?)]) async -> [String: GoalClock] {
        var out: [String: GoalClock] = [:]
        for session in sessions {
            guard let pid = session.pid,
                  let pane = await GoalPaneResolver.shared.pane(sessionID: session.id, pid: pid)
            else { continue }
            let text = await Task.detached(priority: .utility) {
                GoalDeadlineFile.read(pane: pane)
            }.value
            if let clock = GoalClock.parse(text, now: Date()) { out[session.id] = clock }
        }
        return out
    }

    func track(_ sessions: [(id: String, pid: Int?)]) async {
        while !Task.isCancelled {
            let found = await Self.read(sessions)
            if found != goals { goals = found }
            try? await Task.sleep(for: .seconds(Self.interval))
        }
    }
}

/// The mark a row carries while its session is on a timed `/goal` run. Nothing
/// is drawn without a clock: a row with no sign means "no run or not known",
/// which is why the sign never has an "off" state of its own.
struct GoalFlag: View {
    let goal: GoalClock?

    var body: some View {
        if let goal {
            Image(systemName: "flag.checkered")
                .font(.ui(8))
                .foregroundStyle(goal.isLanding || goal.isOverrun ? Color.attention : Color.series1)
                .help(goal.label)
                .accessibilityLabel("on a goal run, \(goal.label)")
        }
    }
}
