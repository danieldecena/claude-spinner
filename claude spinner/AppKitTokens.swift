// App Kit colours for SwiftUI. Generated from tokens.json by app_build.py; do not edit.
// Prefer system colours where one exists (Color.accentColor, .primary, .secondary);
// these cover the rest and match Artifact Kit on the web.
import SwiftUI

#if canImport(UIKit)
import UIKit
private func dyn(_ l: (Double, Double, Double, Double), _ d: (Double, Double, Double, Double)) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: d.0, green: d.1, blue: d.2, alpha: d.3) : UIColor(red: l.0, green: l.1, blue: l.2, alpha: l.3) })
}
#else
import AppKit
private func dyn(_ l: (Double, Double, Double, Double), _ d: (Double, Double, Double, Double)) -> Color {
    Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: d.0, green: d.1, blue: d.2, alpha: d.3) : NSColor(red: l.0, green: l.1, blue: l.2, alpha: l.3) })
}
#endif

public extension Color {
    enum Kit {
        /// Screen background behind grouped content: systemGroupedBackground.
        public static let ground = dyn((0.949, 0.949, 0.969, 1.00), (0.000, 0.000, 0.000, 1.00))
        /// Panels, cards, list rows, sheets: secondarySystemGroupedBackground.
        public static let surface = dyn((1.000, 1.000, 1.000, 1.00), (0.110, 0.110, 0.118, 1.00))
        /// Segmented tracks, neutral badges, thumbnail placeholders: systemGray5 / tertiary grouped.
        public static let surfaceSunk = dyn((0.898, 0.898, 0.918, 1.00), (0.173, 0.173, 0.180, 1.00))
        /// Primary text and icons (label). 13:1 or better on ground and surface, just under 12.8:1 on surface-sunk in dar
        public static let ink = dyn((0.114, 0.114, 0.122, 1.00), (0.961, 0.961, 0.969, 1.00))
        /// Secondary text (secondaryLabel, opaque). 4.7:1 or better on ground, surface and surface-sunk.
        public static let inkSoft = dyn((0.388, 0.388, 0.400, 1.00), (0.596, 0.596, 0.616, 1.00))
        /// Tertiary text (tertiaryLabel, translucent): absences ("not recorded"), panel titles, the empty-slot outline. U
        public static let inkFaint = dyn((0.235, 0.235, 0.263, 0.30), (0.922, 0.922, 0.961, 0.30))
        /// Hairline dividers (separator). Decorative only: never the only boundary of a control.
        public static let hair = dyn((0.820, 0.820, 0.839, 1.00), (0.220, 0.220, 0.227, 1.00))
        /// Outlines of interactive controls (3:1 or better on ground and surface).
        public static let edge = dyn((0.525, 0.525, 0.545, 1.00), (0.486, 0.486, 0.502, 1.00))
        /// The system fill: gray buttons, off filter pills, hover and pressed rows. Translucent.
        public static let fill = dyn((0.463, 0.463, 0.502, 0.12), (0.463, 0.463, 0.502, 0.24))
        /// The system fill one step stronger: hover on gray buttons.
        public static let fillHover = dyn((0.463, 0.463, 0.502, 0.20), (0.463, 0.463, 0.502, 0.32))
        /// The app's accent: Color.accentColor, System Blue by default; follows the person's accent on the Mac. Tints, se
        public static let accent = dyn((0.000, 0.478, 1.000, 1.00), (0.039, 0.518, 1.000, 1.00))
        /// Filled (borderedProminent) buttons: the accent stepped 20% toward black so white text passes 4.5:1.
        public static let accentFill = dyn((0.000, 0.384, 0.800, 1.00), (0.031, 0.416, 0.800, 1.00))
        /// Text and symbols on accent-fill.
        public static let onAccent = dyn((1.000, 1.000, 1.000, 1.00), (1.000, 1.000, 1.000, 1.00))
        /// Translucent accent tint: tinted (bordered) buttons, selected pills and rows.
        public static let accentWash = dyn((0.000, 0.478, 1.000, 0.12), (0.039, 0.518, 1.000, 0.20))
        /// Accent text on accent-wash or on any ground (4.5:1 or better): links, plain buttons.
        public static let accentInk = dyn((0.000, 0.345, 0.725, 1.00), (0.365, 0.671, 1.000, 1.00))
        /// Status: done, healthy, synced (system green, text step). Always with a word or glyph.
        public static let ok = dyn((0.125, 0.475, 0.212, 1.00), (0.188, 0.859, 0.357, 1.00))
        /// Fill behind ok text.
        public static let okWash = dyn((0.863, 0.957, 0.882, 1.00), (0.122, 0.271, 0.153, 1.00))
        /// Status: needs a look soon, stale, partial (system orange, text step).
        public static let warn = dyn((0.780, 0.200, 0.000, 1.00), (1.000, 0.702, 0.251, 1.00))
        /// Fill behind warn text.
        public static let warnWash = dyn((0.988, 0.925, 0.827, 1.00), (0.318, 0.224, 0.078, 1.00))
        /// Warn text on warn-wash (4.6:1 or better).
        public static let warnInk = dyn((0.780, 0.200, 0.000, 1.00), (1.000, 0.702, 0.251, 1.00))
        /// Status: failed, over limit, destructive (system red, text step). Never a high value on a data scale.
        public static let bad = dyn((0.800, 0.000, 0.078, 1.00), (1.000, 0.416, 0.388, 1.00))
        /// Fill behind bad text.
        public static let badWash = dyn((0.988, 0.867, 0.859, 1.00), (0.318, 0.141, 0.122, 1.00))
        /// Data scale, lowest step (calm, low urgency, slow bite). Marks only, 3:1 on surface. Claude Spinner's urgency r
        public static let heat1 = dyn((0.247, 0.561, 0.278, 1.00), (0.549, 0.851, 0.549, 1.00))
        /// Data scale, second step. Marks only.
        public static let heat2 = dyn((0.561, 0.478, 0.110, 1.00), (0.941, 0.851, 0.420, 1.00))
        /// Data scale, third step. Marks only.
        public static let heat3 = dyn((0.753, 0.416, 0.071, 1.00), (1.000, 0.698, 0.361, 1.00))
        /// Data scale, top step (hottest, prime, most urgent). A scale value, not an error: pair with the scale's legend,
        public static let heat4 = dyn((0.788, 0.275, 0.231, 1.00), (1.000, 0.478, 0.439, 1.00))
        /// Chart series 1, Apple mint. First, and the colour of a single-series chart. Light is the HIG Increased Contras
        public static let series1 = dyn((0.000, 0.522, 0.459, 1.00), (0.000, 0.855, 0.765, 1.00))
        /// Chart series 2, Apple purple. Light is the HIG Increased Contrast value (4.4:1 or better on surface), dark the
        public static let series2 = dyn((0.690, 0.184, 0.761, 1.00), (0.859, 0.204, 0.949, 1.00))
        /// Chart series 3, Apple blue. Reads as the accent; avoid beside accent controls. Light is the HIG Increased Cont
        public static let series3 = dyn((0.118, 0.431, 0.957, 1.00), (0.000, 0.569, 1.000, 1.00))
        /// Chart series 4, Apple pink. Light is the HIG Increased Contrast value (4.4:1 or better on surface), dark the d
        public static let series4 = dyn((0.906, 0.071, 0.302, 1.00), (1.000, 0.216, 0.373, 1.00))
        /// Chart series 5, Apple orange. Light is the HIG Increased Contrast value (4.4:1 or better on surface), dark the
        public static let series5 = dyn((0.773, 0.325, 0.000, 1.00), (1.000, 0.573, 0.188, 1.00))
        /// Emphasis charts: every mark that is not the point (systemGray3). Under 3:1, so those marks carry a value label
        public static let chartBase = dyn((0.780, 0.780, 0.800, 1.00), (0.282, 0.282, 0.290, 1.00))
        /// A lone series with nothing to single out (systemGray); hover on grey marks.
        public static let chartMid = dyn((0.557, 0.557, 0.576, 1.00), (0.557, 0.557, 0.576, 1.00))
        /// Highlighted text in purple, as in Apple Notes: bold, on hl-purple-wash (4.5:1 or better in both themes). Also 
        public static let hlPurple = dyn((0.537, 0.267, 0.671, 1.00), (0.855, 0.561, 1.000, 1.00))
        /// The system purple at 10% (16% dark), translucent: highlight and purple tinted-button fill.
        public static let hlPurpleWash = dyn((0.686, 0.322, 0.871, 0.10), (0.749, 0.353, 0.949, 0.16))
        /// Filled purple button: 4.5:1 or better under hl-purple-on in both themes.
        public static let hlPurpleFill = dyn((0.549, 0.259, 0.698, 1.00), (0.600, 0.282, 0.761, 1.00))
        /// Label on hl-purple-fill.
        public static let hlPurpleOn = dyn((1.000, 1.000, 1.000, 1.00), (1.000, 1.000, 1.000, 1.00))
        /// Highlighted text in pink, as in Apple Notes: bold, on hl-pink-wash (4.5:1 or better in both themes). Also the 
        public static let hlPink = dyn((0.776, 0.055, 0.255, 1.00), (1.000, 0.392, 0.510, 1.00))
        /// The system pink at 10% (16% dark), translucent: highlight and pink tinted-button fill.
        public static let hlPinkWash = dyn((1.000, 0.176, 0.333, 0.10), (1.000, 0.216, 0.373, 0.16))
        /// Filled pink button: 4.5:1 or better under hl-pink-on in both themes.
        public static let hlPinkFill = dyn((0.800, 0.141, 0.267, 1.00), (0.800, 0.173, 0.298, 1.00))
        /// Label on hl-pink-fill.
        public static let hlPinkOn = dyn((1.000, 1.000, 1.000, 1.00), (1.000, 1.000, 1.000, 1.00))
        /// Highlighted text in orange, as in Apple Notes: bold, on hl-orange-wash (4.5:1 or better in both themes). Also 
        public static let hlOrange = dyn((0.780, 0.200, 0.000, 1.00), (1.000, 0.702, 0.251, 1.00))
        /// The system orange at 10% (16% dark), translucent: highlight and orange tinted-button fill.
        public static let hlOrangeWash = dyn((1.000, 0.584, 0.000, 0.10), (1.000, 0.624, 0.039, 0.16))
        /// Filled orange button: 4.5:1 or better under hl-orange-on in both themes.
        public static let hlOrangeFill = dyn((1.000, 0.584, 0.000, 1.00), (1.000, 0.624, 0.039, 1.00))
        /// Label on hl-orange-fill.
        public static let hlOrangeOn = dyn((0.114, 0.114, 0.122, 1.00), (0.114, 0.114, 0.122, 1.00))
        /// Highlighted text in mint, as in Apple Notes: bold, on hl-mint-wash (4.5:1 or better in both themes). Also the 
        public static let hlMint = dyn((0.043, 0.467, 0.443, 1.00), (0.400, 0.831, 0.812, 1.00))
        /// The system mint at 10% (16% dark), translucent: highlight and mint tinted-button fill.
        public static let hlMintWash = dyn((0.000, 0.780, 0.745, 0.10), (0.388, 0.902, 0.886, 0.16))
        /// Filled mint button: 4.5:1 or better under hl-mint-on in both themes.
        public static let hlMintFill = dyn((0.000, 0.780, 0.745, 1.00), (0.388, 0.902, 0.886, 1.00))
        /// Label on hl-mint-fill.
        public static let hlMintOn = dyn((0.114, 0.114, 0.122, 1.00), (0.114, 0.114, 0.122, 1.00))
        /// Highlighted text in blue, as in Apple Notes: bold, on hl-blue-wash (4.5:1 or better in both themes). Also the 
        public static let hlBlue = dyn((0.000, 0.251, 0.867, 1.00), (0.259, 0.616, 1.000, 1.00))
        /// The system blue at 10% (16% dark), translucent: highlight and blue tinted-button fill.
        public static let hlBlueWash = dyn((0.000, 0.478, 1.000, 0.10), (0.039, 0.518, 1.000, 0.16))
        /// Filled blue button: 4.5:1 or better under hl-blue-on in both themes.
        public static let hlBlueFill = dyn((0.000, 0.384, 0.800, 1.00), (0.031, 0.416, 0.800, 1.00))
        /// Label on hl-blue-fill.
        public static let hlBlueOn = dyn((1.000, 1.000, 1.000, 1.00), (1.000, 1.000, 1.000, 1.00))
        /// The system purple: what a purple tinted button mixes its hover wash from.
        public static let hlPurpleTint = dyn((0.686, 0.322, 0.871, 1.00), (0.749, 0.353, 0.949, 1.00))
        /// Web stand-in for Liquid Glass (with a 16px blur): toolbars and controls floating over content. In SwiftUI use 
        public static let glass = dyn((1.000, 1.000, 1.000, 0.55), (0.173, 0.173, 0.180, 0.55))
        /// The 0.5px inner edge of glass.
        public static let glassEdge = dyn((1.000, 1.000, 1.000, 0.70), (1.000, 1.000, 1.000, 0.14))
        /// Toasts and hints over content, white text.
        public static let scrim = dyn((0.000, 0.000, 0.000, 0.80), (0.000, 0.000, 0.000, 0.78))
        /// Music's fixed red. Sidebar glyphs, text actions, the active queue icon, and CTA button fills. NOT the transpor
        public static let musicAccent = dyn((0.980, 0.137, 0.231, 1.00), (0.980, 0.180, 0.282, 1.00))
        /// Accent TEXT, where 4.5:1 must hold. Music itself uses the raw accent here and fails AA; this is the one delibe
        public static let musicAccentInk = dyn((0.918, 0.024, 0.137, 1.00), (0.980, 0.220, 0.318, 1.00))
        /// Selected row fill while the window is key, with a white label. Not derivable from the accent: stepping the acc
        public static let musicSelect = dyn((0.863, 0.071, 0.161, 1.00), (0.800, 0.075, 0.176, 1.00))
        /// Selected row fill when another app is frontmost. The normal state for a monitor app, so do not treat it as an 
        public static let musicSelectInactive = dyn((0.863, 0.863, 0.863, 1.00), (0.275, 0.275, 0.275, 1.00))
        /// SIDEBAR selection while the window is key. NEUTRAL, not music-select: Music's sidebar never draws the red, key
        public static let musicSidebarSelect = dyn((0.000, 0.000, 0.000, 0.09), (1.000, 1.000, 1.000, 0.13))
        /// SIDEBAR selection while another app is frontmost. Measured: dark #333333 over #252525 and #1F1F1F over #101010
        public static let musicSidebarSelectInactive = dyn((0.000, 0.000, 0.000, 0.04), (1.000, 1.000, 1.000, 0.06))
        /// Row hover fill. Drawn as a rounded inset pill, 40pt in from each side of the row and ~6pt radius, never a full
        public static let musicHover = dyn((0.941, 0.941, 0.941, 1.00), (0.173, 0.173, 0.176, 1.00))
        /// The transport button (Play). Maximum contrast against the ground, so it inverts with appearance. Never the acc
        public static let musicPrimary = dyn((0.055, 0.055, 0.055, 1.00), (0.953, 0.953, 0.953, 1.00))
        /// Label on music-primary. Inverts with it.
        public static let onMusicPrimary = dyn((1.000, 1.000, 1.000, 1.00), (0.000, 0.000, 0.000, 1.00))
        /// Label on a selected row, white in both themes.
        public static let onMusicSelect = dyn((1.000, 1.000, 1.000, 1.00), (1.000, 1.000, 1.000, 1.00))
        /// The Music window's content ground. Flat, not graded and not tinted by artwork. Differs from App Kit's iOS-deri
        public static let groundWindow = dyn((1.000, 1.000, 1.000, 1.00), (0.122, 0.122, 0.125, 1.00))
        /// Primary text in the Music variant. Deliberately softer than App Kit's ink in both directions; do not inherit i
        public static let musicInk = dyn((0.153, 0.153, 0.153, 1.00), (0.867, 0.867, 0.867, 1.00))
        /// Secondary text. Music measures #808080 in light, which is only 3.95:1 on white; #767676 is the first grey that
        public static let musicInkSoft = dyn((0.463, 0.463, 0.463, 1.00), (0.604, 0.604, 0.604, 1.00))
        /// The favorited star, both values MEASURED: #FFD700 dark (album-detail-unfocused-dark.png, 11.74:1) and #FFCC00 
        public static let musicStar = dyn((1.000, 0.800, 0.000, 1.00), (1.000, 0.843, 0.000, 1.00))
        /// The transport button when the window is NOT key. Dark is MEASURED #2F2F30 from album-transport-inactive-dark.p
        public static let musicPrimaryInactive = dyn((0.925, 0.925, 0.925, 1.00), (0.184, 0.184, 0.188, 1.00))
        /// Ink on the MiniPlayer capsule, which is a glass surface and not the window ground. Dark is MEASURED #FFFFFF on
        public static let onMusicGlass = dyn((0.000, 0.000, 0.000, 1.00), (1.000, 1.000, 1.000, 1.00))
        /// Secondary text on music-hover or music-select-inactive. music-ink-soft reaches only 3.31:1 on the inactive sel
        public static let musicInkSoftOnFill = dyn((0.373, 0.373, 0.373, 1.00), (0.706, 0.706, 0.706, 1.00))
    }
}

public extension Font {
    enum Kit {
        /// Health-style figure: SF Pro Rounded, bold.
        public static let figure = Font.system(.largeTitle, design: .rounded).bold()
        public static let figureSmall = Font.system(.title2, design: .rounded).bold()
        /// Long reading: SF Pro Text body; add .lineSpacing(6).
        public static let script = Font.body
        /// Mono uppercase key above a value.
        public static let label = Font.caption2.monospaced().weight(.semibold)
        /// Panel title: uppercased, .tracking(CGFloat.Kit.trackingPanelTitle), .foregroundStyle(.tertiary).
        public static let panelTitle = Font.caption2.weight(.semibold)
        /// Eyebrow: uppercased, .tracking(CGFloat.Kit.trackingEyebrow).
        public static let eyebrow = Font.caption2.monospaced().weight(.semibold)
        /// Fact value, beside a .caption label in .secondary.
        public static let factValue = Font.system(.caption, design: .monospaced)
    }
}

public extension CGFloat {
    enum Kit {
        /// State outlines: act and live panels, the empty slot, a selected filter pill, an attention tile. SwiftUI: .stro
        public static let strokeOutline: CGFloat = 1.5
        /// The empty slot: 6 on, 4 off, in ink-faint. SwiftUI: StrokeStyle(lineWidth: 1.5, dash: [6, 4]).
        public static let strokeDash: [CGFloat] = [6, 4]
        public static let trackingDisplay: CGFloat = -0.5
        public static let trackingPanelTitle: CGFloat = 0.8
        public static let trackingEyebrow: CGFloat = 1.2
    }
}
