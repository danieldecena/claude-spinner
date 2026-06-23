//
//  claude_spinnerApp.swift
//  claude spinner
//
//  Menubar mirror of the live Claude Code session feed.
//

import SwiftUI

@main
struct claude_spinnerApp: App {
    @State private var feed = FeedWatcher()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(feed: feed)
        } label: {
            MenuBarLabel(feed: feed)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The status-bar glyph: an animated braille spinner while any session works, a
/// warning mark when one needs attention, an idle star otherwise. Plain Text
/// bound to the watcher's timer-driven `menuBarText` — a TimelineView here can
/// collapse the status item to zero size and make the icon invisible.
struct MenuBarLabel: View {
    let feed: FeedWatcher

    var body: some View {
        // A single (concatenated) Text — MenuBarExtra renders this fully, unlike a
        // multi-view HStack label which drops everything after the first element.
        // Concatenation lets the glyph use a larger font; opacity pulse animates it
        // without changing width (so the item never jitters).
        let color = feed.menuBarActive ? Color.claude : Color.claudeDim
        let glyphColor = feed.menuBarActive ? color.opacity(feed.glyphPulse) : color
        let glyph = Text(feed.menuBarGlyph)
            .font(.claudeMono(17))
            .foregroundColor(glyphColor)
        let bodyText = Text(feed.menuBarBody.isEmpty ? "" : " \(feed.menuBarBody)")
            .font(.claudeMono(13))
            .foregroundColor(color)
        return glyph + bodyText
    }
}

/// Claude's pulsing asterisk spinner glyphs, indexed by wall-clock time so every
/// view that draws the spinner stays in phase.
enum Spinner {
    static let frames = ["✶", "✸", "✹", "✺", "✻", "✽", "✻", "✺", "✹", "✸"]

    static func frame(at date: Date) -> String {
        let i = Int((date.timeIntervalSinceReferenceDate * 10).rounded(.down))
        return frames[((i % frames.count) + frames.count) % frames.count]
    }
}

extension Color {
    /// Claude's burnt-orange accent, matching the terminal spinner.
    static let claude = Color(red: 0.76, green: 0.42, blue: 0.24)
    /// Muted variant for the idle/done line — colored, but quieter than active.
    static let claudeDim = Color(red: 0.76, green: 0.42, blue: 0.24).opacity(0.65)
}

extension Font {
    /// The terminal font Claude Code is shown in (the user's Ghostty font-family).
    /// Always-installed Menlo; Font.custom falls back to the system font if absent.
    static let claudeFontName = "Menlo"

    static func claudeMono(_ size: CGFloat) -> Font {
        .custom(claudeFontName, size: size)
    }
}
