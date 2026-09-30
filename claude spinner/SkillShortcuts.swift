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
    /// Superpowers sit in the Skills card under their own heading.
    enum Group { case skill, superpower, git }

    let name: String
    let symbol: String
    let blurb: String
    let builtIn: Bool
    var group: Group = .skill

    var id: String { name }
    var command: String { "/" + name }
    /// The chip's text: a namespaced command drops its namespace, which the
    /// heading above it already says.
    var label: String { name.split(separator: ":").last.map(String.init) ?? name }

    /// The toolbar action this chip duplicates, whose confirmation it inherits:
    /// /clear and /compact discard context whichever button types them.
    var sessionAction: SessionAction? {
        SessionAction.allCases.first { $0.promptText == command }
    }

    static let curated: [SkillShortcut] = [
        .init(name: "start-up", symbol: "sunrise", blurb: "Survey the repo and start the top task", builtIn: false),
        .init(name: "wrap-up", symbol: "moon.zzz", blurb: "Commit, update STATUS, hand off", builtIn: false),
        .init(name: "compact", symbol: SessionAction.compact.symbol, blurb: "Summarize and drop the transcript",
              builtIn: true),
        .init(name: "clear", symbol: SessionAction.clear.symbol, blurb: "Discard the conversation", builtIn: true),
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
        // The superpowers workflow, one chip per stage. Each command hands off
        // to the plugin skill, and asks what it applies to when typed bare.
        .init(name: "superpower:brainstorm", symbol: "lightbulb", blurb: "Shape an idea before building",
              builtIn: false, group: .superpower),
        .init(name: "superpower:plan", symbol: "list.number", blurb: "Spec to step-by-step plan",
              builtIn: false, group: .superpower),
        .init(name: "superpower:tdd", symbol: "checkmark.seal", blurb: "Test first, then code",
              builtIn: false, group: .superpower),
        .init(name: "superpower:debug", symbol: "ladybug", blurb: "Reproduce, isolate, fix",
              builtIn: false, group: .superpower),
        .init(name: "superpower:verify", symbol: "checkmark.shield", blurb: "Prove it works",
              builtIn: false, group: .superpower),
    ]

    /// The curated shortcuts that are installed. `exists` is injected so the
    /// filter is testable without touching the real home directory.
    static func available(claudeDir: URL,
                          exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> [SkillShortcut] {
        curated.filter { shortcut in
            // "superpower:debug" is commands/superpower/debug.md.
            let path = shortcut.name.replacingOccurrences(of: ":", with: "/")
            return shortcut.builtIn
                || exists(claudeDir.appendingPathComponent("skills/\(path)/SKILL.md").path)
                || exists(claudeDir.appendingPathComponent("commands/\(path).md").path)
        }
    }

    /// Why a git skill has nothing to act on, or nil. Same test the
    /// suggestion uses (tracked edits, unpushed commits), so an untracked-only
    /// tree reads as clean here too. An unread snapshot blocks nothing.
    static func idleReason(_ shortcut: SkillShortcut, snapshot: GitSnapshot?) -> String? {
        guard shortcut.group == .git, let snap = snapshot, !snap.isDirty else { return nil }
        switch (shortcut.name, snap.sync) {
        case ("git-push", .ahead), ("git-push", .noUpstream): return nil
        case ("git-push", _): return "Nothing to commit or push."
        case ("code-review", _) where !snap.isDefaultBranch: return nil
        case ("code-review", _): return "No changes to review."
        default: return nil
        }
    }

    /// Why a shortcut can't be typed into this session right now, or nil.
    /// Same rule as `/compact`: there has to be a pane, and the prompt has to be free.
    static func unavailableReason(session: SessionFeed, hasPane: Bool) -> String? {
        guard hasPane else { return "That session isn't in a tmux pane, so there's nowhere to type." }
        return session.isAtPrompt ? nil : "That session is mid-turn — wait for it to finish."
    }
}
