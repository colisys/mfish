import XCTest
@testable import FishCore

final class ReminderEngineTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func workCalendar(schedule: WorkSchedule? = nil) -> WorkCalendar {
        let s = schedule ?? WorkSchedule(enabled: true)
        let holidays = HolidayCalendar(years: [
            HolidayYear(year: 2026, days: [
                HolidayDay(name: "春节", date: "2026-02-14", isOffDay: false),
                HolidayDay(name: "春节", date: "2026-02-17", isOffDay: true),
            ]),
        ], calendar: calendar)
        return WorkCalendar(holidays: holidays, schedule: s, calendar: calendar)
    }

    func testWorkStartFiresWithinGrace() {
        let due = ReminderEngine.due(now: date(2026, 11, 9, 9, 5), workCalendar: workCalendar(),
                                     customs: [], fired: [], calendar: calendar)
        XCTAssertEqual(due.map(\.key), ["work-start-2026-11-09"])
    }

    func testWorkStartBoundaries() {
        let cal = workCalendar()
        XCTAssertTrue(ReminderEngine.due(now: date(2026, 11, 9, 8, 59), workCalendar: cal,
                                         customs: [], fired: [], calendar: calendar).isEmpty)
        XCTAssertTrue(ReminderEngine.due(now: date(2026, 11, 9, 9, 31), workCalendar: cal,
                                         customs: [], fired: [], calendar: calendar).isEmpty)
        XCTAssertFalse(ReminderEngine.due(now: date(2026, 11, 9, 9, 30), workCalendar: cal,
                                          customs: [], fired: [], calendar: calendar).isEmpty)
    }

    func testFiredKeySuppresses() {
        let due = ReminderEngine.due(now: date(2026, 11, 9, 9, 5), workCalendar: workCalendar(),
                                     customs: [], fired: ["work-start-2026-11-09"], calendar: calendar)
        XCTAssertTrue(due.isEmpty)
    }

    func testSkipsRestDaysAndHolidaysButNotMakeup() {
        let cal = workCalendar()
        XCTAssertTrue(ReminderEngine.due(now: date(2026, 11, 14, 9, 5), workCalendar: cal,
                                         customs: [], fired: [], calendar: calendar).isEmpty)  // Saturday
        XCTAssertTrue(ReminderEngine.due(now: date(2026, 2, 17, 9, 5), workCalendar: cal,
                                         customs: [], fired: [], calendar: calendar).isEmpty)  // 春节
        XCTAssertFalse(ReminderEngine.due(now: date(2026, 2, 14, 9, 5), workCalendar: cal,
                                          customs: [], fired: [], calendar: calendar).isEmpty) // 调休上班
    }

    func testWorkEndAndDisabledReminders() {
        var s = WorkSchedule(enabled: true)
        s.remindStart = false
        let due = ReminderEngine.due(now: date(2026, 11, 9, 18, 10), workCalendar: workCalendar(schedule: s),
                                     customs: [], fired: [], calendar: calendar)
        XCTAssertEqual(due.map(\.key), ["work-end-2026-11-09"])
        s.enabled = false
        XCTAssertTrue(ReminderEngine.due(now: date(2026, 11, 9, 18, 10), workCalendar: workCalendar(schedule: s),
                                         customs: [], fired: [], calendar: calendar).isEmpty)
    }

    func testCustomRules() {
        let cal = workCalendar()
        let daily = CustomReminder(title: "喝水", minutes: 750, rule: .daily)
        let workdays = CustomReminder(title: "站会", minutes: 545, rule: .workdays)
        let monday = CustomReminder(title: "周报", minutes: 545, rule: .weekly([2]))
        let sunday = CustomReminder(title: "买菜", minutes: 545, rule: .weekly([1]))
        let customs = [daily, workdays, monday, sunday]
        let mondayDue = ReminderEngine.due(now: date(2026, 11, 9, 9, 5), workCalendar: cal,
                                           customs: customs, fired: [], calendar: calendar)
        XCTAssertTrue(mondayDue.contains { $0.title == "站会" })
        XCTAssertTrue(mondayDue.contains { $0.title == "周报" })
        XCTAssertFalse(mondayDue.contains { $0.title == "买菜" })
        XCTAssertFalse(mondayDue.contains { $0.title == "喝水" })  // 12:30 not yet
        let saturdayDue = ReminderEngine.due(now: date(2026, 11, 14, 9, 5), workCalendar: cal,
                                             customs: customs, fired: [], calendar: calendar)
        XCTAssertFalse(saturdayDue.contains { $0.title == "站会" })  // workdays rule skips Saturday
        let noonDue = ReminderEngine.due(now: date(2026, 11, 14, 12, 30), workCalendar: cal,
                                         customs: customs, fired: [], calendar: calendar)
        XCTAssertTrue(noonDue.contains { $0.title == "喝水" })       // daily fires on Saturday
    }

    func testOnceReminder() {
        var s = WorkSchedule(enabled: true)
        s.remindStart = false
        s.remindEnd = false
        let cal = workCalendar(schedule: s)
        let id = UUID()
        let once = CustomReminder(id: id, title: "开会", minutes: 545, rule: .once("2026-11-09"))
        let due = ReminderEngine.due(now: date(2026, 11, 9, 9, 5), workCalendar: cal,
                                     customs: [once], fired: [], calendar: calendar)
        let event = due.first { $0.title == "开会" }
        XCTAssertEqual(event?.key, "once-\(id.uuidString)")
        XCTAssertEqual(event?.disablesReminderID, id)
        XCTAssertTrue(ReminderEngine.due(now: date(2026, 11, 10, 9, 5), workCalendar: cal,
                                         customs: [once], fired: [], calendar: calendar).isEmpty)
        XCTAssertTrue(ReminderEngine.due(now: date(2026, 11, 9, 9, 5), workCalendar: cal,
                                         customs: [once], fired: ["once-\(id.uuidString)"],
                                         calendar: calendar).isEmpty)
    }

    func testPruneFiredKeys() {
        let keys: Set<String> = ["work-start-2026-11-01", "work-start-2026-11-03",
                                 "custom-abc-2026-11-09", "once-xyz"]
        let pruned = ReminderEngine.pruneFiredKeys(keys, now: date(2026, 11, 9), calendar: calendar)
        XCTAssertEqual(pruned, ["work-start-2026-11-03", "custom-abc-2026-11-09", "once-xyz"])
    }
}