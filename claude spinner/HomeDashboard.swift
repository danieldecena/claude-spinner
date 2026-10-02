import SwiftUI

// The window's Home tab: everything at once, rather than one session's pane.
//
// It answers the three questions the sidebar makes you click around for -- what
// is the account burning, what is every session doing, and what is open across
// the projects -- and nothing that belongs to a single session, which the
// session's own pane already carries.

/// The sidebar row that selects the dashboard. Not a session id and not a
/// pinned tag, so `resolveSelection` can tell all three apart.
enum HomeTab {
    static let tag = "home:dashboard"
    static func isHomeTag(_ tag: String?) -> Bool { tag == Self.tag }

    /// The sidebar section for sessions running at `~`, hoisted above Pinned.
    /// Derived from the home directory rather than written as "home": the id is
    /// `projectSections`' own "project:" + `projectName`, which is the last path
    /// component, and a differently-named home folder would silently never match.
    static var homeSectionID: String {
        "project:" + (NSHomeDirectory() as NSString).lastPathComponent
    }

    static func isHomeSection(_ id: String) -> Bool { id == homeSectionID }
}

struct HomeDashboard: View {
    /// Root sessions only: a subagent is listed under its parent, not here.
    let sessions: [SessionFeed]
    let asks: [AskRequest]
    /// The account's limits and this Mac's load, built by the window.
    let usage: OverviewStrip
    /// Open titles per project, as the sidebar already reads them.
    let tasks: [String: (open: [String], done: Int, path: String)]
    /// Which sessions are on a timed /goal run.
    let goals: [String: GoalClock]
    /// Clicking a session row opens its pane.
    let select: (String) -> Void

    @State private var idealHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let fit = PaneFit.fit(available: geo.size.height, ideal: idealHeight)
            let scale = fit.scale
            
            ScrollView(.vertical) {
                let scaledHeight = idealHeight * scale
                let frameHeight = max(geo.size.height, scaledHeight)
                let shift = idealHeight > frameHeight ? (idealHeight - frameHeight) / 2 : 0
                let _ = try? "ideal=\(idealHeight) scale=\(scale) shift=\(shift) geo=\(geo.size.height)".write(toFile: "/tmp/claude_debug.txt", atomically: true, encoding: .utf8)
                
                VStack(alignment: .leading, spacing: 12) {
                    usage
                    sessionsCard
                    tasksCard
                }
                .padding(20)
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

    // MARK: - Sessions

    /// Every session as a row: what it is doing, how full its context is, what it
    /// has spent. Ordered the way the sidebar orders them, so the two agree.
    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardTitle("Sessions")
                Spacer(minLength: 4)
                Text(countLabel).font(.ui(10)).foregroundStyle(Color.label)
            }
            if sessions.isEmpty {
                Text("No sessions are running.").font(.ui(11)).foregroundStyle(Color.label)
            }
            ForEach(FeedWatcher.sorted(sessions)) { session in
                Button { select(session.id) } label: { row(session) }
                    .buttonStyle(.plain)
            }
        }
        .detailCard()
    }

    private var countLabel: String {
        let working = sessions.filter(\.isWorking).count
        let waiting = sessions.filter { $0.isBlockedOnYou || asked.contains($0.id) }.count
        var parts: [String] = []
        if waiting > 0 { parts.append("\(waiting) need you") }
        if working > 0 { parts.append("\(working) working") }
        parts.append("\(sessions.count) in all")
        return parts.joined(separator: " · ")
    }

    private var asked: Set<String> { Set(asks.map(\.sessionId)) }

    private func row(_ session: SessionFeed) -> some View {
        HStack(spacing: 8) {
            Text(session.isWorking ? Spinner.frame(at: Date()) : Spinner.idle)
                .font(.claudeMono(11)).foregroundStyle(tint(session))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.distinctName).font(.claudeMono(11)).lineLimit(1)
                Text(session.projectName).font(.ui(10)).foregroundStyle(Color.label).lineLimit(1)
            }
            Spacer(minLength: 8)
            GoalFlag(goal: goals[session.id])
            Text(session.statusLabel).font(.ui(10)).foregroundStyle(tint(session)).lineLimit(1)
            // Fixed widths so the three figures line up down the card rather than
            // drifting with each name's length.
            Text(contextLabel(session)).font(.figure(10)).foregroundStyle(Color.label)
                .frame(width: 70, alignment: .trailing)
            // Wall time, not an api-equivalent dollar figure: nothing here is
            // charged on a Max plan, and a column of money said it was.
            Text(session.stats.wallSeconds.map(StatFormat.duration) ?? "—")
                .font(.figure(10)).foregroundStyle(Color.label)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .help(session.cwd)
        .accessibilityElement(children: .combine)
    }

    /// Tokens over the window, which is what the ring in the session's own pane
    /// says. A session whose statusLine has not reported has neither.
    private func contextLabel(_ session: SessionFeed) -> String {
        guard let tokens = session.contextTokens else { return "—" }
        guard let window = session.stats.contextWindowSize, window > 0 else {
            return StatFormat.compactCount(tokens)
        }
        return "\(StatFormat.compactCount(tokens)) · \(Color.contextPercent(tokens: tokens, window: window))%"
    }

    private func tint(_ session: SessionFeed) -> Color {
        if session.isBlockedOnYou || asked.contains(session.id) { return .attention }
        return session.isWorking ? .claude : .secondary
    }

    // MARK: - Tasks

    /// Open items across every project the sidebar read a TASKS.md for, project
    /// by project. The file itself is one click away; this is the count and the
    /// first few titles, as in the sidebar.
    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardTitle("Open tasks")
                Spacer(minLength: 4)
                Text("\(totalOpen) across \(tasks.count) \(tasks.count == 1 ? "project" : "projects")")
                    .font(.ui(10)).foregroundStyle(Color.label)
            }
            if tasks.isEmpty {
                Text("No TASKS.md found in the running sessions' repos.")
                    .font(.ui(11)).foregroundStyle(Color.label)
            }
            ForEach(tasks.keys.sorted(), id: \.self) { key in
                if let file = tasks[key] { project(key, file) }
            }
        }
        .detailCard()
    }

    private var totalOpen: Int { tasks.values.reduce(0) { $0 + $1.open.count } }

    @ViewBuilder private func project(_ key: String,
                                      _ file: (open: [String], done: Int, path: String)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(key.replacingOccurrences(of: "project:", with: ""))
                    .font(.ui(10)).fontWeight(.semibold)
                    .foregroundStyle(Color.label).textCase(.uppercase).tracking(0.8)
                Spacer(minLength: 4)
                Button("\(file.open.count) open · \(file.done) done") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
                }
                .buttonStyle(.link).font(.ui(10))
                .help("Open \(file.path)")
            }
            ForEach(Array(file.open.prefix(Self.shownTasks).enumerated()), id: \.offset) { _, title in
                Label { Text(title) } icon: {
                    Circle().fill(Color.label).frame(width: 4, height: 4)
                }
                .font(.ui(10)).lineLimit(1).truncationMode(.tail)
                .help(title)
            }
        }
    }

    private static let shownTasks = 5
}
