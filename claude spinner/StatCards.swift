import SwiftUI

// The detail pane's stat card: this session's rings, the account's limits and
// this Mac's own load, in one row.
//
// Ratios are rings and history is columns, never a horizontal bar or line: a
// ring reads "how full" at a glance whatever the card's width, and a column
// per time slice puts a gap or a burst where the eye expects it. A tick on the
// ring says how much of a limit window has gone by.

// MARK: - Marks

/// One named part of a ring. `share` is of the whole circle, not of the fill.
struct RingSegment: Identifiable {
    let label: String
    let share: Double
    let color: Color
    var id: String { label }
}

/// A share of a whole as a ring, with its reading in the middle. `pace` puts a
/// tick where the limit window's clock stands, so fill past the tick means
/// burning faster than the window refills. A nil ratio is an unknown, drawn as
/// an empty track and never as zero. `segments` replace the single arc with its
/// parts, laid end to end from the top with a gap between them, so `ratio` is
/// still the whole fill and `tint` is unused.
struct Ring: View {
    let ratio: Double?
    let tint: Color
    var pace: Double?
    var segments: [RingSegment] = []
    let value: String

    private let line: CGFloat = 5
    /// 2pt on the 47pt-diameter circle's 148pt circumference.
    private let gap = 2.0 / 148

    var body: some View {
        let share = min(1, max(0, ratio ?? 0))
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.22), lineWidth: line)
            if ratio != nil, !segments.isEmpty {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, part in
                    let start = segments[..<index].reduce(0) { $0 + $1.share }
                    let end = start + part.share
                    if part.share > gap {
                        Circle().trim(from: start + gap / 2, to: end - gap / 2)
                            .stroke(part.color, style: StrokeStyle(lineWidth: line))
                            .rotationEffect(.degrees(-90))
                    }
                }
            } else if ratio != nil {
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
    var segments: [RingSegment] = []
    var detail: String?
    /// The value as a figure in the ring's slot, with no ring: for a number that
    /// is not a share of anything. A ring around "$30" reads as a dollar gauge.
    var plain = false

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            if plain {
                Text(value).font(.figure(15)).fontWeight(.semibold)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: 72, height: 56)
            } else {
                Ring(ratio: ratio, tint: tint, pace: pace, segments: segments, value: value)
            }
            // One line, and wide enough for itself: the limit pair sits in its own
            // nested HStack, which took a narrower share than the three machine
            // rings and wrapped "5h window" onto two lines beside one-line
            // captions, leaving the card's bottom edge ragged.
            Text(caption).font(.ui(9)).fontWeight(.semibold)
                .foregroundStyle(Color.label).textCase(.uppercase).tracking(0.8)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 && (detail != nil || !segments.isEmpty) }
        .popover(isPresented: $hovering, arrowEdge: .top) { info }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
        .accessibilityValue(detail?.replacingOccurrences(of: "\n", with: ", ") ?? "")
    }

    /// What used to sit under the ring: its detail lines, then each part with its
    /// share. Swatch beside the words, which stay in label ink.
    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption).font(.ui(9)).fontWeight(.semibold)
                .foregroundStyle(Color.label).textCase(.uppercase).tracking(0.8)
            if let detail {
                Text(detail).font(.ui(11)).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(segments) { part in
                HStack(spacing: 6) {
                    Circle().fill(part.color).frame(width: 7, height: 7)
                    Text(part.label).font(.ui(11))
                    Spacer(minLength: 8)
                    Text("\(Int((part.share * 100).rounded()))%").font(.figure(11))
                }
            }
        }
        .padding(10)
        .frame(minWidth: 140, alignment: .leading)
    }
}

// MARK: - This session

/// Context, prompt cache and wall time for one session: two rings for the shares
/// and a figure for the time. Unframed, for the Usage card's row.
struct SessionRings: View {
    let session: SessionFeed

    /// A session that has reported none of the three draws nothing, and the card
    /// leaves out the divider that would have followed it.
    var isEmpty: Bool {
        let st = session.stats
        let hasContext = (st.contextWindowSize ?? 0) > 0 && session.contextTokens != nil
        return !hasContext && st.cacheHitRatio == nil && st.wallSeconds == nil
    }

    var body: some View {
        let st = session.stats
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
            // Time, not money. The figure used to be the api-equivalent dollar
            // cost, which is never charged on a Max plan and read as if it were:
            // what a session actually spends there is wall time.
            if let wall = st.wallSeconds {
                RingMetric(caption: "time", value: StatFormat.duration(wall),
                           ratio: nil, tint: .label, detail: timeDetail, plain: true)
            }
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

    /// What the figure beside it does not already say: the wall time is the ring's
    /// own value, so repeating it here would be the whole tooltip.
    private var timeDetail: String? {
        session.stats.apiShare.map { "\(StatFormat.percent($0)) on the api" }
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

/// The detail pane's one card of rings: the selected session's, then the
/// account's two limit windows with the window's clock ticked on them, then this
/// Mac's load. Dividers mark the three groups.
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
    /// The selected session, whose rings lead the row. Nil outside a session.
    var session: SessionFeed?

    @StateObject private var system = SystemStats()

    func including(_ session: SessionFeed) -> OverviewStrip {
        var copy = self
        copy.session = session
        return copy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Usage")

            // The rate-limit windows lead, not the dollar figure. On a Max plan
            // these are the only numbers that can actually stop you; the money
            // is a proxy for burn and is never charged. This Mac's own load
            // follows them in the same row.
            HStack(alignment: .top, spacing: 8) {
                if let session, !SessionRings(session: session).isEmpty {
                    SessionRings(session: session)
                    Divider().frame(height: 80)
                }
                HStack(alignment: .top, spacing: 8) {
                    limit("5h window", pct: fiveHour, elapsed: fiveHourElapsed, reset: fiveHourReset)
                    limit("7d window", pct: sevenDay, elapsed: sevenDayElapsed, reset: sevenDayReset)
                }
                .opacity(usageStale ? 0.5 : 1)
                .help(usageHelp)

                Divider().frame(height: 80)

                machine("cpu", share: system.cpu,
                        segments: parts([("user", system.cpuUser, .segment1),
                                         ("system", system.cpuSystem, .segment2)]),
                        detail: "all cores")
                machine("memory", share: system.memory,
                        segments: parts([("active", system.memoryActive, .segment1),
                                         ("wired", system.memoryWired, .segment2),
                                         ("compressed", system.memoryCompressed, .segment3)]),
                        detail: system.memoryUsedBytes.map {
                            "\(StatFormat.gigabytes($0)) of \(StatFormat.gigabytes(system.memoryTotalBytes))"
                        })
                machine("disk", share: system.disk,
                        detail: system.diskFreeBytes.map {
                            "\(StatFormat.gigabytes(UInt64(max(0, $0)))) free"
                        })
            }
        }
        .detailCard()
        .onAppear { system.start() }
        .onDisappear { system.stop() }
    }

    /// The parts of a reading, or none when any part could not be read: a ring
    /// whose parts do not add up to its fill would be a wrong picture.
    private func parts(_ named: [(String, Double?, Color)]) -> [RingSegment] {
        let known = named.compactMap { n in n.1.map { RingSegment(label: n.0, share: $0, color: n.2) } }
        return known.count == named.count ? known : []
    }

    /// One reading of this Mac. Unknown is an empty ring and a dash, as for the
    /// limit windows.
    private func machine(_ name: String, share: Double?, segments: [RingSegment] = [],
                         detail: String?) -> some View {
        RingMetric(caption: name,
                   value: share.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                   ratio: share,
                   tint: share.map { Color.usageTint(Int(($0 * 100).rounded())) } ?? .label,
                   segments: share == nil ? [] : segments,
                   detail: share == nil ? "no reading yet" : detail)
    }

    /// One limit window. No reading is not a reading of zero: an unknown window
    /// is an empty ring and a dash, never the green of untouched headroom.
    private func limit(_ name: String, pct: Int?, elapsed: Double?, reset: String?) -> some View {
        var detail = reset.map { "resets \($0)" } ?? ""
        if let pct, let elapsed {
            // Not "ahead of pace", which reads as good news on a meter where it
            // is the warning: spending ahead of the clock is what fills the
            // window early. Say the clock, then the verdict in those terms.
            let gone = Int((elapsed * 100).rounded())
            detail += (detail.isEmpty ? "" : "\n") + "\(gone)% of the window has passed · "
                + (StatFormat.aheadOfPace(pct: pct, elapsed: elapsed)
                    ? "spending faster than that" : "spending no faster than that")
        }
        return RingMetric(caption: name, value: pct.map { "\($0)%" } ?? "—",
                          ratio: pct.map { Double($0) / 100 },
                          tint: pct.map { Color.usageTint($0) } ?? .label,
                          pace: pct == nil ? nil : elapsed,
                          detail: pct == nil ? "no current reading" : detail)
    }
}

