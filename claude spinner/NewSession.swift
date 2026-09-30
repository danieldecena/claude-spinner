import Foundation

/// Starts a Claude Code session in one of your projects, in a new Ghostty window.
///
/// The window runs your `claude` shell function, not the binary: that function
/// heals settings, titles the tab and wraps the session in its own tmux session,
/// forwarding the environment tmux would otherwise drop. tmux is what lets this
/// app type into the session afterwards, so a session started any other way
/// could be watched but not answered. `zsh -i` is what loads the function.
enum NewSession {
    struct Project: Equatable, Identifiable {
        let name: String
        let path: String
        var id: String { path }
    }

    static let registry = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/project-registry.json")

    /// The projects `ws` knows, from the registry `~/bin/repo-inventory.py`
    /// writes: those on disk and not someone else's clone, by name. nil when the
    /// registry can't be read, which is not the same as having no projects.
    static func projects(registryJSON: Data?, home: String,
                         isDirectory: (String) -> Bool) -> [Project]? {
        guard let registryJSON,
              let obj = try? JSONSerialization.jsonObject(with: registryJSON) as? [String: Any],
              let projects = obj["projects"] as? [String: [String: Any]] else { return nil }
        return projects.compactMap { name, meta in
            guard var path = meta["path"] as? String,
                  meta["third_party_owner"] == nil || meta["third_party_owner"] is NSNull else { return nil }
            if path.hasPrefix("~/") { path = home + path.dropFirst() }
            return isDirectory(path) ? Project(name: name, path: path) : nil
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func loadProjects() -> [Project]? {
        projects(registryJSON: try? Data(contentsOf: registry), home: NSHomeDirectory()) { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// `sh` single quoting: safe for any text, including quotes and spaces.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The command Ghostty runs. Arguments (`--resume <id>`, a starting prompt)
    /// go to the `claude` function, which forwards them; none keeps the bare form.
    static func command(claudeArgs: [String]) -> String {
        guard !claudeArgs.isEmpty else { return "/bin/zsh -lic claude" }
        let line = "claude " + claudeArgs.map(shellQuoted).joined(separator: " ")
        return "/bin/zsh -lic " + shellQuoted(line)
    }

    private static func appleScriptQuoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func appleScript(for dir: String, claudeArgs: [String] = []) -> String {
        let quoted = appleScriptQuoted(dir)
        let command = appleScriptQuoted(command(claudeArgs: claudeArgs))
        return """
        tell application "Ghostty"
            set cfg to new surface configuration
            set initial working directory of cfg to \(quoted)
            set command of cfg to \(command)
            new window with configuration cfg
            activate
        end tell
        """
    }

    /// Open the window. nil when Ghostty took it, otherwise osascript's own
    /// error (Ghostty missing, Automation permission refused). Blocks; call it
    /// off the main thread.
    static func launch(in dir: String, claudeArgs: [String] = []) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", appleScript(for: dir, claudeArgs: claudeArgs)]
        let err = Pipe()
        task.standardOutput = FileHandle.nullDevice
        task.standardError = err
        do { try task.run() } catch { return error.localizedDescription }
        let data = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus != 0 else { return nil }
        let said = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return said.isEmpty ? "osascript exited \(task.terminationStatus)." : said
    }
}
