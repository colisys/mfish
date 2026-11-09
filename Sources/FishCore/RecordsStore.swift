import Foundation

public struct ClockDay: Codable, Equatable {
    public var start: Date?
    public var end: Date?

    public init(start: Date? = nil, end: Date? = nil) {
        self.start = start; self.end = end
    }

    /// A record needs a start time; the end time, when present, must be later.
    public var isValid: Bool {
        guard let start else { return false }
        if let end { return end > start }
        return true
    }
}

public struct FishRecords: Codable, Equatable {
    public var clockIns: [String: ClockDay]
    public var firedKeys: [String]

    public init(clockIns: [String: ClockDay] = [:], firedKeys: [String] = []) {
        self.clockIns = clockIns; self.firedKeys = firedKeys
    }
}

public struct RecordsStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> FishRecords {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return FishRecords()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FishRecords.self, from: data)
    }

    public func save(_ records: FishRecords) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}