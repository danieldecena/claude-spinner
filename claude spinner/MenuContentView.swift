//
//  MenuContentView.swift
//  claude spinner
//
//  The panel shown when the menubar icon is clicked: one live row per session.
//

import SwiftUI
import AppKit
import Combine

struct MenuContentView: View {
    @ObservedObject var feed: FeedWatcher
    /// In a popover the panel states its own width, because the popover sizes
    /// itself to its content. In a resizable window that is backwards — the window
    /// owns the width and the panel must fill it, or the two fight: the pinned
    /// content forces the window back to `panelWidth` every time it is dragged.
    var fillsWidth = false
    @StateObject private var install = InstallState()
    @ObservedObject private var asks = AskInbox.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            UsageHeader(feed: feed)

            // Denied authorization makes every banner a no-op that still reports
            // success, so the panel has to say it out loud. macOS has no API to
            // grant this — only System Settings can.
            NotificationsNotice()

            if feed.sessions.isEmpty {
                if feed.isSetupInstalled {
                    Text("No active sessions")
                        .font(.claudeMono(11)).foregroundStyle(Color.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 12)
                } else {
                    // Nothing will ever appear until the hooks are wired up — offer a
                    // one-click install instead of a silent empty panel.
                    SetupBanner(feed: feed, install: install, compact: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 12)
                }
            } else {
                // One ticking clock drives every row's spinner + timer in phase.
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    // Resolve the row list once per tick — displayItems does a full
                    // sort + grouping, so evaluating it per-row (ForEach, last, and
                    // the animation value) would repeat that work every 100ms.
                    let sections = FeedWatcher.projectSections(
                        feed.displayItems, asked: Set(asks.pending.map(\.sessionId)))
                    // Flattened once: the columns must be sized across the WHOLE
                    // panel, not per section, or they jag at every heading.
                    let rows = sections.flatMap(\.items)
                    let columns = RowLayout.columns(
                        statusLabels: rows.map(\.session.statusLabel),
                        models: rows.map { feed.modelDisplay(for: $0.session).map(FeedWatcher.modelFamily) ?? "" },
                        panelWidth: feed.panelWidth)
                    let list = VStack(spacing: 0) {
                        ForEach(sections) { section in
                            PanelSectionHeader(section: section)
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                SessionRow(feed: feed, item: item, now: context.date, columns: columns)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                // Dividers separate rows inside a section; the next
                                // heading is what separates one section from the next.
                                if index < section.items.count - 1 && section.items[index + 1].depth == 0 {
                                    Divider().opacity(0.5)
                                }
                            }
                        }
                    }
                    ScrollView(.vertical, showsIndicators: true) {
                        list
                    }
                    .frame(maxHeight: fillsWidth ? .infinity : Constants.panelListMaxHeight)
                    // Animate only when the set/order of rows changes (keyed by ids),
                    // not on every 0.1s spinner tick.
                    .animation(.easeInOut(duration: 0.2), value: rows.map(\.id))
                }
                // Only pad the top; the last row's own vertical padding plus the
                // footer's divider/padding already separate it from the footer, so
                // a bottom pad here just opened a dead gap.
                .padding(.top, 6)
            }

            UsageFooter(feed: feed)
        }
        // Two modifiers, not one: there is no `frame(width:maxWidth:)` overload, and
        // writing it as one silently failed to compile while a stale binary kept
        // answering the resize probes.
        .frame(width: fillsWidth ? nil : feed.panelWidth)
        // `alignment: .top` pins content to the window's top edge when the window
        // is taller than the content wants (dragged tall, or a stale remembered
        // frame). Without it NSHostingView centers the shorter content vertically,
        // leaving equal dead space above and below instead of just below.
        .frame(maxWidth: fillsWidth ? .infinity : nil,
               maxHeight: fillsWidth ? .infinity : nil,
               alignment: .top)
        // An opaque ground in the popover. Over the default vibrant material the
        // row text took on the wallpaper behind it, and every contrast figure in
        // `Color.Ink` assumes a solid ground. The window keeps its own background.
        .background {
            if !fillsWidth { Color.panelGround.ignoresSafeArea() }
        }
        // No visible Quit button; ⌘Q still terminates while the panel is open.
        // `.allowsHitTesting(false)` keeps this invisible button from swallowing a
        // row click as a quit while its ⌘Q keyboard shortcut still fires.
        .background(
            Button("") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        )
    }
}

/// Panel header: the 5-hour reset countdown (or the limit notice, which takes
/// precedence) pinned above the session list so it reads first. A 1s clock keeps
/// the "in …" countdown live-ticking.
struct UsageHeader: View {
    @ObservedObject var feed: FeedWatcher

    /// The usage line only exists once there's something to say about the account.
    private var hasUsageLine: Bool {
        feed.hasUsage && (feed.usageNotice != nil || feed.usageFiveHourReset != nil)
    }

    var body: some View {
        if hasUsageLine || feed.totalContextTokens != nil {
            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 0) {
                        if hasUsageLine {
                            Group {
                                if let notice = feed.usageNotice {
                                    Text("\(Image(systemName: NoticeKind.error.symbol)) \(notice)")
                                        .foregroundStyle(NoticeKind.error.tint)
                                        .help(feed.usageNoticeDetail)
                                        .accessibilityLabel("Usage warning: \(notice)")
                                } else {
                                    let clock = feed.usageFiveHourReset ?? ""
                                    let rel = feed.usageFiveHourResetRelative ?? ""
                                    let resetsStr = rel.isEmpty ? " \(clock)" : " \(clock) · in \(rel)"
                                    Text("\(Image(systemName: "arrow.clockwise"))\(resetsStr)")
                                        .foregroundStyle(Color.secondary.opacity(0.75))
                                        .help(feed.usageResetTooltip)
                                        // The bare glyph + clock reads as nothing without this.
                                        .accessibilityLabel(
                                            "5-hour limit resets at \(clock)\(rel.isEmpty ? "" : ", in \(rel)")")
                                }
                            }
                            .font(.claudeMono(10))
                            .lineLimit(1)
                            .textCase(.lowercase)
                            // Only the account numbers go stale; the total below is
                            // read from the sessions, which are live regardless.
                            .opacity(feed.usageIsStale ? 0.5 : 1)
                        }

                        Spacer(minLength: 8)

                        // Context across every session at once — the one number no
                        // single row can show.
                        if let total = feed.totalContextTokens {
                            Text("\(FeedWatcher.formatTokens(total)) total")
                                .font(.claudeMono(10))
                                .monospacedDigit()
                                .foregroundStyle(Color.secondary.opacity(0.75))
                                .lineLimit(1)
                                .textCase(.lowercase)
                                .help("Total context tokens across all sessions")
                                .accessibilityLabel("\(FeedWatcher.formatTokens(total)) context tokens across all sessions")
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider().opacity(0.5)
            }
        }
    }
}

/// Always-present footer: the 5-hour and 7-day rate limits and the recent trend,
/// colored by urgency. A 1s clock keeps the stale-dimming current.
struct UsageFooter: View {
    @ObservedObject var feed: FeedWatcher

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            // 1s clock keeps the reset countdown live-ticking.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        if feed.hasUsage {
                            HStack(spacing: 12) {
                                if let h5 = feed.usageFiveHourPct {
                                    UsageGauge(label: "5h", pct: h5)
                                }
                                if let d7 = feed.usageSevenDayPct {
                                    UsageGauge(label: "7d", pct: d7)
                                }
                                // Recent 5h change, once there are ≥2 poll samples.
                                if let trend = feed.usageFiveHourTrend {
                                    TrendGauge(delta: trend)
                                }
                            }
                            // Dim when stale so a frozen snapshot doesn't read as live;
                            // the "as of" time and age live in the hover tooltip.
                            .opacity(feed.usageIsStale ? 0.5 : 1)
                            .help(feed.usageAsOfString)
                        } else {
                            Text("no usage data yet")
                                .font(.claudeMono(11))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                        }

                        Spacer(minLength: 4)
                    }
                    Text(feed.usageTotals == nil ? feed.usageTotalsStatus
                         : feed.usageTotalsRows.prefix(2).map { "\($0.label) \($0.value)" }
                             .joined(separator: "   "))
                        .font(.claudeMono(11))
                        .foregroundStyle(Color.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(feed.usageTotals == nil || feed.usageTotalsIsStale ? 0.6 : 1)
                        .help(feed.usageTotalsTooltip)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }
}

/// A compact usage gauge: a small label, a drawn rounded track with the filled
/// portion tinted by urgency, and the percentage. Reads far cleaner than a row of
/// █/░ block glyphs and keeps 5h and 7d visually aligned.
struct UsageGauge: View {
    let label: String
    let pct: Int

    private let trackWidth = Constants.usageTrackWidth
    private let trackHeight: CGFloat = 5

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.claudeMono(11))
                .foregroundStyle(Color.secondary)
                .fixedSize()
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: trackWidth, height: trackHeight)
                Capsule()
                    .fill(Color.usageTint(pct))
                    // Clamp to [0,1]; keep a sliver visible for tiny non-zero values.
                    .frame(width: max(pct > 0 ? 3 : 0,
                                      trackWidth * CGFloat(min(100, max(0, pct))) / 100),
                           height: trackHeight)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: pct)
            }
            Text("\(pct)%")
                .font(.claudeMono(11)).monospacedDigit()
                .foregroundStyle(Color.usageTint(pct))
                .fixedSize()
        }
        .help("\(label == "5h" ? "5-hour" : "7-day") usage \(pct)%")
        // The level is otherwise conveyed by fill length and tint alone.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label == "5h" ? "5-hour" : "7-day") usage")
        .accessibilityValue("\(pct) percent")
    }
}

/// A capsule gauge in the same language as `UsageGauge`, showing the recent
/// *change* in 5h utilization rather than an absolute level: how far it moved
/// across the sample window, signed. Rising usage tints warm (heading toward the
/// limit); falling tints green; the fill length is the magnitude.
struct TrendGauge: View {
    let delta: Int

    private let trackWidth = Constants.usageTrackWidth
    private let trackHeight: CGFloat = 5

    /// Fill fraction for a signed point change, square-rooted over the full
    /// 0-100 range. The old linear 20-point scale saturated: every move past 20
    /// points drew an identical full bar, so +20 and +52 were the same picture.
    /// Square root keeps resolution where samples actually land — single-digit
    /// moves stay distinguishable — while leaving headroom all the way to 100.
    static func fillFraction(delta: Int) -> CGFloat {
        sqrt(CGFloat(min(100, abs(delta))) / 100)
    }

    private var tint: Color {
        if delta > 0 { return .usageAmber }  // rising
        if delta < 0 { return .usageGreen }  // falling
        return Color.secondary
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("trend")
                .font(.claudeMono(11))
                .foregroundStyle(Color.secondary)
                .fixedSize()
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: trackWidth, height: trackHeight)
                Capsule()
                    .fill(tint)
                    .frame(width: max(delta != 0 ? 3 : 0,
                                      trackWidth * Self.fillFraction(delta: delta)),
                           height: trackHeight)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: delta)
            }
            Text("\(delta > 0 ? "+" : "")\(delta)%")
                .font(.claudeMono(11)).monospacedDigit()
                .foregroundStyle(tint)
                .fixedSize()
        }
        .help("5h usage change over recent polls")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("5-hour usage change over recent polls")
        .accessibilityValue("\(delta > 0 ? "up" : delta < 0 ? "down" : "unchanged") \(abs(delta)) percent")
    }
}

extension SessionFeed {
    /// The status word the row draws. Lives here rather than in SessionRow because
    /// the panel measures every row's label to size the shared columns, so the
    /// string the layout budgets for and the string drawn must be the same one.
    var statusLabel: String {
        switch status {
        case .tool:      return tool.isEmpty ? "running" : "running \(tool)"
        case .thinking:  return "thinking"
        case .attention: return "needs input"
        case .idle:      return lastDuration != nil ? "done" : "idle"
        }
    }

    /// The todo list as text, or nil when the session has none. The ten-box bar
    /// this replaced was drawn on every row, so a session with no list showed an
    /// orange-framed `0%` that read as its context; text that appears only when
    /// there is something to count cannot be mistaken for a gauge.
    var todoSummary: String? {
        let p = todoProgress
        guard p.total > 0 else { return nil }
        return "todos \(min(max(p.done, 0), p.total))/\(p.total)"
    }
}

/// How a row divides its width across two lines: line 1's name/model columns,
/// and line 2's status column (beside the fixed-width context meter).
///
/// Name and model were once fixed (105 / 46), so the split was a guess made once
/// for every row. Model is the measurable one — a known vocabulary, monospaced
/// font, always ASCII — so it takes what it needs and the name, unbounded prose,
/// gets the rest of line 1. Status moved to line 2 alongside the context meter and is
/// budgeted separately, against what that line actually has available, rather
/// than sharing line 1's space the way it used to — see `columns(...)` below.
enum RowLayout {
    /// Width of the animated working-dots slot, held even at rest so the column
    /// edge doesn't move as the dots grow (see the SessionRow comment). Lives on
    /// line 2, next to the status text.
    static let dotsSlot: CGFloat = 13
    /// Right-flushed resting evidence ("idle 12m") on line 2. Charged to every
    /// row's budget, not only the resting ones: the columns are sized once for
    /// the whole panel so they stay aligned, and a slot that came and went would
    /// shift the status text every time a session finished a turn.
    static let evidenceSlot: CGFloat = 56
    /// The name never shrinks past this, even if a long model word wants more —
    /// past this point the model is the one that gives way (see `columns`).
    static let minNameWidth: CGFloat = 70
    /// And it never grows past this. Reverses the 2026-07-17 split deliberately:
    /// the name used to absorb every spare point, which let one long session name
    /// dominate a row that also has to say what the session is doing. Names past
    /// this are cut with `..` rather than being given the width.
    static let maxNameWidth: CGFloat = 132
    /// Headroom on the measured status width. Menlo's advance measures exact, but
    /// bug-111/122 both truncated a column budgeted to its arithmetic minimum.
    static let statusSlack: CGFloat = 4
    /// Mirrors `SessionRow`'s `.padding(.horizontal, 10)` — one side of the row's
    /// own padding, charged twice when budgeting line 2's available width.
    static let rowHorizontalPadding: CGFloat = 10
    /// Mirrors `SessionRow`'s second line `.padding(.leading, 20)`, which aligns
    /// the status text under the name column, past the glyph.
    static let secondRowLeadingInset: CGFloat = 20
    /// Line 2's `HStack(spacing: 8)` gap. Charged three times: status | spacer |
    /// evidence | context meter each sit a gap apart.
    static let lineTwoGap: CGFloat = 8
    /// Line 2's context meter: the `ctx` word, the track, and the token count,
    /// 4pt apart. The track is the footer gauges' width so every bar in the panel
    /// is the same size.
    static let contextLabelWidth: CGFloat = 20
    static let contextValueWidth: CGFloat = 34
    static let contextSlot: CGFloat = contextLabelWidth + 4 + Constants.usageTrackWidth + 4 + contextValueWidth

    /// One character's advance in the row font. Menlo is monospaced, so a string's
    /// width is its count times this — no per-string measurement per render, and
    /// exact rather than the ~0.602×size estimate the old widths were derived from.
    static let monoAdvance: CGFloat = {
        let font = NSFont(name: Font.claudeFontName, size: 11)
            ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
        return ("m" as NSString).size(withAttributes: [.font: font]).width
    }()

    /// One line's height in the row font, measured the same way as `monoAdvance`.
    /// Pins the working-dots slot's height, not just its width: `FeedWatcher.
    /// workingDots` cycles through an empty `""` phase, and SwiftUI can size an
    /// empty `Text` shorter than a non-empty one at the same font. On line 1 that
    /// never showed, because the glyph `Text` beside it (font 13, never empty) was
    /// always the tallest sibling and pinned the line's height regardless. Line 2
    /// has no such permanently non-empty sibling once the dots go blank, so
    /// without this the whole row — and everything below it — pulsed a line's
    /// worth of height every ~0.5s (2026-08-15 second-row jitter).
    static let lineHeight: CGFloat = {
        let font = NSFont(name: Font.claudeFontName, size: 11)
            ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
        return font.ascender - font.descender + font.leading
    }()

    /// What a measurable column needs to draw `text` without truncating.
    static func width(for text: String) -> CGFloat {
        text.isEmpty ? 0 : CGFloat(text.count) * monoAdvance + statusSlack
    }

    /// `label` cut to what `width` can draw, leaving `statusSlack` of headroom so
    /// SwiftUI never reaches for its own tail `…`. Without this, a long tool name
    /// (`running mcp__…`) truncates to `…` and the animated working-dots render
    /// right after it — two ellipses in a row (`running askuserqu……`). The dots
    /// are the only trailing signal; the word is cut to fit and they follow it.
    /// Monospaced, so the fit is exact and testable without standing up a view.
    static func fit(_ label: String, toWidth width: CGFloat) -> String {
        let maxChars = Int((width - statusSlack) / monoAdvance)
        guard maxChars > 0, label.count > maxChars else { return label }
        return String(label.prefix(maxChars))
    }

    /// A session name cut to `width`, ending in `..` so the cut is visible. Unlike
    /// `fit`, which cuts silently because the animated dots already signal "there
    /// is more", a name has no such marker — without the dots a truncated name and
    /// a genuinely short one look identical.
    ///
    /// Character-count based, so exact only for monospaced ASCII. Session names can
    /// carry emoji or wide glyphs, which is why the `Text` keeps its
    /// `.truncationMode(.tail)` backstop: those rare names still cannot overflow,
    /// they just show SwiftUI's `…` instead of this `..`.
    /// What a row's `×N` badge takes out of the name column, including the 3pt gap
    /// before it. Zero for an ungrouped row, which has no badge.
    static func countBadgeWidth(_ count: Int) -> CGFloat {
        count > 1 ? CGFloat(String(count).count + 1) * monoAdvance + 3 : 0
    }

    static func fitName(_ name: String, toWidth width: CGFloat) -> String {
        let maxChars = Int((width - statusSlack) / monoAdvance)
        guard maxChars > 2, name.count > maxChars else { return name }
        return String(name.prefix(maxChars - 2)) + ".."
    }

    /// The name/model column widths (line 1) and the status column width (line 2),
    /// shared by every row in the panel.
    struct Columns: Equatable {
        var name: CGFloat
        var model: CGFloat
        var status: CGFloat
    }

    /// Size the columns once for the whole panel, from the widest label in each.
    ///
    /// Sized per row instead, the columns jag: each row's model and status start
    /// at a different x and the eye loses the vertical run. Sizing to the panel's
    /// widest label keeps the columns aligned and still hands every spare point to
    /// the names. The cost is honest and bounded — one row running a long tool
    /// narrows every name — which beats either the old fixed guess or a ragged
    /// grid.
    ///
    /// Pure so the budget is testable without standing up a view: every bug in
    /// this family (111, 122, 138) was arithmetic, and arithmetic is checkable.
    /// Only the ASCII model/status labels are measured; session names may hold
    /// emoji or wide glyphs, which is why the name is the column that flexes and
    /// truncates rather than the one being measured.
    /// `panelWidth` is the clamped, per-display width (see `Constants.fittedPanelWidth`);
    /// the caller guarantees it is at least `Constants.panelMinWidth`, which is why the
    /// subtractions below never need a `max(0)` guard.
    ///
    /// Name/model (line 1) and status (line 2) are budgeted independently now that
    /// status renders on its own line beside the context meter, not beside the
    /// name — a long status label no longer eats into the name column, and neither
    /// `dotsSlot` nor the meter's width belong to line 1's budget at all.
    static func columns(statusLabels: [String], models: [String], panelWidth: CGFloat) -> Columns {
        var model = models.map(width(for:)).max() ?? 0
        var status = statusLabels.map(width(for:)).max() ?? 0

        // Line 1: name and model only. The name's floor wins — the model gives
        // way first, since a model word is recoverable from the row's tooltip and
        // there are only ever a few of them, whereas a truncated session name is
        // what makes two rows in one directory indistinguishable.
        let modelCap = max(0, panelWidth - Constants.rowFixedColumns - minNameWidth)
        model = min(model, modelCap)
        let name = min(panelWidth - Constants.rowFixedColumns - model, maxNameWidth)

        // Line 2: status shares its budget with the context meter, sized against
        // what that line actually has — the row's own horizontal padding (charged
        // on both sides), the second row's leading inset, the meter, the evidence
        // slot, the three gaps between them, and the working-dots slot.
        let line2Width = panelWidth - 2 * rowHorizontalPadding - secondRowLeadingInset
            - Constants.childRowIndent
        let statusBudget = max(0, line2Width - contextSlot - 3 * lineTwoGap
                                - dotsSlot - evidenceSlot)
        status = min(status, statusBudget)

        return Columns(name: name, model: model, status: status)
    }
}

/// A project heading in the dropdown. Same content as the sidebar's, sized for the
/// panel: name, session count, and the section's context added up.
///
/// The total is untinted on purpose, matching `FeedWatcher.totalContextTokens` —
/// summed context across separate windows is not the same "heavy" a single
/// session's `contextTint` band means.
///
/// Uppercase and bold so a heading cannot be read as a row. "Needs you" alone
/// takes the attention blue: it is the one heading that is a state, not a place.
private struct PanelSectionHeader: View {
    let section: ProjectSection

    private var ink: Color { section.id == "needs-you" ? .attention : .label }

    var body: some View {
        HStack(spacing: 6) {
            Text(section.title)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(section.sessionCount)")
            if let total = section.contextTotal {
                Text(FeedWatcher.formatTokens(total))
            }
        }
        .font(.claudeMono(10)).fontWeight(.bold)
        .textCase(.uppercase)
        .foregroundStyle(ink)
        .padding(.horizontal, 10)
        .padding(.top, 8).padding(.bottom, 3)
    }
}

struct SessionRow: View {
    @ObservedObject var feed: FeedWatcher
    let item: SessionRowItem
    let now: Date
    /// Column widths shared by every row in the panel, so they stay aligned.
    let columns: RowLayout.Columns
    @StateObject private var hover = HoverState()

    private var session: SessionFeed { item.session }

    private var indent: CGFloat { CGFloat(item.depth) * Constants.childRowIndent }

    /// The `×N` idle-collapse badge: only for a row grouping several idle
    /// sessions sharing a directory. A parent row with real subagent children
    /// also has `item.count > 1` (subagent ids ride along on `ids` so `clear()`
    /// cascades), but that is not the idle-collapse case, so it must not badge.
    private var grouped: Bool { item.showsCountBadge }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Line 1: [└] [glyph] name ×N  model  time  [chip]
            HStack(spacing: 5) {
                // A subagent's indent carries a connector to its parent, sized so
                // connector + gap is exactly `indent` and every column after it
                // lands where the plain indent put it.
                if item.depth > 0 {
                    Text("└")
                        .font(.claudeMono(11))
                        .foregroundStyle(Color.secondary)
                        .frame(width: indent - 5, alignment: .trailing)
                }

                Text(glyph)
                    .font(.claudeMono(13))
                    .foregroundStyle(tint)
                    .frame(width: 15)

                // Column 1: Project Name + Count. Fixed width ensures alignment of subsequent columns.
                HStack(spacing: 3) {
                    // A grouped row stands for several idle sessions sharing a directory —
                    // displayItems groups on cwd, not name — so only a single-session row
                    // can honestly show a session name.
                    // A grouped row spends part of the column on its `×N` badge, so the
                    // name is fitted to what's left rather than to the whole column —
                    // otherwise the name fills the frame and squeezes the count out.
                    Text(RowLayout.fitName(grouped ? session.projectName : session.displayName,
                                           toWidth: columns.name - indent - RowLayout.countBadgeWidth(grouped ? item.count : 1)))
                        .font(.claudeMono(11))
                        .foregroundStyle(nameColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if grouped {
                        Text("×\(item.count)")
                            .font(.claudeMono(11))
                            .foregroundStyle(Color.secondary)
                    }
                }
                // Sized against the model and status beside it, not fixed: both are
                // drawn from bounded vocabularies and take only what they need, so the
                // name — unbounded prose — gets everything left over. The indent comes
                // out of the name column only, not the model/time/chip columns.
                .frame(width: max(0, columns.name - indent), alignment: .leading)

                // Column 2: Model, sized to the family word it actually holds.
                Group {
                    if let rawModel = feed.modelDisplay(for: session) {
                        Text(FeedWatcher.modelFamily(rawModel))
                            .font(.claudeMono(11)).fontWeight(.semibold)
                            .foregroundStyle(Color.modelTint(rawModel))
                            .lineLimit(1)
                    } else {
                        Text("")
                    }
                }
                .frame(width: columns.model, alignment: .leading)

                // Status / Activity moved to the second row (see below); this Spacer
                // takes over pushing the trailing columns right in its place.
                Spacer(minLength: 0)

                // Time + host chip travel together as one right-flush unit with a tight
                // gap, so the time stays near the right edge with the tag just after it.
                HStack(spacing: 4) {
                    // Elapsed / waiting / done time in a fixed-width column so the times
                    // line up down the panel regardless of label. A one-line resting
                    // row puts its evidence ("idle 12m", open todos) here instead, and
                    // may grow leftward into the spare width past the model.
                    Text(isResting ? (session.restingEvidence(now: now) ?? timeText) : timeText)
                        .font(.claudeMono(11))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(Color.secondary)
                        .frame(minWidth: 48, alignment: .trailing)

                    // The color-coded host chip (vsc/trm/web/app) at rest, which flips to
                    // an ✕ clear button on hover so a session can be dismissed in place.
                    // A fixed width holds the slot constant so the time never shifts.
                    ZStack(alignment: .trailing) {
                        Color.clear.frame(width: Constants.rowTrailingSlot, height: 1)
                        if hover.isHovering {
                            Button {
                                feed.clear(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Color.secondary)
                            .help("Clear this session")
                        } else if !session.isChild, let tag = session.hostTag {
                            Text(tag.label)
                                .font(.claudeMono(10))
                                .foregroundStyle(tag.color)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(tag.color.opacity(Color.Ink.chipTint))
                                )
                        }
                    }
                }
            }

            // A resting session has nothing happening to report, so it takes one
            // line: its age sits in the time column above and the rest recedes.
            if !isResting {
                HStack(spacing: RowLayout.lineTwoGap) {
                    // Status / Activity, with the working-dots attached to the word
                    // they belong to.
                    HStack(spacing: 0) {
                        Text(displayStatus)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        // A fixed slot: the dots grow and shrink every 0.5s, and letting that
                        // reflow the status text would make its truncation flicker in time
                        // with them. Reserved even at rest so the column edge never moves —
                        // height included, so the empty phase of the cycle can't shrink the
                        // row (see `RowLayout.lineHeight`).
                        Text(isWorking ? FeedWatcher.workingDots(at: now) : "")
                            .frame(width: RowLayout.dotsSlot, height: RowLayout.lineHeight, alignment: .leading)
                    }
                    .font(.claudeMono(11))
                    .foregroundStyle(statusColor)

                    Spacer(minLength: 0)

                    // What the feed saw about a session that is sitting still, else its
                    // todo count; nothing at all when there is neither.
                    if let evidence = session.restingEvidence(now: now, includeTodos: false)
                        ?? session.todoSummary {
                        Text(evidence)
                            .font(.claudeMono(10))
                            .foregroundStyle(Color.label)
                            .lineLimit(1)
                            .frame(width: RowLayout.evidenceSlot, alignment: .trailing)
                    }

                    // A subagent shares its parent's window, so it has no meter of its own.
                    if !session.isChild {
                        contextMeter
                    }
                }
                .padding(.leading, 20 + indent)  // aligns under the name column, past the glyph
            }
        }
        // Everything in a row renders lowercase — including hook-supplied text like
        // the attention message and tool names — for one consistent visual voice.
        .textCase(.lowercase)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .opacity(rowOpacity)
        .background(rowHighlight)
        .onHover { hover.isHovering = $0 }
        .onTapGesture {
            openSession()
        }
        .help(rowTooltip)
        .contextMenu {
            Button("Open in Terminal") { openWithApp(bundleID: "com.apple.Terminal") }
            Button("Open in VS Code") { openWithApp(bundleID: "com.microsoft.VSCode") }
            Button("Open in Ghostty") { openWithApp(bundleID: "com.mitchellh.ghostty") }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
            }
            Divider()
            Button("Copy Session ID") { copyToPasteboard(session.id) }
            Button("Copy Path") { copyToPasteboard(session.cwd) }
            Divider()
            Button("Clear") { feed.clear(item) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Opens this session's app")
        // children: .ignore hides the hover-revealed ✕ entirely, so clearing a
        // session is otherwise unreachable without a mouse.
        .accessibilityAction(named: "Clear session") { feed.clear(item) }
    }

    private func openWithApp(bundleID: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-b", bundleID, session.cwd]
        try? task.run()
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// An inset, rounded highlight pill behind the row — only on hover: a blue wash
    /// for an attention row, a neutral wash otherwise, nothing at rest. The blue
    /// glyph/text already signal "needs you" without a persistent band. Inset +
    /// rounded reads as a proper selection, and it fades in/out.
    @ViewBuilder private var rowHighlight: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(rowFill)
            .animation(.easeInOut(duration: 0.12), value: hover.isHovering)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }

    private var rowFill: Color {
        guard hover.isHovering else { return .clear }
        return session.status == .attention
            ? Color.attention.opacity(0.22)
            : Color.primary.opacity(0.09)
    }

    /// Idle rows fade with age so a stale session recedes instead of sitting at
    /// full strength for hours; working/attention rows stay fully opaque.
    private var rowOpacity: Double {
        guard session.status == .idle, let updated = session.updated else { return 1.0 }
        let age = now.timeIntervalSince(updated)
        let t = min(max((age - Constants.idleFadeStart) / Constants.idleFadeSpan, 0), 1)
        return 1.0 - (1.0 - Constants.idleMinOpacity) * t
    }

    /// Bring the session's host app (and its existing window) to the front —
    /// never a new window. See `SessionLauncher.focus`.
    private func openSession() {
        SessionLauncher.focus(host: session.host, pid: session.pid, cwd: session.cwd)
    }

    private var glyph: String {
        switch session.status {
        case .attention: return Spinner.idle   // the star, same as the rest; the blue tint carries "needs you"
        case .thinking, .tool: return Spinner.frame(at: now)
        case .idle: return Spinner.idle
        }
    }

    // Idle/done rows go fully grey (glyph, name, and status) so a finished
    // session recedes — the way Claude Code greys out completed work.
    private var tint: Color {
        switch session.status {
        // Blue signals "needs you" — a different state from busy orange, not a
        // second shade of it.
        case .attention: return .attention
        case .thinking, .tool: return .claude
        case .idle: return .secondary
        }
    }

    private var nameColor: Color {
        session.status == .idle ? .secondary : .primary
    }

    /// An idle row's context number recedes with the rest of the row; a live one
    /// is tinted by how many tokens it's carrying.
    private var contextColor: Color {
        guard let used = session.contextTokens, session.status != .idle else { return .secondary }
        return .contextTint(used)
    }

    private var contextTokens: String {
        session.contextTokens.map(FeedWatcher.formatTokens) ?? ""
    }

    /// `ctx`, a track scaled to the session's own window, and the token count.
    /// With no window or no reading the track is not drawn: an empty track is a
    /// reading of zero, and a missing reading is not one. The count says `n/a`.
    private var contextMeter: some View {
        HStack(spacing: 4) {
            Text("ctx")
                .font(.claudeMono(10))
                .foregroundStyle(Color.label)
                .frame(width: RowLayout.contextLabelWidth, alignment: .leading)
            Group {
                if let tokens = session.contextTokens,
                   let window = session.stats.contextWindowSize, window > 0 {
                    ContextMeter(tokens: tokens, window: window)
                } else {
                    Color.clear.frame(height: 5)
                }
            }
            .frame(width: Constants.usageTrackWidth)
            Text(contextTokens.isEmpty ? "n/a" : contextTokens)
                .font(.claudeMono(11))
                .monospacedDigit()
                .foregroundStyle(contextColor)
                .frame(width: RowLayout.contextValueWidth, alignment: .trailing)
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .attention: return .attention
        case .thinking, .tool: return .claude
        case .idle: return .secondary
        }
    }

    /// The concrete activity word, without the time (which lives in its own
    /// right-aligned column): `running Bash`, `thinking`, `done`, or the message.
    private var statusLabel: String { session.statusLabel }

    /// `statusLabel` cut to the width the status column actually has — the span
    /// `RowLayout.columns` sized for it. Pre-truncating here means SwiftUI's own
    /// tail `…` never lands beside the working-dots (bug: a long tool name drew
    /// `running askuserqu……`). Only the working `running <tool>` labels ever grow
    /// long enough to cut; the idle words always fit and pass through.
    private var displayStatus: String {
        RowLayout.fit(statusLabel, toWidth: columns.status)
    }

    /// An idle row, drawn on one line.
    private var isResting: Bool { session.status == .idle }

    /// True while the row is mid-turn — the dots animate and the time counts up.
    private var isWorking: Bool { session.status == .tool || session.status == .thinking }

    /// The time shown right-aligned at the end of the row: elapsed in-turn while
    /// working, how long it's been waiting for attention, the finished turn's
    /// duration when done, or how long idle. Empty when there's nothing to show.
    private var timeText: String {
        switch session.status {
        case .tool, .thinking:
            // Time in the current turn. turn_start is null when nothing is running,
            // so a working row without one has no elapsed time to show.
            guard let start = session.turnStart else { return "" }
            return FeedWatcher.formatDuration(max(0, Int(now.timeIntervalSince(start))))
        case .attention:
            return sinceUpdated
        case .idle:
            // A finished turn shows its (fixed) duration; a session that's just
            // sitting idle with nothing running shows nothing rather than a
            // placeholder.
            if let dur = session.lastDuration { return FeedWatcher.formatDuration(dur) }
            return ""
        }
    }

    /// How long since the session last changed — used for waiting/idle age.
    private var sinceUpdated: String {
        guard let updated = session.updated else { return "" }
        return FeedWatcher.formatDuration(max(0, Int(now.timeIntervalSince(updated))))
    }

    private var rowTooltip: String {
        var parts: [String] = []
        parts.append("path: \(session.displayPath)")
        if let pid = session.pid {
            parts.append("pid: \(pid)")
        }
        if let updated = session.updated {
            parts.append("updated: \(FeedWatcher.compactAge(since: updated, now: now)) ago")
        }
        return parts.joined(separator: "\n")
    }

    /// The row collapses to one VoiceOver element (`accessibilityElement(children:
    /// .ignore)` above), so this is the only place task-progress info can reach an
    /// assistive user.
    private var accessibilityLabelText: String {
        if session.isChild {
            var text = "subagent \(session.displayName), \(statusLabel) \(timeText)"
            if session.todoTotal != nil {
                text += ", task progress \(session.todoProgress.done) of \(session.todoProgress.total)"
            }
            return text
        }
        var text = "\(session.displayName), \(statusLabel) \(timeText)"
        if !contextTokens.isEmpty { text += ", \(contextTokens) context tokens" }
        if session.todoTotal != nil {
            text += ", task progress \(session.todoProgress.done) of \(session.todoProgress.total)"
        }
        if item.subagentCount > 0 {
            text += ", \(item.subagentCount) subagents"
        }
        return text
    }
}

class HoverState: ObservableObject {
    @Published var isHovering = false
}

/// Drives the one-click installer button in the Setup-needed panel. A small
/// ObservableObject rather than @State, matching HoverState (the codebase avoids
/// @State so the swiftc dev-loop build keeps working).
class InstallState: ObservableObject {
    @Published var installing = false
    @Published var message: NoticeMessage?
}
