//
//  claude_spinnerApp.swift
//  claude spinner
//
//  Menubar mirror of the live Claude Code session feed.
//

import SwiftUI
import AppKit

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

        let launch = NSMenuItem(title: "Launch at Login",
                                action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = feed.launchAtLogin ? .on : .off
        menu.addItem(launch)

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
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}

/// The status-bar label: the animated spinner glyph plus the compact status
/// text, rendered via an NSHostingView inside the status item's button.
struct MenuBarLabel: View {
    // @ObservedObject so the label redraws on every glyphPhase tick (spinner
    // animation) and whenever the session list changes.
    @ObservedObject var feed: FeedWatcher

    var body: some View {
        let color = feed.menuBarActive ? Color.claudeBright : Color.claudeBright.opacity(0.8)
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
            if !feed.menuBarBody.isEmpty {
                Text(feed.menuBarBody)
                    .font(.claudeMono(13))
                    .monospacedDigit()
                    .foregroundColor(color)
            }
        }
        .fixedSize()
        .padding(.horizontal, 4)
    }
}

/// Claude's pulsing asterisk spinner glyphs, indexed by wall-clock time so every
/// view that draws the spinner stays in phase.
enum Spinner {
    static let frames = ["✶", "✸", "✹", "✺", "✻", "✽", "✻", "✺", "✹", "✸"]

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

    /// Urgency tint for a 0–100 usage percentage: quiet when there's headroom,
    /// amber past 75%, red past 90% — so a rate limit reads at a glance.
    static func usageTint(_ pct: Int) -> Color {
        if pct >= 90 { return Color(red: 0.85, green: 0.32, blue: 0.28) }  // red
        if pct >= 75 { return Color(red: 0.88, green: 0.62, blue: 0.24) }  // amber
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
