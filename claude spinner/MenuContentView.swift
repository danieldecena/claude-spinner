//
//  MenuContentView.swift
//  claude spinner
//
//  The panel shown when the menubar icon is clicked: one live row per session.
//

import SwiftUI
import AppKit

struct MenuContentView: View {
    @ObservedObject var feed: FeedWatcher

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if feed.sessions.isEmpty {
                if feed.isSetupInstalled {
                    Text("No active sessions")
                        .font(.claudeMono(11)).foregroundStyle(Color.claudeDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 12)
                } else {
                    // Nothing will ever appear until the hooks are wired up — say so
                    // instead of a silent empty panel that looks broken.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Setup needed")
                            .font(.claudeMono(11)).fontWeight(.semibold)
                            .foregroundStyle(Color.usageTint(95))
                        Text("The feed hooks aren't installed, so no sessions can show. Add the spinner hooks + statusLine to ~/.claude/settings.json.")
                            .font(.claudeMono(10)).foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 12)
                }
            } else {
                // One ticking clock drives every row's spinner + timer in phase.
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    // Resolve the row list once per tick — displayItems does a full
                    // sort + grouping, so evaluating it per-row (ForEach, last, and
                    // the animation value) would repeat that work every 100ms.
                    let rows = feed.displayItems
                    VStack(spacing: 0) {
                        ForEach(rows) { item in
                            SessionRow(feed: feed, item: item, now: context.date)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            if item.id != rows.last?.id {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                    // Animate only when the set/order of rows changes (keyed by ids),
                    // not on every 0.1s spinner tick.
                    .animation(.easeInOut(duration: 0.2), value: rows.map(\.id))
                }
                // Only pad the top; the last row's own vertical padding plus the
                // footer's divider/padding already separate it from the footer, so
                // a bottom pad here just opened a dead gap.
                .padding(.top, 6)
            }

            UsageFooter(feed: feed)
        }
        .frame(width: Constants.panelWidth)
        // No visible Quit button; ⌘Q still terminates while the panel is open.
        .background(
            Button("") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .opacity(0)
        )
    }
}

/// Always-present footer: live account usage — model, 5-hour and 7-day rate
/// limits (colored by urgency), reset countdown, and total spend — on the left,
/// with the settings gear always reachable on the right. A 1s clock keeps the
/// "resets in" countdown current.
struct UsageFooter: View {
    @ObservedObject var feed: FeedWatcher

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            // 1s clock keeps the reset countdown live-ticking.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        if feed.hasUsage {
                            Group {
                                if let h5 = feed.usageFiveHourPct {
                                    UsageGauge(label: "5h", pct: h5)
                                }
                                if let d7 = feed.usageSevenDayPct {
                                    UsageGauge(label: "7d", pct: d7)
                                }
                                // Recent 5h change, once there are ≥2 poll samples.
                                if let trend = feed.usageFiveHourTrend {
                                    TrendGauge(delta: trend)
                                }
                            }
                            // Dim when stale so a frozen snapshot doesn't read as live;
                            // the "as of" time and age live in the hover tooltip.
                            .opacity(feed.usageIsStale ? 0.5 : 1)
                            .help(feed.usageAsOfString)
                        } else {
                            Text("no usage data yet")
                                .font(.claudeMono(10))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                        }
                        Spacer(minLength: 0)
                    }

                    if feed.hasUsage {
                        HStack(spacing: 0) {
                            if let notice = feed.usageNotice {
                                // An urgent poller note (auth expired / out of credits)
                                // takes the slot when present — usage is stale or
                                // blocked, so a reset countdown would mislead.
                                HStack(spacing: 2) {
                                    Text("!").font(.claudeMono(9)).fontWeight(.bold)
                                    Text(notice).font(.claudeMono(10))
                                }
                                .foregroundStyle(Color.usageTint(95))
                                .help(feed.usageNoticeDetail)
                            } else {
                                HStack(spacing: 3) {
                                    Text("↺").font(.claudeMono(9))
                                    if let clock = feed.usageFiveHourReset {
                                        Text("resets \(clock)")
                                            .font(.claudeMono(10))
                                    }
                                    if let rel = feed.usageFiveHourResetRelative {
                                        Text("· in \(rel)")
                                            .font(.claudeMono(10)).monospacedDigit()
                                    }
                                }
                                .foregroundStyle(Color.secondary.opacity(0.75))
                                .help(feed.usageResetTooltip)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }
}

/// A compact usage gauge: a small label, a drawn rounded track with the filled
/// portion tinted by urgency, and the percentage. Reads far cleaner than a row of
/// █/░ block glyphs and keeps 5h and 7d visually aligned.
struct UsageGauge: View {
    let label: String
    let pct: Int

    private let trackWidth = Constants.usageTrackWidth
    private let trackHeight: CGFloat = 5

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.claudeMono(10))
                .foregroundStyle(Color.secondary)
                .fixedSize()
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: trackWidth, height: trackHeight)
                Capsule()
                    .fill(Color.usageTint(pct))
                    // Clamp to [0,1]; keep a sliver visible for tiny non-zero values.
                    .frame(width: max(pct > 0 ? 3 : 0,
                                      trackWidth * CGFloat(min(100, max(0, pct))) / 100),
                           height: trackHeight)
                    .opacity(pct < 10 ? 0.35 : 1.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: pct)
            }
            Text("\(pct)%")
                .font(.claudeMono(10)).monospacedDigit()
                .foregroundStyle(Color.usageTint(pct))
                .fixedSize()
        }
        .help("\(label == "5h" ? "5-hour" : "7-day") usage \(pct)%")
    }
}

/// A capsule gauge in the same language as `UsageGauge`, showing the recent
/// *change* in 5h utilization rather than an absolute level: how far it moved
/// across the sample window, signed. Rising usage tints warm (heading toward the
/// limit); falling tints green; the fill length is the magnitude (a 20-point
/// move fills the track).
struct TrendGauge: View {
    let delta: Int

    private let trackWidth = Constants.usageTrackWidth
    private let trackHeight: CGFloat = 5
    private let fullScale: CGFloat = 20  // points of change that fill the track

    private var tint: Color {
        if delta > 0 { return Color(red: 0.90, green: 0.58, blue: 0.24) }  // amber: rising
        if delta < 0 { return Color(red: 0.45, green: 0.70, blue: 0.45) }  // green: falling
        return Color.secondary
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("chg")
                .font(.claudeMono(10))
                .foregroundStyle(Color.secondary)
                .fixedSize()
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: trackWidth, height: trackHeight)
                Capsule()
                    .fill(tint)
                    .frame(width: max(delta != 0 ? 3 : 0,
                                      trackWidth * min(fullScale, CGFloat(abs(delta))) / fullScale),
                           height: trackHeight)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: delta)
            }
            Text("\(delta > 0 ? "+" : "")\(delta)%")
                .font(.claudeMono(10)).monospacedDigit()
                .foregroundStyle(tint)
                .fixedSize()
        }
        .help("5h usage change over recent polls")
    }
}

struct SessionRow: View {
    @ObservedObject var feed: FeedWatcher
    let item: SessionRowItem
    let now: Date
    @StateObject private var hover = HoverState()

    private var session: SessionFeed { item.session }

    var body: some View {
        // One line: [glyph] project-name ×N  status…time   ctx%
        HStack(spacing: 5) {
            Text(glyph)
                .font(.claudeMono(12))
                .foregroundStyle(tint)
                .frame(width: 14)

            // Column 1: Project Name + Count. Fixed width ensures alignment of subsequent columns.
            HStack(spacing: 3) {
                Text(session.projectName)
                    .font(.claudeMono(10))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if item.count > 1 {
                    Text("×\(item.count)")
                        .font(.claudeMono(10))
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(width: 95, alignment: .leading)

            // Column 2: Model (fixed width). Keeps Status aligned.
            Group {
                if let rawModel = feed.modelDisplay(for: session) {
                    Text(FeedWatcher.modelFamily(rawModel))
                        .font(.claudeMono(10)).fontWeight(.semibold)
                        .foregroundStyle(Color.modelTint(rawModel))
                        .lineLimit(1)
                } else {
                    Text("")
                }
            }
            .frame(width: 42, alignment: .leading)

            // Column 3: Status / Activity (flexible width, truncating if necessary).
            Text(statusLabel)
                .font(.claudeMono(10))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // Time + host chip travel together as one right-flush unit with a tight
            // gap, so the time stays near the right edge with the tag just after it.
            HStack(spacing: 4) {
                // Elapsed / waiting / done time in a fixed-width column so the
                // times line up down the panel regardless of label. Right-aligned
                // normally; the animated working-dots use leading alignment
                // instead, so a new dot appends on the right (growing naturally)
                // rather than on the left, which a right-aligned fixed frame would
                // otherwise produce as the string lengthens.
                if !timeText.isEmpty {
                    Text(timeText)
                        .font(.claudeMono(10))
                        .monospacedDigit()
                        .foregroundStyle(isAnimatingDots ? Color.secondary.opacity(0.4) : Color.secondary)
                        .frame(width: isAnimatingDots ? 14 : 34, alignment: isAnimatingDots ? .leading : .trailing)
                }

                // The color-coded host chip (vsc/trm/web/app) at rest, which flips to
                // an ✕ clear button on hover so a session can be dismissed in place.
                // A fixed width holds the slot constant so the time never shifts.
                ZStack(alignment: .trailing) {
                    Color.clear.frame(width: Constants.rowTrailingSlot, height: 1)
                    if hover.isHovering {
                        Button {
                            feed.clear(item)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color.secondary)
                        .help("Clear this session")
                    } else if let tag = session.hostTag {
                        Text(tag.label)
                            .font(.claudeMono(9))
                            .foregroundStyle(tag.color)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(tag.color.opacity(0.16))
                            )
                    }
                }
            }
        }
        // Everything in a row renders lowercase — including hook-supplied text like
        // the attention message and tool names — for one consistent visual voice.
        .textCase(.lowercase)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .opacity(rowOpacity)
        .background(rowHighlight)
        .onHover { hover.isHovering = $0 }
        .onTapGesture {
            openSession()
        }
        .help(rowTooltip)
        .contextMenu {
            Button("Open in Terminal") { openWithApp(bundleID: "com.apple.Terminal") }
            Button("Open in VS Code") { openWithApp(bundleID: "com.microsoft.VSCode") }
            Button("Open in Ghostty") { openWithApp(bundleID: "com.mitchellh.ghostty") }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
            }
            Divider()
            Button("Copy Session ID") { copyToPasteboard(session.id) }
            Button("Copy Path") { copyToPasteboard(session.cwd) }
            Divider()
            Button("Clear") { feed.clear(item) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.projectName), \(statusLabel) \(timeText)")
        .accessibilityHint("Opens this session's app")
    }

    private func openWithApp(bundleID: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-b", bundleID, session.cwd]
        try? task.run()
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// An inset, rounded highlight pill behind the row — only on hover: a blue wash
    /// for an attention row, a neutral wash otherwise, nothing at rest. The blue
    /// glyph/text already signal "needs you" without a persistent band. Inset +
    /// rounded reads as a proper selection, and it fades in/out.
    @ViewBuilder private var rowHighlight: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(rowFill)
            .animation(.easeInOut(duration: 0.12), value: hover.isHovering)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }

    private var rowFill: Color {
        guard hover.isHovering else { return .clear }
        return session.status == .attention
            ? Color.attention.opacity(0.22)
            : Color.primary.opacity(0.09)
    }

    /// Idle rows fade with age so a stale session recedes instead of sitting at
    /// full strength for hours; working/attention rows stay fully opaque.
    private var rowOpacity: Double {
        guard session.status == .idle, let updated = session.updated else { return 1.0 }
        let age = now.timeIntervalSince(updated)
        let t = min(max((age - Constants.idleFadeStart) / Constants.idleFadeSpan, 0), 1)
        return 1.0 - (1.0 - Constants.idleMinOpacity) * t
    }
    
    /// Bring the session's host app (and its existing window) to the front —
    /// never a new window. See `SessionLauncher.focus`.
    private func openSession() {
        SessionLauncher.focus(host: session.host)
    }

    private var glyph: String {
        switch session.status {
        case .attention: return Spinner.idle   // the star, same as the rest; the blue tint carries "needs you"
        case .thinking, .tool: return Spinner.frame(at: now)
        case .idle: return Spinner.idle
        }
    }

    // Idle/done rows go fully grey (glyph, name, and status) so a finished
    // session recedes — the way Claude Code greys out completed work.
    private var tint: Color {
        switch session.status {
        // Blue signals "needs you" — a different state from busy orange, not a
        // second shade of it.
        case .attention: return .attention
        case .thinking, .tool: return .claude
        case .idle: return .secondary
        }
    }

    private var nameColor: Color {
        session.status == .idle ? .secondary : .primary
    }

    private var statusColor: Color {
        switch session.status {
        case .attention: return .attention
        case .thinking, .tool: return .claude
        case .idle: return .secondary
        }
    }

    /// The concrete activity word, without the time (which lives in its own
    /// right-aligned column): `running Bash`, `thinking`, `done`, or the message.
    private var statusLabel: String {
        switch session.status {
        case .tool:
            return session.tool.isEmpty ? "running" : "running \(session.tool)"
        case .thinking:
            return SpinnerWords.word(for: session)
        case .attention:
            // One word, same vocabulary as the menu-bar title — the full hook
            // message ("Claude is waiting for your input") only truncates anyway.
            return AttentionWords.word(for: session)
        case .idle:
            if session.lastDuration != nil {
                return SpinnerWords.pastWord(for: session)
            }
            return "idle"
        }
    }

    /// True while the time slot shows the animated working-dots rather than a
    /// number — used to flip its frame alignment so the dots grow rightward.
    private var isAnimatingDots: Bool { session.status == .tool || session.status == .thinking }

    /// The time shown right-aligned at the end of the row: elapsed in-turn while
    /// working, how long it's been waiting for attention, the finished turn's
    /// duration when done, or how long idle. Empty when there's nothing to show.
    private var timeText: String {
        switch session.status {
        case .tool, .thinking:
            return FeedWatcher.workingDots(at: now)
        case .attention:
            return sinceUpdated
        case .idle:
            // A finished turn shows its (fixed) duration; a session that's just
            // sitting idle with nothing running shows nothing rather than a
            // placeholder.
            if let dur = session.lastDuration { return FeedWatcher.formatDuration(dur) }
            return ""
        }
    }

    /// How long since the session last changed — used for waiting/idle age.
    private var sinceUpdated: String {
        guard let updated = session.updated else { return "" }
        return FeedWatcher.formatDuration(max(0, Int(now.timeIntervalSince(updated))))
    }

    private var rowTooltip: String {
        var parts: [String] = []
        parts.append("path: \(session.cwd)")
        if let pid = session.pid {
            parts.append("pid: \(pid)")
        }
        if let updated = session.updated {
            parts.append("updated: \(FeedWatcher.compactAge(since: updated, now: now)) ago")
        }
        return parts.joined(separator: "\n")
    }
}

class HoverState: ObservableObject {
    @Published var isHovering = false
}
