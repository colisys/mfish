import Foundation

public enum HolidaySourceError: Error, LocalizedError {
    case invalidTemplate
    case invalidResponse
    case notPublished
    case httpStatus(Int)
    case tooLarge
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .invalidTemplate: return "数据源地址需为 HTTPS，且包含 {year} 占位符。"
        case .invalidResponse: return "数据源返回了无效响应。"
        case .notPublished: return "该年份的放假安排尚未公布。"
        case let .httpStatus(status): return "数据源请求失败（HTTP \(status)）。"
        case .tooLarge: return "数据源响应过大，已拒绝。"
        case .invalidData: return "数据源内容不是有效的节假日 JSON。"
        }
    }
}

public enum HolidaySource {
    public static let defaultURLTemplate =
        "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/{year}.json"

    public static func url(template: String, year: Int) throws -> URL {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("{year}"),
              let url = URL(string: trimmed.replacingOccurrences(of: "{year}", with: String(year))),
              url.scheme == "https", url.host != nil else {
            throw HolidaySourceError.invalidTemplate
        }
        return url
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct HolidayFetcher {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(year: Int, template: String) async throws -> HolidayYear {
        let url = try HolidaySource.url(template: template, year: year)
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("MFish/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request, delegate: NoRedirectDelegate())
        guard let http = response as? HTTPURLResponse else { throw HolidaySourceError.invalidResponse }
        if http.statusCode == 404 { throw HolidaySourceError.notPublished }
        guard http.statusCode == 200 else { throw HolidaySourceError.httpStatus(http.statusCode) }
        guard data.count <= 1_048_576, http.expectedContentLength <= 1_048_576 else {
            throw HolidaySourceError.tooLarge
        }
        let decoded: HolidayYear
        do { decoded = try JSONDecoder().decode(HolidayYear.self, from: data) }
        catch { throw HolidaySourceError.invalidData }
        guard decoded.year == year, !decoded.days.isEmpty,
              decoded.days.allSatisfy({ Self.isValidDay($0, year: year) }) else {
            throw HolidaySourceError.invalidData
        }
        return decoded
    }

    private static func isValidDay(_ day: HolidayDay, year: Int) -> Bool {
        let parts = day.date.split(separator: "-")
        guard parts.count == 3, parts[0] == String(year),
              let month = Int(parts[1]), let dayNum = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(dayNum),
              !day.name.isEmpty else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: dayNum)) else {
            return false
        }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == dayNum
    }
}

public struct CachedHoliday: Codable {
    public let fetchedAt: Date
    public let year: HolidayYear

    public init(fetchedAt: Date, year: HolidayYear) {
        self.fetchedAt = fetchedAt; self.year = year
    }
}

/// Per-year cache files; a corrupt file is ignored (treated as absent) and
/// refetched, never silently trusted.
public struct HolidayCache {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private func fileURL(year: Int) -> URL { directory.appendingPathComponent("\(year).json") }

    public func load(year: Int) -> CachedHoliday? {
        guard let data = try? Data(contentsOf: fileURL(year: year)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cached = try? decoder.decode(CachedHoliday.self, from: data),
              cached.year.year == year else { return nil }
        return cached
    }

    public func save(_ year: HolidayYear, fetchedAt: Date) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(CachedHoliday(fetchedAt: fetchedAt, year: year))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(year: year.year), options: .atomic)
    }

    public func availableYears() -> [Int] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.compactMap { name -> Int? in
            guard name.hasSuffix(".json") else { return nil }
            return Int(name.dropLast(5))
        }.sorted()
    }
}