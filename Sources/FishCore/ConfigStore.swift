import Foundation

public struct FishConfig: Codable, Equatable {
    public var sourceURLTemplate: String
    public var overrides: [HolidayOverride]
    public var dayOverrides: [DayOverride]
    public var schedule: WorkSchedule
    public var customReminders: [CustomReminder]
    public var notificationsEnabled: Bool
    public var debtModeEnabled: Bool
    public var debtReminderEnabled: Bool
    public var debtReminderIntervalMinutes: Int
    /// Standard-hours reference used by the calendar warning (national rule: 8h/day, 40h/week).
    public var standardDailyHours: Double
    public var standardWeeklyHours: Double
    /// Warn once hours exceed this percentage of the standard reference (150 = 1.5×).
    public var warningThresholdPercent: Int

    public init(sourceURLTemplate: String = HolidaySource.defaultURLTemplate,
                overrides: [HolidayOverride] = [], dayOverrides: [DayOverride] = [],
                schedule: WorkSchedule = WorkSchedule(), customReminders: [CustomReminder] = [],
                notificationsEnabled: Bool = false, debtModeEnabled: Bool = false,
                debtReminderEnabled: Bool = false, debtReminderIntervalMinutes: Int = 5,
                standardDailyHours: Double = 8, standardWeeklyHours: Double = 40,
                warningThresholdPercent: Int = 150) {
        self.sourceURLTemplate = sourceURLTemplate
        self.overrides = overrides
        self.dayOverrides = dayOverrides
        self.schedule = schedule
        self.customReminders = customReminders
        self.notificationsEnabled = notificationsEnabled
        self.debtModeEnabled = debtModeEnabled
        self.debtReminderEnabled = debtReminderEnabled
        self.debtReminderIntervalMinutes = debtReminderIntervalMinutes
        self.standardDailyHours = standardDailyHours
        self.standardWeeklyHours = standardWeeklyHours
        self.warningThresholdPercent = warningThresholdPercent
    }

    enum CodingKeys: String, CodingKey {
        case sourceURLTemplate, overrides, dayOverrides, schedule, customReminders, notificationsEnabled
        case debtModeEnabled, debtReminderEnabled, debtReminderIntervalMinutes
        case standardDailyHours, standardWeeklyHours, warningThresholdPercent
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
        debtModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .debtModeEnabled) ?? false
        debtReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .debtReminderEnabled) ?? false
        debtReminderIntervalMinutes = min(120, max(1, try container.decodeIfPresent(Int.self, forKey: .debtReminderIntervalMinutes) ?? 5))
        standardDailyHours = Self.clampHours(try container.decodeIfPresent(Double.self, forKey: .standardDailyHours),
                                             fallback: 8, upper: 24)
        standardWeeklyHours = Self.clampHours(try container.decodeIfPresent(Double.self, forKey: .standardWeeklyHours),
                                              fallback: 40, upper: 168)
        warningThresholdPercent = min(400, max(100, try container.decodeIfPresent(Int.self,
                                                                                forKey: .warningThresholdPercent) ?? 150))
    }

    private static func clampHours(_ value: Double?, fallback: Double, upper: Double) -> Double {
        guard let value, value.isFinite, value > 0 else { return fallback }
        return min(upper, max(0.5, value))
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