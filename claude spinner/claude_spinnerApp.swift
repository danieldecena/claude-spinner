//
//  claude_spinnerApp.swift
//  claude spinner
//
//  Menubar mirror of the live Claude Code session feed.
//

import SwiftUI
import AppKit
import UserNotifications

@main
struct claude_spinnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No SwiftUI window/scene: the menu bar item and its popover are owned by
        // AppDelegate. Settings gives the App a valid (empty) scene body.
        Settings { EmptyView() }
    }
}

/// Owns the status-bar item and the popover anchored beneath it. Using
/// NSStatusItem + NSPopover (instead of SwiftUI's MenuBarExtra) lets the panel
/// sit flush under the icon with a pointer arrow, rather than floating detached.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let feed = FeedWatcher()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: a second copy exits immediately.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            exit(0)
        }
        NSApp.setActivationPolicy(.accessory)

        // Ask once for notification permission (used for attention alerts), and
        // register the "Focus session" action so its button appears on the alert.
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let focus = UNNotificationAction(identifier: NotificationConfig.focusAction,
                                         title: "Focus session", options: [.foreground])
        let category = UNNotificationCategory(identifier: NotificationConfig.attentionCategory,
                                              actions: [focus], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuContentView(feed: feed))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let host = NSHostingView(rootView: MenuBarLabel(feed: feed))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Left-click toggles the panel; right-click shows the settings menu.
    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            if popover.isShown { popover.performClose(nil) }
            showSettingsMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Make the popover key so its ⌘Q shortcut responds.
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showSettingsMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()

        // Menu-bar title mode: activity (spinner word) vs usage (5h %).
        let modeItem = NSMenuItem(title: "Menu bar shows", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        let activity = NSMenuItem(title: "Activity", action: #selector(setModeActivity), keyEquivalent: "")
        activity.target = self
        activity.state = feed.menuBarMode == .activity ? .on : .off
        let usage = NSMenuItem(title: "Usage", action: #selector(setModeUsage), keyEquivalent: "")
        usage.target = self
        usage.state = feed.menuBarMode == .usage ? .on : .off
        modeMenu.addItem(activity)
        modeMenu.addItem(usage)
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(.separator())

        let launch = NSMenuItem(title: "Launch at Login",
                                action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = feed.launchAtLogin ? .on : .off
        menu.addItem(launch)

        // Live usage: poll the API for 5h/7d limits so they refresh in any session
        // (not just interactive TUI ones). One tiny request per poll.
        let liveUsage = NSMenuItem(title: "Live usage (polls API)",
                                   action: #selector(toggleUsagePolling), keyEquivalent: "")
        liveUsage.target = self
        liveUsage.state = feed.usagePollingEnabled ? .on : .off
        menu.addItem(liveUsage)

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshFeed), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let relaunch = NSMenuItem(title: "Relaunch", action: #selector(relaunchApp), keyEquivalent: "")
        relaunch.target = self
        menu.addItem(relaunch)

        let clear = NSMenuItem(title: "Clear All Sessions",
                               action: #selector(clearAllSessions), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit claude spinner",
                              action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    @objc private func toggleLaunchAtLogin() { feed.launchAtLogin.toggle() }
    @objc private func toggleUsagePolling() { feed.usagePollingEnabled.toggle() }
    @objc private func clearAllSessions() { feed.clearAll() }
    @objc private func refreshFeed() { feed.refresh(); feed.refreshUsage() }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
    @objc private func setModeActivity() { feed.menuBarMode = .activity }
    @objc private func setModeUsage() { feed.menuBarMode = .usage }

    /// Quit and reopen. A short-lived helper reopens after this instance exits, so
    /// the single-instance guard doesn't reject the new copy.
    /// Handle a tap on the attention notification (or its "Focus session" button):
    /// bring the session's host window to the front. Both the default tap and the
    /// explicit action focus — the button just makes the affordance visible.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == NotificationConfig.focusAction
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let host = response.notification.request.content.userInfo["host"] as? String ?? ""
            let pidVal = response.notification.request.content.userInfo["pid"] as? Int
            let pid = pidVal == 0 ? nil : pidVal
            let cwd = response.notification.request.content.userInfo["cwd"] as? String ?? ""
            SessionLauncher.focus(host: host, pid: pid, cwd: cwd)
        }
        completionHandler()
    }

    /// Show the banner + play the sound even if the app is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    @objc private func relaunchApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; open \"\(Bundle.main.bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// The status-bar label: the animated spinner glyph plus the compact status
/// text, rendered via an NSHostingView inside the status item's button.
struct MenuBarLabel: View {
    // @ObservedObject so the label redraws on every glyphPhase tick (spinner
    // animation) and whenever the session list changes.
    @ObservedObject var feed: FeedWatcher

    var body: some View {
        // Bright + pulsing while working/attention; quiet grey for the done-flash
        // and idle states so a finished session recedes into the menu bar.
        // Blue while a session needs you, the Claude orange while working, grey at
        // rest. Both active states pulse the animated spinner, like the terminal.
        let color: Color = {
            switch feed.menuBarState {
            case .attention:        return .attentionBright
            case .working:          return .claudeBright
            case .doneFlash, .idle: return .menuIdle
            }
        }()
        let glyphColor = feed.menuBarActive ? color.opacity(feed.glyphPulse) : color

        // The spinner frames (✶✸✹✺✻✽…) have different advance widths in the
        // fallback font, so cycling them shifts everything after and makes the
        // status item shimmy. Pin the glyph to a fixed-width slot so it animates
        // in place, and use monospaced digits so the timer never jitters either —
        // width then only changes on rare digit-count/word rollovers.
        HStack(spacing: 3) {
            Text(feed.menuBarGlyph)
                .font(.claudeMono(15))
                .foregroundColor(glyphColor)
                .frame(width: 16)
            switch feed.menuBarMode {
            case .usage:
                // Usage mode always shows the 5h % (that's what the toggle promises);
                // attention is still carried by the blue glyph, not the title text.
                // Fall back to the activity word only when there's no usage data yet.
                if let h5 = feed.usageFiveHourPct {
                    // Pulse the % when it crosses the red threshold so an imminent
                    // rate limit catches the eye even with nothing running.
                    Text("5h \(h5)%")
                        .font(.claudeMono(13))
                        .monospacedDigit()
                        .foregroundColor(Color.usageTint(h5).opacity(feed.usageAlarm ? feed.glyphPulse : 1))
                } else if !feed.menuBarBody.isEmpty {
                    Text(feed.menuBarBody)
                        .font(.claudeMono(13)).monospacedDigit().foregroundColor(color)
                }
            case .activity:
                if !feed.menuBarBody.isEmpty {
                    Text(feed.menuBarBody)
                        .font(.claudeMono(13)).monospacedDigit().foregroundColor(color)
                }
            }
        }
        .fixedSize()
        .padding(.horizontal, 4)
        .accessibilityLabel(feed.menuBarBody.isEmpty ? "Claude spinner, idle"
                                                     : "Claude spinner, \(feed.menuBarBody)")
    }
}

/// Claude's pulsing asterisk spinner glyphs, indexed by wall-clock time so every
/// view that draws the spinner stays in phase.
enum Spinner {
    static let frames = ["✶", "✸", "✹", "✺", "✻", "✽", "✻", "✺", "✹", "✸"]
    /// The idle/done resting glyph.
    static let idle = "✻"

    static func frame(at date: Date) -> String {
        let i = Int((date.timeIntervalSinceReferenceDate * Constants.spinnerFPS).rounded(.down))
        return frames[((i % frames.count) + frames.count) % frames.count]
    }
}

extension Color {
    /// Resolves per appearance. Defined in code rather than an asset catalog because
    /// run.sh's swiftc fallback compiles only the three sources — a colorset would
    /// exist in Xcode builds and silently vanish from the dev loop.
    ///
    /// The panel's colors are tuned for the light material; on the dark one the same
    /// mid-dark values sink into the background, so each has a lifted counterpart.
    static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Claude's burnt-orange accent, matching the terminal spinner.
    static let claude = dynamic(light: (0.76, 0.42, 0.24), dark: (0.93, 0.58, 0.36))
    /// Muted variant for the idle/done line — colored, but quieter than active.
    static let claudeDim = claude.opacity(0.65)
    /// Brighter, higher-contrast accent for the menu-bar label so it stays legible
    /// against the translucent menu bar over any wallpaper.
    static let claudeBright = Color(red: 0.98, green: 0.62, blue: 0.34)
    /// Neutral grey for the menu-bar label when idle/done — recedes into the bar.
    static let menuIdle = Color(white: 0.60)
    /// Blue "needs you" accent — deliberately unlike the busy orange, so an
    /// attention session reads as a different state, not just a louder one.
    static let attention = dynamic(light: (0.30, 0.58, 0.92), dark: (0.45, 0.70, 1.0))
    /// Brighter attention blue for menu-bar-label legibility over any wallpaper.
    static let attentionBright = Color(red: 0.40, green: 0.66, blue: 1.0)

    // The urgency bands, built once rather than per call: every `dynamic` call mints a
    // fresh NSColor, and SwiftUI compares Color by that underlying instance — so
    // building them on the fly would make two same-band tints compare unequal.
    static let usageRed = dynamic(light: (0.85, 0.32, 0.28), dark: (1.0, 0.48, 0.44))
    static let usageAmber = dynamic(light: (0.90, 0.58, 0.24), dark: (1.0, 0.70, 0.36))
    static let usageYellow = dynamic(light: (0.82, 0.72, 0.30), dark: (0.94, 0.85, 0.42))
    static let usageGreen = dynamic(light: (0.45, 0.70, 0.45), dark: (0.55, 0.85, 0.55))

    /// Urgency gradient for a 0–100 usage percentage: green (headroom) → yellow →
    /// amber → red (near limit), so a rate limit reads at a glance.
    static func usageTint(_ pct: Int) -> Color {
        switch pct {
        case 90...: return usageRed
        case 75...: return usageAmber
        case 50...: return usageYellow
        default:    return usageGreen
        }
    }

    /// Urgency for a session's context, banded on the absolute token count rather
    /// than its percentage: a 200k conversation is heavy whether the window is 200k
    /// or 1m, and the percentage hides that on the big windows.
    static func contextTint(_ tokens: Int) -> Color {
        switch tokens {
        case 200_000...: return usageRed
        case 150_000...: return usageAmber
        case 100_000...: return usageYellow
        default:         return usageGreen
        }
    }

    static let modelOpus = dynamic(light: (0.62, 0.47, 0.86), dark: (0.76, 0.63, 0.96))    // purple
    static let modelSonnet = dynamic(light: (0.35, 0.68, 0.80), dark: (0.48, 0.82, 0.94))  // cyan
    static let modelHaiku = dynamic(light: (0.45, 0.72, 0.45), dark: (0.55, 0.85, 0.55))   // green
    static let modelFable = dynamic(light: (0.42, 0.56, 0.86), dark: (0.56, 0.70, 0.98))   // blue

    /// Model-family accent, matching the statusLine's color language.
    static func modelTint(_ name: String?) -> Color {
        guard let n = name?.lowercased() else { return .claudeDim }
        if n.contains("opus")   { return modelOpus }
        if n.contains("sonnet") { return modelSonnet }
        if n.contains("haiku")  { return modelHaiku }
        if n.contains("fable")  { return modelFable }
        return .claudeDim
    }

    static let hostVsc = dynamic(light: (0.35, 0.60, 0.90), dark: (0.50, 0.74, 1.0))   // blue
    static let hostTrm = dynamic(light: (0.45, 0.72, 0.45), dark: (0.55, 0.85, 0.55))  // green
    static let hostWeb = dynamic(light: (0.35, 0.72, 0.78), dark: (0.48, 0.85, 0.92))  // cyan
    static let hostApp = dynamic(light: (0.62, 0.47, 0.86), dark: (0.76, 0.63, 0.96))  // purple
}

/// Identifiers for the attention notification's category and "Focus session"
/// action, shared between the notification content (FeedWatcher) and the handler
/// that registers/acts on them (AppDelegate).
enum NotificationConfig {
    static let attentionCategory = "ATTENTION"
    static let focusAction = "FOCUS_SESSION"
}

/// Brings a session's host app to the front. Shared by the row tap and the
/// attention notification's "Focus session" action so both behave identically.
enum SessionLauncher {
    /// Host string (bundle ID or `TERM_PROGRAM` value) → the app bundle to focus.
    static let hostBundleIDs: [String: String] = [
        "com.microsoft.VSCode": "com.microsoft.VSCode", "vscode": "com.microsoft.VSCode",
        "com.mitchellh.ghostty": "com.mitchellh.ghostty", "ghostty": "com.mitchellh.ghostty",
        "com.apple.Terminal": "com.apple.Terminal", "Apple_Terminal": "com.apple.Terminal",
        "com.googlecode.iterm2": "com.googlecode.iterm2", "iTerm.app": "com.googlecode.iterm2",
        "com.anthropic.claudefordesktop": "com.anthropic.claudefordesktop",
        "dev.zed.Zed": "dev.zed.Zed", "zed": "dev.zed.Zed",
    ]

    /// Which bundle to focus for a host string. A known host maps through
    /// `hostBundleIDs`; an unknown host that is ITSELF the bundle ID of a running
    /// app resolves to itself, because every GUI editor reports its bundle ID as
    /// the host (`dev.zed.Zed`, Cursor, VSCodium, Windsurf). Without that, a host
    /// missing from the table silently took the terminal fallback and opened a
    /// brand-new Ghostty window instead of the editor the session is running in —
    /// the same wrong-window failure as bug-072/091/110, arriving through the
    /// table rather than the branch logic. Only a host we genuinely can't place
    /// (an unrecognized `TERM_PROGRAM`, whose value is never a bundle ID) falls
    /// back. Pure, with the running-app check injected, so it's testable.
    static func resolveBundleID(host: String, fallback: String,
                                isRunning: (String) -> Bool) -> String {
        if let known = hostBundleIDs[host] { return known }
        if !host.isEmpty && isRunning(host) { return host }
        return fallback
    }

    /// What `focus` does for a GUI app (VS Code, Ghostty, Claude for Desktop). A
    /// running instance is ALWAYS activated in place; a path launch — which spawns a
    /// NEW window for the folder — is used only when the app isn't running yet.
    /// Pure so the "running instance wins" ordering can be locked down by a test; it
    /// has regressed every time this branch was refactored (bug-072/073/091).
    enum GUIFocusAction: Equatable {
        case activateRunning   // focus the already-open window in place
        case openPath          // launch and open cwd (spawns a window)
        case launchBare        // launch with no path
    }

    static func guiFocusAction(isRunning: Bool, cwd: String) -> GUIFocusAction {
        if isRunning { return .activateRunning }
        return cwd.isEmpty ? .launchBare : .openPath
    }

    static func focus(host: String, pid: Int?, cwd: String) {
        // Unplaceable host — focus the user's terminal, never spawn a fresh window.
        let fallback = FileManager.default.fileExists(atPath: "/Applications/Ghostty.app")
            ? "com.mitchellh.ghostty" : "com.apple.Terminal"
        let bundleID = resolveBundleID(host: host, fallback: fallback) { id in
            !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
        }

        if bundleID == "com.apple.Terminal" {
            if let pid = pid, let tty = getTTY(for: pid) {
                if focusTerminalByTTY(tty) { return }
            }
            let folderName = (cwd as NSString).lastPathComponent
            if !folderName.isEmpty {
                if focusTerminalByTitle(folderName) { return }
            }
            openPath(cwd, withBundleID: "com.apple.Terminal")
        } else if bundleID == "com.googlecode.iterm2" {
            if let pid = pid, let tty = getTTY(for: pid) {
                if focusITermByTTY(tty) { return }
            }
            let folderName = (cwd as NSString).lastPathComponent
            if !folderName.isEmpty {
                if focusITermByTitle(folderName) { return }
            }
            openPath(cwd, withBundleID: "com.googlecode.iterm2")
        } else {
            // VS Code, Ghostty, Claude for Desktop, etc.
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            switch guiFocusAction(isRunning: running != nil, cwd: cwd) {
            case .activateRunning:
                running?.activate(options: [.activateAllWindows])
            case .openPath:
                openPath(cwd, withBundleID: bundleID)
            case .launchBare:
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = ["-b", bundleID]
                try? task.run()
            }
        }
    }

    private static func openPath(_ path: String, withBundleID bundleID: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-b", bundleID, path]
        try? task.run()
    }

    /// Runs `script`, treating any error as "couldn't focus" so the caller can fall
    /// back. Note the failure mode this hides: an AppleScript that half-executes
    /// (selects the tab) and then throws still reports false, so the caller opens a
    /// new tab on top of the tab it just selected. Use only verbs the target app
    /// actually supports — `activate`, never `set frontmost to true`, which iTerm
    /// rejects with -10006 (bug-110).
    private static func runAppleScript(_ script: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return false }
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output == "true"
    }

    private static func getTTY(for pid: Int) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "tty=", "-p", "\(pid)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let tty = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if tty == "?" || tty?.isEmpty == true { return nil }
        if let t = tty {
            return t.hasPrefix("tty") ? t : "tty" + t
        }
        return nil
    }

    private static func focusTerminalByTTY(_ tty: String) -> Bool {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t contains "\(tty)" then
                        activate
                        set index of w to 1
                        set selected of t to true
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        return runAppleScript(script)
    }

    private static func focusTerminalByTitle(_ title: String) -> Bool {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if name of t contains "\(title)" or custom title of t contains "\(title)" then
                        activate
                        set index of w to 1
                        set selected of t to true
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        return runAppleScript(script)
    }

    private static func focusITermByTTY(_ tty: String) -> Bool {
        let script = """
        tell application "iTerm"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s contains "\(tty)" then
                            select s
                            select t
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        return runAppleScript(script)
    }

    private static func focusITermByTitle(_ title: String) -> Bool {
        let script = """
        tell application "iTerm"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if name of s contains "\(title)" then
                            select s
                            select t
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        return runAppleScript(script)
    }
}

/// A compact, color-coded tag for where a session runs, shown just left of the
/// row's time. Collapses the many possible host strings (macOS bundle IDs and
/// `TERM_PROGRAM` values) into four buckets so the row reads at a glance.
enum HostTag {
    case vsc, trm, web, app

    var label: String {
        switch self {
        case .vsc: return "vsc"
        case .trm: return "trm"
        case .web: return "web"
        case .app: return "app"
        }
    }

    /// Distinct hue per surface: editor blue, terminal green, web cyan, app purple.
    var color: Color {
        switch self {
        case .vsc: return .hostVsc
        case .trm: return .hostTrm
        case .web: return .hostWeb
        case .app: return .hostApp
        }
    }

    /// Classify a raw host string (a macOS bundle ID or a `TERM_PROGRAM` value).
    /// Returns nil only when the host is unknown/empty, so no tag is drawn rather
    /// than a wrong one.
    static func from(_ host: String) -> HostTag? {
        let h = host.lowercased()
        if h.isEmpty { return nil }
        // VS Code and its forks (Cursor, VSCodium, Windsurf) share the vscode host.
        if h.contains("vscode") || h.contains("cursor")
            || h.contains("vscodium") || h.contains("windsurf") { return .vsc }
        // Zed reports `dev.zed.Zed` (bundle ID, also `dev.zed.Zed-Preview`) or `zed`
        // (TERM_PROGRAM). Matched exactly rather than by `contains`, which the other
        // tokens above can afford but a three-letter "zed" can't — it would claim
        // any host merely containing those letters, and this branch runs before the
        // terminal one below.
        if h == "zed" || h.hasPrefix("dev.zed.") { return .vsc }
        // Anthropic's desktop app.
        if h.contains("claudefordesktop") || h.contains("claude-desktop") { return .app }
        // The web app (claude.ai/code).
        if h.contains("claude.ai") || h == "web" { return .web }
        // Known terminal emulators.
        if h.contains("ghostty") || h.contains("terminal") || h.contains("iterm")
            || h.contains("wezterm") || h.contains("alacritty") || h.contains("kitty")
            || h.contains("hyper") || h.contains("tabby") || h.contains("warp") { return .trm }
        return nil
    }
}

extension Font {
    /// The terminal font Claude Code is shown in (the user's Ghostty font-family).
    /// Always-installed Menlo; Font.custom falls back to the system font if absent.
    static let claudeFontName = "Menlo"

    static func claudeMono(_ size: CGFloat) -> Font {
        .custom(claudeFontName, size: size)
    }
}
