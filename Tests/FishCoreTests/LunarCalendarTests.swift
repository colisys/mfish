import XCTest
@testable import FishCore

final class LunarCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testLunarDateToday() {
        let lunar = LunarCalendar.lunar(for: date(2026, 11, 9), calendar: calendar)
        XCTAssertEqual(lunar.monthName, "十月")
        XCTAssertEqual(lunar.dayName, "初一")
        XCTAssertEqual(lunar.yearGanzhi, "丙午")
        XCTAssertEqual(lunar.zodiac, "马")
        XCTAssertEqual(lunar.fullText, "丙午年【马】十月初一")
    }

    func testYearSwitchesAtSpringFestival() {
        let eve = LunarCalendar.lunar(for: date(2026, 2, 16), calendar: calendar)
        XCTAssertEqual(eve.monthName, "腊月")
        XCTAssertEqual(eve.dayName, "廿九")
        XCTAssertEqual(eve.yearGanzhi, "乙巳")
        XCTAssertEqual(eve.zodiac, "蛇")
        let newYear = LunarCalendar.lunar(for: date(2026, 2, 17), calendar: calendar)
        XCTAssertEqual(newYear.monthName, "正月")
        XCTAssertEqual(newYear.dayName, "初一")
        XCTAssertEqual(newYear.yearGanzhi, "丙午")
    }

    func testLeapMonth() {
        let lunar = LunarCalendar.lunar(for: date(2025, 7, 25), calendar: calendar)
        XCTAssertEqual(lunar.monthName, "闰六月")
        XCTAssertEqual(lunar.dayName, "初一")
        let normal = LunarCalendar.lunar(for: date(2025, 6, 25), calendar: calendar)
        XCTAssertEqual(normal.monthName, "六月")
    }

    func testDayGanzhiAnchor() {
        XCTAssertEqual(LunarCalendar.lunar(for: date(1949, 10, 1), calendar: calendar).dayGanzhi, "甲子")
        XCTAssertEqual(LunarCalendar.lunar(for: date(2000, 1, 1), calendar: calendar).dayGanzhi, "戊午")
        let next = LunarCalendar.lunar(for: date(1949, 10, 2), calendar: calendar)
        XCTAssertEqual(next.dayGanzhi, "乙丑")
    }
}