import Foundation

/// Slash commands offered as one-click shortcuts in the detail pane.
///
/// Curated rather than listed from disk: `~/.claude/skills` holds fifty-odd
/// entries, most of them agent-only or domain references, and a card of all of
/// them is a directory listing, not a shortcut. What IS read from disk is
/// whether each one is installed, so a chip never types a command that isn't
/// there. Built-ins ship with Claude Code and need no check.
struct SkillShortcut: Identifiable, Equatable {
    /// Which card it sits in: git work gets its own, beside the git actions.
    enum Group { case skill, git }

    let name: String
    let symbol: String
    let blurb: String
    let builtIn: Bool
    var group: Group = .skill

    var id: String { name }
    var command: String { "/" + name }

    static let curated: [SkillShortcut] = [
        .init(name: "start-up", symbol: "sunrise", blurb: "Survey the repo and start the top task", builtIn: false),
        .init(name: "wrap-up", symbol: "moon.zzz", blurb: "Commit, update STATUS, hand off", builtIn: false),
        .init(name: "todo", symbol: "checklist", blurb: "Turn the conversation into tasks", builtIn: false),
        .init(name: "tasks", symbol: "list.bullet.rectangle", blurb: "Re-render the task box", builtIn: false),
        .init(name: "code-review", symbol: "magnifyingglass", blurb: "Review the current diff", builtIn: true,
              group: .git),
        .init(name: "simplify", symbol: "wand.and.stars", blurb: "Clean up the changed code", builtIn: true),
        .init(name: "git-push", symbol: "arrow.up.circle", blurb: "Commit and push", builtIn: false,
              group: .git),
        .init(name: "recall", symbol: "brain", blurb: "Search past decisions", builtIn: false),
        .init(name: "goal", symbol: "flag.checkered", blurb: "Work autonomously toward a goal", builtIn: false),
        .init(name: "checkup", symbol: "stethoscope", blurb: "Health-check the Claude config", builtIn: false),
    ]

    /// The curated shortcuts that are installed. `exists` is injected so the
    /// filter is testable without touching the real home directory.
    static func available(claudeDir: URL,
                          exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> [SkillShortcut] {
        curated.filter { shortcut in
            shortcut.builtIn
                || exists(claudeDir.appendingPathComponent("skills/\(shortcut.name)/SKILL.md").path)
                || exists(claudeDir.appendingPathComponent("commands/\(shortcut.name).md").path)
        }
    }

    /// Why a shortcut can't be typed into this session right now, or nil.
    /// Same rule as `/compact`: there has to be a pane, and the prompt has to be free.
    static func unavailableReason(session: SessionFeed, hasPane: Bool) -> String? {
        guard hasPane else { return "That session isn't in a tmux pane, so there's nowhere to type." }
        return session.isAtPrompt ? nil : "That session is mid-turn — wait for it to finish."
    }
}
