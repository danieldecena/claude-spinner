# Wireframes

Every surface of the app as a text wireframe, each region labelled with the
SwiftUI struct that draws it and the file it lives in. Read this before a UI
change instead of browsing the sources; then open only the struct you need.

- Labels are `Struct` (`File.swift`). Line numbers are left out on purpose: they
  rot with the next edit. `grep -n "struct Name"` finds the current one.
- Numbers in the boxes are the literal values in the code (pt). A value marked
  *derived* is arithmetic on those, not something the code states.
- A change that moves, adds or resizes a region updates this file in the same
  commit. A wireframe that disagrees with the app is worse than none.

Mapped at `2fc14cc` (2026-10-02); Home updated for #10. Paths are relative to `claude spinner/`.

## Shell — the main window

`AppDelegate.showMainWindow()` (`claude_spinnerApp.swift`) builds an `NSWindow`
with a hidden titlebar, an `NSVisualEffectView` (`.sidebar`), and
`WindowContentView` (`WindowContentView.swift`) inside it.

```
+-----------------------------------------------------------------------------+
| [sidebar.left]  WindowToolbar (glass, padding 10)  ActionBar (session picked)|
| clear over sidebar | opaque Color.pane over detail only                     |
+------------------+----------------------------------------------------------+
| sidebar  w250    | detail  (maxWidth/maxHeight .infinity, Color.pane)       |
| FULL HEIGHT, no  |                                                          |
| card: the window |   routed by selection:                                   |
| material shows   |     "home:dashboard"   -> HomeDashboard                  |
| through, under a |     "appkit:showcase"  -> AppKitShowcase                 |
| pane-coloured    |     pinned tag         -> PinnedProjectDetail            |
| veil             |     session id         -> SessionDetail                  |
| (SidebarScrim)   |     nothing -> ContentUnavailableView                    |
| top pad 40       |                                                          |
| NotificationsNotice                                                         |
| SetupBanner (no hooks)                                                      |
| NewSessionBar  Sessions [+]                                                 |
| SessionSidebar (List, .plain, small, no selection binding)                  |
|   [grid] Home                                                               |
|   [palette] App Kit                                                         |
|   <~ sessions>                                                              |
|   Pinned                                                                    |
|     [pin] Job Search  N live                                                |
|     [pin] Plans       N live                                                |
|   <project sections>                                                        |
+------------------+----------------------------------------------------------+
```

- Window: default 900 x 560, minimum 620 x 360, autosave `SpinnerWindow`
  (`Constants`, `FeedWatcher.swift`). Opens on Home.
- Sidebar (Music look, 2026-10-03). Selectable rows (Home, App Kit, pinned
  projects, sessions) use `.sidebarRow(_:selection:)` (`SidebarRowChrome`): a
  neutral rounded fill (`Color.Kit.musicSidebarSelect`, `...Inactive` when the
  window is not key) plus semibold, drawn by the row itself. The List has **no
  `selection:` binding** because its native highlight is the system accent and
  `.tint` does not override it; the arrow keys are `.onKeyPress` on the focusable
  List (`selectableIDs`). Row symbols are `SidebarGlyph` in `Color.Kit.musicAccent`
  (a mark colour only, dimmed when inactive); names and counts are SF `.ui`, not
  Menlo (the status glyph itself stays mono). Other rows use `.denseRow()`.
  A project section is `SectionHeader` (title, "N sessions · tokens"), then
  session rows, then subagent `childRow`s, a "N finished" toggle, then
  `tasksRows` (a `checklist` header, up to 5 TASKS.md titles with a `circle`
  symbol). `SidebarScrim` is the pane colour at 0.62 (dark) / 0.94 (light) over
  the window's `.sidebar` material: bare, the dark ground measured #575757 and
  secondary labels 3.1:1; veiled, 0.14 and 6.7:1.
- **`PaneFit`** (`WindowContentView.swift`) wraps Home, Session and Pinned: the
  pane lays out at its natural height and, when that is taller than the window,
  is drawn smaller with `scaleEffect`, down to 0.55, then scrolls. While scaled
  it lays out at `width / scale`, so **a scaled pane is wider than it looks** and
  can pick a different TileGrid column count than the visible width suggests.

## Home — `HomeDashboard` (`HomeDashboard.swift`)

Plain `VStack(spacing: 12)`, padding 20. Every card is full width except Mail
and Calendar, which share a two-column TileGrid.

```
+---------------------------------------------------------------+
| OverviewStrip  (StatCards.swift)            -> see Session R3 |
+---------------------------------------------------------------+
| sessionsCard   SESSIONS  n                                    |
| [glyph w14] name / project ......  GoalFlag status ctx w70 wall w56 |
| ...one row per session, click opens it                        |
+---------------------------------------------------------------+
| tasksCard      OPEN TASKS · N across M projects               |
| project header + link, then up to 5 titles, per project       |
+------------------------------+ +------------------------------+
| MailCard (MailCard.swift)    | | CalendarCard                 |
|  updated 3m [Draft replies]  | |  (CalendarCard.swift)        |
|             [Refresh]        | |  Now / Next                  |
| [Urgent][This week][CI][Fin] | |  rest of today, 5 rows,      |
|  4 x StatColumn, spacing 8   | |    then "+N more"            |
| summary / accounts lines     | |  all-day line, tomorrow line |
+------------------------------+ +------------------------------+
  TileGrid(minimum: 330, spacing: 12, maxColumns: 2): side by side
  while each keeps 330, stacked below that; one height per row.
```

- Mail's buttons wrap under the title at the narrowest width. Draft replies is
  disabled with a reason when the response-drafter skill is missing.
- Calendar reads EventKit on appear, on `EKEventStoreChanged`, on activate and on
  Refresh, with no timer. Its logic lives in `CalendarSnapshot` and
  `CalendarFormat`.

## Session — `SessionDetail` (`WindowContentView.swift`)

`VStack(spacing: 12)`, padding 20: `header` (attention summary, if any), one
`AskCard` per pending question, then `TileGrid(minimum: 180, spacing: 12)`.
**Every grid child is `.tileSpan(.max)`**, so the grid is really a column of
full-width rows; the side-by-side layout inside R1 and R2 is plain `HStack`.

`AskCard` draws one question (or a permission) with one button per option.
When `ask.isForm` it draws `AskFormCard` instead:

```text
AskFormCard (WindowContentView.swift) -- drawn by AskCard when ask.isForm
+--------------------------------------------------------------+
| 2 questions                                    ui(11) attention
|                                                               |
| Pick a color?                                  ui(13) semibold|
| [ (o) Red                                                   ] |
| [ ( ) Green                                                 ] |
|                                                    spacing 10 |
| Pick toppings?                                                |
| Pick any that apply                            ui(10) label   |
| [ [x] Ham                                                   ] |
| [ [ ] Olives                                                ] |
|                                                               |
| [ Send answers ]  [ Answer in terminal ]                      |
+--------------------------------------------------------------+
padding 12, corner radius 8, attention 8% fill (same as AskCard).
Send answers is disabled until every question has a pick.
After sending: one line, "Answered: Red / Ham".
```

```
R1 +-------------------------------------------+  +----------------------+
   | ConversationCard            (flexible)    |  | SkillsCard    w380   |
   |  TranscriptCard                           |  |  Skills  ShortcutChips|
   |   you asked / claude said (fills height)  |  |  Superpowers chips   |
   |   ran ... (tools line)                    |  |  Git  GitButtons     |
   |  [ReplyBox r10 ............] [ConfigCard] |  |       git skill chips|
   |  Notice                                   |  |  pick line           |
   +-------------------------------------------+  +----------------------+
R2 +----------------------+  +-------------------------------------------+
   | GitGraphCard  w360   |  | .detailCard()  VStack(spacing 14)          |
   |  HISTORY lane graph  |  |  GitCard(framed: false)                   |
   |  row 17, lane 12,    |  |   branch line                             |
   |  max 8 lanes         |  |   ChipFlow of GitStatusRow: tree remote   |
   |                      |  |     pr checks ci, then read ages          |
   |                      |  |  AutomationToggles                        |
   |                      |  |   [Merge PR][Push main][Commit][Open PR]  |
   |                      |  |   [Auto-fix CI & comments]                |
   +----------------------+  +-------------------------------------------+
R3 +--------------------------------------------------------------------+
   | OverviewStrip.including(session)  USAGE                            |
   | SessionRings(ctx cache time) | 5h 7d RingMetric | cpu mem disk     |
   |   one HStack(spacing 8), never wraps; Ring 52x52, Divider h80      |
   +--------------------------------------------------------------------+
R4 +--------------------------------------------------------------------+
   | GraphifyCard  (GraphifyCard.swift)  GRAPH  size, staleness         |
   | name w118 [bar h8 ..........] count w34   one row per community    |
   |   measures zero without graphify-out/graph.json; the grid skips it |
   +--------------------------------------------------------------------+
```

Narrow windows: **nothing stacks.** The 380 and 360 side columns are fixed, so
only `ConversationCard` and the Git card shrink; past that, `PaneFit` scales.

## Pinned project — `PinnedProjectDetail` (`PinnedProjectDetail.swift`)

Pinned rows come from `PinnedProject.all` = Job Search, Plans
(`PinnedProjects.swift`). An expanded artifact replaces the whole pane with
`ArtifactFullView` (`ArtifactView.swift`).

```
Job Search                                  (SF 26 bold, outside PaneFit)
summary line                                (.ui(12))
+--------------------------------------------------+ +------------------+
| VStack(spacing 24)  -- no TileGrid, no stretched | | rail     w300    |
| rows: sections take their own height             | | .detailCard()    |
|                                                  | | Instructions  >  |
| Top picks                                        | | Context       >  |
| [New session][Apply next job][artifact heroes..] | | Folder        >  |
|   HeroMetrics 170 x 227 (3:4), scrolls sideways  | | Memory        >  |
| [ prompt field  (card fill, hairline)          ] | | Scheduled     >  |
| [ workflowCard                         full w  ] | | railRow: icon16, |
| [ jobPipelineCard  flex ][ scoutStatusCard w260] | | items indent 24  |
|   liveCard "RUNNING NOW" when a run no step      | |                  |
|   started is live                                | |                  |
| [recentApplicationsCard w320][ Tasks (ground)  ] | |                  |
| Recent sessions   SessionShelf (ground)          | |                  |
| Skills            chips (ground)                 | |                  |
| Workflows         chips (ground)                 | |                  |
+--------------------------------------------------+ +------------------+
   AnyLayout: HStack(top, 16) when the pane is >= 808 wide, else VStack(16)
   with the rail full width under the page. padding 20
```

Cards (`.detailCard()`) are kept only for controls and read-outs that are a unit:
Workflow, Job pipeline, Scout daemon, Recent applications, Running now. Tasks, Recent
sessions, Skills and Workflows are sections on the pane's own ground.

| Section | Draws | Shown when |
|---|---|---|
| `topPicks` "Top picks" | `LaunchHeroCard` New session, `LaunchHeroCard` quick start, then one `ArtifactHeroCard` per artifact (`TopPicks.swift`, `ArtifactView.swift`), all `HeroMetrics` 170 x 227; the prompt field under them | always |
| `workflowCard` WORKFLOW: steps, each with its runs boxed under it | full width | the project has steps |
| `jobPipelineCard` + `scoutStatusCard` | flex + 260 | Job Search only |
| `liveCard` RUNNING NOW: `AskCard`s + `ConversationCard` per run | full width | an unclaimed run is live |
| `recentApplicationsCard` last 5 applied, w320, beside `tasksSection` | | Job Search only |
| `tasksSection` Tasks `.ui(15)` bold + "N open - M done" beside it, TASKS.md, 5 titles | ground | always |
| `recentSection` Recent sessions: `SessionShelf` (`SessionShelf.swift`), `SessionTile`s 124pt square art over a 50pt caption; the tile is the button, "Resume" shows on hover or focus | ground | always |
| `discoveryCard("Skills")` chips, `LazyVGrid(.adaptive(minimum: 120))` | ground | the project reaches skills |
| `discoveryCard("Workflows")` | ground | the project has workflows |
| `discoveryCard("Artifacts")` error line | ground | an artifact is unreadable |

Rail switch: `railBesideMinWidth` = 40 + (2 x 220 + 12) + 16 + 300 = 808, the
narrowest pane that keeps the rail beside a two-column grid. It is tested on the
pane's visible width, not `width / scale`, because stacking makes the page taller,
which shrinks the scale and would flip it back. Seen 2026-10-02: at the 900 default
(pane 630) the rail sits under the grid and the scaled grid draws 3 columns; at
1528 the rail is beside it.

## App Kit — `AppKitShowcase` (`AppKitShowcase.swift`)

Components in `AppKitMusicComponents.swift`, tokens in `AppKitTokens.swift`
(generated from `~/developer/app-kit`; do not edit either by hand).

```
+-----------+---------------------------------------------------------+
| SidebarList| ScrollView  VStack(spacing 28), vertical padding 28    |
| w200       | Color.Kit.groundWindow                                  |
| Search     | Top Picks for You          Shelf                       |
| Home       | [HeroCard w258 3:4 r14] [HeroCard] [HeroCard] ->        |
| New        | Recently Played            Shelf                       |
| Radio      | [ArtworkCard w188][...][...][...] ->  spacing 20 (16)  |
| LIBRARY    | Playlist                                                |
|  Songs     | TrackList  rows h56, art 40, cols 160 / 48              |
|  Albums    | (80 clear spacer)                                       |
|  Artists   |      +---- MiniPlayer 700 x 54, floats bottom, pad 19 --+|
+-----------+---------------------------------------------------------+
```

## Popover — `MenuContentView` (`MenuContentView.swift`)

Left-click on the status item. Fixed width `feed.panelWidth` (470, clamped to at
least 360 with a 16 screen margin), opaque `Color.panelGround`.

```
+--------------------------------------------------+
| UsageHeader   5h reset countdown / limit notice  |
| SessionBreakdownBars  StackedBar   (if sessions) |
| NotificationsNotice                              |
| ScrollView  maxHeight 240   (TimelineView 0.1s)  |
|  PanelSectionHeader  project                     |
|  SessionRow  name w70-132 | context | ...        |  RowLayout.columns
|  ...                                             |
|  (none: "No active sessions" / SetupBanner)      |
| UsageFooter  UsageGauge 5h | 7d | TrendGauge     |
|              Sparkline (5h history)              |
+--------------------------------------------------+
```

## Primitives and tokens

There is **no spacing or radius token file**. These values are written inline
at each call site; match them rather than inventing new ones.

| Value | Used for |
|---|---|
| 20 | pane padding, sidebar outer padding |
| 12 | card-to-card spacing |
| 16 | card inner padding (`.detailCard()`), pinned grid-to-rail spacing |
| 14 | card radius (continuous); spacing inside a combined card |
| 10 | toolbar padding, ReplyBox / artifact radius |
| 8 | AskCard radius, input radius, stat-column spacing |
| 6 | chip spacing (`ChipFlow`, discovery grid), small input radius |

| Primitive | File | What it controls |
|---|---|---|
| `TileGrid` (`Layout`) | `WindowContentView.swift` | columns = `min(maxColumns 3, (w + spacing) / (minimum + spacing))`; rows as tall as their tallest card; a card that doesn't fit starts the next row; `fillsRows` stretches the last card; spare height goes to the last row; zero-height cards are skipped |
| `.tileSpan(_:)` / `TileSpan` | `WindowContentView.swift` | columns a card takes, default 1, clamped |
| `.detailCard()` / `DetailCard` | `WindowContentView.swift` | the card: padding 16, fills, `Color.card`, radius 14, no border or shadow |
| `OptionalCard` | `WindowContentView.swift` | `.detailCard()` only when `framed` |
| `CardTitle` | `WindowContentView.swift` | card heading: `.ui(10)` semibold, uppercase, tracking 0.8, `Color.label` |
| `SectionTitle` | `PinnedProjectDetail.swift` | the pinned page's card heading: `.ui(15)` bold, sentence case, primary ink; with `opens:` it is a button and draws a `chevron.right` in `Color.Kit.musicAccent` (Tasks, when more than 5 are open). `CardTitle` stays for the session pane |
| `ChipFlow` (`Layout`) | `WindowContentView.swift` | wrapping chips at natural width, spacing 6 |
| `StatSection` | `WindowContentView.swift` | titled key/value `Grid`, mono values |
| `PaneFit` | `WindowContentView.swift` | scale-to-fit, floor 0.55 |
| `Notice` / `NoticeKind` | `Notice.swift` | inline info and error lines |
| `GlowRing` / `.suggestedGlow` | `WindowContentView.swift` | pulsing ring round the suggested button |
| `Ring`, `RingMetric`, `RingSegment` | `StatCards.swift` | 52x52 ring, line 5, hover detail at least 140 wide |
| `Sparkline`, `ContextMeter`, `ContextChart` | `WindowContentView.swift` | chart primitives |
| `extension Color` | `claude_spinnerApp.swift` | `card` (white / #1C1C1E), `pane` (#F2F2F7 / black), `label`, `claude`, `attention`, `usageAmber`, `series1`, `identity*` |
| `extension Font` | `claude_spinnerApp.swift` | `ui(_)` SF with a size remap (10->11, 11->12, 12->13), `claudeMono` Menlo, `figure` rounded |
| `Color.Kit`, `Font.Kit`, `CGFloat.Kit` | `AppKitTokens.swift` | App Kit palette, type and strokes (generated) |

## Before you change the layout

1. Find the region here; open only its struct.
2. Check which width rule it lives under: fixed column, flexible `HStack` side,
   or `TileGrid` span. A change to one does not reflow the others.
3. Remember `PaneFit`: test at the minimum window (620 x 360) and at a tall
   pane, where the scaled layout width is larger than what you see.
4. Update the box and table here in the same commit.
5. Then the review in `CLAUDE.md` § Design review: capture first, critique
   second.
