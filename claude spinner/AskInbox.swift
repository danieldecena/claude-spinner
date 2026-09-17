import Foundation
import Combine
import UserNotifications
import os.log

/// One question option as `ask.sh` copied it out of the tool input.
struct AskOption: Decodable, Equatable {
    let label: String
    let description: String?
}

/// One question, verbatim from `AskUserQuestion`'s `tool_input`.
struct AskQuestion: Decodable, Equatable {
    let question: String
    let header: String?
    let options: [AskOption]?
}

/// `tool_input`, decoded only as far as its string fields.
///
/// The shape differs per tool and the card only ever prints one value, so the
/// strings are kept and everything else -- numbers, arrays, nested objects -- is
/// discarded rather than modelled.
struct ToolInput: Decodable, Equatable {
    let strings: [String: String]

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        // A `tool_input` that isn't an object leaves this empty rather than
        // throwing: a decode failure here loses the whole request, and a prompt
        // that vanishes from the window is worse than one shown without detail.
        guard let container = try? decoder.container(keyedBy: AnyKey.self) else {
            strings = [:]
            return
        }
        var found: [String: String] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(String.self, forKey: key) {
                found[key.stringValue] = value
            }
        }
        strings = found
    }
}

/// A prompt `ask.sh` is blocking on, read from `<req>.ask.json`.
///
/// The hook is sitting in a poll loop the whole time one of these exists, so the
/// file's lifetime *is* the window in which an answer counts. It disappearing
/// means the deadline passed and the terminal took over — any answer written
/// after that lands nowhere, which is why every write checks first.
struct AskRequest: Decodable, Identifiable, Equatable {
    enum Kind: String, Decodable { case question, permission }

    let req: String
    let kind: Kind
    let sessionId: String
    let cwd: String
    let created: Double
    let toolName: String?
    let toolInput: ToolInput?
    let questions: [AskQuestion]?

    var id: String { req }

    /// Keys that name what a tool would actually do, most specific first.
    ///
    /// One ordered list rather than a table per tool: every tool with a subject
    /// puts it under one of these, and one without falls back to its own name.
    static let subjectKeys = ["command", "file_path", "url", "pattern", "query", "path", "prompt"]
    /// Capped because a heredoc script would otherwise *be* the card.
    static let subjectLimit = 600

    /// The command, path or URL the permission is actually for. Nil when the
    /// input carries no string field -- then the tool name is all there is.
    var toolSubject: String? {
        guard let strings = toolInput?.strings else { return nil }
        for key in Self.subjectKeys {
            let value = strings[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { continue }
            return value.count > Self.subjectLimit
                ? String(value.prefix(Self.subjectLimit)) + "…"
                : value
        }
        return nil
    }

    var projectName: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "session" : name
    }

    /// The single question `ask.sh` guarantees when it hands over a `question`
    /// ask — it passes multi-question and multiSelect shapes through to the
    /// terminal, because a banner cannot express either.
    var question: AskQuestion? { questions?.first }

    enum CodingKeys: String, CodingKey {
        case req, kind, cwd, created, questions
        case sessionId = "session_id"
        case toolName = "tool_name"
        case toolInput = "tool_input"
    }
}

/// What the user chose, written back as `<req>.answer.json` for `ask.sh` to read.
enum AskAnswer: Equatable {
    case option(String)   // a labelled choice for a question ask
    case allow
    case deny
    /// Seen and declined — the banner was dismissed, or the user went to the
    /// session instead. Same outcome as a timeout: the terminal prompt takes over.
    case passthrough

    var behavior: String {
        switch self {
        case .option, .allow: return "allow"
        case .deny: return "deny"
        case .passthrough: return "passthrough"
        }
    }
}

/// Watches `~/.claude/spinnerfeed/asks/` and answers what's in it.
///
/// Separate from `FeedWatcher` on purpose: the feed is a poll-and-render loop over
/// state that is true whether or not anyone looks, while this is a request/response
/// with a process blocked at the other end. Mixing them would put a deadline inside
/// a debounce.
@MainActor
final class AskInbox: ObservableObject {
    /// One instance owns the directory; views read it without being threaded it
    /// through every initializer.
    static let shared = AskInbox()

    @Published private(set) var pending: [AskRequest] = []
    /// nil until the first settings read lands. False is the case that matters:
    /// `add()` reports no error when authorization is denied, so without this the
    /// whole feature is a silent no-op — a banner nobody sees looks exactly like
    /// a banner nobody answered.
    @Published private(set) var notificationsAllowed: Bool?

    private let dir: URL
    private let ioQueue = DispatchQueue(label: "claude-spinner.asks")
    private var source: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    /// Requests already put on screen, so a rescan doesn't re-post a live banner.
    private var notified: Set<String> = []
    /// A killed hook changes nothing in the directory, so no event would ever
    /// notice its request is dead. This rescan is what does.
    private var pruneTimer: Timer?

    init(dir: URL? = nil) {
        self.dir = dir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/spinnerfeed/asks", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.dir, withIntermediateDirectories: true)
        rescan()
        startWatching()
        refreshAuthorization()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
    }

    /// Re-read whether macOS will actually present what we post.
    ///
    /// Logged because while the answer stays `false` the re-read changes nothing
    /// on screen, so a refresh that never runs and one that runs and finds the
    /// same denial are the same picture. The log line is the only thing that
    /// separates them.
    func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            os_log("claude spinner: authorization re-read status=%{public}d allowed=%{public}d",
                   settings.authorizationStatus.rawValue, allowed ? 1 : 0)
            Task { @MainActor [weak self] in self?.notificationsAllowed = allowed }
        }
    }

    deinit { source?.cancel(); pruneTimer?.invalidate() }

    // MARK: - Reading

    private func startWatching() {
        dirFD = open(dir.path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write, .extend, .delete, .rename],
            queue: ioQueue
        )
        src.setEventHandler { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
        src.setCancelHandler { [dirFD] in if dirFD >= 0 { close(dirFD) } }
        src.resume()
        source = src
    }

    func rescan() {
        var found = Self.read(from: dir)
        let orphans = Set(Self.orphaned(found, isAlive: Self.isAlive).map(\.req))
        for req in orphans {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(req).ask.json"))
        }
        found.removeAll { orphans.contains($0.req) }
        // An answer written after its hook died has no reader either, and it
        // outlived its ask forever: nothing else ever deletes an answer file.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in Self.orphanedAnswers(names, isAlive: Self.isAlive) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        let live = Set(found.map(\.req))

        // A request whose file vanished timed out; pull its banner so a tap can't
        // land on a hook that stopped listening several minutes ago.
        for gone in notified.subtracting(live) {
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: [Self.notificationID(gone)])
        }
        notified = live
        pending = found
    }

    /// Decode every `*.ask.json` in `dir`, oldest first. Pure but for the read, so
    /// a test can point it at a temp directory.
    nonisolated static func read(from dir: URL) -> [AskRequest] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let decoder = JSONDecoder()
        return names
            .filter { $0.hasSuffix(".ask.json") }
            .compactMap { name -> AskRequest? in
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(name))
                else { return nil }
                return try? decoder.decode(AskRequest.self, from: data)
            }
            .sorted { $0.created < $1.created }
    }

    /// The pid of the `ask.sh` that wrote a request: the last field of
    /// `<session-uuid>-<epoch>-<pid>`. Nil for an id not in that shape.
    nonisolated static func hookPID(_ req: String) -> pid_t? {
        guard let last = req.split(separator: "-").last, let pid = pid_t(last), pid > 0
        else { return nil }
        return pid
    }

    /// EPERM means the process exists and belongs to someone else, so it counts.
    nonisolated static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Requests whose hook has exited without removing its file. An id with no
    /// readable pid is kept: not knowing is not the same as dead.
    nonisolated static func orphaned(_ found: [AskRequest],
                                     isAlive: (pid_t) -> Bool) -> [AskRequest] {
        found.filter { request in
            guard let pid = hookPID(request.req) else { return false }
            return !isAlive(pid)
        }
    }

    /// Answer files whose hook has exited, by name. Same rule as `orphaned`: an
    /// unreadable pid is kept.
    nonisolated static func orphanedAnswers(_ names: [String],
                                            isAlive: (pid_t) -> Bool) -> [String] {
        let suffix = ".answer.json"
        return names.filter { name in
            guard name.hasSuffix(suffix),
                  let pid = hookPID(String(name.dropLast(suffix.count))) else { return false }
            return !isAlive(pid)
        }
    }

    // MARK: - Answering

    /// Write the answer `ask.sh` is waiting on. Returns false when the request is
    /// no longer live, which is a real outcome and not an error: the hook gave up
    /// and Claude Code is showing its own prompt, so silently "succeeding" here
    /// would claim an answer landed somewhere it did not.
    @discardableResult
    func answer(_ req: AskRequest, with answer: AskAnswer) -> Bool {
        Self.write(answer, for: req, in: dir)
    }

    nonisolated static func write(_ answer: AskAnswer, for req: AskRequest, in dir: URL) -> Bool {
        let askFile = dir.appendingPathComponent("\(req.req).ask.json")
        guard FileManager.default.fileExists(atPath: askFile.path) else { return false }

        var payload: [String: Any] = ["behavior": answer.behavior]
        if case .option(let label) = answer, let question = req.question {
            payload["answers"] = [question.question: label]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }

        // Same tmp+rename the hook scripts use: ask.sh polls for this path, and a
        // partially written file would decode as an empty behavior and pass through.
        let dst = dir.appendingPathComponent("\(req.req).answer.json")
        let tmp = dir.appendingPathComponent(".\(req.req).answer.tmp-\(UUID().uuidString)")
        do {
            try data.write(to: tmp)
            try FileManager.default.moveItem(at: tmp, to: dst)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
        return true
    }

    // MARK: - Notification identifiers
    //
    // Pure string work, kept together and testable: an action identifier that
    // doesn't round-trip means a tap resolves to no request and does nothing,
    // which looks exactly like a notification the user never touched.

    nonisolated static let prefix = "ASK"
    /// `|` because request ids are `<session-uuid>-<epoch>-<pid>` — every other
    /// obvious separator already appears inside one.
    nonisolated static let separator = "|"

    nonisolated static func categoryID(_ req: String) -> String { "\(prefix)\(separator)\(req)" }
    nonisolated static func notificationID(_ req: String) -> String { "ask-\(req)" }

    nonisolated static func actionID(req: String, choice: String) -> String {
        [prefix, req, choice].joined(separator: separator)
    }

    /// Split an action identifier back into its request and choice. Nil for
    /// anything that isn't ours, including the built-in default/dismiss actions.
    nonisolated static func parseAction(_ identifier: String) -> (req: String, choice: String)? {
        let parts = identifier.components(separatedBy: separator)
        guard parts.count == 3, parts[0] == prefix else { return nil }
        return (parts[1], parts[2])
    }

    /// The choice token for option `index`, and the answer a token maps back to.
    nonisolated static func optionChoice(_ index: Int) -> String { "opt\(index)" }

    nonisolated static func answer(for choice: String, in req: AskRequest) -> AskAnswer? {
        switch choice {
        case "allow": return .allow
        case "deny": return .deny
        default:
            guard choice.hasPrefix("opt"),
                  let index = Int(choice.dropFirst(3)),
                  let options = req.question?.options,
                  options.indices.contains(index)
            else { return nil }
            return .option(options[index].label)
        }
    }

    // MARK: - Categories

    /// A category per live request, since the buttons *are* that request's option
    /// labels. `setNotificationCategories` replaces the whole set, so the caller
    /// passes the static ones in alongside.
    nonisolated static func categories(for requests: [AskRequest]) -> [UNNotificationCategory] {
        requests.map { req in
            var actions: [UNNotificationAction] = []
            switch req.kind {
            case .permission:
                actions = [
                    UNNotificationAction(identifier: actionID(req: req.req, choice: "allow"),
                                         title: "Allow", options: []),
                    UNNotificationAction(identifier: actionID(req: req.req, choice: "deny"),
                                         title: "Deny", options: [.destructive]),
                ]
            case .question:
                // Only two show on a banner; the rest need the notification
                // expanded. Documented behaviour, and the reason the window's
                // detail pane is the surface for anything longer.
                actions = (req.question?.options ?? []).enumerated().map { index, option in
                    UNNotificationAction(identifier: actionID(req: req.req,
                                                              choice: optionChoice(index)),
                                         title: option.label, options: [])
                }
            }
            actions.append(UNNotificationAction(
                identifier: actionID(req: req.req, choice: "focus"),
                title: "Open session", options: [.foreground]))
            return UNNotificationCategory(identifier: categoryID(req.req),
                                          actions: actions,
                                          intentIdentifiers: [],
                                          options: [])
        }
    }

    /// Title and body for a request's banner.
    nonisolated static func notificationText(_ req: AskRequest) -> (title: String, body: String) {
        switch req.kind {
        case .question:
            return (req.question?.header ?? "Claude has a question",
                    "\(req.projectName) — \(req.question?.question ?? "")")
        case .permission:
            // The subject, not the tool name: "Bash" is not a thing you can
            // decide about. The banner truncates it, which is the tradeoff.
            return ("Permission needed",
                    "\(req.projectName) — \(req.toolSubject ?? req.toolName ?? "a tool")")
        }
    }
}
