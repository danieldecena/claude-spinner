import SwiftUI

// The detail pane's two stat cards: this session, and the account's limits.
//
// Ratios are rings and history is columns, never a horizontal bar or line: a
// ring reads "how full" at a glance whatever the card's width, and a column
// per time slice puts a gap or a burst where the eye expects it. A tick on the
// ring says how much of a limit window has gone by.

// MARK: - Pure bucketing

/// A time series cut into equal slices, for the column charts. Pure, so the
/// degenerate cases are testable without laying out a view.
enum Buckets {
    /// Which slice a timestamp falls in, held inside the range: a sample stamped
    /// before the first (a clock stepped back) joins the first slice instead of
    /// indexing off the front.
    private static func slice(_ at: Double, first: Double, span: Double, count: Int) -> Int {
        let raw = (at - first) / span * Double(count)
        return raw.isFinite ? min(count - 1, max(0, Int(raw))) : 0
    }

    /// `count` equal slices from the first sample to the last. A slice holds the
    /// last level seen in it and carries the previous slice's level when it has
    /// no sample, because a level (context, a percentage) does not vanish while
    /// nothing is reported. nil when there is no span to slice: one sample is a
    /// dot, not a history.
    static func levels(_ samples: [(at: Double, value: Double)], count: Int) -> [Double]? {
        guard count > 0, samples.count >= 2, let first = samples.first, let last = samples.last,
              last.at > first.at else { return nil }
        let span = last.at - first.at
        var out = [Double?](repeating: nil, count: count)
        for sample in samples {
            out[slice(sample.at, first: first.at, span: span, count: count)] = sample.value
        }
        var carried = samples[0].value
        return out.map { value in
            carried = value ?? carried
            return carried
        }
    }

    /// What was added in each slice of a running total, so a heavy turn is a tall
    /// column and an idle stretch is none. A total that went down (a reset) adds
    /// nothing rather than a negative.
    static func increases(_ samples: [(at: Double, value: Double)], count: Int) -> [Double]? {
        guard count > 0, samples.count >= 2, let first = samples.first, let last = samples.last,
              last.at > first.at else { return nil }
        let span = last.at - first.at
        var out = [Double](repeating: 0, count: count)
        for (previous, sample) in zip(samples, samples.dropFirst()) {
            out[slice(sample.at, first: first.at, span: span, count: count)] += max(0, sample.value - previous.value)
        }
        return out
    }
}

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

    private let line: CGFloat = 7

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
                    .stroke(Color.primary.opacity(0.85), lineWidth: line + 4)
                    .rotationEffect(.degrees(-90))
            }
            Text(value).font(.claudeMono(13)).fontWeight(.semibold)
                .foregroundStyle(ratio == nil ? Color.label : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, line + 2)
        }
        .frame(width: 70, height: 70)
        .padding(3)
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

    var body: some View {
        VStack(spacing: 5) {
            Ring(ratio: ratio, tint: tint, pace: pace, value: value)
            Text(caption).font(.claudeMono(9)).fontWeight(.semibold)
                .foregroundStyle(Color.label).textCase(.uppercase).tracking(0.8)
            if let detail {
                Text(detail).font(.claudeMono(10)).foregroundStyle(Color.label)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
    }
}

/// One column per time slice, each as tall as its share of the top. A nil slice
/// is a faint stub: "nothing yet" must not read as "used nothing".
struct Columns: View {
    let shares: [Double?]
    let tints: [Color]
    var height: CGFloat = 44

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(share == nil ? Color.secondary.opacity(0.15) : tints[index])
                        .frame(height: share.map { max($0 > 0 ? 2 : 0, height * CGFloat(min(1, $0))) } ?? 2)
                }
            }
        }
        .frame(height: height)
    }
}

/// A captioned column chart: what it is and where it stands now above, how far
/// back it reaches below.
struct TrendColumns: View {
    let title: String
    let now: String
    let shares: [Double]?
    let tints: [Color]
    let first: Double?
    let last: Double?
    var empty = "no history yet"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.claudeMono(9)).fontWeight(.semibold)
                    .foregroundStyle(Color.label).textCase(.uppercase).tracking(0.8)
                Spacer(minLength: 4)
                Text(now).font(.claudeMono(11)).fontWeight(.semibold).lineLimit(1)
            }
            if let shares {
                Columns(shares: shares, tints: tints)
                if let first, let last {
                    let clock = Date()
                    HStack {
                        Text(StatFormat.age(Date(timeIntervalSince1970: first), now: clock) ?? "")
                        Spacer(minLength: 0)
                        Text(StatFormat.age(Date(timeIntervalSince1970: last), now: clock) ?? "")
                    }
                    .font(.claudeMono(9)).foregroundStyle(Color.label)
                }
            } else {
                Text(empty).font(.claudeMono(10)).foregroundStyle(Color.label)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(now)
    }
}

/// A figure with its caption over it, for the totals that have no ratio to draw.
private struct Figure: View {
    let caption: String
    let main: String
    var sub: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption).font(.claudeMono(9)).fontWeight(.semibold)
                .foregroundStyle(Color.label).textCase(.uppercase).tracking(0.8)
            Text(main).font(.claudeMono(13)).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.7)
            if let sub {
                Text(sub).font(.claudeMono(10)).foregroundStyle(Color.label).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - This session

/// Cost, prompt cache, context and the session's own facts as one card: three
/// rings for the three shares, two column charts for how the two that grow have
/// grown, and a line of the rest.
struct SessionStatsCard: View {
    let session: SessionFeed
    let history: [ContextSample]
    let spend: [SpendSample]

    private static let slices = 18

    var body: some View {
        let st = session.stats
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardTitle("This session")
                Spacer(minLength: 4)
                Text(statusLabel).font(.claudeMono(10)).foregroundStyle(Color.label).lineLimit(1)
            }
            HStack(alignment: .top, spacing: 8) {
                if let window = st.contextWindowSize, window > 0, let tokens = session.contextTokens {
                    let share = min(1, Double(tokens) / Double(window))
                    RingMetric(caption: "context",
                               value: st.contextUsedPercent.map { "\($0)%" } ?? "\(Int((share * 100).rounded()))%",
                               ratio: share, tint: .contextTint(tokens),
                               detail: "\(StatFormat.compactCount(tokens)) of \(StatFormat.compactCount(window))")
                }
                if let hit = st.cacheHitRatio {
                    RingMetric(caption: "cache", value: "\(Int((min(1, max(0, hit)) * 100).rounded()))%",
                               ratio: hit, tint: .usageGreen, detail: cacheDetail)
                }
                if let cost = st.costUSD {
                    RingMetric(caption: "spend", value: StatFormat.money(cost),
                               ratio: st.apiShare, tint: .claude, detail: costDetail)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                contextTrend
                spendTrend
            }
            if let facts = facts {
                Text(facts).font(.claudeMono(10)).foregroundStyle(Color.label).lineLimit(2)
                    .truncationMode(.middle)
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

    /// Context on the same absolute axis as before, ceiling and all: a 20k
    /// session must still crawl along the bottom. Each column takes the colour
    /// its level would tint the ring, so the bands the old chart ruled in are
    /// carried by the columns themselves.
    @ViewBuilder private var contextTrend: some View {
        let st = session.stats
        let pairs = history.map { (at: $0.at, value: Double($0.tokens)) }
        let levels = Buckets.levels(pairs, count: Self.slices)
        let top = Double(st.contextWindowSize.map { ContextChart.ceiling(window: $0, samples: history) } ?? 0)
        TrendColumns(title: "context", now: session.contextTokens.map(StatFormat.compactCount) ?? "",
                     shares: top > 0 ? levels?.map { $0 / top } : nil,
                     tints: (levels ?? []).map { Color.contextTint(Int($0)) },
                     first: history.first?.at, last: history.last?.at,
                     empty: "no context history yet")
    }

    @ViewBuilder private var spendTrend: some View {
        let pairs = spend.map { (at: $0.at, value: $0.usd) }
        let steps = Buckets.increases(pairs, count: Self.slices)
        let peak = steps?.max() ?? 0
        TrendColumns(title: "spend", now: session.stats.costUSD.map(StatFormat.money) ?? "",
                     shares: peak > 0 ? steps?.map { $0 / peak } : nil,
                     tints: Array(repeating: .claude, count: Self.slices),
                     first: spend.first?.at, last: spend.last?.at,
                     empty: "no spend history yet")
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
        VStack(alignment: .leading, spacing: 14) {
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

            // Headed, because every figure above counts live sessions only and
            // these count every transcript -- same words, different population.
            VStack(alignment: .leading, spacing: 6) {
                CardTitle("All sessions")
                if totals.isEmpty {
                    Text(totalsStatus).font(.claudeMono(11)).foregroundStyle(Color.label)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(totals, id: \.self) { row in
                            let (main, sub) = Self.split(row.value)
                            Figure(caption: row.label, main: main, sub: sub)
                        }
                    }
                }
            }
            .opacity(totalsDimmed ? 0.6 : 1)
            .help(totalsHelp)

            if !weekBars.isEmpty {
                WeekChart(bars: weekBars)
                    .opacity(totalsDimmed ? 0.6 : 1)
            }

            usageHistory

            // Labelled for what it is. "$93.62 today" under a dollar sign reads
            // as a bill, and on a subscription plan that is simply wrong.
            VStack(alignment: .leading, spacing: 2) {
                if let spend = overview.spendUSD {
                    Text("\(StatFormat.money(spend)) api-equivalent, not billed")
                }
                Text(liveLine)
            }
            .font(.claudeMono(10)).foregroundStyle(Color.label)
        }
        .detailCard()
    }

    /// One limit window. No reading is not a reading of zero: an unknown window
    /// is an empty ring and a dash, never the green of untouched headroom.
    private func limit(_ name: String, pct: Int?, elapsed: Double?, reset: String?) -> some View {
        var detail = reset.map { "resets \($0)" } ?? ""
        if let pct, let elapsed {
            detail += (detail.isEmpty ? "" : " · ")
                + (Double(pct) / 100 > elapsed ? "ahead of pace" : "within pace")
        }
        return RingMetric(caption: name, value: pct.map { "\($0)%" } ?? "—",
                          ratio: pct.map { Double($0) / 100 },
                          tint: pct.map(Color.usageTint) ?? .label,
                          pace: pct == nil ? nil : elapsed,
                          detail: pct == nil ? "no current reading" : detail)
    }

    /// Five-hour usage over the retained polls, one column per slice, each in the
    /// colour its level would tint the ring. The 7d line the old chart dashed in
    /// is the second ring now.
    @ViewBuilder private var usageHistory: some View {
        let slices = 30
        let levels = Buckets.levels(history.map { (at: $0.at, value: Double($0.pct)) }, count: slices)
        TrendColumns(title: "5h usage", now: fiveHour.map { "\($0)%" } ?? "",
                     shares: levels?.map { min(1, max(0, $0 / 100)) },
                     tints: (levels ?? []).map { Color.usageTint(Int($0)) },
                     first: history.first?.at, last: history.last?.at,
                     empty: "no usage history yet")
            .accessibilityValue(Sparkline.spokenValue(history))
    }

    /// `329M  $154` and `41M → 67M · 1h56m left` as a figure and what goes
    /// with it. The rows are the poller's own strings; only their two-space and
    /// dot separators are read here.
    static func split(_ value: String) -> (String, String?) {
        for separator in ["  ", " · "] {
            if let range = value.range(of: separator) {
                return (String(value[..<range.lowerBound]),
                        String(value[range.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
        }
        return (value, nil)
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

/// Tokens per day, Monday to Sunday, from the ccusage daily rows.
///
/// Scaled to the week's own peak: the question is which day was heavy, and
/// there is no limit to draw against. Days still ahead are faint stubs, not
/// zero-height bars, so "hasn't happened" never reads as "used nothing".
struct WeekChart: View {
    let bars: [UsageTotalsPoller.WeekBar]

    var body: some View {
        let peak = max(1, bars.compactMap(\.tokens).max() ?? 0)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("tokens by day").font(.claudeMono(9)).fontWeight(.semibold)
                    .foregroundStyle(Color.label).textCase(.uppercase).tracking(0.8)
                Spacer(minLength: 4)
                if let today = bars.first(where: \.isToday)?.tokens {
                    Text(FeedWatcher.formatTokens(today)).font(.claudeMono(11)).fontWeight(.semibold)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
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
            .frame(height: 56)
        }
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
