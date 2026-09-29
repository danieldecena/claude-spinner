import Foundation
import AppKit

/// Things you can do to a session from the window.
///
/// Split by what they need. The local ones touch only this Mac and always work.
/// The typed ones go through `SessionReplier`'s pane, so they inherit all of its
/// constraints -- tmux only, idle only, delivery confirmed by observation -- and
/// are unavailable rather than silently ineffective when a session isn't in a
/// pane.
enum SessionAction: String, CaseIterable, Identifiable {
    case interrupt
    case compact
    case clear
    case revealCWD
    case openTranscript
    case copySessionID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interrupt: return "Interrupt"
        case .compact: return "Compact"
        case .clear: return "Clear"
        case .revealCWD: return "Reveal folder"
        case .openTranscript: return "Open transcript"
        case .copySessionID: return "Copy session id"
        }
    }

    /// The toolbar draws these as icons; the title rides along as the tooltip
    /// and the accessibility label.
    var symbol: String {
        switch self {
        case .interrupt: return "stop.circle"
        case .compact: return "arrow.down.right.and.arrow.up.left"
        case .clear: return "eraser"
        case .revealCWD: return "folder"
        case .openTranscript: return "doc.text"
        case .copySessionID: return "doc.on.doc"
        }
    }

    /// Needs a tmux pane to type into.
    var needsPane: Bool {
        switch self {
        case .interrupt, .compact, .clear: return true
        case .revealCWD, .openTranscript, .copySessionID: return false
        }
    }

    /// Throws away context that cannot be recovered, so it asks first.
    var isDestructive: Bool {
        switch self {
        case .clear, .compact: return true
        default: return false
        }
    }

    var confirmation: String? {
        switch self {
        case .clear:
            return "Clear this session? Its conversation is discarded and cannot be recovered."
        case .compact:
            return "Compact this session? Claude keeps a summary and drops the rest of the transcript."
        default: return nil
        }
    }

    /// What gets typed at the prompt, or nil for the local actions.
    ///
    /// Interrupt is Escape alone and deliberately sends no text: it cancels the
    /// current turn rather than submitting anything.
    var promptText: String? {
        switch self {
        case .compact: return "/compact"
        case .clear: return "/clear"
        default: return nil
        }
    }
}

enum SessionActions {
    /// Whether an action can run against this session right now, and why not.
    ///
    /// Returns the reason rather than a bare bool so the button can say it. A
    /// disabled control with no explanation is the thing that makes people click
    /// twice and assume the app is broken.
    static func unavailableReason(_ action: SessionAction,
                                  session: SessionFeed,
                                  hasPane: Bool) -> String? {
        switch action {
        case .revealCWD:
            return session.cwd.isEmpty ? "This session has no working directory yet." : nil
        case .openTranscript:
            return session.stats.transcriptPath == nil
                ? "No transcript yet — the statusLine hasn't reported." : nil
        case .copySessionID:
            return nil
        case .interrupt, .compact, .clear:
            guard hasPane else {
                return "That session isn't in a tmux pane, so there's nowhere to type."
            }
            // Interrupt is the one that is FOR a running turn; the other two
            // type at the prompt and need it free.
            if action == .interrupt {
                return session.isWorking ? nil : "Nothing is running to interrupt."
            }
            return session.isAtPrompt ? nil : "That session is mid-turn — wait for it to finish."
        }
    }

    /// Run a local action. The typed ones go through `SessionReplier` instead.
    @discardableResult
    static func runLocal(_ action: SessionAction, session: SessionFeed) -> Bool {
        switch action {
        case .revealCWD:
            guard !session.cwd.isEmpty else { return false }
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
            return true
        case .openTranscript:
            guard let path = session.stats.transcriptPath else { return false }
            return NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .copySessionID:
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(session.id, forType: .string)
        case .interrupt, .compact, .clear:
            return false
        }
    }
}
