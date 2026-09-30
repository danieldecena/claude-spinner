//
//  PinnedProjectsTests.swift
//  claude spinnerTests
//
//  The pinned project tab: which folder counts as "in" the project, how the
//  sidebar tag stays apart from session ids, and what each discovery source
//  returns for a folder that has something, has nothing, and can't be read.
//  Every source runs against a temp folder, never the real home.
//

import XCTest
@testable import claude_spinner

final class PinnedProjectsTests: XCTestCase {
    private let folder = "/Users/me/developer/job search"
    private let topic = PinnedProject.jobSearch.topic

    private func withTempDir(_ body: (String) throws -> Void) rethrows {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pinned-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        try body(dir.path)
    }

    @discardableResult
    private func write(_ text: String, to path: String, age: TimeInterval = 0) -> String {
        try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try! text.write(toFile: path, atomically: true, encoding: .utf8)
        if age != 0 {
            try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)],
                                                   ofItemAtPath: path)
        }
        return path
    }

    private func session(_ id: String, cwd: String, parent: String? = nil) -> SessionFeed {
        var s = SessionFeed(id: id)
        s.cwd = cwd
        s.parentSessionId = parent
        return s
    }

    // MARK: - Which sessions are in the folder

    func testLiveSessionsAreTheFolderAndWhatIsInsideIt() {
        let sessions = [
            session("in", cwd: "/x/job search"),
            session("deeper", cwd: "/x/job search/Resume/artifact"),
            session("cased", cwd: "/X/JOB SEARCH"),
            session("sibling", cwd: "/x/job search-foo"),
            session("prefix", cwd: "/x/job"),
            session("subagent", cwd: "/x/job search", parent: "in"),
            session("none", cwd: ""),
        ]
        XCTAssertEqual(PinnedProject.liveSessions(in: "/x/job search", sessions: sessions).map(\.id),
                       ["in", "deeper", "cased"])
        XCTAssertEqual(PinnedProject.liveSessions(in: "/x/job search/", sessions: sessions).map(\.id),
                       ["in", "deeper", "cased"], "a trailing slash on the pinned path changes nothing")
        XCTAssertEqual(PinnedProject.liveSessions(in: "/x/job search", sessions: []).count, 0)
    }

    // MARK: - Tag routing

    func testPinnedTagNeverResolvesToASession() {
        let project = PinnedProject.all[0]
        XCTAssertTrue(PinnedProject.isPinnedTag(project.tag))
        XCTAssertFalse(PinnedProject.isPinnedTag("3f2a9c1e-0000-4000-8000-000000000001"))
        XCTAssertFalse(PinnedProject.isPinnedTag(nil))
        XCTAssertEqual(PinnedProject.project(forTag: project.tag), project)
        XCTAssertNil(PinnedProject.project(forTag: "pinned:Nope"))
        XCTAssertNil(PinnedProject.project(forTag: "a"))

        let roots = [session("a", cwd: "/x")]
        // A pinned selection is no session, so the default cannot take its pane.
        XCTAssertNil(WindowContentView.resolveSelection(project.tag, roots: roots, asks: []))
        XCTAssertNil(WindowContentView.resolveSelection("pinned:Nope", roots: roots, asks: []))
        // The known-good side: everything else resolves as before.
        XCTAssertEqual(WindowContentView.resolveSelection("a", roots: roots, asks: [])?.id, "a")
        XCTAssertEqual(WindowContentView.resolveSelection(nil, roots: roots, asks: [])?.id, "a")
        XCTAssertEqual(WindowContentView.resolveSelection("gone", roots: roots, asks: [])?.id, "a")
    }

    // MARK: - Recent sessions

    func testTranscriptSlugReplacesEveryNonAlphanumeric() {
        XCTAssertEqual(ProjectDiscovery.transcriptSlug("/Users/home/developer/job search"),
                       "-Users-home-developer-job-search")
        XCTAssertEqual(ProjectDiscovery.transcriptSlug("/Users/home/.claude/a_b.c/Dev"),
                       "-Users-home--claude-a-b-c-Dev")
        XCTAssertEqual(ProjectDiscovery.transcriptSlug("/tmp/x9"), "-tmp-x9")
        XCTAssertEqual(ProjectDiscovery.transcriptSlug(""), "")
    }

    func testTranscriptDirsMatchCaseInsensitivelyAndLeaveSiblingsOut() {
        let names = ["-Users-home-developer-job-search", "-Users-home-Developer-job-search",
                     "-Users-home-developer-job-search--worktrees-daily",
                     "-Users-home-developer-job-search-foo", "-Users-home-developer-other"]
        XCTAssertEqual(ProjectDiscovery.transcriptDirs(matching: "-Users-home-developer-job-search", among: names),
                       ["-Users-home-developer-job-search", "-Users-home-Developer-job-search"])
        XCTAssertEqual(ProjectDiscovery.transcriptDirs(matching: "-nothing", among: names), [])
    }

    func testNewestKeepsOnePerSessionNewestFirstWithoutLiveOnes() {
        func file(_ id: String, _ age: TimeInterval, dir: String = "a") -> TranscriptFile {
            TranscriptFile(id: id, path: "/\(dir)/\(id).jsonl", modified: Date(timeIntervalSinceNow: -age))
        }
        let files = [file("old", 900), file("new", 10), file("dup", 500, dir: "a"), file("dup", 50, dir: "b"),
                     file("live", 1), file("mid", 100)]
        let picked = ProjectDiscovery.newest(files, excluding: ["LIVE"], limit: 3)
        XCTAssertEqual(picked.map(\.id), ["new", "dup", "mid"])
        XCTAssertEqual(picked[1].path, "/b/dup.jsonl", "the newer copy of a merged session wins")
        XCTAssertEqual(ProjectDiscovery.newest(files, excluding: [], limit: 20).count, 5)
        XCTAssertEqual(ProjectDiscovery.newest([], excluding: [], limit: 8), [])
    }

    func testTranscriptsListsOnlyNonEmptyUUIDFiles() {
        withTempDir { root in
            let slug = "-x-job-search"
            let good = "0019742F-6C83-4EE0-B787-9364F9D5299E"
            let other = "001c1562-6910-4e63-9bce-a8df14932b0b"
            write("{}\n", to: "\(root)/\(slug)/\(good).jsonl", age: 100)
            write("{}\n", to: "\(root)/\(slug)/\(other).jsonl", age: 10)
            write("", to: "\(root)/\(slug)/3f2a9c1e-0000-4000-8000-000000000001.jsonl")
            write("{}\n", to: "\(root)/\(slug)/agent-abc123.jsonl")
            write("{}\n", to: "\(root)/\(slug)/\(other).txt")
            write("{}\n", to: "\(root)/\(slug)--worktrees-daily/3f2a9c1e-0000-4000-8000-000000000002.jsonl")

            let found = ProjectDiscovery.transcripts(slug: slug, projectsDir: root)
            XCTAssertEqual(found.items.map(\.id).sorted(), [good.lowercased(), other].sorted())
            XCTAssertTrue(found.unreadable.isEmpty)

            let none = ProjectDiscovery.transcripts(slug: "-nothing-here", projectsDir: root)
            XCTAssertTrue(none.isEmpty, "no folder for the project is empty, not an error")
        }
    }

    func testTranscriptsTellUnreadableFromEmpty() {
        withTempDir { root in
            let file = write("x", to: "\(root)/not-a-folder")
            let bad = ProjectDiscovery.transcripts(slug: "-x", projectsDir: file)
            XCTAssertEqual(bad.unreadable, [file])
            XCTAssertTrue(bad.items.isEmpty)

            let locked = "\(root)/-x"
            try! FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: true)
            try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked) }
            XCTAssertEqual(ProjectDiscovery.transcripts(slug: "-x", projectsDir: root).unreadable, [locked])
        }
    }

    /// Headless and Claude Desktop sessions are skipped before the limit, so a
    /// pile of them cannot push the real sessions off the list. Both directions
    /// are covered: those files are dropped, and a terminal one and one with no
    /// `entrypoint` stay.
    /// The card's description is the note's first sentence without its
    /// "<title> =" lead-in; a missing or blank note gives nothing to show.
    func testArtifactSummaryIsTheNotesFirstSentence() {
        let note = "Career Hub = Front prep sheet + Applications tab, merged 2026-09-28. Data refresh only: run it."
        XCTAssertEqual(ProjectArtifact.summary(fromNote: note, title: "Career Hub"),
                       "Front prep sheet + Applications tab, merged 2026-09-28")
        XCTAssertEqual(ProjectArtifact.summary(fromNote: "A board of openings.", title: "Board"), "A board of openings")
        XCTAssertNil(ProjectArtifact.summary(fromNote: nil, title: "X"))
        XCTAssertNil(ProjectArtifact.summary(fromNote: "   ", title: "X"))
    }

    func testRecentSessionsSkipHeadlessAndDesktopRuns() {
        withTempDir { root in
            let slug = ProjectDiscovery.transcriptSlug("/x/job search")
            let real = "bbbbbbbb-0000-4000-8000-000000000001"
            let unlabelled = "bbbbbbbb-0000-4000-8000-000000000002"
            write(#"{"type":"user","entrypoint":"cli"}"#, to: "\(root)/\(slug)/\(real).jsonl", age: 90)
            write(#"{"type":"user"}"#, to: "\(root)/\(slug)/\(unlabelled).jsonl", age: 80)
            var headless: [String] = []
            for n in 0..<10 {
                let id = String(format: "bbbbbbbb-0000-4000-8000-0000000001%02d", n)
                headless.append(id)
                write(#"{"type":"queue-operation"}"# + "\n" + #"{"type":"user","entrypoint":"sdk-cli"}"#,
                      to: "\(root)/\(slug)/\(id).jsonl", age: TimeInterval(n + 1))
            }
            let desktop = "bbbbbbbb-0000-4000-8000-000000000003"
            write(#"{"type":"user","entrypoint":"claude-desktop"}"#, to: "\(root)/\(slug)/\(desktop).jsonl", age: 5)
            XCTAssertFalse(ProjectDiscovery.ranInTerminal(path: "\(root)/\(slug)/\(headless[0]).jsonl"))
            XCTAssertFalse(ProjectDiscovery.ranInTerminal(path: "\(root)/\(slug)/\(desktop).jsonl"))
            XCTAssertTrue(ProjectDiscovery.ranInTerminal(path: "\(root)/\(slug)/\(real).jsonl"))
            XCTAssertTrue(ProjectDiscovery.ranInTerminal(path: "\(root)/\(slug)/\(unlabelled).jsonl"))
            XCTAssertTrue(ProjectDiscovery.ranInTerminal(path: "\(root)/nope.jsonl"),
                          "an unreadable file is kept: not knowing is not the same as headless")

            let found = ProjectDiscovery.recentSessions(folder: "/x/job search", projectsDir: root,
                                                         excluding: [], limit: 3)
            XCTAssertEqual(found.items.map(\.id), [unlabelled, real],
                           "ten newer headless runs must not crowd out the two real sessions")
        }
    }

    func testRecentSessionsAreSummarisedFromTheTranscriptTail() {
        withTempDir { root in
            let slug = ProjectDiscovery.transcriptSlug("/x/job search")
            let titled = "aaaaaaaa-0000-4000-8000-000000000001"
            let prompted = "aaaaaaaa-0000-4000-8000-000000000002"
            let blank = "aaaaaaaa-0000-4000-8000-000000000003"
            write(#"{"type":"ai-title","aiTitle":"Fix the scout cooldown"}"# + "\n"
                  + #"{"type":"last-prompt","lastPrompt":"run it"}"#,
                  to: "\(root)/\(slug)/\(titled).jsonl", age: 30)
            write(#"{"type":"last-prompt","lastPrompt":"\n  apply to the Stripe role\nthen log it"}"#,
                  to: "\(root)/\(slug)/\(prompted).jsonl", age: 20)
            write(#"{"type":"user"}"#, to: "\(root)/\(slug)/\(blank).jsonl", age: 10)

            let found = ProjectDiscovery.recentSessions(folder: "/x/job search", projectsDir: root, excluding: [blank])
            XCTAssertEqual(found.items.map(\.id), [prompted, titled])
            XCTAssertEqual(found.items.map(\.headline), ["apply to the Stripe role", "Fix the scout cooldown"])

            let all = ProjectDiscovery.recentSessions(folder: "/x/job search", projectsDir: root, excluding: [])
            XCTAssertEqual(all.items.first?.headline, "Untitled session")
        }
    }

    // MARK: - Skills

    func testSkillsListTheFoldersOwnAndTheUserOnesAboutThisWork() {
        withTempDir { root in
            let project = "\(root)/proj", claude = "\(root)/claude"
            write("---\nname: JobScout\ndescription: run the pipeline\n---\nbody", to: "\(project)/.claude/skills/JobScout/SKILL.md")
            write("no frontmatter", to: "\(project)/.claude/skills/bare/SKILL.md")
            write("x", to: "\(project)/.claude/skills/PROJECT_WORKFLOW.md")
            write("---\nname: about-jobs\ndescription: >\n  Use for the job search queue\n---\n", to: "\(claude)/skills/about-jobs/SKILL.md")
            write("---\nname: apply-helper\ndescription: fills forms\n---\n", to: "\(claude)/skills/apply-helper/SKILL.md")
            write("---\nname: git-push\ndescription: push\n---\nApply the change to the job search repo", to: "\(claude)/skills/git-push/SKILL.md")
            write("---\nname: JobScout\ndescription: job search duplicate\n---\n", to: "\(claude)/skills/JobScoutCopy/SKILL.md")

            let found = ProjectDiscovery.skills(projectRoot: project, claudeDir: claude, topic: topic)
            XCTAssertEqual(found.items, [ProjectSkill(name: "JobScout", isProject: true),
                                         ProjectSkill(name: "bare", isProject: true),
                                         ProjectSkill(name: "about-jobs", isProject: false),
                                         ProjectSkill(name: "apply-helper", isProject: false)])
            XCTAssertTrue(found.unreadable.isEmpty)
        }
    }

    func testSkillsEmptyAndUnreadable() {
        withTempDir { root in
            write("---\nname: git-push\n---\napply job search", to: "\(root)/claude/skills/git-push/SKILL.md")
            XCTAssertTrue(ProjectDiscovery.skills(projectRoot: "\(root)/proj", claudeDir: "\(root)/claude", topic: topic).isEmpty)

            let file = write("x", to: "\(root)/proj/.claude/skills")
            let found = ProjectDiscovery.skills(projectRoot: "\(root)/proj", claudeDir: "\(root)/claude", topic: topic)
            XCTAssertEqual(found.unreadable, [file])
            XCTAssertTrue(found.items.isEmpty)
        }
    }

    func testSkillsIncludeDesktopPluginSkillsOnceUnderTheirSlashName() {
        withTempDir { root in
            let plugins = "\(root)/plugins"
            for space in ["acct1/space", "acct2/space"] {
                write(#"{"name": "anthropic-skills"}"#, to: "\(plugins)/\(space)/.claude-plugin/plugin.json")
                write("---\nname: \"apply-next-job\"\ndescription: submit one\n---\n",
                      to: "\(plugins)/\(space)/skills/apply-next-job/SKILL.md")
                write("---\nname: linkedin-job-list\ndescription: list LinkedIn jobs\n---\n",
                      to: "\(plugins)/\(space)/skills/linkedin-job-list/SKILL.md")
                write("---\nname: pdf\ndescription: read PDFs\n---\n", to: "\(plugins)/\(space)/skills/pdf/SKILL.md")
            }
            let found = ProjectDiscovery.skills(projectRoot: "\(root)/proj", claudeDir: "\(root)/claude",
                                                pluginsDir: plugins, topic: topic)
            XCTAssertEqual(found.items.map(\.command),
                           ["/anthropic-skills:apply-next-job", "/anthropic-skills:linkedin-job-list"])
            XCTAssertTrue(found.unreadable.isEmpty)

            let none = ProjectDiscovery.skills(projectRoot: "\(root)/proj", claudeDir: "\(root)/claude",
                                               pluginsDir: "\(root)/no-desktop", topic: topic)
            XCTAssertTrue(none.items.isEmpty)
            XCTAssertFalse(none.unreadable.contains("\(root)/no-desktop"))
        }
    }

    func testPlansIsPinnedWithItsOwnTopicAndNoQuickStart() {
        let plans = PinnedProject.project(forTag: PinnedProject.plans.tag)
        XCTAssertEqual(plans?.path, NSHomeDirectory() + "/developer/_project-knowledge")
        XCTAssertNil(plans?.quickStart)
        XCTAssertNotNil(PinnedProject.jobSearch.quickStart)
        withTempDir { root in
            write("---\nname: resync\ndescription: re-index _project-knowledge\n---\n", to: "\(root)/claude/skills/resync/SKILL.md")
            write("---\nname: about-jobs\ndescription: the job search queue\n---\n", to: "\(root)/claude/skills/about-jobs/SKILL.md")
            let found = ProjectDiscovery.skills(projectRoot: "\(root)/proj", claudeDir: "\(root)/claude", topic: PinnedProject.plans.topic)
            XCTAssertEqual(found.items.map(\.name), ["resync"])
        }
        XCTAssertFalse(ProjectDiscovery.mentionsProject("com.me.job-sync", folder: "/x/_project-knowledge",
                                                        topic: PinnedProject.plans.topic))
    }

    func testAboutFindsInstructionsAndCountsMemories() {
        withTempDir { root in
            let project = "\(root)/my proj", projects = "\(root)/projects"
            write("x", to: "\(project)/PROJECT-INSTRUCTIONS.md")
            let memory = "\(projects)/\(ProjectDiscovery.transcriptSlug(project))/memory"
            write("index", to: "\(memory)/MEMORY.md")
            write("a", to: "\(memory)/one.md")
            write("b", to: "\(memory)/two.md")
            let about = ProjectDiscovery.about(root: project, projectsDir: projects)
            XCTAssertEqual(about.instructions, ["\(project)/PROJECT-INSTRUCTIONS.md"])
            XCTAssertEqual(about.memoryDir, memory)
            XCTAssertEqual(about.memories, 2)

            let bare = ProjectDiscovery.about(root: "\(root)/other", projectsDir: projects)
            XCTAssertEqual(bare.instructions, [])
            XCTAssertEqual(bare.memories, 0)
        }
    }

    /// Desktop's session record, in its real shape: the newest entry holding
    /// the root gives the project's folders, root first.
    func testLinkedFoldersComeFromTheNewestDesktopSessionHoldingTheRoot() {
        withTempDir { root in
            let spaces = "\(root)/remote-session-spaces.json"
            write(#"""
            {"entries": [
              {"sessionId": "a", "folders": ["/p/job search"]},
              {"sessionId": "b", "folders": ["/p/job search/Resume/artifact", "/p/job search"], "memoryEnabled": false},
              {"sessionId": "c", "folders": ["/p/other"]}
            ]}
            """#, to: spaces)
            XCTAssertEqual(ProjectDiscovery.desktopFolders(root: "/p/job search", spacesFiles: [spaces]).items,
                           ["/p/job search", "/p/job search/Resume/artifact"])
            XCTAssertEqual(ProjectDiscovery.desktopFolders(root: "/p/none", spacesFiles: [spaces]).items, ["/p/none"],
                           "no record: just the root")
            let missing = ProjectDiscovery.desktopFolders(root: "/p/x", spacesFiles: ["\(root)/missing.json"])
            XCTAssertEqual(missing, Found(items: ["/p/x"]), "a missing record is normal, not unreadable")
        }
    }

    func testLinkedFoldersPreferTheNewestFileAndReportOneThatWontParse() {
        withTempDir { root in
            let older = "\(root)/a/remote-session-spaces.json", newer = "\(root)/b/remote-session-spaces.json"
            let broken = "\(root)/c/remote-session-spaces.json"
            write(#"{"entries": [{"folders": ["/p/j", "/p/j/new"]}]}"#, to: newer)
            write(#"{"entries": [{"folders": ["/p/j", "/p/j/old"]}]}"#, to: older)
            write("{not json", to: broken)
            try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)],
                                                   ofItemAtPath: older)
            // The newer file is listed first: directory order must not decide.
            let found = ProjectDiscovery.desktopFolders(root: "/p/j", spacesFiles: [newer, older, broken])
            XCTAssertEqual(found.items, ["/p/j", "/p/j/new"])
            XCTAssertEqual(found.unreadable, [broken])
        }
    }

    func testTopicWordsMatchOnlyWhereAWordStarts() {
        let topic = PinnedProject.jobSearch.topic
        for hit in ["com.me.jobscout-control", "run-jobs.sh", "career-sync"] {
            XCTAssertTrue(ProjectDiscovery.mentionsProject(hit, folder: "/x/job search", topic: topic), hit)
        }
        for miss in ["com.me.cronjob", "boyscout-alerts", "com.apple.backup"] {
            XCTAssertFalse(ProjectDiscovery.mentionsProject(miss, folder: "/x/job search", topic: topic), miss)
        }
    }

    func testContextListsTheDocsPresentInTheRoot() {
        withTempDir { root in
            write("s", to: "\(root)/STATUS.md")
            write("t", to: "\(root)/TASKS.md")
            let about = ProjectDiscovery.about(root: root, projectsDir: "\(root)/projects")
            XCTAssertEqual(about.context, ["\(root)/STATUS.md", "\(root)/TASKS.md"])
            XCTAssertEqual(about.folders, [root])
        }
    }

    // MARK: - Scheduled

    func testScheduleWording() {
        XCTAssertEqual(ProjectDiscovery.cronSchedule("0 8 * * 1"), "Mon 08:00")
        XCTAssertEqual(ProjectDiscovery.cronSchedule("30 6 * * *"), "daily 06:30")
        XCTAssertEqual(ProjectDiscovery.cronSchedule("0 10 28 * *"), "day 28 10:00")
        XCTAssertEqual(ProjectDiscovery.cronSchedule("*/5 * * * *"), "cron */5 * * * *")
        XCTAssertEqual(ProjectDiscovery.launchdSchedule(["StartCalendarInterval": ["Hour": 9, "Minute": 5]]), "daily 09:05")
        XCTAssertEqual(ProjectDiscovery.launchdSchedule(["StartCalendarInterval": [["Weekday": 5, "Hour": 17], ["Weekday": 0, "Hour": 8]]]),
                       "Fri 17:00, Sun 08:00")
        XCTAssertEqual(ProjectDiscovery.launchdSchedule(["StartInterval": 300]), "every 5 min")
        XCTAssertEqual(ProjectDiscovery.launchdSchedule(["StartInterval": 90]), "every 90s")
        XCTAssertEqual(ProjectDiscovery.launchdSchedule(["RunAtLoad": true]), "at login")
        XCTAssertEqual(ProjectDiscovery.launchdSchedule([:]), "on demand")
    }

    private func plist(_ dict: [String: Any], to path: String) {
        try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            .write(to: URL(fileURLWithPath: path))
    }

    func testLaunchdJobsThatBelongToTheProject() {
        withTempDir { agents in
            plist(["Label": "com.me.nightly", "ProgramArguments": ["/bin/sh", "-c", "cd '\(folder)' && make run"],
                   "StartCalendarInterval": ["Hour": 3, "Minute": 30]], to: "\(agents)/a.plist")
            plist(["Label": "com.me.CareerSync", "StartInterval": 3600], to: "\(agents)/b.plist")
            plist(["Label": "com.me.backup", "ProgramArguments": ["/bin/backup"], "RunAtLoad": true], to: "\(agents)/c.plist")
            write("ignored", to: "\(agents)/disabled/d.plist.off")

            let found = ProjectDiscovery.launchdJobs(agentsDir: agents, folder: folder, topic: topic)
            XCTAssertEqual(found.items.map(\.name), ["com.me.nightly", "com.me.CareerSync"])
            XCTAssertEqual(found.items.map(\.schedule), ["daily 03:30", "every 1 h"])
            XCTAssertTrue(found.unreadable.isEmpty)
        }
    }

    func testLaunchdEmptyAndUnreadable() {
        withTempDir { agents in
            plist(["Label": "com.me.backup", "ProgramArguments": ["/bin/backup"]], to: "\(agents)/c.plist")
            XCTAssertTrue(ProjectDiscovery.launchdJobs(agentsDir: agents, folder: folder, topic: topic).isEmpty)
            XCTAssertTrue(ProjectDiscovery.launchdJobs(agentsDir: agents + "/missing", folder: folder, topic: topic).isEmpty)

            let broken = write("not a plist", to: "\(agents)/broken.plist")
            let found = ProjectDiscovery.launchdJobs(agentsDir: agents, folder: folder, topic: topic)
            XCTAssertEqual(found.unreadable, [broken], "a plist that won't parse can't be ruled out")
        }
    }

    func testCronLinesForTheProject() {
        let tab = """
        # a comment about job search
        PATH=/usr/bin:/job
        0 8 * * 1 cd '\(folder)' && ./run.sh
        @daily /Users/me/bin/scout-refresh
        15\t2 * * *\t/Users/me/bin/job-sync
        30 3 * * * /usr/bin/true
        """
        let found = ProjectDiscovery.cronJobs(crontab: tab, folder: folder, topic: topic)
        XCTAssertEqual(found.items.map(\.schedule), ["Mon 08:00", "@daily", "daily 02:15"])
        XCTAssertEqual(found.items.first?.name, "cd '\(folder)' && ./run.sh")
        XCTAssertTrue(found.unreadable.isEmpty)

        XCTAssertTrue(ProjectDiscovery.cronJobs(crontab: "", folder: folder, topic: topic).isEmpty)
        XCTAssertTrue(ProjectDiscovery.cronJobs(crontab: "PATH=/usr/bin\n0 1 * * * /usr/bin/true\n", folder: folder, topic: topic).isEmpty)
        XCTAssertEqual(ProjectDiscovery.cronJobs(crontab: "0 1 job-line\n", folder: folder, topic: topic).unreadable.count, 1)
    }

    func testDesktopTasksForTheProject() {
        withTempDir { base in
            func tasks(_ items: [[String: Any]]) -> String {
                String(decoding: try! JSONSerialization.data(withJSONObject: ["scheduledTasks": items]), as: UTF8.self)
            }
            write(tasks([["id": "job-app-sync", "enabled": false],
                         ["id": "email-digest", "displayName": "Email Digest", "cronExpression": "0 8 * * 1"],
                         ["id": "elsewhere", "cwd": "\(folder)/Resume", "cronExpression": "0 9 * * *", "enabled": true]]),
                  to: "\(base)/claude-code-sessions/acct/space/scheduled-tasks.json")
            write(tasks([["id": "job-app-sync", "enabled": true]]),
                  to: "\(base)/local-agent-mode-sessions/acct/space/scheduled-tasks.json")
            write(tasks([["id": "too-deep", "cwd": folder]]),
                  to: "\(base)/claude-code-sessions/a/b/c/scheduled-tasks.json")
            write(tasks([["id": "browser-cache", "cwd": folder]]),
                  to: "\(base)/Cache/x/y/scheduled-tasks.json")

            let found = ProjectDiscovery.desktopTasks(base: base, folder: folder, topic: topic)
            XCTAssertEqual(found.items.map(\.name).sorted(), ["elsewhere", "job-app-sync"])
            let elsewhere = found.items.first { $0.name == "elsewhere" }
            XCTAssertEqual(elsewhere?.schedule, "daily 09:00")
            XCTAssertEqual(elsewhere?.enabled, true)
            XCTAssertEqual(found.items.first { $0.name == "job-app-sync" }?.schedule, "no schedule recorded")
            XCTAssertTrue(found.unreadable.isEmpty)
        }
    }

    func testDesktopTasksEmptyAndUnreadable() {
        withTempDir { base in
            XCTAssertTrue(ProjectDiscovery.desktopTasks(base: base + "/missing", folder: folder, topic: topic).isEmpty)
            write(#"{"scheduledTasks":[]}"#, to: "\(base)/claude-code-sessions/acct/space/scheduled-tasks.json")
            XCTAssertTrue(ProjectDiscovery.desktopTasks(base: base, folder: folder, topic: topic).isEmpty)

            let bad = write("{ nope", to: "\(base)/claude-code-sessions/acct/other/scheduled-tasks.json")
            XCTAssertEqual(ProjectDiscovery.desktopTasks(base: base, folder: folder, topic: topic).unreadable, [bad])
        }
    }

    // MARK: - Workflows

    func testWorkflowsAreTheFoldersOwnPlusUserOnesThatMentionIt() {
        withTempDir { root in
            let project = "\(root)/proj", user = "\(root)/user"
            write("// anything", to: "\(project)/.claude/workflows/own.js")
            write("x", to: "\(project)/.claude/workflows/notes.md")
            write("// scouts the Job Search hub", to: "\(user)/uses-it.js")
            write("// JobScout", to: "\(user)/also.js")
            write("// lean research", to: "\(user)/lean-research.js")

            let found = ProjectDiscovery.workflows(projectRoot: project, userDir: user, topic: topic)
            XCTAssertEqual(found.items.map(\.name), ["own", "also", "uses-it"])
            XCTAssertTrue(found.unreadable.isEmpty)
        }
    }

    func testWorkflowsEmptyAndUnreadable() {
        withTempDir { root in
            write("// lean research", to: "\(root)/user/lean-research.js")
            XCTAssertTrue(ProjectDiscovery.workflows(projectRoot: "\(root)/proj", userDir: "\(root)/user", topic: topic).isEmpty)

            let file = write("x", to: "\(root)/proj/.claude/workflows")
            let found = ProjectDiscovery.workflows(projectRoot: "\(root)/proj", userDir: "\(root)/user", topic: topic)
            XCTAssertEqual(found.unreadable, [file])
            XCTAssertTrue(found.items.isEmpty)
        }
    }

    // MARK: - Artifacts

    func testArtifactsRecordedInTheFolder() {
        withTempDir { root in
            write(#"{"url":"https://claude.ai/artifact/abc","title":"Career Hub","note":"n"}"#,
                  to: "\(root)/docs/artifacts/artifact.json")
            write(#"{"url":"https://claude.ai/code/artifact/def"}"#, to: "\(root)/tools/board/artifact.json")
            write(#"{"url":"https://claude.ai/artifact/skipped"}"#, to: "\(root)/.worktrees/x/artifact.json")
            write(#"{"url":"https://claude.ai/artifact/skipped"}"#, to: "\(root)/node_modules/p/artifact.json")
            write(#"{"url":"https://claude.ai/artifact/too-deep"}"#, to: "\(root)/a/b/c/d/e/artifact.json")
            write(#"{"url":"https://claude.ai/artifact/edge"}"#, to: "\(root)/a/b/c/artifact.json")

            let found = ProjectDiscovery.artifacts(root: root)
            XCTAssertEqual(found.items.map(\.url).sorted(),
                           ["https://claude.ai/artifact/abc", "https://claude.ai/artifact/edge",
                            "https://claude.ai/code/artifact/def"])
            XCTAssertEqual(found.items.first { $0.url.hasSuffix("abc") }?.title, "Career Hub")
            XCTAssertEqual(found.items.first { $0.url.hasSuffix("def") }?.title, "board", "no title falls back to its folder")
            XCTAssertTrue(found.unreadable.isEmpty)
        }
    }

    func testArtifactsEmptyAndUnreadable() {
        withTempDir { root in
            write("{}", to: "\(root)/notes/other.json")
            XCTAssertTrue(ProjectDiscovery.artifacts(root: root).isEmpty)
            XCTAssertTrue(ProjectDiscovery.artifacts(root: root + "/missing").isEmpty)

            let noURL = write(#"{"title":"x"}"#, to: "\(root)/a/artifact.json")
            let badJSON = write("{ nope", to: "\(root)/b/artifact.json")
            let notWeb = write(#"{"url":"file:///etc/passwd"}"#, to: "\(root)/c/artifact.json")
            let found = ProjectDiscovery.artifacts(root: root)
            XCTAssertTrue(found.items.isEmpty)
            XCTAssertEqual(found.unreadable.sorted(), [noURL, badJSON, notWeb].sorted())
        }
        withTempDir { root in
            let locked = "\(root)/private"
            try! FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: true)
            try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked) }
            write(#"{"url":"https://claude.ai/artifact/ok"}"#, to: "\(root)/docs/artifact.json")
            let found = ProjectDiscovery.artifacts(root: root)
            XCTAssertEqual(found.items.count, 1, "a folder that won't list doesn't hide the ones that do")
            XCTAssertEqual(found.unreadable, [locked])
        }
    }
}
