//
//  CalendarCardTests.swift
//  claude spinnerTests
//
//  The Calendar card's pure logic: which event is Now or Next, the rest of
//  today, the all-day split, declined events, the tomorrow summary, the
//  time-until label, and the empty and denied states. Events here are plain
//  structs with made-up titles; nothing touches EventKit or the real calendar,
//  so a test run never raises a permission prompt.
//

import EventKit
import XCTest
@testable import claude_spinner

final class CalendarCardTests: XCTestCase {

    // 2026-10-02 10:00 UTC, in a calendar pinned to UTC so the day boundaries
    // do not depend on the machine running the tests.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let us = Locale(identifier: "en_US")

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 2, second: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    private var now: Date { at(10) }

    private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false,
                       location: String? = nil, declined: Bool = false) -> CalendarEventInfo {
        CalendarEventInfo(title: title, start: start, end: end, isAllDay: allDay,
                          location: location, isDeclined: declined)
    }

    private func timed(_ title: String, _ hour: Int, _ minute: Int = 0, mins: Int = 30,
                       day: Int = 2, declined: Bool = false) -> CalendarEventInfo {
        let start = at(hour, minute, day: day)
        return event(title, start, start.addingTimeInterval(Double(mins) * 60), declined: declined)
    }

    private func snapshot(_ events: [CalendarEventInfo], readAt: Date? = nil) -> CalendarSnapshot {
        CalendarSnapshot.make(events: events, readAt: readAt ?? now, now: now, calendar: cal)
    }

    // MARK: Now / Next

    func testNextIsTheFirstEventStillToCome() {
        let s = snapshot([timed("B", 14), timed("A", 11)])
        XCTAssertEqual(s.focus, .next(timed("A", 11)))
        XCTAssertEqual(s.upcoming, [timed("B", 14)])
    }

    func testAnEventInProgressIsNowAndBeatsTheNextOne() {
        let running = event("Running", at(9, 30), at(10, 30))
        let s = snapshot([timed("Later", 11), running])
        XCTAssertEqual(s.focus, .now(running))
        XCTAssertEqual(s.upcoming, [timed("Later", 11)])
    }

    func testAnEventEndingExactlyNowIsOverAndOneStartingNowIsCurrent() {
        let over = event("Over", at(9), at(10))
        let starting = event("Starting", at(10), at(11))
        XCTAssertEqual(snapshot([over]).focus, nil)
        XCTAssertEqual(snapshot([over, starting]).focus, .now(starting))
    }

    func testOverlappingEventsPickTheEarliestStartedAsNowAndKeepTheOtherListed() {
        let first = event("First", at(9, 30), at(10, 30))
        let second = event("Second", at(9, 45), at(10, 15))
        let s = snapshot([second, first])
        XCTAssertEqual(s.focus, .now(first))
        XCTAssertEqual(s.upcoming, [second])
    }

    // MARK: Rest of today

    func testRestOfTodayIsOrderedByStartThenTitle() {
        let s = snapshot([timed("Zed", 13), timed("Beta", 12), timed("Alpha", 12), timed("First", 11)])
        XCTAssertEqual(s.focus, .next(timed("First", 11)))
        XCTAssertEqual(s.upcoming.map(\.title), ["Alpha", "Beta", "Zed"])
    }

    func testAtMostFiveAreListedAndTheRestAreCounted() {
        let many = (0..<9).map { timed("E\($0)", 11 + $0 / 2, ($0 % 2) * 30) }
        let s = snapshot(many)
        XCTAssertEqual(s.focus, .next(many[0]))
        XCTAssertEqual(s.upcoming.count, 5)
        XCTAssertEqual(s.moreCount, 3)
        XCTAssertEqual(s.upcoming.first, many[1])
    }

    func testExactlyFiveRemainingShowsNoMoreLine() {
        let six = (0..<6).map { timed("E\($0)", 11 + $0) }
        let s = snapshot(six)
        XCTAssertEqual(s.upcoming.count, 5)
        XCTAssertEqual(s.moreCount, 0)
    }

    func testFinishedEventsAreNotListedButTheDayIsNotEmpty() {
        let s = snapshot([timed("Done", 8), timed("Also done", 9)])
        XCTAssertNil(s.focus)
        XCTAssertTrue(s.upcoming.isEmpty)
        XCTAssertFalse(s.isEmptyToday)
        XCTAssertTrue(s.isDoneForToday)
    }

    // MARK: All-day and declined

    func testAllDayEventsAreSplitOutAndNeverNowOrNext() {
        let holiday = event("Holiday", at(0), at(23, 59, second: 59), allDay: true)
        let s = snapshot([holiday, timed("Call", 11)])
        XCTAssertEqual(s.allDay, [holiday])
        XCTAssertEqual(s.focus, .next(timed("Call", 11)))
        XCTAssertTrue(s.upcoming.isEmpty)
        XCTAssertFalse(s.isEmptyToday)
    }

    func testAnAllDayOnlyDayHasNoFocusAndIsNotEmptyOrDone() {
        let s = snapshot([event("Holiday", at(0), at(23, 59, second: 59), allDay: true)])
        XCTAssertNil(s.focus)
        XCTAssertFalse(s.isEmptyToday)
        XCTAssertTrue(s.isDoneForToday)
    }

    func testDeclinedEventsAreLeftOutEverywhere() {
        let s = snapshot([timed("Declined now", 10, mins: 30, declined: true),
                          timed("Declined next", 10, 15, declined: true),
                          timed("Kept", 12),
                          timed("Declined tomorrow", 9, day: 3, declined: true)])
        XCTAssertEqual(s.focus, .next(timed("Kept", 12)))
        XCTAssertTrue(s.upcoming.isEmpty)
        XCTAssertEqual(s.tomorrow, CalendarSnapshot.Tomorrow(count: 0, firstStart: nil))
    }

    func testOnlyDeclinedEventsTodayIsEmpty() {
        XCTAssertTrue(snapshot([timed("No", 11, declined: true)]).isEmptyToday)
    }

    // MARK: Tomorrow

    func testTomorrowCountsEventsAndNamesTheFirstTimedStart() {
        let allDay = event("Trip", at(0, day: 3), at(23, 59, day: 3, second: 59), allDay: true)
        let s = snapshot([timed("Late", 15, day: 3), timed("Early", 9, day: 3), allDay])
        XCTAssertEqual(s.tomorrow, CalendarSnapshot.Tomorrow(count: 3, firstStart: at(9, day: 3)))
    }

    func testTomorrowWithOnlyAnAllDayEventHasNoFirstStart() {
        let allDay = event("Trip", at(0, day: 3), at(23, 59, day: 3, second: 59), allDay: true)
        XCTAssertEqual(snapshot([allDay]).tomorrow, CalendarSnapshot.Tomorrow(count: 1, firstStart: nil))
    }

    func testAnEmptyTomorrowIsAKnownZero() {
        XCTAssertEqual(snapshot([]).tomorrow, CalendarSnapshot.Tomorrow(count: 0, firstStart: nil))
    }

    func testAnEventThatStartedTodayAndRunsPastMidnightBelongsToToday() {
        let lateNow = at(23, 30)
        let late = event("Late", at(23), at(1, day: 3))
        let s = CalendarSnapshot.make(events: [late], readAt: lateNow, now: lateNow, calendar: cal)
        XCTAssertEqual(s.focus, .now(late))
        XCTAssertEqual(s.tomorrow, CalendarSnapshot.Tomorrow(count: 0, firstStart: nil))
    }

    func testTomorrowIsUnknownNotZeroWhenTheReadWasYesterday() {
        // The read covered the 1st and 2nd; "tomorrow" is the 3rd, which it did not.
        let s = CalendarSnapshot.make(events: [timed("Today", 11)], readAt: at(9, day: 1), now: now, calendar: cal)
        XCTAssertTrue(s.covered)
        XCTAssertNil(s.tomorrow)
        XCTAssertEqual(s.focus, .next(timed("Today", 11)))
    }

    func testAReadTwoDaysOldDoesNotCoverToday() {
        let s = CalendarSnapshot.make(events: [timed("Today", 11)], readAt: at(9, day: 2), now: at(10, day: 5),
                                      calendar: cal)
        XCTAssertFalse(s.covered)
        XCTAssertNil(s.tomorrow)
        XCTAssertNil(s.focus)
    }

    // MARK: Empty and denied

    func testNothingTodayIsEmpty() {
        let s = snapshot([])
        XCTAssertTrue(s.isEmptyToday)
        XCTAssertFalse(s.isDoneForToday)
        XCTAssertNil(s.focus)
        XCTAssertEqual(CalendarFormat.emptyText, "Nothing on the calendar today.")
    }

    func testAuthorizationStatesMapToReadableOrNot() {
        XCTAssertEqual(CalendarAccess(.fullAccess), .granted)
        XCTAssertEqual(CalendarAccess(.notDetermined), .notDetermined)
        XCTAssertEqual(CalendarAccess(.denied), .denied)
        XCTAssertEqual(CalendarAccess(.restricted), .denied)
        // Write-only cannot read, so it is the same dead end as denied.
        XCTAssertEqual(CalendarAccess(.writeOnly), .denied)
        XCTAssertTrue(CalendarAccess.granted.canRead)
        XCTAssertFalse(CalendarAccess.denied.canRead)
        XCTAssertFalse(CalendarAccess.notDetermined.canRead)
    }

    func testDeniedCopyAndSettingsLink() {
        XCTAssertEqual(CalendarFormat.deniedText,
                       "Calendar access is off. Allow it in System Settings > Privacy & Security > Calendars")
        XCTAssertEqual(CalendarFormat.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    }

    // MARK: Labels

    func testTimeUntil() {
        let t = now
        XCTAssertEqual(CalendarFormat.timeUntil(t, now: t), "now")
        XCTAssertEqual(CalendarFormat.timeUntil(t.addingTimeInterval(-90), now: t), "now")
        XCTAssertEqual(CalendarFormat.timeUntil(t.addingTimeInterval(30), now: t), "in 1 min")
        XCTAssertEqual(CalendarFormat.timeUntil(t.addingTimeInterval(14 * 60), now: t), "in 14 min")
        XCTAssertEqual(CalendarFormat.timeUntil(t.addingTimeInterval(14 * 60 + 1), now: t), "in 15 min")
        XCTAssertEqual(CalendarFormat.timeUntil(t.addingTimeInterval(59 * 60), now: t), "in 59 min")
        XCTAssertEqual(CalendarFormat.timeUntil(t.addingTimeInterval(3600), now: t), "in 1 h")
        XCTAssertEqual(CalendarFormat.timeUntil(t.addingTimeInterval(65 * 60), now: t), "in 1 h 5 min")
        XCTAssertEqual(CalendarFormat.timeUntil(t.addingTimeInterval(3 * 3600), now: t), "in 3 h")
        XCTAssertEqual(CalendarFormat.timeUntil(t.addingTimeInterval(49 * 3600), now: t), "in 2 d")
    }

    func testOnlyANextEventWithinFifteenMinutesIsImminent() {
        XCTAssertTrue(CalendarFormat.isImminent(.next(timed("A", 10, 15)), now: now))
        XCTAssertTrue(CalendarFormat.isImminent(.next(timed("A", 10, 1)), now: now))
        XCTAssertFalse(CalendarFormat.isImminent(.next(timed("A", 10, 16)), now: now))
        XCTAssertFalse(CalendarFormat.isImminent(.now(timed("A", 9, 50)), now: now))
        XCTAssertFalse(CalendarFormat.isImminent(nil, now: now))
    }

    func testTimeLabelIsPlainAmPm() {
        XCTAssertEqual(CalendarFormat.timeLabel(at(9), calendar: cal, locale: us), "9:00 AM")
        XCTAssertEqual(CalendarFormat.timeLabel(at(15, 5), calendar: cal, locale: us), "3:05 PM")
    }

    func testTomorrowLine() {
        func line(_ t: CalendarSnapshot.Tomorrow?) -> String? {
            CalendarFormat.tomorrowLine(t, calendar: cal, locale: us)
        }
        XCTAssertEqual(line(.init(count: 3, firstStart: at(9, day: 3))), "Tomorrow: 3 events, first at 9:00 AM")
        XCTAssertEqual(line(.init(count: 1, firstStart: at(14, 30, day: 3))), "Tomorrow: 1 event, first at 2:30 PM")
        XCTAssertEqual(line(.init(count: 2, firstStart: nil)), "Tomorrow: 2 events, all day")
        XCTAssertEqual(line(.init(count: 0, firstStart: nil)), "Tomorrow: no events")
        XCTAssertNil(line(nil), "an unread tomorrow says nothing rather than 'no events'")
    }

    func testAllDayLine() {
        func e(_ t: String) -> CalendarEventInfo { event(t, at(0), at(23, 59), allDay: true) }
        XCTAssertNil(CalendarFormat.allDayLine([]))
        XCTAssertEqual(CalendarFormat.allDayLine([e("Holiday")]), "All day: Holiday")
        XCTAssertEqual(CalendarFormat.allDayLine([e("A"), e("B")]), "All day: A, B")
        XCTAssertEqual(CalendarFormat.allDayLine([e("A"), e("B"), e("C"), e("D")]), "All day: A, B +2 more")
    }

    func testFocusDetailIncludesTheLocationOnlyWhenThereIsOne() {
        let withRoom = event("Sync", at(11), at(11, 30), location: "Room 4")
        let without = event("Sync", at(11), at(11, 30))
        XCTAssertEqual(CalendarFormat.focusDetail(.next(withRoom), calendar: cal, locale: us),
                       "11:00 AM – 11:30 AM · Room 4")
        XCTAssertEqual(CalendarFormat.focusDetail(.next(without), calendar: cal, locale: us),
                       "11:00 AM – 11:30 AM")
        XCTAssertEqual(CalendarFormat.focusDetail(.now(withRoom), calendar: cal, locale: us),
                       "until 11:30 AM · Room 4")
    }

    func testSpokenFocus() {
        let e = event("Sync", at(10, 10), at(10, 40), location: "Room 4")
        XCTAssertEqual(CalendarFormat.spokenFocus(.next(e), now: now, calendar: cal, locale: us),
                       "Next: Sync at 10:10 AM, in 10 min, Room 4")
        XCTAssertEqual(CalendarFormat.spokenFocus(.now(event("Sync", at(9, 40), at(10, 40))), now: now,
                                                  calendar: cal, locale: us),
                       "Now: Sync, until 10:40 AM")
    }

    func testUpdatedStaleness() {
        XCTAssertFalse(CalendarFormat.isStale(readAt: at(0), now: at(23, 59), calendar: cal))
        XCTAssertTrue(CalendarFormat.isStale(readAt: at(23, day: 1), now: at(0, 5), calendar: cal))
    }
}
