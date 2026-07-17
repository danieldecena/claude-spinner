//
//  MenuContentView.swift
//  claude spinner
//
//  The panel shown when the menubar icon is clicked: one live row per session.
//

import SwiftUI
import AppKit
import Combine

struct MenuContentView: View {
    @ObservedObject var feed: FeedWatcher
    @StateObject private var install = InstallState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            UsageHeader(feed: feed)

            if feed.sessions.isEmpty {
                if feed.isSetupInstalled {
                    Text("No active sessions")
                        .font(.claudeMono(12)).foregroundStyle(Color.claudeDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 12)
                } else {
                    // Nothing will ever appear until the hooks are wired up — offer a
                    // one-click install instead of a silent empty panel.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Setup needed")
                            .font(.claudeMono(12)).fontWeight(.semibold)
                            .foregroundStyle(Color.usageTint(95))
                        Text("The feed hooks aren't installed, so no sessions can show.")
                            .font(.claudeMono(11)).foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let message = install.message {
                            Text(message)
                                .font(.claudeMono(11)).foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(install.installing ? "Installing…" : "Install hooks") {
                            install.installing = true
                            install.message = nil
                            DispatchQueue.global(qos: .userInitiated).async {
                                let result = SetupInstaller.install()
                                DispatchQueue.main.async {
                                    install.installing = false
                                    switch result {
                                    case .success:
                                        feed.refreshSetupState()
                                        install.message = "Installed — restart your Claude Code sessions to start the feed."
                                    case .failure(let error):
                                        install.message = "Couldn't install: \(error.localizedDescription)"
                                    }
                                }
                            }
                        }
                        .font(.claudeMono(11))
                        .disabled(install.installing)
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

/// Panel header: the 5-hour reset countdown (or the limit notice, which takes
/// precedence) pinned above the session list so it reads first. A 1s clock keeps
/// the "in …" countdown live-ticking.
struct UsageHeader: View {
    @ObservedObject var feed: FeedWatcher

    /// The usage line only exists once there's something to say about the account.
    private var hasUsageLine: Bool {
        feed.hasUsage && (feed.usageNotice != nil || feed.usageFiveHourReset != nil)
    }

    var body: some View {
        if hasUsageLine || feed.totalContextTokens != nil {
            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 0) {
                        if hasUsageLine {
                            Group {
                                if let notice = feed.usageNotice {
                                    Text("\(Image(systemName: "exclamationmark.triangle")) \(notice)")
                                        .foregroundStyle(Color.usageTint(95))
                                        .help(feed.usageNoticeDetail)
                                        .accessibilityLabel("Usage warning: \(notice)")
                                } else {
                                    let clock = feed.usageFiveHourReset ?? ""
                                    let rel = feed.usageFiveHourResetRelative ?? ""
                                    let resetsStr = rel.isEmpty ? " \(clock)" : " \(clock) · in \(rel)"
                                    Text("\(Image(systemName: "arrow.clockwise"))\(resetsStr)")
                                        .foregroundStyle(Color.secondary.opacity(0.75))
                                        .help(feed.usageResetTooltip)
                                        // The bare glyph + clock reads as nothing without this.
                                        .accessibilityLabel(
                                            "5-hour limit resets at \(clock)\(rel.isEmpty ? "" : ", in \(rel)")")
                                }
                            }
                            .font(.claudeMono(10.5))
                            .lineLimit(1)
                            .textCase(.lowercase)
                            // Only the account numbers go stale; the total below is
                            // read from the sessions, which are live regardless.
                            .opacity(feed.usageIsStale ? 0.5 : 1)
                        }

                        Spacer(minLength: 8)

                        // Context across every session at once — the one number no
                        // single row can show.
                        if let total = feed.totalContextTokens {
                            Text("\(FeedWatcher.formatTokens(total)) total")
                                .font(.claudeMono(10.5))
                                .monospacedDigit()
                                .foregroundStyle(Color.secondary.opacity(0.75))
                                .lineLimit(1)
                                .textCase(.lowercase)
                                .help("Total context tokens across all sessions")
                                .accessibilityLabel("\(FeedWatcher.formatTokens(total)) context tokens across all sessions")
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider().opacity(0.5)
            }
        }
    }
}

/// Always-present footer: the 5-hour and 7-day rate limits and the recent trend,
/// colored by urgency. A 1s clock keeps the stale-dimming current.
struct UsageFooter: View {
    @ObservedObject var feed: FeedWatcher

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            // 1s clock keeps the reset countdown live-ticking.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 0) {
                    if feed.hasUsage {
                        HStack(spacing: 12) {
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
                            .font(.claudeMono(11))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                    }

                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 10)
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
                .font(.claudeMono(11))
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
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: pct)
            }
            Text("\(pct)%")
                .font(.claudeMono(11)).monospacedDigit()
                .foregroundStyle(Color.usageTint(pct))
                .fixedSize()
        }
        .help("\(label == "5h" ? "5-hour" : "7-day") usage \(pct)%")
        // The level is otherwise conveyed by fill length and tint alone.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label == "5h" ? "5-hour" : "7-day") usage")
        .accessibilityValue("\(pct) percent")
    }
}

/// A capsule gauge in the same language as `UsageGauge`, showing the recent
/// *change* in 5h utilization rather than an absolute level: how far it moved
/// across the sample window, signed. Rising usage tints warm (heading toward the
/// limit); falling tints green; the fill length is the magnitude.
struct TrendGauge: View {
    let delta: Int

    private let trackWidth = Constants.usageTrackWidth
    private let trackHeight: CGFloat = 5

    /// Fill fraction for a signed point change, square-rooted over the full
    /// 0-100 range. The old linear 20-point scale saturated: every move past 20
    /// points drew an identical full bar, so +20 and +52 were the same picture.
    /// Square root keeps resolution where samples actually land — single-digit
    /// moves stay distinguishable — while leaving headroom all the way to 100.
    static func fillFraction(delta: Int) -> CGFloat {
        sqrt(CGFloat(min(100, abs(delta))) / 100)
    }

    private var tint: Color {
        if delta > 0 { return .usageAmber }  // rising
        if delta < 0 { return .usageGreen }  // falling
        return Color.secondary
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("chg")
                .font(.claudeMono(11))
                .foregroundStyle(Color.secondary)
                .fixedSize()
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: trackWidth, height: trackHeight)
                Capsule()
                    .fill(tint)
                    .frame(width: max(delta != 0 ? 3 : 0,
                                      trackWidth * Self.fillFraction(delta: delta)),
                           height: trackHeight)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: delta)
            }
            Text("\(delta > 0 ? "+" : "")\(delta)%")
                .font(.claudeMono(11)).monospacedDigit()
                .foregroundStyle(tint)
                .fixedSize()
        }
        .help("5h usage change over recent polls")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("5-hour usage change over recent polls")
        .accessibilityValue("\(delta > 0 ? "up" : delta < 0 ? "down" : "unchanged") \(abs(delta)) percent")
    }
}

struct SessionRow: View {
    @ObservedObject var feed: FeedWatcher
    let item: SessionRowItem
    let now: Date
    @StateObject private var hover = HoverState()

    private var session: SessionFeed { item.session }

    var body: some View {
        // One line: [glyph] project-name ×N  model  status…  ctx%  time  [chip]
        HStack(spacing: 5) {
            Text(glyph)
                .font(.claudeMono(13))
                .foregroundStyle(tint)
                .frame(width: 15)

            // Column 1: Project Name + Count. Fixed width ensures alignment of subsequent columns.
            HStack(spacing: 3) {
                // A grouped row stands for several idle sessions sharing a directory —
                // displayItems groups on cwd, not name — so only a single-session row
                // can honestly show a session name.
                Text(item.count > 1 ? session.projectName : session.displayName)
                    .font(.claudeMono(11))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if item.count > 1 {
                    Text("×\(item.count)")
                        .font(.claudeMono(11))
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(width: 105, alignment: .leading)

            // Column 2: Model (fixed width). Keeps Status aligned.
            Group {
                if let rawModel = feed.modelDisplay(for: session) {
                    Text(FeedWatcher.modelFamily(rawModel))
                        .font(.claudeMono(11)).fontWeight(.semibold)
                        .foregroundStyle(Color.modelTint(rawModel))
                        .lineLimit(1)
                } else {
                    Text("")
                }
            }
            .frame(width: 46, alignment: .leading)

            // Column 3: Status / Activity (flexible width, truncating if necessary),
            // with the working-dots attached to the word they belong to. The
            // maxWidth frame — not a Spacer — pushes the trailing columns right.
            HStack(spacing: 0) {
                Text(statusLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // A fixed slot: the dots grow and shrink every 0.5s, and letting that
                // reflow the status text would make its truncation flicker in time
                // with them. Reserved even at rest so the column edge never moves.
                Text(isWorking ? FeedWatcher.workingDots(at: now) : "")
                    .frame(width: 13, alignment: .leading)
            }
            .font(.claudeMono(11))
            .foregroundStyle(statusColor)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Time + host chip travel together as one right-flush unit with a tight
            // gap, so the time stays near the right edge with the tag just after it.
            HStack(spacing: 4) {
                // This session's own context tokens, tinted by how full its window
                // is — the percentage still drives the color, it just isn't the
                // number shown. The slot is held even when a session has no
                // context_window yet, so the times below it stay aligned.
                Text(contextTokens)
                    .font(.claudeMono(11))
                    .monospacedDigit()
                    .foregroundStyle(contextColor)
                    .frame(width: 30, alignment: .trailing)

                // Elapsed / waiting / done time in a fixed-width column so the times
                // line up down the panel regardless of label.
                Text(timeText)
                    .font(.claudeMono(11))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(Color.secondary)
                    .frame(width: 48, alignment: .trailing)

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
                            .font(.claudeMono(10))
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
        .accessibilityLabel("\(session.displayName), \(statusLabel) \(timeText)\(contextTokens.isEmpty ? "" : ", \(contextTokens) context tokens")")
        .accessibilityHint("Opens this session's app")
        // children: .ignore hides the hover-revealed ✕ entirely, so clearing a
        // session is otherwise unreachable without a mouse.
        .accessibilityAction(named: "Clear session") { feed.clear(item) }
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
        SessionLauncher.focus(host: session.host, pid: session.pid, cwd: session.cwd)
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

    /// An idle row's context number recedes with the rest of the row; a live one
    /// is tinted by how many tokens it's carrying.
    private var contextColor: Color {
        guard let used = session.contextTokens, session.status != .idle else { return .secondary }
        return .contextTint(used)
    }

    private var contextTokens: String {
        session.contextTokens.map(FeedWatcher.formatTokens) ?? ""
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
            return "thinking"
        case .attention:
            return "needs input"
        case .idle:
            return session.lastDuration != nil ? "done" : "idle"
        }
    }

    /// True while the row is mid-turn — the dots animate and the time counts up.
    private var isWorking: Bool { session.status == .tool || session.status == .thinking }

    /// The time shown right-aligned at the end of the row: elapsed in-turn while
    /// working, how long it's been waiting for attention, the finished turn's
    /// duration when done, or how long idle. Empty when there's nothing to show.
    private var timeText: String {
        switch session.status {
        case .tool, .thinking:
            // Time in the current turn. turn_start is null when nothing is running,
            // so a working row without one has no elapsed time to show.
            guard let start = session.turnStart else { return "" }
            return FeedWatcher.formatDuration(max(0, Int(now.timeIntervalSince(start))))
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
        parts.append("path: \(session.displayPath)")
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

/// Drives the one-click installer button in the Setup-needed panel. A small
/// ObservableObject rather than @State, matching HoverState (the codebase avoids
/// @State so the swiftc dev-loop build keeps working).
class InstallState: ObservableObject {
    @Published var installing = false
    @Published var message: String?
}
