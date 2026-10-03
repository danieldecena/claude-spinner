// Slice 8: the four Music components as SwiftUI, compiled against the REAL
// generated tokens.
//
// Every component in App Kit before this one shipped a SwiftUI recipe in its
// README; Shelf, HeroCard, TrackList and MiniPlayer shipped CSS only, which is
// backwards for a system whose stated target is SwiftUI apps on the Mac.
//
// This file is the source of those recipes, not a copy of them: the README
// snippets are lifted from here AFTER it compiles and renders, so a recipe that
// does not build cannot reach the docs.
//
//   swiftc build/source/music-components-spike.swift swift/AppKit.swift -o <bin>
//   <bin> --selfshot <out.png>
//
// It compiles against swift/AppKit.swift rather than redeclaring the measured
// values, which also makes it the first check that the generated Swift builds.

import AppKit
import SwiftUI

// MARK: - ArtworkCard

/// Square artwork over a caption block of CONSTANT height. Card height minus
/// card width measured 37pt at every width, so the caption does not scale.
struct ArtworkCard: View {
    let art: Color
    let title: String
    let subtitle: String
    var width: CGFloat = 188
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) { card }
            .buttonStyle(.plain)
            // One label for the pair: VoiceOver should say "Episode 740,
            // Soulection playgroup", not read two separate static texts.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(subtitle)")
            .accessibilityAddTraits(.isButton)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(art)
                .frame(width: width, height: width)   // square
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.footnote).foregroundStyle(Color.Kit.musicInk)
                    .lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(Color.Kit.musicInkSoft)
                    .lineLimit(1)
            }
            .padding(.top, 6)
            .frame(height: 37, alignment: .top)       // constant, not derived
        }
        .frame(width: width)
    }
}

// MARK: - HeroCard

/// Full-bleed artwork at 3:4 with the caption INSIDE the card. The ratio is the
/// spec; the size is not.
struct HeroCard: View {
    let art: LinearGradient
    let eyebrow: String
    let title: String
    var width: CGFloat = 258
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) { card }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(eyebrow), \(title)")
            .accessibilityAddTraits(.isButton)
    }

    private var card: some View {
        ZStack(alignment: .bottomLeading) {
            art
            // The scrim is ours, not Music's: Music's heroes are commissioned to
            // carry white text, an adopting app's artwork is not.
            LinearGradient(stops: [
                .init(color: .black.opacity(0.78), location: 0.00),
                .init(color: .black.opacity(0.70), location: 0.16),
                .init(color: .black.opacity(0.30), location: 0.34),
                .init(color: .black.opacity(0.00), location: 0.56),
            ], startPoint: .bottom, endPoint: .top)
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).font(.caption2).foregroundStyle(.white.opacity(0.82))
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(18)
        }
        .frame(width: width, height: width / 0.75)    // 3:4
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Shelf

/// A horizontally scrolling row. The shelf owns the GAP; the card owns its size.
struct Shelf<Content: View>: View {
    let title: String
    var compact: Bool = false
    /// Leading inset of the shelf's header and first card: 34pt from the content
    /// edge, 6pt outside the 40pt line TrackList's pill starts on. Measured in
    /// Music at 980 and 1588pt (music-capture.md, 2026-10-02).
    var inset: CGFloat = 34
    /// The see-all chevron, drawn only when there IS a see-all: Music's Home
    /// shows it after "Recently Played" and not after "Top Picks for You"
    /// (music-capture.md, Page title). A chevron with nowhere to go promises a
    /// page that does not exist.
    var onMore: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title).font(.title3.bold()).foregroundStyle(Color.Kit.musicInk)
                if let onMore {
                    Button(action: onMore) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.Kit.musicInkSoft)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all \(title)")
                }
            }
            .padding(.leading, inset)
            ScrollView(.horizontal, showsIndicators: false) {
                // 20pt wide, 16pt once the window narrows. A breakpoint, not a scale.
                HStack(alignment: .top, spacing: compact ? 16 : 20) { content }
                    .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)       // the snap Music has
            // The cards rest 34pt in, 6pt outside TrackList's pill, but scroll
            // all the way under the edge -- which contentMargins gives and a
            // plain .padding does not.
            .contentMargins(.horizontal, inset, for: .scrollContent)
        }
    }
}

// MARK: - TrackList

struct Track: Identifiable {
    let id: Int
    let starred: Bool
    let art: Color
    let song: String
    let artist: String
    let time: String
}

/// Music's song table. The highlight is a rounded inset PILL, not a row fill.
struct TrackList: View {
    let rows: [Track]
    @Binding var selection: Int?
    var onPlay: (Int) -> Void = { _ in }
    /// Not a parameter: no adopter remembered to pass it, so every one rendered
    /// as active forever. macOS already knows whether the window is key.
    @Environment(\.appearsActive) private var appearsActive
    private var windowInactive: Bool { !appearsActive }
    @FocusState private var focused: Bool

    private func fill(_ id: Int) -> Color {
        guard id == selection else { return .clear }
        return windowInactive ? Color.Kit.musicSelectInactive : Color.Kit.musicSelect
    }
    private func ink(_ id: Int, soft: Bool) -> Color {
        if id == selection && !windowInactive { return Color.Kit.onMusicSelect }
        if id == selection && windowInactive { return soft ? Color.Kit.musicInkSoftOnFill : Color.Kit.musicInk }
        return soft ? Color.Kit.musicInkSoft : Color.Kit.musicInk
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { r in
                HStack(spacing: 12) {
                    Text(r.starred ? "\u{2605}" : " ")
                        .foregroundStyle(Color.Kit.musicStar).frame(width: 16)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(r.art).frame(width: 40, height: 40)
                    Text(r.song).foregroundStyle(ink(r.id, soft: false))
                    Spacer()
                    Text(r.artist).foregroundStyle(ink(r.id, soft: true))
                        .frame(width: 160, alignment: .leading)
                    Text(r.time).foregroundStyle(ink(r.id, soft: true))
                        .monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                // The pill fills the row between hairlines: 55pt inside a 56pt row.
                .frame(height: 55)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill(r.id)))
                .padding(.horizontal, 40)   // the measured inset
                .frame(height: 56)
                .contentShape(Rectangle())
                .onTapGesture { selection = r.id }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(r.id == selection ? [.isSelected] : [])
            }
        }
        // One focus target for the whole table, with the arrows moving inside
        // it -- a row-per-tab-stop would be 200 stops on a real playlist. This
        // mirrors the keyboard model the web component documents.
        .focusable()
        .focused($focused)
        .onMoveCommand { direction in
            guard let current = selection ?? rows.first?.id,
                  let i = rows.firstIndex(where: { $0.id == current }) else { return }
            switch direction {
            case .up:   selection = rows[max(0, i - 1)].id
            case .down: selection = rows[min(rows.count - 1, i + 1)].id
            default:    break
            }
        }
        // Return plays, which is what Music does.
        .onKeyPress(.return) {
            if let s = selection { onPlay(s); return .handled }
            return .ignored
        }
        .accessibilityLabel("Tracks")
    }
}

// MARK: - SidebarList

/// A Mac source list with Music's NEUTRAL selection: a translucent grey, not the
/// red. A focused `.listStyle(.sidebar)` draws the system accent instead
/// (measured: #007AFF, and `.tint()` does not override it), which Music never
/// does, so the rows draw their own background and the List supplies only the
/// vibrancy. The List is given NO `selection:` binding for the same reason: its
/// native highlight would draw under ours and the two stack (measured: dark
/// `#555456` against Music's `#434346`). The cost is that the List no longer
/// handles arrow keys, so a real app should add `.onMoveCommand` if it needs them.
struct SidebarRow: Identifiable {
    let id: String
    let label: String
    let symbol: String
}

struct SidebarList: View {
    let sections: [(String?, [SidebarRow])]
    @Binding var selection: String?
    /// Not a parameter: no adopter remembered to pass it, so every one rendered
    /// as active forever. macOS already knows whether the window is key.
    @Environment(\.appearsActive) private var appearsActive
    private var windowInactive: Bool { !appearsActive }

    private func fill(_ id: String) -> Color {
        guard id == selection else { return .clear }
        return windowInactive ? Color.Kit.musicSidebarSelectInactive : Color.Kit.musicSidebarSelect
    }
    /// Music dims EVERY label in an inactive window, not only the selected
    /// row's (music-capture.md, Inactive sidebar ink).
    private func ink(_ id: String) -> Color {
        if id == selection { return windowInactive ? Color.Kit.musicInk : Color.Kit.onMusicGlass }
        return windowInactive ? Color.Kit.musicSidebarInkInactive : Color.Kit.musicInk
    }
    /// Music tints the SYMBOL and leaves the label in normal ink, which is why
    /// the row is built from Text and Image rather than a Label: a
    /// .foregroundStyle on a Label would tint both. In an inactive window every
    /// symbol loses the accent, not only the selected one.
    private func glyph(_ id: String) -> Color {
        if id == selection && windowInactive { return Color.Kit.musicInkSoftOnFill }
        return windowInactive ? Color.Kit.musicSidebarGlyphInactive : Color.Kit.musicAccent
    }

    var body: some View {
        List {
            ForEach(sections.indices, id: \.self) { i in
                let (header, rows) = sections[i]
                Section {
                    ForEach(rows) { r in
                        HStack(spacing: 8) {
                            Image(systemName: r.symbol)
                                .foregroundStyle(glyph(r.id)).frame(width: 16)
                                .accessibilityHidden(true)   // decorative; the label names the row
                            Text(r.label).foregroundStyle(ink(r.id))
                            Spacer(minLength: 0)
                        }
                        .frame(height: 32)                       // measured
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill(r.id)))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)          // let the row's own fill show
                        .contentShape(Rectangle())
                        .onTapGesture { selection = r.id }
                        .accessibilityAddTraits(r.id == selection ? .isSelected : [])
                    }
                } header: {
                    if let header { Text(header).foregroundStyle(Color.Kit.musicInkSoft) }
                }
            }
        }
        .listStyle(.sidebar)        // the vibrancy; set NO background
        .scrollContentBackground(.hidden)
    }
}

// MARK: - MiniPlayer

/// The floating transport capsule: 700x54, stadium radius, real material.
struct MiniPlayer: View {
    let art: Color
    let title: String
    let subtitle: String
    var progress: Double = 0.54
    var playing: Bool = true
    var shuffle: Bool = false
    var repeatOn: Bool = false
    var onPlayPause: () -> Void = {}
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}
    var onShuffle: () -> Void = {}
    var onRepeat: () -> Void = {}
    var onLyrics: () -> Void = {}
    var onQueue: () -> Void = {}
    var onVolume: () -> Void = {}

    private func control(_ symbol: String, _ label: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: symbol).foregroundStyle(Color.Kit.onMusicGlass)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// A toggle says whether it is ON, which a plain button cannot. The accent
    /// is the only visual signal otherwise, so without this the state is
    /// colour-only and invisible to VoiceOver.
    private func toggle(_ symbol: String, _ label: String, _ on: Bool,
                        _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: symbol)
                .foregroundStyle(on ? Color.Kit.musicAccent : Color.Kit.onMusicGlass)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    var body: some View {
        HStack(spacing: 9) {
            // Hit frames, not glyphs, set the layout: 28pt buttons, Play 36,
            // frames 9-157 from the capsule edge, then 9pt to the artwork.
            HStack(spacing: 0) {
                toggle("shuffle", "Shuffle", shuffle, onShuffle).frame(width: 28, height: 28)
                control("backward.fill", "Previous", onPrevious).frame(width: 28, height: 28)
                control(playing ? "pause.fill" : "play.fill", playing ? "Pause" : "Play", onPlayPause)
                    .frame(width: 36, height: 36)
                control("forward.fill", "Next", onNext).frame(width: 28, height: 28)
                toggle("repeat", "Repeat", repeatOn, onRepeat).frame(width: 28, height: 28)
            }

            ZStack(alignment: .bottom) {
                Color.clear.frame(height: 54)   // the line belongs to the CAPSULE's edge
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(art).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.Kit.onMusicGlass)
                        Text(subtitle).font(.footnote).foregroundStyle(Color.Kit.onMusicGlass)
                    }
                    Spacer()
                }
                .frame(height: 54)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.Kit.onMusicGlass.opacity(0.26))
                        Capsule().fill(Color.Kit.onMusicGlass.opacity(0.79))
                            .frame(width: g.size.width * progress)
                    }
                }
                .frame(height: 2).padding(.bottom, 2)
                .accessibilityElement()
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(Int(progress * 100)) percent")
            }

            // 36pt hit frames 1pt apart: Music's now-playing group (and so the
            // progress line) ends where these frames begin, not at their glyphs.
            HStack(spacing: 1) {
                control("quote.bubble", "Lyrics", onLyrics).frame(width: 36, height: 36)
                control("list.bullet", "Queue", onQueue).frame(width: 36, height: 36)
                control("speaker.wave.2.fill", "Volume", onVolume).frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 700, height: 54)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

