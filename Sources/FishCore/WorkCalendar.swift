import Foundation

public enum DayKind: Equatable {
    case holiday(String)
    case makeupWorkday(String)
    case rest
    case work
}

/// Merged calendar. Precedence: holiday off days (incl. user overrides) >
/// makeup workdays (incl. custom 调休) > personal week schedule > weekends.
public struct WorkCalendar {
    public let holidays: HolidayCalendar
    public let schedule: WorkSchedule
    private let calendar: Calendar

    public init(holidays: HolidayCalendar, schedule: WorkSchedule = WorkSchedule(),
                calendar: Calendar = .current) {
        self.holidays = holidays
        self.schedule = schedule
        self.calendar = calendar
    }

    public func isRestDay(on date: Date) -> Bool {
        if holidays.holidayName(on: date) != nil { return true }
        if holidays.isMakeupWorkday(on: date) { return false }
        if schedule.enabled {
            let restDays = isSingleWeek(containing: date) ? schedule.singleRestWeekdays : schedule.restWeekdays
            return restDays.contains(calendar.component(.weekday, from: date))
        }
        return calendar.isDateInWeekend(date)
    }

    public func kind(on date: Date) -> DayKind {
        if let name = holidays.holidayName(on: date) { return .holiday(name) }
        if let name = holidays.makeupName(on: date) { return .makeupWorkday(name) }
        return isRestDay(on: date) ? .rest : .work
    }

    /// Net scheduled seconds, independent of clock records. Timed work replaces
    /// the normal interval; timed rest subtracts only its net overlap with it.
    public func scheduledWorkDuration(on date: Date) -> TimeInterval {
        let override = holidays.timedOverride(on: date)
        if let override, !override.isOffDay,
           let start = override.startMinutes, let end = override.endMinutes {
            return TimeInterval(netMinutes(from: start, to: end) * 60)
        }
        guard !isRestDay(on: date),
              (0..<1440).contains(schedule.startMinutes),
              (0..<1440).contains(schedule.endMinutes),
              schedule.startMinutes < schedule.endMinutes else { return 0 }
        var minutes = netMinutes(from: schedule.startMinutes, to: schedule.endMinutes)
        if let override, override.isOffDay,
           let start = override.startMinutes, let end = override.endMinutes {
            minutes -= netMinutes(from: max(schedule.startMinutes, start),
                                  to: min(schedule.endMinutes, end))
        }
        return TimeInterval(max(0, minutes) * 60)
    }

    private func netMinutes(from start: Int, to end: Int) -> Int {
        guard start < end else { return 0 }
        guard schedule.lunchEnabled,
              (0..<1440).contains(schedule.lunchStartMinutes),
              (0..<1440).contains(schedule.lunchEndMinutes),
              schedule.lunchStartMinutes < schedule.lunchEndMinutes else { return end - start }
        let lunch = max(0, min(end, schedule.lunchEndMinutes) - max(start, schedule.lunchStartMinutes))
        return end - start - lunch
    }

    /// Whether the week containing `date` uses the 单休 rest-day set.
    public func isSingleWeek(containing date: Date) -> Bool {
        switch schedule.weekMode {
        case .double: return false
        case .single: return true
        case .alternating:
            guard let anchor = HolidayCalendar.parseDay(schedule.anchorMonday, calendar: calendar) else {
                return false
            }
            guard let days = calendar.dateComponents([.day], from: mondayOfWeek(anchor),
                                                     to: mondayOfWeek(date)).day else { return false }
            let weeks = days / 7
            let parity = ((weeks % 2) + 2) % 2
            return parity == 0 ? schedule.anchorIsSingle : !schedule.anchorIsSingle
        }
    }

    public func nextRestDay(after date: Date) -> (date: Date, name: String?)? {
        let today = calendar.startOfDay(for: date)
        for offset in 1...400 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if isRestDay(on: day) { return (day, holidays.holidayName(on: day)) }
        }
        return nil
    }

    /// The configured end time on a given date, whether it is a workday or not.
    public func scheduledEnd(on date: Date) -> Date? {
        guard (0..<1440).contains(schedule.endMinutes) else { return nil }
        return calendar.date(bySettingHour: schedule.endMinutes / 60,
                             minute: schedule.endMinutes % 60,
                             second: 0, of: date)
    }

    /// Returns the next workday's configured end time, including today when it
    /// is a workday and its end time has not passed yet.
    public func nextWorkdayEnd(after date: Date) -> Date? {
        let today = calendar.startOfDay(for: date)
        for offset in 0...400 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  !isRestDay(on: day),
                  let end = scheduledEnd(on: day), end > date else { continue }
            return end
        }
        return nil
    }

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

    private func mondayOfWeek(_ date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }
}