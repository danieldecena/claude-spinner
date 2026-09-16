import Foundation

/// Reads git state for a directory, and caches it by directory.
///
/// Keyed on the path rather than the session id because several sessions
/// routinely sit in one repo -- that is the case that started this feature --
/// and probing once per session would run the same commands three times over
/// and could show three different answers for one working tree.
///
/// Local probes and network probes are cached separately. A `git status` is
/// milliseconds; `ls-remote` and `gh pr view` are network round trips, and
/// tying the two to one TTL would either hammer the network or leave the dirty
/// count stale for minutes.
actor GitProbe {
    static let shared = GitProbe()

    /// Local facts: cheap enough to re-read whenever the pane is looked at.
    private static let localTTL: TimeInterval = 5
    /// Network facts: a round trip each, so they trail the local ones.
    private static let remoteTTL: TimeInterval = 90
    /// No git or gh invocation may outlive this. A network partition otherwise
    /// leaves `ls-remote` blocked on connect and the entry never resolves.
    private static let timeout: TimeInterval = 8

    private struct Entry {
        var snapshot: GitSnapshot
        var localAt: Date
        var remoteAt: Date
    }

    private var cache: [String: Entry] = [:]
    /// Paths already known not to be repositories, so a non-repo cwd doesn't
    /// re-run `rev-parse` every few seconds forever.
    private var notRepos: Set<String> = []

    /// Where `gh` lives. Homebrew's ARM prefix, then Intel's. Resolved once,
    /// because a hardcoded path that isn't there produces a failed run, which
    /// `prState` used to map to `.unknown` -- a state whose sentence blames
    /// GitHub for a binary that was never installed.
    static let ghPath: String? = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Every subprocess runs on `queue`, never on the actor's own executor.
    /// Blocking a cooperative thread for the length of a network `ls-remote`
    /// starves the pool that the rest of the app's async work shares.
    private static let queue = DispatchQueue(label: "spinner.gitprobe", qos: .utility)

    func snapshot(for cwd: String) async -> GitSnapshot? {
        guard !cwd.isEmpty, !notRepos.contains(cwd) else { return nil }
        let now = Date()

        if let entry = cache[cwd], now.timeIntervalSince(entry.localAt) < Self.localTTL {
            return entry.snapshot
        }

        let previous = cache[cwd]?.snapshot ?? GitSnapshot()
        let remoteAt = cache[cwd]?.remoteAt ?? .distantPast
        let expired = now.timeIntervalSince(remoteAt) >= Self.remoteTTL

        let read = await Self.offMainRead(cwd: cwd, previous: previous, remoteExpired: expired)

        guard let read else {
            notRepos.insert(cwd)
            cache[cwd] = nil
            return nil
        }
        var snap = read.snapshot
        snap.readAt = now
        if read.readRemote { snap.remoteReadAt = now }
        cache[cwd] = Entry(snapshot: snap, localAt: now,
                           remoteAt: read.readRemote ? now : remoteAt)
        return snap
    }

    /// nil means "not a repository", which is distinct from a probe that failed:
    /// the `rev-parse` gate below is the only thing allowed to produce it.
    private static func offMainRead(cwd: String,
                                    previous: GitSnapshot,
                                    remoteExpired: Bool)
    async -> (snapshot: GitSnapshot, readRemote: Bool)? {
        await withCheckedContinuation { cont in
            queue.async {
                guard git(["rev-parse", "--is-inside-work-tree"], in: cwd) != nil else {
                    cont.resume(returning: nil)
                    return
                }
                var snap = previous
                readLocal(into: &snap, cwd: cwd)

                // The remote decision is made here, after the local read, and
                // not from the clock alone. A commit or a branch switch makes
                // the cached sync and PR wrong immediately; waiting out the
                // 90-second TTL means the card asserts something false in the
                // meantime, which is worse than admitting it doesn't know.
                let switchedBranch = snap.branch != previous.branch
                if switchedBranch {
                    // These describe the branch we just left. Dropping them
                    // before the read means a read that then fails says
                    // "unknown" instead of attributing the old branch's PR to
                    // this one.
                    snap.sync = .unknown
                    snap.pr = .unknown
                    snap.merge = MergeReadiness()
                }
                let wantRemote = remoteExpired
                    || switchedBranch
                    || snap.headSHA != previous.headSHA
                if wantRemote { readRemote(into: &snap, cwd: cwd) }
                cont.resume(returning: (snap, wantRemote))
            }
        }
    }

    /// Drop a directory's cached state so the next read is fresh. Called after
    /// an action changes the repo -- a push that leaves the row still reading
    /// "ahead 3" looks like it silently failed.
    func invalidate(_ cwd: String) {
        cache[cwd] = nil
        notRepos.remove(cwd)
    }

    // MARK: - Probes

    private static func readLocal(into snap: inout GitSnapshot, cwd: String) {
        let head = git(["rev-parse", "--abbrev-ref", "HEAD"], in: cwd)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        snap.detached = (head == "HEAD")
        snap.branch = snap.detached ? nil : head
        snap.headSHA = git(["rev-parse", "HEAD"], in: cwd)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        snap.ghInstalled = (ghPath != nil)

        let counts = GitParse.porcelain(
            git(["status", "--porcelain=v1", "--untracked-files=all"], in: cwd) ?? "")
        snap.dirty = counts.dirty
        snap.staged = counts.staged
        snap.untracked = counts.untracked

        snap.upstream = git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
                            in: cwd)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let branch = snap.branch {
            // `origin/HEAD` is the recorded default. Absent in a fresh clone that
            // never set it, in which case no branch claims to be the default and
            // "create PR" simply stays available -- the safe way to be wrong.
            let def = git(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: cwd)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "/").last.map(String.init)
            snap.isDefaultBranch = (def == branch)
        }
    }

    private static func readRemote(into snap: inout GitSnapshot, cwd: String) {
        snap.sync = syncState(cwd: cwd, snap: snap)
        (snap.pr, snap.merge) = prState(cwd: cwd)
    }

    private static func syncState(cwd: String, snap: GitSnapshot) -> SyncState {
        guard snap.branch != nil else { return .noUpstream }
        guard let upstream = snap.upstream, !upstream.isEmpty else { return .noUpstream }
        // "origin/main" -> remote "origin", branch "main". The remote name is
        // everything before the first slash; the branch may itself contain slashes.
        let parts = upstream.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return .unknown }
        let (remoteName, remoteBranch) = (parts[0], parts[1])

        // Already read by `readLocal`, which always runs first.
        let local = snap.headSHA
        let remote = git(["ls-remote", remoteName, "refs/heads/\(remoteBranch)"], in: cwd)
            .flatMap { GitParse.lsRemote($0, branch: remoteBranch) }

        guard let remote else {
            return GitParse.sync(local: local, remote: nil, hasUpstream: true,
                                 haveRemoteObject: false, remoteIsAncestor: false,
                                 aheadCount: 0)
        }
        let haveObject = git(["cat-file", "-e", "\(remote)^{commit}"], in: cwd) != nil
        let isAncestor = haveObject
            && git(["merge-base", "--is-ancestor", remote, "HEAD"], in: cwd) != nil
        let ahead = isAncestor
            ? Int(git(["rev-list", "--count", "\(remote)..HEAD"], in: cwd)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
            : 0
        return GitParse.sync(local: local, remote: remote, hasUpstream: true,
                             haveRemoteObject: haveObject, remoteIsAncestor: isAncestor,
                             aheadCount: ahead)
    }

    private static func prState(cwd: String) -> (PRState, MergeReadiness) {
        guard let gh = ghPath else { return (.unknown, MergeReadiness()) }
        let fields = "number,state,isDraft,url,mergeable,mergeStateStatus,reviewDecision"
        let result = run(gh, ["pr", "view", "--json", fields], in: cwd)
        guard let result else { return (.unknown, MergeReadiness()) }
        if result.status == 0, let state = GitParse.pr(json: Data(result.out.utf8)) {
            return (state, GitParse.mergeReadiness(json: Data(result.out.utf8)))
        }
        // Mergeability is only meaningful alongside a PR that was actually read.
        return (GitParse.prFailure(stderr: result.err), MergeReadiness())
    }

    // MARK: - Running

    /// stdout of a successful git command, or nil on any nonzero exit. Callers
    /// that need to tell failure modes apart use `run` directly.
    static func git(_ args: [String], in cwd: String) -> String? {
        guard let r = run("/usr/bin/git", args, in: cwd), r.status == 0 else { return nil }
        return r.out
    }

    static func run(_ launchPath: String,
                    _ args: [String],
                    in cwd: String) -> (out: String, err: String, status: Int32)? {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        // A GUI app's environment has no interactive PATH, and `gh` shells out
        // to `git`. Without this, gh reports a repo it can see as not a repo.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        // Never let a credential helper open a GUI prompt behind the menu bar,
        // where nobody would ever see it and the probe would hang to its timeout.
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = "/usr/bin/true"
        task.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do { try task.run() } catch { return nil }

        // Read both pipes on their own queues before waiting. A single-threaded
        // read-then-wait deadlocks the moment either stream fills its 64K buffer,
        // and `ls-remote` against a large repo is well past that.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        for (pipe, sink) in [(outPipe, { outData = $0 }), (errPipe, { errData = $0 })]
            as [(Pipe, (Data) -> Void)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                sink(pipe.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
        }

        if task.waitUntilExit(before: Date().addingTimeInterval(timeout)) == false {
            task.terminate()
            _ = group.wait(timeout: .now() + 1)
            return nil
        }
        _ = group.wait(timeout: .now() + 2)
        return (String(decoding: outData, as: UTF8.self),
                String(decoding: errData, as: UTF8.self),
                task.terminationStatus)
    }
}

private extension Process {
    /// `waitUntilExit()` with a deadline. Returns false if the process was still
    /// running when the deadline passed, leaving termination to the caller.
    func waitUntilExit(before deadline: Date) -> Bool {
        while isRunning {
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return true
    }
}
