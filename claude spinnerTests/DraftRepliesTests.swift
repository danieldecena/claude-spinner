//
//  DraftRepliesTests.swift
//  claude spinnerTests
//
//  The Mail card's "Draft replies" button: finding the response-drafter skill
//  (a plain skill, or one synced from the account), choosing the session's
//  working directory, the starting prompt, and the synced-skill chips. The file
//  system is injected as closures over made-up paths; nothing here reads the
//  real home directory or opens a window.
//

import XCTest
@testable import claude_spinner

final class DraftRepliesTests: XCTestCase {

    private let claude = URL(fileURLWithPath: "/c")

    private func list(_ dirs: [String: [String]]) -> (String) -> [String] {
        { dirs[$0] ?? [] }
    }

    // MARK: - Finding the skill

    func testSkillFoundInPlainSkillsDirectory() {
        let installed: Set<String> = ["/c/skills/response-drafter/SKILL.md"]
        XCTAssertEqual(DraftReplies.skillPath(claudeDir: claude, exists: installed.contains, listDir: list([:])),
                       "/c/skills/response-drafter/SKILL.md")
    }

    func testSkillFoundInSyncedDirectory() {
        let installed: Set<String> = ["/c/skills/synced/id-b/response-drafter/SKILL.md"]
        let dirs = ["/c/skills/synced": ["id-a", "id-b"]]
        XCTAssertEqual(DraftReplies.skillPath(claudeDir: claude, exists: installed.contains, listDir: list(dirs)),
                       "/c/skills/synced/id-b/response-drafter/SKILL.md")
    }

    func testPlainSkillBeatsSyncedAndFirstSyncedWinsInNameOrder() {
        let dirs = ["/c/skills/synced": ["id-b", "id-a"]]
        let both: Set<String> = ["/c/skills/response-drafter/SKILL.md",
                                 "/c/skills/synced/id-a/response-drafter/SKILL.md",
                                 "/c/skills/synced/id-b/response-drafter/SKILL.md"]
        XCTAssertEqual(DraftReplies.skillPath(claudeDir: claude, exists: both.contains, listDir: list(dirs)),
                       "/c/skills/response-drafter/SKILL.md")
        let synced = both.subtracting(["/c/skills/response-drafter/SKILL.md"])
        XCTAssertEqual(DraftReplies.skillPath(claudeDir: claude, exists: synced.contains, listDir: list(dirs)),
                       "/c/skills/synced/id-a/response-drafter/SKILL.md")
    }

    func testSkillMissingIsNil() {
        // A synced directory that exists but holds other skills only.
        let installed: Set<String> = ["/c/skills/synced/id-a/pdf/SKILL.md"]
        let dirs = ["/c/skills/synced": ["id-a"]]
        XCTAssertNil(DraftReplies.skillPath(claudeDir: claude, exists: installed.contains, listDir: list(dirs)))
        XCTAssertNil(DraftReplies.skillPath(claudeDir: claude, exists: { _ in false }, listDir: list([:])))
    }

    // MARK: - Working directory

    func testWorkingDirectoryPrefersLifeAdminThenPersonalTasksThenHome() {
        let both: Set<String> = ["/h/cowork/life-admin", "/h/cowork/personal-tasks"]
        XCTAssertEqual(DraftReplies.workingDirectory(home: "/h", isDirectory: both.contains),
                       "/h/cowork/life-admin")
        let old: Set<String> = ["/h/cowork/personal-tasks"]
        XCTAssertEqual(DraftReplies.workingDirectory(home: "/h", isDirectory: old.contains),
                       "/h/cowork/personal-tasks")
        XCTAssertEqual(DraftReplies.workingDirectory(home: "/h", isDirectory: { _ in false }), "/h")
    }

    // MARK: - Prompt

    func testPromptNamesTheSkillAndSaysDraftsOnly() {
        let prompt = DraftReplies.prompt(skillPath: "/c/skills/response-drafter/SKILL.md")
        XCTAssertTrue(prompt.contains("/c/skills/response-drafter/SKILL.md"))
        XCTAssertTrue(prompt.contains("response-drafter"))
        XCTAssertTrue(prompt.contains("Drafts only"))
        XCTAssertTrue(prompt.contains("past 7 days"))
        // Plain text for the model, not a slash command: a synced skill may not be
        // registered under its bare name.
        XCTAssertFalse(prompt.hasPrefix("/"))
        XCTAssertFalse(prompt.contains("\n"))
    }

    func testPlanNeedsTheSkillAndCarriesDirectoryAndPrompt() {
        XCTAssertNil(DraftReplies.plan(claudeDir: claude, home: "/h", exists: { _ in false },
                                       listDir: list([:]), isDirectory: { _ in true }))
        let installed: Set<String> = ["/c/skills/response-drafter/SKILL.md"]
        let plan = DraftReplies.plan(claudeDir: claude, home: "/h", exists: installed.contains,
                                     listDir: list([:]), isDirectory: { $0 == "/h/cowork/life-admin" })
        XCTAssertEqual(plan?.directory, "/h/cowork/life-admin")
        XCTAssertEqual(plan?.prompt, DraftReplies.prompt(skillPath: "/c/skills/response-drafter/SKILL.md"))
    }

    /// A path with every character that breaks a naive quote still reaches
    /// `claude` as one argument, through the same command and script the sidebar
    /// "+" uses.
    func testPromptSurvivesShellAndAppleScriptQuoting() throws {
        let prompt = DraftReplies.prompt(skillPath: #"/c/it's a "odd" $HOME `x` \path/SKILL.md"#)
        let command = NewSession.command(claudeArgs: [prompt])
        let prefix = "/bin/zsh -lic "
        XCTAssertTrue(command.hasPrefix(prefix))
        let line = String(command.dropFirst(prefix.count))
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", "claude() { for a in \"$@\"; do printf '[%s]' \"$a\"; done; }; eval \(line)"]
        let out = Pipe()
        sh.standardOutput = out
        try sh.run()
        sh.waitUntilExit()
        XCTAssertEqual(String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
                       "[\(prompt)]")

        let script = NewSession.appleScript(for: "/h/cowork/life-admin", claudeArgs: [prompt])
        XCTAssertTrue(script.contains(#"set initial working directory of cfg to "/h/cowork/life-admin""#))
        // The odd characters are escaped for AppleScript, so the string literal
        // that carries the command is not ended early.
        XCTAssertTrue(script.contains(#"\"odd\""#), script)
        XCTAssertFalse(script.contains(#" "odd" "#), script)
    }

    // MARK: - Chips for synced skills

    /// Claude Code lists an account skill as `anthropic-skills:<name>`, so that is
    /// what the chip has to type; the label still reads as the bare name.
    func testSyncedSkillsGetNamespacedChips() {
        let installed: Set<String> = ["/c/skills/synced/id-a/response-drafter/SKILL.md",
                                      "/c/skills/synced/id-a/recruiter-mail/SKILL.md"]
        let dirs = ["/c/skills/synced": ["id-a"]]
        let found = SkillShortcut.available(claudeDir: claude, exists: installed.contains, listDir: list(dirs))
        let drafter = found.first { $0.label == "response-drafter" }
        XCTAssertEqual(drafter?.command, "/anthropic-skills:response-drafter")
        XCTAssertEqual(drafter?.symbol, "square.and.pencil")
        XCTAssertEqual(found.first { $0.label == "recruiter-mail" }?.command, "/anthropic-skills:recruiter-mail")
    }

    func testSyncedChipsAbsentWhenNotInstalledAndPlainSkillKeepsItsName() {
        let none = SkillShortcut.available(claudeDir: claude, exists: { _ in false }, listDir: list([:]))
        XCTAssertFalse(none.contains { $0.label == "response-drafter" })
        let plain: Set<String> = ["/c/skills/response-drafter/SKILL.md"]
        let found = SkillShortcut.available(claudeDir: claude, exists: plain.contains, listDir: list([:]))
        XCTAssertEqual(found.first { $0.label == "response-drafter" }?.command, "/response-drafter")
    }
}
