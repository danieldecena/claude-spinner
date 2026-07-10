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
final class AppDelegate: NSObject, NSApplicationDelegate {
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

        // Ask once for notification permission (used for attention alerts).
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

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
    @objc private func clearAllSessions() { feed.clearAll() }
    @objc private func refreshFeed() { feed.refresh() }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
    @objc private func setModeActivity() { feed.menuBarMode = .activity }
    @objc private func setModeUsage() { feed.menuBarMode = .usage }

    /// Quit and reopen. A short-lived helper reopens after this instance exits, so
    /// the single-instance guard doesn't reject the new copy.
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
        let color: Color = feed.menuBarActive ? .claudeBright : .menuIdle
        // Bright for working+attention, but only working pulses — a waiting glyph
        // holds steady so it doesn't read as busy motion.
        let glyphColor = feed.menuBarAnimating ? color.opacity(feed.glyphPulse) : color

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
                // A waiting session is time-sensitive, so it wins the title even in
                // usage mode; the 5h % returns once nothing needs you.
                if feed.menuBarState == .attention, !feed.menuBarBody.isEmpty {
                    Text(feed.menuBarBody)
                        .font(.claudeMono(13)).monospacedDigit().foregroundColor(color)
                } else if let h5 = feed.usageFiveHourPct {
                    Text("5h \(h5)%")
                        .font(.claudeMono(13))
                        .monospacedDigit()
                        .foregroundColor(Color.usageTint(h5))
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
    /// A steady, distinct marker for a session that has stopped and needs you —
    /// so "waiting" never looks like the animated "busy" spinner.
    static let attention = "◆"

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

    /// Tint for a context-window percentage in a row: quiet until it's filling,
    /// amber past 65%, red past 85% (running out of context is disruptive early).
    static func contextTint(_ pct: Int) -> Color {
        if pct >= 85 { return Color(red: 0.85, green: 0.32, blue: 0.28) }  // red
        if pct >= 65 { return Color(red: 0.90, green: 0.58, blue: 0.24) }  // amber
        return .claudeDim
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

extension Font {
    /// The terminal font Claude Code is shown in (the user's Ghostty font-family).
    /// Always-installed Menlo; Font.custom falls back to the system font if absent.
    static let claudeFontName = "Menlo"

    static func claudeMono(_ size: CGFloat) -> Font {
        .custom(claudeFontName, size: size)
    }
}
