import Foundation

/// What the Mail card's "Draft replies" button starts: a new Claude session, in
/// the project the reply-drafting skill belongs to, told to use that skill.
///
/// Pure on purpose: the file system comes in as closures, so the lookups are
/// testable without the real home directory, and nothing here runs until the
/// button is pressed (the card resolves a `Plan` once when it appears, which is
/// a handful of stats, and launches nothing).
nonisolated enum DraftReplies {
    static let skillName = "response-drafter"

    /// Shown on the card, and as the button's help text, when there is no skill
    /// to point the session at.
    static let missingMessage = "response-drafter skill not found in ~/.claude/skills"

    /// Where Claude Code registers a skill synced from the account.
    static let syncedNamespace = "anthropic-skills:"

    struct Plan: Equatable {
        let directory: String
        let prompt: String
    }

    /// The `SKILL.md` for `name`: `skills/<name>/SKILL.md`, else the first
    /// `skills/synced/*/<name>/SKILL.md` in name order. Account skills live under
    /// a directory named for the account and organisation, which can change, so
    /// the directory is listed rather than named.
    static func skillPath(named name: String = skillName, claudeDir: URL,
                          exists: (String) -> Bool,
                          listDir: (String) -> [String]) -> String? {
        let plain = claudeDir.appendingPathComponent("skills/\(name)/SKILL.md").path
        if exists(plain) { return plain }
        return syncedPath(named: name, claudeDir: claudeDir, exists: exists, listDir: listDir)
    }

    /// Only the synced half of `skillPath`: what a chip needs to know to decide
    /// whether to type the namespaced command.
    static func syncedPath(named name: String, claudeDir: URL,
                           exists: (String) -> Bool,
                           listDir: (String) -> [String]) -> String? {
        let synced = claudeDir.appendingPathComponent("skills/synced")
        for entry in listDir(synced.path).sorted() {
            let path = synced.appendingPathComponent("\(entry)/\(name)/SKILL.md").path
            if exists(path) { return path }
        }
        return nil
    }

    /// The skill says it belongs to Daniel's `personal-tasks` project and reads
    /// his resume from `assets/` there. On disk that project is `life-admin`;
    /// `cowork/personal-tasks` is a symlink to it, kept as the legacy path. The
    /// session starts there when it exists, otherwise in the home directory.
    static func workingDirectory(home: String, isDirectory: (String) -> Bool) -> String {
        for name in ["life-admin", "personal-tasks"] {
            let path = home + "/cowork/" + name
            if isDirectory(path) { return path }
        }
        return home
    }

    /// One plain-text line, not a slash command: an account skill is registered
    /// as `/anthropic-skills:<name>`, and pointing at the file works either way.
    static func prompt(skillPath: String) -> String {
        "Use my \(skillName) skill (\(skillPath)) to draft replies in my voice. "
        + "Find messages from the past 7 days that need a reply from me "
        + "(recruiters, interviews, job applications) in email and LinkedIn, "
        + "show me the list first, then draft each reply. "
        + "Drafts only: do not send, submit or post anything."
    }

    /// nil when the skill isn't installed.
    static func plan(claudeDir: URL, home: String,
                     exists: (String) -> Bool,
                     listDir: (String) -> [String],
                     isDirectory: (String) -> Bool) -> Plan? {
        guard let skill = skillPath(claudeDir: claudeDir, exists: exists, listDir: listDir) else { return nil }
        return Plan(directory: workingDirectory(home: home, isDirectory: isDirectory),
                    prompt: prompt(skillPath: skill))
    }

    /// The real file system, for the card.
    static func currentPlan() -> Plan? {
        let fm = FileManager.default
        return plan(
            claudeDir: fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude"),
            home: NSHomeDirectory(),
            exists: { fm.fileExists(atPath: $0) },
            listDir: { (try? fm.contentsOfDirectory(atPath: $0)) ?? [] },
            isDirectory: {
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue
            })
    }
}
