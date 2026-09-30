import Foundation

/// Types a follow-up prompt into a running Claude Code session.
///
/// This is the only thing in the app that writes *into* a session, and it is the
/// one part of the answer path with no first-party channel behind it. Everything
/// else -- the option buttons, allow/deny -- goes back through `ask.sh`, which
/// Claude Code is already blocked on. A free-text prompt has no such hook, so it
/// has to be typed, and on this machine only tmux can do that. Both alternatives
/// were measured and neither works: writing to another process's `/dev/ttysNNN`
/// is output-only (the bytes paint on screen and never reach the reader in
/// stdin's position), and `TIOCSTI`, the one ioctl that pushes into a tty's input
/// queue, returns EPERM on this macOS even against a pty the caller owns.
///
/// A session outside tmux is therefore unreachable, and says so rather than
/// appearing to send.
enum SessionReplier {
    enum Failure: LocalizedError, Equatable {
        case noPane
        case busy
        case sendFailed
        case notObserved

        var errorDescription: String? {
            switch self {
            case .noPane:
                return "That session isn't in a tmux pane, so there's nowhere to type."
            case .busy:
                return "That session is mid-turn — wait for it to finish."
            case .sendFailed:
                return "tmux wouldn't take the keys."
            case .notObserved:
                return "Sent, but the session never showed it landing. Check it by hand."
            }
        }
    }

    /// What a delivered send looks like in the feed, which depends on what was
    /// typed. Built-in commands fire no UserPromptSubmit, so neither ever reads
    /// "thinking" -- observed 2026-09-29 against a live pane: `/clear` ends the
    /// session id and SessionEnd deletes its files within a second, and
    /// `/compact` ends in a SessionStart that rewrites the file idle with the
    /// turn fields cleared, after however long compaction takes.
    ///
    /// `unobservable` is the built-ins that change a setting or hand off to the
    /// cloud without starting a local turn and without touching the state file
    /// (`/model`, `/effort`, `/autofix-pr`): waiting for "thinking" would report
    /// every one of them as lost. For those, tmux taking the keys is the most
    /// that can be known, and callers say so rather than claiming it landed.
    enum Landing: Equatable {
        case turnStarted, cleared, compacted, unobservable

        init(typed text: String) {
            switch text.split(whereSeparator: \.isWhitespace).first {
            case "/clear": self = .cleared
            case "/compact": self = .compacted
            case "/model", "/effort", "/autofix-pr": self = .unobservable
            default: self = .turnStarted
            }
        }

        var timeout: TimeInterval {
            switch self {
            case .turnStarted: return 4
            case .cleared: return 15
            // Compaction is a model call over the whole context; a large one
            // runs well past a minute.
            case .compacted: return 180
            case .unobservable: return 0
            }
        }
    }

    /// Whether a successful `reply` for this text means it was seen to land, or
    /// only that the keys went in.
    static func canObserve(_ text: String) -> Bool {
        Landing(typed: text) != .unobservable
    }

    static let tmuxPaths = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]

    static var tmuxPath: String? {
        tmuxPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Resolving the pane

    /// Join a controlling tty against `tmux list-panes` output. Pure so the join
    /// is testable without a tmux server.
    ///
    /// Keyed on the pane id and never the session name: `send-keys -t <session>`
    /// resolves to that session's *active* pane, which on this machine has
    /// already typed into a different agent's prompt.
    static func paneID(forTTY tty: String, in listing: String) -> String? {
        guard !tty.isEmpty else { return nil }
        // `ps -o tty=` prints `ttys003`; tmux prints `/dev/ttys003`.
        let target = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        for line in listing.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, parts[0] == target else { continue }
            return String(parts[1])
        }
        return nil
    }

    /// Whether this session can be typed into at all — the check the UI needs
    /// before offering an action that sends keys.
    static func hasPane(_ session: SessionFeed) -> Bool {
        guard let pid = session.pid else { return false }
        return paneID(forPID: pid) != nil
    }

    /// The pane a pid's session is running in, or nil when it isn't in tmux.
    static func paneID(forPID pid: Int) -> String? {
        guard let tmux = tmuxPath else { return nil }
        let tty = run("/bin/ps", ["-o", "tty=", "-p", String(pid)])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let listing = run(tmux, ["list-panes", "-a", "-F", "#{pane_tty} #{pane_id}"])
        else { return nil }
        return paneID(forTTY: tty, in: listing)
    }

    // MARK: - Sending

    /// Cancel the current turn. Escape alone, and deliberately no Enter: this
    /// interrupts what is running rather than submitting anything.
    static func interrupt(_ session: SessionFeed,
                          completion: @escaping (Result<Void, Failure>) -> Void) {
        let done: (Result<Void, Failure>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let pid = session.pid, let tmux = tmuxPath,
                  let pane = paneID(forPID: pid) else { return done(.failure(.noPane)) }
            done(run(tmux, ["send-keys", "-t", pane, "Escape"]) == nil
                 ? .failure(.sendFailed) : .success(()))
        }
    }

    /// Type `text` into the session and confirm it landed.
    ///
    /// `send-keys` exiting 0 proves the keys reached a pane's input buffer, not
    /// that Claude was the foreground process in it, so the return here is keyed
    /// on the session's own state leaving idle. `completion` runs on the main
    /// queue.
    static func reply(to session: SessionFeed,
                      text: String,
                      feedDir: URL,
                      completion: @escaping (Result<Void, Failure>) -> Void) {
        let done: (Result<Void, Failure>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }
        // Only type into a session that is actually at its prompt. Keys sent
        // mid-turn land in whatever Claude is doing -- but `.attention` IS at
        // the prompt, so this asks whether it is working, not whether it is idle.
        guard session.isAtPrompt else { return done(.failure(.busy)) }
        let landing = Landing(typed: text)
        let file = stateFile(sessionID: session.id, feedDir: feedDir)
        DispatchQueue.global(qos: .userInitiated).async {
            // Resolving the pane shells out to ps and tmux, so it stays off the
            // main thread with the sends.
            guard let pid = session.pid, let tmux = tmuxPath,
                  let pane = paneID(forPID: pid) else { return done(.failure(.noPane)) }
            // Read before sending: /clear and /compact are only visible as a
            // change from this.
            let baseline = try? Data(contentsOf: file)
            // Three calls, and `-l` is not optional: without it tmux reads words
            // like "Enter" or "Space" in the text as key names and sends
            // keypresses instead of characters.
            let steps: [[String]] = [
                ["send-keys", "-t", pane, "Escape"],
                ["send-keys", "-t", pane, "-l", "--", text],
                ["send-keys", "-t", pane, "Enter"],
            ]
            for args in steps where run(tmux, args) == nil {
                return done(.failure(.sendFailed))
            }
            if landing == .unobservable { return done(.success(())) }
            done(observe(landing, sessionID: session.id, feedDir: feedDir, baseline: baseline)
                 ? .success(()) : .failure(.notObserved))
        }
    }

    /// Watch the session's own state file start working. This is the observation
    /// the return value is worth: everything upstream of it reports success for a
    /// pane that swallowed the keys.
    static func observeTurnStarted(sessionID: String,
                                   feedDir: URL,
                                   timeout: TimeInterval = 4,
                                   poll: TimeInterval = 0.15) -> Bool {
        observe(.turnStarted, sessionID: sessionID, feedDir: feedDir,
                baseline: nil, timeout: timeout, poll: poll)
    }

    static func observe(_ landing: Landing,
                        sessionID: String,
                        feedDir: URL,
                        baseline: Data?,
                        timeout: TimeInterval? = nil,
                        poll: TimeInterval = 0.15) -> Bool {
        let file = stateFile(sessionID: sessionID, feedDir: feedDir)
        let deadline = Date().addingTimeInterval(timeout ?? landing.timeout)
        while Date() < deadline {
            if landed(landing, baseline: baseline, current: try? Data(contentsOf: file)) {
                return true
            }
            Thread.sleep(forTimeInterval: poll)
        }
        return false
    }

    /// Whether the state file now shows `landing`, given what it held before
    /// the keys went in. With no baseline the two built-ins cannot be told
    /// apart from a file that was never there, so they are not observed.
    static func landed(_ landing: Landing, baseline: Data?, current: Data?) -> Bool {
        let obj = current.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        switch landing {
        case .turnStarted:
            let status = obj?["status"] as? String
            return status == "thinking" || status == "tool"
        case .cleared:
            return baseline != nil && current == nil
        case .compacted:
            guard baseline != nil, let obj, current != baseline else { return false }
            return obj["status"] as? String == "idle"
                && (obj["turn_start"] ?? NSNull()) is NSNull
                && (obj["last_seed"] ?? NSNull()) is NSNull
        case .unobservable:
            return false
        }
    }

    private static func stateFile(sessionID: String, feedDir: URL) -> URL {
        feedDir.appendingPathComponent("\(sessionID).state.json")
    }

    // MARK: - Process

    /// Run a command and return stdout, or nil if it failed to launch, exited
    /// non-zero or ran past 3s. nil is a distinct outcome from empty output on
    /// purpose. GitProbe's runner, for its timeout: a wedged tmux server
    /// otherwise blocks `list-panes` forever and the action never answers.
    private static func run(_ path: String, _ args: [String]) -> String? {
        guard let r = GitProbe.run(path, args, in: "/", timeout: 3), r.status == 0 else { return nil }
        return r.out
    }
}
