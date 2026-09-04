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
                return "Sent, but the session never started a turn. Check it by hand."
            }
        }
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
        // mid-turn land in whatever Claude is doing.
        guard session.status == .idle else { return done(.failure(.busy)) }
        guard let pid = session.pid, let tmux = tmuxPath,
              let pane = paneID(forPID: pid) else { return done(.failure(.noPane)) }

        DispatchQueue.global(qos: .userInitiated).async {
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
            done(observeTurnStarted(sessionID: session.id, feedDir: feedDir)
                 ? .success(()) : .failure(.notObserved))
        }
    }

    /// Watch the session's own state file leave `idle`. This is the observation
    /// the return value is worth: everything upstream of it reports success for a
    /// pane that swallowed the keys.
    static func observeTurnStarted(sessionID: String,
                                   feedDir: URL,
                                   timeout: TimeInterval = 4,
                                   poll: TimeInterval = 0.15) -> Bool {
        let file = feedDir.appendingPathComponent("\(sessionID).state.json")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: file),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = obj["status"] as? String, status != "idle" {
                return true
            }
            Thread.sleep(forTimeInterval: poll)
        }
        return false
    }

    // MARK: - Process

    /// Run a command and return stdout, or nil if it failed to launch or exited
    /// non-zero. nil is a distinct outcome from empty output on purpose.
    private static func run(_ path: String, _ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
