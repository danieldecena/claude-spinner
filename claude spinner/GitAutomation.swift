import Foundation
import Combine

/// The four git automations the Git commands card can switch, each backed by
/// the mechanism that already exists for it rather than a new one of the
/// app's own where one was there:
///
/// - auto-merge: GitHub's own, on the branch's open PR (`gh pr merge --auto`)
/// - auto-push on main: the `.autocommit-main-ok` marker the push and commit
///   hooks already check before touching main
/// - auto-commit: the `auto-commit.sh` Stop hook in `~/.claude/settings.json`,
///   which is global -- every project, not this repo
/// - auto-PR: the one with no existing mechanism, so the app does it
///   (`AutoPRWatcher`), opted into per repository
enum GitAutomation {
    static let mainMarker = ".autocommit-main-ok"
    static let autoCommitCommand = "bash ~/bin/auto-commit.sh"
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    // MARK: auto-push on main

    static func mainPushEnabled(toplevel: String) -> Bool {
        FileManager.default.fileExists(atPath: (toplevel as NSString).appendingPathComponent(mainMarker))
    }

    static func setMainPush(_ on: Bool, toplevel: String) throws {
        let path = (toplevel as NSString).appendingPathComponent(mainMarker)
        if on {
            try Data().write(to: URL(fileURLWithPath: path))
        } else if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: auto-commit hook

    static func autoCommitEnabled(settings text: String) -> Bool {
        text.contains("auto-commit.sh")
    }

    /// The settings text with the auto-commit hook inserted just before the
    /// auto-push entry, in that entry's own indentation. A text edit, not a
    /// JSON rewrite: re-serializing would reorder and restyle a file that two
    /// repositories track. nil when it's already there or the anchor is missing.
    static func enablingAutoCommit(in text: String) -> String? {
        guard !autoCommitEnabled(settings: text) else { return nil }
        let pattern = #"(?m)^([ \t]*)\{\s*"type":\s*"command",\s*"command":\s*"bash ~/\.claude/bin/auto-push\.sh"\s*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(match.range, in: text),
              let indentRange = Range(match.range(at: 1), in: text) else { return nil }
        let indent = String(text[indentRange])
        let block = "\(indent){\n\(indent)  \"type\": \"command\",\n\(indent)  \"command\": \"\(autoCommitCommand)\"\n\(indent)},\n"
        var out = text
        out.insert(contentsOf: block, at: whole.lowerBound)
        return out
    }

    /// The settings text with every auto-commit hook entry removed, or nil when
    /// there is none. Takes the entry's trailing comma, or the comma before it
    /// when it was the last in its array.
    static func disablingAutoCommit(in text: String) -> String? {
        let entry = #"\{\s*"type":\s*"command",\s*"command":\s*"[^"]*auto-commit\.sh[^"]*"\s*\}"#
        for pattern in [#"(?m)^[ \t]*"# + entry + #",[ \t]*\n"#, #",\s*"# + entry] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range, in: text) else { continue }
            var out = text
            out.removeSubrange(range)
            return out
        }
        return nil
    }

    enum SettingsError: LocalizedError {
        case unreadable, noChange, invalidResult
        var errorDescription: String? {
            switch self {
            case .unreadable: return "~/.claude/settings.json couldn't be read."
            case .noChange: return "Couldn't find where the hook goes (no auto-push entry in the Stop hooks)."
            case .invalidResult: return "The edit would have left settings.json invalid, so nothing was written."
            }
        }
    }

    /// Edit settings.json, backing it up first and refusing to write anything
    /// that no longer parses.
    static func setAutoCommit(_ on: Bool) throws {
        let url = settingsURL
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            throw SettingsError.unreadable
        }
        guard let edited = on ? enablingAutoCommit(in: text) : disablingAutoCommit(in: text) else {
            if autoCommitEnabled(settings: text) == on { return }
            throw SettingsError.noChange
        }
        guard (try? JSONSerialization.jsonObject(with: Data(edited.utf8))) is [String: Any] else {
            throw SettingsError.invalidResult
        }
        let stamp = Int(Date().timeIntervalSince1970)
        try data.write(to: url.deletingLastPathComponent().appendingPathComponent("settings.json.backup-\(stamp)"))
        try Data(edited.utf8).write(to: url, options: .atomic)
    }

    // MARK: auto-PR

    private static func autoPRKey(_ toplevel: String) -> String { "autoPR:" + toplevel }

    static func autoPREnabled(toplevel: String) -> Bool {
        UserDefaults.standard.bool(forKey: autoPRKey(toplevel))
    }

    static func setAutoPR(_ on: Bool, toplevel: String) {
        UserDefaults.standard.set(on, forKey: autoPRKey(toplevel))
    }

    /// A pushed feature branch with no PR, where gh can open one. Every other
    /// state is either not a branch you'd PR, not on the remote yet, or
    /// already has a PR -- and `unknown` PR state is never read as "none".
    static func shouldCreatePR(_ snap: GitSnapshot) -> Bool {
        snap.ghInstalled && !snap.detached && snap.branch != nil && !snap.isDefaultBranch
            && snap.sync == .inSync && snap.pr == .none
    }

    // MARK: auto-fix

    /// Claude Code's own PR auto-fix: a cloud session watches CI and review
    /// comments and pushes fixes. A button, not a switch: it's turned off at
    /// claude.ai/code and its state can't be read from here, so a switch would
    /// show a position nobody can vouch for.
    static let autoFixCommand = "/autofix-pr"
    static let autoFixConfirmation =
        "Turn on auto-fix for this PR? /autofix-pr starts a Claude Code cloud session that watches CI "
        + "and review comments and pushes fixes. It needs the Claude GitHub App on the repo, replies to "
        + "review threads under your GitHub account, and is turned off at claude.ai/code."

    /// Why the auto-merge switch can't be used, or nil. Shown under the switch,
    /// not only as a tooltip: a disabled mini switch looks like one that's off.
    static func autoMergeUnavailableReason(_ snap: GitSnapshot) -> String? {
        guard snap.ghInstalled else { return "The gh CLI isn't installed." }
        if snap.autoMergeAllowed == false {
            return "GitHub has auto-merge off for this repo (Settings -> General -> Allow auto-merge)."
        }
        guard case .open(_, _, let draft) = snap.pr else { return "There is no open PR on this branch." }
        if draft { return "The PR is a draft." }
        // Enabling can merge at once when checks already pass, and --delete-branch
        // then switches this checkout: the same guard as Merge.
        if snap.isDirty, snap.autoMerge != true { return "There are uncommitted changes. Commit or stash them first." }
        return nil
    }

    static func autoFixUnavailableReason(_ snap: GitSnapshot) -> String? {
        guard snap.ghInstalled else { return "The gh CLI isn't installed." }
        guard case .open = snap.pr else { return "There is no open PR on this branch." }
        return nil
    }

    // MARK: auto-merge

    static func autoMergeCommand(enable: Bool, snapshot: GitSnapshot) -> (tool: String, args: [String])? {
        guard case .open(let n, _, _) = snapshot.pr else { return nil }
        return (GitProbe.ghPath ?? "", enable
            ? ["pr", "merge", String(n), "--auto", "--squash", "--delete-branch"]
            : ["pr", "merge", String(n), "--disable-auto"])
    }
}

/// Opens PRs for repositories that opted in, on its own clock, for every live
/// session's directory -- not only the one the window happens to show.
///
/// Once per branch per launch: a failed create is reported and not retried in
/// a loop, and a branch that got its PR stops matching `shouldCreatePR`.
@MainActor
final class AutoPRWatcher: ObservableObject {
    static let shared = AutoPRWatcher()

    /// The last thing it did per repository, for the card to say.
    @Published private(set) var lastResult: [String: NoticeMessage] = [:]
    private var attempted: Set<String> = []
    private var timer: Timer?

    func start(cwds: @escaping @MainActor () -> [String]) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick(cwds()) }
        }
    }

    func tick(_ cwds: [String]) async {
        for cwd in Set(cwds) where !cwd.isEmpty {
            guard let snap = await GitProbe.shared.snapshot(for: cwd),
                  let top = snap.toplevel, let branch = snap.branch,
                  GitAutomation.autoPREnabled(toplevel: top),
                  GitAutomation.shouldCreatePR(snap),
                  let gh = GitProbe.ghPath else { continue }
            let key = top + "#" + branch
            guard !attempted.contains(key) else { continue }
            attempted.insert(key)
            let result = await Task.detached(priority: .utility) {
                GitProbe.run(gh, ["pr", "create", "--fill"], in: cwd, timeout: GitActions.actionTimeout)
            }.value
            if let result, result.status == 0 {
                lastResult[top] = .init(kind: .info,
                                        text: "Opened a PR for \(branch): \(GitActions.firstLine(result.out) ?? "done")")
            } else {
                lastResult[top] = .init(kind: .error,
                                        text: "Auto-PR for \(branch) failed: \(result.flatMap { GitActions.firstLine($0.err) } ?? "gh didn't report back")")
            }
            await GitProbe.shared.invalidate(cwd)
        }
    }
}
