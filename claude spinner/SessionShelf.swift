//
//  SessionShelf.swift
//
//  Recent sessions as a horizontal shelf, after App Kit's `ArtworkCard`/`Shelf`
//  (AppKitMusicComponents.swift): square art over a caption block of constant
//  height, the whole tile as the one control, and "Resume" shown only while the
//  tile is hovered or focused. Not `Shelf` itself: its header is a title3 and an
//  inset of its own, and this page already draws its section header.
//

import SwiftUI

/// A row of past sessions the user can resume. `resume` gets the session id.
struct SessionShelf: View {
    let sessions: [RecentSession]
    /// The project's symbol, drawn on every tile: all of one project's sessions
    /// share it, so the tile says which project and the caption says which session.
    let symbol: String
    let resume: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: SessionTile.gap) {
                ForEach(sessions) { session in
                    SessionTile(session: session, symbol: symbol) { resume(session.id) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }
}

struct SessionTile: View {
    let session: RecentSession
    let symbol: String
    let action: () -> Void

    static let width: CGFloat = 124
    static let gap: CGFloat = 12
    /// Constant, as the kit's caption is: a long name takes two lines, a short one
    /// leaves the second empty, and the tiles never differ in height.
    static let captionHeight: CGFloat = 50

    /// What VoiceOver reads for the tile: the session, how long ago, and what a
    /// press does. A pure function so the wording is tested without drawing.
    nonisolated static func spoken(headline: String, age: String) -> String {
        "\(headline), \(age)"
    }

    @State private var hovering = false

    private var age: String {
        session.when.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    var body: some View {
        Button(action: action) { Face(session: session, symbol: symbol, age: age, hovering: hovering) }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spoken(headline: session.headline, age: age))
            .accessibilityHint("Resume")
            .accessibilityAddTraits(.isButton)
            .help(session.lastPrompt ?? session.headline)
    }

    /// The look, in its own view so it can read the focus of the button around it.
    private struct Face: View {
        let session: RecentSession
        let symbol: String
        let age: String
        let hovering: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [Color.Kit.surfaceSunk, Color.card],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(Color.label)
                    if hovering || focused {
                        // The resume cue appears with the pointer or the keyboard
                        // and is never the only way to resume: the tile is the button.
                        VStack {
                            Spacer()
                            Text("Resume").font(.ui(10)).fontWeight(.semibold)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.regularMaterial, in: Capsule())
                                .padding(.bottom, 6)
                        }
                    }
                }
                .frame(width: SessionTile.width, height: SessionTile.width)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(focused ? Color.primary.opacity(0.7) : .clear, lineWidth: 2)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.headline).font(.ui(11)).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(age).font(.ui(10)).foregroundStyle(Color.label).lineLimit(1)
                }
                .padding(.top, 6)
                .frame(width: SessionTile.width, height: SessionTile.captionHeight, alignment: .topLeading)
            }
            .frame(width: SessionTile.width)
            .contentShape(Rectangle())
        }
    }
}
