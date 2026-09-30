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
    case focus
    case interrupt
    case compact
    case clear
    case revealCWD
    case openTerminal
    case copyPath
    case openTranscript
    case copySessionID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus session"
        case .interrupt: return "Interrupt"
        case .compact: return "Compact"
        case .clear: return "Clear"
        case .revealCWD: return "Reveal folder"
        case .openTerminal: return "New terminal here"
        case .copyPath: return "Copy folder path"
        case .openTranscript: return "Open transcript"
        case .copySessionID: return "Copy session id"
        }
    }

    /// The toolbar draws these as icons; the title rides along as the tooltip
    /// and the accessibility label.
    var symbol: String {
        switch self {
        case .focus: return "arrow.up.forward.app"
        case .interrupt: return "stop.circle"
        case .compact: return "arrow.down.right.and.arrow.up.left"
        case .clear: return "eraser"
        case .revealCWD: return "folder"
        case .openTerminal: return "terminal"
        case .copyPath: return "link"
        case .openTranscript: return "doc.text"
        case .copySessionID: return "doc.on.doc"
        }
    }

    /// Needs a tmux pane to type into.
    var needsPane: Bool {
        switch self {
        case .interrupt, .compact, .clear: return true
        case .focus, .revealCWD, .openTerminal, .copyPath, .openTranscript, .copySessionID: return false
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

/// Switching a session's model or effort by typing the command Claude Code
/// already has, rather than editing settings behind its back.
///
/// Typed, `/model <alias>` and `/effort <level>` also save the choice as the
/// default for new sessions, and a model switch makes the next turn re-read
/// the whole conversation uncached. Both are said in the confirmation.
enum SessionConfig {
    static let models: [(alias: String, title: String)] = [
        ("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku"), ("fable", "Fable"),
    ]
    static let efforts = ["low", "medium", "high", "xhigh", "max"]

    static func modelCommand(_ alias: String) -> String { "/model \(alias)" }
    static func effortCommand(_ level: String) -> String { "/effort \(level)" }

    /// Whether a display name such as "Opus 5.5" is the model an alias picks.
    static func isCurrent(_ alias: String, model: String?) -> Bool {
        model?.lowercased().hasPrefix(alias) == true
    }

    static func modelConfirmation(_ title: String) -> String {
        "Switch this session to \(title)? The next turn re-reads the whole conversation uncached, "
            + "and /model also saves \(title) as your default for new sessions. "
            + "Claude Code may ask you to confirm in the terminal."
    }

    static func effortConfirmation(_ level: String) -> String {
        level == "max"
            ? "Set effort to max for this session?"
            : "Set effort to \(level)? /effort also saves it as your default for this model."
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
        case .revealCWD, .openTerminal, .copyPath:
            return session.cwd.isEmpty ? "This session has no working directory yet." : nil
        case .openTranscript:
            return session.stats.transcriptPath == nil
                ? "No transcript yet — the statusLine hasn't reported." : nil
        case .focus, .copySessionID:
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
        case .focus:
            SessionLauncher.focus(host: session.host, pid: session.pid, cwd: session.cwd)
            return true
        case .revealCWD:
            guard !session.cwd.isEmpty else { return false }
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
            return true
        case .openTerminal:
            // A fresh window on purpose -- Focus is the one that finds the
            // session's own. Same terminal choice as SessionLauncher's fallback.
            guard !session.cwd.isEmpty else { return false }
            let bundleID = FileManager.default.fileExists(atPath: "/Applications/Ghostty.app")
                ? "com.mitchellh.ghostty" : "com.apple.Terminal"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-b", bundleID, session.cwd]
            return (try? task.run()) != nil
        case .copyPath:
            guard !session.cwd.isEmpty else { return false }
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(session.cwd, forType: .string)
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
