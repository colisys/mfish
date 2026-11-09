import Foundation

/// One day entry from holiday-cn: `isOffDay == false` marks a weekend
/// makeup workday (调休), `true` marks a holiday rest day.
public struct HolidayDay: Codable, Equatable {
    public let name: String
    public let date: String
    public let isOffDay: Bool

    public init(name: String, date: String, isOffDay: Bool) {
        self.name = name; self.date = date; self.isOffDay = isOffDay
    }
}

public struct HolidayYear: Codable, Equatable {
    public let year: Int
    public let days: [HolidayDay]

    public init(year: Int, days: [HolidayDay]) {
        self.year = year; self.days = days
    }
}

public struct HolidayPeriod: Equatable {
    public let name: String
    public let start: Date
    public let end: Date
    public let dayCount: Int

    public init(name: String, start: Date, end: Date, dayCount: Int) {
        self.name = name; self.start = start; self.end = end; self.dayCount = dayCount
    }
}

/// Rest-day calendar driven by holiday-cn data, falling back to plain
/// weekends for years without data. Merge order: source days, then named
/// period overrides, then single-day overrides. All dates are local
/// "yyyy-MM-dd" day keys in `calendar`'s time zone.
public struct HolidayCalendar {
    private let calendar: Calendar
    private var offDays: [String: String] = [:]
    private var workDays: [String: String] = [:]
    private var periods: [HolidayPeriod] = []
    private var timedOverrides: [String: DayOverride] = [:]
    public let dataYears: Set<Int>

    public init(years: [HolidayYear], overrides: [HolidayOverride] = [],
                dayOverrides: [DayOverride] = [], calendar: Calendar = .current) {
        self.calendar = calendar
        var yearsWithData = Set(years.map(\.year))
        for year in years {
            for day in year.days where day.date.hasPrefix("\(year.year)-") {
                if day.isOffDay { offDays[day.date] = day.name }
                else { workDays[day.date] = day.name }
            }
        }
        for periodOverride in overrides {
            guard let (start, end) = periodOverride.dateRange(calendar: calendar) else { continue }
            var touched = Set<Int>()
            var day = start
            while day <= end {
                touched.insert(calendar.component(.year, from: day))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            yearsWithData.formUnion(touched)
            offDays = offDays.filter { key, name in
                !(name == periodOverride.name && touched.contains(Self.keyYear(key)))
            }
            workDays = workDays.filter { key, name in
                !(name == periodOverride.name && touched.contains(Self.keyYear(key)))
            }
            day = start
            while day <= end {
                let key = Self.dayKey(for: day, calendar: calendar)
                offDays[key] = periodOverride.name
                workDays.removeValue(forKey: key)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        // Resolve duplicates before merging so an earlier all-day override cannot
        // leak into the base schedule used by a later timed rest override.
        var resolved: [String: DayOverride] = [:]
        for dayOverride in dayOverrides where dayOverride.isValid(calendar: calendar) {
            resolved[dayOverride.date] = dayOverride
        }
        for dayOverride in resolved.values {
            guard let date = Self.parseDay(dayOverride.date, calendar: calendar) else { continue }
            let key = Self.dayKey(for: date, calendar: calendar)
            yearsWithData.insert(calendar.component(.year, from: date))
            if !dayOverride.isAllDay {
                timedOverrides[key] = dayOverride
                if !dayOverride.isOffDay {
                    workDays[key] = dayOverride.name
                    offDays.removeValue(forKey: key)
                }
                continue
            }
            if dayOverride.isOffDay {
                offDays[key] = dayOverride.name
                workDays.removeValue(forKey: key)
            } else {
                workDays[key] = dayOverride.name
                offDays.removeValue(forKey: key)
            }
        }
        dataYears = yearsWithData
        periods = Self.makePeriods(offDays: offDays, calendar: calendar)
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func dayKey(for date: Date) -> String { Self.dayKey(for: date, calendar: calendar) }

    public static func parseDay(_ text: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        guard let date = formatter.date(from: text),
              dayKey(for: date, calendar: calendar) == text else { return nil }
        return calendar.startOfDay(for: date)
    }

    private static func keyYear(_ key: String) -> Int { Int(key.prefix(4)) ?? 0 }

    public func hasData(forYear year: Int) -> Bool { dataYears.contains(year) }

    public func isRestDay(on date: Date) -> Bool {
        let key = dayKey(for: date)
        if offDays[key] != nil { return true }
        if workDays[key] != nil { return false }
        return calendar.isDateInWeekend(date)
    }

    /// Holiday name when the date is inside a named holiday, otherwise nil.
    public func holidayName(on date: Date) -> String? { offDays[dayKey(for: date)] }

    /// The effective partial-day override; partial rest does not alter base holidays.
    public func timedOverride(on date: Date) -> DayOverride? { timedOverrides[dayKey(for: date)] }

    public func isMakeupWorkday(on date: Date) -> Bool { workDays[dayKey(for: date)] != nil }

    public func makeupName(on date: Date) -> String? { workDays[dayKey(for: date)] }

    /// First rest day strictly after the calendar day of `date`, at local
    /// midnight. Weekends guarantee a result even with no holiday data.
    public func nextRestDay(after date: Date) -> (date: Date, name: String?)? {
        let today = calendar.startOfDay(for: date)
        for offset in 1...400 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if isRestDay(on: day) { return (day, offDays[dayKey(for: day)]) }
        }
        return nil
    }

    /// First named holiday period starting strictly after the calendar day of
    /// `date`; the current period (if today is a holiday) is skipped.
    public func nextHoliday(after date: Date) -> HolidayPeriod? {
        let today = calendar.startOfDay(for: date)
        return periods.first { $0.start > today }
    }

    public func periods(inYear year: Int) -> [HolidayPeriod] {
        periods.filter { calendar.component(.year, from: $0.start) == year }
    }

    /// Rest days from `date`'s calendar day through Dec 31 of `year`.
    public func remainingRestDays(inYear year: Int, from date: Date) -> Int {
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return 0 }
        var day = max(calendar.startOfDay(for: date), yearStart)
        var count = 0
        while day < yearEnd {
            if isRestDay(on: day) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    private static func makePeriods(offDays: [String: String], calendar: Calendar) -> [HolidayPeriod] {
        let sorted = offDays.compactMap { key, name -> (Date, String)? in
            guard let date = parseDay(key, calendar: calendar) else { return nil }
            return (date, name)
        }.sorted { $0.0 < $1.0 }
        var result: [HolidayPeriod] = []
        var current: (name: String, start: Date, end: Date, count: Int)?
        for (date, name) in sorted {
            if let existing = current, existing.name == name,
               calendar.date(byAdding: .day, value: 1, to: existing.end) == date {
                current = (name, existing.start, date, existing.count + 1)
            } else {
                if let existing = current {
                    result.append(HolidayPeriod(name: existing.name, start: existing.start,
                                                end: existing.end, dayCount: existing.count))
                }
                current = (name, date, date, 1)
            }
        }
        if let existing = current {
            result.append(HolidayPeriod(name: existing.name, start: existing.start,
                                        end: existing.end, dayCount: existing.count))
        }
        return result
    }
}