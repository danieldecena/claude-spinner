import Foundation

/// Where a branch stands against its remote.
///
/// Deliberately not an ahead/behind pair. `@{upstream}` is only as fresh as the
/// last fetch, so a pair of exact-looking numbers computed from it is a stale
/// reading wearing a precise face -- the failure `~/CLAUDE.md` calls out by
/// name. Every case here is derived from a `ls-remote` SHA read just now, and
/// `unknown` exists so a failed probe can say so instead of rendering as zero.
enum SyncState: Equatable {
    /// The remote was not reachable, or the probe hasn't run yet.
    case unknown
    /// No upstream is configured -- nothing to be ahead or behind of.
    case noUpstream
    case inSync
    /// The remote head is an ancestor of HEAD: local commits aren't pushed.
    case ahead(Int)
    /// The remote head isn't in local history at all. How far behind is
    /// genuinely unknown without fetching those objects, so it isn't guessed.
    case remoteAhead
    /// Both sides moved. Nothing here should offer to reconcile it.
    case diverged

    var label: String {
        switch self {
        case .unknown:     return "unknown"
        case .noUpstream:  return "no upstream"
        case .inSync:      return "in sync"
        case .ahead(let n): return "ahead \(n)"
        case .remoteAhead: return "remote is ahead"
        case .diverged:    return "diverged"
        }
    }
}

/// Whether this branch has a pull request.
///
/// Three cases, not two. `gh pr view` exits non-zero both when there is no PR
/// and when it couldn't reach GitHub, and reading the second as the first would
/// invent an absence -- the "not found is not the same as unreachable" rule.
/// The two are told apart by what gh actually said on stderr.
enum PRState: Equatable {
    case unknown
    case none
    case open(number: Int, url: String, draft: Bool)
    case merged(number: Int, url: String)
    case closed(number: Int, url: String)

    var number: Int? {
        switch self {
        case .open(let n, _, _), .merged(let n, _), .closed(let n, _): return n
        case .unknown, .none: return nil
        }
    }

    var url: String? {
        switch self {
        case .open(_, let u, _), .merged(_, let u), .closed(_, let u): return u
        case .unknown, .none: return nil
        }
    }

    var label: String? {
        switch self {
        case .unknown: return nil
        case .none: return "none"
        case .open(let n, _, let draft): return draft ? "#\(n) draft" : "#\(n) open"
        case .merged(let n, _): return "#\(n) merged"
        case .closed(let n, _): return "#\(n) closed"
        }
    }
}

/// One directory's git state. `nil` for a cwd that isn't a repository at all,
/// which is why the detail pane can drop the whole section rather than draw a
/// column of dashes.
struct GitSnapshot: Equatable {
    var branch: String?
    var detached: Bool = false
    /// Tracked modifications only. Untracked files are excluded on purpose:
    /// `~/` carries ~22 permanently-untracked paths, so counting them makes
    /// that repo look alarming forever (`~/CLAUDE.md`).
    var dirty: Int = 0
    var staged: Int = 0
    var untracked: Int = 0
    var upstream: String?
    var sync: SyncState = .unknown
    var pr: PRState = .unknown
    var isDefaultBranch: Bool = false
    var readAt: Date = .distantPast

    var branchLabel: String {
        if detached { return "detached" }
        return branch ?? "unknown"
    }

    /// Uncommitted tracked work. The counter-signal to clearing a session:
    /// the reasoning behind a half-finished edit lives only in that context.
    var isDirty: Bool { dirty > 0 || staged > 0 }
}

/// Pure parsing, split out from the subprocess work so every branch below is
/// reachable in a unit test without a repository on disk.
enum GitParse {
    /// `git status --porcelain=v1 --untracked-files=all`.
    ///
    /// Column 1 is the index status and column 2 the worktree status, so a file
    /// both staged and edited since counts once in each -- that is two facts
    /// about one file, not double counting.
    static func porcelain(_ out: String) -> (dirty: Int, staged: Int, untracked: Int) {
        var dirty = 0, staged = 0, untracked = 0
        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.count >= 2 else { continue }
            let chars = Array(line)
            let index = chars[0], tree = chars[1]
            if index == "?" && tree == "?" { untracked += 1; continue }
            if index != " " && index != "?" { staged += 1 }
            if tree != " " && tree != "?" { dirty += 1 }
        }
        return (dirty, staged, untracked)
    }

    /// `git ls-remote <remote> <ref>` -> the SHA for an exact ref match.
    ///
    /// Matched exactly rather than by suffix: a branch named `main` and one
    /// named `feature/main` both end in `main`, and a suffix match would hand
    /// back whichever line came first.
    static func lsRemote(_ out: String, branch: String) -> String? {
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let ref = parts[1].trimmingCharacters(in: .whitespaces)
            if ref == "refs/heads/\(branch)" || ref == branch {
                return String(parts[0]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Decide sync from two SHAs plus two cheap local facts.
    ///
    /// `haveRemoteObject` is `git cat-file -e <sha>`: false means the remote
    /// commit isn't in this clone at all, which is itself the answer -- the
    /// remote moved and we haven't fetched. Only when we *do* have the object
    /// can ancestry decide between ahead and diverged.
    static func sync(local: String?,
                     remote: String?,
                     hasUpstream: Bool,
                     haveRemoteObject: Bool,
                     remoteIsAncestor: Bool,
                     aheadCount: Int) -> SyncState {
        guard hasUpstream else { return .noUpstream }
        guard let local, let remote else { return .unknown }
        if local == remote { return .inSync }
        if !haveRemoteObject { return .remoteAhead }
        if remoteIsAncestor { return .ahead(aheadCount) }
        return .diverged
    }

    /// `gh pr view --json number,state,isDraft,url`.
    static func pr(json: Data) -> PRState? {
        guard let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let number = obj["number"] as? Int,
              let url = obj["url"] as? String,
              let state = obj["state"] as? String
        else { return nil }
        switch state.uppercased() {
        case "MERGED": return .merged(number: number, url: url)
        case "CLOSED": return .closed(number: number, url: url)
        default:       return .open(number: number, url: url,
                                    draft: obj["isDraft"] as? Bool ?? false)
        }
    }

    /// Tell "this branch has no PR" from "GitHub couldn't be reached".
    ///
    /// Both exit non-zero. gh names the first case in its own words, so that
    /// string is the only thing allowed to produce `.none`; everything else --
    /// no network, not a GitHub remote, auth expired -- stays `.unknown`.
    static func prFailure(stderr: String) -> PRState {
        let s = stderr.lowercased()
        if s.contains("no pull requests found") || s.contains("no open pull requests") {
            return .none
        }
        return .unknown
    }
}
