//
//  MenuContentView.swift
//  claude spinner
//
//  The panel shown when the menubar icon is clicked: one live row per session.
//

import SwiftUI

struct MenuContentView: View {
    let feed: FeedWatcher

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
                            SessionRow(session: session, now: context.date)
                            if session.id != feed.sortedSessions.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(width: 320)
        // No visible Quit button; ⌘Q still terminates while the panel is open.
        .background(
            Button("") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .opacity(0)
        )
    }
}

struct SessionRow: View {
    let session: SessionFeed
    let now: Date

    var body: some View {
        HStack(spacing: 11) {
            Text(glyph)
                .font(.claudeMono(16))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayPath)
                    .font(.claudeMono(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusText)
                    .font(.claudeMono(11))
                    .foregroundStyle(session.isWorking ? Color.claude : Color.claudeDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
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
        let timer = elapsed >= 60 ? "\(elapsed / 60)m \(elapsed % 60)s" : "\(elapsed)s"
        switch session.status {
        case .tool:
            return session.tool.isEmpty ? " (\(timer))" : " (\(timer) · \(session.tool))"
        case .thinking:
            return elapsed >= 30 ? " (\(timer) · still thinking)" : " (\(timer))"
        default:
            return ""
        }
    }
}
