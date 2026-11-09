import XCTest
@testable import FishCore

final class SolarMonthTests: XCTestCase {
    private func calendar(_ zone: String = "Asia/Shanghai") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0,
                      _ minute: Int = 0, _ second: Int = 0, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                          hour: hour, minute: minute, second: second))!
    }

    func testStartOfSpringUsesEntireLocalTransitionDay() {
        let cal = calendar()
        XCTAssertEqual(SolarMonth.branchIndex(on: date(2026, 2, 3, 23, 59, 59, in: cal), calendar: cal), 1)
        for hour in [0, 6, 12, 18, 23] {
            XCTAssertEqual(SolarMonth.branchIndex(on: date(2026, 2, 4, hour, in: cal), calendar: cal), 2)
        }
        XCTAssertEqual(SolarMonth.branchIndex(on: date(2026, 2, 5, in: cal), calendar: cal), 2)
    }

    func testAwakeningOfInsectsAndStartOfWinterBrackets() {
        let cal = calendar()
        // 不依赖未经独立核实的惊蛰交节日期（3 月 5 日或 6 日）。
        for (month, day, expected) in [(3, 4, 2), (3, 7, 3), (11, 6, 10), (11, 8, 11)] {
            XCTAssertEqual(SolarMonth.branchIndex(on: date(2026, month, day, in: cal), calendar: cal), expected)
        }
    }

    func testAllTwelveBranchesAwayFromBoundaries() {
        let cal = calendar()
        for month in 1...12 {
            XCTAssertEqual(SolarMonth.branchIndex(on: date(2026, month, 15, in: cal), calendar: cal),
                           month % 12, "month \(month)")
        }
    }

    func testWinterSolsticeDoesNotChangeMonthAndNewYearDoesNotResetIt() {
        let cal = calendar()
        for (year, month, day) in [(2025, 12, 31), (2026, 1, 1), (2026, 1, 3),
                                   (2026, 12, 20), (2026, 12, 21), (2026, 12, 22),
                                   (2026, 12, 23), (2026, 12, 31), (2027, 1, 1)] {
            XCTAssertEqual(SolarMonth.branchIndex(on: date(year, month, day, in: cal), calendar: cal), 0)
        }
        XCTAssertEqual(SolarMonth.branchIndex(on: date(2026, 1, 7, in: cal), calendar: cal), 1)
        XCTAssertEqual(SolarMonth.branchIndex(on: date(2027, 1, 7, in: cal), calendar: cal), 1)
    }

    func testSameInstantCanBelongToDifferentLocalTransitionDays() {
        let shanghai = calendar()
        let losAngeles = calendar("America/Los_Angeles")
        // 上海仍在交节前一天，洛杉矶已进入其当地交节日。
        let instant = date(2026, 2, 3, 20, in: shanghai)
        XCTAssertEqual(SolarMonth.branchIndex(on: instant, calendar: shanghai), 1)
        XCTAssertEqual(SolarMonth.branchIndex(on: instant, calendar: losAngeles), 2)
    }

    func testExplicitTimeZonesAndDaylightSavingDaysAreStable() {
        for zone in ["Asia/Shanghai", "UTC", "America/Los_Angeles", "Pacific/Kiritimati"] {
            let cal = calendar(zone)
            // 包含洛杉矶夏令时开始与结束日，另含跨 360° 的春分日。
            for (month, day, expected) in [(2, 2, 1), (2, 5, 2), (3, 8, 3), (3, 20, 3),
                                           (11, 1, 10), (11, 8, 11), (12, 22, 0)] {
                for hour in [0, 12, 23] {
                    let instant = date(2026, month, day, hour, 59, 59, in: cal)
                    XCTAssertEqual(SolarMonth.branchIndex(on: instant, calendar: cal), expected,
                                   "\(zone) \(month)/\(day) hour \(hour)")
                }
            }
        }
    }
}
