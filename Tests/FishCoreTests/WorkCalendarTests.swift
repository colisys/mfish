import XCTest
@testable import FishCore

final class WorkCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private var fixture2026: HolidayYear {
        HolidayYear(year: 2026, days: [
            HolidayDay(name: "元旦", date: "2026-01-01", isOffDay: true),
            HolidayDay(name: "元旦", date: "2026-01-02", isOffDay: true),
            HolidayDay(name: "元旦", date: "2026-01-03", isOffDay: true),
            HolidayDay(name: "元旦", date: "2026-01-04", isOffDay: false),
            HolidayDay(name: "春节", date: "2026-02-14", isOffDay: false),
            HolidayDay(name: "春节", date: "2026-02-15", isOffDay: true),
            HolidayDay(name: "春节", date: "2026-02-16", isOffDay: true),
            HolidayDay(name: "春节", date: "2026-02-17", isOffDay: true),
            HolidayDay(name: "春节", date: "2026-02-18", isOffDay: true),
            HolidayDay(name: "春节", date: "2026-02-19", isOffDay: true),
            HolidayDay(name: "春节", date: "2026-02-20", isOffDay: true),
            HolidayDay(name: "春节", date: "2026-02-21", isOffDay: true),
            HolidayDay(name: "春节", date: "2026-02-22", isOffDay: true),
            HolidayDay(name: "春节", date: "2026-02-23", isOffDay: true),
            HolidayDay(name: "春节", date: "2026-02-28", isOffDay: false),
        ])
    }

    private var fixture2027: HolidayYear {
        HolidayYear(year: 2027, days: [
            HolidayDay(name: "元旦", date: "2027-01-01", isOffDay: true),
            HolidayDay(name: "元旦", date: "2027-01-02", isOffDay: true),
            HolidayDay(name: "元旦", date: "2027-01-03", isOffDay: true),
        ])
    }

    private func schedule(_ mode: WeekMode, single: Bool = false) -> WorkSchedule {
        WorkSchedule(enabled: true, weekMode: mode, anchorMonday: "2026-11-09", anchorIsSingle: single)
    }

    func testPeriodOverrideReplacesRangeAndDropsMakeupDays() {
        let ov = HolidayOverride(name: "春节", start: "2026-02-16", end: "2026-02-20")
        let cal = HolidayCalendar(years: [fixture2026], overrides: [ov], calendar: calendar)
        XCTAssertTrue(cal.isRestDay(on: date(2026, 2, 17)))
        XCTAssertEqual(cal.holidayName(on: date(2026, 2, 17)), "春节")
        XCTAssertFalse(cal.isRestDay(on: date(2026, 2, 23)))   // was off, now outside range (Monday)
        XCTAssertNil(cal.holidayName(on: date(2026, 2, 23)))
        XCTAssertTrue(cal.isRestDay(on: date(2026, 2, 14)))    // makeup dropped, plain Saturday
        XCTAssertFalse(cal.isMakeupWorkday(on: date(2026, 2, 14)))
        XCTAssertEqual(cal.periods(inYear: 2026).first { $0.name == "春节" }?.dayCount, 5)
    }

    func testPeriodOverrideScopedToTouchedYears() {
        let ov = HolidayOverride(name: "元旦", start: "2026-01-01", end: "2026-01-01")
        let cal = HolidayCalendar(years: [fixture2026, fixture2027], overrides: [ov], calendar: calendar)
        XCTAssertFalse(cal.isRestDay(on: date(2026, 1, 2)))    // Friday, removed from 元旦
        XCTAssertTrue(cal.isRestDay(on: date(2027, 1, 2)))     // 2027 元旦 untouched
        XCTAssertEqual(cal.holidayName(on: date(2027, 1, 2)), "元旦")
    }

    func testCustomHolidayPeriod() {
        let ov = HolidayOverride(name: "公司福利假", start: "2026-11-20", end: "2026-11-21")
        let cal = HolidayCalendar(years: [fixture2026, fixture2027], overrides: [ov], calendar: calendar)
        XCTAssertTrue(cal.isRestDay(on: date(2026, 11, 20)))   // Friday
        XCTAssertEqual(cal.nextHoliday(after: date(2026, 11, 9))?.name, "公司福利假")
        XCTAssertTrue(cal.hasData(forYear: 2026))
    }

    func testInvalidOverrideIgnored() {
        let bad = HolidayOverride(name: "春节", start: "2026-02-20", end: "2026-02-16")  // reversed
        let cal = HolidayCalendar(years: [fixture2026], overrides: [bad], calendar: calendar)
        XCTAssertTrue(cal.isRestDay(on: date(2026, 2, 23)))    // original intact
        XCTAssertNil(HolidayOverride(name: "", start: "2026-01-01", end: "2026-01-02").dateRange(calendar: calendar))
        XCTAssertNil(HolidayOverride(name: "x", start: "2026-13-01", end: "2026-01-02").dateRange(calendar: calendar))
    }

    func testCustomMakeupWorkday() {
        let dov = DayOverride(date: "2026-11-14", isOffDay: false, name: "公司调休")  // Saturday
        let holidays = HolidayCalendar(years: [fixture2026], dayOverrides: [dov], calendar: calendar)
        XCTAssertTrue(holidays.isMakeupWorkday(on: date(2026, 11, 14)))
        XCTAssertEqual(holidays.makeupName(on: date(2026, 11, 14)), "公司调休")
        let work = WorkCalendar(holidays: holidays, schedule: schedule(.double), calendar: calendar)
        XCTAssertFalse(work.isRestDay(on: date(2026, 11, 14)))  // makeup beats double-week schedule
        XCTAssertEqual(work.kind(on: date(2026, 11, 14)), .makeupWorkday("公司调休"))
    }

    func testCustomRestDay() {
        let dov = DayOverride(date: "2026-11-13", isOffDay: true, name: "司庆")  // Friday
        let holidays = HolidayCalendar(years: [fixture2026], dayOverrides: [dov], calendar: calendar)
        let work = WorkCalendar(holidays: holidays, schedule: schedule(.single, single: true), calendar: calendar)
        XCTAssertTrue(work.isRestDay(on: date(2026, 11, 13)))
        XCTAssertEqual(work.kind(on: date(2026, 11, 13)), .holiday("司庆"))
    }

    func testDayOverrideBeatsPeriodOverride() {
        let ov = HolidayOverride(name: "春节", start: "2026-02-16", end: "2026-02-20")
        let dov = DayOverride(date: "2026-02-17", isOffDay: false, name: "公司调休")
        let cal = HolidayCalendar(years: [fixture2026], overrides: [ov], dayOverrides: [dov], calendar: calendar)
        XCTAssertFalse(cal.isRestDay(on: date(2026, 2, 17)))
        XCTAssertTrue(cal.isMakeupWorkday(on: date(2026, 2, 17)))
    }

    func testAlternatingWeeks() {
        let work = WorkCalendar(holidays: HolidayCalendar(years: [], calendar: calendar),
                                schedule: schedule(.alternating, single: true), calendar: calendar)
        XCTAssertFalse(work.isRestDay(on: date(2026, 11, 14)))  // anchor week Saturday: 单休上班
        XCTAssertTrue(work.isRestDay(on: date(2026, 11, 21)))   // next week: 双休
        XCTAssertFalse(work.isRestDay(on: date(2026, 11, 28)))  // single again
        XCTAssertTrue(work.isRestDay(on: date(2026, 11, 7)))    // week before anchor: double
        XCTAssertTrue(work.isRestDay(on: date(2026, 11, 15)))   // Sunday always rest
        XCTAssertFalse(work.isRestDay(on: date(2026, 11, 9)))   // Monday always work
    }

    func testSingleAndDoubleModes() {
        let holidays = HolidayCalendar(years: [], calendar: calendar)
        let single = WorkCalendar(holidays: holidays, schedule: schedule(.single), calendar: calendar)
        XCTAssertFalse(single.isRestDay(on: date(2026, 11, 14)))
        let double = WorkCalendar(holidays: holidays, schedule: schedule(.double), calendar: calendar)
        XCTAssertTrue(double.isRestDay(on: date(2026, 11, 14)))
    }

    func testHolidayBeatsScheduleAndMakeupBeatsSchedule() {
        let work = WorkCalendar(holidays: HolidayCalendar(years: [fixture2026], calendar: calendar),
                                schedule: schedule(.single, single: true), calendar: calendar)
        XCTAssertTrue(work.isRestDay(on: date(2026, 2, 21)))    // 春节 Saturday beats single-week work
        XCTAssertEqual(work.kind(on: date(2026, 2, 21)), .holiday("春节"))
        let double = WorkCalendar(holidays: HolidayCalendar(years: [fixture2026], calendar: calendar),
                                  schedule: schedule(.double), calendar: calendar)
        XCTAssertFalse(double.isRestDay(on: date(2026, 2, 14))) // national makeup beats double-week rest
    }

    func testNextRestDayWithSingleWeek() {
        let work = WorkCalendar(holidays: HolidayCalendar(years: [], calendar: calendar),
                                schedule: schedule(.single), calendar: calendar)
        let next = work.nextRestDay(after: date(2026, 11, 13, 10))  // Friday → skips working Saturday
        XCTAssertEqual(next?.date, date(2026, 11, 15, 0))
    }

    func testDisabledScheduleFallsBackToWeekend() {
        var s = schedule(.single)
        s.enabled = false
        let work = WorkCalendar(holidays: HolidayCalendar(years: [], calendar: calendar),
                                schedule: s, calendar: calendar)
        XCTAssertTrue(work.isRestDay(on: date(2026, 11, 14)))
    }

    func testCustomRestWeekdays() {
        var s = schedule(.double)
        s.restWeekdays = [2, 4]  // Monday + Wednesday rest
        let work = WorkCalendar(holidays: HolidayCalendar(years: [], calendar: calendar),
                                schedule: s, calendar: calendar)
        XCTAssertTrue(work.isRestDay(on: date(2026, 11, 9)))    // Monday
        XCTAssertTrue(work.isRestDay(on: date(2026, 11, 11)))   // Wednesday
        XCTAssertFalse(work.isRestDay(on: date(2026, 11, 14)))  // Saturday now works
        XCTAssertFalse(work.isRestDay(on: date(2026, 11, 15)))  // Sunday now works
        let next = work.nextRestDay(after: date(2026, 11, 13))  // Friday → Monday
        XCTAssertEqual(next?.date, date(2026, 11, 16, 0))
    }

    func testCustomSingleRestWeekday() {
        var s = schedule(.single)
        s.singleRestWeekdays = [3]  // Tuesday rest only
        let work = WorkCalendar(holidays: HolidayCalendar(years: [], calendar: calendar),
                                schedule: s, calendar: calendar)
        XCTAssertTrue(work.isRestDay(on: date(2026, 11, 10)))   // Tuesday
        XCTAssertFalse(work.isRestDay(on: date(2026, 11, 15)))  // Sunday now works
        XCTAssertFalse(work.isRestDay(on: date(2026, 11, 14)))  // Saturday works
    }

    func testAlternatingCustomRestDays() {
        var s = schedule(.alternating, single: true)
        s.restWeekdays = [1, 7]
        s.singleRestWeekdays = [1, 6]  // 单休周: Friday + Sunday rest
        let work = WorkCalendar(holidays: HolidayCalendar(years: [], calendar: calendar),
                                schedule: s, calendar: calendar)
        XCTAssertTrue(work.isRestDay(on: date(2026, 11, 13)))   // anchor week Friday: 单休周休息
        XCTAssertFalse(work.isRestDay(on: date(2026, 11, 14)))  // anchor week Saturday: 上班
        XCTAssertFalse(work.isRestDay(on: date(2026, 11, 20)))  // next week Friday: 双休周上班
        XCTAssertTrue(work.isRestDay(on: date(2026, 11, 21)))   // next week Saturday: 双休
        XCTAssertTrue(work.isRestDay(on: date(2026, 11, 15)))   // Sunday rest in both sets
    }
}