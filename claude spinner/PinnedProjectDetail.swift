import SwiftUI
import AppKit

/// The pane for a pinned project: launch buttons, what is running in the
/// folder, its open tasks, sessions to resume, and what is connected to it
/// (skills, schedulers, workflows, artifacts). Read from disk while it is open.
struct PinnedProjectDetail: View {
    let project: PinnedProject
    /// Root sessions, as the sidebar lists them.
    let sessions: [SessionFeed]
    /// Every pending question, filtered here to this project's own sessions.
    let asks: [AskRequest]
    /// Where the feed files live, for the reply field to write into.
    let feedDir: URL
    /// Shared with the window: a reply and a session action report in one place.
    @Binding var notice: NoticeMessage?
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
    @State private var jobStats: JobStats?
    /// Desktop's "New session in <project>" box: a first prompt to start with.
    @State private var draft = ""
    /// What has been typed for each workflow step that takes an argument.
    @State private var arguments: [String: String] = [:]
    /// An artifact expanded to fill the pane in place of the dashboard.
    @State private var focused: ProjectArtifact?

    private static let shownTasks = 5
    @State private var idealHeight: CGFloat = 0

    private var live: [SessionFeed] { PinnedProject.liveSessions(in: project.path, sessions: sessions) }
    private var runs: (byStep: [String: [SessionFeed]], other: [SessionFeed]) { project.runs(among: live) }

    /// The questions this project's own sessions are waiting on, oldest first so
    /// the one that has been blocking longest is answered first.
    private var pending: [AskRequest] {
        let ids = Set(live.map(\.id))
        return asks.filter { ids.contains($0.sessionId) }
    }

    private static let sectionGap: CGFloat = 24
    private static let pagePadding: CGFloat = 20
    private static let gridMinimum: CGFloat = 220
    private static let gridSpacing: CGFloat = 12
    private static let railGap: CGFloat = 16
    private static let railWidth: CGFloat = 300
    /// Narrowest page that keeps the rail beside two columns of cards (Job
    /// pipeline beside Scout daemon). Below it the rail drops under the page.
    private static let railBesideMinWidth: CGFloat =
        2 * pagePadding + 2 * gridMinimum + gridSpacing + railGap + railWidth

    var body: some View {
        if let focused {
            ArtifactFullView(artifact: focused, backTitle: project.name) {
                withAnimation(.snappy) { self.focused = nil }
            }
        } else {
            dashboard
        }
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            // Above the scroll, not in it: inside, the title slid up under the opaque
            // toolbar strip and was drawn cut off at its top edge (seen 2026-09-30).
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(.system(size: 26, weight: .bold))
                Text(project.summary).font(.ui(12)).foregroundStyle(Color.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 20)
            // The page takes the pane's height rather than stopping where the
            // rail's last row ends: on a tall window that left a third of it
            // blank under both columns.

                GeometryReader { geo in
                    let fit = PaneFit.fit(available: geo.size.height, ideal: idealHeight)
                    let scale = fit.scale
                    
                    ScrollView(.vertical) {
                        let scaledHeight = idealHeight * scale
                        let frameHeight = max(geo.size.height, scaledHeight)
                        // The pane's own width, not width / scale: stacking makes the
                        // page taller, which shrinks the scale, which widens the layout
                        // past the threshold, which unstacks it -- a loop at the edge.
                        let railBeside = geo.size.width >= Self.railBesideMinWidth
                        // AnyLayout, not an if/else of stacks: the cards keep their
                        // state (typed links, open runs) when the window crosses over.
                        let columns = railBeside
                            ? AnyLayout(HStackLayout(alignment: .top, spacing: Self.railGap))
                            : AnyLayout(VStackLayout(alignment: .leading, spacing: Self.railGap))

                        columns {
                // Sections at their own height, not a TileGrid: a grid that stretches
                // each row to its tallest card left panels with a third of their
                // height empty. Only the cards that are controls stay cards.
                VStack(alignment: .leading, spacing: Self.sectionGap) {
                    topPicks
                    // What you run here, and in which order you run it. The run under
                    // a step carries a conversation and a reply field, so it is full
                    // width.
                    if !project.workflow.isEmpty { workflowCard }
                    if project.name == "Job Search" {
                        HStack(alignment: .top, spacing: Self.gridSpacing) {
                            jobPipelineCard.frame(maxWidth: .infinity)
                            scoutStatusCard.frame(width: 260)
                        }
                    }
                    // Directly under them: it carries a conversation and a reply
                    // field now, not a name and a word. Only the runs no step
                    // started; the rest are drawn under their step.
                    if !runs.other.isEmpty { liveCard }
                    if project.name == "Job Search" {
                        HStack(alignment: .top, spacing: Self.railGap) {
                            recentApplicationsCard.frame(width: 320)
                            tasksSection.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        tasksSection
                    }
                    recentSection
                    if let extras {
                        discoveryCard("Skills", extras.skills) { skills in
                            chips(skills) { skill in
                                chip(skill.name, symbol: "wand.and.stars",
                                     help: (skill.isProject ? "Project skill" : skill.plugin.map { "\($0) plugin skill" } ?? "User skill")
                                        + ": start a session that runs " + skill.command) {
                                    start([skill.command])
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
                        if !extras.artifacts.unreadable.isEmpty {
                            discoveryCard("Artifacts", Found<ProjectArtifact>(unreadable: extras.artifacts.unreadable)) { _ in
                                EmptyView()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                // Under the sections it takes its own height.
                rail.frame(width: railBeside ? Self.railWidth : nil)
                    .fixedSize(horizontal: false, vertical: !railBeside)
                }
                .padding(Self.pagePadding)
                // At least the pane's height, inside the fixed size below, so a
                // short page still fills the pane. A taller page is unaffected.
                .frame(minHeight: geo.size.height, alignment: .topLeading)
                .frame(width: geo.size.width / scale, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if abs(height - idealHeight) > 2 { idealHeight = height }
                }
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: frameHeight, alignment: .topLeading)
            }
            .scrollDisabled(!fit.scrolls)
            .scrollIndicators(fit.scrolls ? .automatic : .hidden)
        }
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
            let path = project.path, topic = project.topic
            while !Task.isCancelled {
                extras = await Task.detached(priority: .utility) {
                    ProjectDiscovery.loadExtras(root: path, topic: topic, home: NSHomeDirectory())
                }.value
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .task(id: project.id) {
            if project.name == "Job Search" {
                let path = project.path
                while !Task.isCancelled {
                    jobStats = await Task.detached(priority: .utility) { Self.readJobStats(in: path) }.value
                    recentApplications = await Task.detached(priority: .utility) { Self.readRecentApplications(in: path) }.value
                    scoutStatus = await Task.detached(priority: .utility) { Self.readScoutStatus() }.value
                    try? await Task.sleep(for: .seconds(30))
                }
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

    /// The first row: what you can start here, then what the project has
    /// published, as hero cards of one size. The prompt field stays under it,
    /// because a card cannot hold a text field.
    private var topPicks: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Top picks")
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: HeroMetrics.gap) {
                    LaunchHeroCard(symbol: "plus",
                                   eyebrow: (project.path as NSString).abbreviatingWithTildeInPath,
                                   title: "New session",
                                   hint: "Start Claude Code in \(project.path)") { start([]) }
                    if let quick = project.quickStart {
                        LaunchHeroCard(symbol: quick.systemImage, eyebrow: "Quick start", title: quick.label,
                                       hint: "Start a session that runs \(quick.prompt)") {
                            start(project.quickStartArgs ?? [quick.prompt])
                        }
                    }
                    if let extras {
                        ForEach(Array(extras.artifacts.items.enumerated()), id: \.offset) { _, artifact in
                            ArtifactHeroCard(artifact: artifact) {
                                withAnimation(.snappy) { focused = artifact }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            TextField(text: $draft, prompt: Text("New session in \(project.name)").foregroundStyle(Color.label)) {
                Text("New session in \(project.name)")
            }
                .textFieldStyle(.plain).font(.ui(12))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.label.opacity(0.3)))
                .onSubmit {
                    let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !prompt.isEmpty else { return }
                    start([prompt])
                    draft = ""
                }
                .help("Return starts Claude Code in \(project.path) with this as its first prompt")
            if let failure {
                Text(failure).font(.ui(10)).foregroundStyle(Color.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Desktop's right-hand panel, from the files behind it: one row per part
    /// of the project, each with what it holds and a way to open it.
    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let extras {
                let about = extras.about
                railRow("Instructions", symbol: "doc.text",
                        detail: about.instructions.isEmpty ? "none"
                            : about.instructions.map(Self.name).joined(separator: ", "),
                        action: about.instructions.first.map { ("Open", $0) })
                railRow("Context", symbol: "doc.on.doc",
                        detail: about.context.count == 1 ? "1 file" : "\(about.context.count) files",
                        note: "Files uploaded in Claude Desktop stay there.") {
                    ForEach(about.context, id: \.self) { railItem(Self.name($0), path: $0) }
                }
                railRow("Folder", symbol: "folder",
                        detail: about.folders.count == 1 ? "1 folder" : "\(about.folders.count) folders") {
                    ForEach(about.folders, id: \.self) { folder in
                        railItem(folder == project.path ? Self.name(folder)
                                    : String(folder.dropFirst(project.path.count + 1)),
                                 path: folder)
                    }
                    if !about.foldersUnreadable.isEmpty {
                        Text("Couldn't read " + about.foldersUnreadable.joined(separator: ", "))
                            .font(.ui(10)).foregroundStyle(Color.attention)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                railRow("Memory", symbol: "brain",
                        detail: about.memories.map { $0 == 1 ? "1 memory" : "\($0) memories" } ?? "couldn't read",
                        action: about.memories.map { $0 > 0 ? ("View", about.memoryDir) : nil } ?? nil)
                railRow("Scheduled", symbol: "clock",
                        detail: extras.scheduled.items.isEmpty ? "none"
                            : extras.scheduled.items.count == 1 ? "1 task" : "\(extras.scheduled.items.count) tasks") {
                    ForEach(Array(extras.scheduled.items.enumerated()), id: \.offset) { _, job in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(job.name).font(.ui(11)).lineLimit(1).truncationMode(.middle)
                            Text(job.schedule + (job.enabled == false ? " · off" : "") + " · " + job.source)
                                .font(.ui(10)).foregroundStyle(Color.label).lineLimit(1)
                        }
                    }
                    if !extras.scheduled.unreadable.isEmpty {
                        Text("Couldn't read " + extras.scheduled.unreadable.joined(separator: ", "))
                            .font(.ui(10)).foregroundStyle(Color.attention)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("Reading the project…").font(.ui(10)).foregroundStyle(Color.label)
                    .padding(.vertical, 12)
            }
            // The rows keep their heights and the card takes the rest, rather
            // than the card ending mid-pane with blank window under it.
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .detailCard()
        .frame(maxHeight: .infinity)
    }

    private nonisolated static func name(_ path: String) -> String { (path as NSString).lastPathComponent }

    /// A rail row: icon, title and a dim summary, an optional action at the
    /// right, and the items under it. Rows are ruled apart as Desktop's are.
    private func railRow<Items: View>(_ title: String, symbol: String, detail: String,
                                      action: (label: String, path: String)? = nil, note: String? = nil,
                                      @ViewBuilder items: () -> Items = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 16).foregroundStyle(Color.label)
                Text(title).font(.ui(12)).fixedSize()
                Text(detail).font(.ui(10)).foregroundStyle(Color.label).lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                if let action {
                    Button(action.label) { NSWorkspace.shared.open(URL(fileURLWithPath: action.path)) }
                        .buttonStyle(.attentionLink).font(.ui(11))
                        .help("Open \(action.path)")
                }
            }
            VStack(alignment: .leading, spacing: 4) { items() }
                .padding(.leading, 24)
            if let note {
                Text(note).font(.ui(10)).foregroundStyle(Color.label).padding(.leading, 24)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func railItem(_ label: String, path: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.ui(11)).lineLimit(1).truncationMode(.middle).layoutPriority(1)
            Spacer(minLength: 4)
            Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                .buttonStyle(.attentionLink).font(.ui(10))
                .help("Open \(path)")
        }
    }

    /// The project's routine, in the order it is worked. The questions a run is
    /// waiting on live in the Running now card, beside the run that asked them.
    private var workflowCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle("Workflow")
                Spacer(minLength: 4)
                waiting(on: runs.byStep.values.flatMap { $0 })
            }
            ForEach(project.workflow) { step in
                self.step(step)
                // Under the step that started it, so a run parked on "fill or
                // skip?" is answered beside what it is doing.
                ForEach(runs.byStep[step.id] ?? []) { session in
                    // Tinted, as the fields are, so the next step reads as the next
                    // step and not as more of this run's conversation.
                    run(session, underStep: true)
                        .padding(10)
                        .background(Color.secondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.leading, 20)
                }
            }
            Spacer(minLength: 0)
        }
        .detailCard()
        .frame(maxHeight: .infinity)
    }

    private func step(_ step: PinnedProject.Step) -> some View {
        let prompt = step.prompt(with: arguments[step.id] ?? "")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(step.label, systemImage: step.systemImage).font(.ui(11)).fixedSize()
                Spacer(minLength: 4)
                Button("Start") { start(step) }
                    .buttonStyle(.bordered).font(.ui(11))
                    .disabled(prompt == nil)
                    .help(prompt.map { "Start a session in \(project.name) running \($0)" }
                          ?? "\(step.argument ?? "") first")
            }
            Text(step.detail).font(.ui(10)).foregroundStyle(Color.label)
                .fixedSize(horizontal: false, vertical: true)
            if let placeholder = step.argument {
                // Started without it the skill only asks for it in the terminal,
                // which is the switch this card exists to avoid.
                TextField(text: Binding(get: { arguments[step.id] ?? "" }, set: { arguments[step.id] = $0 }),
                          prompt: Text(placeholder).foregroundStyle(Color.label)) { Text(placeholder) }
                    .textFieldStyle(.plain).font(.ui(11))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onSubmit { start(step) }
            }
        }
    }

    /// Cleared once started, as the Start card's field is: left filled, a second
    /// press opened a second session on the same link.
    private func start(_ step: PinnedProject.Step) {
        guard let prompt = step.prompt(with: arguments[step.id] ?? "") else { return }
        start(["--name", step.sessionName(in: project), prompt])
        arguments[step.id] = nil
    }

    /// What the project's runs are actually doing, in full: the status line, the
    /// last exchange, whatever question is waiting, and a field to answer in.
    ///
    /// The pinned pane used to say only a name and a word here, which told you
    /// to go and look somewhere else. Everything below is the same view the
    /// session's own pane draws, so there is nothing to go and look at.
    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Running now")
                Spacer(minLength: 4)
                waiting(on: runs.other)
            }
            ForEach(runs.other) { session in run(session) }
            Spacer(minLength: 0)
        }
        .detailCard()
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private func waiting(on sessions: [SessionFeed]) -> some View {
        let ids = Set(sessions.map(\.id))
        let count = pending.filter { ids.contains($0.sessionId) }.count
        if count > 0 {
            Text(count == 1 ? "1 waiting on you" : "\(count) waiting on you")
                .font(.ui(10)).foregroundStyle(Color.attention)
        }
    }

    private func run(_ session: SessionFeed, underStep: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { select(session.id) } label: { liveHeader(session, named: !underStep) }
                .buttonStyle(.plain)
                .help("Open this session's own pane")
            // The question boxes, with their real options: a run parked
            // on "fill or skip?" is answered here rather than in
            // whichever terminal it happens to be in.
            ForEach(pending.filter { $0.sessionId == session.id }, id: \.req) { ask in
                AskCard(ask: ask)
            }
            ConversationCard(session: session, feedDir: feedDir, notice: $notice)
        }
    }

    /// `named` false under a step: its name is "Job Search: <step>", said again
    /// right under the step's own label.
    private func liveHeader(_ session: SessionFeed, named: Bool = true) -> some View {
        HStack(spacing: 6) {
            Text(session.isWorking ? Spinner.frame(at: Date()) : Spinner.idle)
                .font(.claudeMono(11)).frame(width: 14)
                .foregroundStyle(session.isBlockedOnYou ? Color.attention
                                    : session.isWorking ? Color.claude : Color.secondary)
            if named { Text(session.distinctName).font(.claudeMono(11)).lineLimit(1).layoutPriority(1) }
            Text(session.statusLabel).font(.ui(10)).lineLimit(1)
                .foregroundStyle(session.isBlockedOnYou ? Color.attention : Color.label)
            Spacer(minLength: 4)
            Text(liveDetail(session)).font(.ui(10)).foregroundStyle(Color.label).lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    /// Context and elapsed time for a running session, each left out when the
    /// statusLine has not reported it rather than printed as a dash.
    private func liveDetail(_ session: SessionFeed) -> String {
        var parts: [String] = []
        if let tokens = session.contextTokens {
            if let window = session.stats.contextWindowSize, window > 0 {
                parts.append("\(Color.contextPercent(tokens: tokens, window: window))% context")
            } else {
                parts.append("\(StatFormat.compactCount(tokens)) context")
            }
        }
        if let wall = session.stats.wallSeconds { parts.append(StatFormat.duration(wall)) }
        return parts.joined(separator: " · ")
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // The chevron is only here when there is more to open: the same
                // file the "+N more" link below opens.
                if case .loaded(let open, _, let path) = tasks, open.count > Self.shownTasks {
                    SectionTitle("Tasks", opens: "Open \(path)") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                } else {
                    SectionTitle("Tasks")
                }
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
                    .buttonStyle(.attentionLink).font(.ui(10))
                    .help("Open \(path)")
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Recent sessions")
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
                if !recent.items.isEmpty {
                    SessionShelf(sessions: recent.items, symbol: project.tileSymbol) { id in
                        start(["--resume", id])
                    }
                }
            } else {
                Text("Reading sessions…").font(.ui(10)).foregroundStyle(Color.label)
            }
        }
    }

    /// A discovery card. Nothing at all when the source was empty; the items
    /// when it had some; and a line saying what couldn't be read, so an
    /// unreadable source never passes for an empty one.
    @ViewBuilder private func discoveryCard<T: Equatable, Content: View>(
        _ title: String, _ found: Found<T>, @ViewBuilder content: ([T]) -> Content
    ) -> some View {
        if !found.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title)
                if !found.items.isEmpty { content(found.items) }
                if !found.unreadable.isEmpty {
                    Text("Couldn't read " + found.unreadable.joined(separator: ", "))
                        .font(.ui(10)).foregroundStyle(Color.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func chips<T, Chip: View>(_ items: [T], @ViewBuilder chip: @escaping (T) -> Chip) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in chip(item) }
        }
    }

    nonisolated struct JobStats: Codable, Equatable {
        var scouted: Int?
        var needs_manual: Int?
        var rejected: Int?
        var applied: Int?
        var queued: Int?
        var interview: Int?
    }

    private nonisolated static func readJobStats(in path: String) -> JobStats? {
        let pythonScript = "import sys, json; sys.path.append('.'); import db; db.init('JobData'); import pg; c = db._conn(); cur = c.execute('SELECT status, count(*) FROM jobs GROUP BY status'); print(json.dumps(dict(cur.fetchall())))"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path + "/.venv/bin/python3")
        process.arguments = ["-c", pythonScript]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return try JSONDecoder().decode(JobStats.self, from: data)
        } catch {
            return nil
        }
    }

    private var jobPipelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Job pipeline")
                Spacer()
                Button {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    task.arguments = ["-a", "Ghostty", "--args", "-e", "bash", "-c", "cd '\(project.path)/apply-tui' && cargo run"]
                    try? task.run()
                } label: {
                    Label("Apply TUI", systemImage: "terminal")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            if let stats = jobStats {
                HStack(spacing: 16) {
                    pipelineMetric(label: "Scouted", value: stats.scouted ?? 0, color: .secondary)
                    Spacer()
                    pipelineMetric(label: "Triage", value: stats.needs_manual ?? 0, color: .attention)
                    Spacer()
                    pipelineMetric(label: "Queued", value: stats.queued ?? 0, color: .claude)
                    Spacer()
                    pipelineMetric(label: "Applied", value: stats.applied ?? 0, color: .green)
                    Spacer()
                    pipelineMetric(label: "Interview", value: stats.interview ?? 0, color: .purple)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Loading pipeline stats...").font(.ui(11)).foregroundStyle(Color.secondary)
            }
        }
        .detailCard()
    }

    struct RecentApplication: Codable, Equatable, Identifiable {
        var id: String { title + company }
        let title: String
        let company: String
        let applied_at: String
    }

    @State private var recentApplications: [RecentApplication] = []
    @State private var scoutStatus: Bool = false

    private nonisolated static func readRecentApplications(in path: String) -> [RecentApplication] {
        let pythonScript = "import sys, json; sys.path.append('.'); import db; db.init('JobData'); import pg; c = db._conn(); cur = c.execute(\"SELECT title, company, applied_at FROM jobs WHERE status = 'applied' ORDER BY applied_at DESC LIMIT 5\"); print(json.dumps([{'title': r[0], 'company': r[1], 'applied_at': r[2]} for r in cur.fetchall()]))"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path + "/.venv/bin/python3")
        process.arguments = ["-c", pythonScript]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return try JSONDecoder().decode([RecentApplication].self, from: data)
        } catch {
            return []
        }
    }

    private nonisolated static func readScoutStatus() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "python.*scout.py"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func toggleScout() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        if scoutStatus {
            process.arguments = ["-a", "Ghostty", "--args", "-e", "bash", "-c", "pkill -f 'python.*scout.py'"]
        } else {
            process.arguments = ["-a", "Ghostty", "--args", "-e", "bash", "-c", "cd '\(project.path)' && source .venv/bin/activate && python scout.py"]
        }
        try? process.run()
    }

    private var scoutStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Scout daemon")
            HStack {
                Circle()
                    .fill(scoutStatus ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(scoutStatus ? "Running" : "Stopped")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(scoutStatus ? .primary : .secondary)
                Spacer()
                Button {
                    toggleScout()
                    // Optimistic update
                    scoutStatus.toggle()
                } label: {
                    Text(scoutStatus ? "Stop" : "Start")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered).controlSize(.mini)
            }
        }
        .detailCard()
    }

    private var recentApplicationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Recent applications")
            if recentApplications.isEmpty {
                Text("No recent applications.").font(.ui(11)).foregroundStyle(Color.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(recentApplications) { app in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                                .font(.system(size: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.title)
                                    .font(.ui(12))
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.label)
                                Text("\(app.company) • \(app.applied_at.prefix(10))")
                                    .font(.ui(10))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
            }
        }
        .detailCard()
    }

    private func pipelineMetric(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text("\(value)").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.ui(11)).foregroundStyle(Color.secondary).textCase(.uppercase)
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

/// A section header on the pinned-project page: bold, sentence case, in the
/// primary ink. The "›" is the Music red, which is a mark colour only (it
/// measures 3.5:1 on the pane, but 4.13:1 as text), and it appears only when the
/// header opens something. `CardTitle` stays the uppercase label the session
/// pane uses.
struct SectionTitle: View {
    let text: String
    var help: String?
    var action: (() -> Void)?

    init(_ text: String) { self.text = text }
    init(_ text: String, opens help: String, action: @escaping () -> Void) {
        self.text = text
        self.help = help
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(text).font(.ui(15)).fontWeight(.bold)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.Kit.musicAccent)
                }
            }
            .buttonStyle(.plain)
            .help(help ?? "")
            .accessibilityLabel(text)
            .accessibilityHint(help ?? "")
        } else {
            Text(text).font(.ui(15)).fontWeight(.bold).accessibilityAddTraits(.isHeader)
        }
    }
}
