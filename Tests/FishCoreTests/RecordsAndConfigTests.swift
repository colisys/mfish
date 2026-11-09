import XCTest
@testable import FishCore

final class RecordsAndConfigTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mfish-records-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDirectory)
    }

    func testRecordsRoundTrip() throws {
        let store = RecordsStore(url: tempDirectory.appendingPathComponent("records.json"))
        XCTAssertEqual(try store.load(), FishRecords())
        var records = FishRecords()
        records.clockIns["2026-11-09"] = ClockDay(start: Date(timeIntervalSince1970: 1_700_000_000),
                                                end: Date(timeIntervalSince1970: 1_700_032_400))
        records.firedKeys = ["work-start-2026-11-09"]
        try store.save(records)
        let loaded = try store.load()
        XCTAssertEqual(loaded.firedKeys, records.firedKeys)
        XCTAssertEqual(loaded.clockIns["2026-11-09"]?.start?.timeIntervalSince1970 ?? 0,
                       1_700_000_000, accuracy: 1)
    }

    func testRecordsCorruptThrows() throws {
        let url = tempDirectory.appendingPathComponent("records.json")
        try Data("{corrupt".utf8).write(to: url)
        XCTAssertThrowsError(try RecordsStore(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), Data("{corrupt".utf8))
    }

    func testConfigDecodesOldVersion() throws {
        let json = #"{"sourceURLTemplate":"https://example.com/{year}.json"}"#
        let config = try JSONDecoder().decode(FishConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.sourceURLTemplate, "https://example.com/{year}.json")
        XCTAssertEqual(config.overrides, [])
        XCTAssertEqual(config.dayOverrides, [])
        XCTAssertEqual(config.schedule, WorkSchedule())
        XCTAssertEqual(config.customReminders, [])
        XCTAssertFalse(config.notificationsEnabled)
    }

    func testConfigFullRoundTrip() throws {
        var config = FishConfig()
        config.overrides = [HolidayOverride(name: "春节", start: "2026-02-16", end: "2026-02-20")]
        config.dayOverrides = [DayOverride(date: "2026-11-14", isOffDay: false, name: "公司调休")]
        config.schedule = WorkSchedule(enabled: true, weekMode: .alternating, anchorIsSingle: true)
        config.customReminders = [CustomReminder(title: "喝水", minutes: 750, rule: .daily),
                                  CustomReminder(title: "周报", minutes: 600, rule: .weekly([2, 6])),
                                  CustomReminder(title: "开会", minutes: 900, rule: .once("2026-11-10"))]
        config.notificationsEnabled = true
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(FishConfig.self, from: data), config)
    }

    func testRepeatRuleCodable() throws {
        let rules: [RepeatRule] = [.daily, .workdays, .weekly([1, 7]), .once("2026-12-01")]
        let data = try JSONEncoder().encode(rules)
        XCTAssertEqual(try JSONDecoder().decode([RepeatRule].self, from: data), rules)
    }

    func testClockDayValidation() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(ClockDay().isValid)
        XCTAssertFalse(ClockDay(end: start).isValid)
        XCTAssertTrue(ClockDay(start: start).isValid)
        XCTAssertTrue(ClockDay(start: start, end: start.addingTimeInterval(3600)).isValid)
        XCTAssertFalse(ClockDay(start: start, end: start).isValid)
        XCTAssertFalse(ClockDay(start: start, end: start.addingTimeInterval(-1)).isValid)
    }
}