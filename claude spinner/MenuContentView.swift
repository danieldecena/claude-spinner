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
                                Divider().padding(.leading, 14)
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

    private var separator: some View {
        Text("·").foregroundStyle(Color.secondary.opacity(0.5))
    }

    /// A block-bar for a 0–100 percentage: filled part tinted by urgency, empty
    /// part muted. Returned as a concatenated Text so it sits inline in the row.
    /// A block-bar for a 0–100 percentage: filled part tinted by urgency, empty
    /// part muted. Six segments so 5h and 7d both fit on one line. Returned as a
    /// concatenated Text so it sits inline in the row.
    private func bar(_ pct: Int, segments: Int = 6) -> Text {
        let filled = min(segments, max(0, Int((Double(pct) / 100 * Double(segments)).rounded())))
        return Text(String(repeating: "█", count: filled))
                .foregroundColor(Color.usageTint(pct))
             + Text(String(repeating: "░", count: segments - filled))
                .foregroundColor(Color.secondary.opacity(0.35))
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            // 1s clock keeps the reset countdown live-ticking.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 6) {
                    if feed.hasUsage {
                        if let model = feed.globalModelFamily {
                            Text(model).foregroundStyle(Color.modelTint(feed.globalModel))
                            separator
                        }
                        if let h5 = feed.usageFiveHourPct {
                            Text("5h").foregroundStyle(Color.secondary)
                            bar(h5)
                            Text("\(h5)%").foregroundStyle(Color.usageTint(h5))
                        }
                        if let d7 = feed.usageSevenDayPct {
                            separator
                            Text("7d").foregroundStyle(Color.secondary)
                            bar(d7)
                            Text("\(d7)%").foregroundStyle(Color.usageTint(d7))
                        }
                        // Live countdown inline (both reset formats don't fit one
                        // row at 360px); the exact clock time is in the tooltip.
                        if let rel = feed.usageFiveHourResetRelative {
                            separator
                            Text("↺\(rel)")
                                .foregroundStyle(Color.secondary.opacity(0.8))
                                .help(feed.usageFiveHourReset.map { "Resets at \($0)" } ?? "")
                        }
                    } else {
                        Text("no usage data yet").foregroundStyle(Color.secondary.opacity(0.6))
                    }

                    Spacer(minLength: 0)
                }
                .font(.claudeMono(11))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
        }
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
                    .foregroundStyle(Color.claudeDim)
            }

            Text(statusText)
                .font(.claudeMono(12))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            // Fixed trailing slot so ctx% aligns across rows and the hover ✕ never
            // squeezes the activity text.
            Group {
                if hover.isHovering {
                    Button {
                        feed.clear(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color.claudeDim)
                } else if let ctx = session.contextPct {
                    Text("\(ctx)%")
                        .font(.claudeMono(11))
                        .foregroundStyle(Color.contextTint(ctx))
                        .help("Context window \(ctx)% full")
                }
            }
            .frame(width: 34, alignment: .trailing)
        }
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
        .accessibilityLabel("\(session.projectName), \(statusText)")
        .accessibilityHint("Opens this session's app")
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// An inset, rounded highlight pill behind the row — a persistent blue wash for
    /// attention, a lighter wash on hover, nothing at rest. Inset + rounded reads as
    /// a proper selection rather than an edge-to-edge band, and it fades in/out.
    @ViewBuilder private var rowHighlight: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(rowFill)
            .animation(.easeInOut(duration: 0.12), value: hover.isHovering)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }

    private var rowFill: Color {
        if session.status == .attention {
            return Color.attention.opacity(hover.isHovering ? 0.28 : 0.16)
        }
        return hover.isHovering ? Color.primary.opacity(0.09) : Color.clear
    }

    /// Idle rows fade with age so a stale session recedes instead of sitting at
    /// full strength for hours; working/attention rows stay fully opaque.
    private var rowOpacity: Double {
        guard session.status == .idle, let updated = session.updated else { return 1.0 }
        let age = now.timeIntervalSince(updated)
        let t = min(max((age - Constants.idleFadeStart) / Constants.idleFadeSpan, 0), 1)
        return 1.0 - (1.0 - Constants.idleMinOpacity) * t
    }
    
    /// Open/focus the session in the app it's actually running in (its captured
    /// host), so a click lands you in the right place. Folder-aware hosts open the
    /// project dir; others (iTerm2, the Claude desktop app) are just focused;
    /// unknown host falls back to a terminal at the folder.
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
            task.arguments = pathValid ? ["-a", "Ghostty.app", path]
                                       : ["-b", "com.mitchellh.ghostty"]
        case "com.apple.Terminal", "Apple_Terminal":
            task.arguments = pathValid ? ["-a", "Terminal", path]
                                       : ["-b", "com.apple.Terminal"]
        case "com.googlecode.iterm2", "iTerm.app":
            task.arguments = ["-b", "com.googlecode.iterm2"]   // can't target a folder; focus it
        case "com.anthropic.claudefordesktop":
            task.arguments = ["-b", "com.anthropic.claudefordesktop"]  // focus the desktop app
        default:
            guard pathValid else { return }
            let ghostty = FileManager.default.fileExists(atPath: "/Applications/Ghostty.app")
            task.arguments = ["-a", ghostty ? "Ghostty.app" : "Terminal", path]
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

    /// The concrete activity, not the whimsical spinner word (that lives in the
    /// menu title): `running Bash · 4m 57s`, `thinking · 22s`, `done · 5m 18s`.
    private var statusText: String {
        switch session.status {
        case .tool:
            let what = session.tool.isEmpty ? "running" : "running \(session.tool)"
            return "\(what)\(elapsedSuffix)"
        case .thinking:
            return "thinking\(elapsedSuffix)"
        case .attention:
            // Lead with how long it's been waiting so a fresh pause reads apart
            // from a stuck one; the time survives truncation, the message trails.
            let msg = session.message.isEmpty ? "waiting for you" : session.message
            return waitingSuffix.isEmpty ? msg : "\(waitingSuffix) · \(msg)"
        case .idle:
            if let dur = session.lastDuration {
                return "done · \(FeedWatcher.formatDuration(dur))"
            }
            return idleSuffix.isEmpty ? "idle" : "idle · \(idleSuffix)"
        }
    }

    /// ` · 4m 57s` elapsed since the turn started, or empty if not in a turn.
    private var elapsedSuffix: String {
        guard let start = session.turnStart else { return "" }
        let elapsed = max(0, Int(now.timeIntervalSince(start)))
        return " · \(FeedWatcher.formatDuration(elapsed))"
    }

    /// How long since the session last changed — used to show waiting/idle age.
    private var sinceUpdated: String {
        guard let updated = session.updated else { return "" }
        return FeedWatcher.formatDuration(max(0, Int(now.timeIntervalSince(updated))))
    }
    private var waitingSuffix: String { sinceUpdated }
    private var idleSuffix: String { sinceUpdated }
}

class HoverState: ObservableObject {
    @Published var isHovering = false
}
