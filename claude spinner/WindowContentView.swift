import SwiftUI
import AppKit
import Combine

/// The window surface: a sidebar of sessions and a detail pane for the selected
/// one.
///
/// Deliberately not the popover panel with more room. The panel is a glance —
/// one line per session, sized to a menu-bar dropdown. This is the surface for
/// everything that does not fit in a glance or on a notification banner: the
/// full text of a question with all its options and their descriptions, the
/// multi-question and multiSelect asks `ask.sh` passes through to the terminal
/// precisely because a banner has one tap, and a reply field.
struct WindowContentView: View {
    @ObservedObject var feed: FeedWatcher
    @ObservedObject private var asks = AskInbox.shared
    @StateObject private var install = InstallState()
    /// The window opens on the Home dashboard rather than guessing a session.
    @State private var selection: String? = HomeTab.tag
    @State private var sidebarVisible = true
    /// The last session action's outcome. Set by the toolbar, shown in the
    /// conversation card; cleared on a new selection so a notice about one
    /// session is never read as about the next.
    @State private var actionNotice: NoticeMessage?
    /// The selected session's repo, read once here so the suggestion can be
    /// worked out once and handed to every card that might own its button.
    @State private var gitSnapshot: GitSnapshot?
    /// How many open items the selected repo's TASKS.md has, re-read with the
    /// snapshot. Counted when the file is read, not when it is asked for: the
    /// suggestion inputs are built several times per render and the file is 20KB.
    @State private var projectOpenTasks: Int?
    @State private var wrappedUp = false
    /// Each project's TASKS.md, read here because both the sidebar and the Home
    /// dashboard list it.
    @State private var tasks: [String: (open: [String], done: Int, path: String)] = [:]
    /// Which sessions are on a timed /goal run, for the rows that mark it.
    @StateObject private var goals = GoalWatcher()

    private var suggestionInput: Suggestion.Input? {
        guard let session = selected else { return nil }
        return .init(
            git: gitSnapshot,
            contextPercent: session.stats.contextUsedPercent,
            contextTokens: session.contextTokens,
            atPrompt: session.isAtPrompt,
            idleFor: session.updated.map { Date().timeIntervalSince($0) },
            fiveHourPct: feed.usageFiveHourPct,
            fiveHourElapsed: feed.usageFiveHourElapsed,
            installed: Set(installedShortcuts.map(\.command)),
            linesChanged: session.stats.linesAdded.map { $0 + (session.stats.linesRemoved ?? 0) },
            todoTotal: session.todoTotal,
            todoDone: session.todoDone,
            projectOpenTasks: projectOpenTasks,
            wrappedUp: wrappedUp)
    }

    private var suggestion: Suggestion? { suggestionInput.flatMap(Suggestion.next) }
    private var skillPick: Suggestion? { suggestionInput.flatMap(Suggestion.skill) }

    private var tasksFolders: [String: String] {
        var folders: [String: String] = [:]
        for session in roots.sorted(by: { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }) {
            let key = "project:" + session.projectName
            if folders[key] == nil {
                folders[key] = session.cwd
            }
        }
        return folders
    }

    private var tasksKey: String {
        tasksFolders.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
    }

    /// Roots only. Children are listed under their parent in the sidebar.
    private var roots: [SessionFeed] {
        feed.sessions.filter { $0.parentSessionId == nil }
    }

    /// What to show before anything is clicked.
    ///
    /// Two earlier versions of this were wrong in the same way — they opened on
    /// whatever happened to sort first, which is reliably a session whose
    /// statusLine hasn't reported, so the pane rendered two rows and looked
    /// broken. Order: something waiting on a person, then the most recently
    /// active session that actually has numbers to show, then anything.
    private var selected: SessionFeed? {
        Self.resolveSelection(selection, roots: roots, asks: asks.pending)
    }

    /// nil for a pinned project's tag: that pane is not a session, and falling
    /// through to the default here would put a session's toolbar, git probe and
    /// transcript loops behind the project's pane.
    static func resolveSelection(_ selection: String?, roots: [SessionFeed], asks: [AskRequest]) -> SessionFeed? {
        if HomeTab.isHomeTag(selection) || AppKitTab.isTag(selection)
            || PinnedProject.isPinnedTag(selection) { return nil }
        if let selection, let picked = roots.first(where: { $0.id == selection }) { return picked }
        return defaultSelection(roots: roots, asks: asks)
    }

    static func defaultSelection(roots: [SessionFeed], asks: [AskRequest]) -> SessionFeed? {
        let asked = Set(asks.map(\.sessionId))
        if let waiting = roots.first(where: { asked.contains($0.id) || $0.isBlockedOnYou }) {
            return waiting
        }
        let byRecency = roots.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
        // `model` is the cheapest proof a statusLine has run for this session,
        // and a statusLine is what fills the whole detail pane.
        return byRecency.first { $0.model != nil } ?? byRecency.first
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            // The pane's ground is the detail's alone: behind the sidebar it would
            // paint over the window's material.
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.pane)
        }
        // Across both columns, not just the detail pane: the toolbar acts on the
        // selected session wherever you are. Its strip is opaque edge to edge; a
        // strip half blur and half pane put a seam through the reply field.
        .safeAreaInset(edge: .top, spacing: 0) {
            WindowToolbar(session: selected, feedDir: feed.feedDirectory,
                          sidebarVisible: $sidebarVisible, suggestion: suggestion,
                          notice: $actionNotice)
                // Opaque over the detail only: over the sidebar it would be a pane-
                // coloured bar across the see-through column's top.
                .background {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: sidebarVisible ? 250 : 0)
                        Color.pane
                    }
                }
                // Rebuilt per session so a half-typed reply or a notice about one
                // session can never be sent to, or read as about, the next.
                .id(selected?.id)
        }
        // The window has no title bar (see showMainWindow), so the content owns
        // the top edge instead of leaving the bar's height empty above it.
        // This must come AFTER safeAreaInset, so the entire group (content + toolbar)
        // ignores the native title bar safe area, placing the toolbar at the very top.
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: selected?.id) { actionNotice = nil }
        .task(id: roots.map(\.id).joined(separator: "|")) {
            await goals.track(roots.map { (id: $0.id, pid: $0.pid) })
        }
        // Keyed on the folders, not the sections: a section's id is its project
        // name, and two sessions can swap folders under one.
        .task(id: tasksKey) {
            while !Task.isCancelled {
                let folders = tasksFolders
                tasks = await Task.detached(priority: .utility) {
                    folders.reduce(into: [:]) { out, entry in
                        if let root = Suggestion.tasksRoot(startingAt: entry.value),
                           let text = try? String(contentsOfFile: root + "/TASKS.md", encoding: .utf8) {
                            let file = Suggestion.tasks(inTasksFile: text)
                            out[entry.key] = (file.open, file.done, root + "/TASKS.md")
                        }
                    }
                }.value
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .task(id: selected?.cwd) {
            gitSnapshot = nil
            projectOpenTasks = nil
            guard let cwd = selected?.cwd else { return }
            while !Task.isCancelled {
                gitSnapshot = await GitProbe.shared.snapshot(for: cwd)
                let root = gitSnapshot?.toplevel ?? cwd
                projectOpenTasks = (try? String(contentsOfFile: root + "/TASKS.md", encoding: .utf8))
                    .flatMap(Suggestion.openTasks(inTasksFile:))
                try? await Task.sleep(for: .seconds(5))
            }
        }
        // Per session, not per folder: two sessions can share a cwd and only one
        // of them wrapped up.
        .task(id: selected?.id) {
            wrappedUp = false
            while !Task.isCancelled {
                if let path = selected?.stats.transcriptPath {
                    wrappedUp = await Task.detached(priority: .utility) {
                        TranscriptReader.read(path: path).wrappedUp
                    }.value
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// A full-height source list over the window's own sidebar material, like
    /// Music's: the desktop shows through it. An earlier version was an opaque
    /// card inset like the detail pane's, because a clear panel read as a second
    /// design beside the cards; the Music look (2026-09-30) reverses that on
    /// purpose, and the selected row's fill carries the structure instead.
    private var sidebar: some View {
            VStack(spacing: 0) {
                // Same reason the panel carries it: without this the window
                // surface answers questions fine and silently never rings.
                NotificationsNotice()
                if !feed.isSetupInstalled {
                    Divider()
                    SetupBanner(feed: feed, install: install)
                        .padding(.horizontal, 10).padding(.vertical, 10)
                }
                Divider()
                NewSessionBar()
                SessionSidebar(sessions: roots, children: feed.sessions.filter { $0.parentSessionId != nil },
                               asks: asks.pending, tasks: tasks, goals: goals.goals,
                               selection: $selection)
            }
            .frame(width: 250)
            // Clear of the toggle that sits in the toolbar strip above it.
            .padding(.top, 40)
            .background { SidebarScrim().ignoresSafeArea() }
            // The light sidebar and the pane are nearly one tone, so the seam needs
            // an edge of its own.
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 0.5).ignoresSafeArea()
            }
    }

    private var usageCard: OverviewStrip {
        OverviewStrip(fiveHour: feed.usageFiveHourPct,
                      sevenDay: feed.usageSevenDayPct,
                      usageStale: feed.usageIsStale,
                      usageHelp: feed.usageAsOfString,
                      fiveHourElapsed: feed.usageFiveHourElapsed,
                      sevenDayElapsed: feed.usageSevenDayElapsed,
                      fiveHourReset: feed.usageFiveHourResetRelative,
                      sevenDayReset: feed.usageSevenDayReset)
    }

    @ViewBuilder private var detail: some View {
            if HomeTab.isHomeTag(selection) {
                HomeDashboard(sessions: roots, asks: asks.pending, usage: usageCard,
                              tasks: tasks, goals: goals.goals) { selection = $0 }
            } else if AppKitTab.isTag(selection) {
                AppKitShowcase()
            } else if let project = PinnedProject.project(forTag: selection) {
                PinnedProjectDetail(project: project, sessions: roots,
                                    asks: asks.pending, feedDir: feed.feedDirectory,
                                    notice: $actionNotice) { selection = $0 }
                    .id(project.id)
            } else if let session = selected {
                SessionDetail(session: session,
                              asks: asks.pending.filter { $0.sessionId == session.id },
                              feedDir: feed.feedDirectory,
                              suggestion: suggestion,
                              skillPick: skillPick,
                              usage: usageCard,
                              headSHA: gitSnapshot?.headSHA,
                              repoRoot: gitSnapshot?.toplevel,
                              notice: $actionNotice)
                .id(session.id)
                .onAppear { if selection == nil { selection = session.id } }
            } else {
                ContentUnavailableView("No active sessions",
                                       systemImage: "moon.zzz",
                                       description: Text("Sessions appear here as Claude Code runs."))
            }
    }
}

// MARK: - Sidebar

private struct SessionSidebar: View {
    let sessions: [SessionFeed]
    /// Subagents, listed under the session that spawned them.
    let children: [SessionFeed]
    let asks: [AskRequest]
    /// Each project section's TASKS.md, read by the window: the Home dashboard
    /// lists it too.
    let tasks: [String: (open: [String], done: Int, path: String)]
    /// A checkered flag on the rows whose session is on a timed /goal run.
    let goals: [String: GoalClock]
    @Binding var selection: String?
    /// Parent sessions whose finished subagents are opened out.
    @State private var showFinished: Set<String> = []

    private static let shownTasks = 5

    /// One section per project, with anything blocked on a human pinned above them.
    ///
    /// This replaced three status sections (Needs you / Working / Idle) rendered in
    /// whatever order `sessions` arrived in — which `rescan` builds from a
    /// dictionary's `values`, so the rows reshuffled on every scan. Status is still
    /// legible per row through the dot and the badge; what a heading is worth here
    /// is the project, which does not change while you are reading it.
    private var groups: [ProjectSection] {
        FeedWatcher.projectSections(
            sessions.map { SessionRowItem(id: $0.id, session: $0, ids: [$0.id], depth: 0) },
            asked: Set(asks.map(\.sessionId)),
            byRecency: true)
    }

    private var homeGroups: [ProjectSection] { groups.filter { HomeTab.isHomeSection($0.id) } }
    private var otherGroups: [ProjectSection] { groups.filter { !HomeTab.isHomeSection($0.id) } }

    private func asksFor(_ session: SessionFeed) -> Bool {
        asks.contains { $0.sessionId == session.id }
    }

    var body: some View {
        let childrenByParent = Dictionary(grouping: children, by: { $0.parentSessionId ?? "" })
        
        List {
            // The dashboard first, and the window opens on it: what every session
            // is doing is the question you have before you pick one.
            HStack(spacing: 6) {
                SidebarGlyph(symbol: "square.grid.2x2")
                Text("Home").font(.ui(11))
            }
            .sidebarRow(HomeTab.tag, selection: $selection)
            .accessibilityLabel("Home, every session at once")
            HStack(spacing: 6) {
                SidebarGlyph(symbol: "paintpalette")
                Text("App Kit").font(.ui(11))
            }
            .sidebarRow(AppKitTab.tag, selection: $selection)
            .accessibilityLabel("App Kit, the design system's Music components")
            // Then the home project group: the session at ~ others start from.
            ForEach(homeGroups) { section in sectionView(section, childrenByParent: childrenByParent) }
            Section {
                ForEach(PinnedProject.all) { project in
                    let live = PinnedProject.liveSessions(in: project.path, sessions: sessions).count
                    HStack(spacing: 6) {
                        SidebarGlyph(symbol: "pin.fill")
                        Text(project.name).font(.ui(11)).lineLimit(1)
                        Spacer(minLength: 0)
                        if live > 0 {
                            Text("\(live) live").font(.ui(10)).foregroundStyle(Color.label)
                        }
                    }
                    .sidebarRow(project.tag, selection: $selection)
                    .help(project.path)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(project.name), pinned project" + (live > 0 ? ", \(live) live" : ""))
                }
            } header: {
                Text("Pinned").font(.ui(10)).fontWeight(.semibold).foregroundStyle(Color.label)
            }
            ForEach(otherGroups) { section in sectionView(section, childrenByParent: childrenByParent) }
        }
        // Plain, not sidebar: the sidebar style's row metrics do not yield to
        // `listRowInsets`, `defaultMinListRowHeight` or `controlSize` -- captures
        // either side of all three put every row at the same y (2026-10-01). Plain
        // rows are about a third shorter, which is what fits four projects and
        // their tasks without scrolling.
        .listStyle(.plain)
        // Dense rows: the sidebar is a list of names, counts and one-line task
        // titles, and the sidebar style's default row height left a third of each
        // row empty -- four projects did not fit without scrolling.
        .environment(\.defaultMinListRowHeight, 18)
        // The lever that actually moves these rows. `listRowInsets` and the min
        // row height alone changed nothing measurable (rows sat at the same y in
        // captures either side of the edit, 2026-10-01); the sidebar style sizes
        // its rows from the control size.
        .controlSize(.small)
        // The window's own sidebar material is the background; the list's would
        // sit on top of it.
        .scrollContentBackground(.hidden)
        // No `selection:` binding above: the list's native highlight is the system
        // accent blue and `.tint` does not override it, so rows draw their own
        // neutral fill (App Kit's `SidebarList`, measured against Music). That
        // costs the list its arrow keys, which are put back here.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { step(1) }
        .onKeyPress(.upArrow) { step(-1) }
    }

    /// Moves the selection one selectable row, or reports the key unhandled when
    /// there is nowhere to go.
    private func step(_ delta: Int) -> KeyPress.Result {
        let ids = selectableIDs
        guard !ids.isEmpty else { return .ignored }
        let at = selection.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : ids.count)
        let next = min(max(at + delta, 0), ids.count - 1)
        selection = ids[next]
        return .handled
    }

    /// Every selectable row, top to bottom: the order the arrow keys walk.
    private var selectableIDs: [String] {
        [HomeTab.tag, AppKitTab.tag]
            + homeGroups.flatMap { $0.items.map(\.id) }
            + PinnedProject.all.map(\.tag)
            + otherGroups.flatMap { $0.items.map(\.id) }
    }

    /// One project's heading and rows. Shared by the home group above Pinned and
    /// the rest below it.
    @ViewBuilder private func sectionView(_ section: ProjectSection, childrenByParent: [String: [SessionFeed]]) -> some View {
        Section {
            ForEach(section.items) { item in
                let session = item.session
                HStack(spacing: 6) {
                    // The glyph, not a dot: a dot said which state only by
                    // hue. Motion now says "working" and the row's spoken
                    // label says the rest.
                    if session.isWorking {
                        TimelineView(.periodic(from: .now, by: 1 / Constants.spinnerFPS)) { context in
                            Text(Spinner.frame(at: context.date))
                                .font(.claudeMono(11)).foregroundStyle(tint(session))
                        }
                    } else {
                        Text(Spinner.idle)
                            .font(.claudeMono(11)).foregroundStyle(tint(session))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.distinctName)
                            .font(.ui(11)).lineLimit(1)
                        // Under a project heading the project name is already
                        // overhead; only the pinned section needs it spelled out.
                        if section.id == "needs-you" {
                            Text(session.projectName)
                                .font(.ui(10)).foregroundStyle(Color.label)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    // At the row's trailing edge, with the other marks: the name
                    // is what the eye scans down, and a glyph inside it broke
                    // that column.
                    GoalFlag(goal: goals[session.id])
                    if asksFor(session) {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(Color.attention)
                    }
                }
                .sidebarRow(session.id, selection: $selection)
                .help(session.statusLabel)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowLabel(session))
                // Not selectable: the detail pane shows root sessions, and a
                // subagent has no pane of its own to show.
                let split = SubagentSplit(childrenByParent[session.id] ?? [])
                ForEach(split.live) { child in childRow(child) }
                // Finished ones as a count that opens out: six "done" rows
                // outweighed the session they belonged to.
                if !split.finished.isEmpty {
                    let open = showFinished.contains(session.id)
                    Button {
                        withAnimation(.snappy) {
                            if open { showFinished.remove(session.id) } else { showFinished.insert(session.id) }
                        }
                    } label: {
                        Label("\(split.finished.count) finished",
                              systemImage: open ? "chevron.down" : "chevron.right")
                            .font(.ui(10)).foregroundStyle(Color.label)
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 16)
                    .denseRow()
                    if open {
                        ForEach(split.finished) { child in childRow(child) }
                    }
                }
            }
            if let file = tasks[section.id] { tasksRows(file) }
        } header: {
            SectionHeader(section: section)
        }
    }

    /// The project's open tasks under its sessions. Not selectable: they are a
    /// read-out, and /todo (in the Skills card) is what writes the file.
    @ViewBuilder private func tasksRows(_ file: (open: [String], done: Int, path: String)) -> some View {
        HStack(spacing: 6) {
            SidebarGlyph(symbol: "checklist", accent: false)
            Text("Tasks").font(.ui(11)).fontWeight(.semibold)
            Spacer(minLength: 4)
            Text("\(file.open.count) open · \(file.done) done")
                .font(.ui(10)).foregroundStyle(Color.label)
        }
        .denseRow()
        if file.open.isEmpty {
            Text("Nothing open in TASKS.md.").font(.ui(10)).foregroundStyle(Color.label.opacity(0.6))
                .denseRow()
        }
        // The id carries the file: a List wants ids unique across every section,
        // and a bare offset made row N of each project the same row, so each
        // drew the titles of whichever project had drawn row N first.
        let shown = file.open.prefix(Self.shownTasks).enumerated()
            .map { (id: "\(file.path)#\($0.offset)", title: $0.element) }
        ForEach(shown, id: \.id) { row in
            let title = row.title
            Label { Text(title) } icon: {
                Image(systemName: "circle").font(.system(size: 6)).foregroundStyle(Color.label)
            }
                .font(.ui(10)).lineLimit(1).truncationMode(.tail)
                .denseRow()
                .help(title)
        }
        if file.open.count > Self.shownTasks {
            // The rest are one click away in the file itself, not a longer list.
            Button("+\(file.open.count - Self.shownTasks) more") {
                NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
            }
            .buttonStyle(.link).font(.ui(10))
            .denseRow()
            .help("Open \(file.path)")
        }
    }

    private func childRow(_ child: SessionFeed) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint(child)).frame(width: 6, height: 6)
            Text(child.agentType ?? "subagent")
                .font(.ui(10)).lineLimit(1)
            Spacer(minLength: 0)
            Text(child.statusLabel)
                .font(.ui(10)).foregroundStyle(tint(child))
                .lineLimit(1)
        }
        .padding(.leading, 16)
        .denseRow()
        .accessibilityElement(children: .combine)
    }

    private func rowLabel(_ session: SessionFeed) -> String {
        var parts = [session.distinctName, session.statusLabel]
        if asksFor(session) { parts.append("has a question for you") }
        return parts.joined(separator: ", ")
    }

    private func tint(_ session: SessionFeed) -> Color {
        if session.isBlockedOnYou || asksFor(session) { return .attention }
        return session.isWorking ? .claude : .secondary
    }
}

/// A session's subagents split into the ones still doing something (listed) and
/// the ones that stopped (counted). Pure so the split is testable.
struct SubagentSplit {
    let live: [SessionFeed]
    let finished: [SessionFeed]

    /// How long a finished subagent stays counted. By time, not by the parent's
    /// turn: a background subagent's completion notice starts a new parent turn,
    /// so "finished this turn" hid the one that had just finished.
    static let keepFinished: TimeInterval = 30 * 60

    init(_ children: [SessionFeed], now: Date = Date()) {
        live = children.filter { $0.isWorking || $0.isBlockedOnYou }
        finished = children.filter { child in
            guard !(child.isWorking || child.isBlockedOnYou) else { return false }
            guard let updated = child.updated else { return false }
            return now.timeIntervalSince(updated) <= Self.keepFinished
        }
    }
}

/// The sessions heading, with + to start one in a project: a Ghostty window
/// running `claude` there, which the feed then picks up like any other.
private struct NewSessionBar: View {
    @State private var projects: [NewSession.Project]?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Sessions").font(.ui(11)).fontWeight(.semibold).foregroundStyle(Color.label)
                Spacer()
                Menu {
                    if let projects {
                        if projects.isEmpty { Text("No projects in the registry") }
                        ForEach(projects) { project in
                            Button(project.name) { start(project) }
                        }
                    } else {
                        Text("Couldn't read ~/.claude/project-registry.json")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("New Claude Code session in a project")
            }
            if let failure {
                Text(failure).font(.ui(10)).foregroundStyle(Color.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
        // Re-read now and then: repo-inventory.py rewrites the registry.
        .task {
            while !Task.isCancelled {
                projects = await Task.detached(priority: .utility) { NewSession.loadProjects() }.value
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func start(_ project: NewSession.Project) {
        failure = nil
        Task {
            let error = await Task.detached(priority: .userInitiated) {
                NewSession.launch(in: project.path)
            }.value
            failure = error.map { "Couldn't open Ghostty: \($0)" }
        }
    }
}

/// A project heading: what it is, how many sessions, and their context added up.
///
/// The total is deliberately untinted, for the reason recorded on
/// `FeedWatcher.totalContextTokens` — these are separate windows, so a summed 210k
/// is not the same "heavy" as one 210k session, and `contextTint` bands for one.
private struct SectionHeader: View {
    let section: ProjectSection

    var body: some View {
        HStack(spacing: 6) {
            Text(section.title).lineLimit(1)
                .font(.ui(10)).fontWeight(.semibold)
                .foregroundStyle(Color.label)
            Spacer(minLength: 4)
            Text(([ "\(section.sessionCount) session\(section.sessionCount == 1 ? "" : "s")" ]
                  + [section.contextTotal.map(FeedWatcher.formatTokens)].compactMap { $0 })
                    .joined(separator: " · "))
                .font(.ui(10)).foregroundStyle(Color.label)
        }
    }
}

// MARK: - Detail

/// How the detail pane fits the window without scrolling. Pure so the edges are
/// testable without laying out a view.
enum PaneFit {
    /// Under this the text stops being readable; the bottom clips instead.
    static let floor: CGFloat = 0.55

    /// `scale`: how much of its ideal size the pane is drawn at, never above 1
    /// (a tall window does not blow the cards up) and never below the floor.
    /// `extra`: the window height left over when the pane fits at full size,
    /// which goes to the top row so no empty band sits under the last one.
    /// `scrolls`: even at the floor the pane is taller than the window, so it
    /// scrolls rather than cutting its bottom off where nobody can reach it.
    static func fit(available: CGFloat, ideal: CGFloat) -> (scale: CGFloat, extra: CGFloat, scrolls: Bool) {
        guard ideal > 0, available > 0 else { return (1, 0, false) }
        let scale = min(1, max(floor, available / ideal))
        return (scale, scale < 1 ? 0 : available - ideal, ideal * scale > available + 1)
    }
}

private struct SessionDetail: View {
    let session: SessionFeed
    let asks: [AskRequest]
    let feedDir: URL
    /// Shown as a glow on the button it names, in whichever card owns it.
    let suggestion: Suggestion?
    /// The Skills card's own pick, outlined there and explained under it.
    let skillPick: Suggestion?
    /// Account-wide, not this session's: built by the window from the feed so
    /// the detail pane doesn't need the watcher.
    let usage: OverviewStrip
    /// The repo's HEAD, for the Graph card to say whether the graph is behind it.
    let headSHA: String?
    /// The repo root, which is where graphify writes its output. Nil outside a
    /// repo, and then the session's own directory is all there is to look in.
    let repoRoot: String?
    @Binding var notice: NoticeMessage?
    /// The pane's height at the width it is laid out at, without the top row's
    /// share of leftover height, read back from the layout so the fit can be
    /// worked out.
    @State private var idealHeight: CGFloat = 0

    var body: some View {
        // No scrolling: the whole pane is laid out at its natural height and, when
        // that is taller than the window, drawn smaller to fit. It is laid out at
        // the window's width divided by the scale, not the window's width, so the
        // cards use the room that shrinking frees instead of leaving a margin.
        GeometryReader { geo in
            let fit = PaneFit.fit(available: geo.size.height, ideal: idealHeight)
            let scale = fit.scale
            let pane = content(extra: fit.extra)
                .frame(width: geo.size.width / scale, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // The top row grew by exactly `extra`, so taking it back off
                    // leaves the ideal. Only a real change: a 1pt wobble would
                    // re-lay the pane out at a new width and chase its own tail.
                    let ideal = height - fit.extra
                    if abs(ideal - idealHeight) > 2 { idealHeight = ideal }
                }
                .scaleEffect(scale, anchor: .topLeading)
            // One structure whether it scrolls or not: swapping a plain pane for a
            // ScrollView changed the view's identity and its measured ideal, and
            // the fit flipped between the two and could settle on the wrong one.
            // scaleEffect draws smaller but keeps the layout size, so the content
            // is framed to the drawn height, and to at least the window's.
            ScrollView(.vertical) {
                pane.frame(width: geo.size.width, height: max(geo.size.height, idealHeight * scale),
                           alignment: .topLeading)
            }
            .scrollDisabled(!fit.scrolls)
            .scrollIndicators(fit.scrolls ? .automatic : .hidden)
        }
    }

    /// `extra` is leftover window height; both top-row cards take all of it, so
    /// the row, and the pane, grow by exactly that much.
    private func content(extra: CGFloat) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                header

                ForEach(asks) { ask in
                    AskCard(ask: ask)
                }

                // Side by side where the pane is wide enough, one column where it
                // isn't, and every card the height of the tallest in its row, so
                // each row reads as a set of equal tiles without a short card
                // stretched to match a chart two rows away. The transcript, tasks
                // and skills row and the git row each take the full width; below
                // them, at three columns, every row of stat tiles is full.
                TileGrid(minimum: 180, spacing: 12) {
                    // What was said, what is planned, and what can be run on
                    // it, in one row: the prose and the task titles split the
                    // width, the skill chips keep a fixed column.
                    HStack(alignment: .top, spacing: 12) {
                        ConversationCard(session: session, feedDir: feedDir, notice: $notice, extra: extra)
                        SkillsCard(session: session, feedDir: feedDir, suggestion: suggestion, pick: skillPick,
                                   extra: extra)
                            .frame(width: 380)
                    }
                    .tileSpan(.max)
                    // One full-width tile for everything git, straight under the
                    // transcript and skills: it is acted on, the stat tiles below
                    // are only read. The graph takes what is left beside
                    // a fixed-width status column with its automation switches under it,
                    // so the state sits next to the history. The git commands
                    // themselves live in the Skills card.
                    HStack(alignment: .top, spacing: 12) {
                        // Fixed width: the subject fills what the SHA, refs and age
                        // leave, and the Git card takes the rest of the row.
                        GitGraphCard(cwd: session.cwd)
                            .frame(width: 360)
                        // The repo's state and the switches that act on it, one card.
                        VStack(alignment: .leading, spacing: 14) {
                            GitCard(cwd: session.cwd, framed: false)
                            AutomationToggles(session: session, feedDir: feedDir)
                        }
                        .detailCard()
                    }
                    .tileSpan(.max)
                    // This session, the account and this Mac in one row of rings:
                    // the card needs the full width.
                    usage.including(session)
                        .tileSpan(.max)
                    // Only drawn for a repo that has a graphify-out/graph.json.
                    GraphifyCard(root: repoRoot ?? session.cwd, headSHA: headSHA)
                        .tileSpan(.max)
                }

            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// No name or path: the selected sidebar row already names the session, and
    /// the toolbar copies or reveals its folder. No idle age either: the Session
    /// card carries the status. Only what asks something of you.
    @ViewBuilder private var header: some View {
        if let summary = session.attentionSummary {
            // Blue only when something is genuinely blocked. A finished
            // session that simply hasn't been typed at is not an alarm.
            Text(summary)
                .font(.ui(11))
                .foregroundStyle(session.isBlockedOnYou ? Color.attention : Color.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - A pending question, in full

struct AskCard: View {
    let ask: AskRequest
    @State private var answered: String?
    /// The options ignore clicks until this long after the card appears. The card
    /// draws under a pointer that was resting on whatever it replaced, and a click
    /// meant for that answered the question (four "Red" answers, 2026-09-30, each
    /// with a trackpad click just before it).
    static let armDelay: Duration = .milliseconds(800)
    @State private var armed = false

    var body: some View {
        if ask.isForm {
            AskFormCard(ask: ask)
        } else {
            single
        }
    }

    private var single: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ask.kind == .permission ? "Permission needed" : (ask.question?.header ?? "Question"))
                .font(.ui(11)).foregroundStyle(Color.attention)
            Text(prompt).font(.ui(13)).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)

            // What the tool would actually do. Without this the card asks you to
            // approve a command it never shows, which is the one place this
            // surface is worse than the terminal prompt it replaces.
            if let subject = ask.toolSubject {
                Text(subject)
                    .font(.claudeMono(11))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.claudeDim.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 6))
            }

            if let answered {
                Text("Answered: \(answered)").font(.ui(11)).foregroundStyle(Color.label)
            } else {
                // Full labels *and* their descriptions — the reason this surface
                // exists. A banner shows two buttons and no descriptions at all.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                        Button { answer(choice.answer, label: choice.label) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(choice.label).font(.ui(11))
                                if let detail = choice.detail {
                                    Text(detail).font(.ui(10))
                                        .foregroundStyle(Color.label)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!armed)
                        .accessibilityLabel(choice.label)
                    }
                }
            }
        }
        .task(id: ask.req) {
            armed = false
            try? await Task.sleep(for: Self.armDelay)
            armed = true
        }
        .padding(12)
        .background(Color.attention.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var prompt: String {
        switch ask.kind {
        case .question: return ask.question?.question ?? ""
        case .permission: return "Run \(ask.toolName ?? "a tool")?"
        }
    }

    private var choices: [(label: String, detail: String?, answer: AskAnswer)] {
        switch ask.kind {
        case .permission:
            return [("Allow", nil, .allow), ("Deny", nil, .deny)]
        case .question:
            return (ask.question?.options ?? []).map {
                ($0.label, $0.description, .option($0.label))
            }
        }
    }

    private func answer(_ value: AskAnswer, label: String) {
        // False means ask.sh already gave up and Claude Code is showing its own
        // prompt. Say that rather than reporting an answer that went nowhere.
        // A question is only typed into the terminal box; the card leaves once
        // the session shows the box took it.
        let sent = AskInbox.shared.answer(ask, with: value)
        answered = ask.blocking
            ? (sent ? label : "expired — answer it in the terminal")
            : (sent ? "\(label), typed into the terminal"
                    : "couldn't type into this session — answer it in the terminal")
        AskInbox.shared.rescan()
    }
}

/// A form: every question of the ask, each with its options, sent together.
///
/// The hook is waiting on all the answers at once, so nothing is sent until each
/// question has a pick. "Answer in terminal" hands it back: the hook returns
/// without a decision and Claude Code draws its own box.
struct AskFormCard: View {
    let ask: AskRequest
    @State private var picks: [Int: Set<String>] = [:]
    @State private var outcome: String?
    @State private var armed = false

    private var questions: [AskQuestion] { ask.questions ?? [] }
    private var answers: [String: String]? { AskForm.answers(for: questions, picks: picks) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(questions.count == 1 ? (questions[0].header ?? "Question")
                                      : "\(questions.count) questions")
                .font(.ui(11)).foregroundStyle(Color.attention)

            if let outcome {
                Text(outcome).font(.ui(11)).foregroundStyle(Color.label)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    self.question(question, at: index)
                }
                HStack(spacing: 8) {
                    Button("Send answers") { send() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!armed || answers == nil)
                    Button("Answer in terminal") { handBack() }
                        .buttonStyle(.bordered)
                        .disabled(!armed)
                }
            }
        }
        .task(id: ask.req) {
            armed = false
            try? await Task.sleep(for: AskCard.armDelay)
            armed = true
        }
        .padding(12)
        .background(Color.attention.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func question(_ question: AskQuestion, at index: Int) -> some View {
        let multi = question.multiSelect == true
        return VStack(alignment: .leading, spacing: 6) {
            Text(question.question).font(.ui(13)).fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
            if multi {
                Text("Pick any that apply").font(.ui(10)).foregroundStyle(Color.label)
            }
            ForEach(Array((question.options ?? []).enumerated()), id: \.offset) { _, option in
                let on = picks[index]?.contains(option.label) ?? false
                Button {
                    picks = AskForm.toggle(option.label, at: index, multi: multi, in: picks)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: multi ? (on ? "checkmark.square.fill" : "square")
                                                : (on ? "largecircle.fill.circle" : "circle"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.label).font(.ui(11))
                            if let detail = option.description {
                                Text(detail).font(.ui(10))
                                    .foregroundStyle(Color.label)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(!armed)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func send() {
        guard let answers else { return }
        // False means ask.sh already gave up and Claude Code is showing its own
        // box. Say that rather than reporting answers that went nowhere.
        let sent = AskInbox.shared.answer(ask, with: .form(answers))
        outcome = sent
            ? "Answered: " + questions.map { answers[$0.question] ?? "" }.joined(separator: " / ")
            : "expired — answer it in the terminal"
        AskInbox.shared.rescan()
    }

    private func handBack() {
        let sent = AskInbox.shared.answer(ask, with: .passthrough)
        outcome = sent ? "Left for the terminal" : "expired — answer it in the terminal"
        AskInbox.shared.rescan()
    }
}

// MARK: - Free-text reply

/// The window's one-row toolbar, edge to edge: the sidebar toggle and the
/// session actions on glass. Their outcome is said in the conversation card,
/// beside the reply field. Git actions live in the Git commands card.
///
/// Pinned above the scroll rather than inside it, after the footage library:
/// replying and acting on the session stay in reach however far down the cards
/// you are. The notice is the one thing allowed to add a line, and only after
/// you did something: it answers the click, so it should not wait in the scroll.
private struct WindowToolbar: View {
    let session: SessionFeed?
    let feedDir: URL
    @Binding var sidebarVisible: Bool
    let suggestion: Suggestion?
    @Binding var notice: NoticeMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { withAnimation(.smooth) { sidebarVisible.toggle() } } label: {
                        Image(systemName: "sidebar.left").frame(width: 18, height: 18)
                    }
                    .buttonStyle(.glass)
                    .help(sidebarVisible ? "Hide sidebar" : "Show sidebar")
                    .accessibilityLabel(sidebarVisible ? "Hide sidebar" : "Show sidebar")
                    Spacer(minLength: 0)
                    if let session {
                        ActionBar(session: session, feedDir: feedDir, notice: $notice,
                                  suggestion: suggestion)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}

private struct ReplyBox: View {
    let session: SessionFeed
    let feedDir: URL
    @Binding var notice: NoticeMessage?
    @State private var text = ""
    @State private var sending = false

    var body: some View {
        HStack(spacing: 8) {
            TextField("Reply to this session…", text: $text)
                .textFieldStyle(.plain)
                .font(.claudeMono(11))
                .onSubmit(send)
            Button(sending ? "Sending…" : "Send", action: send)
                .font(.ui(11))
                .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.accentColor)
                .controlSize(.small)
                .disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 7)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func send() {
        let message = text.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty, !sending else { return }
        // A session holding a question reads as working in the feed, so the
        // replier's refusal said "mid-turn" about a session waiting on you.
        if AskInbox.shared.pending.contains(where: { $0.sessionId == session.id }) {
            notice = .init(kind: .error, text: "That session is waiting on the question above. Answer it first.")
            return
        }
        sending = true
        notice = nil
        SessionReplier.reply(to: session, text: message, feedDir: feedDir) { result in
            sending = false
            switch result {
            case .success:
                text = ""
                notice = .init(kind: .info, text: "Sent — the session picked it up.")
            case .failure(let error):
                notice = error.errorDescription.map { .init(kind: .error, text: $0) }
            }
        }
    }
}


// MARK: - Stat rendering

/// The pane's colour as a veil over the window's sidebar material. The desktop
/// still shows through, but the ground behind the text is bounded: every status
/// colour in the app was tuned for a near-black or near-white ground, and the
/// bare material measured #575757 in dark over this desktop, which put secondary
/// labels at 3.1:1 and the red symbols near 2:1.
struct SidebarScrim: View {
    static let darkAlpha = 0.62
    static let lightAlpha = 0.94

    var body: some View {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = dark ? Color.Ink.paneDark : Color.Ink.paneLight
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: dark ? Self.darkAlpha : Self.lightAlpha)
        })
    }
}

/// A sidebar symbol: Music tints the symbol and leaves the label in normal ink,
/// and every symbol loses the accent in an inactive window. Red is a mark colour
/// only (claude-spinner-music slice 1), which a 14pt glyph is.
private struct SidebarGlyph: View {
    let symbol: String
    /// Red marks a place you can go (Home, App Kit, a pinned project). A read-out
    /// such as a Tasks header is neutral, or red stops meaning anything and
    /// out-shouts the status colours.
    var accent = true
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Image(systemName: symbol).font(.ui(10))
            .foregroundStyle(!accent ? Color.label
                : appearsActive ? Color.Kit.musicAccent : Color.Kit.musicSidebarGlyphInactive)
            .frame(width: 14)
            .accessibilityHidden(true)
    }
}

/// A selectable sidebar row. The row draws its own neutral rounded fill and the
/// label goes semibold, so selection is fill plus weight, never colour alone.
private struct SidebarRowChrome: ViewModifier {
    let id: String
    @Binding var selection: String?
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        let on = id == selection
        content
            .fontWeight(on ? .semibold : .regular)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(on ? (appearsActive ? Color.Kit.musicSidebarSelect
                                              : Color.Kit.musicSidebarSelectInactive) : .clear))
            .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { selection = id }
            // A tap gesture is not a button to VoiceOver; the list gave rows that
            // role until it lost its selection binding.
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

extension View {
    fileprivate func sidebarRow(_ id: String, selection: Binding<String?>) -> some View {
        modifier(SidebarRowChrome(id: id, selection: selection))
    }

    /// One section of the detail pane as a card, after the footage library's:
    /// the design system's radius-lg on a surface one step off the pane, with no
    /// border or shadow. Fills its grid column so neighbours line up at the edges.
    func detailCard() -> some View { modifier(DetailCard()) }

    /// A sidebar row at its text's own height. The list style's default insets
    /// are sized for a Finder sidebar's 13pt rows; these are 10 and 11pt.
    func denseRow() -> some View {
        listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
            // Plain draws a hairline under every row; the section headings are
            // what separate things here.
            .listRowSeparator(.hidden)
            // The whole row selects, not just the glyph and the name. Sidebar
            // style painted a full-width target; plain hit-tests the content,
            // and a row is mostly the Spacer between its name and its marks, so
            // clicking anywhere but the text did nothing.
            .contentShape(Rectangle())
    }

    /// How many `TileGrid` columns this card takes.
    func tileSpan(_ columns: Int) -> some View { layoutValue(key: TileSpan.self, value: columns) }
}

struct DetailCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            // Unbounded height takes whatever the tile grid places it at; outside
            // the grid the scroll view proposes no height, so the card keeps its own.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Columns at least `minimum` wide, as many as fit, and each row as tall as its
/// tallest card. LazyVGrid can't do the last part: it sizes rows but leaves each
/// cell at its own height, and the grid holds six cards, so laziness buys nothing.
///
/// A card may span several columns (`tileSpan`), clamped to however many there
/// are; one that doesn't fit what is left of a row starts the next.
struct TileGrid: Layout {
    let minimum: CGFloat
    let spacing: CGFloat
    /// The rows are composed for three columns (wide cards alternating sides);
    /// a fourth let them wrap into a row with one card and a gap.
    var maxColumns = 3
    /// The last card of a row takes the columns nothing else claimed. For a
    /// page of mixed spans, where a two-column card alone in a row of three
    /// left a third of the pane bare beside it.
    var fillsRows = false

    struct Slot: Equatable {
        let index: Int
        let column: Int
        let span: Int
    }

    /// Which card lands in which row and column, from spans and measured heights
    /// alone. Pure, because the two rules in it are the ones that went wrong on
    /// screen and a layout cannot be looked at from a test.
    ///
    /// A card measuring zero drew nothing and takes no row: an absent Graph card
    /// otherwise packed an empty tile and left a bare spacing-height row under
    /// the grid.
    static func pack(spans: [Int], heights: [CGFloat], columns: Int, fillsRows: Bool = false) -> [[Slot]] {
        var packed: [[Slot]] = []
        var used = columns
        for index in spans.indices where heights[index] > 0 {
            let span = min(max(1, spans[index]), columns)
            if used + span > columns {
                packed.append([])
                used = 0
            }
            packed[packed.count - 1].append(Slot(index: index, column: used, span: span))
            used += span
        }
        guard fillsRows else { return packed }
        return packed.map { row in
            guard let last = row.last else { return row }
            return Array(row.dropLast()) + [Slot(index: last.index, column: last.column, span: columns - last.column)]
        }
    }

    /// The height each row is placed at. Everything the grid was handed beyond
    /// its content goes to the last row, so a short page ends in a tall card
    /// rather than in blank pane; a grid sized to its content has none to give.
    static func placedHeights(rows: [CGFloat], spacing: CGFloat, available: CGFloat) -> [CGFloat] {
        guard let last = rows.indices.last else { return [] }
        let content = rows.reduce(0, +) + spacing * CGFloat(rows.count - 1)
        let slack = max(0, available - content)
        var heights = rows
        heights[last] += slack
        return heights
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var width = proposal.replacingUnspecifiedDimensions().width
        // A stack probing for its widest proposes infinity, and a column count
        // from that traps converting to Int: the Job Search rail's HStack crashed
        // the app on open (2026-09-30). Answer with the widest useful grid.
        if !width.isFinite { width = CGFloat(maxColumns) * (minimum + spacing) - spacing }
        let heights = rows(width: width, subviews: subviews).map(\.height)
        let content = heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0))
        // A height was proposed only where the grid sits in a flexible frame that
        // means it to fill; a grid in a scroll view is proposed nil and keeps its
        // content height. Taking the proposal is what lets placeSubviews hand the
        // slack to the last row instead of the frame centring a short grid.
        if let height = proposal.height, height.isFinite, height > content {
            return CGSize(width: width, height: height)
        }
        return CGSize(width: width, height: content)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = grid(width: bounds.width).columnWidth
        var y = bounds.minY
        let packed = rows(width: bounds.width, subviews: subviews)
        let placed = Self.placedHeights(rows: packed.map(\.height), spacing: spacing,
                                        available: bounds.height)
        for (index, row) in packed.enumerated() {
            let height = placed[index]
            for slot in row.slots {
                subviews[slot.index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(slot.column) * (columnWidth + spacing), y: y),
                    proposal: ProposedViewSize(width: width(slot.span, columnWidth), height: height))
            }
            y += height + spacing
        }
    }

    private func grid(width: CGFloat) -> (columns: Int, columnWidth: CGFloat) {
        let columns = min(maxColumns, max(1, Int((width + spacing) / (minimum + spacing))))
        return (columns, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func width(_ span: Int, _ columnWidth: CGFloat) -> CGFloat {
        columnWidth * CGFloat(span) + spacing * CGFloat(span - 1)
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [(slots: [Slot], height: CGFloat)] {
        let (columns, columnWidth) = grid(width: width)
        let measured = subviews.indices.map {
            subviews[$0].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
        }
        let packed = Self.pack(spans: subviews.indices.map { subviews[$0][TileSpan.self] },
                               heights: measured, columns: columns, fillsRows: fillsRows)
        return packed.map { slots in
            (slots, slots.map {
                subviews[$0.index]
                    .sizeThatFits(ProposedViewSize(width: self.width($0.span, columnWidth), height: nil))
                    .height
            }.max() ?? 0)
        }
    }
}

nonisolated struct TileSpan: LayoutValueKey {
    static let defaultValue = 1
}

/// A titled group of key/value rows. A nil value drops its row entirely rather
/// than drawing an em dash: a section of eight dashes says nothing except that
/// the statusLine hasn't run, and one line saying that is enough.
private struct StatSection: View {
    let title: String
    /// Label, value, and an optional dim note after the value -- how old this
    /// particular row is, for a section whose rows are read on two clocks.
    let rows: [(String, String?, String?)]
    /// Drawn beside the title when the section can be re-read on demand.
    var refresh: (() -> Void)?
    /// Said in place of the rows when none has a value. A section that vanished
    /// instead read the same as one that was never there to look at.
    var empty = "nothing reported yet"

    init(_ title: String, rows: [(String, String?)]) {
        self.title = title
        self.rows = rows.map { ($0.0, $0.1, nil) }
    }

    init(_ title: String, rows: [(String, String?, String?)] = [], refresh: (() -> Void)? = nil,
         empty: String = "nothing reported yet") {
        self.title = title
        self.rows = rows
        self.refresh = refresh
        self.empty = empty
    }

    var body: some View {
        let present = rows.compactMap { key, value, note in value.map { (key, $0, note) } }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title).font(.ui(10)).fontWeight(.semibold)
                    .foregroundStyle(Color.label)
                    .textCase(.uppercase).tracking(0.8)
                if let refresh {
                    Button("Refresh", action: refresh)
                        .font(.ui(10)).buttonStyle(.link)
                }
            }
            if present.isEmpty {
                Text(empty).font(.ui(11)).foregroundStyle(Color.label)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    ForEach(present, id: \.0) { key, value, note in
                        GridRow {
                            // Proportional labels against monospaced values, so the
                            // eye separates the two columns by face as well as by gap.
                            Text(key).font(.ui(11)).foregroundStyle(Color.label)
                                .gridColumnAlignment(.leading)
                            HStack(spacing: 8) {
                                // Cut in the middle, not wrapped: in a card-width
                                // column a bundle id broke mid-word onto a second
                                // line. Both ends of an id or path carry meaning.
                                Text(value).font(.claudeMono(11)).textSelection(.enabled)
                                    .lineLimit(1).truncationMode(.middle).help(value)
                                if let note {
                                    Text(note).font(.ui(10))
                                        .foregroundStyle(Color.label)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Pure formatting, kept out of the views so the awkward cases are testable:
/// sub-dollar spend, a zero denominator, and a diff with only one side.
nonisolated enum StatFormat {
    /// Always two decimals: a session starts in the cents, and a rounded "$0"
    /// would read as free.
    static func money(_ usd: Double) -> String { String(format: "$%.2f", usd) }

    /// Binary gigabytes, the unit Activity Monitor and Finder's storage bar use.
    static func gigabytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 100 ? String(format: "%.0f GB", gb) : String(format: "%.1f GB", gb)
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }

    static func percent(_ ratio: Double) -> String {
        String(format: "%.1f%%", ratio * 100)
    }

    static func compactCount(_ n: Int) -> String {
        n >= 1_000_000 ? "\(n / 1_000_000)M" : (n >= 1_000 ? "\(n / 1_000)k" : "\(n)")
    }

    /// How long ago something was read, or nil if it never was. A never-read
    /// stamp renders as nothing rather than as a very large age, which would
    /// read as a very stale reading rather than as an absent one.
    static func age(_ read: Date, now: Date) -> String? {
        guard read != .distantPast else { return nil }
        let seconds = Int(max(0, now.timeIntervalSince(read)).rounded())
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    /// nil when neither side is known — "+0 -0" claims a measurement that was
    /// never taken.
    static func lines(added: Int?, removed: Int?) -> String? {
        guard added != nil || removed != nil else { return nil }
        return "+\(added ?? 0) −\(removed ?? 0)"
    }

    /// The headline text and the level to tint it by, or nil when no window has
    /// reported. Both come back together so the caller cannot print a reading
    /// and tint it by a different number -- the old code printed `?? "—"` and
    /// tinted `usageTint(fiveHour ?? 0)`, so "unknown" drew in the green of
    /// "nothing used". 0% is a real reading and must still print.
    static func usageHeadline(_ pct: Int?) -> (text: String, level: Int)? {
        pct.map { ("\($0)%", $0) }
    }

    /// Whether a limit window is being used faster than it refills. Not judged in
    /// the first 5% of a window: right after a reset any use at all is "ahead"
    /// of a clock that has barely moved, and 1% flagged as ahead of pace.
    static func aheadOfPace(pct: Int, elapsed: Double, margin: Double = 0) -> Bool {
        elapsed >= 0.05 && Double(pct) / 100 > elapsed + margin
    }
}


/// The persisted 5h utilization samples as a filled line.
///
/// Scaled 0-100 rather than to its own min/max: this is a percentage of a rate
/// limit, so a flat 4% and a flat 90% must not draw the same line.
struct Sparkline: View {
    let samples: [UsageSample]

    /// What the line shows, said in words: where it started and where it is now.
    static func spokenValue(_ samples: [UsageSample]) -> String {
        guard let last = samples.last else { return "no usage history yet" }
        guard samples.count >= 2, let first = samples.first else { return "\(last.pct) percent" }
        return "\(last.pct) percent now, from \(first.pct) percent"
    }

    var body: some View {
        GeometryReader { geo in
            // Two points is the minimum that can be a trend; one is a dot with
            // no shape, and drawing it as a line implies history that isn't there.
            if samples.count >= 2 {
                let w = geo.size.width, h = geo.size.height
                let step = w / CGFloat(samples.count - 1)
                let points = samples.enumerated().map { index, sample in
                    CGPoint(x: CGFloat(index) * step,
                            y: h - (CGFloat(min(max(sample.pct, 0), 100)) / 100 * h))
                }
                let tint = Color.usageTint(samples.last?.pct ?? 0)
                ChartPath.area(points, baseline: h).fill(tint.opacity(0.15))
                ChartPath.line(points).stroke(tint, lineWidth: 1.5)
            } else {
                Text("no usage history yet")
                    .font(.ui(10)).foregroundStyle(Color.label)
            }
        }
    }
}


/// Where each context sample sits in a unit box: x from its timestamp, y from
/// its share of the window. Pure, so the degenerate cases are testable without
/// laying out a view.
enum ContextChart {
    /// The token counts `Color.contextTint` changes colour at.
    static let bandFloors = [100_000, 150_000, 200_000]

    /// nil when there is nothing honest to draw. Two points is the minimum that
    /// can be a trend, and without a window size there is no scale to plot
    /// against -- inventing one would make every session look equally full.
    static func unitPoints(_ samples: [ContextSample], window: Int?) -> [CGPoint]? {
        guard let window, window > 0, samples.count >= 2,
              let first = samples.first, let last = samples.last else { return nil }
        let span = last.at - first.at
        return samples.enumerated().map { index, sample in
            // Time-scaled, unlike `Sparkline` above: a session that sat idle for
            // twenty minutes has to read as a flat stretch rather than as one
            // step the same width as a busy minute. Equal timestamps would divide
            // by zero, so those fall back to even spacing.
            let x = span > 0 ? (sample.at - first.at) / span
                             : Double(index) / Double(samples.count - 1)
            let y = min(1, max(0, Double(sample.tokens) / Double(window)))
            return CGPoint(x: x, y: 1 - y)
        }
    }
}

/// A trend line and its fill, shared by every chart that draws one. The fill is
/// the same run of points closed down to the baseline, built as its own path
/// rather than reusing the stroked one.
enum ChartPath {
    static func line(_ points: [CGPoint]) -> Path {
        Path { path in
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    static func area(_ points: [CGPoint], baseline: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: points[0].x, y: baseline))
            for point in points { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: baseline))
            path.closeSubpath()
        }
    }
}

/// Context against the window, in the same capsule language as `UsageGauge`.
///
/// The `used` row above already prints the percentage; this is the same number
/// as a length, which is the form a ratio-against-a-limit actually wants.
struct ContextMeter: View {
    let tokens: Int
    let window: Int

    var body: some View {
        let ratio = min(1, max(0, Double(tokens) / Double(window)))
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.22))
                Capsule().fill(Color.contextTint(tokens: tokens, window: window))
                    // Keep a sliver visible for a tiny non-zero context, so a
                    // just-started session doesn't read as an empty track.
                    .frame(width: max(tokens > 0 ? 3 : 0, geo.size.width * ratio))
            }
        }
        .frame(height: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context used")
        .accessibilityValue("\(Int((ratio * 100).rounded())) percent of the window")
    }
}

// MARK: - What Claude is actually doing

/// The last thing Claude said, what you last asked, and what it just ran.
///
/// Everything said to and by the session in one card: the last exchange, a
/// field to answer it, and the model and effort the next turn runs on.
struct ConversationCard: View {
    let session: SessionFeed
    let feedDir: URL
    /// Shared with the toolbar: a reply and a session action report in one place.
    @Binding var notice: NoticeMessage?
    /// Leftover window height; Claude's reply takes it.
    var extra: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Flexible: Claude's reply fills whatever height the row gives the
            // card, so the reply row sits at the foot, where a chat box is.
            TranscriptCard(path: session.stats.transcriptPath, sessionID: session.id, pid: session.pid,
                           extra: extra)
            // The answer and what runs it, on one line.
            HStack(spacing: 8) {
                ReplyBox(session: session, feedDir: feedDir, notice: $notice)
                ConfigCard(session: session, feedDir: feedDir, notice: $notice)
            }
            if let notice { Notice(notice) }
        }
        .detailCard()
        // A half-typed reply or its notice must never carry to the next session.
        .id(session.id)
    }
}

/// Answers the question the rest of the pane cannot: a row saying "needs input"
/// tells you something is waiting, not what it wants or how to reply. This is
/// read from the session's own transcript, which no feed file carries.
private struct TranscriptCard: View {
    let path: String?
    let sessionID: String
    let pid: Int?
    var extra: CGFloat = 0
    /// About four lines of the transcript face: the reply's height before the
    /// row hands it any more.
    private static let replyIdeal: CGFloat = 54
    @State private var snapshot = TranscriptSnapshot()
    @State private var expanded = false
    @State private var goal: GoalClock?

    var body: some View {
        // Three things, no captions on the last: what you asked, what Claude said
        // (either can open out), and a dim line of what it just ran. It used to
        // reserve every block's full height so the card never moved, which left
        // a hole under a short reply; the row is as tall as the Skills card
        // beside it either way, so a card that resizes moves nothing.
        VStack(alignment: .leading, spacing: 10) {
            // Nothing read from the transcript at all: one line, not two reserved
            // blocks. A session whose transcript is missing drew "not recorded"
            // twice over two thirds of the pane, and the room belongs to the
            // cards under it.
            if nothingRecorded {
                Labelled("conversation", nil, limit: 1, goal: goal)
                Spacer(minLength: 0)
            } else {
                Labelled("you asked", snapshot.lastPrompt, limit: expanded ? nil : 2, expanded: $expanded,
                         goal: goal)
                Labelled("claude said", snapshot.lastAssistantText, limit: nil,
                         fill: expanded ? nil : Self.replyIdeal + extra)
            }
            if !snapshot.recentTools.isEmpty {
                Text("ran " + snapshot.recentTools.joined(separator: " · "))
                    .font(.claudeMono(10)).foregroundStyle(Color.label).lineLimit(1)
            }
        }
        // Opened out, the reply no longer takes `extra` through its fill, so the
        // card takes it here: the row must grow by exactly `extra` either way,
        // or the pane's measured ideal comes back short and it clips.
        .padding(.bottom, expanded && !nothingRecorded ? extra : 0)
        .task(id: sessionID) { await refresh() }
        .task(id: "\(sessionID)|\(pid.map(String.init) ?? "-")") { await trackGoal() }
        // Re-read on the same cadence the rows already tick at. The read is a
        // bounded tail, not the whole file, so this stays cheap.
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            Task { await refresh() }
        }
    }

    /// Neither side of the turn was read. Distinct from an empty reply, which is
    /// a turn in progress and keeps its reserved height.
    private var nothingRecorded: Bool {
        snapshot.lastPrompt == nil && snapshot.lastAssistantText == nil
    }

    /// Re-reads the goal's deadline file each time its label can change, about
    /// once a minute. A session with no pane, or no file, shows no sign: that is
    /// unknown, and the sign is never drawn from a guess. With no file yet it
    /// looks again in 10s, so a `/goal` started mid-view shows within seconds.
    private func trackGoal() async {
        goal = nil
        while !Task.isCancelled {
            var wait = 60.0
            if let pid, let pane = await Task.detached(priority: .utility, operation: {
                await GoalPaneResolver.shared.pane(sessionID: sessionID, pid: pid)
            }).value {
                let text = await Task.detached(priority: .utility) {
                    GoalDeadlineFile.read(pane: pane)
                }.value
                let clock = GoalClock.parse(text, now: Date())
                if clock != goal { goal = clock }
                wait = clock?.secondsUntilLabelChanges ?? 10
            } else if goal != nil {
                goal = nil
            }
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    private func refresh() async {
        guard let path else { return }
        // Off the main actor: this touches the filesystem, and the transcripts
        // are megabytes even though only the tail is read.
        let read = await Task.detached(priority: .utility) {
            TranscriptReader.read(path: path)
        }.value
        if read != snapshot { snapshot = read }
    }
}

/// A titled block of transcript prose, clamped unless expanded. A clamped block
/// holds its full line count even when the text is shorter or missing.
private struct Labelled: View {
    let title: String
    let body_: String?
    let limit: Int?
    /// When given, a chevron beside the title opens the block out.
    var expanded: Binding<Bool>?
    /// When given, the text asks for this height but takes whatever it is given,
    /// showing as many lines as fit and cutting the rest.
    var fill: CGFloat?
    /// A timed `/goal` run's clock, shown beside the title.
    var goal: GoalClock?

    init(_ title: String, _ body: String?, limit: Int?, expanded: Binding<Bool>? = nil,
         fill: CGFloat? = nil, goal: GoalClock? = nil) {
        self.title = title
        self.body_ = body
        self.limit = limit
        self.expanded = expanded
        self.fill = fill
        self.goal = goal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.ui(10)).fontWeight(.semibold)
                    .foregroundStyle(Color.label).textCase(.uppercase).tracking(0.8)
                if let goal {
                    // Tinted, not grey: in the label grey it read as part of the
                    // caption and was missed (asked "where is it" twice, 2026-09-30).
                    let tint = goal.isLanding || goal.isOverrun ? Color.attention : Color.series1
                    Label(goal.label, systemImage: "flag.checkered")
                        .font(.ui(11)).fontWeight(.semibold)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(tint.opacity(0.16), in: Capsule())
                        .fixedSize()
                        .help("Time left on this session's /goal run")
                }
                Spacer(minLength: 4)
                if let expanded {
                    Button { expanded.wrappedValue.toggle() } label: {
                        Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.borderless).foregroundStyle(Color.label)
                    .help(expanded.wrappedValue ? "Show less" : "Show the full text")
                }
            }
            let text = Text(body_ ?? "not recorded")
                .font(.claudeMono(11))
                .foregroundStyle(body_ == nil ? Color.label : Color.primary)
                .textSelection(.enabled)
            if let fill {
                text.frame(maxWidth: .infinity, minHeight: 0, idealHeight: fill, maxHeight: .infinity,
                           alignment: .topLeading)
            } else {
                text.lineLimit(limit ?? Int.max)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}


// MARK: - Actions

/// The session actions beside the reply field, in three groups: get to the
/// session, act on its turn, and reach its files.
///
/// Every button is either enabled or disabled with a stated reason. A control
/// that is greyed out and says nothing is what makes people click it twice and
/// conclude the app is broken -- and here the commonest reason, "not in a tmux
/// pane", is permanent rather than temporary, so it especially needs saying.
private struct ActionBar: View {
    let session: SessionFeed
    let feedDir: URL
    @Binding var notice: NoticeMessage?
    let suggestion: Suggestion?
    @State private var hasPane = false
    @State private var confirming: SessionAction?

    private static let groups: [[SessionAction]] = [
        [.focus],
        [.interrupt, .compact, .clear],
        [.revealCWD, .openTerminal, .copyPath, .openTranscript, .copySessionID],
    ]
    private static let named: Set<SessionAction> = [.interrupt, .compact, .clear]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Self.groups, id: \.self) { group in
                HStack(spacing: 6) {
                    ForEach(group) { action in
                        let reason = SessionActions.unavailableReason(action,
                                                                      session: session,
                                                                      hasPane: hasPane)
                        Button { start(action) } label: {
                            // Named where a click changes the session; the rest
                            // only reach its files and stay icons.
                            if Self.named.contains(action) {
                                Label(action.title, systemImage: action.symbol)
                                    .font(.ui(11)).frame(height: 18)
                            } else {
                                Image(systemName: action.symbol).frame(width: 18, height: 18)
                            }
                        }
                        .buttonStyle(.glass)
                        .disabled(reason != nil)
                        // The system's disabled dimming is too slight on glass to
                        // tell an unavailable action from an available one.
                        .opacity(reason == nil ? 1 : 0.45)
                        .suggestedGlow(reason == nil && suggested(action))
                        .help(reason ?? (suggested(action) ? suggestion?.reason : nil) ?? action.title)
                        .accessibilityLabel(action.title)
                    }
                }
            }
        }
        .task(id: session.id) {
            // Resolving a pane shells out to ps and tmux, so it happens once per
            // selected session rather than on every redraw.
            let pid = session.pid
            hasPane = await Task.detached(priority: .utility) {
                pid != nil && SessionReplier.hasPane(session)
            }.value
        }
        .confirmationDialog(confirming?.confirmation ?? "",
                            isPresented: Binding(get: { confirming != nil },
                                                 set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            if let action = confirming {
                Button(action.title, role: .destructive) {
                    confirming = nil
                    perform(action)
                }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        }
    }

    private func suggested(_ action: SessionAction) -> Bool {
        guard let text = action.promptText else { return false }
        return suggestion?.action == .command(text)
    }

    private func start(_ action: SessionAction) {
        notice = nil
        // /clear and /compact discard context that cannot be recovered, and one
        // of these buttons sits a few pixels from "Interrupt".
        if action.isDestructive { confirming = action } else { perform(action) }
    }

    private func perform(_ action: SessionAction) {
        if !action.needsPane {
            notice = SessionActions.runLocal(action, session: session)
                ? nil : .init(kind: .error, text: "Couldn't do that.")
            return
        }
        if action == .interrupt {
            SessionReplier.interrupt(session) { result in
                notice = describe(result, sent: "Interrupted.")
            }
            return
        }
        guard let text = action.promptText else { return }
        SessionReplier.reply(to: session, text: text, feedDir: feedDir) { result in
            notice = describe(result, sent: "Sent \(text).")
        }
    }

    private func describe(_ result: Result<Void, SessionReplier.Failure>,
                          sent: String) -> NoticeMessage? {
        switch result {
        case .success: return .init(kind: .info, text: sent)
        case .failure(let error): return error.errorDescription.map { .init(kind: .error, text: $0) }
        }
    }
}

// MARK: - Config

/// Model and effort as menus that type `/model` or `/effort` into the
/// session, after a confirmation naming what that costs. The read-only facts
/// stay rows beneath them.
private struct ConfigCard: View {
    let session: SessionFeed
    let feedDir: URL
    @State private var hasPane = false
    @State private var pending: (command: String, question: String)?
    /// The conversation card's, so a reply and a model change report in one place.
    @Binding var notice: NoticeMessage?
    @State private var sending = false

    var body: some View {
        let st = session.stats
        let reason = SkillShortcut.unavailableReason(session: session, hasPane: hasPane)
        // Only the two settings you can change. Thinking, output style and the
        // version were read-only and sat under them for nobody's decision.
        HStack(spacing: 6) {
            Menu {
                ForEach(SessionConfig.models, id: \.alias) { model in
                    Button {
                        pending = (SessionConfig.modelCommand(model.alias),
                                   SessionConfig.modelConfirmation(model.title))
                    } label: {
                        if SessionConfig.isCurrent(model.alias, model: session.model) {
                            Label(model.title, systemImage: "checkmark")
                        } else {
                            Text(model.title)
                        }
                    }
                }
            } label: {
                // The id only when the display name is missing.
                Text(session.model ?? st.modelID ?? "unknown").font(.ui(10))
            }
            .fixedSize()
            .disabled(reason != nil || sending)
            .help(reason ?? "Switch model")
            Menu {
                ForEach(SessionConfig.efforts, id: \.self) { level in
                    Button {
                        pending = (SessionConfig.effortCommand(level),
                                   SessionConfig.effortConfirmation(level))
                    } label: {
                        if st.effort == level {
                            Label(level, systemImage: "checkmark")
                        } else {
                            Text(level)
                        }
                    }
                }
            } label: {
                Text(st.effort ?? "default").font(.ui(10))
            }
            .fixedSize()
            .disabled(reason != nil || sending)
            .help(reason ?? "Change effort")
        }
        .controlSize(.small)
        .task(id: session.id) {
            let pid = session.pid
            hasPane = await Task.detached(priority: .utility) {
                pid != nil && SessionReplier.hasPane(session)
            }.value
        }
        .confirmationDialog(pending?.question ?? "",
                            isPresented: Binding(get: { pending != nil },
                                                 set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            if let command = pending?.command {
                Button(command) {
                    pending = nil
                    send(command)
                }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        }
    }

    private func send(_ command: String) {
        sending = true
        notice = nil
        SessionReplier.reply(to: session, text: command, feedDir: feedDir) { result in
            sending = false
            switch result {
            // /model and /effort start no turn, so "sent" is all that's known.
            case .success: notice = .init(kind: .info, text: "Typed \(command). The app can't see whether it took; check the terminal.")
            case .failure(let error): notice = error.errorDescription.map { .init(kind: .error, text: $0) }
            }
        }
    }
}

// MARK: - Suggested

/// A pulsing ring around the button `Suggestion.next` picked. In place of a
/// separate "suggested" banner: the button already sits in the card that
/// explains it, so the glow says "this one" without a second copy of it.
private struct GlowRing: View {
    @State private var bright = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.claude, lineWidth: 1.5)
            .shadow(color: Color.claude.opacity(bright ? 0.9 : 0.3), radius: bright ? 8 : 3)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bright = true }
            }
    }
}

private extension View {
    /// Glows only a button that can run: a lit-up disabled control points at
    /// something you can't do.
    func suggestedGlow(_ active: Bool) -> some View {
        overlay { if active { GlowRing() } }
    }
}

// MARK: - Shortcuts

private let installedShortcuts = SkillShortcut.available(
    claudeDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"))

/// A card's title, in the StatSection style. Not a StatSection itself: with no
/// rows that would say "nothing reported yet".
struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.ui(10)).fontWeight(.semibold)
            .foregroundStyle(Color.label)
            .textCase(.uppercase).tracking(0.8)
    }
}

/// The session skills as one-click slash commands.
private struct SkillsCard: View {
    let session: SessionFeed
    let feedDir: URL
    let suggestion: Suggestion?
    let pick: Suggestion?
    /// Leftover window height, taken as bottom space so the row grows evenly.
    var extra: CGFloat = 0
    @State private var notice: NoticeMessage?
    @State private var snapshot: GitSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("Skills")
            // Mid-turn every skill chip is disabled; a wall of greyed buttons for
            // most of the session's life said nothing. The git buttons still work.
            if session.isWorking {
                Text("Skills return when this turn ends.")
                    .font(.ui(10)).foregroundStyle(Color.label)
            } else {
                ShortcutChips(session: session, feedDir: feedDir,
                              shortcuts: installedShortcuts.filter { $0.group == .skill || $0.group == .tasks },
                              suggestion: suggestion, notice: $notice, pick: pick)
                let superpowers = installedShortcuts.filter { $0.group == .superpower }
                if !superpowers.isEmpty {
                    Text("Superpowers").font(.ui(9)).foregroundStyle(Color.label)
                        .textCase(.uppercase).tracking(0.8)
                    ShortcutChips(session: session, feedDir: feedDir, shortcuts: superpowers,
                                  suggestion: suggestion, notice: $notice, pick: pick)
                }
            }
            gitCommands
            // Said even while the chips are greyed mid-turn: it is what to run
            // when the turn ends.
            if let pick, case .command(let command) = pick.action {
                Text("\(Text(command).foregroundStyle(Color.claude))  \(pick.reason)")
                    .font(.ui(10)).foregroundStyle(Color.label)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Said out loud so a missing outline reads as a verdict, not a fault.
                Text("No skill needed right now.")
                    .font(.ui(10)).foregroundStyle(Color.label.opacity(0.6))
            }
            if let notice { Notice(notice) }
        }
        .padding(.bottom, extra)
        .detailCard()
    }

    /// The repo's git buttons and the git skills, under the other skills: they
    /// are the same kind of thing, one click that acts on the session.
    @ViewBuilder private var gitCommands: some View {
        Text("Git").font(.ui(9)).foregroundStyle(Color.label)
            .textCase(.uppercase).tracking(0.8)
        GitButtons(cwd: session.cwd, suggestion: suggestion, notice: $notice, snapshot: $snapshot)
        // Same rule as the buttons: a skill with nothing to act on is hidden,
        // and outside a repo (no snapshot) there is nothing to act on.
        let chips = snapshot == nil ? [] : installedShortcuts.filter {
            $0.group == .git && SkillShortcut.idleReason($0, snapshot: snapshot) == nil
        }
        // No "nothing to do" line when there are none: the Git card's pills
        // already say clean and in sync.
        if !chips.isEmpty {
            ShortcutChips(session: session, feedDir: feedDir, shortcuts: chips,
                          suggestion: suggestion, notice: $notice)
        }
    }
}

/// Buttons at their own width, wrapping onto the next line when a line is full.
/// A grid column made every chip as wide as the widest, and a short name like
/// "goal" sat in a bar twice its length.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(bounds.width, subviews)
        for (index, frame) in placed.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                  proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), frames)
    }
}

private struct OptionalCard: ViewModifier {
    let framed: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if framed { content.detailCard() } else { content }
    }
}

/// The four automations as switches, each reading its state back from where
/// it actually lives (GitHub, a marker file, settings.json, the app's own
/// defaults) rather than remembering what was last clicked. Turning one on
/// asks first and says what it will do and where; turning one off doesn't.
private struct AutomationToggles: View {
    let session: SessionFeed
    let feedDir: URL
    private var cwd: String { session.cwd }
    @ObservedObject private var autoPR = AutoPRWatcher.shared
    @State private var hasPane = false
    @State private var snapshot: GitSnapshot?
    @State private var autoCommitOn = false
    @State private var confirm: Pending?
    @State private var notice: NoticeMessage?
    @State private var busy = false

    private enum Pending: Equatable {
        case autoMerge, mainPush, autoCommit, autoPR, autoFix

        var question: String {
            switch self {
            case .autoMerge:
                return "Turn on GitHub auto-merge for this PR? GitHub squash-merges it and deletes the branch once checks pass -- straight away if they already have."
            case .mainPush:
                return "Let the auto-push and auto-commit hooks act on main in this repo? This creates .autocommit-main-ok at the repo root."
            case .autoCommit:
                return "Add the auto-commit Stop hook to ~/.claude/settings.json? Every project's sessions will commit their tracked changes at the end of each turn (Haiku writes the message) and push feature branches. settings.json is tracked in ~/.claude and ~, so both will show it modified."
            case .autoPR:
                return "Open pull requests automatically in this repo? When a feature branch is pushed and has no PR, the app runs gh pr create --fill -- once per branch."
            case .autoFix:
                return GitAutomation.autoFixConfirmation
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("Automation")
            if let snap = snapshot, let top = snap.toplevel {
                let mergeReason = GitAutomation.autoMergeUnavailableReason(snap)
                // One row of four, the name under each switch: a labelled switch per
                // line made this the tallest part of the card.
                HStack(alignment: .top, spacing: 4) {
                    toggle("Auto-merge PR", short: "Merge PR", isOn: snap.autoMerge == true,
                           disabledReason: mergeReason) { on in
                        if on { confirm = .autoMerge } else { setAutoMerge(false, snap) }
                    }
                    toggle("Auto-push on main", short: "Push main",
                           isOn: GitAutomation.mainPushEnabled(toplevel: top), disabledReason: nil) { on in
                        if on { confirm = .mainPush } else { setMainPush(false, top) }
                    }
                    toggle("Auto-commit (all projects)", short: "Commit", isOn: autoCommitOn,
                           disabledReason: nil) { on in
                        if on { confirm = .autoCommit } else { setAutoCommit(false) }
                    }
                    toggle("Auto-PR", short: "Open PR",
                           isOn: GitAutomation.autoPREnabled(toplevel: top),
                           disabledReason: snap.ghInstalled ? nil : "The gh CLI isn't installed.") { on in
                        if on { confirm = .autoPR } else { GitAutomation.setAutoPR(false, toplevel: top); reread() }
                    }
                }
                // "No open PR" is already the pr pill above; gh missing or auto-merge
                // disallowed are news whether or not a PR is open.
                if let mergeReason, !GitAutomation.autoMergeLacksOnlyAPR(snap) {
                    Text(mergeReason).font(.ui(10)).foregroundStyle(Color.label.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let result = autoPR.lastResult[top] { Notice(result) }
                let fixReason = GitAutomation.autoFixUnavailableReason(snap)
                    ?? SkillShortcut.unavailableReason(session: session, hasPane: hasPane)
                Button { confirm = .autoFix } label: {
                    Label("Auto-fix CI & comments", systemImage: "wrench.and.screwdriver")
                        .font(.ui(10)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)
                .disabled(fixReason != nil || busy)
                .opacity(fixReason == nil ? 1 : 0.7)
                .help(fixReason ?? "Type /autofix-pr into the session")
            }
            if let notice { Notice(notice) }
        }
        .task(id: cwd) { await poll() }
        .task(id: session.id) {
            let pid = session.pid
            let current = session
            hasPane = await Task.detached(priority: .utility) {
                pid != nil && SessionReplier.hasPane(current)
            }.value
        }
        .confirmationDialog(confirm?.question ?? "",
                            isPresented: Binding(get: { confirm != nil },
                                                 set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible) {
            if let pending = confirm {
                Button("Turn on") {
                    confirm = nil
                    turnOn(pending)
                }
            }
            Button("Cancel", role: .cancel) { confirm = nil }
        }
    }

    private func toggle(_ title: String, short: String, isOn: Bool, disabledReason: String?,
                        set: @escaping (Bool) -> Void) -> some View {
        VStack(spacing: 4) {
            Toggle(title, isOn: Binding(get: { isOn }, set: set))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .disabled(disabledReason != nil || busy)
            Text(short).font(.ui(10)).foregroundStyle(Color.label).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .help(disabledReason ?? title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private func turnOn(_ pending: Pending) {
        guard let snap = snapshot, let top = snap.toplevel else { return }
        switch pending {
        case .autoMerge: setAutoMerge(true, snap)
        case .mainPush: setMainPush(true, top)
        case .autoCommit: setAutoCommit(true)
        case .autoPR:
            GitAutomation.setAutoPR(true, toplevel: top)
            reread()
            Task { await AutoPRWatcher.shared.tick([cwd]) }
        case .autoFix:
            busy = true
            notice = nil
            SessionReplier.reply(to: session, text: GitAutomation.autoFixCommand, feedDir: feedDir) { result in
                busy = false
                switch result {
                case .success: notice = .init(kind: .info, text: "Typed /autofix-pr. The app can't see whether it took; check the terminal, then claude.ai/code.")
                case .failure(let error): notice = error.errorDescription.map { .init(kind: .error, text: $0) }
                }
            }
        }
    }

    /// Auto-merge is the one toggle that is unavailable until something exists,
    /// so it switches itself on the first time a PR is open and ready. Once per
    /// PR, not whenever it reads off: turning it off by hand must stick.
    private func enableAutoMergeWhenAvailable() {
        guard let snap = snapshot, let top = snap.toplevel,
              GitAutomation.shouldEnableAutoMerge(snap),
              case .open(let number, _, _) = snap.pr, !busy,
              AutoPRWatcher.shared.claimAutoMerge(toplevel: top, number: number) else { return }
        setAutoMerge(true, snap)
    }

    private func setAutoMerge(_ on: Bool, _ snap: GitSnapshot) {
        guard let cmd = GitAutomation.autoMergeCommand(enable: on, snapshot: snap) else { return }
        busy = true
        notice = nil
        let dir = cwd
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                GitProbe.run(cmd.tool, cmd.args, in: dir, timeout: GitActions.actionTimeout)
            }.value
            busy = false
            if let result, result.status == 0 {
                notice = .init(kind: .info, text: on ? "Auto-merge is on." : "Auto-merge is off.")
            } else {
                notice = .init(kind: .error,
                               text: result.flatMap { GitActions.firstLine($0.err) } ?? "gh didn't report back.")
            }
            await GitProbe.shared.invalidate(dir)
            snapshot = await GitProbe.shared.snapshot(for: dir)
        }
    }

    private func setMainPush(_ on: Bool, _ top: String) {
        do {
            try GitAutomation.setMainPush(on, toplevel: top)
            notice = nil
        } catch {
            notice = .init(kind: .error, text: error.localizedDescription)
        }
        reread()
    }

    private func setAutoCommit(_ on: Bool) {
        do {
            try GitAutomation.setAutoCommit(on)
            notice = .init(kind: .info, text: on ? "Auto-commit hook added." : "Auto-commit hook removed.")
        } catch {
            notice = .init(kind: .error, text: error.localizedDescription)
        }
        reread()
    }

    /// Marker files and defaults are read in the view body; this nudges a
    /// redraw and re-reads the one that lives in settings.json.
    private func reread() {
        autoCommitOn = (try? String(contentsOf: GitAutomation.settingsURL, encoding: .utf8))
            .map(GitAutomation.autoCommitEnabled) ?? false
        let current = snapshot
        snapshot = nil
        snapshot = current
    }

    private func poll() async {
        snapshot = nil
        while !Task.isCancelled {
            snapshot = await GitProbe.shared.snapshot(for: cwd)
            autoCommitOn = (try? String(contentsOf: GitAutomation.settingsURL, encoding: .utf8))
                .map(GitAutomation.autoCommitEnabled) ?? false
            enableAutoMergeWhenAvailable()
            try? await Task.sleep(for: .seconds(5))
        }
    }
}

/// Slash commands typed through the same pane as the reply field and held to
/// the same rule: idle and in tmux, or the chip is greyed with the reason.
private struct ShortcutChips: View {
    let session: SessionFeed
    let feedDir: URL
    let shortcuts: [SkillShortcut]
    let suggestion: Suggestion?
    @Binding var notice: NoticeMessage?
    /// This card's best skill: outlined, steady, beside the pane-wide glow.
    var pick: Suggestion? = nil
    @State private var hasPane = false
    @State private var sending = false
    @State private var confirming: SkillShortcut?

    var body: some View {
        ChipFlow(spacing: 6) {
            ForEach(shortcuts) { shortcut in
                let reason = SkillShortcut.unavailableReason(session: session, hasPane: hasPane)
                Button { start(shortcut) } label: {
                    // The name alone; the slash is implied by the card, and the
                    // tooltip and the notice still say the command typed.
                    Label(shortcut.label, systemImage: shortcut.symbol)
                        .font(.ui(10))
                        .lineLimit(1)
                }
                .buttonStyle(.glass)
                .disabled(reason != nil || sending)
                // Lighter than the toolbar's 0.45: these carry names worth
                // reading while the session is busy.
                .opacity(reason == nil ? 1 : 0.7)
                .overlay {
                    if reason == nil, pick?.action == .command(shortcut.command) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.claude, lineWidth: 1.2)
                            .allowsHitTesting(false)
                    }
                }
                .suggestedGlow(reason == nil && suggestion?.action == .command(shortcut.command))
                .help(reason ?? (suggestion?.action == .command(shortcut.command) ? suggestion?.reason : nil)
                      ?? (pick?.action == .command(shortcut.command) ? pick?.reason : nil)
                      ?? shortcut.blurb)
            }
        }
        .task(id: session.id) {
            let pid = session.pid
            hasPane = await Task.detached(priority: .utility) {
                pid != nil && SessionReplier.hasPane(session)
            }.value
        }
        .confirmationDialog(confirming?.sessionAction?.confirmation ?? "",
                            isPresented: Binding(get: { confirming != nil },
                                                 set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            if let shortcut = confirming, let action = shortcut.sessionAction {
                Button(action.title, role: .destructive) {
                    confirming = nil
                    send(shortcut)
                }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        }
    }

    private func start(_ shortcut: SkillShortcut) {
        if shortcut.sessionAction?.isDestructive == true { confirming = shortcut } else { send(shortcut) }
    }

    private func send(_ shortcut: SkillShortcut) {
        sending = true
        notice = nil
        SessionReplier.reply(to: session, text: shortcut.command, feedDir: feedDir) { result in
            sending = false
            switch result {
            case .success:
                notice = .init(kind: .info, text: "Sent \(shortcut.command).")
            case .failure(let error):
                notice = error.errorDescription.map { .init(kind: .error, text: $0) }
            }
        }
    }
}

// MARK: - Git

/// The repository's recent history as a lane graph: a dot per landmark commit
/// (runs of plain ones fold into a dashed "N commits" row), a coloured line per
/// branch, curves where they split and merge, and the commit's refs and age
/// beside it (the subject is the row's tooltip).
private struct GitGraphCard: View {
    let cwd: String
    @State private var history: (rows: [GraphRow], remotes: Set<String>)?
    @State private var read = false
    /// Rows the card has room for, measured, so a card stretched by a taller
    /// neighbour fills with commits instead of leaving a gap below them.
    @State private var fit = 10

    /// Read this many, then show only their landmarks (`GitGraph.condense`),
    /// so the card fits its rows instead of scrolling.
    private nonisolated static let limit = 60
    private static let rowHeight: CGFloat = 17
    private static let laneWidth: CGFloat = 12
    /// Beyond this many lanes the drawing is clipped rather than letting a
    /// repo full of stale remote branches push the text off the card.
    private static let maxLanes = 8
    private static let palette: [Color] = [.claude, .identityCyan, .identityPurple,
                                           .identityJade, .usageAmber, .identityIndigo]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("History")
            if let history, case let rows = condensed(history), !rows.isEmpty {
                let lanes = min(Self.maxLanes, rows.map(\.width).max() ?? 1)
                HStack(alignment: .top, spacing: 8) {
                    graph(rows)
                        .frame(width: CGFloat(lanes) * Self.laneWidth,
                               height: CGFloat(rows.map(Self.span).reduce(0, +)) * Self.rowHeight)
                        .clipped()
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, line in
                            label(line).frame(height: CGFloat(Self.span(line)) * Self.rowHeight, alignment: .top)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Measured from the space offered, not the rows drawn, so the
                // count can't feed back into its own height.
                .onGeometryChange(for: Int.self) { max(4, Int($0.size.height / Self.rowHeight)) } action: {
                    fit = $0
                }
            } else {
                Text(history != nil ? "no commits yet" : read ? "history couldn't be read" : "reading…")
                    .font(.ui(11)).foregroundStyle(Color.label)
            }
        }
        .detailCard()
        .task(id: cwd) { await poll() }
    }

    /// Text lines a row takes: one. Refs sit beside the SHA on its line, so a
    /// commit carrying three of them is no taller than one carrying none.
    private nonisolated static func span(_ line: GraphLine) -> Int {
        return 1
    }

    /// The newest commits whole and the rest folded into the last line, as
    /// many as fit. Stacked refs make some rows taller, so fewer are kept
    /// whole until the total fits the measured lines.
    private func condensed(_ history: (rows: [GraphRow], remotes: Set<String>)) -> [GraphLine] {
        var newest = fit - 1
        while true {
            let lines = GitGraph.condense(history.rows, remotes: history.remotes,
                                          newest: newest, maxLines: fit)
            var used = 0
            let kept = Array(lines.prefix { used += Self.span($0); return used <= fit })
            if kept.count == lines.count || newest <= 1 { return kept }
            newest -= 1
        }
    }

    private func graph(_ rows: [GraphLine]) -> some View {
        Canvas { context, _ in
            let h = Self.rowHeight
            let tops = rows.reduce(into: [CGFloat(0)]) { $0.append($0.last! + CGFloat(Self.span($1)) * h) }
            func x(_ lane: Int) -> CGFloat { CGFloat(lane) * Self.laneWidth + Self.laneWidth / 2 }
            func y(_ row: Int) -> CGFloat { tops[row] + h / 2 }
            func color(_ lane: Int) -> Color { Self.palette[lane % Self.palette.count] }

            for (r, line) in rows.enumerated() {
                // A folded run is dashed: the line continues, but not every
                // commit on it is drawn.
                let style = if case .gap = line {
                    StrokeStyle(lineWidth: 1.6, dash: [2, 3])
                } else {
                    StrokeStyle(lineWidth: 1.6)
                }
                for edge in line.edges {
                    var path = Path()
                    let start = CGPoint(x: x(edge.from), y: y(r))
                    let end = CGPoint(x: x(edge.to), y: y(r + 1))
                    path.move(to: start)
                    if edge.from == edge.to {
                        path.addLine(to: end)
                    } else {
                        path.addCurve(to: end,
                                      control1: CGPoint(x: start.x, y: start.y + h * 0.6),
                                      control2: CGPoint(x: end.x, y: end.y - h * 0.6))
                    }
                    // A branch-off or merge takes the colour of the side lane.
                    let lane = edge.from == edge.to ? edge.from : max(edge.from, edge.to)
                    context.stroke(path, with: .color(color(lane)), style: style)
                }
            }
            for (r, line) in rows.enumerated() {
                guard case .commit(let row) = line else { continue }
                let center = CGPoint(x: x(row.column), y: y(r))
                let isHead = row.commit.refs.contains { $0.hasPrefix("HEAD") }
                let radius: CGFloat = isHead ? 5 : 3.5
                let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                 width: radius * 2, height: radius * 2))
                if row.commit.parents.count > 1 {
                    // A merge commit is a ring, so it reads as a join, not a step.
                    context.fill(dot, with: .color(Color.card))
                    context.stroke(dot, with: .color(color(row.column)), lineWidth: 1.6)
                } else {
                    context.fill(dot, with: .color(color(row.column)))
                }
                if isHead {
                    context.stroke(dot, with: .color(.primary), lineWidth: 1.2)
                }
            }
        }
    }

    @ViewBuilder private func label(_ line: GraphLine) -> some View {
        switch line {
        case .commit(let row): label(row)
        case .gap(let count, _):
            Text("\u{22EF} \(count) commit\(count == 1 ? "" : "s")")
                .font(.ui(10)).foregroundStyle(Color.label)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ row: GraphRow) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(row.commit.shortSHA).foregroundStyle(Color.label).fixedSize()
                .frame(height: Self.rowHeight)
            HStack(spacing: 4) {
                ForEach(GitGraph.shownRefs(row.commit.refs), id: \.self) { ref in
                    // Capped and cut in the middle, never fixed: two long branch
                    // names at their full width made the row wider than the card,
                    // which then drew out over the sidebar (2026-09-30).
                    // Its own width when that fits, else cut to 150. A bare
                    // `frame(maxWidth:)` is flexible and stretched every chip,
                    // `main` included, to take what the row offered.
                    ViewThatFits(in: .horizontal) {
                        Text(ref).fixedSize()
                        Text(ref).lineLimit(1).truncationMode(.middle).frame(maxWidth: 150)
                    }
                    .font(.claudeMono(9))
                    .foregroundStyle(ref.hasPrefix("HEAD") ? Color.usageGreen : Color.identityCyan)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: Self.rowHeight)
                    .help(ref)
                }
            }
            // Served before the subject: at equal priority the row handed the
            // chips too little to fit and cut even `HEAD -> main`.
            .layoutPriority(1)
            // The subject takes what the SHA, refs and age leave: a hash alone
            // says nothing about what the commit was.
            Text(row.commit.subject).font(.ui(11)).foregroundStyle(Color.primary)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.rowHeight)
            if let at = row.commit.committedAt {
                Text(FeedWatcher.compactAge(since: at)).foregroundStyle(Color.label).fixedSize()
                    .frame(height: Self.rowHeight)
            }
        }
        .font(.claudeMono(11))
        .contentShape(Rectangle())
        .help(row.commit.subject)
    }

    /// Local and cheap, so a commit made in the session shows within seconds.
    private func poll() async {
        history = nil
        read = false
        while !Task.isCancelled {
            let dir = cwd
            let fresh = await Task.detached(priority: .utility) {
                GitProbe.graph(cwd: dir, limit: Self.limit)
            }.value
            if fresh?.rows != history?.rows || fresh?.remotes != history?.remotes { history = fresh }
            read = true
            try? await Task.sleep(for: .seconds(15))
        }
    }
}

/// One git fact: a tinted icon saying how it reads, a label, the value.
private struct GitStatusRow: View {
    let label: String
    let value: String
    let symbol: String
    let tone: GitTone

    init(_ label: String, _ value: String, symbol: String, tone: GitTone) {
        self.label = label
        self.value = value
        self.symbol = symbol
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.ui(11)).foregroundStyle(tint)
            Text(label).font(.ui(11)).foregroundStyle(Color.label)
            Text(value).font(.ui(11))
                .foregroundStyle(tone == .neutral ? Color.label : Color.primary)
                .lineLimit(1).truncationMode(.middle).help(value)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    private var tint: Color {
        switch tone {
        case .good: return .usageGreen
        case .pending: return .claude
        case .warn: return .usageAmber
        case .bad: return .usageRed
        case .neutral: return .label
        }
    }
}

/// Branch, working-tree and remote state for the selected session's directory.
/// The actions that act on it live in the Git commands card (`GitButtons`);
/// what stays here is the sentence for any of them that couldn't be worked out.
///
/// Absent entirely when the cwd isn't a repository: a section of dashes tells
/// you nothing that its own absence doesn't tell you faster.
private struct GitCard: View {
    let cwd: String
    /// Drawn as its own card unless a parent card holds it.
    var framed = true
    @State private var snapshot: GitSnapshot?
    /// Whether `snapshot` has been read for this `cwd` yet. A nil snapshot is
    /// either "still reading" or "not a repository", and only this tells them apart.
    @State private var read = false

    var body: some View {
        // A VStack, not a Group: a Group hands its modifiers to each member, so
        // the task still re-ran on every branch swap, reset the snapshot, and
        // swapped back -- the section flickered and was caught blank on screen.
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .modifier(OptionalCard(framed: framed))
        .task(id: cwd) { await poll() }
    }

    @ViewBuilder private var content: some View {
        if let snap = snapshot {
            // Two clocks, so two ages. `remote` and `pr` are network reads on a
            // 90-second cycle sitting next to local facts read every five, and
            // one age for the section would misreport whichever half it wasn't.
            let now = Date()
            let local = snap.readAt == .distantPast ? nil
                : FeedWatcher.compactAge(since: snap.readAt, now: now)
            let remote = snap.remoteReadAt == .distantPast ? nil
                : FeedWatcher.compactAge(since: snap.remoteReadAt, now: now)
            VStack(alignment: .leading, spacing: 8) {
                header
                HStack(spacing: 6) {
                    Image(systemName: snap.detached ? "exclamationmark.triangle" : "arrow.triangle.branch")
                        .foregroundStyle(snap.detached ? Color.usageAmber : Color.label)
                    Text(snap.branchLabel).font(.claudeMono(12)).fontWeight(.semibold)
                        .lineLimit(1).truncationMode(.middle)
                    if snap.isDefaultBranch {
                        Text("default").font(.ui(9)).foregroundStyle(Color.label)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    if let isPrivate = snap.isPrivate {
                        Label(isPrivate ? "private" : "public", systemImage: isPrivate ? "lock" : "globe")
                            .font(.ui(9)).foregroundStyle(Color.label)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .help(isPrivate ? "Private repository on GitHub" : "Public repository on GitHub")
                    }
                }
                .help(snap.upstream.map { "tracks \($0)" } ?? "no upstream")
                // Four facts as pills that wrap, not four rows: state at a glance.
                ChipFlow(spacing: 6) {
                    GitStatusRow("tree", changesLabel(snap) ?? "clean",
                                 symbol: snap.isDirty ? "pencil" : "checkmark.circle",
                                 tone: snap.changesTone)
                    GitStatusRow("remote", snap.sync.label, symbol: snap.sync.symbol, tone: snap.sync.tone)
                    GitStatusRow("pr", snap.pr.label ?? "unknown",
                                 symbol: "arrow.triangle.pull", tone: snap.pr.tone)
                    if let checks = checksLabel(snap) {
                        GitStatusRow("checks", checks, symbol: "checklist", tone: snap.merge.tone)
                    }
                    GitStatusRow("ci", snap.ci.label, symbol: "gearshape.2", tone: snap.ci.tone)
                }
                blockedReasons(snap)
                // Two clocks, said once each, under everything they date.
                Text([local.map { "local read \($0) ago" }, remote.map { "remote \($0) ago" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.ui(9)).foregroundStyle(Color.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            StatSection("Git", empty: read ? "not a git repository" : "reading…")
        }
    }

    /// The title and Refresh. The read ages sit once at the foot of the card:
    /// a local age and a remote age on every row was five timestamps saying two
    /// things, and on the title line they were cut off at card width.
    private var header: some View {
        HStack(spacing: 10) {
            Text("Git").font(.ui(10)).fontWeight(.semibold)
                .foregroundStyle(Color.label).textCase(.uppercase).tracking(0.8)
            Button("Refresh", action: reload).font(.ui(10)).buttonStyle(.link)
        }
    }

    /// An action that couldn't be worked out, with its reason. Settled blocks
    /// ("in sync", "clean") are not listed: the rows above already say why.
    private struct Unsettled: Identifiable {
        let action: GitAction
        let reason: String
        var id: String { action.id }
    }

    @ViewBuilder private func blockedReasons(_ snap: GitSnapshot) -> some View {
        // The action button stays greyed for these; the sentence goes on the
        // page instead of behind a tooltip nobody hovers for.
        let unsettled = GitAction.allCases.compactMap { action -> Unsettled? in
            guard let block = GitActions.unavailableReason(action, snapshot: snap),
                  !block.settled else { return nil }
            return Unsettled(action: action, reason: block.reason)
        }
        ForEach(unsettled) { item in
            Text("\(item.action.title.lowercased()): \(item.reason)")
                .font(.ui(10)).foregroundStyle(Color.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Only meaningful beside a PR that was actually read.
    private func checksLabel(_ snap: GitSnapshot) -> String? {
        guard snap.pr.number != nil else { return nil }
        return snap.merge.label
    }

    /// Untracked files are counted but never folded into the modified count.
    /// A repo with a deny-by-default ignore file carries a permanent untracked
    /// population, and adding it to "3 modified" would make every such directory
    /// read as busy forever.
    private func changesLabel(_ snap: GitSnapshot) -> String? {
        var parts: [String] = []
        if snap.dirty > 0 { parts.append("\(snap.dirty) modified") }
        if snap.staged > 0 { parts.append("\(snap.staged) staged") }
        if snap.untracked > 0 { parts.append("\(snap.untracked) untracked") }
        if parts.isEmpty { return "clean" }
        return parts.joined(separator: ", ")
    }

    /// Invalidate, then read, on one task and in that order. Two unordered
    /// actor hops let the read win and hand back the pre-action entry, which is
    /// how a finished push leaves the row still saying "ahead 1".
    private func reload() {
        Task {
            await GitProbe.shared.invalidate(cwd)
            snapshot = await GitProbe.shared.snapshot(for: cwd)
        }
    }

    /// Re-reads on the probe's own local TTL. The probe caches, so this loop
    /// costs a dictionary lookup on most passes and a `git status` on the rest.
    private func poll() async {
        // A new cwd must not show the last directory's branch while it reads.
        snapshot = nil
        read = false
        while !Task.isCancelled {
            snapshot = await GitProbe.shared.snapshot(for: cwd)
            read = true
            try? await Task.sleep(for: .seconds(5))
        }
    }
}

/// The Git actions for the selected session's directory.
///
/// Reads through the same cached `GitProbe` as `GitCard`, so the second reader
/// costs a dictionary lookup. Every action is drawn, greyed with its reason
/// when it can't run: hiding the settled ones left a repo on main, in sync and
/// without a PR showing no git commands at all, which read as missing rather
/// than finished. Absent when the directory isn't a repository.
private struct GitButtons: View {
    let cwd: String
    let suggestion: Suggestion?
    @Binding var notice: NoticeMessage?
    @Binding var snapshot: GitSnapshot?
    @State private var confirming: GitAction?
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snap = snapshot {
                ChipFlow(spacing: 6) {
                    // Always drawn, so Push/Pull/Merge are where you expect them;
                    // an idle one is dimmed with its reason as the tooltip.
                    ForEach(GitAction.allCases.filter { !$0.isTool }) { action in
                        let block = GitActions.unavailableReason(action, snapshot: snap)
                        Button { start(action) } label: {
                            Label(action.title, systemImage: action.symbol)
                                .font(.ui(10))
                                .lineLimit(1)
                        }
                        .buttonStyle(.glass)
                        .disabled(block != nil || running)
                        .opacity(block == nil ? 1 : 0.7)
                        .suggestedGlow(block == nil && suggestion?.action == .git(action))
                        .help(help(action, block: block))
                    }
                }
                HStack(spacing: 4) {
                    ForEach(GitAction.allCases.filter(\.isTool)) { action in
                        let block = GitActions.unavailableReason(action, snapshot: snap)
                        Button { start(action) } label: {
                            Image(systemName: action.symbol).frame(width: 28, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.label)
                        .disabled(block != nil || running)
                        .opacity(block == nil ? 1 : 0.45)
                        .suggestedGlow(block == nil && suggestion?.action == .git(action))
                        .help(help(action, block: block))
                        .accessibilityLabel(action.title)
                    }
                }
            }
        }
        .task(id: cwd) { await poll() }
        .confirmationDialog(confirming?.confirmation ?? "",
                            isPresented: Binding(get: { confirming != nil },
                                                 set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            if let action = confirming {
                Button(action.title) {
                    confirming = nil
                    perform(action)
                }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        }
    }

    private func help(_ action: GitAction, block: GitActions.Block?) -> String {
        block?.reason ?? (suggestion?.action == .git(action) ? suggestion?.reason : nil) ?? action.title
    }

    private func start(_ action: GitAction) {
        notice = nil
        if action.confirmation != nil { confirming = action } else { perform(action) }
    }

    private func perform(_ action: GitAction) {
        guard let snap = snapshot else { return }
        running = true
        GitActions.perform(action, snapshot: snap, cwd: cwd) { message in
            notice = message
            running = false
            // Invalidate, then read, on one task and in that order -- see
            // `GitCard.reload`.
            Task {
                await GitProbe.shared.invalidate(cwd)
                snapshot = await GitProbe.shared.snapshot(for: cwd)
            }
        }
    }

    private func poll() async {
        snapshot = nil
        while !Task.isCancelled {
            snapshot = await GitProbe.shared.snapshot(for: cwd)
            try? await Task.sleep(for: .seconds(5))
        }
    }
}
