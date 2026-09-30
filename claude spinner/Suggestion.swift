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
        /// Lines this session added plus removed.
        var linesChanged: Int? = nil
        /// The session's own task list, from TodoWrite or TaskCreate.
        var todoTotal: Int? = nil
        var todoDone: Int? = nil
        /// Unchecked items in the project's TASKS.md, nil when it has none.
        var projectOpenTasks: Int? = nil
        /// `/wrap-up` ran in this session and nothing was edited since.
        var wrappedUp = false
    }

    /// The Skills card's pick: the one skill most worth running in this
    /// session now, whatever `next` chose for the pane as a whole. Same
    /// discipline as `next` -- facts on screen, first rule that holds wins.
    /// Nothing is picked for /recall or /checkup: nothing on screen says when
    /// those are due. /clear is picked only after a wrap-up the transcript shows.
    static func skill(_ input: Input) -> Suggestion? {
        func pick(_ command: String, _ reason: String) -> Suggestion? {
            command == "/compact" || input.installed.contains(command)
                ? .init(action: .command(command), reason: reason) : nil
        }
        let tokens = input.contextTokens ?? 0

        // Wrapped up and still saved: another wrap-up would redo the same work,
        // and every call from here re-reads a context nothing needs.
        var saved = true
        if let git = input.git {
            if case .ahead = git.sync { saved = false }
            if git.isDirty { saved = false }
        }
        if input.wrappedUp, saved,
           let s = pick("/clear", "Wrapped up and nothing changed since. Clear to start fresh.") { return s }
        if let pct = input.contextPercent, pct >= 85,
           let s = pick("/wrap-up", "Context is at \(pct)%. Wrap up, then /clear.") { return s }
        // Absolute tokens as well as percent: every call re-reads the whole
        // context, so cost follows its size, and a 1M window puts 60% at 600k.
        // Only at the prompt: mid-turn the session is doing the work this would
        // have it wrap up, and the chip would type into a running turn.
        if tokens >= 150_000, input.atPrompt,
           let s = pick("/wrap-up", "\(tokens / 1000)k tokens re-read on every call. Wrap up, then /clear.") {
            return s
        }
        if let pct = input.contextPercent, pct >= 60,
           let s = pick("/compact", "Context is at \(pct)% of the window.") { return s }
        if tokens >= 100_000, input.atPrompt,
           let s = pick("/compact", "\(tokens / 1000)k tokens in context and the session is idle.") { return s }
        if let idle = input.idleFor, idle >= 30 * 60, tokens >= 50_000,
           let s = pick("/wrap-up", "Idle for \(Int(idle / 60))m with a loaded context.") { return s }
        if input.contextTokens != nil, tokens < 20_000,
           let s = pick("/start-up", "A fresh session: survey the repo and start the top task.") { return s }
        if let total = input.todoTotal, total > 0, (input.todoDone ?? 0) >= total, input.git?.isDirty == true,
           let s = pick("/wrap-up", "Every task in this session is done and the work isn't committed.") {
            return s
        }
        // The uncommitted diff, not the session's lifetime count: a session that
        // committed 600 lines and has 3 left dirty has nothing to simplify.
        if let lines = input.git?.dirtyLines, lines >= 100, input.git?.isDirty == true,
           let s = pick("/simplify", "\(lines) lines changed and not committed yet: clean up first.") {
            return s
        }
        if let total = input.todoTotal, total > 0, (input.todoDone ?? 0) < total, input.atPrompt {
            let open = total - (input.todoDone ?? 0)
            if let s = pick("/goal", "\(open) todo\(open == 1 ? "" : "s") still open and the session is idle.") {
                return s
            }
        }
        if let open = input.projectOpenTasks, open > 0, input.atPrompt, (input.todoTotal ?? 0) == 0,
           let s = pick("/goal", "\(open) open task\(open == 1 ? "" : "s") in TASKS.md and the session is idle.") {
            return s
        }
        // Work was done and it is all committed and pushed: the session has
        // likely finished its job.
        if let idle = input.idleFor, idle >= 10 * 60, (input.linesChanged ?? 0) > 0,
           input.git?.isDirty == false, input.git?.sync == .inSync,
           let s = pick("/wrap-up", "Idle \(Int(idle / 60))m with its work committed and pushed.") {
            return s
        }
        return nil
    }

    /// The folder whose TASKS.md belongs to a session started in `cwd`: `cwd`
    /// itself, or the nearest parent that has one. Stops at a repo root, so a
    /// session in a repo with no TASKS.md does not pick up a parent's, and never
    /// looks above the home folder.
    static func tasksRoot(startingAt cwd: String) -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var dir = URL(fileURLWithPath: cwd)
        for _ in 0..<8 where dir.path != "/" && dir.path != home {
            if fm.fileExists(atPath: dir.appendingPathComponent("TASKS.md").path) { return dir.path }
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return nil }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    /// Unchecked `- [ ]` items above `## Completed`, or nil when there are none.
    static func openTasks(inTasksFile text: String) -> Int? {
        let open = tasks(inTasksFile: text).open.count
        return open > 0 ? open : nil
    }

    /// The titles of the open items above `## Completed`, in file order, and
    /// how many are checked anywhere in the file.
    static func tasks(inTasksFile text: String) -> (open: [String], done: Int) {
        var open: [String] = []
        var done = 0
        var completed = false
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("## Completed") { completed = true }
            if t.hasPrefix("- [x]") || t.hasPrefix("- [X]") { done += 1 }
            if !completed, t.hasPrefix("- [ ]") {
                open.append(t.dropFirst(5).trimmingCharacters(in: .whitespaces))
            }
        }
        return (open, done)
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
           StatFormat.aheadOfPace(pct: pct, elapsed: elapsed, margin: 0.15) {
            return .init(action: .warning,
                         reason: "5h usage is at \(pct)% with \(Int((elapsed * 100).rounded()))% of the window gone.")
        }
        return nil
    }
}
