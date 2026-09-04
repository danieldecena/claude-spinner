//
//  claude_spinnerApp.swift
//  claude spinner
//
//  Menubar mirror of the live Claude Code session feed.
//

import SwiftUI
import AppKit
import Combine
import UserNotifications
import os.log

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
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate,
                         NSWindowDelegate, NSMenuDelegate {
    private let feed = FeedWatcher()
    /// Nil in the `window` surface, where no status item is ever created.
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    /// Standalone window showing the same panel. The status item is the primary
    /// surface, but macOS silently refuses to place a status item when the menu
    /// bar is full -- on a notched display that happens well before the bar looks
    /// full, and the item is parked at a bogus off-bar position (observed
    /// 2026-07-27: x=-1, y=972 on a 1512x982 screen, menu bar at y=0..33). The app
    /// was .accessory with no window and no Dock icon, so that state left no way
    /// in at all. This window is the fallback.
    private var mainWindow: NSWindow?
    /// The settings menu's second host. With the status item unplaced there is
    /// nothing to right-click, so every control below `showSettingsMenu` is
    /// otherwise unreachable; .regular gives the app a real menu bar to hang it on.
    private var spinnerMenuItem: NSMenuItem?
    private var titleObserver: AnyCancellable?
    /// Prompts a blocked `ask.sh` is waiting on, and the only writer of the
    /// answers it reads back.
    private let asks = AskInbox.shared
    private var askObserver: AnyCancellable?

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
        center.requestAuthorization(options: [.alert, .sound]) { [asks] granted, error in
            // Public on purpose. NSLog's Swift bridge redacts interpolated values
            // to <private>, and this line is the one that separates "posted but
            // not presented" from "never posted" — the two look identical from
            // add()'s error, which is nil either way.
            os_log("claude spinner: authorization granted=%{public}d error=%{public}@",
                   granted ? 1 : 0, error?.localizedDescription ?? "none")
            asks.refreshAuthorization()
        }
        registerCategories(for: asks.pending)

        // Every pending ask contributes its own category, because the buttons are
        // that request's option labels. Re-register on each change rather than at
        // launch: `setNotificationCategories` replaces the whole set, so the
        // static one has to be rebuilt alongside them every time.
        askObserver = asks.$pending.sink { [weak self] pending in
            self?.registerCategories(for: pending)
            self?.postAskNotifications(pending)
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuContentView(feed: feed))

        // Window surface creates no status item at all: it is the deterministic
        // choice precisely because nothing about it depends on the menu bar having
        // room, and not asking for a slot hands one back to a bar that was full
        // enough to drop us. Everything below reaches the item through optional
        // chaining, so its absence needs no further guards.
        guard feed.surface == .menuBar else {
            installSettingsMenu()
            showMainWindow()
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
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

        // AppKit does not report placement failure, and the item's frame is not
        // final at launch -- so check on the next runloop passes rather than here.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.showWindowIfStatusItemUnplaced()
        }
        // Placement is decided against the menu bar of a particular display, so a
        // display change is the one moment it genuinely changes. Cheaper and more
        // honest than polling for an event that fires a handful of times a day.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Installed at launch, not when the window opens: appending to `mainMenu`
        // immediately after the .regular flip did not stick (verified 2026-08-12 --
        // the Spinner menu was absent from a running .regular instance). An
        // .accessory app's menu bar is never drawn, so an early install is free.
        installSettingsMenu()
    }

    @objc private func screenParametersChanged() { showWindowIfStatusItemUnplaced() }

    /// The status item's window frame and the frame of the screen holding it.
    /// `nil` when either is missing, which the caller reads as unplaced.
    private var statusItemFrames: (item: CGRect, screen: CGRect)? {
        guard let window = statusItem?.button?.window,
              let screen = window.screen ?? NSScreen.main else { return nil }
        return (window.frame, screen.frame)
    }

    private var statusItemIsUnplaced: Bool {
        guard let frames = statusItemFrames else { return true }
        return Constants.statusItemIsUnplaced(itemFrame: frames.item, screenFrame: frames.screen)
    }

    private func showWindowIfStatusItemUnplaced() {
        // Opens the fallback once and never re-fronts it: this also runs on every
        // display change, and an unplaced item is a permanent state, so re-showing
        // would steal focus each time a monitor is plugged in.
        guard mainWindow == nil, statusItemIsUnplaced else { return }
        let measured = statusItemFrames.map {
            "item \(NSStringFromRect($0.item)) on screen \(NSStringFromRect($0.screen))"
        } ?? "status item has no window"
        // Log what was measured, not just the verdict -- the frames are the whole
        // evidence for this call, and without them the next investigation restarts.
        NSLog("claude spinner: status item unplaced (menu bar full) -- \(measured); opening window instead")
        showMainWindow()
    }

    /// Show the panel as an ordinary window. Switches to .regular so the app gets
    /// a Dock icon -- without one, an .accessory app whose status item is unplaced
    /// cannot be reached again after the window is closed.
    @objc func showMainWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        if mainWindow == nil {

            // Built from a bare NSHostingView rather than a contentViewController.
            // The controller path could not do both halves of "resizable": its
            // default sizingOptions publish the content's size as the window's min
            // AND max (asked for 760x400, got 470x215 back), clearing them let the
            // drag work but made AppKit open the window at 1904x1050, and
            // `.preferredContentSize` fixed the open size and re-pinned the drag.
            // A hosting view with an autoresizing mask has no such opinion: the
            // window's own contentRect sizes it, and the view follows.
            // Only the VERTICAL fill goes here. `maxWidth: .infinity` inflates the
            // hosting view, `windowDidResize` writes that width into `panelWidth`,
            // the content then demands it back, and the window can no longer shrink
            // (measured: stuck at 1904 whatever it was asked for). Width is owned by
            // `panelWidth` alone; height fills whatever the window is dragged to.
            // No outer `.frame(maxWidth/maxHeight: .infinity)`: `fillsWidth` already
            // frees the width inside the panel, and asking for infinity here is what
            // made AppKit open the window at the size of the screen.
            let hosting = NSHostingView(rootView: WindowContentView(feed: feed))
            hosting.autoresizingMask = [.width, .height]
            // The hosting view goes inside a plain container. NSHostingView drives
            // the window's size through its own constraints whichever way its
            // content is framed — that is what kept pinning one axis or the other.
            // A bare NSView has no intrinsic size and no constraints, so the window
            // is free and the hosting view just follows it via the autoresize mask.
            let container = NSView(frame: NSRect(x: 0, y: 0,
                                                 width: Constants.windowDefaultWidth,
                                                 height: Constants.windowDefaultHeight))
            hosting.frame = container.bounds
            container.addSubview(hosting)

            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0,
                                    width: Constants.windowDefaultWidth,
                                    height: Constants.windowDefaultHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.contentView = container
            // Width has a floor because `RowLayout.columns` subtracts fixed slots
            // from it without a `max(0)` guard, relying on the caller never handing
            // it less than `panelMinWidth`.
            w.contentMinSize = NSSize(width: Constants.windowMinWidth,
                                      height: Constants.windowMinHeight)
            // `setFrameAutosaveName` restores a saved frame the instant it is called,
            // so it goes before the default size and the default is applied only when
            // there was nothing to restore. Checking UserDefaults directly is the only
            // way to tell: the call reports whether the NAME was set, not whether a
            // frame came back. Without the explicit size a first run opens at
            // 1904x1050 — the content can fill, so AppKit gives it the screen.
            let remembered = UserDefaults.standard.string(forKey: "NSWindow Frame SpinnerPanel") != nil
            w.setFrameAutosaveName("SpinnerPanel")
            if !remembered {
                w.setContentSize(NSSize(width: Constants.windowDefaultWidth,
                                        height: Constants.windowDefaultHeight))
                w.center()
            }
            w.isReleasedWhenClosed = false
            w.delegate = self
            mainWindow = w
            startWindowTitleUpdates()
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Reflow the rows to the dragged width. `.resizable` alone is half a feature:
    /// `MenuContentView` pins itself to `feed.panelWidth`, so without this the drag
    /// would only add dead space beside a fixed-width panel.
    ///
    /// Deliberately not routed through `Constants.fittedPanelWidth` — that clamp
    /// exists to keep a popover from overrunning a screen edge, and its 470pt
    /// ceiling would silently ignore a window the user dragged wider. The floor is
    /// upheld by `contentMinSize` instead.
    func windowDidResize(_ notification: Notification) {
        // Nothing to do. This used to write the dragged width into
        // `feed.panelWidth`, because the window hosted the popover panel and the
        // panel pins itself to that value. The window now hosts its own view,
        // and the popover still needs its own fixed width -- so resizing the
        // window must no longer reflow the menu-bar dropdown.
    }

    /// Closing the window hands the Dock icon back -- but only when there is a
    /// placed status item to return to. With an unplaced one, .accessory would
    /// leave the app with no surface at all, which is the state this window fixes.
    func windowWillClose(_ notification: Notification) {
        guard !statusItemIsUnplaced else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Mirror the menu-bar readout into the window title. When the status item is
    /// unplaced, `MenuBarLabel` renders into a button nobody can see, so the title
    /// is the only place the spinner word or the usage figure appears at all.
    private func startWindowTitleUpdates() {
        updateWindowTitle()
        // `menuBarBody`/`usageMenuBarTitle` are computed, so there is no per-property
        // publisher to observe. `objectWillChange` fires *before* the change, hence
        // the hop to the next runloop pass; it also fires at spinner FPS, so
        // assigning only a changed string is what keeps this cheap.
        titleObserver = feed.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateWindowTitle() }
    }

    private func updateWindowTitle() {
        guard let window = mainWindow else { return }
        // The glyph is left out on purpose: it animates, and a title bar redrawing
        // ten times a second is noise rather than information.
        let body = feed.menuBarMode == .usage
            ? (feed.usageMenuBarTitle ?? feed.menuBarBody)
            : feed.menuBarBody
        let title = body.isEmpty ? "Claude Spinner" : "Claude Spinner · \(body)"
        if window.title != title { window.title = title }
    }

    /// Clicking the Dock icon (or a second `open -a`) reopens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
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
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Clamp the panel to the display actually holding this status item so a
            // far-right icon can't push the fixed-width panel off the screen edge.
            // The status bar has a per-display window, so `button.window?.screen` is
            // that display; `visibleFrame` excludes the menu bar and Dock.
            let screen = button.window?.screen ?? NSScreen.main
            feed.setPanelWidth(Constants.fittedPanelWidth(visibleWidth: screen?.visibleFrame.width))
            // Force the hosting controller to adopt the new width before AppKit sizes
            // the popover, so a display change doesn't open one frame at a stale width.
            popover.contentViewController?.view.layoutSubtreeIfNeeded()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Make the popover key so its ⌘Q shortcut responds.
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showSettingsMenu() {
        guard let button = statusItem?.button else { return }
        settingsMenu().popUp(positioning: nil,
                             at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    /// The settings menu's other host. Right-clicking the status item is the only
    /// way in, so when the item is unplaced every control below is unreachable --
    /// .regular gives the app a real menu bar, so the same menu goes there too.
    private func installSettingsMenu() {
        guard spinnerMenuItem == nil else { return }
        guard let mainMenu = NSApp.mainMenu else {
            NSLog("claude spinner: no main menu to install the Spinner menu into")
            return
        }
        let menu = settingsMenu()
        menu.title = "Spinner"
        menu.delegate = self
        let item = NSMenuItem(title: "Spinner", action: nil, keyEquivalent: "")
        item.submenu = menu
        mainMenu.addItem(item)
        spinnerMenuItem = item
    }

    /// Checkmarks are resolved as the items are built, which is fine for a popup
    /// rebuilt on every right-click but not for the main-menu copy, which outlives
    /// the state it shows. Rebuilding it here keeps one builder for both hosts.
    func menuNeedsUpdate(_ menu: NSMenu) { populateSettingsMenu(menu) }

    private func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        populateSettingsMenu(menu)
        return menu
    }

    private func populateSettingsMenu(_ menu: NSMenu) {
        menu.removeAllItems()

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

        // Which surface to present. Applies on next launch, so both entries say so
        // rather than leaving the user waiting for something to happen.
        let surfaceItem = NSMenuItem(title: "Show in", action: nil, keyEquivalent: "")
        let surfaceMenu = NSMenu()
        let bar = NSMenuItem(title: "Menu bar", action: #selector(setSurfaceMenuBar), keyEquivalent: "")
        bar.target = self
        bar.state = feed.surface == .menuBar ? .on : .off
        let win = NSMenuItem(title: "Window", action: #selector(setSurfaceWindow), keyEquivalent: "")
        win.target = self
        win.state = feed.surface == .window ? .on : .off
        surfaceMenu.addItem(bar)
        surfaceMenu.addItem(win)
        surfaceMenu.addItem(.separator())
        surfaceMenu.addItem(NSMenuItem(title: "Applies on next launch", action: nil, keyEquivalent: ""))
        surfaceItem.submenu = surfaceMenu
        menu.addItem(surfaceItem)

        menu.addItem(.separator())

        let window = NSMenuItem(title: "Open Window", action: #selector(showMainWindow),
                                keyEquivalent: "")
        window.target = self
        menu.addItem(window)

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

        // Off by default: every turn of every session ends, so this is the noisy
        // one. Attention alerts fire whether or not it's on.
        let doneAlert = NSMenuItem(title: "Notify when a turn finishes",
                                   action: #selector(toggleNotifyOnDone), keyEquivalent: "")
        doneAlert.target = self
        doneAlert.state = feed.notifyOnDone ? .on : .off
        menu.addItem(doneAlert)

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
    }

    @objc private func toggleLaunchAtLogin() { feed.launchAtLogin.toggle() }
    @objc private func toggleUsagePolling() { feed.usagePollingEnabled.toggle() }
    @objc private func clearAllSessions() { feed.clearAll() }
    @objc private func refreshFeed() { feed.refresh(); feed.refreshUsage() }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
    @objc private func setModeActivity() { feed.menuBarMode = .activity }
    @objc private func setModeUsage() { feed.menuBarMode = .usage }
    @objc private func toggleNotifyOnDone() { feed.notifyOnDone.toggle() }
    @objc private func setSurfaceMenuBar() { feed.surface = .menuBar }
    @objc private func setSurfaceWindow() { feed.surface = .window }

    /// Quit and reopen. A short-lived helper reopens after this instance exits, so
    /// the single-instance guard doesn't reject the new copy.
    /// The static "Focus session" category plus one per live ask.
    private func registerCategories(for pending: [AskRequest]) {
        let focus = UNNotificationAction(identifier: NotificationConfig.focusAction,
                                         title: "Focus session", options: [.foreground])
        let attention = UNNotificationCategory(identifier: NotificationConfig.attentionCategory,
                                               actions: [focus], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current()
            .setNotificationCategories(Set([attention] + AskInbox.categories(for: pending)))
    }

    /// One banner per pending ask. The request id is the notification id, so a
    /// rescan that sees the same file again replaces the banner rather than
    /// stacking a second copy of the same question.
    private func postAskNotifications(_ pending: [AskRequest]) {
        for req in pending {
            let text = AskInbox.notificationText(req)
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            content.categoryIdentifier = AskInbox.categoryID(req.req)
            // There is a process blocked on this one, on a deadline. That is
            // what .timeSensitive is for, and it is the difference between an
            // answer and a five-minute stall behind a Focus filter.
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["req": req.req, "cwd": req.cwd, "sessionId": req.sessionId]
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: AskInbox.notificationID(req.req),
                                      content: content, trigger: nil)
            ) { error in
                // A refused authorization makes add() fail silently, which looks
                // identical to a banner the user simply didn't see. Say which.
                if let error {
                    NSLog("claude spinner: ask banner not posted — \(error.localizedDescription)")
                } else {
                    NSLog("claude spinner: ask banner posted for \(req.req)")
                }
            }
        }
        requestAttention()
    }

    /// Bounce the Dock icon. Only the `window` surface has one to bounce -- the
    /// app is `LSUIElement` and sits at `.accessory` behind the menu bar, where
    /// there is no Dock tile and this is deliberately a no-op.
    private func requestAttention() {
        guard NSApp.activationPolicy() == .regular else { return }
        NSApp.requestUserAttention(.criticalRequest)
    }

    /// A tap on one of an ask's option buttons. Nothing here can assume the hook
    /// is still listening: it may have hit its deadline while the banner sat on
    /// screen, in which case `answer` reports false and Claude Code is already
    /// showing its own prompt in the terminal.
    private func handleAskResponse(_ response: UNNotificationResponse) -> Bool {
        guard let parsed = AskInbox.parseAction(response.actionIdentifier),
              let req = asks.pending.first(where: { $0.req == parsed.req })
        else { return false }

        if parsed.choice == "focus" {
            // Going to the session is itself an answer: it says "I'll deal with
            // this in the terminal", so release the hook instead of leaving it
            // blocked until the deadline.
            asks.answer(req, with: .passthrough)
            SessionLauncher.focus(host: "", pid: nil, cwd: req.cwd)
            return true
        }
        guard let answer = AskInbox.answer(for: parsed.choice, in: req) else { return false }
        if !asks.answer(req, with: answer) {
            NSLog("claude spinner: ask \(req.req) expired before it was answered")
        }
        asks.rescan()
        return true
    }

    /// Handle a tap on the attention notification (or its "Focus session" button):
    /// bring the session's host window to the front. Both the default tap and the
    /// explicit action focus — the button just makes the affordance visible.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if handleAskResponse(response) {
            completionHandler()
            return
        }
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
                if let h5 = feed.usageFiveHourPct, let title = feed.usageMenuBarTitle {
                    // Pulse the % when it crosses the red threshold so an imminent
                    // rate limit catches the eye even with nothing running.
                    Text(title)
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
        .accessibilityLabel({
            // In usage mode the visible title is the usage readout, not the
            // activity word — VoiceOver should read what's on screen.
            if feed.menuBarMode == .usage, let pct = feed.usageFiveHourPct {
                let left = feed.usageFiveHourResetRelative.map { ", resets in \($0)" } ?? ""
                return "Claude spinner, 5 hour limit \(pct) percent\(left)"
            }
            return feed.menuBarBody.isEmpty ? "Claude spinner, idle"
                                            : "Claude spinner, \(feed.menuBarBody)"
        }())
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
