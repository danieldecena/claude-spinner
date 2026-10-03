//
//  TopPicks.swift
//
//  The pinned page's first row, after App Kit's `HeroCard` (AppKitMusicComponents):
//  tall 3:4 cards with the caption inside, over a dark scrim. A launch card uses
//  the project's own tile as its art; an artifact card (ArtifactView.swift) uses
//  its live page. Every card in the row is the same size by construction.
//

import SwiftUI

enum HeroMetrics {
    /// Narrower than the kit's 258: the page is dense, and a row of six should
    /// still show most of itself beside the rail.
    static let width: CGFloat = 170
    static let height: CGFloat = width / 0.75
    static let gap: CGFloat = 12
}

/// A fixed graphite, in both appearances: the card's text is white, so its art is
/// dark in light mode too.
struct HeroGraphite: View {
    var body: some View {
        LinearGradient(colors: [Color(white: 0.24), Color(white: 0.11)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The kit's scrim: ours, because an adopting app's artwork is not commissioned
/// to carry white text.
struct HeroScrim: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.78), location: 0.00),
            .init(color: .black.opacity(0.70), location: 0.16),
            .init(color: .black.opacity(0.30), location: 0.34),
            .init(color: .black.opacity(0.00), location: 0.56),
        ], startPoint: .bottom, endPoint: .top)
    }
}

/// A button that starts something: the project's symbol on graphite, an eyebrow
/// and a title inside the card.
struct LaunchHeroCard: View {
    let symbol: String
    let eyebrow: String
    let title: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                HeroGraphite()
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 40)
                HeroScrim()
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrow).font(.ui(10)).foregroundStyle(.white.opacity(0.82)).lineLimit(1)
                        .truncationMode(.middle)
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                .padding(14)
            }
            .frame(width: HeroMetrics.width, height: HeroMetrics.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .help(hint)
    }
}
