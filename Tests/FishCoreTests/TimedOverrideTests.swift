import XCTest
@testable import FishCore

final class TimedOverrideTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return result
    }

    private var schedule: WorkSchedule {
        WorkSchedule(startMinutes: 540, endMinutes: 1080, lunchEnabled: true,
                     lunchStartMinutes: 720, lunchEndMinutes: 780)
    }

    private func date(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func override(_ day: Int = 9, off: Bool = true,
                          start: Int? = nil, end: Int? = nil) -> DayOverride {
        DayOverride(date: String(format: "2026-11-%02d", day), isOffDay: off, name: "自定义",
                    startMinutes: start, endMinutes: end)
    }

    private func work(_ overrides: [DayOverride], years: [HolidayYear] = []) -> WorkCalendar {
        WorkCalendar(holidays: HolidayCalendar(years: years, dayOverrides: overrides, calendar: calendar),
                     schedule: schedule, calendar: calendar)
    }

    func testLegacyCodableAndRoundTrips() throws {
        let old = #"{"id":"00000000-0000-0000-0000-000000000001","date":"2026-11-09","isOffDay":true,"name":"休息"}"#
        let decoded = try JSONDecoder().decode(DayOverride.self, from: Data(old.utf8))
        XCTAssertNil(decoded.startMinutes)
        XCTAssertNil(decoded.endMinutes)
        XCTAssertTrue(decoded.isAllDay)
        XCTAssertTrue(decoded.isValid(calendar: calendar))
        for value in [decoded, override(start: 690, end: 750), override(off: false, start: 0, end: 1440)] {
            XCTAssertEqual(try JSONDecoder().decode(DayOverride.self, from: JSONEncoder().encode(value)), value)
        }
        let config = try JSONDecoder().decode(FishConfig.self, from: Data("{\"dayOverrides\":[\(old)]}".utf8))
        XCTAssertEqual(config.dayOverrides, [decoded])
    }

    func testValidation() {
        for (start, end) in [(nil, nil), (0, 1440), (540, 1080)] as [(Int?, Int?)] {
            XCTAssertTrue(override(start: start, end: end).isValid(calendar: calendar))
        }
        for (start, end) in [(nil, 600), (600, nil), (-1, 600), (0, 1441),
                             (1440, 1440), (600, 600), (800, 600)] as [(Int?, Int?)] {
            let invalid = override(start: start, end: end)
            XCTAssertFalse(invalid.isValid(calendar: calendar))
            XCTAssertEqual(work([invalid]).scheduledWorkDuration(on: date(9)), 8 * 3600)
            XCTAssertNil(work([invalid]).holidays.timedOverride(on: date(9)))
        }
        var invalid = override(start: 540, end: 600)
        invalid.date = "2026-02-30"
        XCTAssertFalse(invalid.isValid(calendar: calendar))
        invalid.date = "2026-11-09"
        invalid.name = " "
        XCTAssertFalse(invalid.isValid(calendar: calendar))
    }

    func testPartialRestDoesNotBecomeHolidayOrPeriod() {
        let value = override(start: 690, end: 750)
        let holidays = work([value]).holidays
        XCTAssertFalse(holidays.isRestDay(on: date(9)))
        XCTAssertNil(holidays.holidayName(on: date(9)))
        XCTAssertEqual(holidays.periods(inYear: 2026), [])
        XCTAssertNil(holidays.nextHoliday(after: date(8)))
        XCTAssertEqual(holidays.timedOverride(on: date(9)), value)
    }

    func testRestSubtractsOnlyNetIntersection() {
        // 09:00–18:00 with lunch 12:00–13:00.
        for (start, end, minutes) in [(690, 750, 450), (750, 810, 450), (690, 810, 420),
                                      (720, 780, 480), (0, 570, 450), (1050, 1440, 450),
                                      (0, 500, 480), (1100, 1440, 480), (0, 1440, 0)] {
            XCTAssertEqual(work([override(start: start, end: end)]).scheduledWorkDuration(on: date(9)),
                           Double(minutes * 60), "\(start)..<\(end)")
        }
        XCTAssertEqual(work([override(14, start: 540, end: 600)]).scheduledWorkDuration(on: date(14)), 0)
        let source = HolidayYear(year: 2026, days: [HolidayDay(name: "原假期", date: "2026-11-09", isOffDay: true)])
        let result = work([override(start: 540, end: 600)], years: [source])
        XCTAssertEqual(result.scheduledWorkDuration(on: date(9)), 0)
        XCTAssertEqual(result.holidays.holidayName(on: date(9)), "原假期")
    }

    func testTimedWorkReplacesIntervalEvenOnHolidayOrWeekend() {
        for (start, end, minutes) in [(690, 750, 30), (750, 810, 30), (720, 780, 0),
                                      (360, 540, 180), (1080, 1440, 360)] {
            XCTAssertEqual(work([override(14, off: false, start: start, end: end)])
                .scheduledWorkDuration(on: date(14)), Double(minutes * 60))
        }
        let source = HolidayYear(year: 2026, days: [HolidayDay(name: "原假期", date: "2026-11-09", isOffDay: true)])
        let result = work([override(off: false, start: 750, end: 840)], years: [source])
        XCTAssertEqual(result.scheduledWorkDuration(on: date(9)), 3600)
        XCTAssertFalse(result.isRestDay(on: date(9)))
        XCTAssertTrue(result.holidays.periods(inYear: 2026).isEmpty)
    }

    func testAllDayAndLastValidOverrideWins() {
        let full = override()
        let partial = override(start: 540, end: 600)
        XCTAssertEqual(work([full]).scheduledWorkDuration(on: date(9)), 0)
        XCTAssertEqual(work([override(14, off: false)]).scheduledWorkDuration(on: date(14)), 8 * 3600)
        XCTAssertEqual(work([full, partial]).scheduledWorkDuration(on: date(9)), 7 * 3600)
        XCTAssertEqual(work([partial, full]).scheduledWorkDuration(on: date(9)), 0)
        XCTAssertNil(work([partial, full]).holidays.timedOverride(on: date(9)))
        XCTAssertEqual(work([partial, partial]).scheduledWorkDuration(on: date(9)), 7 * 3600)
        XCTAssertEqual(work([partial, override(start: 800, end: 600)]).scheduledWorkDuration(on: date(9)), 7 * 3600)
    }

    func testMonthAndWeekUseNetScheduleWithoutChangingClockedHours() {
        let result = work([override(start: 690, end: 750),
                           override(10), override(14, off: false, start: 750, end: 900)])
        // November has 21 weekdays: 168 - 0.5 - 8 + 2 = 161.5 hours.
        XCTAssertEqual(WorkTimeCalculator.expectedWorkDuration(inMonth: date(9), workCalendar: result,
                                                              schedule: schedule, calendar: calendar), 161.5 * 3600)
        let comparison = WorkTimeCalculator.workHoursComparison(
            clockIns: ["2026-11-09": ClockDay(start: date(9, hour: 9), end: date(9, hour: 18)),
                       "2026-11-10": ClockDay(start: date(10, hour: 9), end: date(10, hour: 18))],
            from: date(9), until: date(16), standardHours: 40,
            workCalendar: result, schedule: schedule, calendar: calendar)
        XCTAssertEqual(comparison.scheduledSeconds, Int(33.5 * 3600))
        XCTAssertEqual(comparison.actualSeconds, 16 * 3600)
        XCTAssertEqual(comparison.completedDays, 2)
    }
}
