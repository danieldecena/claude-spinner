import Foundation

/// Writes the feed plumbing on first run: copies the bundled scripts into
/// ~/.claude and merges the spinnerfeed hooks + statusLine into settings.json
/// without clobbering existing config (backup + append-only merge, atomic write).
enum SetupInstaller {
    enum SetupError: LocalizedError {
        case malformedSettings
        case missingBundledScript
        var errorDescription: String? {
            switch self {
            case .malformedSettings:
                return "settings.json isn't valid JSON — fix it, or add the hooks by hand."
            case .missingBundledScript:
                return "The bundled feed scripts are missing from the app."
            }
        }
    }

    /// Every Claude Code lifecycle event the feed listens on.
    static let hookEvents = [
        "SessionStart", "PreToolUse", "PostToolUse",
        "UserPromptSubmit", "Notification", "SessionEnd", "Stop",
        "SubagentStart", "SubagentStop",
    ]

    static let emitCommandPath = "~/.claude/spinnerfeed/emit.sh"
    static let askCommandPath = "~/.claude/spinnerfeed/ask.sh"

    /// One hook entry to merge. `script` is the idempotency key, not the whole
    /// command: two handlers on the same event point at different scripts, so
    /// "is anything of ours already wired here" would see emit.sh and wrongly
    /// conclude ask.sh was installed too. It is the full path, matched against
    /// the command's executable: a bare "emit.sh" substring also matched some
    /// other tool's `~/bin/emit.sh`, and the real hook was then never added.
    struct HookHandler {
        let event: String
        let matcher: String
        let script: String
        let command: String
        /// nil leaves Claude Code's default. ask.sh blocks on a human, so its
        /// handlers pin a ceiling well above the deadline the script enforces
        /// itself — the script decides the fallback, never the timeout.
        var timeout: Int?
    }

    static let handlers: [HookHandler] =
        hookEvents.map {
            HookHandler(event: $0, matcher: "", script: emitCommandPath,
                        command: "\(emitCommandPath) \($0)", timeout: nil)
        } + [
            HookHandler(event: "PreToolUse", matcher: "AskUserQuestion", script: askCommandPath,
                        command: "\(askCommandPath) question", timeout: 600),
            HookHandler(event: "PermissionRequest", matcher: "", script: askCommandPath,
                        command: "\(askCommandPath) permission", timeout: 600),
        ]

    /// Append-only merge of the spinnerfeed hooks + statusLine. Pure, no I/O.
    static func mergeSpinnerHooks(into settings: [String: Any]) -> [String: Any] {
        var out = settings
        var hooks = (out["hooks"] as? [String: Any]) ?? [:]
        for handler in handlers {
            var groups = (hooks[handler.event] as? [[String: Any]]) ?? []
            // Keyed on (script, matcher). A missing "matcher" key means the
            // empty matcher — settings.json in the wild has both forms.
            let alreadyWired = groups.contains { group in
                guard (group["matcher"] as? String ?? "") == handler.matcher else { return false }
                let entries = (group["hooks"] as? [[String: Any]]) ?? []
                return entries.contains {
                    // Tilde-expanded both sides: a hand-edited settings.json may
                    // spell the same script as an absolute path.
                    let exe = ($0["command"] as? String)?
                        .split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
                    return (exe as NSString).expandingTildeInPath
                        == (handler.script as NSString).expandingTildeInPath
                }
            }
            if !alreadyWired {
                var entry: [String: Any] = ["type": "command", "command": handler.command]
                if let timeout = handler.timeout { entry["timeout"] = timeout }
                groups.append(["matcher": handler.matcher, "hooks": [entry]])
                hooks[handler.event] = groups
            }
        }
        out["hooks"] = hooks
        if out["statusLine"] == nil {
            out["statusLine"] = ["type": "command", "command": "bash ~/.claude/statusline-command.sh"]
        }
        return out
    }

    /// Copy the scripts and merge settings.json. Safe to re-run.
    static func install() -> Result<Void, Error> {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
        let feedDir = claudeDir.appendingPathComponent("spinnerfeed", isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: feedDir, withIntermediateDirectories: true)

            guard let emitSrc = Bundle.main.url(forResource: "emit", withExtension: "sh"),
                  let askSrc = Bundle.main.url(forResource: "ask", withExtension: "sh"),
                  let statusSrc = Bundle.main.url(forResource: "statusline-command", withExtension: "sh")
            else { return .failure(SetupError.missingBundledScript) }

            try copyExecutable(from: emitSrc, to: feedDir.appendingPathComponent("emit.sh"))
            try copyExecutable(from: askSrc, to: feedDir.appendingPathComponent("ask.sh"))
            try copyExecutable(from: statusSrc, to: claudeDir.appendingPathComponent("statusline-command.sh"))

            let settingsURL = claudeDir.appendingPathComponent("settings.json")
            var current: [String: Any] = [:]
            if fm.fileExists(atPath: settingsURL.path) {
                let data = try Data(contentsOf: settingsURL)
                let stamp = Int(Date().timeIntervalSince1970)
                try data.write(to: claudeDir.appendingPathComponent("settings.json.backup-\(stamp)"))
                guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                else { return .failure(SetupError.malformedSettings) }
                current = parsed
            }
            let merged = mergeSpinnerHooks(into: current)
            let out = try JSONSerialization.data(withJSONObject: merged,
                                                 options: [.prettyPrinted, .sortedKeys])
            try writeAtomically(out, to: settingsURL)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Copy `src` over `dst`, preserving a differing `dst` as a timestamped
    /// backup first.
    ///
    /// The scripts are the only thing the installer replaces wholesale, and
    /// they're also the thing most likely to have been hand-edited in place —
    /// `~/.claude/statusline-command.sh` had drifted well ahead of the bundled
    /// copy, and replacing it silently would have destroyed that work with
    /// nothing to recover from. settings.json has been backed up before writing
    /// since the first version; this brings the scripts up to the same footing
    /// and reuses its `.backup-<epoch>` naming.
    ///
    /// An identical `dst` is left alone. `install()` is documented safe to
    /// re-run, so backing up a byte-identical file would just accumulate noise
    /// on every launch while preserving nothing.
    static func copyExecutable(from src: URL, to dst: URL, now: Date = Date()) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            if let incoming = try? Data(contentsOf: src),
               let existing = try? Data(contentsOf: dst),
               incoming == existing {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst.path)
                return
            }
            let stamp = Int(now.timeIntervalSince1970)
            let backup = dst.deletingLastPathComponent()
                .appendingPathComponent("\(dst.lastPathComponent).backup-\(stamp)")
            // Two installs inside the same second collide on the stamp. The
            // loser is a backup of the same generation, so replacing it loses
            // nothing the winner isn't already preserving.
            if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
            try fm.copyItem(at: dst, to: backup)
            try fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst.path)
    }

    private static func writeAtomically(_ data: Data, to dst: URL) throws {
        let tmp = dst.deletingLastPathComponent()
            .appendingPathComponent(".\(dst.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp)
        if FileManager.default.fileExists(atPath: dst.path) {
            _ = try FileManager.default.replaceItemAt(dst, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: dst)
        }
    }
}
