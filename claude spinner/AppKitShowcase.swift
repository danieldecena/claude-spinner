import SwiftUI

// A trial tab for App Kit (~/developer/app-kit): its Music components, laid out
// the way the spike's own window lays them out, inside this window's detail pane.
//
// AppKitTokens.swift and AppKitMusicComponents.swift are byte-identical copies
// of app-kit's swift/AppKit.swift and lines 1-386 of
// build/source/music-components-spike.swift, taken at app-kit 7cb1cd2. Do not
// edit them here: change app-kit's generator, rebuild, and copy again. `cmp`
// against those two sources says whether they have drifted.
//
// The spike's SpikeView is NOT copied. It wraps everything in a
// NavigationSplitView, and this window already is one, so SidebarList sits in a
// plain fixed-width column here instead. The cost: outside a split view's
// sidebar column `.listStyle(.sidebar)` gets no desktop vibrancy, so the
// sidebar's material is not what an adopting app would show. Judge colour,
// spacing and state here; judge the sidebar material in a real split view.

/// The sidebar row that selects the showcase. Its own prefix, so
/// `resolveSelection` can tell it from a session id, Home and a pinned tag.
enum AppKitTab {
    static let tag = "appkit:showcase"
    static func isTag(_ tag: String?) -> Bool { tag == Self.tag }
}

struct AppKitShowcase: View {
    @State private var selection: Int? = 2
    @State private var navSelection: String? = "Home"

    private let tracks = [
        Track(id: 1, starred: true,  art: Color(red: 0.79, green: 0.28, blue: 0.18), song: "Nights",       artist: "Frank Ocean", time: "5:07"),
        Track(id: 2, starred: false, art: Color(red: 0.18, green: 0.43, blue: 0.79), song: "Solo",         artist: "Frank Ocean", time: "4:17"),
        Track(id: 3, starred: false, art: Color(red: 0.18, green: 0.60, blue: 0.43), song: "Pink + White", artist: "Frank Ocean", time: "3:04"),
    ]
    private let nav: [(String?, [SidebarRow])] = [
        (nil, [SidebarRow(id: "Search", label: "Search", symbol: "magnifyingglass"),
               SidebarRow(id: "Home", label: "Home", symbol: "house.fill"),
               SidebarRow(id: "New", label: "New", symbol: "square.grid.2x2"),
               SidebarRow(id: "Radio", label: "Radio", symbol: "dot.radiowaves.left.and.right")]),
        ("Library", [SidebarRow(id: "Songs", label: "Songs", symbol: "music.note"),
                     SidebarRow(id: "Albums", label: "Albums", symbol: "square.stack"),
                     SidebarRow(id: "Artists", label: "Artists", symbol: "music.mic")]),
    ]

    private func grad(_ a: Color, _ b: Color) -> LinearGradient {
        LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarList(sections: nav, selection: $navSelection)
                .frame(width: 200)
            Divider()
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Shelf(title: "Top Picks for You") {
                            HeroCard(art: grad(Color(red: 1, green: 0.37, blue: 0.23), Color(red: 1, green: 0.70, blue: 0.0)),
                                     eyebrow: "Made for You", title: "Daniel Decena's Station")
                            HeroCard(art: grad(Color(red: 0.17, green: 0.33, blue: 0.39), Color(red: 0.06, green: 0.13, blue: 0.15)),
                                     eyebrow: "Updated Playlist", title: "New Music Mix")
                            HeroCard(art: grad(Color(red: 0.56, green: 0.18, blue: 0.89), Color(red: 0.29, green: 0.0, blue: 0.88)),
                                     eyebrow: "Station", title: "Soulection Radio")
                        }
                        Shelf(title: "Recently Played") {
                            ArtworkCard(art: Color(red: 0.76, green: 0.23, blue: 0.23), title: "Episode 740", subtitle: "Soulection playgroup")
                            ArtworkCard(art: Color(red: 0.55, green: 0.33, blue: 0.70), title: "Episode 741", subtitle: "Soulection playgroup")
                            ArtworkCard(art: Color(red: 0.20, green: 0.49, blue: 0.45), title: "Episode 743", subtitle: "Soulection playgroup")
                            ArtworkCard(art: Color(red: 0.78, green: 0.29, blue: 0.11), title: "Episode 745", subtitle: "Soulection playgroup")
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Playlist").font(.title3.bold())
                                .foregroundStyle(Color.Kit.musicInk).padding(.leading, 40)
                            TrackList(rows: tracks, selection: $selection)
                        }
                        // Room for the floating MiniPlayer, so the last row is never under it.
                        Color.clear.frame(height: 80)
                    }
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                MiniPlayer(art: Color(red: 0.79, green: 0.28, blue: 0.18),
                           title: "Nights", subtitle: "Frank Ocean \u{2014} Blonde", shuffle: true)
                    .padding(.bottom, 19)
            }
            .background(Color.Kit.groundWindow)
        }
    }
}
