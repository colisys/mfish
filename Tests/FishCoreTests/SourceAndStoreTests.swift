import XCTest
@testable import FishCore

final class SourceAndStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mfish-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDirectory)
    }

    func testTemplateValidation() throws {
        XCTAssertEqual(try HolidaySource.url(template: HolidaySource.defaultURLTemplate, year: 2026).absoluteString,
                       "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/2026.json")
        XCTAssertNoThrow(try HolidaySource.url(template: "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/{year}.json", year: 2027))
        XCTAssertThrowsError(try HolidaySource.url(template: "http://example.com/{year}.json", year: 2026))
        XCTAssertThrowsError(try HolidaySource.url(template: "https://example.com/latest.json", year: 2026))
        XCTAssertThrowsError(try HolidaySource.url(template: "", year: 2026))
        XCTAssertThrowsError(try HolidaySource.url(template: "not a url {year}", year: 2026))
    }

    func testCacheRoundTripAndCorruption() throws {
        let cache = HolidayCache(directory: tempDirectory.appendingPathComponent("holidays"))
        let year = HolidayYear(year: 2026, days: [HolidayDay(name: "元旦", date: "2026-01-01", isOffDay: true)])
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try cache.save(year, fetchedAt: fetchedAt)
        let loaded = cache.load(year: 2026)
        XCTAssertEqual(loaded?.year, year)
        XCTAssertEqual(loaded?.fetchedAt.timeIntervalSince1970 ?? 0, 1_700_000_000, accuracy: 1)
        XCTAssertEqual(cache.availableYears(), [2026])

        try Data("corrupt".utf8).write(to: tempDirectory.appendingPathComponent("holidays/2026.json"))
        XCTAssertNil(cache.load(year: 2026))
        XCTAssertNil(cache.load(year: 2027))
    }

    func testCacheRejectsMismatchedYear() throws {
        let cache = HolidayCache(directory: tempDirectory.appendingPathComponent("holidays"))
        let wrong = HolidayYear(year: 2025, days: [HolidayDay(name: "元旦", date: "2025-01-01", isOffDay: true)])
        try cache.save(wrong, fetchedAt: Date())
        // File lives at 2025.json; asking for 2026 finds nothing.
        XCTAssertNil(cache.load(year: 2026))
        XCTAssertEqual(cache.load(year: 2025)?.year.year, 2025)
    }

    func testConfigDefaultsAndRoundTrip() throws {
        let store = ConfigStore(url: tempDirectory.appendingPathComponent("config.json"))
        XCTAssertEqual(try store.load(), FishConfig())
        var config = FishConfig()
        config.sourceURLTemplate = "https://mirror.example.com/{year}.json"
        try store.save(config)
        XCTAssertEqual(try store.load(), config)
    }

    func testConfigCorruptThrows() throws {
        let url = tempDirectory.appendingPathComponent("config.json")
        try Data("{corrupt".utf8).write(to: url)
        let store = ConfigStore(url: url)
        XCTAssertThrowsError(try store.load())
        // The corrupt file must survive untouched for the user to inspect.
        XCTAssertEqual(try Data(contentsOf: url), Data("{corrupt".utf8))
    }

    func testLegacyScheduleDecodeGetsRestWeekdayDefaults() throws {
        let json = """
        {"enabled":true,"startMinutes":480,"endMinutes":1080,"weekMode":"single",\
        "anchorMonday":"2026-01-05","anchorIsSingle":false,"remindStart":true,"remindEnd":true}
        """
        let schedule = try JSONDecoder().decode(WorkSchedule.self, from: Data(json.utf8))
        XCTAssertEqual(schedule.restWeekdays, [1, 7])
        XCTAssertEqual(schedule.singleRestWeekdays, [1])
        XCTAssertEqual(schedule.weekMode, .single)
        XCTAssertEqual(schedule.startMinutes, 480)
    }

    func testScheduleDecodeSanitizesWeekdays() throws {
        let json = """
        {"restWeekdays":[7,7,9,0],"singleRestWeekdays":[]}
        """
        let schedule = try JSONDecoder().decode(WorkSchedule.self, from: Data(json.utf8))
        XCTAssertEqual(schedule.restWeekdays, [7])
        XCTAssertEqual(schedule.singleRestWeekdays, [1])  // empty falls back to default
        XCTAssertEqual(schedule.weekMode, .double)
    }
}