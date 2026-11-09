import XCTest
@testable import FishCore

final class WorkTimeCalculatorTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    func testActualWorkDurationDeductsOnlyLunchOverlap() {
        let day = date(2026, 11, 9, 0)
        let schedule = WorkSchedule(startMinutes: 540, endMinutes: 1080,
                                   lunchEnabled: true, lunchStartMinutes: 720, lunchEndMinutes: 780)
        let clock = ClockDay(start: date(2026, 11, 9, 8, 30), end: date(2026, 11, 9, 18, 20))
        XCTAssertEqual(WorkTimeCalculator.actualWorkDuration(for: clock, on: day, schedule: schedule,
                                                              calendar: calendar) ?? 0,
                       8 * 3600 + 50 * 60, accuracy: 1)

        let partialLunch = ClockDay(start: date(2026, 11, 9, 12, 30), end: date(2026, 11, 9, 13, 30))
        XCTAssertEqual(WorkTimeCalculator.actualWorkDuration(for: partialLunch, on: day, schedule: schedule,
                                                              calendar: calendar) ?? 0,
                       30 * 60, accuracy: 1)

        var noLunch = schedule
        noLunch.lunchEnabled = false
        XCTAssertEqual(WorkTimeCalculator.actualWorkDuration(for: clock, on: day, schedule: noLunch,
                                                              calendar: calendar) ?? 0,
                       9 * 3600 + 50 * 60, accuracy: 1)
    }

    func testExpectedMonthlyWorkDurationUsesWorkCalendarAndLunch() {
        let schedule = WorkSchedule(enabled: true, startMinutes: 540, endMinutes: 1080,
                                    restWeekdays: [1, 7], lunchEnabled: true,
                                    lunchStartMinutes: 720, lunchEndMinutes: 780)
        let workCalendar = WorkCalendar(holidays: HolidayCalendar(years: [], calendar: calendar),
                                        schedule: schedule, calendar: calendar)
        let hours = WorkTimeCalculator.expectedWorkDuration(inMonth: date(2026, 11, 9, 12),
                                                             workCalendar: workCalendar,
                                                             schedule: schedule, calendar: calendar)
        XCTAssertEqual(hours, 168 * 3600, accuracy: 1)
    }

    func testDailyWorkHoursWarningUsesStrictThresholdAndLunchOverlap() {
        let schedule = WorkSchedule(startMinutes: 540, endMinutes: 1320,
                                    lunchEnabled: true, lunchStartMinutes: 720, lunchEndMinutes: 780)
        let workCalendar = WorkCalendar(holidays: HolidayCalendar(years: [], calendar: calendar),
                                       schedule: schedule, calendar: calendar)
        func comparison(endMinute: Int) -> WorkHoursComparison {
            WorkTimeCalculator.workHoursComparison(
                clockIns: ["2026-11-09": ClockDay(start: date(2026, 11, 9, 9),
                                                   end: date(2026, 11, 9, 22, endMinute))],
                from: date(2026, 11, 9, 0), until: date(2026, 11, 10, 0), standardHours: 8,
                workCalendar: workCalendar, schedule: schedule, calendar: calendar)
        }
        let boundary = comparison(endMinute: 0)
        XCTAssertEqual(boundary.scheduledSeconds, 12 * 3600)
        XCTAssertEqual(boundary.actualSeconds, 12 * 3600)
        XCTAssertFalse(boundary.needsWarning)
        XCTAssertTrue(comparison(endMinute: 1).actualExceedsWarning)
    }

    func testWeeklyComparisonIncludesCrossMonthAndRestDayRecords() {
        let schedule = WorkSchedule(enabled: true, startMinutes: 540, endMinutes: 1320, restWeekdays: [1],
                                    lunchEnabled: true, lunchStartMinutes: 720, lunchEndMinutes: 780)
        let workCalendar = WorkCalendar(holidays: HolidayCalendar(years: [], calendar: calendar),
                                       schedule: schedule, calendar: calendar)
        let records = [
            "2026-10-26": ClockDay(start: date(2026, 10, 26, 9), end: date(2026, 10, 26, 22)),
            "2026-11-01": ClockDay(start: date(2026, 11, 1, 9), end: date(2026, 11, 1, 22)),
            "2026-10-27": ClockDay(start: date(2026, 10, 27, 9)),
            "2026-11-02": ClockDay(start: date(2026, 11, 2, 9), end: date(2026, 11, 2, 22)),
        ]
        let result = WorkTimeCalculator.workHoursComparison(
            clockIns: records, from: date(2026, 10, 26, 0), until: date(2026, 11, 2, 0),
            standardHours: 40, workCalendar: workCalendar, schedule: schedule, calendar: calendar)
        XCTAssertEqual(result.scheduledSeconds, 72 * 3600)
        XCTAssertEqual(result.actualSeconds, 24 * 3600)
        XCTAssertEqual(result.completedDays, 2)
        XCTAssertTrue(result.scheduledExceedsWarning)
        XCTAssertFalse(result.actualExceedsWarning)
    }

    func testWeeklyWarningStartsAboveSixtyHours() {
        let boundary = WorkHoursComparison(scheduledSeconds: 60 * 3600, actualSeconds: 60 * 3600,
                                           completedDays: 5, standardSeconds: 40 * 3600)
        XCTAssertEqual(boundary.thresholdSeconds, 60 * 3600)
        XCTAssertFalse(boundary.needsWarning)
        let exceeded = WorkHoursComparison(scheduledSeconds: 60 * 3600 + 1,
                                           actualSeconds: 60 * 3600 + 1,
                                           completedDays: 5, standardSeconds: 40 * 3600)
        XCTAssertTrue(exceeded.scheduledExceedsWarning)
        XCTAssertTrue(exceeded.actualExceedsWarning)
    }

    func testConfigurableThresholdChangesWarning() {
        let schedule = WorkSchedule(enabled: true, startMinutes: 540, endMinutes: 1200,
                                    lunchEnabled: true, lunchStartMinutes: 720, lunchEndMinutes: 780)
        let workCalendar = WorkCalendar(holidays: HolidayCalendar(years: [], calendar: calendar),
                                       schedule: schedule, calendar: calendar)
        // 11 net hours: 11h / 8h = 1.375 -> no warning at 150%, warning at 130%.
        func comparison(threshold: Int) -> WorkHoursComparison {
            WorkTimeCalculator.workHoursComparison(
                clockIns: ["2026-11-09": ClockDay(start: date(2026, 11, 9, 9),
                                                   end: date(2026, 11, 9, 21))],
                from: date(2026, 11, 9, 0), until: date(2026, 11, 10, 0), standardHours: 8,
                thresholdPercent: threshold, workCalendar: workCalendar, schedule: schedule,
                calendar: calendar)
        }
        XCTAssertEqual(comparison(threshold: 150).actualSeconds, 11 * 3600)
        XCTAssertFalse(comparison(threshold: 150).needsWarning)
        XCTAssertTrue(comparison(threshold: 130).needsWarning)
        XCTAssertEqual(comparison(threshold: 130).worstRatio, 1.4, accuracy: 0.001)
    }

    func testCustomStandardHoursDriveThreshold() {
        let schedule = WorkSchedule(enabled: true, startMinutes: 540, endMinutes: 1140)
        let workCalendar = WorkCalendar(holidays: HolidayCalendar(years: [], calendar: calendar),
                                       schedule: schedule, calendar: calendar)
        // 10 net hours against a 6h standard: 10 / 6 = 1.67 -> warns at 150%.
        let result = WorkTimeCalculator.workHoursComparison(
            clockIns: [:], from: date(2026, 11, 9, 0), until: date(2026, 11, 10, 0),
            standardHours: 6, workCalendar: workCalendar, schedule: schedule, calendar: calendar)
        XCTAssertEqual(result.scheduledSeconds, 10 * 3600)
        XCTAssertTrue(result.scheduledExceedsWarning)
        XCTAssertFalse(result.actualExceedsWarning)
    }

    func testOvertimeSummaryCountsOnlyCompletedLateClockOutsInRange() {
        let schedule = WorkSchedule(startMinutes: 540, endMinutes: 1080)
        let records: [String: ClockDay] = [
            "2026-11-09": ClockDay(start: date(2026, 11, 9, 8, 30), end: date(2026, 11, 9, 18, 30)),
            "2026-11-10": ClockDay(start: date(2026, 11, 10, 9), end: date(2026, 11, 10, 17, 59)),
            "2026-11-11": ClockDay(start: date(2026, 11, 11, 9), end: date(2026, 11, 11, 19, 15)),
            "2026-11-12": ClockDay(start: date(2026, 11, 12, 9)),
            "2026-12-01": ClockDay(start: date(2026, 12, 1, 9), end: date(2026, 12, 1, 18, 30)),
        ]
        let summary = WorkTimeCalculator.overtimeSummary(clockIns: records,
                                                         from: date(2026, 11, 9, 0),
                                                         until: date(2026, 12, 1, 0),
                                                         schedule: schedule, calendar: calendar)
        XCTAssertEqual(summary.lateDays, 2)
        XCTAssertEqual(summary.totalSeconds, 6_300)
    }
}
