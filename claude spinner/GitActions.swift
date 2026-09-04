import Foundation
import AppKit

/// Git operations offered from the window.
///
/// These run `git` and `gh` directly in the session's directory rather than
/// typing a slash command at Claude. Typing would burn the session's context to
/// do something the shell does for free, only works inside tmux, and needs the
/// session to be idle. A subprocess has none of those constraints and leaves the
/// transcript untouched.
enum GitAction: String, CaseIterable, Identifiable {
    case openPR
    case push
    case createPR
    case pull

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openPR:   return "Open PR"
        case .push:     return "Push"
        case .createPR: return "Create PR"
        case .pull:     return "Pull"
        }
    }

    /// Whether clicking it needs a yes first.
    ///
    /// Push and Create PR are outward-facing: once they land, other people can
    /// see them and neither is undone by clicking again. Pull writes to the
    /// working tree. Open PR only opens a browser tab.
    var confirmation: String? {
        switch self {
        case .openPR:   return nil
        case .push:     return "Push this branch to its remote? Anyone with access will see these commits."
        case .createPR: return "Open a pull request for this branch? It becomes visible to the repository's reviewers straight away."
        case .pull:     return "Fast-forward this branch to the remote?"
        }
    }
}

enum GitActions {
    /// Why an action can't run right now, or nil when it can.
    ///
    /// Returns the sentence rather than a bool, the same contract as
    /// `SessionActions.unavailableReason`: a greyed-out button that won't say
    /// why is the thing that makes people click it twice.
    static func unavailableReason(_ action: GitAction, snapshot: GitSnapshot) -> String? {
        switch action {
        case .openPR:
            switch snapshot.pr {
            case .unknown: return "GitHub couldn't be reached, so it isn't known whether this branch has a PR."
            case .none:    return "This branch has no pull request yet."
            default:       return nil
            }

        case .push:
            if snapshot.detached { return "HEAD is detached; there is no branch to push." }
            switch snapshot.sync {
            case .unknown:     return "The remote couldn't be read, so there is nothing to compare against."
            case .noUpstream:  return nil   // the first push, which sets the upstream
            case .inSync:      return "Already in sync with the remote."
            case .remoteAhead: return "The remote has commits you don't have. Pull first."
            case .diverged:    return "This branch and its remote have both moved. Reconcile it in a terminal, deliberately."
            case .ahead:       return nil
            }

        case .createPR:
            if snapshot.detached { return "HEAD is detached; there is no branch to open a PR from." }
            if snapshot.isDefaultBranch { return "This is the default branch, so there is nothing to merge into." }
            switch snapshot.pr {
            case .open(let n, _, _):  return "PR #\(n) is already open for this branch."
            case .unknown:            return "GitHub couldn't be reached, so an existing PR can't be ruled out."
            case .merged, .closed, .none: break
            }
            if case .noUpstream = snapshot.sync { return "Push the branch first; there is nothing on the remote to open a PR against." }
            return nil

        case .pull:
            // The one rule this feature inherited from `start-up`: a diverged or
            // dirty repo is flagged and stopped at, never reconciled behind your
            // back. Pull here fast-forwards or refuses; it never rebases or merges.
            if snapshot.isDirty { return "There are uncommitted changes. Commit or stash them first." }
            switch snapshot.sync {
            case .remoteAhead: return nil
            case .diverged:    return "This branch and its remote have both moved; a fast-forward isn't possible."
            case .inSync:      return "Already up to date with the remote."
            case .ahead:       return "Nothing to pull; this branch is ahead of the remote."
            case .noUpstream:  return "No upstream is configured for this branch."
            case .unknown:     return "The remote couldn't be read, so it isn't known whether there is anything to pull."
            }
        }
    }

    /// The command an action runs, or nil when it doesn't run one (Open PR just
    /// opens a URL). Exposed so tests can assert the argument list rather than
    /// having to execute a push to find out what it would have done.
    static func command(_ action: GitAction, snapshot: GitSnapshot) -> (tool: String, args: [String])? {
        switch action {
        case .openPR:
            return nil
        case .push:
            if case .noUpstream = snapshot.sync, let branch = snapshot.branch {
                return ("/usr/bin/git", ["push", "--set-upstream", "origin", branch])
            }
            return ("/usr/bin/git", ["push"])
        case .createPR:
            return ("/opt/homebrew/bin/gh", ["pr", "create", "--fill", "--web"])
        case .pull:
            // --ff-only is the whole safety story. Without it this is the button
            // that quietly rebases someone's afternoon.
            return ("/usr/bin/git", ["pull", "--ff-only"])
        }
    }

    /// Run an action. Returns what to tell the user, always something.
    ///
    /// Reports what the command actually said rather than its exit code alone:
    /// a push that is refused for a stale ref exits nonzero with the reason on
    /// stderr, and "Couldn't push." would throw away the only useful part.
    static func perform(_ action: GitAction,
                        snapshot: GitSnapshot,
                        cwd: String,
                        completion: @escaping (String) -> Void) {
        if action == .openPR {
            guard let url = snapshot.pr.url, let link = URL(string: url) else {
                completion("That PR has no URL.")
                return
            }
            NSWorkspace.shared.open(link)
            completion("Opened \(snapshot.pr.label ?? "the PR") in your browser.")
            return
        }
        guard let cmd = command(action, snapshot: snapshot) else {
            completion("Nothing to run.")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = GitProbe.run(cmd.tool, cmd.args, in: cwd)
            Task { await GitProbe.shared.invalidate(cwd) }
            DispatchQueue.main.async {
                guard let result else {
                    completion("\(action.title) didn't finish within the timeout.")
                    return
                }
                guard result.status == 0 else {
                    completion(firstLine(result.err) ?? "\(action.title) failed (exit \(result.status)).")
                    return
                }
                completion(firstLine(result.out) ?? firstLine(result.err) ?? "\(action.title) done.")
            }
        }
    }

    /// git and gh put the useful sentence first and progress noise after it.
    static func firstLine(_ text: String) -> String? {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
