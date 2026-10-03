//
//  FloatingBar.swift
//
//  The reply bar that floats at the bottom of the window, after Music's mini
//  player: which session it speaks to, what has been typed to each session, and
//  the glass capsule itself. The decisions live in pure functions so the rules
//  that protect a draft are tested without drawing anything.
//

import Combine
import SwiftUI

/// What has been typed to each session and not yet sent. One store for every
/// reply field in the window, so a draft follows its session whichever field it is
/// typed in, and switching sessions swaps the text instead of discarding it.
@MainActor
final class ReplyDrafts: ObservableObject {
    static let shared = ReplyDrafts()

    @Published private(set) var drafts: [String: String] = [:]

    func text(for id: String) -> String { drafts[id] ?? "" }

    func set(_ text: String, for id: String) {
        // An emptied field removes its entry: the store holds only what is unsent.
        if text.isEmpty { drafts[id] = nil } else { drafts[id] = text }
    }

    func binding(for id: String) -> Binding<String> {
        Binding(get: { self.text(for: id) }, set: { self.set($0, for: id) })
    }

    func hasDraft(_ id: String?) -> Bool {
        guard let id, let text = drafts[id] else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum BarTarget {
    /// Which session the bar speaks to.
    ///
    /// - A session whose pane is open is always the target: opening it is the
    ///   user's own choice.
    /// - Anywhere else it is the session that needs the user, else the one most
    ///   recently working.
    /// - But never switches while there is an unsent draft in the field: a
    ///   message half typed to one session must not be sent to, or lost under, the
    ///   next. The session that would have taken over is counted as waiting.
    ///
    /// `current` is the target as last chosen; `exists` says whether it is still a
    /// live session (a draft to a session that ended cannot be held on to).
    static func choose(current: String?, openSession: String?, attention: String?,
                       recentlyWorking: String?, currentHasDraft: Bool,
                       exists: (String) -> Bool) -> String? {
        if let openSession { return openSession }
        if let current, currentHasDraft, exists(current) { return current }
        return attention ?? recentlyWorking
    }

    /// Sessions that need the user and are not the bar's target, for the "waiting"
    /// pill that stands in for the switch that was held back.
    static func waiting(attention: [String], target: String?) -> Int {
        attention.filter { $0 != target }.count
    }

    /// Whether the session the bar speaks to needs the user: blocked on a prompt, or
    /// holding a question or form. The bar takes the attention colour then, so a
    /// session that needs you is never drawn like one that is merely open.
    static func needsYou(blocked: Bool, hasAsk: Bool) -> Bool { blocked || hasAsk }
}

/// How a reply is sent, shared by the bar and the conversation card's field.
enum ReplySend {
    /// Starts the send, or says why not through `notice`. `done` is called with
    /// whether it was delivered, so the caller can clear its draft only then.
    @MainActor
    static func send(_ message: String, to session: SessionFeed, feedDir: URL,
                     notice: @escaping (NoticeMessage?) -> Void,
                     started: () -> Void, done: @escaping (Bool) -> Void) {
        // A session holding a question reads as working in the feed, so the
        // replier's refusal said "mid-turn" about a session waiting on you.
        if AskInbox.shared.pending.contains(where: { $0.sessionId == session.id }) {
            notice(.init(kind: .error, text: "That session is waiting on a question. Answer it first."))
            return
        }
        started()
        notice(nil)
        SessionReplier.reply(to: session, text: message, feedDir: feedDir) { result in
            switch result {
            case .success:
                notice(.init(kind: .info, text: "Sent \u{2014} the session picked it up."))
                done(true)
            case .failure(let error):
                notice(error.errorDescription.map { .init(kind: .error, text: $0) })
                done(false)
            }
        }
    }
}

struct FloatingBar: View {
    let session: SessionFeed
    let feedDir: URL
    let waiting: Int
    /// Whether the conversation card beside it already says the outcome.
    let showsNotice: Bool
    @Binding var notice: NoticeMessage?

    @ObservedObject private var drafts = ReplyDrafts.shared
    @ObservedObject private var music = NowPlaying.shared
    @ObservedObject private var asks = AskInbox.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sending = false
    @State private var hasPane = false
    @FocusState private var focused: Bool

    /// Four lines, then the field scrolls inside the capsule and the capsule stops
    /// growing.
    static let maxLines = 4

    /// The playing cover's colour on the glass, or nil for plain glass: while Music
    /// is closed, with no cover, or when the cover would take the bar's text below
    /// 4.5:1 on it.
    private var tint: Color? {
        guard case .track = music.status, let average = music.artworkAverage else { return nil }
        let dark = colorScheme == .dark
        let pane = dark ? Color.Ink.paneDark : Color.Ink.paneLight
        let ink: BarTint.RGB = dark ? (1, 1, 1) : (0.1, 0.1, 0.1)
        let label = dark ? Color.Ink.labelDark : Color.Ink.labelLight
        guard let used = BarTint.usable(average: average, pane: (pane.0, pane.1, pane.2), ink: ink,
                                        label: (label.0, label.1, label.2)) else { return nil }
        return Color(red: used.r, green: used.g, blue: used.b).opacity(BarTint.strength)
    }

    private var tintKey: String {
        guard let a = music.artworkAverage else { return "" }
        return String(format: "%.2f,%.2f,%.2f", a.r, a.g, a.b)
    }

    /// A session holding a question cannot be sent a reply (`ReplySend` refuses), so
    /// the field says so before the first keystroke instead of after Return.
    private var placeholder: String {
        asks.pending.contains { $0.sessionId == session.id }
            ? "Answer the question first\u{2026}" : "Reply to \(session.distinctName)\u{2026}"
    }

    private var needsYou: Bool {
        BarTarget.needsYou(blocked: session.isBlockedOnYou,
                           hasAsk: asks.pending.contains { $0.sessionId == session.id })
    }

    private var text: Binding<String> { drafts.binding(for: session.id) }
    private var canSend: Bool {
        !sending && !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsNotice, let notice { Notice(notice) }
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        identity
                        field
                        controls
                    }
                    // Draws nothing while Music is not open.
                    MusicStrip()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassEffect(.regular.tint(tint), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .animation(reduceMotion ? nil : .easeOut(duration: BarTint.fadeDuration), value: tintKey)
                // The glass is barely lighter than a dark page: an edge and a soft
                // shadow are what make it float instead of reading as a strip.
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(needsYou ? Color.attention.opacity(0.85) : Color.primary.opacity(0.14),
                                      lineWidth: needsYou ? 1.5 : 0.5)
                }
                .shadow(color: .black.opacity(0.28), radius: 14, y: 4)
            }
        }
        .frame(maxWidth: 760)
        .onAppear { NowPlaying.shared.start() }
        .task(id: session.id) {
            let pid = session.pid
            hasPane = await Task.detached(priority: .utility) {
                pid != nil && SessionReplier.hasPane(session)
            }.value
        }
    }

    // MARK: Left: who it speaks to

    private var identity: some View {
        HStack(spacing: 8) {
            ContextDot(percent: session.stats.contextUsedPercent)
                .overlay(alignment: .topTrailing) {
                    // The mark that says this session needs you, beside the colour of
                    // its status line and the edge of the capsule: three cues, so it
                    // is not carried by hue alone.
                    if needsYou {
                        Circle().fill(Color.attention).frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Color.card, lineWidth: 1.5))
                            .offset(x: 3, y: -3)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(session.distinctName).font(.ui(11)).fontWeight(.semibold).lineLimit(1)
                    .help(session.distinctName)
                Text(session.statusLabel).font(.ui(10)).lineLimit(1)
                    .fontWeight(needsYou ? .semibold : .regular)
                    .foregroundStyle(needsYou ? Color.attention : Color.label)
            }
            .frame(maxWidth: 150, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(needsYou ? "\(session.distinctName), needs you, \(session.statusLabel)"
                                         : "\(session.distinctName), \(session.statusLabel)")
            if waiting > 0 {
                // Standing in for a switch that was held back while you type.
                Text("\(waiting) waiting").font(.ui(10)).fontWeight(.semibold)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.attention.opacity(0.16), in: Capsule())
                    .foregroundStyle(Color.attention)
                    .accessibilityLabel("\(waiting) other sessions need you")
            }
        }
    }

    // MARK: Centre: the reply field

    /// The field sits on an opaque fill of its own. Music's capsule can be as
    /// transparent as it is because it never takes text; whatever is scrolled
    /// behind this one must not be able to lower the text's contrast.
    private var field: some View {
        // The placeholder is drawn in the label ink: the system's own grey measured
        // 3.1:1 on the white card, under the 4.5:1 a placeholder owes.
        TextField(text: text, prompt: Text(placeholder).foregroundStyle(Color.label),
                  axis: .vertical) { Text("Reply to \(session.distinctName)") }
            .textFieldStyle(.plain)
            .font(.claudeMono(11))
            .lineLimit(1...Self.maxLines)
            .focused($focused)
            .onSubmit(send)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(focused ? Color.primary.opacity(0.7) : Color.label.opacity(0.25),
                                  lineWidth: focused ? 2 : 1)
            }
            .accessibilityLabel("Reply to \(session.distinctName)")
    }

    // MARK: Right: send and the two actions that matter

    private var controls: some View {
        HStack(spacing: 6) {
            Button(sending ? "Sending\u{2026}" : "Send", action: send)
                .font(.ui(11))
                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                .disabled(!canSend)
            ForEach([SessionAction.interrupt, .focus]) { action in
                let reason = SessionActions.unavailableReason(action, session: session, hasPane: hasPane)
                Button { perform(action) } label: {
                    Image(systemName: action.symbol).frame(width: 18, height: 18)
                }
                .buttonStyle(.glass)
                .disabled(reason != nil)
                .opacity(reason == nil ? 1 : 0.45)
                .help(reason ?? action.title)
                .accessibilityLabel(action.title)
            }
        }
    }

    private func send() {
        let message = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !sending else { return }
        let id = session.id
        ReplySend.send(message, to: session, feedDir: feedDir,
                       notice: { notice = $0 },
                       started: { sending = true },
                       done: { delivered in
                           sending = false
                           // Cleared only once it landed: a failed send keeps the text.
                           if delivered { ReplyDrafts.shared.set("", for: id) }
                       })
    }

    private func perform(_ action: SessionAction) {
        notice = nil
        if !action.needsPane {
            notice = SessionActions.runLocal(action, session: session)
                ? nil : .init(kind: .error, text: "Couldn't do that.")
            return
        }
        SessionReplier.interrupt(session) { result in
            switch result {
            case .success: notice = .init(kind: .info, text: "Interrupted.")
            case .failure(let error): notice = error.errorDescription.map { .init(kind: .error, text: $0) }
            }
        }
    }
}

/// The session's context as a small ring: a mark, with the figure beside it in
/// the bar's own caption, so it is never the only carrier of the number.
private struct ContextDot: View {
    let percent: Int?

    var body: some View {
        ZStack {
            // An unknown reading is a dashed track, not an empty one: an empty ring
            // reads as a spinner or a radio button.
            Circle().stroke(Color.secondary.opacity(0.25),
                            style: StrokeStyle(lineWidth: 3, dash: percent == nil ? [2, 3] : []))
            if let percent {
                Circle().trim(from: 0, to: max(0.02, min(1, Double(percent) / 100)))
                    .stroke(Color.usageTint(percent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context")
        .accessibilityValue(percent.map { "\($0) percent" } ?? "unknown")
    }
}
