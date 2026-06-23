# Graph Report - .  (2026-06-23)

## Corpus Check
- Corpus is ~13,887 words - fits in a single context window. You may not need a graph.

## Summary
- 35 nodes · 38 edges · 6 communities (4 shown, 2 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Unit & UI Tests|Unit & UI Tests]]
- [[_COMMUNITY_App & UI Layer|App & UI Layer]]
- [[_COMMUNITY_Test Lifecycle|Test Lifecycle]]
- [[_COMMUNITY_Item List View|Item List View]]
- [[_COMMUNITY_Item Data Model|Item Data Model]]
- [[_COMMUNITY_App Entry & Container|App Entry & Container]]

## God Nodes (most connected - your core abstractions)
1. `claude_spinnerTests` - 6 edges
2. `claude_spinnerUITests` - 6 edges
3. `ContentView` - 5 edges
4. `claude_spinnerApp` - 4 edges
5. `SwiftData` - 3 edges
6. `NavigationViewWrapper` - 3 edges
7. `Item` - 3 edges
8. `SwiftUI` - 2 edges
9. `Item` - 2 edges
10. `Date` - 2 edges

## Surprising Connections (you probably didn't know these)
- `ContentView` --references--> `View`  [EXTRACTED]
  claude spinner/ContentView.swift →   _Bridges community 3 → community 1_
- `claude_spinnerUITests` --inherits--> `XCTestCase`  [EXTRACTED]
  claude spinnerUITests/claude_spinnerUITests.swift →   _Bridges community 2 → community 0_

## Import Cycles
- None detected.

## Communities (6 total, 2 thin omitted)

### Community 1 - "App & UI Layer"
Cohesion: 0.33
Nodes (5): NavigationViewWrapper, Content, SwiftData, SwiftUI, View

### Community 3 - "Item List View"
Cohesion: 0.50
Nodes (3): ContentView, IndexSet, Item

### Community 4 - "Item Data Model"
Cohesion: 0.50
Nodes (3): Item, Date, Foundation

### Community 5 - "App Entry & Container"
Cohesion: 0.50
Nodes (4): App, claude_spinnerApp, ModelContainer, Scene

## Knowledge Gaps
- **5 isolated node(s):** `IndexSet`, `Content`, `Foundation`, `ModelContainer`, `Scene`
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `SwiftData` connect `App & UI Layer` to `Item Data Model`?**
  _High betweenness centrality (0.174) - this node is a cross-community bridge._
- **Why does `ContentView` connect `Item List View` to `App & UI Layer`?**
  _High betweenness centrality (0.133) - this node is a cross-community bridge._
- **Why does `claude_spinnerApp` connect `App Entry & Container` to `App & UI Layer`?**
  _High betweenness centrality (0.096) - this node is a cross-community bridge._
- **What connects `IndexSet`, `Content`, `Foundation` to the rest of the system?**
  _5 weakly-connected nodes found - possible documentation gaps or missing edges._