//
//  MenuContentView.swift
//  claude spinner
//
//  The panel shown when the menubar icon is clicked: one live row per session.
//

import SwiftUI

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
                        ForEach(feed.sortedSessions) { session in
                            SessionRow(feed: feed, session: session, now: context.date)
                            if session.id != feed.sortedSessions.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
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

/// Always-present footer: live usage (model · 5h limit · total cost) on the
/// left, the settings gear on the right so it's reachable even with no usage
/// data yet. A 1s clock keeps the "resets in" countdown current.
struct UsageFooter: View {
    @ObservedObject var feed: FeedWatcher

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 8) {
                    if let usage = feed.globalRateLimitText {
                        if let model = feed.globalModelShort {
                            Text(model).foregroundStyle(Color.claudeDim.opacity(0.8))
                            Text("·").foregroundStyle(Color.claudeDim.opacity(0.4))
                        }
                        Text(usage).foregroundStyle(Color.claudeDim)
                        if let cost = feed.globalCost {
                            Text("·").foregroundStyle(Color.claudeDim.opacity(0.4))
                            Text(String(format: "$%.2f", cost)).foregroundStyle(Color.claudeDim)
                        }
                    } else {
                        Text("no usage data yet").foregroundStyle(Color.claudeDim.opacity(0.55))
                    }

                    Spacer(minLength: 6)

                    Menu {
                        Toggle("Launch at Login", isOn: $feed.launchAtLogin)
                        Button("Clear All Sessions") { feed.clearAll() }
                        Button("Quit") { NSApplication.shared.terminate(nil) }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(Color.claudeDim)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 16)
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
    let session: SessionFeed
    let now: Date
    @StateObject private var hover = HoverState()

    var body: some View {
        HStack(spacing: 11) {
            Text(glyph)
                .font(.claudeMono(16))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.displayPath)
                        .font(.claudeMono(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    if let ctx = session.contextPct {
                        Text("\(ctx)% ctx")
                            .font(.claudeMono(11))
                            .foregroundStyle(Color.claudeDim)
                    }
                    if let cost = session.costUsd {
                        Text(String(format: "$%.2f", cost))
                            .font(.claudeMono(11))
                            .foregroundStyle(Color.claudeDim)
                    }
                }
                Text(statusText)
                    .font(.claudeMono(11))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            
            if hover.isHovering {
                Button {
                    feed.clearSession(id: session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color.claudeDim)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .opacity(rowOpacity)
        .background(hover.isHovering ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { hover.isHovering = $0 }
        .onTapGesture {
            openTerminal(at: session.cwd)
        }
    }

    /// Idle rows fade with age so a stale session recedes instead of sitting at
    /// full strength for hours; working/attention rows stay fully opaque.
    private var rowOpacity: Double {
        guard session.status == .idle, let updated = session.updated else { return 1.0 }
        let age = now.timeIntervalSince(updated)
        let t = min(max((age - Constants.idleFadeStart) / Constants.idleFadeSpan, 0), 1)
        return 1.0 - (1.0 - Constants.idleMinOpacity) * t
    }
    
    /// Open a terminal at the session's project dir. Prefers Ghostty (the app's
    /// styling target); falls back to Terminal.app when Ghostty isn't installed.
    /// Uses `open -a` (no `-n`) with the folder as the argument: Ghostty handles
    /// public.directory, so this reuses the running instance and opens a window
    /// at the dir instead of spawning a duplicate Ghostty process each click.
    private func openTerminal(at path: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        let ghostty = FileManager.default.fileExists(atPath: "/Applications/Ghostty.app")
        task.arguments = ["-a", ghostty ? "Ghostty.app" : "Terminal", path]
        try? task.run()
    }

    private var glyph: String {
        switch session.status {
        case .attention: return "⚠"
        case .thinking, .tool: return Spinner.frame(at: now)
        case .idle: return "✻"
        }
    }

    private var tint: Color {
        switch session.status {
        case .attention: return .orange
        case .thinking, .tool: return .claude
        case .idle: return .claudeDim
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .attention: return .orange
        case .thinking, .tool: return .claude
        case .idle: return .claudeDim
        }
    }

    /// Mirrors the terminal spinner line: `Calculating… (22s · still thinking)`
    /// while active, or the grey `Sautéed for 5m 18s` done line when finished.
    private var statusText: String {
        switch session.status {
        case .thinking, .tool:
            let word = SpinnerWords.word(for: session)
            return "\(word)…\(hint)"
        case .attention:
            return session.message.isEmpty ? "Waiting for you…" : session.message
        case .idle:
            if let dur = session.lastDuration {
                return "\(SpinnerWords.pastWord(for: session)) for \(FeedWatcher.formatDuration(dur))"
            }
            return "Idle"
        }
    }

    private var hint: String {
        guard let start = session.turnStart else { return "" }
        let elapsed = max(0, Int(now.timeIntervalSince(start)))
        let timer = FeedWatcher.formatDuration(elapsed)
        switch session.status {
        case .tool:
            return session.tool.isEmpty ? " (\(timer))" : " (\(timer) · running \(session.tool))"
        case .thinking:
            return " (\(timer))"
        default:
            return ""
        }
    }
}

class HoverState: ObservableObject {
    @Published var isHovering = false
}
