import SwiftUI

// The session repo's graphify knowledge graph, as a card in the detail pane.
//
// What a graph is worth at card size is the shape of the codebase, not the
// graph drawing: 2,099 nodes in a 300pt box is a hairball. So the card answers
// the two questions a drawing would be read for anyway -- how big is it, and
// where is the code concentrated -- as a size line and a bar per community.

/// What `graphify-out/graph.json` says about a repo. Parsed off the main thread;
/// every field is what the file actually carried, and a file that does not parse
/// produces nil rather than a summary of zeroes.
struct GraphSummary: Equatable {
    let nodes: Int
    let links: Int
    /// The commit the graph was built from, as recorded in the file.
    let builtAtCommit: String?
    /// Communities by size, largest first.
    let communities: [(name: String, count: Int)]

    static func == (a: GraphSummary, b: GraphSummary) -> Bool {
        a.nodes == b.nodes && a.links == b.links && a.builtAtCommit == b.builtAtCommit
            && a.communities.map(\.name) == b.communities.map(\.name)
            && a.communities.map(\.count) == b.communities.map(\.count)
    }

    /// nil for anything that is not a graph: no file, unreadable, not JSON, or
    /// JSON without the two arrays. An empty graph is not a missing one, so a
    /// file holding zero nodes still summarises.
    static func parse(_ data: Data, topCommunities: Int = 6) -> GraphSummary? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = root["nodes"] as? [[String: Any]],
              let links = root["links"] as? [[String: Any]]
        else { return nil }

        var counts: [String: Int] = [:]
        for node in nodes {
            // A node with no community is not counted into one: the bars say
            // "this much of the code is this cluster", and an "unknown" bar the
            // size of everything unclustered would say nothing.
            guard let name = node["community_name"] as? String, !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        let top = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(topCommunities)
            .map { (name: $0.key, count: $0.value) }

        return GraphSummary(nodes: nodes.count, links: links.count,
                            builtAtCommit: root["built_at_commit"] as? String,
                            communities: Array(top))
    }

    /// Where the graph lives for a repo. `graphify` writes `graphify-out/` at the
    /// root it was run from, so this wants the repo root, not a session's cwd: a
    /// session started in a subfolder has no graph beside it and the card would
    /// stay empty for a repo that has one.
    static func path(forRepo root: String) -> String { root + "/graphify-out/graph.json" }
}

struct GraphifyCard: View {
    /// The repo root, falling back to the session's cwd before git has answered.
    let root: String
    /// The repo's current HEAD, so the card can say the graph is behind it.
    /// Nil when it could not be read -- which prints nothing, never "current".
    let headSHA: String?

    @State private var summary: GraphSummary?

    var body: some View {
        // One structure, not an if/else of two: a card that swapped its whole
        // body when the summary arrived changed view identity, which re-ran the
        // task -- and the guard added to stop that re-read also stopped the read
        // for the next session's repo.
        //
        // Drawn only for a repo that has a graph: a card saying "no graph here"
        // on every other session is a permanent instruction nobody asked for.
        Group {
            if let summary {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CardTitle("Graph")
                        Spacer(minLength: 4)
                        Text(sizeLabel(summary)).font(.ui(10)).foregroundStyle(Color.label)
                    }
                    if let staleness = staleness(summary) {
                        Text(staleness).font(.ui(10)).foregroundStyle(Color.attention)
                    }
                    ForEach(summary.communities, id: \.name) { community in
                        bar(community, of: summary.communities.first?.count ?? 1)
                    }
                }
                .detailCard()
            }
        }
        .task(id: root) { await load() }
    }

    private func sizeLabel(_ summary: GraphSummary) -> String {
        "\(summary.nodes.formatted()) nodes · \(summary.links.formatted()) edges"
    }

    /// Only ever says the graph is behind, never that it is current: the file
    /// records one commit, and matching it means the graph was built there, not
    /// that nothing has changed in the working tree since.
    private func staleness(_ summary: GraphSummary) -> String? {
        guard let head = headSHA, let built = summary.builtAtCommit, built != head else { return nil }
        return "Built at \(built.prefix(7)), not at \(head.prefix(7)) — graphify update ."
    }

    /// One community. The bar is a share of the largest, which is what makes the
    /// sizes comparable at a glance; the count is direct-labelled because there
    /// are six of them, not sixty, and no axis is drawn.
    private func bar(_ community: (name: String, count: Int), of largest: Int) -> some View {
        HStack(spacing: 8) {
            Text(community.name).font(.ui(10)).lineLimit(1)
                .frame(width: 118, alignment: .leading)
                .help(community.name)
            GeometryReader { geometry in
                let share = largest > 0 ? Double(community.count) / Double(largest) : 0
                // One hue for every bar: these are names, not magnitudes of one
                // thing, so a value ramp across them would invent an order the
                // data does not have.
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.series1)
                    .frame(width: max(2, geometry.size.width * share), height: 8)
                    .frame(height: geometry.size.height, alignment: .center)
            }
            .frame(height: 12)
            Text(community.count.formatted()).font(.figure(10)).foregroundStyle(Color.label)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(community.name), \(community.count) nodes")
    }

    /// Read once per repo. The file is a couple of megabytes, so it is parsed off
    /// the main thread and not re-read on a timer: a graph changes when
    /// `graphify update` runs, not while you watch it.
    private func load() async {
        // Cleared first: a new repo must not show the last one's
        // graph while this one is being read, and a repo without a graph has to
        // clear the card rather than inherit one.
        summary = nil
        let path = GraphSummary.path(forRepo: root)
        let read = await Task.detached(priority: .utility) { () -> GraphSummary? in
            guard let data = FileManager.default.contents(atPath: path) else { return nil }
            return GraphSummary.parse(data)
        }.value
        // `.task(id:)` cancels this call when the directory changes, but the
        // detached read it is waiting on is not cancelled and returns normally.
        // Without the guard a slower read of the previous repo lands after the
        // new one and leaves the wrong repo's graph on the card.
        guard !Task.isCancelled else { return }
        summary = read
    }
}
