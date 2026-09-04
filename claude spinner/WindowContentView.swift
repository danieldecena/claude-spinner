import SwiftUI
import AppKit

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
    @State private var selection: String?

    /// Roots only. Children are shown under their parent in the detail pane,
    /// where there is room for them.
    private var roots: [SessionFeed] {
        feed.sessions.filter { $0.parentSessionId == nil }
    }

    /// Opening on whatever sorted first showed an idle, unnamed session while a
    /// question sat unanswered two rows above it. Default to the one that is
    /// actually waiting on a person.
    private var selected: SessionFeed? {
        if let selection, let picked = roots.first(where: { $0.id == selection }) { return picked }
        return roots.first { session in
            asks.pending.contains { $0.sessionId == session.id }
        } ?? roots.first { $0.status == .attention } ?? roots.first
    }

    var body: some View {
        NavigationSplitView {
            SessionSidebar(sessions: roots, asks: asks.pending, selection: $selection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            if let session = selected {
                SessionDetail(session: session,
                              children: feed.sessions.filter { $0.parentSessionId == session.id },
                              asks: asks.pending.filter { $0.sessionId == session.id },
                              feedDir: feed.feedDirectory)
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

    /// Waiting first — those are the ones with something blocked on a human.
    private var groups: [(String, [SessionFeed])] {
        let waiting = sessions.filter { $0.status == .attention || asksFor($0) }
        let waitingIDs = Set(waiting.map(\.id))
        let working = sessions.filter { $0.isWorking && !waitingIDs.contains($0.id) }
        let workingIDs = Set(working.map(\.id))
        let resting = sessions.filter { !waitingIDs.contains($0.id) && !workingIDs.contains($0.id) }
        return [("Needs you", waiting), ("Working", working), ("Idle", resting)]
            .filter { !$0.1.isEmpty }
    }

    private func asksFor(_ session: SessionFeed) -> Bool {
        asks.contains { $0.sessionId == session.id }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(groups, id: \.0) { title, items in
                Section(title) {
                    ForEach(items) { session in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(tint(session))
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.displayName)
                                    .font(.claudeMono(12)).lineLimit(1)
                                Text(session.projectName)
                                    .font(.claudeMono(10)).foregroundStyle(Color.claudeDim)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if asksFor(session) {
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundStyle(Color.usageTint(95))
                            }
                        }
                        .tag(session.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func tint(_ session: SessionFeed) -> Color {
        if session.status == .attention || asksFor(session) { return Color.usageTint(95) }
        return session.isWorking ? .accentColor : Color.claudeDim
    }
}

// MARK: - Detail

private struct SessionDetail: View {
    let session: SessionFeed
    let children: [SessionFeed]
    let asks: [AskRequest]
    let feedDir: URL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                ForEach(asks) { ask in
                    AskCard(ask: ask)
                }

                ReplyBox(session: session, feedDir: feedDir)

                stats

                if !children.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Subagents").font(.claudeMono(11)).foregroundStyle(Color.claudeDim)
                        ForEach(children) { child in
                            HStack(spacing: 8) {
                                Text(child.agentType ?? "subagent").font(.claudeMono(11))
                                Text(child.tool.isEmpty ? "—" : child.tool)
                                    .font(.claudeMono(11)).foregroundStyle(Color.claudeDim)
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
            Text(session.displayName).font(.claudeMono(18)).fontWeight(.semibold)
            Text(session.displayPath).font(.claudeMono(11)).foregroundStyle(Color.claudeDim)
            if !session.message.isEmpty {
                Text(session.message).font(.claudeMono(11)).foregroundStyle(Color.usageTint(95))
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

        StatSection("Context", rows: [
            ("used", st.contextUsedPercent.map { "\($0)%" }),
            ("tokens", session.contextTokens.map { "\($0.formatted())" }),
            ("window", st.contextWindowSize.map { StatFormat.compactCount($0) }),
            ("over 200k", st.exceeds200k.map { $0 ? "yes" : "no" }),
        ])

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
                .font(.claudeMono(11)).foregroundStyle(Color.usageTint(95))
            Text(prompt).font(.claudeMono(13)).fixedSize(horizontal: false, vertical: true)

            if let answered {
                Text("Answered: \(answered)").font(.claudeMono(11)).foregroundStyle(Color.claudeDim)
            } else {
                // Full labels *and* their descriptions — the reason this surface
                // exists. A banner shows two buttons and no descriptions at all.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                        Button { answer(choice.answer, label: choice.label) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(choice.label).font(.claudeMono(12))
                                if let detail = choice.detail {
                                    Text(detail).font(.claudeMono(10))
                                        .foregroundStyle(Color.claudeDim)
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
        .background(Color.usageTint(95).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Reply to this session…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.claudeMono(12))
                    .onSubmit(send)
                Button(sending ? "Sending…" : "Send", action: send)
                    .font(.claudeMono(11))
                    .disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let notice {
                Text(notice).font(.claudeMono(10)).foregroundStyle(Color.claudeDim)
                    .fixedSize(horizontal: false, vertical: true)
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
                notice = "Sent — the session started a turn."
            case .failure(let error):
                notice = error.errorDescription
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
    let rows: [(String, String?)]

    init(_ title: String, rows: [(String, String?)]) {
        self.title = title
        self.rows = rows
    }

    var body: some View {
        let present = rows.compactMap { key, value in value.map { (key, $0) } }
        if !present.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.claudeMono(10)).foregroundStyle(Color.claudeDim)
                    .textCase(.uppercase)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    ForEach(present, id: \.0) { key, value in
                        GridRow {
                            Text(key).font(.claudeMono(11)).foregroundStyle(Color.claudeDim)
                                .gridColumnAlignment(.leading)
                            Text(value).font(.claudeMono(11)).textSelection(.enabled)
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

    /// nil when neither side is known — "+0 -0" claims a measurement that was
    /// never taken.
    static func lines(added: Int?, removed: Int?) -> String? {
        guard added != nil || removed != nil else { return nil }
        return "+\(added ?? 0) −\(removed ?? 0)"
    }
}
