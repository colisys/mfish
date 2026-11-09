import XCTest
@testable import FishCore

final class HolidayCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Mirrors holiday-cn's real 2026 Spring Festival shape, including makeup
    /// workdays on 02-14 (Saturday) and 02-28 (Saturday).
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

    func testWeekendFallbackWithoutData() {
        let cal = HolidayCalendar(years: [], calendar: calendar)
        XCTAssertTrue(cal.isRestDay(on: date(2026, 11, 14)))  // Saturday
        XCTAssertTrue(cal.isRestDay(on: date(2026, 11, 15)))  // Sunday
        XCTAssertFalse(cal.isRestDay(on: date(2026, 11, 9)))  // Monday
        XCTAssertFalse(cal.hasData(forYear: 2026))
    }

    func testMakeupSaturdayIsWorkday() {
        let cal = HolidayCalendar(years: [fixture2026], calendar: calendar)
        XCTAssertFalse(cal.isRestDay(on: date(2026, 2, 14)))
        XCTAssertFalse(cal.isRestDay(on: date(2026, 2, 28)))
        XCTAssertTrue(cal.hasData(forYear: 2026))
    }

    func testHolidayWeekdayIsRestDay() {
        let cal = HolidayCalendar(years: [fixture2026], calendar: calendar)
        XCTAssertTrue(cal.isRestDay(on: date(2026, 2, 17)))  // Tuesday, 春节
        XCTAssertEqual(cal.holidayName(on: date(2026, 2, 17)), "春节")
        XCTAssertNil(cal.holidayName(on: date(2026, 11, 14)))  // plain weekend
    }

    func testNextRestDaySkipsMakeupWorkday() {
        let cal = HolidayCalendar(years: [fixture2026], calendar: calendar)
        let next = cal.nextRestDay(after: date(2026, 2, 13, 10))  // Friday
        XCTAssertEqual(next?.date, date(2026, 2, 15, 0))
        XCTAssertEqual(next?.name, "春节")
    }

    func testNextRestDayFallsBackToWeekend() {
        let cal = HolidayCalendar(years: [fixture2026], calendar: calendar)
        let next = cal.nextRestDay(after: date(2026, 11, 9, 9))  // Monday, no holiday nearby
        XCTAssertEqual(next?.date, date(2026, 11, 14, 0))
        XCTAssertNil(next?.name)
    }

    func testNextRestDayCrossesYearBoundary() {
        let cal = HolidayCalendar(years: [fixture2026, fixture2027], calendar: calendar)
        let next = cal.nextRestDay(after: date(2026, 12, 31, 10))  // Thursday
        XCTAssertEqual(next?.date, date(2027, 1, 1, 0))
        XCTAssertEqual(next?.name, "元旦")
    }

    func testNextHolidaySkipsCurrentPeriod() {
        let cal = HolidayCalendar(years: [fixture2026, fixture2027], calendar: calendar)
        let next = cal.nextHoliday(after: date(2026, 2, 17))  // mid-春节
        XCTAssertEqual(next?.name, "元旦")
        XCTAssertEqual(next?.start, date(2027, 1, 1, 0))
        XCTAssertEqual(next?.dayCount, 3)
    }

    func testNextHolidayFromOrdinaryDay() {
        let cal = HolidayCalendar(years: [fixture2026, fixture2027], calendar: calendar)
        let next = cal.nextHoliday(after: date(2026, 11, 9))
        XCTAssertEqual(next?.name, "元旦")
        XCTAssertEqual(next?.start, date(2027, 1, 1, 0))
    }

    func testPeriodGroupingExcludesMakeupDays() {
        let cal = HolidayCalendar(years: [fixture2026], calendar: calendar)
        let periods = cal.periods(inYear: 2026)
        let spring = periods.first { $0.name == "春节" }
        XCTAssertEqual(spring?.start, date(2026, 2, 15, 0))
        XCTAssertEqual(spring?.end, date(2026, 2, 23, 0))
        XCTAssertEqual(spring?.dayCount, 9)
        XCTAssertEqual(periods.first { $0.name == "元旦" }?.dayCount, 3)
    }

    func testRemainingRestDays() {
        let cal = HolidayCalendar(years: [fixture2026], calendar: calendar)
        XCTAssertEqual(cal.remainingRestDays(inYear: 2026, from: date(2026, 12, 25)), 2)  // Sat+Sun
        XCTAssertEqual(cal.remainingRestDays(inYear: 2026, from: date(2026, 12, 28)), 0)  // Mon-Thu
    }

    func testDayKeyUsesLocalTimezone() {
        let cal = HolidayCalendar(years: [], calendar: calendar)
        XCTAssertEqual(cal.dayKey(for: date(2026, 11, 9, 23)), "2026-11-09")
    }

    func testDecodesRealSourceShape() throws {
        let json = """
        {"$schema":"https://example.com/schema.json","$id":"https://example.com/2026.json",
         "year":2026,"papers":["https://www.gov.cn/example.htm"],
         "days":[{"name":"元旦","date":"2026-01-01","isOffDay":true},
                 {"name":"元旦","date":"2026-01-04","isOffDay":false}]}
        """
        let decoded = try JSONDecoder().decode(HolidayYear.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.year, 2026)
        XCTAssertEqual(decoded.days.count, 2)
        let cal = HolidayCalendar(years: [decoded], calendar: calendar)
        XCTAssertTrue(cal.isRestDay(on: date(2026, 1, 1)))
        XCTAssertFalse(cal.isRestDay(on: date(2026, 1, 4)))  // Sunday makeup
    }
}