import Foundation

/// The one thing most worth doing next in a session, and why.
///
/// Rules, not a model: each reads facts the pane already shows, so every
/// suggestion can be traced to a row on screen, costs nothing, and can't
/// invent a reason. Checked in priority order; the first that holds wins.
struct Suggestion: Equatable {
    enum Action: Equatable {
        case git(GitAction)
        /// A slash command typed into the session.
        case command(String)
        /// Something to know, with nothing safe to click.
        case warning
    }

    let action: Action
    let reason: String

    /// Everything the rules read, gathered so they stay a pure function.
    struct Input {
        var git: GitSnapshot?
        var contextPercent: Int?
        var contextTokens: Int?
        var atPrompt: Bool
        var idleFor: TimeInterval?
        var fiveHourPct: Int?
        var fiveHourElapsed: Double?
        /// Slash commands that exist (skills and commands found on disk, plus
        /// built-ins), so a suggestion never names one that isn't there.
        var installed: Set<String>
    }

    static func next(_ input: Input) -> Suggestion? {
        func can(_ action: GitAction, _ snap: GitSnapshot) -> Bool {
            GitActions.unavailableReason(action, snapshot: snap) == nil
        }
        func has(_ command: String) -> Bool {
            command == "/compact" || input.installed.contains(command)
        }

        if let snap = input.git {
            if snap.ci.tone == .bad {
                return .init(action: .git(.openCI), reason: "CI failed on \(snap.branchLabel): \(snap.ci.label)")
            }
            if snap.sync == .diverged {
                return .init(action: .warning,
                             reason: "This branch and its remote have both moved. Reconcile it in a terminal.")
            }
            if snap.sync == .remoteAhead, can(.pull, snap) {
                return .init(action: .git(.pull), reason: "The remote has commits this checkout doesn't.")
            }
        }

        if let pct = input.contextPercent {
            if pct >= 85, has("/wrap-up") {
                return .init(action: .command("/wrap-up"),
                             reason: "Context is at \(pct)% of the window. Wrap up, then /clear.")
            }
            if pct >= 60 {
                return .init(action: .command("/compact"), reason: "Context is at \(pct)% of the window.")
            }
        }

        if let snap = input.git {
            if snap.isDirty, input.atPrompt, has("/git-push") {
                let n = snap.dirty + snap.staged
                return .init(action: .command("/git-push"),
                             reason: "\(n) uncommitted change\(n == 1 ? "" : "s") and the session is idle.")
            }
            if case .ahead(let n) = snap.sync, can(.push, snap) {
                return .init(action: .git(.push), reason: "\(n) commit\(n == 1 ? "" : "s") not on the remote yet.")
            }
            if snap.pr == .none, snap.sync == .inSync, can(.createPR, snap) {
                return .init(action: .git(.createPR), reason: "\(snap.branchLabel) is pushed and has no pull request.")
            }
            if case .open(let n, _, _) = snap.pr, can(.merge, snap) {
                return .init(action: .git(.merge), reason: "PR #\(n) is mergeable, green and approved.")
            }
        }

        if let idle = input.idleFor, idle >= 30 * 60, (input.contextTokens ?? 0) >= 50_000, has("/wrap-up") {
            return .init(action: .command("/wrap-up"),
                         reason: "Idle for \(Int(idle / 60))m with a loaded context.")
        }
        if let tokens = input.contextTokens, tokens < 20_000, input.atPrompt, has("/start-up") {
            return .init(action: .command("/start-up"), reason: "A fresh session.")
        }
        if let pct = input.fiveHourPct, let elapsed = input.fiveHourElapsed,
           Double(pct) / 100 > elapsed + 0.15 {
            return .init(action: .warning,
                         reason: "5h usage is at \(pct)% with \(Int((elapsed * 100).rounded()))% of the window gone.")
        }
        return nil
    }
}
