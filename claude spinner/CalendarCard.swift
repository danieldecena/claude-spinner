import AppKit
import Combine
import EventKit
import SwiftUI

// The Home tab's Calendar card: what is on now, what is next, and what is left
// today, read from this Mac's own calendar store through EventKit.
//
// Same cost rule as the Mail card: nothing here polls. The store is read when the
// Home tab appears, when the store says it changed (`EKEventStoreChanged`), when
// the app comes to the front (which is also how a permission granted in System
// Settings is noticed) and when Refresh is pressed. No timer. An idle Home tab
// costs no tokens and no processes; a read is a local two-day query.
//
// The card keeps the raw events and works out Now / Next each time it draws, so
// the classification is never older than the last draw. The "in 25 min" text is
// only as fresh as that draw, which is what the "updated" label is for.

// MARK: - Plain values, so the logic needs no EventKit

nonisolated struct CalendarEventInfo: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    var location: String? = nil
    var isDeclined: Bool = false
}

nonisolated enum CalendarAccess: Equatable {
    case notDetermined
    /// Denied, restricted by policy, or write-only: in each case the card cannot
    /// read, and the fix is the same pane in System Settings.
    case denied
    case granted

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .fullAccess: self = .granted
        case .notDetermined: self = .notDetermined
        default: self = .denied
        }
    }

    var canRead: Bool { self == .granted }
}

nonisolated struct CalendarSnapshot: Equatable {
    enum Focus: Equatable {
        /// In progress.
        case now(CalendarEventInfo)
        /// The first one still to come today.
        case next(CalendarEventInfo)
    }

    struct Tomorrow: Equatable {
        var count: Int
        /// The earliest timed start; nil when there is none (no events, or only all-day).
        var firstStart: Date?
    }

    var focus: Focus?
    /// The rest of today's timed events that have not finished, after the focus
    /// one, in order, at most `shownLimit`.
    var upcoming: [CalendarEventInfo]
    /// How many more there were past `shownLimit`.
    var moreCount: Int
    var allDay: [CalendarEventInfo]
    /// nil when the read did not reach tomorrow, which is not the same as none.
    var tomorrow: Tomorrow?
    /// Any events at all today, finished ones and all-day ones included.
    var hasEventsToday: Bool
    /// False when the read is too old to say anything about today.
    var covered: Bool

    static let shownLimit = 5

    var isEmptyToday: Bool { covered && !hasEventsToday }
    /// Events today, but nothing in progress or still to come.
    var isDoneForToday: Bool { covered && hasEventsToday && focus == nil && upcoming.isEmpty }

    /// `events` is what a read at `readAt` returned for that day and the next.
    static func make(events: [CalendarEventInfo], readAt: Date, now: Date, calendar: Calendar) -> CalendarSnapshot {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: todayStart) ?? tomorrowStart
        let readStart = calendar.startOfDay(for: readAt)
        let readEnd = calendar.date(byAdding: .day, value: 2, to: readStart) ?? readStart

        let todayCovered = todayStart >= readStart && tomorrowStart <= readEnd
        let tomorrowCovered = tomorrowStart >= readStart && dayAfter <= readEnd
        guard todayCovered else {
            return CalendarSnapshot(focus: nil, upcoming: [], moreCount: 0, allDay: [], tomorrow: nil,
                                    hasEventsToday: false, covered: false)
        }

        let live = events.filter { !$0.isDeclined }
        func overlaps(_ e: CalendarEventInfo, _ from: Date, _ to: Date) -> Bool {
            e.start < to && (e.end > from || (e.end == e.start && e.start >= from))
        }
        let today = live.filter { overlaps($0, todayStart, tomorrowStart) }
        let allDay = today.filter(\.isAllDay).sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        let timed = today.filter { !$0.isAllDay }.sorted {
            ($0.start, $0.end, $0.title) < ($1.start, $1.end, $1.title)
        }

        var focusIndex: Int?
        var focus: Focus?
        if let i = timed.firstIndex(where: { $0.start <= now && now < $0.end }) {
            focusIndex = i
            focus = .now(timed[i])
        } else if let i = timed.firstIndex(where: { $0.start > now }) {
            focusIndex = i
            focus = .next(timed[i])
        }
        let rest = timed.enumerated().filter { $0.offset != focusIndex && $0.element.end > now }.map(\.element)

        var tomorrow: Tomorrow?
        if tomorrowCovered {
            // A timed event belongs to the day it starts; one running past
            // midnight is today's. An all-day event belongs to every day it spans.
            let events = live.filter {
                $0.isAllDay ? overlaps($0, tomorrowStart, dayAfter) : ($0.start >= tomorrowStart && $0.start < dayAfter)
            }
            tomorrow = Tomorrow(count: events.count, firstStart: events.filter { !$0.isAllDay }.map(\.start).min())
        }

        return CalendarSnapshot(focus: focus, upcoming: Array(rest.prefix(shownLimit)),
                                moreCount: max(0, rest.count - shownLimit), allDay: allDay,
                                tomorrow: tomorrow, hasEventsToday: !today.isEmpty, covered: true)
    }
}

// MARK: - Words

nonisolated enum CalendarFormat {
    static let emptyText = "Nothing on the calendar today."
    static let doneText = "Nothing more today."
    static let deniedText = "Calendar access is off. Allow it in System Settings > Privacy & Security > Calendars"
    static let staleText = "Press Refresh to read today's events."
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    /// Starts within this long and not yet begun: the card turns it to the attention colour.
    static let imminent: TimeInterval = 15 * 60

    /// "9:00 AM". Short style puts a narrow no-break space before AM/PM; a plain
    /// space reads the same and compares equal to what anyone would type.
    static func timeLabel(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                     calendar: calendar, timeZone: calendar.timeZone)
        return date.formatted(style).replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// "now", "in 14 min", "in 1 h 5 min", "in 2 d". Rounds up, so a start 30
    /// seconds away is "in 1 min" and never "in 0 min".
    static func timeUntil(_ start: Date, now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        if seconds <= 0 { return "now" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        if hours >= 24 { return "in \(hours / 24) d" }
        return rest == 0 ? "in \(hours) h" : "in \(hours) h \(rest) min"
    }

    static func isImminent(_ focus: CalendarSnapshot.Focus?, now: Date) -> Bool {
        guard case .next(let event) = focus else { return false }
        let until = event.start.timeIntervalSince(now)
        return until > 0 && until <= imminent
    }

    /// "11:00 AM – 11:30 AM · Room 4", or "until 11:30 AM · Room 4" for one in progress.
    static func focusDetail(_ focus: CalendarSnapshot.Focus, calendar: Calendar = .current,
                            locale: Locale = .current) -> String {
        let event: CalendarEventInfo, when: String
        switch focus {
        case .now(let e):
            event = e
            when = "until " + timeLabel(e.end, calendar: calendar, locale: locale)
        case .next(let e):
            event = e
            when = timeLabel(e.start, calendar: calendar, locale: locale) + " – "
                + timeLabel(e.end, calendar: calendar, locale: locale)
        }
        return [when, event.location].compactMap { $0 }.joined(separator: " · ")
    }

    static func spokenFocus(_ focus: CalendarSnapshot.Focus, now: Date, calendar: Calendar = .current,
                            locale: Locale = .current) -> String {
        switch focus {
        case .now(let e):
            return ["Now: \(e.title)", "until " + timeLabel(e.end, calendar: calendar, locale: locale), e.location]
                .compactMap { $0 }.joined(separator: ", ")
        case .next(let e):
            return ["Next: \(e.title) at " + timeLabel(e.start, calendar: calendar, locale: locale),
                    timeUntil(e.start, now: now), e.location]
                .compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// "Tomorrow: 3 events, first at 9:00 AM". nil when the read did not reach
    /// tomorrow: no line beats a "no events" that was never checked.
    static func tomorrowLine(_ tomorrow: CalendarSnapshot.Tomorrow?, calendar: Calendar = .current,
                             locale: Locale = .current) -> String? {
        guard let tomorrow else { return nil }
        if tomorrow.count == 0 { return "Tomorrow: no events" }
        let noun = tomorrow.count == 1 ? "event" : "events"
        guard let first = tomorrow.firstStart else { return "Tomorrow: \(tomorrow.count) \(noun), all day" }
        return "Tomorrow: \(tomorrow.count) \(noun), first at " + timeLabel(first, calendar: calendar, locale: locale)
    }

    /// "All day: A, B +2 more": two titles, then a count.
    static func allDayLine(_ events: [CalendarEventInfo]) -> String? {
        guard !events.isEmpty else { return nil }
        let shown = events.prefix(2).map(\.title).joined(separator: ", ")
        let more = events.count - 2
        return "All day: " + shown + (more > 0 ? " +\(more) more" : "")
    }

    /// The read was on an earlier day, so "tomorrow" and the day's tail are old news.
    static func isStale(readAt: Date, now: Date, calendar: Calendar = .current) -> Bool {
        !calendar.isDate(readAt, inSameDayAs: now)
    }
}

// MARK: - EventKit

extension CalendarEventInfo {
    nonisolated init(_ event: EKEvent) {
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(title: title.isEmpty ? "Untitled event" : title,
                  start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                  location: (location?.isEmpty ?? true) ? nil : location,
                  isDeclined: event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
    }
}

/// Reads the store when asked and when it changes; never on a clock.
final class CalendarModel: ObservableObject {
    enum Load: Equatable {
        /// Before the first read, or while the permission prompt is open.
        case checking
        case denied
        case ready(events: [CalendarEventInfo], readAt: Date)
    }

    @Published private(set) var load: Load = .checking

    private var store: EKEventStore?
    private var observers: [NSObjectProtocol] = []
    private var requesting = false

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Home tab appeared.
    func start() {
        let store = self.store ?? EKEventStore()
        self.store = store
        if observers.isEmpty {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.reload() }
                },
                // Also how a grant made in System Settings is noticed.
                center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor [weak self] in self?.reload() }
                },
            ]
        }
        reload()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    func reload() {
        switch CalendarAccess(EKEventStore.authorizationStatus(for: .event)) {
        case .granted: read()
        case .denied: load = .denied
        case .notDetermined: request()
        }
    }

    /// The one-time system prompt; Daniel's answer is remembered by macOS.
    private func request() {
        guard !requesting, let store else { return }
        requesting = true
        load = .checking
        Task { [weak self] in
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            guard let self else { return }
            self.requesting = false
            if granted { self.read() } else { self.load = .denied }
        }
    }

    /// Today and tomorrow, every calendar, canceled events dropped.
    private func read() {
        guard let store else { return }
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 2, to: start) else { return }
        let found = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        load = .ready(events: found.filter { $0.status != .canceled }.map(CalendarEventInfo.init), readAt: now)
    }
}

// MARK: - View

struct CalendarCard: View {
    @StateObject private var model = CalendarModel()

    var body: some View {
        // `now` is read once per render, like the Mail card: no timer, so every
        // "in N min" is as fresh as the last time something made the card draw.
        CalendarCardContent(load: model.load, now: Date(), refresh: { model.reload() })
            .onAppear { model.start() }
            .onDisappear { model.stop() }
    }
}

/// The card as a pure function of what the model loaded, so it can be drawn
/// without EventKit.
struct CalendarCardContent: View {
    let load: CalendarModel.Load
    let now: Date
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch load {
            case .checking:
                Text("Reading the calendar…").font(.ui(11)).foregroundStyle(Color.label)
            case .denied:
                deniedBody
            case .ready(let events, let readAt):
                readyBody(CalendarSnapshot.make(events: events, readAt: readAt, now: now, calendar: .current))
            }
        }
        .detailCard()
    }

    private var header: some View {
        HStack {
            CardTitle("Calendar")
            Spacer(minLength: 4)
            if case .ready(_, let readAt) = load {
                let stale = CalendarFormat.isStale(readAt: readAt, now: now)
                Text(MailStatusFile.updatedLabel(readAt, now: now))
                    .font(.ui(10)).foregroundStyle(stale ? Color.attention : Color.label)
            }
            Button(action: refresh) {
                Text("Refresh").font(.ui(10)).frame(minWidth: 64, minHeight: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Read the calendar again now")
            .accessibilityLabel("Refresh calendar")
        }
    }

    private var deniedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CalendarFormat.deniedText).font(.ui(11)).foregroundStyle(Color.label)
            Button { NSWorkspace.shared.open(CalendarFormat.settingsURL) } label: {
                Text("Open Calendars settings").font(.ui(10)).frame(minHeight: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Open Calendars privacy settings")
        }
    }

    @ViewBuilder private func readyBody(_ snapshot: CalendarSnapshot) -> some View {
        if !snapshot.covered {
            Text(CalendarFormat.staleText).font(.ui(11)).foregroundStyle(Color.attention)
        } else if snapshot.isEmptyToday {
            Text(CalendarFormat.emptyText).font(.ui(11)).foregroundStyle(Color.label)
        } else {
            if let focus = snapshot.focus {
                focusBlock(focus)
            } else if snapshot.isDoneForToday {
                Text(CalendarFormat.doneText).font(.ui(11)).foregroundStyle(Color.label)
            }
            if !snapshot.upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(snapshot.upcoming.enumerated()), id: \.offset) { _, event in
                        upcomingRow(event)
                    }
                    if snapshot.moreCount > 0 {
                        Text("+\(snapshot.moreCount) more").font(.ui(10)).foregroundStyle(Color.label)
                    }
                }
            }
            if let line = CalendarFormat.allDayLine(snapshot.allDay) {
                Text(line).font(.ui(10)).foregroundStyle(Color.label).lineLimit(1).truncationMode(.tail)
            }
        }
        if let line = CalendarFormat.tomorrowLine(snapshot.tomorrow) {
            Text(line).font(.ui(10)).foregroundStyle(Color.label)
        }
    }

    private func focusBlock(_ focus: CalendarSnapshot.Focus) -> some View {
        let imminent = CalendarFormat.isImminent(focus, now: now)
        let event: CalendarEventInfo
        let tag: String
        switch focus {
        case .now(let e): event = e; tag = "Now"
        case .next(let e): event = e; tag = "Next"
        }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(tag).font(.ui(9)).fontWeight(.semibold).textCase(.uppercase).tracking(0.8)
                    .foregroundStyle(imminent ? Color.attention : Color.label)
                Spacer(minLength: 4)
                if case .next = focus {
                    Text(CalendarFormat.timeUntil(event.start, now: now)).font(.figure(11))
                        .foregroundStyle(imminent ? Color.attention : Color.label)
                }
            }
            Text(event.title).font(.ui(13)).fontWeight(.semibold)
                .foregroundStyle(imminent ? Color.attention : Color.primary)
                .lineLimit(2).truncationMode(.tail)
            Text(CalendarFormat.focusDetail(focus)).font(.ui(11)).foregroundStyle(Color.label)
                .lineLimit(1).truncationMode(.tail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CalendarFormat.spokenFocus(focus, now: now))
    }

    private func upcomingRow(_ event: CalendarEventInfo) -> some View {
        HStack(spacing: 8) {
            Text(CalendarFormat.timeLabel(event.start)).font(.figure(10)).foregroundStyle(Color.label)
                .frame(width: 62, alignment: .leading)
            Text(event.title).font(.ui(11)).lineLimit(1).truncationMode(.tail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title) at \(CalendarFormat.timeLabel(event.start))")
    }
}
