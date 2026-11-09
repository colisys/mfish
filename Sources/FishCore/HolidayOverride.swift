import Foundation

/// User replacement for a named holiday period: all source entries (off days
/// and makeup workdays) with the same name in the touched years are dropped,
/// then every date in `start...end` becomes an off day with this name.
public struct HolidayOverride: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var start: String
    public var end: String

    public init(id: UUID = UUID(), name: String, start: String, end: String) {
        self.id = id; self.name = name; self.start = start; self.end = end
    }

    public func dateRange(calendar: Calendar = .current) -> (Date, Date)? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let startDate = HolidayCalendar.parseDay(start, calendar: calendar),
              let endDate = HolidayCalendar.parseDay(end, calendar: calendar),
              startDate <= endDate,
              let span = calendar.dateComponents([.day], from: startDate, to: endDate).day,
              span <= 366 else { return nil }
        return (startDate, endDate)
    }
}

/// A single-day override: `isOffDay == false` marks a custom makeup workday
/// (自定义调休), `true` marks an extra rest day. Wins over everything else.
public struct DayOverride: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: String
    public var isOffDay: Bool
    public var name: String

    /// Both nil means all day; otherwise 0 <= start < end <= 1440 (exclusive end).
    public var startMinutes: Int?
    public var endMinutes: Int?

    public init(id: UUID = UUID(), date: String, isOffDay: Bool, name: String,
                startMinutes: Int? = nil, endMinutes: Int? = nil) {
        self.id = id; self.date = date; self.isOffDay = isOffDay; self.name = name
        self.startMinutes = startMinutes; self.endMinutes = endMinutes
    }

    public var isAllDay: Bool { startMinutes == nil && endMinutes == nil }

    public func isValid(calendar: Calendar = .current) -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              HolidayCalendar.parseDay(date, calendar: calendar) != nil else { return false }
        if isAllDay { return true }
        guard let startMinutes, let endMinutes else { return false }
        return (0..<1440).contains(startMinutes)
            && (1...1440).contains(endMinutes) && startMinutes < endMinutes
    }
}