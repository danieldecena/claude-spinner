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
    case merge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openPR:   return "Open PR"
        case .push:     return "Push"
        case .createPR: return "Create PR"
        case .pull:     return "Pull"
        case .merge:    return "Merge"
        }
    }

    /// Whether clicking it needs a yes first.
    ///
    /// Push and Create PR are outward-facing: once they land, other people can
    /// see them and neither is undone by clicking again. Pull writes to the
    /// working tree. Open PR only opens a browser tab. Merge is the one that
    /// cannot be taken back from here at all, so its sentence names the branch
    /// deletion rather than leaving it as a flag the reader has to know about.
    var confirmation: String? {
        switch self {
        case .openPR:   return nil
        case .push:     return "Push this branch to its remote? Anyone with access will see these commits."
        case .createPR: return "Open a pull request for this branch? It becomes visible to the repository's reviewers straight away."
        case .pull:     return "Fast-forward this branch to the remote?"
        case .merge:    return "Squash-merge this pull request and delete the branch, locally and on the remote? Nothing here can undo it."
        }
    }
}

enum GitActions {
    /// Not the probe's 8s. A push of large objects on a slow link, or a merge
    /// that also fetches, checks out and deletes a branch, routinely outlives
    /// it, and terminating a merge after GitHub has already merged leaves the
    /// checkout half-transitioned under a message saying it never finished.
    static let actionTimeout: TimeInterval = 120

    /// Why an action can't run, and whether that answer is final.
    ///
    /// `settled` is the whole point. "Already in sync with the remote" is a
    /// finished answer -- there is nothing to do, and the status rows above
    /// already say so, so the button is simply not drawn. "The remote couldn't
    /// be read" is not an answer at all, and a button that vanishes for that
    /// reason tells you nothing; it stays on screen, greyed, with this sentence
    /// underneath. Absence then means something definite.
    struct Block: Equatable {
        let reason: String
        let settled: Bool

        init(_ reason: String, settled: Bool) {
            self.reason = reason
            self.settled = settled
        }
    }

    /// Why an action can't run right now, or nil when it can.
    ///
    /// Returns the sentence rather than a bool, the same contract as
    /// `SessionActions.unavailableReason`: a greyed-out button that won't say
    /// why is the thing that makes people click it twice.
    static func unavailableReason(_ action: GitAction, snapshot: GitSnapshot) -> Block? {
        // Everything GitHub knows arrives through gh. Answering this first
        // means a missing binary is never dressed up as an unreachable network.
        if !snapshot.ghInstalled, action == .openPR || action == .createPR || action == .merge {
            return Block("The gh CLI isn't installed, so GitHub state can't be read. Install it with `brew install gh`.",
                         settled: false)
        }

        switch action {
        case .openPR:
            switch snapshot.pr {
            case .unknown: return Block("GitHub couldn't be reached, so it isn't known whether this branch has a PR.", settled: false)
            case .none:    return Block("This branch has no pull request yet.", settled: true)
            default:       return nil
            }

        case .push:
            if snapshot.detached { return Block("HEAD is detached; there is no branch to push.", settled: true) }
            switch snapshot.sync {
            case .unknown:     return Block("The remote couldn't be read, so there is nothing to compare against.", settled: false)
            case .noUpstream:  return nil   // the first push, which sets the upstream
            case .inSync:      return Block("Already in sync with the remote.", settled: true)
            case .remoteAhead: return Block("The remote has commits you don't have. Pull first.", settled: true)
            // Not settled: this one needs a person, and hiding the button would
            // hide the only place that says so.
            case .diverged:    return Block("This branch and its remote have both moved. Reconcile it in a terminal, deliberately.", settled: false)
            case .ahead:       return nil
            }

        case .createPR:
            if snapshot.detached { return Block("HEAD is detached; there is no branch to open a PR from.", settled: true) }
            if snapshot.isDefaultBranch { return Block("This is the default branch, so there is nothing to merge into.", settled: true) }
            switch snapshot.pr {
            case .open(let n, _, _):  return Block("PR #\(n) is already open for this branch.", settled: true)
            case .unknown:            return Block("GitHub couldn't be reached, so an existing PR can't be ruled out.", settled: false)
            case .merged, .closed, .none: break
            }
            if case .noUpstream = snapshot.sync { return Block("Push the branch first; there is nothing on the remote to open a PR against.", settled: true) }
            return nil

        case .pull:
            // Sync answers first. Asked before it, `isDirty` tells a repo that is
            // already up to date to commit or stash -- which reads as a promise
            // that pulling would then work, when there is nothing to pull at all.
            switch snapshot.sync {
            case .diverged:    return Block("This branch and its remote have both moved; a fast-forward isn't possible.", settled: false)
            case .inSync:      return Block("Already up to date with the remote.", settled: true)
            case .ahead:       return Block("Nothing to pull; this branch is ahead of the remote.", settled: true)
            case .noUpstream:  return Block("No upstream is configured for this branch.", settled: true)
            case .unknown:     return Block("The remote couldn't be read, so it isn't known whether there is anything to pull.", settled: false)
            case .remoteAhead:
                // The one rule this feature inherited from `start-up`: a dirty
                // repo is flagged and stopped at, never reconciled behind your
                // back. Tracked changes only -- `isDirty` excludes untracked
                // files, which cannot conflict with a fast-forward.
                if snapshot.isDirty { return Block("There are uncommitted changes. Commit or stash them first.", settled: true) }
                return nil
            }

        case .merge:
            return mergeBlock(snapshot)
        }
    }

    /// Merge is gated on what GitHub actually reports, field by field.
    ///
    /// Each check is asked separately because each fails separately, and an
    /// enabled button that then fails is the failure this whole section exists
    /// to avoid. Anything GitHub hasn't worked out yet is `settled: false`: not
    /// mergeable, but not a finished answer either.
    private static func mergeBlock(_ snapshot: GitSnapshot) -> Block? {
        let n: Int
        switch snapshot.pr {
        case .unknown:          return Block("GitHub couldn't be reached, so this PR's mergeability isn't known.", settled: false)
        case .none:             return Block("This branch has no pull request to merge.", settled: true)
        case .merged(let x, _): return Block("PR #\(x) is already merged.", settled: true)
        case .closed(let x, _): return Block("PR #\(x) is closed.", settled: true)
        case .open(let x, _, let draft):
            if draft { return Block("PR #\(x) is a draft. Mark it ready for review first.", settled: true) }
            n = x
        }

        // Checked here and not left to gh: `--delete-branch` switches this
        // checkout off the branch only after GitHub has merged, so tracked
        // changes fail that switch with the merge already done.
        if snapshot.isDirty {
            return Block("There are uncommitted changes, and merging switches this checkout off the branch. Commit or stash them first.",
                         settled: true)
        }

        switch snapshot.merge.mergeable {
        case "MERGEABLE":   break
        case "CONFLICTING": return Block("PR #\(n) conflicts with its base branch.", settled: true)
        default:            return Block("GitHub hasn't worked out yet whether PR #\(n) can merge.", settled: false)
        }

        // Asked before the state below, which reports a review-blocked PR as the
        // much vaguer BLOCKED. The specific sentence is the useful one.
        switch snapshot.merge.review {
        case "CHANGES_REQUESTED": return Block("Changes have been requested on PR #\(n).", settled: true)
        case "REVIEW_REQUIRED":   return Block("PR #\(n) needs an approving review first.", settled: true)
        default: break
        }

        switch snapshot.merge.state {
        case "CLEAN", "HAS_HOOKS": return nil
        case "UNSTABLE": return Block("Checks on PR #\(n) haven't passed.", settled: true)
        case "BEHIND":   return Block("PR #\(n) is behind its base branch. Update it first.", settled: true)
        case "BLOCKED":  return Block("PR #\(n) is blocked by a branch protection rule.", settled: true)
        case "DIRTY":    return Block("PR #\(n) conflicts with its base branch.", settled: true)
        case "DRAFT":    return Block("PR #\(n) is a draft. Mark it ready for review first.", settled: true)
        default:         return Block("GitHub hasn't reported a merge state for PR #\(n) yet.", settled: false)
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
            return (GitProbe.ghPath ?? "", ["pr", "create", "--fill", "--web"])
        case .pull:
            // --ff-only is the whole safety story. Without it this is the button
            // that quietly rebases someone's afternoon.
            return ("/usr/bin/git", ["pull", "--ff-only"])
        case .merge:
            // The number is the PR the gate and the confirmation were about.
            // Without it gh resolves the PR from whatever branch is checked out
            // at run time, which a session may have switched in the meantime.
            guard case .open(let n, _, _) = snapshot.pr else { return nil }
            // A method has to be named. `gh pr merge` with none prompts, and a
            // subprocess with no terminal would sit there until the timeout.
            return (GitProbe.ghPath ?? "", ["pr", "merge", String(n), "--squash", "--delete-branch"])
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
                        completion: @escaping (NoticeMessage) -> Void) {
        if action == .openPR {
            guard let url = snapshot.pr.url, let link = URL(string: url) else {
                completion(.init(kind: .error, text: "That PR has no URL."))
                return
            }
            NSWorkspace.shared.open(link)
            completion(.init(kind: .info, text: "Opened \(snapshot.pr.label ?? "the PR") in your browser."))
            return
        }
        guard let cmd = command(action, snapshot: snapshot) else {
            completion(.init(kind: .info, text: "Nothing to run."))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = GitProbe.run(cmd.tool, cmd.args, in: cwd, timeout: actionTimeout)
            // The cache is invalidated by the caller, ordered ahead of its own
            // re-read. Doing it here was a second, unordered actor hop, and the
            // read could win and hand back the pre-action entry -- the "still
            // says ahead 3 after a push" symptom this was meant to prevent.
            DispatchQueue.main.async {
                guard let result else {
                    completion(.init(kind: .error, text: "\(action.title) did not report back (timed out, could not start, or its output was cut off). Check the repo."))
                    return
                }
                guard result.status == 0 else {
                    completion(.init(kind: .error, text: firstLine(result.err) ?? "\(action.title) failed (exit \(result.status))."))
                    return
                }
                completion(.init(kind: .info, text: firstLine(result.out) ?? firstLine(result.err) ?? "\(action.title) done."))
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
