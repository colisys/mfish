import Foundation

public struct OvertimeSummary: Equatable {
    public let totalSeconds: Int
    public let lateDays: Int

    public init(totalSeconds: Int = 0, lateDays: Int = 0) {
        self.totalSeconds = max(0, totalSeconds)
        self.lateDays = max(0, lateDays)
    }
}

public struct WorkHoursComparison: Equatable {
    public let scheduledSeconds: Int
    public let actualSeconds: Int
    public let completedDays: Int
    public let standardSeconds: Int
    public let thresholdPercent: Int

    public init(scheduledSeconds: Int = 0, actualSeconds: Int = 0, completedDays: Int = 0,
                standardSeconds: Int = 0, thresholdPercent: Int = 150) {
        self.scheduledSeconds = max(0, scheduledSeconds)
        self.actualSeconds = max(0, actualSeconds)
        self.completedDays = max(0, completedDays)
        self.standardSeconds = max(0, standardSeconds)
        self.thresholdPercent = max(100, thresholdPercent)
    }

    public var thresholdSeconds: Int { standardSeconds * thresholdPercent / 100 }
    public var scheduledExceedsWarning: Bool { thresholdSeconds > 0 && scheduledSeconds > thresholdSeconds }
    public var actualExceedsWarning: Bool { thresholdSeconds > 0 && actualSeconds > thresholdSeconds }
    public var needsWarning: Bool { scheduledExceedsWarning || actualExceedsWarning }

    /// Ratio of the larger figure to the standard hours, rounded to one decimal.
    public var worstRatio: Double {
        guard standardSeconds > 0 else { return 0 }
        let value = Double(max(scheduledSeconds, actualSeconds)) / Double(standardSeconds)
        return (value * 10).rounded() / 10
    }
}

public enum WorkTimeCalculator {
    /// Compares scheduled and completed net hours against a standard-hours reference.
    public static func workHoursComparison(clockIns: [String: ClockDay], from start: Date, until end: Date,
                                           standardHours: Double, thresholdPercent: Int = 150,
                                           workCalendar: WorkCalendar,
                                           schedule: WorkSchedule,
                                           calendar: Calendar = .current) -> WorkHoursComparison {
        var scheduledSeconds = 0
        var actualSeconds = 0
        var completedDays = 0
        var day = calendar.startOfDay(for: start)
        while day < end {
            scheduledSeconds += Int(workCalendar.scheduledWorkDuration(on: day))
            if let clock = clockIns[HolidayCalendar.dayKey(for: day, calendar: calendar)],
               let duration = actualWorkDuration(for: clock, on: day, schedule: schedule, calendar: calendar) {
                actualSeconds += Int(duration)
                completedDays += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return WorkHoursComparison(scheduledSeconds: scheduledSeconds, actualSeconds: actualSeconds,
                                   completedDays: completedDays,
                                   standardSeconds: Int((max(0, standardHours) * 3600).rounded()),
                                   thresholdPercent: thresholdPercent)
    }
    /// Clocked work duration with the overlap of the configured lunch break removed.
    public static func actualWorkDuration(for clock: ClockDay, on date: Date,
                                          schedule: WorkSchedule,
                                          calendar: Calendar = .current) -> TimeInterval? {
        guard clock.isValid, let start = clock.start, let end = clock.end else { return nil }
        let lunch = lunchInterval(on: date, schedule: schedule, calendar: calendar)
        guard let lunch else { return end.timeIntervalSince(start) }
        let overlapStart = max(start, lunch.start)
        let overlapEnd = min(end, lunch.end)
        let lunchOverlap = max(0, overlapEnd.timeIntervalSince(overlapStart))
        return max(0, end.timeIntervalSince(start) - lunchOverlap)
    }

    /// Scheduled net work time for all workdays in the calendar month containing `date`.
    public static func expectedWorkDuration(inMonth date: Date, workCalendar: WorkCalendar,
                                            schedule: WorkSchedule,
                                            calendar: Calendar = .current) -> TimeInterval {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let days = calendar.range(of: .day, in: .month, for: monthStart) else { return 0 }
        var total: TimeInterval = 0
        for offset in days {
            guard let day = calendar.date(byAdding: .day, value: offset - 1, to: monthStart) else { continue }
            total += workCalendar.scheduledWorkDuration(on: day)
        }
        return total
    }

    /// Sums completed clock-outs later than the configured end time in `[start, end)`.
    /// `graceMinutes` is the first reminder cycle after the scheduled end time;
    /// checkouts inside it do not count as leaving late.
    public static func overtimeSummary(clockIns: [String: ClockDay], from start: Date, until end: Date,
                                       schedule: WorkSchedule, graceMinutes: Int = 0,
                                       calendar: Calendar = .current) -> OvertimeSummary {
        guard (0..<1440).contains(schedule.endMinutes), start < end else { return OvertimeSummary() }
        var totalSeconds = 0
        var lateDays = 0
        for (key, clock) in clockIns {
            guard let day = HolidayCalendar.parseDay(key, calendar: calendar),
                  day >= calendar.startOfDay(for: start), day < calendar.startOfDay(for: end),
                  clock.isValid, let checkout = clock.end,
                  let scheduledEnd = calendar.date(bySettingHour: schedule.endMinutes / 60,
                                                   minute: schedule.endMinutes % 60,
                                                   second: 0, of: day),
                  checkout > scheduledEnd else { continue }
            if graceMinutes > 0,
               checkout <= scheduledEnd.addingTimeInterval(TimeInterval(graceMinutes) * 60) {
                continue
            }
            totalSeconds += Int(checkout.timeIntervalSince(scheduledEnd))
            lateDays += 1
        }
        return OvertimeSummary(totalSeconds: totalSeconds, lateDays: lateDays)
    }


    private static func lunchInterval(on date: Date, schedule: WorkSchedule,
                                      calendar: Calendar) -> DateInterval? {
        guard schedule.lunchEnabled,
              (0..<1440).contains(schedule.lunchStartMinutes),
              (0..<1440).contains(schedule.lunchEndMinutes),
              schedule.lunchEndMinutes > schedule.lunchStartMinutes,
              let start = calendar.date(bySettingHour: schedule.lunchStartMinutes / 60,
                                        minute: schedule.lunchStartMinutes % 60,
                                        second: 0, of: date),
              let end = calendar.date(bySettingHour: schedule.lunchEndMinutes / 60,
                                      minute: schedule.lunchEndMinutes % 60,
                                      second: 0, of: date) else { return nil }
        return DateInterval(start: start, end: end)
    }
}
