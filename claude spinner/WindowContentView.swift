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
        NavigationSplitView {
            VStack(spacing: 0) {
                OverviewStrip(overview: feed.overview, history: feed.usageHistory,
                              totals: feed.usageTotalsRows,
                              totalsStatus: feed.usageTotalsStatus,
                              totalsDimmed: feed.usageTotals == nil || feed.usageTotalsIsStale,
                              totalsHelp: feed.usageTotalsTooltip)
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
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            if let session = selected {
                SessionDetail(session: session,
                              children: feed.sessions.filter { $0.parentSessionId == session.id },
                              asks: asks.pending.filter { $0.sessionId == session.id },
                              feedDir: feed.feedDirectory,
                              history: feed.contextHistory[session.id] ?? [])
                .id(session.id)
                .onAppear { if selection == nil { selection = session.id } }
            } else {
                ContentUnavailableView("No active sessions",
                                       systemImage: "moon.zzz",
                                       description: Text("Sessions appear here as Claude Code runs."))
            }
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
            asked: Set(asks.map(\.sessionId)))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                ForEach(asks) { ask in
                    AskCard(ask: ask)
                }

                TranscriptCard(path: session.stats.transcriptPath, sessionID: session.id)

                ReplyBox(session: session, feedDir: feedDir)
                ActionBar(session: session, feedDir: feedDir)
                GitCard(cwd: session.cwd)

                stats

                if !children.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Subagents").font(.claudeMono(11)).foregroundStyle(Color.label)
                        ForEach(children) { child in
                            HStack(spacing: 8) {
                                Text(child.agentType ?? "subagent").font(.claudeMono(11))
                                Text(child.tool.isEmpty ? "—" : child.tool)
                                    .font(.claudeMono(11)).foregroundStyle(Color.label)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.distinctName).font(.claudeMono(18)).fontWeight(.semibold)
            Text(session.displayPath).font(.claudeMono(11)).foregroundStyle(Color.label)
            if let evidence = session.restingEvidence(now: Date()) {
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

    /// Grouped rather than one long list. These arrive from the statusLine as
    /// four unrelated things -- what the turn cost, how full the window is, how
    /// the cache is behaving, how this session is configured -- and reading them
    /// as one column of twenty rows was the version that felt like a data dump.
    @ViewBuilder private var stats: some View {
        let st = session.stats
        let progress = session.todoProgress

        StatSection("Session", rows: [
            ("status", label(for: session)),
            ("todos", progress.total == 0 ? nil : "\(progress.done)/\(progress.total)"),
            ("host", session.host.isEmpty ? nil : session.host),
            ("pid", session.pid.map(String.init)),
            ("repo", st.repo),
        ])

        StatSection("Cost", rows: [
            ("spend", st.costUSD.map(StatFormat.money)),
            ("wall", st.wallSeconds.map(StatFormat.duration)),
            ("api", st.apiSeconds.map(StatFormat.duration)),
            ("api share", st.apiShare.map(StatFormat.percent)),
            ("lines", StatFormat.lines(added: st.linesAdded, removed: st.linesRemoved)),
        ])

        VStack(alignment: .leading, spacing: 8) {
            StatSection("Context", rows: [
                ("used", st.contextUsedPercent.map { "\($0)%" }),
                ("tokens", session.contextTokens.map { "\($0.formatted())" }),
                ("window", st.contextWindowSize.map { StatFormat.compactCount($0) }),
                ("over 200k", st.exceeds200k.map { $0 ? "yes" : "no" }),
            ])
            // Both are scaled to the window, so the bar's fill and the chart's
            // height mean the same thing. Neither is drawn without a window to
            // scale against: a chart with an invented denominator is worse than
            // the four rows above on their own.
            if let window = st.contextWindowSize, window > 0,
               let tokens = session.contextTokens {
                ContextMeter(tokens: tokens, window: window)
                ContextTrend(samples: history, window: window, tokens: tokens)
            }
        }

        StatSection("Prompt cache", rows: [
            ("hit ratio", st.cacheHitRatio.map(StatFormat.percent)),
            ("state", st.cacheWarm.map { $0 ? "warm" : "cold" }),
            ("ttl", st.cacheTTL),
            ("requests", st.cacheRequests.map(String.init)),
            ("misses", st.cacheMisses.map(String.init)),
        ])

        StatSection("Config", rows: [
            ("model", session.model),
            ("model id", st.modelID),
            ("effort", st.effort),
            ("thinking", st.thinking.map { $0 ? "on" : "off" }),
            ("style", st.outputStyle),
            ("claude", st.claudeVersion),
        ])
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

private struct ReplyBox: View {
    let session: SessionFeed
    let feedDir: URL
    @State private var text = ""
    @State private var sending = false
    @State private var notice: NoticeMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Reply to this session…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.claudeMono(11))
                    .onSubmit(send)
                Button(sending ? "Sending…" : "Send", action: send)
                    .font(.claudeMono(11))
                    .disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let notice {
                Notice(notice)
            }
        }
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
                notice = .init(kind: .info, text: "Sent — the session started a turn.")
            case .failure(let error):
                notice = error.errorDescription.map { .init(kind: .error, text: $0) }
            }
        }
    }
}


// MARK: - Stat rendering

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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(title).font(.claudeMono(10)).foregroundStyle(Color.label)
                    .textCase(.uppercase)
                if let refresh {
                    Button("Refresh", action: refresh)
                        .font(.claudeMono(10)).buttonStyle(.link)
                }
            }
            if present.isEmpty {
                Text(empty).font(.claudeMono(11)).foregroundStyle(Color.label)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    ForEach(present, id: \.0) { key, value, note in
                        GridRow {
                            Text(key).font(.claudeMono(11)).foregroundStyle(Color.label)
                                .gridColumnAlignment(.leading)
                            HStack(spacing: 8) {
                                Text(value).font(.claudeMono(11)).textSelection(.enabled)
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
    let history: [UsageSample]
    /// ccusage totals across every session, ended ones included -- the lines
    /// above add up only the sessions that are live right now.
    let totals: [FeedWatcher.TotalsRow]
    let totalsStatus: String
    let totalsDimmed: Bool
    let totalsHelp: String

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

            // Labelled for what it is. "$93.62 today" under a dollar sign reads
            // as a bill, and on a subscription plan that is simply wrong.
            if let spend = overview.spendUSD {
                Text("\(StatFormat.money(spend)) api-equivalent, not billed")
                    .font(.claudeMono(10)).foregroundStyle(Color.label)
            }

            Text(counts).font(.claudeMono(10)).foregroundStyle(Color.label)

            if let tokens = overview.contextTokens {
                Text("\(StatFormat.compactCount(tokens)) context in play")
                    .font(.claudeMono(10)).foregroundStyle(Color.label)
            }
            if let diff = StatFormat.lines(added: overview.linesAdded,
                                           removed: overview.linesRemoved) {
                Text("\(diff) lines").font(.claudeMono(10)).foregroundStyle(Color.label)
            }

            // Headed, because every figure above counts live sessions only and
            // these count every transcript -- same words, different population.
            StatSection("All sessions", rows: totals.map { ($0.label, $0.value, nil) },
                        empty: totalsStatus)
                .padding(.top, 4)
                .opacity(totalsDimmed ? 0.6 : 1)
                .help(totalsHelp)

            Sparkline(samples: history)
                .frame(height: 22)
                .padding(.top, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("5-hour usage over time")
                .accessibilityValue(Sparkline.spokenValue(history))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every session reports the same account-wide window, so the first one that
    /// has it is the answer -- averaging or summing them would be nonsense.
    private var fiveHour: Int? { overview.fiveHourPct }
    private var sevenDay: Int? { overview.sevenDayPct }

    private var counts: String {
        var parts = ["\(overview.sessions) session\(overview.sessions == 1 ? "" : "s")"]
        if overview.working > 0 { parts.append("\(overview.working) working") }
        if overview.waiting > 0 { parts.append("\(overview.waiting) waiting") }
        return parts.joined(separator: " · ")
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
                let line = Path { path in
                    path.move(to: points[0])
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                // The fill is the same line closed down to the baseline, built
                // as its own path rather than reusing the stroked one.
                let area = Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: points[0])
                    for point in points.dropFirst() { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.closeSubpath()
                }
                area.fill(tint.opacity(0.15))
                line.stroke(tint, lineWidth: 1.5)
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

/// Context over the session's life, scaled 0 to the window.
///
/// Scaled to the window rather than to the data on purpose. A 1M-window session
/// holding 20k *should* draw as a flat crawl along the bottom; auto-zooming
/// would make it look as full as a 190k session on a 200k window, which is the
/// same failure `Sparkline`'s fixed 0-100 axis exists to avoid. A compaction
/// shows as a cliff, and is not smoothed -- it is the most informative shape
/// the chart has.
private struct ContextTrend: View {
    let samples: [ContextSample]
    let window: Int
    let tokens: Int

    var body: some View {
        GeometryReader { geo in
            if let unit = ContextChart.unitPoints(samples, window: window) {
                let points = unit.map { CGPoint(x: $0.x * geo.size.width,
                                                y: $0.y * geo.size.height) }
                let tint = Color.contextTint(tokens)
                let line = Path { path in
                    path.move(to: points[0])
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                let area = Path { path in
                    path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                    for point in points { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                    path.closeSubpath()
                }
                area.fill(tint.opacity(0.15))
                line.stroke(tint, lineWidth: 1.5)
            } else {
                Text("no context history yet")
                    .font(.claudeMono(10)).foregroundStyle(Color.label)
            }
        }
        .frame(height: 28)
        .accessibilityLabel("Context over this session")
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
        Group {
            if !snapshot.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    if let prompt = snapshot.lastPrompt {
                        Labelled("you asked", prompt, limit: expanded ? nil : 3)
                    }
                    if let said = snapshot.lastAssistantText {
                        Labelled("claude said", said, limit: expanded ? nil : 6)
                    }
                    if !snapshot.recentTools.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("just ran").font(.claudeMono(10))
                                .foregroundStyle(Color.label).textCase(.uppercase)
                            Text(snapshot.recentTools.joined(separator: " · "))
                                .font(.claudeMono(11))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                        .font(.claudeMono(10)).buttonStyle(.link)
                }
                .padding(12)
                .background(Color.claudeDim.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
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

/// A titled block of transcript prose, clamped unless expanded.
private struct Labelled: View {
    let title: String
    let body_: String
    let limit: Int?

    init(_ title: String, _ body: String, limit: Int?) {
        self.title = title
        self.body_ = body
        self.limit = limit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.claudeMono(10))
                .foregroundStyle(Color.label).textCase(.uppercase)
            Text(body_)
                .font(.claudeMono(11))
                .lineLimit(limit)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}


// MARK: - Actions

/// The action row under the reply field.
///
/// Every button is either enabled or disabled with a stated reason. A control
/// that is greyed out and says nothing is what makes people click it twice and
/// conclude the app is broken -- and here the commonest reason, "not in a tmux
/// pane", is permanent rather than temporary, so it especially needs saying.
private struct ActionBar: View {
    let session: SessionFeed
    let feedDir: URL
    @State private var hasPane = false
    @State private var notice: NoticeMessage?
    @State private var confirming: SessionAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(SessionAction.allCases) { action in
                    let reason = SessionActions.unavailableReason(action,
                                                                  session: session,
                                                                  hasPane: hasPane)
                    Button(action.title) { start(action) }
                        .font(.claudeMono(10))
                        .disabled(reason != nil)
                        .help(reason ?? action.title)
                }
                Spacer(minLength: 0)
            }
            if let notice {
                Notice(notice)
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

// MARK: - Git

/// Branch, working-tree and remote state for the selected session's directory,
/// with the four actions that act on it.
///
/// Absent entirely when the cwd isn't a repository: a section of dashes tells
/// you nothing that its own absence doesn't tell you faster.
private struct GitCard: View {
    let cwd: String
    @State private var snapshot: GitSnapshot?
    /// Whether `snapshot` has been read for this `cwd` yet. A nil snapshot is
    /// either "still reading" or "not a repository", and only this tells them apart.
    @State private var read = false
    @State private var notice: NoticeMessage?
    @State private var confirming: GitAction?
    @State private var running = false

    var body: some View {
        // A VStack, not a Group: a Group hands its modifiers to each member, so
        // the task still re-ran on every branch swap, reset the snapshot, and
        // swapped back -- the section flickered and was caught blank on screen.
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .task(id: cwd) { await poll() }
    }

    @ViewBuilder private var content: some View {
        if let snap = snapshot {
            // Two clocks, so two ages. `remote` and `pr` are network reads on a
            // 90-second cycle sitting next to local facts read every five, and
            // one age for the section would misreport whichever half it wasn't.
            let now = Date()
            let local = StatFormat.age(snap.readAt, now: now)
            let remote = StatFormat.age(snap.remoteReadAt, now: now)
            VStack(alignment: .leading, spacing: 8) {
                StatSection("Git", rows: [
                    ("branch", snap.branchLabel, local),
                    ("changes", changesLabel(snap), local),
                    ("remote", snap.sync.label, remote),
                    ("pr", snap.pr.label, remote),
                    ("checks", checksLabel(snap), remote),
                ], refresh: reload)
                actions(snap)
                if let notice {
                    Notice(notice)
                }
            }
            .confirmationDialog(confirming?.confirmation ?? "",
                                isPresented: Binding(get: { confirming != nil },
                                                     set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible) {
                if let action = confirming {
                    Button(action.title) {
                        confirming = nil
                        perform(action, snap)
                    }
                }
                Button("Cancel", role: .cancel) { confirming = nil }
            }
        } else {
            StatSection("Git", empty: read ? "not a git repository" : "reading…")
        }
    }

    /// An action worth drawing, and why it can't run if it can't.
    private struct Offered: Identifiable {
        let action: GitAction
        let block: GitActions.Block?
        var id: String { action.id }
    }

    @ViewBuilder private func actions(_ snap: GitSnapshot) -> some View {
        // A settled block isn't drawn at all. The rows above already say why --
        // "clean", "in sync", "#3 open" -- and three permanently greyed buttons
        // beside them read as a broken app rather than as a finished repo.
        // What survives is what can run, plus whatever couldn't be worked out,
        // and that second kind states its reason on the page instead of behind
        // a tooltip nobody hovers for.
        let offered = GitAction.allCases
            .map { Offered(action: $0, block: GitActions.unavailableReason($0, snapshot: snap)) }
            .filter { $0.block?.settled != true }
        VStack(alignment: .leading, spacing: 5) {
            if offered.isEmpty {
                Text("no actions available")
                    .font(.claudeMono(10)).foregroundStyle(Color.label)
            } else {
                HStack(spacing: 6) {
                    ForEach(offered) { item in
                        Button(item.action.title) { start(item.action, snap) }
                            .font(.claudeMono(10))
                            .disabled(item.block != nil || running)
                            .help(item.block?.reason ?? item.action.title)
                    }
                    Spacer(minLength: 0)
                }
                ForEach(offered.filter { $0.block != nil }) { item in
                    Text("\(item.action.title.lowercased()): \(item.block?.reason ?? "")")
                        .font(.claudeMono(10)).foregroundStyle(Color.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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

    private func start(_ action: GitAction, _ snap: GitSnapshot) {
        notice = nil
        if action.confirmation != nil { confirming = action } else { perform(action, snap) }
    }

    private func perform(_ action: GitAction, _ snap: GitSnapshot) {
        running = true
        GitActions.perform(action, snapshot: snap, cwd: cwd) { message in
            notice = message
            running = false
            reload()
        }
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
