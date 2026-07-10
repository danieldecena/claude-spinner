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
            SessionLauncher.focus(host: host)
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
    /// Claude's burnt-orange accent, matching the terminal spinner.
    static let claude = Color(red: 0.76, green: 0.42, blue: 0.24)
    /// Muted variant for the idle/done line — colored, but quieter than active.
    static let claudeDim = Color(red: 0.76, green: 0.42, blue: 0.24).opacity(0.65)
    /// Brighter, higher-contrast accent for the menu-bar label so it stays legible
    /// against the translucent menu bar over any wallpaper.
    static let claudeBright = Color(red: 0.98, green: 0.62, blue: 0.34)
    /// Neutral grey for the menu-bar label when idle/done — recedes into the bar.
    static let menuIdle = Color(white: 0.60)
    /// Blue "needs you" accent — deliberately unlike the busy orange, so an
    /// attention session reads as a different state, not just a louder one.
    static let attention = Color(red: 0.30, green: 0.58, blue: 0.92)
    /// Brighter attention blue for menu-bar-label legibility over any wallpaper.
    static let attentionBright = Color(red: 0.40, green: 0.66, blue: 1.0)

    /// Urgency gradient for a 0–100 usage percentage: green (headroom) → yellow →
    /// amber → red (near limit), so a rate limit reads at a glance.
    static func usageTint(_ pct: Int) -> Color {
        switch pct {
        case 90...: return Color(red: 0.85, green: 0.32, blue: 0.28)  // red
        case 75...: return Color(red: 0.90, green: 0.58, blue: 0.24)  // amber
        case 50...: return Color(red: 0.82, green: 0.72, blue: 0.30)  // yellow
        default:    return Color(red: 0.45, green: 0.70, blue: 0.45)  // green
        }
    }

    /// Model-family accent, matching the statusLine's color language.
    static func modelTint(_ name: String?) -> Color {
        guard let n = name?.lowercased() else { return .claudeDim }
        if n.contains("opus")   { return Color(red: 0.62, green: 0.47, blue: 0.86) }  // purple
        if n.contains("sonnet") { return Color(red: 0.35, green: 0.68, blue: 0.80) }  // cyan
        if n.contains("haiku")  { return Color(red: 0.45, green: 0.72, blue: 0.45) }  // green
        if n.contains("fable")  { return Color(red: 0.42, green: 0.56, blue: 0.86) }  // blue
        return .claudeDim
    }
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
    ]

    static func focus(host: String) {
        // Unknown host — focus the user's terminal, never spawn a fresh window.
        let fallback = FileManager.default.fileExists(atPath: "/Applications/Ghostty.app")
            ? "com.mitchellh.ghostty" : "com.apple.Terminal"
        let bundleID = hostBundleIDs[host] ?? fallback

        // Activate the already-running instance — this brings the session's
        // existing window(s) to the front and never opens a new one. Passing the
        // folder path to `open` (as we used to) made VS Code open the folder in a
        // *new* window; just activating the running app avoids that entirely.
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate(options: [.activateAllWindows])
        } else {
            // Not running — launch it (only case where a window legitimately opens).
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-b", bundleID]
            try? task.run()
        }
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
        case .vsc: return Color(red: 0.35, green: 0.60, blue: 0.90)  // blue
        case .trm: return Color(red: 0.45, green: 0.72, blue: 0.45)  // green
        case .web: return Color(red: 0.35, green: 0.72, blue: 0.78)  // cyan
        case .app: return Color(red: 0.62, green: 0.47, blue: 0.86)  // purple
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
