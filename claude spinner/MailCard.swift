import Combine
import SwiftUI

// The Home tab's Mail card: what the last mail scan found, from a small file the
// scan itself leaves behind.
//
// Nothing here scans. `~/.claude/spinnerfeed/mail.status.json` is written by
// `mail_scan.py --status-file` (the /email skill's health check keeps it fresh),
// the card reads it when the tab appears and again whenever the file's
// modification date moves, and the only thing that ever runs a scan is the
// Refresh button, once per press. No timer, no polling, no auto-refresh: an idle
// Home tab costs no tokens and no processes.

/// What the status file said.
nonisolated enum MailStatusLoad: Equatable {
    /// No file, or one that would not parse: the same "no data yet" to the reader.
    case none
    /// The scan ran and failed (`ok: false`). Carries the engine's short reason.
    case failed(error: String, updated: Date?)
    case ok(MailStatus)
}

nonisolated struct MailStatus: Equatable {
    var updated: Date?
    var urgent: Int
    var thisWeek: Int
    var ci: Int
    var finance: Int
    /// nil is "not reported", which is not zero.
    var unread: Int?
    var parseFailures: Int
    var noInboxFiles: [String]
}

nonisolated enum MailStatusFile {
    /// `~/.claude/spinnerfeed/mail.status.json`
    static func defaultURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/spinnerfeed/mail.status.json")
    }

    static func defaultScript() -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Tools/mail-triage/mail_scan.py")
    }

    /// Anything unreadable is `.none`; nothing here throws into the view.
    static func parse(_ data: Data) -> MailStatusLoad {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ok = obj["ok"] as? Bool else { return .none }
        let updated = (obj["updated"] as? String).flatMap(parseDate)
        guard ok else {
            let reason = (obj["error"] as? String).map { String($0.prefix(120)) } ?? "scan failed"
            return .failed(error: reason, updated: updated)
        }
        guard let counts = obj["counts"] as? [String: Any] else { return .none }
        func int(_ value: Any?) -> Int? { (value as? NSNumber).map(\.intValue) }
        return .ok(MailStatus(
            updated: updated,
            urgent: int(counts["act"]) ?? 0,
            thisWeek: int(counts["reply"]) ?? 0,
            ci: int(counts["ci"]) ?? 0,
            finance: int(counts["finance"]) ?? 0,
            unread: int(obj["unread"]),
            parseFailures: int(obj["parse_failures"]) ?? 0,
            noInboxFiles: (obj["no_inbox_files"] as? [String]) ?? []))
    }

    static func load(from url: URL) -> MailStatusLoad {
        guard let data = try? Data(contentsOf: url) else { return .none }
        return parse(data)
    }

    /// Python's isoformat carries microseconds ("…:59.589354-07:00"), which
    /// ISO8601DateFormatter's fractional mode does not promise to take; the
    /// card needs minutes, so the fraction is dropped before parsing.
    static func parseDate(_ text: String) -> Date? {
        let whole = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: whole)
    }

    /// "updated 12 min ago", or "never" when there is no reading to date.
    static func updatedLabel(_ updated: Date?, now: Date) -> String {
        guard let updated else { return "never" }
        let seconds = max(0, now.timeIntervalSince(updated))
        if seconds < 60 { return "updated just now" }
        if seconds < 3600 { return "updated \(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "updated \(Int(seconds / 3600)) h ago" }
        return "updated \(Int(seconds / 86_400)) d ago"
    }

    static func countsLine(_ s: MailStatus) -> String {
        "\(s.urgent) urgent · \(s.thisWeek) this week · \(s.ci) CI · \(s.finance) finance"
    }

    /// Runs the scan once and waits. Stdout (the full scan JSON) is discarded;
    /// stderr is kept only for its last line. Blocking: call it off the main thread.
    static func runScan(python: String = "/usr/bin/python3", script: URL, statusFile: URL,
                        days: Int = 3) -> MailRefreshError? {
        guard FileManager.default.fileExists(atPath: script.path) else {
            return (MailRefreshError(message: "mail_scan.py not found"))
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: python)
        task.arguments = [script.path, "--days", String(days), "--status-file", statusFile.path]
        task.standardOutput = FileHandle.nullDevice
        let err = Pipe()
        task.standardError = err
        do { try task.run() } catch {
            return (MailRefreshError(message: "could not start: \(error.localizedDescription)"))
        }
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus != 0 else { return nil }
        let last = String(decoding: stderr, as: UTF8.self)
            .split(separator: "\n").last.map(String.init) ?? ""
        let detail = last.isEmpty ? "" : ": " + String(last.prefix(100))
        return (MailRefreshError(message: "scan exited \(task.terminationStatus)\(detail)"))
    }
}

nonisolated struct MailRefreshError: Error, Equatable { var message: String }

/// Reads the status file when asked and when the file changes; runs the scan
/// only from `refresh()`.
final class MailStatusModel: ObservableObject {
    @Published private(set) var load: MailStatusLoad = .none
    @Published private(set) var running = false
    @Published private(set) var refreshError: String?

    private let url: URL
    private let script: URL
    private let ioQueue = DispatchQueue(label: "claude-spinner.mail", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var lastModified: Date?

    init(url: URL = MailStatusFile.defaultURL(), script: URL = MailStatusFile.defaultScript()) {
        self.url = url
        self.script = script
    }

    deinit { source?.cancel() }

    /// Home tab appeared: read once, then watch the folder for the file's
    /// modification date to move. Directory events, not a timer.
    func start() {
        reload(force: true)
        guard source == nil else { return }
        let fd = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: ioQueue)
        src.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in self?.reload(force: false) }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    /// Every write in the feed folder lands here, so a changed mtime is the
    /// gate: most events cost one stat and nothing else.
    func reload(force: Bool) {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard force || modified != lastModified else { return }
        lastModified = modified
        load = MailStatusFile.load(from: url)
    }

    func refresh() {
        guard !running else { return }
        running = true
        refreshError = nil
        let script = script, url = url
        Task.detached(priority: .utility) { [weak self] in
            let failure = MailStatusFile.runScan(script: script, statusFile: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.running = false
                self.refreshError = failure?.message
                self.reload(force: true)
            }
        }
    }
}

struct MailCard: View {
    @StateObject private var model = MailStatusModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CardTitle("Mail")
                Spacer(minLength: 4)
                Text(MailStatusFile.updatedLabel(updated, now: Date()))
                    .font(.ui(10)).foregroundStyle(Color.label)
                refreshButton
            }
            switch model.load {
            case .none:
                Text("Run /email or press Refresh").font(.ui(11)).foregroundStyle(Color.label)
            case .failed(let error, _):
                Text("Last scan failed: \(error)").font(.ui(11)).foregroundStyle(Color.attention)
            case .ok(let status):
                Text(MailStatusFile.countsLine(status)).font(.figure(11))
                if status.parseFailures > 0 {
                    Text("\(status.parseFailures) messages could not be read")
                        .font(.ui(10)).foregroundStyle(Color.attention)
                }
                if status.noInboxFiles.contains("gmail11") {
                    Text("gmail11: Gmail connector only").font(.ui(10)).foregroundStyle(Color.label)
                }
            }
            if let error = model.refreshError {
                Text("Refresh failed: \(error)").font(.ui(10)).foregroundStyle(Color.attention)
            }
        }
        .detailCard()
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var updated: Date? {
        switch model.load {
        case .ok(let status): return status.updated
        case .failed(_, let updated): return updated
        case .none: return nil
        }
    }

    private var refreshButton: some View {
        Button { model.refresh() } label: {
            HStack(spacing: 4) {
                if model.running {
                    TimelineView(.periodic(from: .now, by: 1 / Constants.spinnerFPS)) { context in
                        Text(Spinner.frame(at: context.date)).font(.claudeMono(11))
                    }
                }
                Text(model.running ? "Scanning" : "Refresh").font(.ui(10))
            }
        }
        .buttonStyle(.link)
        .disabled(model.running)
        .help("Scan the last 3 days of Apple Mail now")
    }
}
