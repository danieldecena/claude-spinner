import Foundation

/// What the session is actually doing, read from its own transcript.
///
/// The statusLine reports numbers; this reports content — the last thing Claude
/// said, what it just ran, what you last asked, which branch it is on, and which
/// permission mode it is in. None of it is in the feed files.
struct TranscriptSnapshot: Equatable {
    var title: String?
    var lastPrompt: String?
    var lastAssistantText: String?
    var lastThinking: String?
    var recentTools: [String] = []
    var gitBranch: String?
    var permissionMode: String?
    var claudeVersion: String?
    /// Tokens on the most recent assistant turn, which is where the cache
    /// behaviour actually shows up.
    var cacheReadTokens: Int?
    var cacheCreationTokens: Int?
    var outputTokens: Int?
    var thinkingTokens: Int?
    var lastActivity: Date?

    var isEmpty: Bool {
        title == nil && lastPrompt == nil && lastAssistantText == nil && recentTools.isEmpty
    }
}

enum TranscriptReader {
    /// How much of the file's tail to read.
    ///
    /// These run to megabytes — 4.7 MB and 1299 lines for one live session here
    /// — and are appended to while being read, so the whole file is never an
    /// option. 256 KB reliably spans several turns of this transcript.
    static let tailBytes = 256 * 1024

    /// Read the tail of `path` and pull out what the detail pane shows.
    ///
    /// Returns an empty snapshot rather than nil for an unreadable file: a
    /// transcript that has not been written yet is a normal state for a session
    /// that just started, not an error worth surfacing.
    static func read(path: String, tailBytes: Int = TranscriptReader.tailBytes) -> TranscriptSnapshot {
        guard let handle = FileHandle(forReadingAtPath: path) else { return TranscriptSnapshot() }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()).map(Int.init) ?? 0
        let offset = max(0, size - tailBytes)
        try? handle.seek(toOffset: UInt64(offset))
        let data = (try? handle.readToEnd()) ?? Data()
        return parse(String(decoding: data, as: UTF8.self), droppingFirstLine: offset > 0)
    }

    /// Parse newline-delimited records, newest first.
    ///
    /// `droppingFirstLine` matters: seeking into the middle of a file lands
    /// mid-record, and that fragment is not a truncated record to recover but a
    /// different record's tail. Parsing it can only produce garbage, and a
    /// tolerant decoder would happily accept some of it.
    static func parse(_ text: String, droppingFirstLine: Bool) -> TranscriptSnapshot {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if droppingFirstLine, !lines.isEmpty { lines.removeFirst() }

        var out = TranscriptSnapshot()
        var toolsSeen: [String] = []

        // Backwards, so "last" is the first hit and each field is filled once.
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            switch obj["type"] as? String {
            case "ai-title":
                out.title = out.title ?? (obj["aiTitle"] as? String)
            case "last-prompt":
                out.lastPrompt = out.lastPrompt ?? (obj["lastPrompt"] as? String)
            case "permission-mode":
                out.permissionMode = out.permissionMode ?? (obj["permissionMode"] as? String)
            case "assistant":
                out.gitBranch = out.gitBranch ?? (obj["gitBranch"] as? String)
                out.claudeVersion = out.claudeVersion ?? (obj["version"] as? String)
                if out.lastActivity == nil, let stamp = obj["timestamp"] as? String {
                    out.lastActivity = ISO8601DateFormatter().date(from: stamp)
                }
                let message = obj["message"] as? [String: Any]
                if out.outputTokens == nil, let usage = message?["usage"] as? [String: Any] {
                    out.cacheReadTokens = usage["cache_read_input_tokens"] as? Int
                    out.cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int
                    out.outputTokens = usage["output_tokens"] as? Int
                    out.thinkingTokens = (usage["output_tokens_details"] as? [String: Any])?["thinking_tokens"] as? Int
                }
                for block in (message?["content"] as? [[String: Any]] ?? []) {
                    switch block["type"] as? String {
                    case "text":
                        if out.lastAssistantText == nil,
                           let t = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !t.isEmpty { out.lastAssistantText = t }
                    case "thinking":
                        if out.lastThinking == nil,
                           let t = (block["thinking"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !t.isEmpty { out.lastThinking = t }
                    case "tool_use":
                        if let name = block["name"] as? String { toolsSeen.append(name) }
                    default: break
                    }
                }
            default: break
            }
        }
        // Newest first, runs collapsed, capped. A turn that ran eight Bash calls
        // rendered as "Bash · Bash · Bash · Bash · Bash · Bash · Bash · Bash",
        // which fills the line and says less than "Bash ×8".
        var collapsed: [String] = []
        for name in toolsSeen {
            if let last = collapsed.last, last == name || last.hasPrefix("\(name) ×") {
                let count = Int(last.split(separator: "×").last ?? "1") ?? 1
                collapsed[collapsed.count - 1] = "\(name) ×\(count + 1)"
            } else {
                collapsed.append(name)
            }
        }
        out.recentTools = Array(collapsed.prefix(8))
        return out
    }
}
