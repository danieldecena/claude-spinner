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
    @State private var selection: String?
    @State private var sidebarVisible = true
    /// The selected session's repo, read once here so the suggestion can be
    /// worked out once and handed to every card that might own its button.
    @State private var gitSnapshot: GitSnapshot?

    private var suggestion: Suggestion? {
        guard let session = selected else { return nil }
        return Suggestion.next(.init(
            git: gitSnapshot,
            contextPercent: session.stats.contextUsedPercent,
            contextTokens: session.contextTokens,
            atPrompt: session.isAtPrompt,
            idleFor: session.updated.map { Date().timeIntervalSince($0) },
            fiveHourPct: feed.usageFiveHourPct,
            fiveHourElapsed: feed.usageFiveHourElapsed,
            installed: Set(installedShortcuts.map(\.command))))
    }

    /// Roots only. Children are shown under their parent in the detail pane,
    /// where there is room for them.
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
        if let selection, let picked = roots.first(where: { $0.id == selection }) { return picked }
        return Self.defaultSelection(roots: roots, asks: asks.pending)
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
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Opaque: only the sidebar's column shows the window's
                // behind-window blur.
                .background(Color(nsColor: .windowBackgroundColor))
        }
        // Across both columns, not just the detail pane: the toolbar acts on the
        // selected session wherever you are. Its strip is opaque edge to edge; a
        // strip half blur and half pane put a seam through the reply field.
        .safeAreaInset(edge: .top, spacing: 0) {
            WindowToolbar(session: selected, feedDir: feed.feedDirectory,
                          sidebarVisible: $sidebarVisible, suggestion: suggestion)
                .background(Color(nsColor: .windowBackgroundColor))
                // Rebuilt per session so a half-typed reply or a notice about one
                // session can never be sent to, or read as about, the next.
                .id(selected?.id)
        }
        .task(id: selected?.cwd) {
            gitSnapshot = nil
            guard let cwd = selected?.cwd else { return }
            while !Task.isCancelled {
                gitSnapshot = await GitProbe.shared.snapshot(for: cwd)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// A floating glass panel inset from the window edges, after the macOS 26
    /// sidebar, rather than a split-view column. NavigationSplitView only floats
    /// its sidebar under a full-size-content title bar, and this window keeps a
    /// real title because the usage readout lives there when the status item is
    /// unplaced.
    private var sidebar: some View {
            VStack(spacing: 0) {
                OverviewStrip(overview: feed.overview,
                              fiveHour: feed.usageFiveHourPct,
                              sevenDay: feed.usageSevenDayPct,
                              usageStale: feed.usageIsStale,
                              usageHelp: feed.usageAsOfString,
                              history: feed.usageHistory,
                              totals: feed.usageTotalsRows,
                              totalsStatus: feed.usageTotalsStatus,
                              totalsDimmed: feed.usageTotals == nil || feed.usageTotalsIsStale,
                              totalsHelp: feed.usageTotalsTooltip,
                              fiveHourElapsed: feed.usageFiveHourElapsed,
                              sevenDayElapsed: feed.usageSevenDayElapsed,
                              fiveHourReset: feed.usageFiveHourResetRelative,
                              sevenDayReset: feed.usageSevenDayReset,
                              weekBars: feed.usageWeekBars)
                // Same reason the panel carries it: without this the window
                // surface answers questions fine and silently never rings.
                NotificationsNotice()
                if !feed.isSetupInstalled {
                    Divider()
                    SetupBanner(feed: feed, install: install)
                        .padding(.horizontal, 10).padding(.vertical, 10)
                }
                Divider()
                SessionSidebar(sessions: roots, asks: asks.pending, selection: $selection)
            }
            .frame(width: 250)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            // Clear, not regular: the panel should read as a pane of glass over
            // the window, with the rows carrying the contrast.
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.leading, 10).padding(.bottom, 10)
    }

    @ViewBuilder private var detail: some View {
            if let session = selected {
                SessionDetail(session: session,
                              children: feed.sessions.filter { $0.parentSessionId == session.id },
                              asks: asks.pending.filter { $0.sessionId == session.id },
                              feedDir: feed.feedDirectory,
                              history: feed.contextHistory[session.id] ?? [],
                              spend: feed.spendHistory[session.id] ?? [],
                              suggestion: suggestion)
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
    let asks: [AskRequest]
    @Binding var selection: String?

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

    private func asksFor(_ session: SessionFeed) -> Bool {
        asks.contains { $0.sessionId == session.id }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(groups) { section in
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
                                    .font(.claudeMono(11)).lineLimit(1)
                                // Under a project heading the project name is already
                                // overhead; only the pinned section needs it spelled out.
                                if section.id == "needs-you" {
                                    Text(session.projectName)
                                        .font(.claudeMono(10)).foregroundStyle(Color.label)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            if asksFor(session) {
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundStyle(Color.attention)
                            }
                        }
                        .help(session.statusLabel)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(rowLabel(session))
                        .tag(session.id)
                    }
                } header: {
                    SectionHeader(section: section)
                }
            }
        }
        .listStyle(.sidebar)
        // The glass panel is the background; the list's own would sit on top of it.
        .scrollContentBackground(.hidden)
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
            Spacer(minLength: 4)
            Text("\(section.sessionCount)")
                .font(.claudeMono(10)).foregroundStyle(Color.label)
            if let total = section.contextTotal {
                Text(FeedWatcher.formatTokens(total))
                    .font(.claudeMono(10)).foregroundStyle(Color.label)
            }
        }
    }
}

// MARK: - Detail

private struct SessionDetail: View {
    let session: SessionFeed
    let children: [SessionFeed]
    let asks: [AskRequest]
    let feedDir: URL
    /// This session's context over time. Passed in rather than read from the
    /// watcher, the way `OverviewStrip` already receives `usageHistory`.
    let history: [ContextSample]
    /// This session's spend over time, passed in the same way.
    let spend: [SpendSample]
    /// Shown as a glow on the button it names, in whichever card owns it.
    let suggestion: Suggestion?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                ForEach(asks) { ask in
                    AskCard(ask: ask)
                }

                // Side by side where the pane is wide enough, one column where it
                // isn't, and every card the height of the tallest in its row, so
                // each row reads as a set of equal tiles without a short card
                // stretched to match a chart two rows away. At three columns the
                // two wide cards alternate sides and every row is full: the
                // transcript's prose and the context chart are what use width,
                // and Session and Config, both short, share one column.
                TileGrid(minimum: 180, spacing: 10) {
                    TranscriptCard(path: session.stats.transcriptPath, sessionID: session.id)
                        .tileSpan(2)
                    SkillsCard(session: session, feedDir: feedDir, suggestion: suggestion)
                    // One full-width tile for everything git, straight under the
                    // transcript and skills: it is acted on, the stat tiles below
                    // are only read. The graph takes what is left beside
                    // fixed-width status and command columns, so the state and the
                    // actions sit next to the history.
                    HStack(alignment: .top, spacing: 10) {
                        GitGraphCard(cwd: session.cwd)
                        GitCard(cwd: session.cwd)
                            .frame(width: 230)
                        GitCommandsCard(session: session, feedDir: feedDir, suggestion: suggestion)
                            .frame(width: 250)
                    }
                    .tileSpan(.max)
                    costCard
                    cacheCard
                    sessionCard
                    contextCard.tileSpan(2)
                    ConfigCard(session: session, feedDir: feedDir)
                }

                if !children.isEmpty {
                    SubagentTree(parent: session, children: children)
                        .detailCard()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// No name or path: the selected sidebar row already names the session, and
    /// the toolbar copies or reveals its folder. Only the lines no card carries.
    @ViewBuilder private var header: some View {
        let evidence = session.restingEvidence(now: Date())
        if evidence != nil || session.attentionSummary != nil {
        VStack(alignment: .leading, spacing: 3) {
            if let evidence {
                Text(evidence).font(.claudeMono(11)).foregroundStyle(Color.label)
            }
            if let summary = session.attentionSummary {
                // Blue only when something is genuinely blocked. A finished
                // session that simply hasn't been typed at is not an alarm.
                Text(summary)
                    .font(.claudeMono(11))
                    .foregroundStyle(session.isBlockedOnYou ? Color.attention : Color.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        }
    }

    private var showsLinesBar: Bool {
        guard let added = session.stats.linesAdded,
              let removed = session.stats.linesRemoved else { return false }
        return added + removed > 0
    }

    /// Grouped rather than one long list. These arrive from the statusLine as
    /// four unrelated things -- what the turn cost, how full the window is, how
    /// the cache is behaving, how this session is configured -- and reading them
    /// as one column of twenty rows was the version that felt like a data dump.

    private var sessionCard: some View {
        let st = session.stats
        let progress = session.todoProgress
        return VStack(alignment: .leading, spacing: 8) {
            StatSection("Session", rows: [
                ("status", label(for: session)),
                ("todos", progress.total == 0 ? nil : "\(progress.done)/\(progress.total)"),
                ("host", session.host.isEmpty ? nil : session.host),
                ("pid", session.pid.map(String.init)),
                ("repo", st.repo),
            ])
            if progress.total > 0 {
                ShareBar(caption: "todos done",
                         ratio: Double(progress.done) / Double(progress.total),
                         tint: .usageGreen)
            }
        }
        .detailCard()
    }

    private var costCard: some View {
        let st = session.stats
        return VStack(alignment: .leading, spacing: 8) {
            StatSection("Cost", rows: [
                ("spend", st.costUSD.map(StatFormat.money)),
                ("wall", st.wallSeconds.map(StatFormat.duration)),
                ("api", st.apiSeconds.map(StatFormat.duration)),
                ("api share", st.apiShare.map(StatFormat.percent)),
                // The bar below labels both counts; the row stands in only when
                // there is no bar to draw.
                ("lines", showsLinesBar ? nil
                    : StatFormat.lines(added: st.linesAdded, removed: st.linesRemoved)),
            ])
            if st.costUSD != nil {
                SpendTrend(samples: spend)
            }
            if let share = st.apiShare {
                ShareBar(caption: "time waiting on the api", ratio: share, tint: .claude)
            }
            if showsLinesBar, let added = st.linesAdded, let removed = st.linesRemoved {
                LinesBar(added: added, removed: removed)
            }
        }
        .detailCard()
    }

    private var contextCard: some View {
        let st = session.stats
        return VStack(alignment: .leading, spacing: 8) {
            StatSection("Context", rows: [
                ("used", st.contextUsedPercent.map { "\($0)%" }),
                ("tokens", session.contextTokens.map { "\($0.formatted())" }),
                ("window", st.contextWindowSize.map { StatFormat.compactCount($0) }),
                // "over 200k" only when it is: "no" beside a 17% meter says nothing.
                ("over 200k", st.exceeds200k == true ? "yes" : nil),
            ])
            // The bar is share of the window; the chart is absolute tokens
            // against the tint bands, capped at the window. Neither is drawn
            // without a window to scale against: a chart with an invented
            // denominator is worse than the four rows above on their own.
            if let window = st.contextWindowSize, window > 0,
               let tokens = session.contextTokens {
                ContextMeter(tokens: tokens, window: window)
                ContextTrend(samples: history, window: window, tokens: tokens)
            }
        }
        .detailCard()
    }

    private var cacheCard: some View {
        let st = session.stats
        return HStack(alignment: .top, spacing: 12) {
            // The ring prints the hit ratio, so the rows don't.
            StatSection("Prompt cache", rows: [
                ("state", st.cacheWarm.map { $0 ? "warm" : "cold" }),
                ("ttl", st.cacheTTL),
                ("requests", st.cacheRequests.map(String.init)),
                ("misses", st.cacheMisses.map(String.init)),
            ])
            if let ratio = st.cacheHitRatio {
                Spacer(minLength: 0)
                CacheRing(ratio: ratio)
            }
        }
        .detailCard()
    }

    private func label(for session: SessionFeed) -> String {
        switch session.status {
        case .idle: return "idle"
        case .thinking: return "thinking"
        case .tool: return session.tool.isEmpty ? "running a tool" : "running \(session.tool)"
        case .attention: return "needs input"
        }
    }
}

// MARK: - Subagents

/// The session and its subagents drawn as a tree, each node tinted by what it
/// is doing. A parent waiting on three busy children then reads as a shape,
/// where the list it replaced read as three names and a dash.
private struct SubagentTree: View {
    let parent: SessionFeed
    let children: [SessionFeed]

    /// Where the trunk runs: under the centre of the parent node's dot, which
    /// sits past the node's 8pt inset.
    static let trunkX: CGFloat = 8 + 7 / 2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Subagents").font(.claudeMono(11)).foregroundStyle(Color.label)
                .padding(.bottom, 6)
            node(parent, name: parent.distinctName)
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                HStack(spacing: 0) {
                    TreeConnector(trunkX: Self.trunkX, isLast: index == children.count - 1)
                        .stroke(Color.label.opacity(0.6), lineWidth: 1)
                        .frame(width: Self.trunkX + 14)
                    node(child, name: child.agentType ?? "subagent")
                        .padding(.top, 6)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func node(_ session: SessionFeed, name: String) -> some View {
        let tint = Self.tint(session.status)
        return HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(name).font(.claudeMono(11))
            Text(session.statusLabel).font(.claudeMono(11)).foregroundStyle(tint)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(tint.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// The panel's status colours: orange is working, blue is needs you.
    static func tint(_ status: SessionStatus) -> Color {
        switch status {
        case .attention: return .attention
        case .thinking, .tool: return .claude
        case .idle: return .label
        }
    }
}

/// One child's share of the tree: the trunk down its row (stopping at the
/// branch on the last child, so the tree ends in a corner) and the branch
/// across to the node, meeting it at the node's vertical centre.
private struct TreeConnector: Shape {
    let trunkX: CGFloat
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        // The node is padded 6pt from the row's top, so its centre sits 3pt
        // below the row's.
        let branchY = rect.midY + 3
        return Path { path in
            path.move(to: CGPoint(x: trunkX, y: rect.minY))
            path.addLine(to: CGPoint(x: trunkX, y: isLast ? branchY : rect.maxY))
            path.move(to: CGPoint(x: trunkX, y: branchY))
            path.addLine(to: CGPoint(x: rect.maxX, y: branchY))
        }
    }
}

// MARK: - A pending question, in full

private struct AskCard: View {
    let ask: AskRequest
    @State private var answered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ask.kind == .permission ? "Permission needed" : (ask.question?.header ?? "Question"))
                .font(.claudeMono(11)).foregroundStyle(Color.attention)
            Text(prompt).font(.claudeMono(13)).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)

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
                                in: RoundedRectangle(cornerRadius: 4))
            }

            if let answered {
                Text("Answered: \(answered)").font(.claudeMono(11)).foregroundStyle(Color.label)
            } else {
                // Full labels *and* their descriptions — the reason this surface
                // exists. A banner shows two buttons and no descriptions at all.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                        Button { answer(choice.answer, label: choice.label) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(choice.label).font(.claudeMono(11))
                                if let detail = choice.detail {
                                    Text(detail).font(.claudeMono(10))
                                        .foregroundStyle(Color.label)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
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
        answered = AskInbox.shared.answer(ask, with: value)
            ? label
            : "expired — answer it in the terminal"
        AskInbox.shared.rescan()
    }
}

// MARK: - Free-text reply

/// The window's one-row toolbar, edge to edge: the sidebar toggle, the reply
/// field and the session actions on glass, with the last outcome from any of
/// them said underneath. Git actions live in the Git commands card.
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
    @State private var notice: NoticeMessage?

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
                    if let session {
                        ReplyBox(session: session, feedDir: feedDir, notice: $notice)
                        ActionBar(session: session, feedDir: feedDir, notice: $notice,
                                  suggestion: suggestion)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }
            if let notice {
                Notice(notice)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 6))
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
                .font(.claudeMono(11))
                .buttonStyle(.borderless)
                .disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }

    private func send() {
        let message = text.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty, !sending else { return }
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

private extension View {
    /// One section of the detail pane as a card, after the footage library's:
    /// the design system's radius-lg on a surface one step off the pane, with no
    /// border or shadow. Fills its grid column so neighbours line up at the edges.
    func detailCard() -> some View { modifier(DetailCard()) }

    /// How many `TileGrid` columns this card takes.
    func tileSpan(_ columns: Int) -> some View { layoutValue(key: TileSpan.self, value: columns) }
}

private struct DetailCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
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
private struct TileGrid: Layout {
    let minimum: CGFloat
    let spacing: CGFloat
    /// The rows are composed for three columns (wide cards alternating sides);
    /// a fourth let them wrap into a row with one card and a gap.
    var maxColumns = 3

    private struct Slot {
        let index: Int
        let column: Int
        let span: Int
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let heights = rows(width: width, subviews: subviews).map(\.height)
        return CGSize(width: width,
                      height: heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = grid(width: bounds.width).columnWidth
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            for slot in row.slots {
                subviews[slot.index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(slot.column) * (columnWidth + spacing), y: y),
                    proposal: ProposedViewSize(width: width(slot.span, columnWidth), height: row.height))
            }
            y += row.height + spacing
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
        var packed: [[Slot]] = []
        var used = columns
        for index in subviews.indices {
            let span = min(max(1, subviews[index][TileSpan.self]), columns)
            if used + span > columns {
                packed.append([])
                used = 0
            }
            packed[packed.count - 1].append(Slot(index: index, column: used, span: span))
            used += span
        }
        return packed.map { slots in
            (slots, slots.map {
                subviews[$0.index]
                    .sizeThatFits(ProposedViewSize(width: self.width($0.span, columnWidth), height: nil))
                    .height
            }.max() ?? 0)
        }
    }
}

private struct TileSpan: LayoutValueKey {
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
                Text(title).font(.claudeMono(10)).fontWeight(.semibold)
                    .foregroundStyle(Color.label)
                    .textCase(.uppercase).tracking(0.8)
                if let refresh {
                    Button("Refresh", action: refresh)
                        .font(.claudeMono(10)).buttonStyle(.link)
                }
            }
            if present.isEmpty {
                Text(empty).font(.claudeMono(11)).foregroundStyle(Color.label)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    ForEach(present, id: \.0) { key, value, note in
                        GridRow {
                            // Proportional labels against monospaced values, so the
                            // eye separates the two columns by face as well as by gap.
                            Text(key).font(.system(size: 11)).foregroundStyle(Color.label)
                                .gridColumnAlignment(.leading)
                            HStack(spacing: 8) {
                                // Cut in the middle, not wrapped: in a card-width
                                // column a bundle id broke mid-word onto a second
                                // line. Both ends of an id or path carry meaning.
                                Text(value).font(.claudeMono(11)).textSelection(.enabled)
                                    .lineLimit(1).truncationMode(.middle).help(value)
                                if let note {
                                    Text(note).font(.claudeMono(10))
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
enum StatFormat {
    /// Always two decimals: a session starts in the cents, and a rounded "$0"
    /// would read as free.
    static func money(_ usd: Double) -> String { String(format: "$%.2f", usd) }

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
}


// MARK: - Overview

/// Totals across every session, above the sidebar groups. The one thing here
/// that isn't in the detail pane is the shape of the 5h window over time, which
/// only means anything aggregated.
private struct OverviewStrip: View {
    let overview: FeedWatcher.Overview
    /// The menu bar's own resolution (poll, then a live session, then the
    /// persisted snapshot), not the live feeds alone -- read from the feeds, the
    /// window went blank or disagreed whenever only the poll or cache had it.
    let fiveHour: Int?
    let sevenDay: Int?
    let usageStale: Bool
    let usageHelp: String
    let history: [UsageSample]
    /// ccusage totals across every session, ended ones included -- the lines
    /// above add up only the sessions that are live right now.
    let totals: [FeedWatcher.TotalsRow]
    let totalsStatus: String
    let totalsDimmed: Bool
    let totalsHelp: String
    let fiveHourElapsed: Double?
    let sevenDayElapsed: Double?
    let fiveHourReset: String?
    let sevenDayReset: String?
    let weekBars: [UsageTotalsPoller.WeekBar]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The rate-limit windows lead, not the dollar figure. On a Max plan
            // these are the only numbers that can actually stop you; the money
            // is a proxy for burn and is never charged.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // No reading is not a reading of zero. The old `?? "—"` printed a
                // dash tinted `usageTint(0)`, so a window that had never reported
                // drew in the green of untouched headroom.
                if let headline = StatFormat.usageHeadline(fiveHour) {
                    Text(headline.text)
                        .font(.claudeMono(18)).fontWeight(.semibold)
                        .foregroundStyle(Color.usageTint(headline.level))
                    Text("of 5h").font(.claudeMono(10)).foregroundStyle(Color.label)
                } else {
                    // Scoped to the live window, not to usage in general. The
                    // rejected wording here was the panel's own phrase about
                    // having no usage data, which over the sparkline below --
                    // drawing retained history -- would have been the same fault
                    // this slice exists to remove.
                    Text("no current 5h reading")
                        .font(.claudeMono(11)).foregroundStyle(Color.label)
                }
                // Outside the branch: the two percentages are filled by separate
                // `compactMap`s, so 7d can be known while 5h is not.
                if let sevenDay {
                    // The separator belongs to the 5h reading, so it goes when
                    // that reading does -- "no current 5h reading · 40% of 7d"
                    // would contradict itself in the same breath.
                    Text("\(fiveHour == nil ? "" : "· ")\(sevenDay)% of 7d")
                        .font(.claudeMono(10)).foregroundStyle(Color.label)
                }
                Spacer(minLength: 0)
            }
            .opacity(usageStale ? 0.5 : 1)
            .help(usageHelp)

            VStack(spacing: 4) {
                if let fiveHour {
                    PaceBar(label: "5h", pct: fiveHour, elapsed: fiveHourElapsed, reset: fiveHourReset)
                }
                if let sevenDay {
                    PaceBar(label: "7d", pct: sevenDay, elapsed: sevenDayElapsed, reset: sevenDayReset)
                }
            }
            .opacity(usageStale ? 0.5 : 1)

            // Labelled for what it is. "$93.62 today" under a dollar sign reads
            // as a bill, and on a subscription plan that is simply wrong.
            if let spend = overview.spendUSD {
                Text("\(StatFormat.money(spend)) api-equivalent, not billed")
                    .font(.claudeMono(10)).foregroundStyle(Color.label)
            }

            Text(liveLine).font(.claudeMono(10)).foregroundStyle(Color.label)
                .lineLimit(2)

            // Headed, because every figure above counts live sessions only and
            // these count every transcript -- same words, different population.
            StatSection("All sessions", rows: totals.map { ($0.label, $0.value, nil) },
                        empty: totalsStatus)
                .padding(.top, 4)
                .opacity(totalsDimmed ? 0.6 : 1)
                .help(totalsHelp)

            if !weekBars.isEmpty {
                WeekChart(bars: weekBars)
                    .opacity(totalsDimmed ? 0.6 : 1)
            }

            UsageHistoryChart(samples: history)
                .padding(.top, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("5-hour usage over time")
                .accessibilityValue(Sparkline.spokenValue(history))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Counts, context and lines on one line: each was a line of its own, and
    /// four one-fact lines pushed the session list half a screen down.
    private var liveLine: String {
        var parts = ["\(overview.sessions) session\(overview.sessions == 1 ? "" : "s")"]
        if overview.working > 0 { parts.append("\(overview.working) working") }
        if overview.waiting > 0 { parts.append("\(overview.waiting) waiting") }
        if let tokens = overview.contextTokens {
            parts.append("\(StatFormat.compactCount(tokens)) ctx")
        }
        if let diff = StatFormat.lines(added: overview.linesAdded,
                                       removed: overview.linesRemoved) {
            parts.append("\(diff) lines")
        }
        return parts.joined(separator: " · ")
    }
}

/// A limit window's usage against how much of the window has gone by.
///
/// The fill is usage; the tick is time. Fill past the tick means burning faster
/// than the window refills, which the percentage alone cannot say: 40% is fine
/// an hour before reset and alarming ten minutes after one.
struct PaceBar: View {
    let label: String
    let pct: Int
    let elapsed: Double?
    let reset: String?

    var body: some View {
        let ratio = CGFloat(min(100, max(0, pct))) / 100
        HStack(spacing: 6) {
            Text(label).font(.claudeMono(10)).foregroundStyle(Color.label)
                .frame(width: 16, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.22)).frame(height: 5)
                    Capsule().fill(Color.usageTint(pct))
                        .frame(width: max(pct > 0 ? 3 : 0, w * ratio), height: 5)
                    if let elapsed {
                        Capsule().fill(Color.primary.opacity(0.85))
                            .frame(width: 2, height: 10)
                            .offset(x: min(w - 2, max(0, w * elapsed - 1)))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 10)
            if let reset {
                Text(reset).font(.claudeMono(10)).foregroundStyle(Color.label).fixedSize()
            }
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label == "5h" ? "5-hour" : "7-day") usage")
        .accessibilityValue(helpText)
    }

    private var helpText: String {
        var text = "\(pct)% used"
        if let elapsed {
            let gone = Int((elapsed * 100).rounded())
            text += " with \(gone)% of the window gone"
            text += Double(pct) / 100 > elapsed ? ", ahead of pace" : ", within pace"
        }
        if let reset { text += "; resets \(reset)" }
        return text
    }
}

/// Tokens per day, Monday to Sunday, from the ccusage daily rows.
///
/// Scaled to the week's own peak: the question is which day was heavy, and
/// there is no limit to draw against. Days still ahead are faint stubs, not
/// zero-height bars, so "hasn't happened" never reads as "used nothing".
struct WeekChart: View {
    let bars: [UsageTotalsPoller.WeekBar]

    var body: some View {
        let peak = max(1, bars.compactMap(\.tokens).max() ?? 0)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(fill(bar))
                                .frame(height: height(bar, peak: peak, box: geo.size.height))
                        }
                    }
                    Text(bar.label).font(.claudeMono(9))
                        .foregroundStyle(bar.isToday ? Color.primary : Color.label)
                }
                .help(bar.tokens.map { "\(FeedWatcher.formatTokens($0)) tokens" } ?? "not yet")
            }
        }
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tokens by day this week")
        .accessibilityValue(bars.compactMap { bar in
            bar.tokens.map { "\(bar.label) \(FeedWatcher.formatTokens($0))" }
        }.joined(separator: ", "))
    }

    private func fill(_ bar: UsageTotalsPoller.WeekBar) -> Color {
        if bar.isToday { return .claude }
        return Color.secondary.opacity(bar.tokens == nil ? 0.15 : 0.55)
    }

    private func height(_ bar: UsageTotalsPoller.WeekBar, peak: Int, box: CGFloat) -> CGFloat {
        guard let tokens = bar.tokens else { return 2 }
        return max(tokens > 0 ? 2 : 0, box * CGFloat(tokens) / CGFloat(peak))
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
                    .font(.claudeMono(10)).foregroundStyle(Color.label)
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

    /// The detail chart's y-axis top: headroom above the heaviest band, or the
    /// session's own peak past that, and never more than the window can hold.
    static func ceiling(window: Int, samples: [ContextSample]) -> Int {
        min(window, max(250_000, samples.map(\.tokens).max() ?? 0))
    }

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

/// Where each spend sample sits in a unit box.
enum SpendChart {
    /// Scaled 0 to the session's own peak, unlike context: spend has no window
    /// to be a share of, and any fixed ceiling would be invented. The floor stays
    /// at 0 so a line that barely moved still reads as barely moved.
    static func unitPoints(_ samples: [SpendSample]) -> [CGPoint]? {
        guard samples.count >= 2, let first = samples.first, let last = samples.last,
              let peak = samples.map(\.usd).max(), peak > 0 else { return nil }
        let span = last.at - first.at
        return samples.enumerated().map { index, sample in
            let x = span > 0 ? (sample.at - first.at) / span
                             : Double(index) / Double(samples.count - 1)
            return CGPoint(x: x, y: 1 - max(0, sample.usd / peak))
        }
    }
}

/// Where each usage sample sits in a unit box, for one of its two readings.
/// x spans the whole buffer's time range, so the 5h and 7d lines share an axis
/// even when older samples carry no 7d reading.
enum UsageChart {
    /// The percentages `Color.usageTint` changes colour at.
    static let bandFloors = [50, 75, 90]

    static func unitPoints(_ samples: [UsageSample], _ value: (UsageSample) -> Int?) -> [CGPoint]? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.at - first.at
        let points = samples.enumerated().compactMap { index, sample -> CGPoint? in
            guard let pct = value(sample) else { return nil }
            let x = span > 0 ? (sample.at - first.at) / span
                             : Double(index) / Double(max(1, samples.count - 1))
            return CGPoint(x: x, y: 1 - min(1, max(0, Double(pct) / 100)))
        }
        return points.count >= 2 ? points : nil
    }
}

/// The 5h and 7d windows over the retained samples, with the usage bands ruled
/// in so a line's height reads against the levels its colour changes at.
///
/// Time-scaled, unlike the panel's `Sparkline`: at this size a gap between
/// polls (the Mac asleep, the poller failing) is worth seeing as a gap.
/// 7d is dashed and neutral -- it is the slower of the two and the one the
/// tint is not about.
struct UsageHistoryChart: View {
    let samples: [UsageSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ForEach(UsageChart.bandFloors, id: \.self) { band in
                    let y = h * (1 - CGFloat(band) / 100)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.usageTint(band).opacity(0.4),
                            style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
                if let five = UsageChart.unitPoints(samples, { $0.pct }) {
                    let points = five.map { CGPoint(x: $0.x * w, y: $0.y * h) }
                    let tint = Color.usageTint(samples.last?.pct ?? 0)
                    ChartPath.area(points, baseline: h).fill(tint.opacity(0.15))
                    ChartPath.line(points).stroke(tint, lineWidth: 1.5)
                } else {
                    Text("no usage history yet")
                        .font(.claudeMono(10)).foregroundStyle(Color.label)
                }
                if let seven = UsageChart.unitPoints(samples, { $0.sevenDayPct }) {
                    ChartPath.line(seven.map { CGPoint(x: $0.x * w, y: $0.y * h) })
                        .stroke(Color.label, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            .frame(height: 36)

            if let first = samples.first, let last = samples.last, samples.count >= 2 {
                let now = Date()
                HStack(spacing: 6) {
                    Text(StatFormat.age(Date(timeIntervalSince1970: first.at), now: now) ?? "")
                    Spacer(minLength: 0)
                    Text("─ 5h  ┄ 7d")
                    Spacer(minLength: 0)
                    Text(StatFormat.age(Date(timeIntervalSince1970: last.at), now: now) ?? "")
                }
                .font(.claudeMono(10)).foregroundStyle(Color.label)
            }
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
                Capsule().fill(Color.contextTint(tokens))
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

/// A captioned share-of-a-whole bar, in the meter's capsule language: the row
/// above prints the number, this draws it as a length.
struct ShareBar: View {
    let caption: String
    let ratio: Double
    let tint: Color

    var body: some View {
        let clamped = min(1, max(0, ratio))
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.22))
                    Capsule().fill(tint)
                        .frame(width: max(clamped > 0 ? 3 : 0, geo.size.width * clamped))
                }
            }
            .frame(height: 5)
            Text(caption).font(.claudeMono(10)).foregroundStyle(Color.label)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

/// Lines added against lines removed, one bar split at their proportion, so a
/// session that mostly deleted reads differently from one that mostly wrote.
struct LinesBar: View {
    let added: Int
    let removed: Int

    var body: some View {
        let share = Double(added) / Double(added + removed)
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if added > 0 {
                        Capsule().fill(Color.usageGreen)
                            .frame(width: max(3, (geo.size.width - 2) * share))
                    }
                    if removed > 0 {
                        Capsule().fill(Color.usageRed)
                    }
                }
            }
            .frame(height: 5)
            HStack {
                Text("+\(added) added")
                Spacer(minLength: 0)
                Text("-\(removed) removed")
            }
            .font(.claudeMono(10)).foregroundStyle(Color.label)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lines changed")
        .accessibilityValue("\(added) added, \(removed) removed")
    }
}

/// The cache hit ratio as a ring beside the rows, the one number in the card
/// worth reading at a glance.
struct CacheRing: View {
    let ratio: Double

    var body: some View {
        let clamped = min(1, max(0, ratio))
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.22), lineWidth: 5)
            Circle().trim(from: 0, to: clamped)
                .stroke(Color.usageGreen, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((clamped * 100).rounded()))%")
                .font(.claudeMono(10)).fontWeight(.semibold)
        }
        .frame(width: 44, height: 44)
        .padding(.top, 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cache hit ratio")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

/// Context over the session's life, on an absolute token axis.
///
/// Not auto-zoomed to the data: a 20k session must still draw as a crawl along
/// the bottom, or it looks as full as a heavy one. But not the whole window
/// either -- at 1M everything under 200k was a hairline in a box of empty
/// space. The axis is `ContextChart.ceiling`, and the ruled band lines are the
/// same absolute counts `contextTint` uses, so a line crossing one means what
/// the colour means. Share of the window is the meter's job, drawn above.
/// A compaction shows as a cliff, and is not smoothed -- it is the most
/// informative shape the chart has.
private struct ContextTrend: View {
    let samples: [ContextSample]
    let window: Int
    let tokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                // The bands `contextTint` switches at, where they fall inside the
                // window. Only the highest is labelled: on a 1M window all three
                // sit within a few points of each other and their labels would
                // overprint. The rule colours say which is which.
                let top = ContextChart.ceiling(window: window, samples: samples)
                let bands = ContextChart.bandFloors.filter { $0 < top }
                ForEach(bands, id: \.self) { band in
                    let y = h * (1 - CGFloat(band) / CGFloat(top))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.contextTint(band).opacity(0.4),
                            style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    if band == bands.last {
                        Text(StatFormat.compactCount(band))
                            .font(.claudeMono(9)).foregroundStyle(Color.label)
                            .position(x: w - 14, y: max(6, y - 6))
                    }
                }
                if let unit = ContextChart.unitPoints(samples, window: top) {
                    let points = unit.map { CGPoint(x: $0.x * w, y: $0.y * h) }
                    let tint = Color.contextTint(tokens)
                    ChartPath.area(points, baseline: h).fill(tint.opacity(0.15))
                    ChartPath.line(points).stroke(tint, lineWidth: 1.5)
                } else {
                    Text("no context history yet")
                        .font(.claudeMono(10)).foregroundStyle(Color.label)
                }
            }
            .frame(height: 64)

            if let first = samples.first, let last = samples.last, samples.count >= 2 {
                let now = Date()
                HStack {
                    Text(StatFormat.age(Date(timeIntervalSince1970: first.at), now: now) ?? "")
                    Spacer(minLength: 0)
                    Text(StatFormat.age(Date(timeIntervalSince1970: last.at), now: now) ?? "")
                }
                .font(.claudeMono(10)).foregroundStyle(Color.label)
            }
        }
        .accessibilityLabel("Context over this session")
    }
}


/// Cumulative spend over the session, time-scaled like `ContextTrend` so an
/// idle stretch reads as flat and a heavy turn as a climb. The top is labelled
/// with the peak because the axis is the session's own, not a fixed one.
private struct SpendTrend: View {
    let samples: [SpendSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                if let unit = SpendChart.unitPoints(samples),
                   let peak = samples.map(\.usd).max() {
                    let points = unit.map { CGPoint(x: $0.x * w, y: $0.y * h) }
                    ChartPath.area(points, baseline: h).fill(Color.claude.opacity(0.15))
                    ChartPath.line(points).stroke(Color.claude, lineWidth: 1.5)
                    Text(StatFormat.money(peak))
                        .font(.claudeMono(9)).foregroundStyle(Color.label)
                        .position(x: 22, y: 6)
                } else {
                    Text("no spend history yet")
                        .font(.claudeMono(10)).foregroundStyle(Color.label)
                }
            }
            .frame(height: 40)

            if let first = samples.first, let last = samples.last, samples.count >= 2 {
                let now = Date()
                HStack {
                    Text(StatFormat.age(Date(timeIntervalSince1970: first.at), now: now) ?? "")
                    Spacer(minLength: 0)
                    Text(StatFormat.age(Date(timeIntervalSince1970: last.at), now: now) ?? "")
                }
                .font(.claudeMono(10)).foregroundStyle(Color.label)
            }
        }
        .accessibilityLabel("Spend over this session")
    }
}


// MARK: - What Claude is actually doing

/// The last thing Claude said, what you last asked, and what it just ran.
///
/// Answers the question the rest of the pane cannot: a row saying "needs input"
/// tells you something is waiting, not what it wants or how to reply. This is
/// read from the session's own transcript, which no feed file carries.
private struct TranscriptCard: View {
    let path: String?
    let sessionID: String
    @State private var snapshot = TranscriptSnapshot()
    @State private var expanded = false

    var body: some View {
        // Collapsed, every block is always present and reserves its full clamp,
        // so the card is one fixed height: it used to grow and shrink with each
        // reply and jolt the grid below it every few seconds. Expanded is the
        // one state allowed to size to its text, because you asked for that.
        VStack(alignment: .leading, spacing: 10) {
            Labelled("you asked", snapshot.lastPrompt, limit: expanded ? nil : 1)
            Labelled("claude said", snapshot.lastAssistantText, limit: expanded ? nil : 3)
            Labelled("just ran",
                     snapshot.recentTools.isEmpty
                         ? nil : snapshot.recentTools.joined(separator: " · "),
                     limit: expanded ? nil : 1)
            Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                .font(.claudeMono(10)).buttonStyle(.link)
        }
        .detailCard()
        .task(id: sessionID) { await refresh() }
        // Re-read on the same cadence the rows already tick at. The read is a
        // bounded tail, not the whole file, so this stays cheap.
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            Task { await refresh() }
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

    init(_ title: String, _ body: String?, limit: Int?) {
        self.title = title
        self.body_ = body
        self.limit = limit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.claudeMono(10)).fontWeight(.semibold)
                .foregroundStyle(Color.label).textCase(.uppercase)
            Text(body_ ?? "not recorded")
                .font(.claudeMono(11))
                .foregroundStyle(body_ == nil ? Color.label : Color.primary)
                .lineLimit(limit ?? Int.max, reservesSpace: limit != nil)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Self.groups, id: \.self) { group in
                HStack(spacing: 6) {
                    ForEach(group) { action in
                        let reason = SessionActions.unavailableReason(action,
                                                                      session: session,
                                                                      hasPane: hasPane)
                        Button { start(action) } label: {
                            Image(systemName: action.symbol).frame(width: 18, height: 18)
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
    @State private var notice: NoticeMessage?
    @State private var sending = false

    var body: some View {
        let st = session.stats
        let reason = SkillShortcut.unavailableReason(session: session, hasPane: hasPane)
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("Config")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("model").font(.system(size: 11)).foregroundStyle(Color.label)
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
                        Text(session.model ?? st.modelID ?? "unknown").font(.claudeMono(11))
                    }
                    .fixedSize()
                    .disabled(reason != nil || sending)
                    .help(reason ?? "Switch model")
                }
                GridRow {
                    Text("effort").font(.system(size: 11)).foregroundStyle(Color.label)
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
                        Text(st.effort ?? "default").font(.claudeMono(11))
                    }
                    .fixedSize()
                    .disabled(reason != nil || sending)
                    .help(reason ?? "Change effort")
                }
                // Read-only facts, same grid so the columns line up; a nil drops its row.
                ForEach([("thinking", st.thinking.map { $0 ? "on" : "off" }),
                         ("style", st.outputStyle),
                         ("claude", st.claudeVersion)], id: \.0) { key, value in
                    if let value {
                        GridRow {
                            Text(key).font(.system(size: 11)).foregroundStyle(Color.label)
                            Text(value).font(.claudeMono(11)).lineLimit(1)
                        }
                    }
                }
            }
            if let notice { Notice(notice) }
        }
        .detailCard()
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
        RoundedRectangle(cornerRadius: 9, style: .continuous)
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
private struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.claudeMono(10)).fontWeight(.semibold)
            .foregroundStyle(Color.label)
            .textCase(.uppercase).tracking(0.8)
    }
}

/// The session skills as one-click slash commands.
private struct SkillsCard: View {
    let session: SessionFeed
    let feedDir: URL
    let suggestion: Suggestion?
    @State private var notice: NoticeMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("Skills")
            ShortcutChips(session: session, feedDir: feedDir,
                          shortcuts: installedShortcuts.filter { $0.group == .skill },
                          suggestion: suggestion, notice: $notice)
            if let notice { Notice(notice) }
        }
        .detailCard()
    }
}

/// Git work in one place: the actions that run `git`/`gh` directly, then the
/// git skills, which go through Claude.
private struct GitCommandsCard: View {
    let session: SessionFeed
    let feedDir: URL
    let suggestion: Suggestion?
    @State private var notice: NoticeMessage?
    @State private var snapshot: GitSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("Git commands")
            GitButtons(cwd: session.cwd, suggestion: suggestion, notice: $notice, snapshot: $snapshot)
            ShortcutChips(session: session, feedDir: feedDir,
                          shortcuts: installedShortcuts.filter { $0.group == .git },
                          suggestion: suggestion, notice: $notice,
                          idleReason: { SkillShortcut.idleReason($0, snapshot: snapshot) })
            if let notice { Notice(notice) }
            Divider().padding(.vertical, 2)
            AutomationToggles(session: session, feedDir: feedDir)
        }
        .detailCard()
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
                toggle("Auto-merge PR", isOn: snap.autoMerge == true,
                       disabledReason: autoMergeReason(snap)) { on in
                    if on { confirm = .autoMerge } else { setAutoMerge(false, snap) }
                }
                toggle("Auto-push on main", isOn: GitAutomation.mainPushEnabled(toplevel: top),
                       disabledReason: nil) { on in
                    if on { confirm = .mainPush } else { setMainPush(false, top) }
                }
                toggle("Auto-commit (all projects)", isOn: autoCommitOn, disabledReason: nil) { on in
                    if on { confirm = .autoCommit } else { setAutoCommit(false) }
                }
                toggle("Auto-PR", isOn: GitAutomation.autoPREnabled(toplevel: top),
                       disabledReason: snap.ghInstalled ? nil : "The gh CLI isn't installed.") { on in
                    if on { confirm = .autoPR } else { GitAutomation.setAutoPR(false, toplevel: top); reread() }
                }
                if let result = autoPR.lastResult[top] { Notice(result) }
                let fixReason = GitAutomation.autoFixUnavailableReason(snap)
                    ?? SkillShortcut.unavailableReason(session: session, hasPane: hasPane)
                Button { confirm = .autoFix } label: {
                    Label("Auto-fix CI & comments", systemImage: "wrench.and.screwdriver")
                        .font(.claudeMono(10)).lineLimit(1)
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

    private func toggle(_ title: String, isOn: Bool, disabledReason: String?,
                        set: @escaping (Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: set))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.claudeMono(10))
            .disabled(disabledReason != nil || busy)
            .help(disabledReason ?? title)
    }

    private func autoMergeReason(_ snap: GitSnapshot) -> String? {
        guard snap.ghInstalled else { return "The gh CLI isn't installed." }
        guard case .open(_, _, let draft) = snap.pr else { return "There is no open PR on this branch." }
        if draft { return "The PR is a draft." }
        // Enabling can merge at once when checks already pass, and --delete-branch
        // then switches this checkout: the same guard as Merge.
        if snap.isDirty, snap.autoMerge != true { return "There are uncommitted changes. Commit or stash them first." }
        return nil
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
    /// Why a chip has nothing to act on even though it could be typed.
    var idleReason: (SkillShortcut) -> String? = { _ in nil }
    @State private var hasPane = false
    @State private var sending = false
    @State private var confirming: SkillShortcut?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)],
                  alignment: .leading, spacing: 6) {
            ForEach(shortcuts) { shortcut in
                let reason = SkillShortcut.unavailableReason(session: session, hasPane: hasPane)
                    ?? idleReason(shortcut)
                Button { start(shortcut) } label: {
                    // The name alone; the slash is implied by the card, and the
                    // tooltip and the notice still say the command typed.
                    Label(shortcut.name, systemImage: shortcut.symbol)
                        .font(.claudeMono(10))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)
                .disabled(reason != nil || sending)
                // Lighter than the toolbar's 0.45: these carry names worth
                // reading while the session is busy.
                .opacity(reason == nil ? 1 : 0.7)
                .suggestedGlow(reason == nil && suggestion?.action == .command(shortcut.command))
                .help(reason ?? (suggestion?.action == .command(shortcut.command) ? suggestion?.reason : nil)
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
    @State private var rows: [GraphLine]?
    @State private var read = false

    /// Read this many, then show only their landmarks (`GitGraph.condense`),
    /// so the card fits its rows instead of scrolling.
    private static let limit = 40
    private static let rowHeight: CGFloat = 20
    private static let laneWidth: CGFloat = 12
    /// Beyond this many lanes the drawing is clipped rather than letting a
    /// repo full of stale remote branches push the text off the card.
    private static let maxLanes = 8
    private static let palette: [Color] = [.claude, .identityCyan, .identityPurple,
                                           .identityJade, .usageAmber, .identityIndigo]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("History")
            if let rows, !rows.isEmpty {
                let lanes = min(Self.maxLanes, rows.map(\.width).max() ?? 1)
                HStack(alignment: .top, spacing: 8) {
                    graph(rows)
                        .frame(width: CGFloat(lanes) * Self.laneWidth,
                               height: CGFloat(rows.count) * Self.rowHeight)
                        .clipped()
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, line in
                            label(line).frame(height: Self.rowHeight)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(rows != nil ? "no commits yet" : read ? "history couldn't be read" : "reading…")
                    .font(.claudeMono(11)).foregroundStyle(Color.label)
            }
        }
        .detailCard()
        .task(id: cwd) { await poll() }
    }

    private func graph(_ rows: [GraphLine]) -> some View {
        Canvas { context, _ in
            let h = Self.rowHeight
            func x(_ lane: Int) -> CGFloat { CGFloat(lane) * Self.laneWidth + Self.laneWidth / 2 }
            func y(_ row: Int) -> CGFloat { CGFloat(row) * h + h / 2 }
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
                    context.fill(dot, with: .color(Color(nsColor: .windowBackgroundColor)))
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
                .font(.claudeMono(10)).foregroundStyle(Color.label)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ row: GraphRow) -> some View {
        HStack(spacing: 6) {
            Text(row.commit.shortSHA).foregroundStyle(Color.label)
            ForEach(row.commit.refs, id: \.self) { ref in
                Text(ref).font(.claudeMono(9))
                    .foregroundStyle(ref.hasPrefix("HEAD") ? Color.usageGreen : Color.identityCyan)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .fixedSize()
            }
            // No subject line: the card is a picture of branches, and the
            // message sits a hover away without pushing the refs off the row.
            Spacer(minLength: 8)
            if let at = row.commit.committedAt {
                Text(FeedWatcher.compactAge(since: at)).foregroundStyle(Color.label).fixedSize()
            }
        }
        .font(.claudeMono(11))
        .contentShape(Rectangle())
        .help(row.commit.subject)
    }

    /// Local and cheap, so a commit made in the session shows within seconds.
    private func poll() async {
        rows = nil
        read = false
        while !Task.isCancelled {
            let dir = cwd
            let fresh = await Task.detached(priority: .utility) {
                GitProbe.graph(cwd: dir, limit: Self.limit)
            }.value
            if fresh != rows { rows = fresh }
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
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11))
                .foregroundStyle(tint).frame(width: 14)
            Text(label).font(.system(size: 11)).foregroundStyle(Color.label)
                .frame(width: 46, alignment: .leading)
            Text(value).font(.claudeMono(11))
                .foregroundStyle(tone == .neutral ? Color.label : Color.primary)
                .lineLimit(1).truncationMode(.middle).help(value)
        }
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
        .detailCard()
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
                        Text("default").font(.claudeMono(9)).foregroundStyle(Color.label)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.18), in: Capsule())
                    }
                }
                .help(snap.upstream.map { "tracks \($0)" } ?? "no upstream")
                VStack(alignment: .leading, spacing: 5) {
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
                    .font(.claudeMono(9)).foregroundStyle(Color.label)
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
            Text("Git").font(.claudeMono(10)).fontWeight(.semibold)
                .foregroundStyle(Color.label).textCase(.uppercase).tracking(0.8)
            Button("Refresh", action: reload).font(.claudeMono(10)).buttonStyle(.link)
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
                .font(.claudeMono(10)).foregroundStyle(Color.label)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)],
                          alignment: .leading, spacing: 6) {
                    ForEach(GitAction.allCases.filter { !$0.isTool }) { action in
                        let block = GitActions.unavailableReason(action, snapshot: snap)
                        Button { start(action) } label: {
                            Label(action.title, systemImage: action.symbol)
                                .font(.claudeMono(10))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                            Image(systemName: action.symbol).frame(width: 22, height: 18)
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
