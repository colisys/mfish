import XCTest
@testable import FishCore

final class CoreLogicTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testCompactFormat() {
        XCTAssertEqual(CountdownFormat.compact(2 * 86400 + 3 * 3600), "2天3小时")
        XCTAssertEqual(CountdownFormat.compact(2 * 86400), "2天")
        XCTAssertEqual(CountdownFormat.compact(5 * 3600 + 12 * 60), "5小时12分")
        XCTAssertEqual(CountdownFormat.compact(5 * 3600), "5小时")
        XCTAssertEqual(CountdownFormat.compact(8 * 60), "8分钟")
        XCTAssertEqual(CountdownFormat.compact(30), "不到1分钟")
        XCTAssertEqual(CountdownFormat.compact(-100), "不到1分钟")
    }

    func testPreciseCountdownAndOvertimeFormatting() {
        XCTAssertEqual(CountdownFormat.precise(1), "00:00:01")
        XCTAssertEqual(CountdownFormat.precise(1.2), "00:00:02")
        XCTAssertEqual(CountdownFormat.precise(0), "00:00:00")
        XCTAssertEqual(CountdownFormat.precise(-1.9), "+00:00:01")
        XCTAssertEqual(CountdownFormat.precise(-3661), "+01:01:01")
        XCTAssertEqual(CountdownFormat.precise(90061), "1天01:01:01")
    }

    func testYearProgressBoundaries() {
        let start = YearProgress(now: date(2026, 1, 1), calendar: calendar)
        XCTAssertEqual(start.year, 2026)
        XCTAssertEqual(start.fraction, 0, accuracy: 0.0001)
        XCTAssertEqual(start.dayOfYear, 1)
        XCTAssertEqual(start.totalDays, 365)

        let mid = YearProgress(now: date(2026, 7, 2, 12), calendar: calendar)
        XCTAssertEqual(mid.fraction, 0.5, accuracy: 0.01)

        let leap = YearProgress(now: date(2024, 12, 31), calendar: calendar)
        XCTAssertEqual(leap.totalDays, 366)
        XCTAssertEqual(leap.fraction, 1, accuracy: 0.01)
    }

    func testAlmanacDeterministicPerDay() {
        let a = Almanac(date: date(2026, 11, 9, 9), calendar: calendar)
        let b = Almanac(date: date(2026, 11, 9, 23), calendar: calendar)
        XCTAssertEqual(a.good, b.good)
        XCTAssertEqual(a.bad, b.bad)
        XCTAssertEqual(a.motto, b.motto)
        XCTAssertEqual(a.good.count, 3)
        XCTAssertEqual(a.bad.count, 3)
        XCTAssertTrue(a.good.allSatisfy { Almanac.goodItems.contains($0) })
        XCTAssertTrue(a.bad.allSatisfy { Almanac.badItems.contains($0) })
        XCTAssertTrue(Almanac.mottos.contains(a.motto))
    }

    func testAlmanacPoolsAndDailyPicksHaveNoDuplicates() {
        for pool in [Almanac.goodItems, Almanac.badItems, Almanac.mottos] {
            XCTAssertEqual(pool.count, Set(pool).count)
            XCTAssertTrue(pool.allSatisfy { !$0.isEmpty })
        }
        for offset in 0..<365 {
            let day = calendar.date(byAdding: .day, value: offset, to: date(2026, 1, 1, 12))!
            let almanac = Almanac(date: day, calendar: calendar)
            XCTAssertEqual(Set(almanac.good).count, 3)
            XCTAssertEqual(Set(almanac.bad).count, 3)
            XCTAssertTrue(Set(almanac.good).isDisjoint(with: almanac.bad))
        }
    }

    func testAlmanacUsesMonthBranchAndDayBranch() {
        // 2026-11-09 is 丁亥; after 立冬 the month branch is 亥 -> 建日.
        let almanac = Almanac(date: date(2026, 11, 9, 12), calendar: calendar)
        XCTAssertEqual(almanac.monthBranch, "亥")
        XCTAssertEqual(almanac.officer, "建")
        XCTAssertTrue(almanac.bad.contains("理发整装")) // 丁不剃头
        XCTAssertTrue(almanac.bad.contains("签订约定")) // 亥不嫁娶, themed analogy
        XCTAssertFalse(almanac.good.contains("签订约定"))
        XCTAssertTrue(almanac.basis.contains("丁不剃头"))
    }

    func testAlmanacVariesAcrossDays() {
        let combos = (1...10).map { day in
            Almanac(date: date(2026, 11, day), calendar: calendar).good.joined()
        }
        XCTAssertGreaterThan(Set(combos).count, 1)
    }
}