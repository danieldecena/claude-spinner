import SwiftUI
import AppKit

/// The pane for a pinned project: launch buttons, what is running in the
/// folder, its open tasks, sessions to resume, and what is connected to it
/// (skills, schedulers, workflows, artifacts). Read from disk while it is open.
struct PinnedProjectDetail: View {
    let project: PinnedProject
    /// Root sessions, as the sidebar lists them.
    let sessions: [SessionFeed]
    /// Selects a live session's row.
    let select: (String) -> Void

    private enum TasksState: Equatable {
        case loading, missing, unreadable
        case loaded(open: [String], done: Int, path: String)
    }

    @State private var tasks = TasksState.loading
    @State private var recent: Found<RecentSession>?
    @State private var extras: ProjectExtras?
    @State private var failure: String?

    private static let shownTasks = 5

    private var live: [SessionFeed] { PinnedProject.liveSessions(in: project.path, sessions: sessions) }

    var body: some View {
        ScrollView {
            // A dashboard: the same tile grid as a session's pane, so the two
            // read as one app. Launch and tasks share the top row, what ran and
            // what can be run the next, and each artifact takes a full row.
            TileGrid(minimum: 220, spacing: 12) {
                launchCard.tileSpan(1)
                tasksCard.tileSpan(2)
                recentCard.tileSpan(2)
                if let extras {
                    discoveryCard("Skills", extras.skills) { skills in
                        chips(skills) { skill in
                            chip(skill.name, symbol: "wand.and.stars",
                                 help: skill.isProject ? "Project skill" : "User skill") {
                                start(["/" + skill.name])
                            }
                        }
                    }
                }
                if !live.isEmpty { liveCard.tileSpan(1) }
                if let extras {
                    discoveryCard("Scheduled", extras.scheduled) { jobs in
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(jobs.enumerated()), id: \.offset) { _, job in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.name).font(.ui(11)).lineLimit(1).truncationMode(.middle)
                                    Text(job.schedule + (job.enabled == false ? " · off" : "") + " · " + job.source)
                                        .font(.ui(10)).foregroundStyle(Color.label).lineLimit(1)
                                }
                            }
                        }
                    }
                    discoveryCard("Workflows", extras.workflows) { workflows in
                        chips(workflows) { workflow in
                            chip(workflow.name, symbol: "point.3.connected.trianglepath.dotted",
                                 help: "Start a session that runs this workflow") {
                                start(["Run the workflow \(workflow.name) using the Workflow tool"])
                            }
                        }
                    }
                    ForEach(Array(extras.artifacts.items.enumerated()), id: \.offset) { _, artifact in
                        ArtifactCard(artifact: artifact)
                    }
                    if !extras.artifacts.unreadable.isEmpty {
                        discoveryCard("Artifacts", Found<ProjectArtifact>(unreadable: extras.artifacts.unreadable)) { _ in
                            EmptyView()
                        }
                        .tileSpan(3)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: project.id) {
            let path = project.path
            while !Task.isCancelled {
                tasks = await Task.detached(priority: .utility) { Self.readTasks(in: path) }.value
                try? await Task.sleep(for: .seconds(5))
            }
        }
        // Keyed on the live ids: a session that starts or ends changes which
        // transcripts count as "past" straight away, not at the next tick.
        .task(id: live.map(\.id).sorted().joined(separator: ",")) {
            let path = project.path
            let liveIds = Set(live.map(\.id))
            let projects = NSHomeDirectory() + "/.claude/projects"
            while !Task.isCancelled {
                recent = await Task.detached(priority: .utility) {
                    ProjectDiscovery.recentSessions(folder: path, projectsDir: projects, excluding: liveIds)
                }.value
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .task(id: project.id) {
            let path = project.path
            while !Task.isCancelled {
                extras = await Task.detached(priority: .utility) {
                    ProjectDiscovery.loadExtras(root: path, home: NSHomeDirectory())
                }.value
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private nonisolated static func readTasks(in path: String) -> TasksState {
        guard let root = Suggestion.tasksRoot(startingAt: path) else { return .missing }
        let file = root + "/TASKS.md"
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return .unreadable }
        let parsed = Suggestion.tasks(inTasksFile: text)
        return .loaded(open: parsed.open, done: parsed.done, path: file)
    }

    // MARK: - Cards

    private var launchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(project.name)
            Text(project.path).font(.claudeMono(10)).foregroundStyle(Color.label)
                .lineLimit(1).truncationMode(.middle)
            HStack(spacing: 8) {
                Button { start([]) } label: { Label("New session", systemImage: "plus") }
                    .help("Start Claude Code in \(project.path)")
                Button { start([PinnedProject.applyNextJob]) } label: {
                    Label("Apply next job", systemImage: "paperplane")
                }
                .help("Start a session that runs \(PinnedProject.applyNextJob)")
            }
            .buttonStyle(.glass).font(.ui(11))
            if let failure {
                Text(failure).font(.ui(10)).foregroundStyle(Color.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .detailCard()
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("Running now")
            ForEach(live) { session in
                Button { select(session.id) } label: {
                    HStack(spacing: 6) {
                        Text(session.distinctName).font(.claudeMono(11)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(session.statusLabel).font(.ui(10)).lineLimit(1)
                            .foregroundStyle(session.isBlockedOnYou ? Color.attention : Color.label)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open this session")
            }
        }
        .detailCard()
    }

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CardTitle("Tasks")
                Spacer(minLength: 4)
                if case .loaded(let open, let done, _) = tasks {
                    Text("\(open.count) open · \(done) done").font(.ui(10)).foregroundStyle(Color.label)
                }
            }
            switch tasks {
            case .loading:
                Text("Reading TASKS.md…").font(.ui(10)).foregroundStyle(Color.label)
            case .missing:
                Text("No TASKS.md in this folder.").font(.ui(10)).foregroundStyle(Color.label)
            case .unreadable:
                Text("Couldn't read TASKS.md.").font(.ui(10)).foregroundStyle(Color.attention)
            case .loaded(let open, _, let path):
                if open.isEmpty {
                    Text("Nothing open in TASKS.md.").font(.ui(10)).foregroundStyle(Color.label)
                }
                ForEach(Array(open.prefix(Self.shownTasks).enumerated()), id: \.offset) { _, title in
                    Label { Text(title) } icon: {
                        Circle().fill(Color.label).frame(width: 4, height: 4)
                    }
                    .font(.ui(11)).lineLimit(1).truncationMode(.tail)
                    .help(title)
                }
                if open.count > Self.shownTasks {
                    Button("+\(open.count - Self.shownTasks) more") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    .buttonStyle(.link).font(.ui(10))
                    .help("Open \(path)")
                }
            }
        }
        .detailCard()
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("Recent sessions")
            if let recent {
                if !recent.unreadable.isEmpty {
                    Text("Couldn't read " + recent.unreadable.joined(separator: ", "))
                        .font(.ui(10)).foregroundStyle(Color.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if recent.items.isEmpty && recent.unreadable.isEmpty {
                    Text("No earlier sessions on disk for this folder.")
                        .font(.ui(10)).foregroundStyle(Color.label)
                }
                ForEach(recent.items) { session in
                    HStack(spacing: 8) {
                        Text(session.headline).font(.ui(11)).lineLimit(1).truncationMode(.tail)
                            .help(session.lastPrompt ?? session.headline)
                        Spacer(minLength: 4)
                        Text(session.when.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                            .font(.ui(10)).foregroundStyle(Color.label).lineLimit(1)
                        Button("Resume") { start(["--resume", session.id]) }
                            .buttonStyle(.glass).font(.ui(10))
                            .help("claude --resume \(session.id)")
                    }
                }
            } else {
                Text("Reading sessions…").font(.ui(10)).foregroundStyle(Color.label)
            }
        }
        .detailCard()
    }

    /// A discovery card. Nothing at all when the source was empty; the items
    /// when it had some; and a line saying what couldn't be read, so an
    /// unreadable source never passes for an empty one.
    @ViewBuilder private func discoveryCard<T: Equatable, Content: View>(
        _ title: String, _ found: Found<T>, @ViewBuilder content: ([T]) -> Content
    ) -> some View {
        if !found.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(title)
                if !found.items.isEmpty { content(found.items) }
                if !found.unreadable.isEmpty {
                    Text("Couldn't read " + found.unreadable.joined(separator: ", "))
                        .font(.ui(10)).foregroundStyle(Color.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .detailCard()
        }
    }

    private func chips<T, Chip: View>(_ items: [T], @ViewBuilder chip: @escaping (T) -> Chip) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in chip(item) }
        }
    }

    private func chip(_ label: String, symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol).font(.ui(10)).lineLimit(1)
        }
        .buttonStyle(.glass)
        .help(help)
    }

    private func start(_ args: [String]) {
        failure = nil
        let path = project.path
        Task {
            let error = await Task.detached(priority: .userInitiated) {
                NewSession.launch(in: path, claudeArgs: args)
            }.value
            failure = error.map { "Couldn't open Ghostty: \($0)" }
        }
    }
}
