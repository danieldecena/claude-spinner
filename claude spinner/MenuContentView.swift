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
                Text("No active sessions")
                    .font(.claudeMono(12)).foregroundStyle(Color.claudeDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 14)
            } else {
                // One ticking clock drives every row's spinner + timer in phase.
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    VStack(spacing: 0) {
                        ForEach(feed.displayItems) { item in
                            SessionRow(feed: feed, item: item, now: context.date)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            if item.id != feed.displayItems.last?.id {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                    // Animate only when the set/order of rows changes (keyed by ids),
                    // not on every 0.1s spinner tick.
                    .animation(.easeInOut(duration: 0.2), value: feed.displayItems.map(\.id))
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
                HStack(spacing: 10) {
                    if feed.hasUsage {
                        // Dim the numbers when stale so a frozen snapshot doesn't
                        // read as live; the "as of" time is in the tooltip.
                        Group {
                            if let model = feed.globalModelFamily {
                                Text(model)
                                    .font(.claudeMono(11)).fontWeight(.semibold)
                                    .foregroundStyle(Color.modelTint(feed.globalModel))
                                    .fixedSize()
                            }
                            if let h5 = feed.usageFiveHourPct {
                                UsageGauge(label: "5h", pct: h5)
                            }
                            if let d7 = feed.usageSevenDayPct {
                                UsageGauge(label: "7d", pct: d7)
                            }
                        }
                        // Dim when stale so a frozen snapshot doesn't read as live;
                        // the "as of" time and age live in the hover tooltip.
                        .opacity(feed.usageIsStale ? 0.5 : 1)
                        .help(feed.usageAsOfString)

                        Spacer(minLength: 8)

                        // Live countdown (both reset formats don't fit one row at
                        // 360px); the exact clock time is in the tooltip.
                        if let rel = feed.usageFiveHourResetRelative {
                            HStack(spacing: 2) {
                                Text("↺").font(.claudeMono(10))
                                Text(rel).font(.claudeMono(11)).monospacedDigit()
                            }
                            .foregroundStyle(Color.secondary.opacity(0.75))
                            .help(feed.usageFiveHourReset.map { "Resets at \($0)" } ?? "")
                        }
                    } else {
                        Text("no usage data yet")
                            .font(.claudeMono(11))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                        Spacer(minLength: 0)
                    }
                }
                .lineLimit(1)
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

    private let trackWidth: CGFloat = 32
    private let trackHeight: CGFloat = 5

    var body: some View {
        HStack(spacing: 5) {
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
            }
            Text("\(pct)%")
                .font(.claudeMono(11)).monospacedDigit()
                .foregroundStyle(Color.usageTint(pct))
                .fixedSize()
        }
        .help("\(label == "5h" ? "5-hour" : "7-day") usage \(pct)%")
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
        HStack(spacing: 7) {
            Text(glyph)
                .font(.claudeMono(14))
                .foregroundStyle(tint)
                .frame(width: 16)

            // Name wins the space; a long activity/message (e.g. an attention
            // message) truncates before the project name does. The wider panel
            // leaves room for both the name and a short "thinking · 35s".
            Text(session.projectName)
                .font(.claudeMono(13))
                .foregroundStyle(nameColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            if item.count > 1 {
                Text("×\(item.count)")
                    .font(.claudeMono(11))
                    .foregroundStyle(Color.secondary)
            }

            Text(statusLabel)
                .font(.claudeMono(12))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            // Elapsed / waiting / done time in its own right-aligned column so the
            // times line up down the panel, independent of the activity label width.
            if !timeText.isEmpty {
                Text(timeText)
                    .font(.claudeMono(11))
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }

            // Trailing hover-only clear button. A clear spacer holds the slot width
            // at all times, so the time column never shifts when the ✕ appears.
            ZStack(alignment: .trailing) {
                Color.clear.frame(width: 14, height: 1)
                if hover.isHovering {
                    Button {
                        feed.clear(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color.secondary)
                }
            }
        }
        // Everything in a row renders lowercase — including hook-supplied text like
        // the attention message and tool names — for one consistent visual voice.
        .textCase(.lowercase)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .opacity(rowOpacity)
        .background(rowHighlight)
        .onHover { hover.isHovering = $0 }
        .onTapGesture {
            openSession()
        }
        .contextMenu {
            Button("Copy Session ID") { copyToPasteboard(session.id) }
            Button("Copy Path") { copyToPasteboard(session.cwd) }
            Divider()
            Button("Clear") { feed.clear(item) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.projectName), \(statusLabel) \(timeText)")
        .accessibilityHint("Opens this session's app")
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
    
    /// Bring the session's host app to the front. Terminals (Ghostty/Terminal/
    /// iTerm) are only focused — macOS `open` can't target the exact tab running a
    /// session, so passing a folder would spawn a new window; we avoid that. VS Code
    /// does reuse its window, so it opens the project folder in place. An unknown
    /// host focuses the user's terminal rather than spawning a fresh one.
    private func openSession() {
        let path = session.cwd
        let pathValid = !path.isEmpty && FileManager.default.fileExists(atPath: path)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")

        switch session.host {
        case "com.microsoft.VSCode", "vscode":
            task.arguments = pathValid ? ["-b", "com.microsoft.VSCode", path]
                                       : ["-b", "com.microsoft.VSCode"]
        case "com.mitchellh.ghostty", "ghostty":
            task.arguments = ["-b", "com.mitchellh.ghostty"]
        case "com.apple.Terminal", "Apple_Terminal":
            task.arguments = ["-b", "com.apple.Terminal"]
        case "com.googlecode.iterm2", "iTerm.app":
            task.arguments = ["-b", "com.googlecode.iterm2"]
        case "com.anthropic.claudefordesktop":
            task.arguments = ["-b", "com.anthropic.claudefordesktop"]
        default:
            // Unknown host — focus the user's terminal, no new window.
            let ghostty = FileManager.default.fileExists(atPath: "/Applications/Ghostty.app")
            task.arguments = ["-b", ghostty ? "com.mitchellh.ghostty" : "com.apple.Terminal"]
        }
        try? task.run()
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
            return "thinking"
        case .attention:
            return session.message.isEmpty ? "waiting for you" : session.message
        case .idle:
            return session.lastDuration != nil ? "done" : "idle"
        }
    }

    /// The time shown right-aligned at the end of the row: elapsed in-turn while
    /// working, how long it's been waiting for attention, the finished turn's
    /// duration when done, or how long idle. Empty when there's nothing to show.
    private var timeText: String {
        switch session.status {
        case .tool, .thinking:
            guard let start = session.turnStart else { return "" }
            return FeedWatcher.formatDuration(max(0, Int(now.timeIntervalSince(start))))
        case .attention:
            return sinceUpdated
        case .idle:
            if let dur = session.lastDuration { return FeedWatcher.formatDuration(dur) }
            return sinceUpdated
        }
    }

    /// How long since the session last changed — used for waiting/idle age.
    private var sinceUpdated: String {
        guard let updated = session.updated else { return "" }
        return FeedWatcher.formatDuration(max(0, Int(now.timeIntervalSince(updated))))
    }
}

class HoverState: ObservableObject {
    @Published var isHovering = false
}
