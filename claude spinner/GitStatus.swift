import Foundation

/// Where a branch stands against its remote.
///
/// Deliberately not an ahead/behind pair. `@{upstream}` is only as fresh as the
/// last fetch, so a pair of exact-looking numbers computed from it is a stale
/// reading wearing a precise face -- the failure `~/CLAUDE.md` calls out by
/// name. Every case here is derived from a `ls-remote` SHA read just now, and
/// `unknown` exists so a failed probe can say so instead of rendering as zero.
nonisolated enum SyncState: Equatable {
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

/// How a git fact should read at a glance: settled, waiting on you, worth a
/// look, broken, or not known. The card tints each row's icon by it.
nonisolated enum GitTone: Equatable { case good, pending, warn, bad, neutral }

extension SyncState {
    var tone: GitTone {
        switch self {
        case .inSync: return .good
        case .ahead: return .pending
        case .remoteAhead: return .warn
        case .diverged: return .bad
        case .noUpstream, .unknown: return .neutral
        }
    }

    var symbol: String {
        switch self {
        case .inSync: return "checkmark.circle"
        case .ahead: return "arrow.up.circle"
        case .remoteAhead: return "arrow.down.circle"
        case .diverged: return "arrow.triangle.branch"
        case .noUpstream: return "icloud.slash"
        case .unknown: return "questionmark.circle"
        }
    }
}

extension PRState {
    /// No PR is neutral, not bad: most branches never need one.
    var tone: GitTone {
        switch self {
        case .open(_, _, let draft): return draft ? .neutral : .good
        case .merged: return .good
        case .closed, .none, .unknown: return .neutral
        }
    }
}

extension MergeReadiness {
    /// The worst thing GitHub said, since any one of them can stop a merge.
    var tone: GitTone {
        if state == "DIRTY" || mergeable == "CONFLICTING" || review == "CHANGES_REQUESTED" { return .bad }
        if ["UNSTABLE", "BEHIND", "BLOCKED"].contains(state) || review == "REVIEW_REQUIRED" { return .warn }
        if state == "CLEAN" || state == "HAS_HOOKS" { return .good }
        return .neutral
    }
}

extension GitSnapshot {
    /// Uncommitted work is pending; untracked files alone are neutral, for the
    /// same reason `dirty` excludes them.
    var changesTone: GitTone {
        if isDirty { return .pending }
        return untracked > 0 ? .neutral : .good
    }
}

/// The latest GitHub Actions run on this branch.
///
/// Its own row rather than folded into `checks`: that one only exists beside a
/// PR, so a default branch -- where CI matters most -- never showed any.
/// `unknown` (gh failed or isn't there) is kept apart from `none` (gh answered
/// with no runs), the same not-found-is-not-unreachable split as `PRState`.
nonisolated enum CIState: Equatable {
    case unknown
    case none
    case running(workflow: String, url: String)
    case finished(workflow: String, conclusion: String, url: String)

    var url: String? {
        switch self {
        case .running(_, let u), .finished(_, _, let u): return u
        case .unknown, .none: return nil
        }
    }

    var label: String {
        switch self {
        case .unknown: return "unknown"
        case .none: return "no runs"
        case .running(let w, _): return "\(w) running"
        case .finished(let w, let c, _):
            switch c {
            case "success": return "\(w) passed"
            case "failure": return "\(w) failed"
            default: return "\(w) \(c.replacingOccurrences(of: "_", with: " "))"
            }
        }
    }

    var tone: GitTone {
        switch self {
        case .unknown, .none: return .neutral
        case .running: return .pending
        case .finished(_, let c, _):
            switch c {
            case "success": return .good
            case "failure", "timed_out", "startup_failure": return .bad
            case "action_required": return .warn
            default: return .neutral
            }
        }
    }
}

/// Whether this branch has a pull request.
///
/// Three cases, not two. `gh pr view` exits non-zero both when there is no PR
/// and when it couldn't reach GitHub, and reading the second as the first would
/// invent an absence -- the "not found is not the same as unreachable" rule.
/// The two are told apart by what gh actually said on stderr.
nonisolated enum PRState: Equatable {
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
        // A word, not nil. `StatSection` drops nil rows, so returning nothing
        // here made "GitHub couldn't be reached" render exactly like "this
        // branch has no PR" -- the row simply wasn't there.
        case .unknown: return "unknown"
        case .none: return "none"
        case .open(let n, _, let draft): return draft ? "#\(n) draft" : "#\(n) open"
        case .merged(let n, _): return "#\(n) merged"
        case .closed(let n, _): return "#\(n) closed"
        }
    }
}

/// What GitHub says about merging the branch's PR, verbatim.
///
/// Three separate fields because they fail separately: a PR can be mergeable
/// with red checks, clean with no approval, or approved but behind its base.
/// Stored as gh's own strings rather than a digested bool -- the digest is what
/// makes a Merge button that is enabled and then fails.
nonisolated struct MergeReadiness: Equatable {
    /// `MERGEABLE` / `CONFLICTING` / `UNKNOWN`. nil when gh wasn't read.
    var mergeable: String?
    /// `CLEAN` / `BLOCKED` / `BEHIND` / `DIRTY` / `DRAFT` / `UNSTABLE` /
    /// `HAS_HOOKS` / `UNKNOWN`. Only populated for a user with push access.
    var state: String?
    /// `APPROVED` / `CHANGES_REQUESTED` / `REVIEW_REQUIRED`, or empty when the
    /// repository requires no review at all. Empty is not the same as nil.
    var review: String?

    /// The `checks` row. nil only when nothing was read at all.
    var label: String? {
        var parts: [String] = []
        switch state {
        case "CLEAN", "HAS_HOOKS": parts.append("checks passing")
        // UNSTABLE is any non-passing commit status, pending included -- gh can
        // report it for a branch with no checks at all. "failing" would be a
        // claim GitHub never made.
        case "UNSTABLE":           parts.append("checks not passing")
        case "BEHIND":             parts.append("behind the base branch")
        case "BLOCKED":            parts.append("blocked")
        case "DRAFT":              parts.append("draft")
        case "DIRTY":              parts.append("conflicts")
        default: break
        }
        if mergeable == "CONFLICTING" && !parts.contains("conflicts") {
            parts.append("conflicts")
        }
        switch review {
        case "APPROVED":          parts.append("approved")
        case "CHANGES_REQUESTED": parts.append("changes requested")
        case "REVIEW_REQUIRED":   parts.append("no review yet")
        default: break
        }
        if parts.isEmpty { return mergeable == nil && state == nil ? nil : "unknown" }
        return parts.joined(separator: ", ")
    }
}

/// One directory's git state. `nil` for a cwd that isn't a repository at all,
/// which is why the detail pane can drop the whole section rather than draw a
/// column of dashes.
nonisolated struct GitSnapshot: Equatable {
    var branch: String?
    var detached: Bool = false
    /// Tracked modifications only. Untracked files are excluded on purpose:
    /// `~/` carries ~22 permanently-untracked paths, so counting them makes
    /// that repo look alarming forever (`~/CLAUDE.md`).
    var dirty: Int = 0
    var staged: Int = 0
    /// Lines added plus removed in the uncommitted diff against HEAD, tracked
    /// files only (untracked files have no diff to count).
    var dirtyLines: Int = 0
    var untracked: Int = 0
    var upstream: String?
    /// Where the upstream's remote points, from `git remote get-url`.
    var remoteURL: String?
    /// The commit HEAD points at. Carried so the prober can notice a commit and
    /// re-read the remote, instead of trusting a 90-second clock to have been
    /// right about a repository that moved two seconds ago.
    var headSHA: String?
    var sync: SyncState = .unknown
    var pr: PRState = .unknown
    var merge = MergeReadiness()
    var ci: CIState = .unknown
    /// Whether GitHub auto-merge is on for the open PR. nil when there is no
    /// PR that was read, which is not the same as "off".
    var autoMerge: Bool?
    /// The repository's GitHub "Allow auto-merge" setting; nil when unread.
    var autoMergeAllowed: Bool?
    /// Whether the GitHub repository is private; nil when unread or not on GitHub.
    var isPrivate: Bool?
    /// The repository root, which the per-repo automations are keyed on so a
    /// session in a subdirectory shares its repo's settings.
    var toplevel: String?
    /// Whether the `gh` binary was found. False makes every GitHub-derived
    /// answer unavailable for a reason that names gh, rather than for one that
    /// blames the network for a tool that was never installed.
    var ghInstalled: Bool = true
    var isDefaultBranch: Bool = false
    /// When the local half was read.
    var readAt: Date = .distantPast
    /// When the network half was read. Its own stamp because it runs on its own
    /// clock, and a single age would misreport whichever half it wasn't.
    var remoteReadAt: Date = .distantPast

    var branchLabel: String {
        if detached { return "detached" }
        return branch ?? "unknown"
    }

    /// Uncommitted tracked work. The counter-signal to clearing a session:
    /// the reasoning behind a half-finished edit lives only in that context.
    var isDirty: Bool { dirty > 0 || staged > 0 }

    /// A clone of a `git bundle` file: fetchable, but read-only and not on
    /// GitHub, so a push is rejected every time and gh has nothing to read.
    var remoteIsBundle: Bool { remoteURL?.hasSuffix(".bundle") == true }
}

/// One commit for the history graph.
struct GraphCommit: Equatable {
    var sha: String
    var parents: [String]
    var refs: [String] = []
    var subject: String = ""
    var committedAt: Date?

    var shortSHA: String { String(sha.prefix(7)) }
}

/// A commit placed in the graph: its lane, and the line segments that leave
/// its row for the next one, as (from lane, to lane) pairs.
nonisolated struct GraphRow: Equatable {
    var commit: GraphCommit
    var column: Int
    var edges: [GraphEdge]
    /// Lanes in use at this row, for sizing the drawing.
    var width: Int
}

nonisolated struct GraphEdge: Equatable, Hashable {
    var from: Int
    var to: Int
}

/// A row of the History card: a commit worth seeing, or a run of plain ones
/// folded into a count. `edges` on a gap are the lanes passing through it.
nonisolated enum GraphLine: Equatable {
    case commit(GraphRow)
    case gap(count: Int, edges: [GraphEdge])

    var edges: [GraphEdge] {
        switch self {
        case .commit(let row): return row.edges
        case .gap(_, let edges): return edges
        }
    }

    var width: Int {
        switch self {
        case .commit(let row): return row.width
        case .gap(_, let edges): return (edges.map { max($0.from, $0.to) }.max() ?? 0) + 1
        }
    }
}

nonisolated enum GitGraph {
    /// Refs worth a label. `origin/HEAD` only says which branch the remote calls
    /// default, which the Git card already says; it sat on nearly every HEAD row.
    static func shownRefs(_ refs: [String]) -> [String] {
        refs.filter { !$0.hasSuffix("/HEAD") }
    }

    /// Full sha, parents, ref names, subject, commit time -- tab-separated.
    static let format = "%H%x09%P%x09%D%x09%s%x09%ct"

    static func parse(_ output: String) -> [GraphCommit] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { raw in
            let f = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5, !f[0].isEmpty else { return nil }
            return GraphCommit(sha: f[0],
                               parents: f[1].split(separator: " ").map(String.init),
                               refs: f[2].split(separator: ",")
                                   .map { $0.trimmingCharacters(in: .whitespaces) }
                                   .filter { !$0.isEmpty },
                               subject: f[3],
                               committedAt: Double(f[4]).map { Date(timeIntervalSince1970: $0) })
        }
    }

    /// The landmarks of `rows`, with each run of the rest folded into one gap:
    /// the `newest`, anything carrying a ref, merges, fork points, and commits
    /// no remote-tracking ref reaches (unpushed). With no remote ref in view
    /// at all, "unpushed" would keep everything, so it is skipped.
    ///
    /// A gap draws the last folded row's edges, which lead into the next drawn
    /// row; layout never compacts lanes, so they sit in the same columns as
    /// the rows either side of it.
    static func condense(_ rows: [GraphRow], remotes: Set<String>,
                         newest: Int = 3, maxLines: Int = 10) -> [GraphLine] {
        let index = Dictionary(rows.enumerated().map { ($1.commit.sha, $0) }, uniquingKeysWith: { a, _ in a })
        var children: [String: Int] = [:]
        for row in rows { for p in row.commit.parents { children[p, default: 0] += 1 } }

        func isRemote(_ ref: String) -> Bool {
            ref.split(separator: "/").first.map { remotes.contains(String($0)) } ?? false
        }
        var pushed = Set<String>()
        var stack = rows.filter { $0.commit.refs.contains(where: isRemote) }.map(\.commit.sha)
        let judgePushed = !stack.isEmpty
        while let sha = stack.popLast() {
            guard pushed.insert(sha).inserted, let i = index[sha] else { continue }
            stack += rows[i].commit.parents
        }

        var lines: [GraphLine] = []
        var folded: [GraphRow] = []
        func flush() {
            guard !folded.isEmpty else { return }
            // A run ending at the root commit has no edges out of its last row;
            // the line still runs through the run, so draw the one before it.
            let edges = folded.last(where: { !$0.edges.isEmpty })?.edges ?? []
            lines.append(.gap(count: folded.count, edges: edges))
            folded = []
        }
        for (i, row) in rows.enumerated() {
            let c = row.commit
            let landmark = i < newest || !c.refs.isEmpty || c.parents.count > 1
                || children[c.sha, default: 0] > 1 || (judgePushed && !pushed.contains(c.sha))
            if landmark { flush(); lines.append(.commit(row)) } else { folded.append(row) }
        }
        flush()
        return Array(lines.prefix(maxLines))
    }

    /// Lanes for commits in topological order, newest first.
    ///
    /// Each lane holds the sha it is waiting to reach. A commit takes the lane
    /// already waiting for it (the lowest, if several are; else the first free
    /// one), any other lanes waiting
    /// for it converge into it, and its first parent continues in its own lane
    /// so a branch stays a straight line; further parents take a lane already
    /// waiting for them, or a free one. Lanes are never compacted, so a line
    /// keeps its column for its whole length.
    static func layout(_ commits: [GraphCommit]) -> [GraphRow] {
        var lanes: [String?] = []
        var placed: [(commit: GraphCommit, column: Int, carried: [String?], after: [String?], fromNode: [Int])] = []

        for commit in commits {
            let column: Int
            if let i = lanes.firstIndex(of: commit.sha) {
                column = i
            } else if let free = lanes.firstIndex(of: nil) {
                column = free
            } else {
                lanes.append(nil)
                column = lanes.count - 1
            }
            for i in lanes.indices where lanes[i] == commit.sha { lanes[i] = nil }
            let carried = lanes

            var fromNode: [Int] = []
            for (k, parent) in commit.parents.enumerated() {
                if k == 0 {
                    // Always straight down, even when another lane already waits
                    // for this parent: the duplicates converge at the parent's
                    // row, where the lower lane wins, so main stays main.
                    lanes[column] = parent
                    fromNode.append(column)
                } else if let i = lanes.firstIndex(of: parent) {
                    fromNode.append(i)
                } else if let free = lanes.firstIndex(of: nil) {
                    lanes[free] = parent
                    fromNode.append(free)
                } else {
                    lanes.append(parent)
                    fromNode.append(lanes.count - 1)
                }
            }
            placed.append((commit, column, carried, lanes, fromNode))
        }

        return placed.indices.map { r in
            let row = placed[r]
            let next = r + 1 < placed.count ? placed[r + 1] : nil
            var edges: [GraphEdge] = []
            for (i, waiting) in row.after.enumerated() {
                guard let waiting else { continue }
                // Lines converge on the next commit where it sits; everything
                // else runs straight down its own lane.
                let target = waiting == next?.commit.sha ? next!.column : i
                // `carried` predates lanes the parents opened, so it can be shorter.
                if i < row.carried.count, row.carried[i] != nil {
                    edges.append(GraphEdge(from: i, to: target))
                }
                if row.fromNode.contains(i) { edges.append(GraphEdge(from: row.column, to: target)) }
            }
            let width = max(row.after.count, row.carried.count, row.column + 1)
            return GraphRow(commit: row.commit, column: row.column,
                            edges: Array(Set(edges)).sorted { ($0.from, $0.to) < ($1.from, $1.to) },
                            width: width)
        }
    }
}

/// Pure parsing, split out from the subprocess work so every branch below is
/// reachable in a unit test without a repository on disk.
nonisolated enum GitParse {
    /// `gh api repos/{owner}/{repo} --jq '"\(.private) \(.allow_auto_merge)"'`
    /// output, e.g. "true false". Anything but a literal true/false is nil.
    static func repoSettings(_ out: String) -> (isPrivate: Bool?, autoMergeAllowed: Bool?) {
        let words = out.split(whereSeparator: \.isWhitespace).map { Bool(String($0)) }
        return (words.first ?? nil, words.count > 1 ? words[1] : nil)
    }

    /// `git status --porcelain=v1 --untracked-files=all`.
    ///
    /// Column 1 is the index status and column 2 the worktree status, so a file
    /// both staged and edited since counts once in each -- that is two facts
    /// about one file, not double counting.
    /// Added plus removed lines from `git diff --numstat`. A binary file shows
    /// "-\t-" and counts nothing: it has no lines to simplify.
    static func numstatLines(_ out: String) -> Int {
        out.split(separator: "\n").reduce(0) { total, line in
            let cols = line.split(separator: "\t", maxSplits: 2)
            guard cols.count >= 2 else { return total }
            return total + (Int(cols[0]) ?? 0) + (Int(cols[1]) ?? 0)
        }
    }

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

    /// The three mergeability fields, read separately from `pr(json:)` so each
    /// stays a small pure function over the same gh payload.
    ///
    /// A field gh omitted stays nil rather than becoming a default: "GitHub has
    /// not worked out whether this merges" and "it does not merge" are different
    /// answers, and only one of them should stop you.
    static func mergeReadiness(json: Data) -> MergeReadiness {
        guard let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            return MergeReadiness()
        }
        return MergeReadiness(mergeable: obj["mergeable"] as? String,
                              state: obj["mergeStateStatus"] as? String,
                              review: obj["reviewDecision"] as? String)
    }

    /// `gh run list --json status,conclusion,workflowName,url --limit 1`. An
    /// empty array is an observed "no runs"; anything unparseable is unknown.
    static func ci(json: Data) -> CIState {
        guard let rows = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else {
            return .unknown
        }
        guard let run = rows.first else { return .none }
        let workflow = run["workflowName"] as? String ?? "CI"
        let url = run["url"] as? String ?? ""
        if run["status"] as? String != "completed" {
            return .running(workflow: workflow, url: url)
        }
        return .finished(workflow: workflow, conclusion: run["conclusion"] as? String ?? "unknown", url: url)
    }

    /// `autoMergeRequest` is null when auto-merge is off and an object when on.
    /// Absent means the field wasn't read, which stays unknown.
    static func autoMerge(json: Data) -> Bool? {
        guard let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let value = obj["autoMergeRequest"] else { return nil }
        return !(value is NSNull)
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
