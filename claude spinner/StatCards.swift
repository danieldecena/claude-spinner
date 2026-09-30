import SwiftUI

// The detail pane's two stat cards: this session, and the account's limits.
//
// Ratios are rings and history is columns, never a horizontal bar or line: a
// ring reads "how full" at a glance whatever the card's width, and a column
// per time slice puts a gap or a burst where the eye expects it. A tick on the
// ring says how much of a limit window has gone by.

// MARK: - Marks

/// A share of a whole as a ring, with its reading in the middle. `pace` puts a
/// tick where the limit window's clock stands, so fill past the tick means
/// burning faster than the window refills. A nil ratio is an unknown, drawn as
/// an empty track and never as zero.
struct Ring: View {
    let ratio: Double?
    let tint: Color
    var pace: Double?
    let value: String

    private let line: CGFloat = 5

    var body: some View {
        let share = min(1, max(0, ratio ?? 0))
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.22), lineWidth: line)
            if ratio != nil {
                // A sliver for a tiny non-zero share, so a fresh session does not
                // read as an empty ring.
                Circle().trim(from: 0, to: share > 0 ? max(0.012, share) : 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if let pace {
                let at = min(1, max(0, pace))
                Circle().trim(from: max(0, at - 0.006), to: min(1, at + 0.006))
                    .stroke(Color.primary.opacity(0.85), lineWidth: line + 3)
                    .rotationEffect(.degrees(-90))
            }
            Text(value).font(.figure(10)).fontWeight(.semibold)
                .foregroundStyle(ratio == nil ? Color.label : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, line + 2)
        }
        .frame(width: 52, height: 52)
        .padding(2)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(ratio == nil ? "unknown" : "\(Int((share * 100).rounded())) percent")
    }
}

/// A ring with its name above it and one line of detail beneath.
struct RingMetric: View {
    let caption: String
    let value: String
    let ratio: Double?
    let tint: Color
    var pace: Double?
    var detail: String?
    /// The value as a figure in the ring's slot, with no ring: for a number that
    /// is not a share of anything. A ring around "$30" reads as a dollar gauge.
    var plain = false

    var body: some View {
        VStack(spacing: 3) {
            if plain {
                Text(value).font(.figure(15)).fontWeight(.semibold)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: 72, height: 56)
            } else {
                Ring(ratio: ratio, tint: tint, pace: pace, value: value)
            }
            Text(caption).font(.ui(9)).fontWeight(.semibold)
                .foregroundStyle(Color.label).textCase(.uppercase).tracking(0.8)
            if let detail {
                Text(detail).font(.ui(10)).foregroundStyle(Color.label)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
    }
}

// MARK: - This session

/// Cost, prompt cache, context and the session's own facts as one card: three
/// rings for the three shares, two column charts for how the two that grow have
/// grown, and a line of the rest.
struct SessionStatsCard: View {
    let session: SessionFeed

    var body: some View {
        let st = session.stats
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardTitle("This session")
                Spacer(minLength: 4)
                Text(statusLabel).font(.ui(10)).foregroundStyle(Color.label).lineLimit(1)
            }
            HStack(alignment: .top, spacing: 8) {
                if let window = st.contextWindowSize, window > 0, let tokens = session.contextTokens {
                    let share = min(1, Double(tokens) / Double(window))
                    RingMetric(caption: "context",
                               value: st.contextUsedPercent.map { "\($0)%" } ?? "\(Int((share * 100).rounded()))%",
                               // Tinted by the share the arc draws, not by the token
                               // count: a red ring half full said two things at once.
                               ratio: share, tint: .contextTint(tokens: tokens, window: window),
                               detail: "\(StatFormat.compactCount(tokens)) of \(StatFormat.compactCount(window))")
                }
                if let hit = st.cacheHitRatio {
                    RingMetric(caption: "cache", value: "\(Int((min(1, max(0, hit)) * 100).rounded()))%",
                               ratio: hit, tint: .series1, detail: cacheDetail)
                }
                if let cost = st.costUSD {
                    RingMetric(caption: "spend", value: StatFormat.money(cost),
                               ratio: nil, tint: .label, detail: costDetail, plain: true)
                }
            }
        }
        .detailCard()
    }

    private var statusLabel: String {
        switch session.status {
        case .idle: return "idle"
        case .thinking: return "thinking"
        case .tool: return session.tool.isEmpty ? "running a tool" : "running \(session.tool)"
        case .attention: return "needs input"
        }
    }

    private var cacheDetail: String {
        let st = session.stats
        var state: [String] = []
        if let warm = st.cacheWarm { state.append(warm ? "warm" : "cold") }
        if let ttl = st.cacheTTL { state.append("\(ttl) ttl") }
        var lines = [state.joined(separator: " · ")]
        if let requests = st.cacheRequests {
            lines.append("\(st.cacheMisses ?? 0) miss of \(requests)")
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private var costDetail: String {
        let st = session.stats
        var lines: [String] = []
        if let wall = st.wallSeconds { lines.append("\(StatFormat.duration(wall)) wall") }
        if let share = st.apiShare { lines.append("\(StatFormat.percent(share)) on the api") }
        return lines.joined(separator: "\n")
    }

    private var facts: String? {
        let st = session.stats
        let progress = session.todoProgress
        let parts: [String?] = [
            progress.total == 0 ? nil : "\(progress.done)/\(progress.total) todos",
            StatFormat.lines(added: st.linesAdded, removed: st.linesRemoved)
                .flatMap { (st.linesAdded ?? 0) + (st.linesRemoved ?? 0) > 0 ? "\($0) lines" : nil },
            session.host.isEmpty ? nil : session.host,
            session.pid.map { "pid \($0)" },
            st.repo,
        ]
        let present = parts.compactMap { $0 }
        return present.isEmpty ? nil : present.joined(separator: " · ")
    }
}

// MARK: - Usage

/// Totals across every session, as a card in the detail pane beside this
/// session's. The two limit windows lead, as rings with the window's clock
/// ticked on them; the totals and the history follow.
struct OverviewStrip: View {
    /// The menu bar's own resolution (poll, then a live session, then the
    /// persisted snapshot), not the live feeds alone -- read from the feeds, the
    /// window went blank or disagreed whenever only the poll or cache had it.
    let fiveHour: Int?
    let sevenDay: Int?
    let usageStale: Bool
    let usageHelp: String
    let fiveHourElapsed: Double?
    let sevenDayElapsed: Double?
    let fiveHourReset: String?
    let sevenDayReset: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Usage")

            // The rate-limit windows lead, not the dollar figure. On a Max plan
            // these are the only numbers that can actually stop you; the money
            // is a proxy for burn and is never charged.
            HStack(alignment: .top, spacing: 8) {
                limit("5h window", pct: fiveHour, elapsed: fiveHourElapsed, reset: fiveHourReset)
                limit("7d window", pct: sevenDay, elapsed: sevenDayElapsed, reset: sevenDayReset)
            }
            .opacity(usageStale ? 0.5 : 1)
            .help(usageHelp)
        }
        .detailCard()
    }

    /// One limit window. No reading is not a reading of zero: an unknown window
    /// is an empty ring and a dash, never the green of untouched headroom.
    private func limit(_ name: String, pct: Int?, elapsed: Double?, reset: String?) -> some View {
        var detail = reset.map { "resets \($0)" } ?? ""
        if let pct, let elapsed {
            detail += (detail.isEmpty ? "" : " · ")
                + (StatFormat.aheadOfPace(pct: pct, elapsed: elapsed) ? "ahead of pace" : "within pace")
        }
        return RingMetric(caption: name, value: pct.map { "\($0)%" } ?? "—",
                          ratio: pct.map { Double($0) / 100 },
                          tint: pct.map(Color.usageTint) ?? .label,
                          pace: pct == nil ? nil : elapsed,
                          detail: pct == nil ? "no current reading" : detail)
    }
}

