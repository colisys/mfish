import Foundation

public enum WeekMode: String, Codable, Equatable, CaseIterable {
    case double
    case single
    case alternating
}

/// Personal work schedule layered on top of the national holiday calendar.
/// Rest weekdays use Calendar numbering: 1 = Sunday … 7 = Saturday.
/// `anchorMonday` is any day in a known week; `anchorIsSingle` says whether
/// that week is a 单休 week, and parity alternates from there.
public struct WorkSchedule: Codable, Equatable {
    public var enabled: Bool
    public var startMinutes: Int
    public var endMinutes: Int
    public var weekMode: WeekMode
    public var restWeekdays: [Int]
    public var singleRestWeekdays: [Int]
    public var anchorMonday: String
    public var anchorIsSingle: Bool
    public var remindStart: Bool
    public var remindEnd: Bool
    public var lunchEnabled: Bool
    public var lunchStartMinutes: Int
    public var lunchEndMinutes: Int
    public var remindLunchStart: Bool
    public var remindLunchEnd: Bool

    public init(enabled: Bool = false, startMinutes: Int = 540, endMinutes: Int = 1080,
                weekMode: WeekMode = .double, restWeekdays: [Int] = [1, 7],
                singleRestWeekdays: [Int] = [1], anchorMonday: String = "2026-01-05",
                anchorIsSingle: Bool = false, remindStart: Bool = true, remindEnd: Bool = true,
                lunchEnabled: Bool = false, lunchStartMinutes: Int = 720, lunchEndMinutes: Int = 780,
                remindLunchStart: Bool = true, remindLunchEnd: Bool = true) {
        self.enabled = enabled
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.weekMode = weekMode
        self.restWeekdays = restWeekdays
        self.singleRestWeekdays = singleRestWeekdays
        self.anchorMonday = anchorMonday
        self.anchorIsSingle = anchorIsSingle
        self.remindStart = remindStart
        self.remindEnd = remindEnd
        self.lunchEnabled = lunchEnabled
        self.lunchStartMinutes = lunchStartMinutes
        self.lunchEndMinutes = lunchEndMinutes
        self.remindLunchStart = remindLunchStart
        self.remindLunchEnd = remindLunchEnd
    }

    enum CodingKeys: String, CodingKey {
        case enabled, startMinutes, endMinutes, weekMode, restWeekdays, singleRestWeekdays
        case anchorMonday, anchorIsSingle, remindStart, remindEnd
        case lunchEnabled, lunchStartMinutes, lunchEndMinutes, remindLunchStart, remindLunchEnd
    }

    /// Tolerates schedules written by older versions: missing keys get defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        startMinutes = try c.decodeIfPresent(Int.self, forKey: .startMinutes) ?? 540
        endMinutes = try c.decodeIfPresent(Int.self, forKey: .endMinutes) ?? 1080
        weekMode = try c.decodeIfPresent(WeekMode.self, forKey: .weekMode) ?? .double
        restWeekdays = Self.sanitizeWeekdays(try c.decodeIfPresent([Int].self, forKey: .restWeekdays),
                                             fallback: [1, 7])
        singleRestWeekdays = Self.sanitizeWeekdays(try c.decodeIfPresent([Int].self, forKey: .singleRestWeekdays),
                                                   fallback: [1])
        anchorMonday = try c.decodeIfPresent(String.self, forKey: .anchorMonday) ?? "2026-01-05"
        anchorIsSingle = try c.decodeIfPresent(Bool.self, forKey: .anchorIsSingle) ?? false
        remindStart = try c.decodeIfPresent(Bool.self, forKey: .remindStart) ?? true
        remindEnd = try c.decodeIfPresent(Bool.self, forKey: .remindEnd) ?? true
        lunchEnabled = try c.decodeIfPresent(Bool.self, forKey: .lunchEnabled) ?? false
        lunchStartMinutes = try c.decodeIfPresent(Int.self, forKey: .lunchStartMinutes) ?? 720
        lunchEndMinutes = try c.decodeIfPresent(Int.self, forKey: .lunchEndMinutes) ?? 780
        remindLunchStart = try c.decodeIfPresent(Bool.self, forKey: .remindLunchStart) ?? true
        remindLunchEnd = try c.decodeIfPresent(Bool.self, forKey: .remindLunchEnd) ?? true
    }

    private static func sanitizeWeekdays(_ days: [Int]?, fallback: [Int]) -> [Int] {
        guard let days else { return fallback }
        let valid = Array(Set(days.filter { (1...7).contains($0) })).sorted()
        return valid.isEmpty ? fallback : valid
    }
}