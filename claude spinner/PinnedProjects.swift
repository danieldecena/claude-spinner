import Foundation

/// A project pinned to the top of the sidebar, so it can be worked on with no
/// session running. Hard-coded: two projects, and a settings UI for them would
/// be more code than the list.
struct PinnedProject: Identifiable, Equatable {
    let name: String
    let path: String
    /// The line under the title. The Desktop project's description lives on
    /// Anthropic's servers, so it is copied here rather than read.
    let summary: String
    let topic: Topic
    /// A second launch button that starts the session with a prompt.
    var quickStart: QuickStart? = nil

    /// What ties the user-wide skills, workflows and schedulers to this project.
    struct Topic: Equatable {
        /// Searched in a skill's frontmatter and a workflow's body.
        let about: String
        /// Looser, for schedulers: a job that names the project only by a word.
        let words: [String]
    }

    struct QuickStart: Equatable {
        let label: String
        let systemImage: String
        let prompt: String
    }

    /// The selection value for its sidebar row. The selection is a session id
    /// otherwise; this prefix is what keeps the two from ever being equal.
    static let tagPrefix = "pinned:"
    var tag: String { Self.tagPrefix + name }
    var id: String { tag }

    static let jobSearch = PinnedProject(
        name: "Job Search", path: NSHomeDirectory() + "/developer/job search",
        summary: "Marketing and rev ops roles, remote US or LA, Bay Area, NYC and Vancouver.",
        topic: Topic(about: "job[ -]?search|jobscout|job (application|board|alert|posting|list)|linkedin"
                            + "|recruiter|interview|name:.*apply|work ?search",
                     words: ["job", "scout", "career"]),
        quickStart: QuickStart(label: "Apply next job", systemImage: "paperplane",
                               prompt: "/anthropic-skills:apply-next-job"))

    static let plans = PinnedProject(
        name: "Plans", path: NSHomeDirectory() + "/developer/_project-knowledge",
        summary: "Planning only: plans, research, specs and comparisons, never code. "
            + "Each plan is saved to plans/<slug>.md and handed to the build project.",
        topic: Topic(about: "project-knowledge", words: ["project-knowledge"]))

    static let all = [jobSearch, plans]

    /// Session ids are UUIDs, so this is the whole test for "not a session".
    static func isPinnedTag(_ tag: String?) -> Bool { tag?.hasPrefix(tagPrefix) == true }

    static func project(forTag tag: String?) -> PinnedProject? { all.first { $0.tag == tag } }

    /// `cwd` is the folder or inside it. Case-insensitive, as the volume is, and
    /// by path component: `/x/job search-foo` is a different folder from `/x/job search`.
    static func contains(_ path: String, cwd: String) -> Bool {
        var root = path.lowercased()
        while root.count > 1, root.hasSuffix("/") { root.removeLast() }
        let dir = cwd.lowercased()
        return dir == root || dir.hasPrefix(root + "/")
    }

    static func liveSessions(in path: String, sessions: [SessionFeed]) -> [SessionFeed] {
        sessions.filter { $0.parentSessionId == nil && contains(path, cwd: $0.cwd) }
    }
}

/// What a discovery source found. An empty source and an unreadable one look
/// the same as a bare array; they are kept apart because "nothing scheduled"
/// and "couldn't look" say opposite things about the project.
nonisolated struct Found<T: Equatable>: Equatable {
    var items: [T] = []
    /// Folders that would not list and files that would not parse.
    var unreadable: [String] = []

    var isEmpty: Bool { items.isEmpty && unreadable.isEmpty }
}

nonisolated struct TranscriptFile: Equatable {
    let id: String
    let path: String
    let modified: Date
}

nonisolated struct RecentSession: Identifiable, Equatable {
    let id: String
    let modified: Date
    let title: String?
    let lastPrompt: String?
    let lastActivity: Date?

    var when: Date { lastActivity ?? modified }

    var headline: String {
        func clean(_ text: String?) -> String? {
            let line = text?.split(separator: "\n", omittingEmptySubsequences: true).first
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return line?.isEmpty == false ? line : nil
        }
        return clean(title) ?? clean(lastPrompt) ?? "Untitled session"
    }
}

nonisolated struct ProjectSkill: Equatable {
    let name: String
    let isProject: Bool
    /// Set for a plugin's skill, whose slash name carries the plugin's.
    var plugin: String? = nil

    var command: String { "/" + (plugin.map { $0 + ":" } ?? "") + name }
}

nonisolated struct ScheduledJob: Equatable {
    let name: String
    let schedule: String
    /// "launchd", "cron" or "Desktop".
    let source: String
    /// nil when the source doesn't say (launchd: whether it is loaded isn't read).
    let enabled: Bool?
}

nonisolated struct ProjectWorkflow: Equatable {
    let name: String
}

nonisolated struct ProjectArtifact: Equatable {
    let title: String
    let url: String
    let path: String
    var summary: String? = nil

    /// A one-line description from the file's `note`: its first sentence, less
    /// a leading "<title> =" (Career Hub's note opens "Career Hub = …"). The
    /// rest of a note is upkeep instructions, not something to show.
    static func summary(fromNote note: String?, title: String) -> String? {
        guard var text = note?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let end = text.range(of: ". ") { text = String(text[..<end.lowerBound]) }
        let prefix = title + " ="
        if text.hasPrefix(prefix) { text = text.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces) }
        if text.hasSuffix(".") { text.removeLast() }
        return text.isEmpty ? nil : text
    }
}

nonisolated struct ProjectExtras: Equatable {
    var skills = Found<ProjectSkill>()
    var scheduled = Found<ScheduledJob>()
    var workflows = Found<ProjectWorkflow>()
    var artifacts = Found<ProjectArtifact>()
    var about = ProjectAbout()
}

/// The terminal's side of the Desktop project panel: its instructions, its
/// memory and its folder.
nonisolated struct ProjectAbout: Equatable {
    /// Instruction files present in the folder.
    var instructions: [String] = []
    var memoryDir = ""
    /// Memory files, not counting the MEMORY.md index. nil when the folder
    /// exists but can't be listed; 0 when there is none.
    var memories: Int? = 0
    /// The folders Desktop gives this project's sessions: the root first, then
    /// any others linked beside it. Just the root when Desktop has no record.
    var folders: [String] = []
    /// Docs in the root that sessions read for context. Desktop's uploaded
    /// project files are not on this Mac, so they are not counted here.
    var context: [String] = []
}

/// Everything the pinned tab reads from disk. Pure over the paths it is given,
/// so the tests point it at a temp folder and never at the real home.
nonisolated enum ProjectDiscovery {
    // MARK: - Files

    /// Directory entries; [] when the folder isn't there, nil when it is but
    /// can't be listed (or is a file).
    static func listing(_ dir: String) -> [String]? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) else { return [] }
        guard isDir.boolValue else { return nil }
        return try? FileManager.default.contentsOfDirectory(atPath: dir)
    }

    static func text(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// Files called `name` up to `maxDepth` levels under `root` (its own
    /// entries are level 1), never entering a folder named in `skipping`.
    /// Walked by hand rather than with `FileManager.enumerator`, which drops a
    /// folder it can't read without saying so, and whose `skipDescendants`
    /// also swallowed sibling files.
    static func find(_ name: String, under root: String, maxDepth: Int,
                     skipping: Set<String> = []) -> (paths: [String], unreadable: [String]) {
        var paths: [String] = []
        var unreadable: [String] = []
        func visit(_ dir: String, level: Int) {
            guard let entries = listing(dir) else {
                unreadable.append(dir)
                return
            }
            for entry in entries.sorted() {
                let path = dir + "/" + entry
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                if entry == name, exists, !isDir.boolValue {
                    paths.append(path)
                } else if exists, isDir.boolValue, level < maxDepth, !skipping.contains(entry) {
                    visit(path, level: level + 1)
                }
            }
        }
        visit(root, level: 1)
        return (paths, unreadable)
    }

    // MARK: - Recent sessions

    /// The name Claude Code gives a folder under `~/.claude/projects`: every
    /// character that isn't a letter or digit becomes `-`.
    static func transcriptSlug(_ path: String) -> String {
        String(path.utf16.map { unit -> Character in
            switch unit {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return Character(UnicodeScalar(UInt8(unit)))
            default: return "-"
            }
        })
    }

    /// The folders that hold this project's transcripts: the slug matched
    /// case-insensitively, since one project turns up under both `developer`
    /// and `Developer` on a case-insensitive volume. Worktree folders
    /// (`<slug>--worktrees-x`) are other projects.
    static func transcriptDirs(matching slug: String, among names: [String]) -> [String] {
        names.filter { $0.lowercased() == slug.lowercased() }
    }

    /// Newest first, one per session id, without the live ones, capped.
    static func newest(_ files: [TranscriptFile], excluding live: Set<String>, limit: Int) -> [TranscriptFile] {
        let live = Set(live.map { $0.lowercased() })
        var byId: [String: TranscriptFile] = [:]
        for file in files where !live.contains(file.id) {
            if let have = byId[file.id], have.modified >= file.modified { continue }
            byId[file.id] = file
        }
        return Array(byId.values.sorted { $0.modified > $1.modified }.prefix(limit))
    }

    /// Whether a transcript came from an interactive terminal session: its
    /// records carry `"entrypoint":"cli"` (headless runs say `sdk-cli`, Claude
    /// Desktop says `claude-desktop`). Read from the first few KB only; a file
    /// that says nothing is kept, since hiding a real session is worse than
    /// showing a stray one.
    static func ranInTerminal(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return true }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 32 * 1024)) ?? Data()
        for line in head.split(separator: UInt8(ascii: "\n")) {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let entry = obj["entrypoint"] as? String else { continue }
            return entry == "cli"
        }
        return true
    }

    /// The project's transcripts on disk: `<uuid>.jsonl`, non-empty. Anything
    /// else in there (agent files, stray notes) isn't a session you can resume.
    static func transcripts(slug: String, projectsDir: String) -> Found<TranscriptFile> {
        var found = Found<TranscriptFile>()
        guard let names = listing(projectsDir) else {
            found.unreadable = [projectsDir]
            return found
        }
        let fm = FileManager.default
        for dir in transcriptDirs(matching: slug, among: names) {
            let full = projectsDir + "/" + dir
            guard let files = listing(full) else {
                found.unreadable.append(full)
                continue
            }
            for file in files where file.hasSuffix(".jsonl") {
                let id = String(file.dropLast(".jsonl".count)).lowercased()
                guard UUID(uuidString: id) != nil,
                      let attrs = try? fm.attributesOfItem(atPath: full + "/" + file),
                      (attrs[.size] as? Int ?? 0) > 0,
                      let modified = attrs[.modificationDate] as? Date else { continue }
                found.items.append(TranscriptFile(id: id, path: full + "/" + file, modified: modified))
            }
        }
        return found
    }

    static func recentSessions(folder: String, projectsDir: String, excluding live: Set<String>,
                               limit: Int = 8) -> Found<RecentSession> {
        let all = transcripts(slug: transcriptSlug(folder), projectsDir: projectsDir)
        var found = Found<RecentSession>(unreadable: all.unreadable)
        // Headless runs (`claude -p`, the SDK) and Claude Desktop's own sessions
        // are not something to resume into a terminal, and here they outnumber
        // real sessions many to one, so they are skipped before the limit is
        // applied rather than after.
        let interactive = newest(all.items, excluding: live, limit: .max)
            .lazy.filter { ranInTerminal(path: $0.path) }.prefix(limit)
        found.items = interactive.map { file in
            let read = TranscriptReader.read(path: file.path)
            return RecentSession(id: file.id, modified: file.modified, title: read.title,
                                 lastPrompt: read.lastPrompt, lastActivity: read.lastActivity)
        }
        return found
    }

    // MARK: - Skills

    /// The lines between the opening `---` and the next one.
    static func frontmatter(_ text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }
        return lines[1..<end].joined(separator: "\n")
    }

    static func frontmatterName(_ block: String) -> String? {
        for line in block.split(separator: "\n") where line.hasPrefix("name:") {
            let value = line.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// The folder's own skills, then those of `claudeDir` and of the plugins
    /// under `pluginsDir` whose frontmatter matches the topic. Body text is not
    /// searched: "apply" alone is in fifteen of the fifty-odd here (git-push,
    /// wrap-up), none of them a job-search skill.
    ///
    /// `pluginsDir` is Claude Desktop's synced skills plugin
    /// (`<pluginsDir>/<account>/<space>/.claude-plugin/plugin.json`), which the
    /// terminal also runs as `/anthropic-skills:<name>`. Absent means no
    /// Desktop, not a failure.
    static func skills(projectRoot: String, claudeDir: String, pluginsDir: String? = nil,
                       topic: PinnedProject.Topic) -> Found<ProjectSkill> {
        func read(_ dir: String, isProject: Bool, plugin: String? = nil) -> Found<ProjectSkill> {
            var found = Found<ProjectSkill>()
            guard let names = listing(dir) else {
                found.unreadable = [dir]
                return found
            }
            for entry in names.sorted() {
                let file = dir + "/" + entry + "/SKILL.md"
                guard FileManager.default.fileExists(atPath: file) else { continue }
                guard let text = text(file) else {
                    found.unreadable.append(file)
                    continue
                }
                let block = frontmatter(text) ?? ""
                let name = frontmatterName(block) ?? entry
                if !isProject {
                    guard block.range(of: topic.about, options: [.regularExpression, .caseInsensitive]) != nil
                    else { continue }
                }
                found.items.append(ProjectSkill(name: name, isProject: isProject, plugin: plugin))
            }
            return found
        }
        var found = read(projectRoot + "/.claude/skills", isProject: true)
        var others = [read(claudeDir + "/skills", isProject: false)]
        if let pluginsDir, FileManager.default.fileExists(atPath: pluginsDir) {
            let manifests = find("plugin.json", under: pluginsDir, maxDepth: 4)
            found.unreadable += manifests.unreadable
            for manifest in manifests.paths where manifest.hasSuffix("/.claude-plugin/plugin.json") {
                guard let data = FileManager.default.contents(atPath: manifest),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let plugin = obj["name"] as? String else {
                    found.unreadable.append(manifest)
                    continue
                }
                let root = String(manifest.dropLast("/.claude-plugin/plugin.json".count))
                others.append(read(root + "/skills", isProject: false, plugin: plugin))
            }
        }
        // The same skill synced for two accounts shows once.
        var have = Set(found.items.map(\.command))
        for other in others {
            found.items += other.items.filter { have.insert($0.command).inserted }
            found.unreadable += other.unreadable
        }
        return found
    }

    // MARK: - Scheduled

    /// The folder's path or one of the words that mark it. Loose on purpose: a
    /// scheduler that names the project only by a word still belongs here.
    static func mentionsProject(_ text: String, folder: String, topic: PinnedProject.Topic) -> Bool {
        let lower = text.lowercased()
        return lower.contains(folder.lowercased()) || topic.words.contains { lower.contains($0) }
    }

    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private static func weekday(_ n: Int) -> String { weekdays[((n % 7) + 7) % 7] }

    private static func clock(hour: Int, minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }

    static func cronSchedule(_ expression: String) -> String {
        let f = expression.split(separator: " ").map(String.init)
        guard f.count == 5, let minute = Int(f[0]), let hour = Int(f[1]), f[3] == "*" else { return "cron " + expression }
        let time = clock(hour: hour, minute: minute)
        if f[2] == "*", f[4] == "*" { return "daily \(time)" }
        if f[2] == "*", let day = Int(f[4]) { return "\(weekday(day)) \(time)" }
        if f[4] == "*", let date = Int(f[2]) { return "day \(date) \(time)" }
        return "cron " + expression
    }

    static func launchdSchedule(_ plist: [String: Any]) -> String {
        func interval(_ seconds: Int) -> String {
            switch seconds {
            case ..<120: return "\(seconds)s"
            case ..<3600: return "\(seconds / 60) min"
            default: return "\(seconds / 3600) h"
            }
        }
        func calendar(_ entry: [String: Any]) -> String {
            let hour = entry["Hour"] as? Int
            let minute = entry["Minute"] as? Int ?? 0
            let day: String
            if let d = entry["Weekday"] as? Int { day = weekday(d) }
            else if let d = entry["Day"] as? Int { day = "day \(d)" }
            else { day = "daily" }
            guard let hour else { return "\(day) at :\(String(format: "%02d", minute)) past" }
            return "\(day) \(clock(hour: hour, minute: minute))"
        }
        let raw = plist["StartCalendarInterval"]
        let entries = (raw as? [[String: Any]]) ?? (raw as? [String: Any]).map { [$0] } ?? []
        if !entries.isEmpty {
            let shown = entries.prefix(3).map(calendar).joined(separator: ", ")
            return entries.count > 3 ? shown + " +\(entries.count - 3) more" : shown
        }
        if let seconds = plist["StartInterval"] as? Int { return "every " + interval(seconds) }
        if plist["KeepAlive"] != nil { return "kept running" }
        if plist["RunAtLoad"] as? Bool == true { return "at login" }
        return "on demand"
    }

    static func launchdJobs(agentsDir: String, folder: String, topic: PinnedProject.Topic) -> Found<ScheduledJob> {
        var found = Found<ScheduledJob>()
        guard let names = listing(agentsDir) else {
            found.unreadable = [agentsDir]
            return found
        }
        for file in names.sorted() where file.hasSuffix(".plist") {
            let path = agentsDir + "/" + file
            guard let data = FileManager.default.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else {
                found.unreadable.append(path)
                continue
            }
            let label = plist["Label"] as? String ?? String(file.dropLast(".plist".count))
            let searched = [label, (plist["ProgramArguments"] as? [String] ?? []).joined(separator: " "),
                            plist["WorkingDirectory"] as? String ?? ""].joined(separator: " ")
            guard mentionsProject(searched, folder: folder, topic: topic) else { continue }
            found.items.append(ScheduledJob(name: label, schedule: launchdSchedule(plist),
                                            source: "launchd", enabled: nil))
        }
        return found
    }

    /// Crontab lines that run something in or about the project.
    static func cronJobs(crontab: String, folder: String, topic: PinnedProject.Topic) -> Found<ScheduledJob> {
        var found = Found<ScheduledJob>()
        for raw in crontab.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), mentionsProject(line, folder: folder, topic: topic) else { continue }
            let special = line.hasPrefix("@")
            let needed = special ? 2 : 6
            let fields = line.split(maxSplits: needed - 1, omittingEmptySubsequences: true,
                                    whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if fields.count != needed {
                // `PATH=...` and the like are settings, not jobs.
                if !(fields.first?.contains("=") ?? false) { found.unreadable.append("crontab line: " + line.prefix(40)) }
                continue
            }
            let schedule = special ? fields[0] : cronSchedule(fields[0..<5].joined(separator: " "))
            found.items.append(ScheduledJob(name: String(fields[needed - 1].prefix(48)), schedule: schedule,
                                            source: "cron", enabled: true))
        }
        return found
    }

    /// Claude Desktop's scheduled tasks. They sit under
    /// `<base>/<kind>-sessions/<account>/<space>/scheduled-tasks.json`; the
    /// rest of the app-support folder is browser cache.
    static func desktopTasks(base: String, folder: String, topic: PinnedProject.Topic) -> Found<ScheduledJob> {
        var found = Found<ScheduledJob>()
        guard let kinds = listing(base) else {
            found.unreadable = [base]
            return found
        }
        var files: [String] = []
        for kind in kinds.sorted() where kind.hasSuffix("-sessions") {
            let hit = find("scheduled-tasks.json", under: base + "/" + kind, maxDepth: 3)
            files += hit.paths
            found.unreadable += hit.unreadable
        }
        var seen = Set<String>()
        for path in files {
            guard let data = FileManager.default.contents(atPath: path),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tasks = root["scheduledTasks"] as? [[String: Any]] else {
                found.unreadable.append(path)
                continue
            }
            for task in tasks {
                let id = task["id"] as? String ?? ""
                let name = task["displayName"] as? String ?? id
                let places = [task["cwd"] as? String ?? ""]
                    + (task["userSelectedFolders"] as? [String] ?? [])
                guard !id.isEmpty, seen.insert(id).inserted,
                      mentionsProject(([id, name] + places).joined(separator: " "), folder: folder, topic: topic) else { continue }
                found.items.append(ScheduledJob(
                    name: name,
                    schedule: (task["cronExpression"] as? String).map(cronSchedule) ?? "no schedule recorded",
                    source: "Desktop", enabled: task["enabled"] as? Bool))
            }
        }
        return found
    }

    /// `crontab -l`. nil when it could not be run; "" when there is no crontab,
    /// which it reports as an error of its own.
    static func readCrontab() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/crontab")
        task.arguments = ["-l"]
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do { try task.run() } catch { return nil }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let said = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        task.waitUntilExit()
        if task.terminationStatus == 0 { return text }
        return said.contains("no crontab") ? "" : nil
    }

    // MARK: - Workflows

    /// `.js` workflows: every one in the folder's own `.claude/workflows`, and
    /// those in `userDir` that mention the project (the user's are shared by
    /// every project, so a mention is what ties one to this).
    static func workflows(projectRoot: String, userDir: String, topic: PinnedProject.Topic) -> Found<ProjectWorkflow> {
        var found = Found<ProjectWorkflow>()
        func read(_ dir: String, needsMention: Bool) {
            guard let names = listing(dir) else {
                found.unreadable.append(dir)
                return
            }
            for file in names.sorted() where file.hasSuffix(".js") {
                let path = dir + "/" + file
                if needsMention {
                    guard let body = text(path) else {
                        found.unreadable.append(path)
                        continue
                    }
                    guard body.range(of: topic.about, options: [.regularExpression, .caseInsensitive]) != nil
                    else { continue }
                }
                found.items.append(ProjectWorkflow(name: String(file.dropLast(".js".count))))
            }
        }
        read(projectRoot + "/.claude/workflows", needsMention: false)
        read(userDir, needsMention: true)
        return found
    }

    // MARK: - Artifacts

    private static let skippedDirs: Set<String> = [".worktrees", "node_modules", ".git", ".venv"]

    /// Every `artifact.json` in the folder, up to `maxDepth` levels down, that
    /// records a URL. Only the file is read; nothing is fetched.
    static func artifacts(root: String, maxDepth: Int = 4) -> Found<ProjectArtifact> {
        var found = Found<ProjectArtifact>()
        let hit = find("artifact.json", under: root, maxDepth: maxDepth, skipping: skippedDirs)
        found.unreadable = hit.unreadable
        for path in hit.paths {
            let rel = String(path.dropFirst(root.count + 1))
            guard let data = FileManager.default.contents(atPath: path),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let url = (obj["url"] as? String)?.trimmingCharacters(in: .whitespaces),
                  let parsed = URL(string: url), parsed.scheme?.hasPrefix("http") == true else {
                found.unreadable.append(path)
                continue
            }
            let folder = ((rel as NSString).deletingLastPathComponent as NSString).lastPathComponent
            let title = (obj["title"] as? String) ?? (obj["name"] as? String)
            let name = title ?? (folder.isEmpty ? "Artifact" : folder)
            found.items.append(ProjectArtifact(title: name, url: url, path: path,
                                               summary: ProjectArtifact.summary(fromNote: obj["note"] as? String,
                                                                                title: name)))
        }
        return found
    }

    // MARK: - About

    static let instructionFiles = ["CLAUDE.md", "PROJECT-INSTRUCTIONS.md"]

    static let contextFiles = ["AGENTS.md", "STATUS.md", "TASKS.md", "README.md"]

    /// Desktop keeps no local list of a project's linked folders, but it records
    /// the folders each session was given. The newest record holding the root is
    /// the project's current set (2026-09-30: job search + job search/Resume/artifact,
    /// matching the project page's "2 folders").
    static func desktopFolders(root: String, spacesFiles: [String]) -> [String] {
        var newest: [String]?
        for file in spacesFiles {
            guard let data = FileManager.default.contents(atPath: file),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = obj["entries"] as? [[String: Any]] else { continue }
            // Appended as sessions start, so the last match is the newest.
            if let last = entries.last(where: { ($0["folders"] as? [String])?.contains(root) == true }) {
                newest = last["folders"] as? [String]
            }
        }
        guard let folders = newest else { return [root] }
        return [root] + folders.filter { $0 != root }
    }

    static func about(root: String, projectsDir: String, spacesFiles: [String] = []) -> ProjectAbout {
        var about = ProjectAbout()
        about.folders = desktopFolders(root: root, spacesFiles: spacesFiles)
        about.context = contextFiles.map { root + "/" + $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
        about.instructions = instructionFiles.map { root + "/" + $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
        about.memoryDir = projectsDir + "/" + transcriptSlug(root) + "/memory"
        if FileManager.default.fileExists(atPath: about.memoryDir) {
            about.memories = listing(about.memoryDir).map {
                $0.filter { $0.hasSuffix(".md") && $0 != "MEMORY.md" }.count
            }
        }
        return about
    }

    // MARK: - All of it

    static func loadExtras(root: String, topic: PinnedProject.Topic, home: String) -> ProjectExtras {
        var extras = ProjectExtras()
        extras.skills = skills(projectRoot: root, claudeDir: home + "/.claude",
                               pluginsDir: home + "/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin",
                               topic: topic)
        extras.workflows = workflows(projectRoot: root, userDir: home + "/.claude/workflows", topic: topic)
        extras.artifacts = artifacts(root: root)
        let sessionsBase = home + "/Library/Application Support/Claude/local-agent-mode-sessions"
        let spaces = (listing(sessionsBase) ?? []).flatMap { account in
            (listing(sessionsBase + "/" + account) ?? []).map { sessionsBase + "/" + account + "/" + $0 + "/remote-session-spaces.json" }
        }
        extras.about = about(root: root, projectsDir: home + "/.claude/projects", spacesFiles: spaces)
        var scheduled = launchdJobs(agentsDir: home + "/Library/LaunchAgents", folder: root, topic: topic)
        if let crontab = readCrontab() {
            scheduled.items += cronJobs(crontab: crontab, folder: root, topic: topic).items
        } else {
            scheduled.unreadable.append("crontab")
        }
        let desktop = desktopTasks(base: home + "/Library/Application Support/Claude", folder: root, topic: topic)
        scheduled.items += desktop.items
        scheduled.unreadable += desktop.unreadable
        extras.scheduled = scheduled
        return extras
    }
}
