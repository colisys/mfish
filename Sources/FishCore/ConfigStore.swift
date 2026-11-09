import Foundation

public struct FishConfig: Codable, Equatable {
    public var sourceURLTemplate: String
    public var overrides: [HolidayOverride]
    public var dayOverrides: [DayOverride]
    public var schedule: WorkSchedule
    public var customReminders: [CustomReminder]
    public var notificationsEnabled: Bool

    public init(sourceURLTemplate: String = HolidaySource.defaultURLTemplate,
                overrides: [HolidayOverride] = [], dayOverrides: [DayOverride] = [],
                schedule: WorkSchedule = WorkSchedule(), customReminders: [CustomReminder] = [],
                notificationsEnabled: Bool = false) {
        self.sourceURLTemplate = sourceURLTemplate
        self.overrides = overrides
        self.dayOverrides = dayOverrides
        self.schedule = schedule
        self.customReminders = customReminders
        self.notificationsEnabled = notificationsEnabled
    }

    enum CodingKeys: String, CodingKey {
        case sourceURLTemplate, overrides, dayOverrides, schedule, customReminders, notificationsEnabled
    }

    /// Tolerates configs written by older versions: missing keys get defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceURLTemplate = try container.decodeIfPresent(String.self, forKey: .sourceURLTemplate)
            ?? HolidaySource.defaultURLTemplate
        overrides = try container.decodeIfPresent([HolidayOverride].self, forKey: .overrides) ?? []
        dayOverrides = try container.decodeIfPresent([DayOverride].self, forKey: .dayOverrides) ?? []
        schedule = try container.decodeIfPresent(WorkSchedule.self, forKey: .schedule) ?? WorkSchedule()
        customReminders = try container.decodeIfPresent([CustomReminder].self, forKey: .customReminders) ?? []
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
    }
}

public struct ConfigStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> FishConfig {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return FishConfig()
        }
        return try JSONDecoder().decode(FishConfig.self, from: data)
    }

    public func save(_ config: FishConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}