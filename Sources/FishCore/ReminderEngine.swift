import Foundation

public struct DueReminder: Equatable {
    public let key: String
    public let title: String
    public let body: String
    public let disablesReminderID: UUID?

    public init(key: String, title: String, body: String, disablesReminderID: UUID? = nil) {
        self.key = key; self.title = title; self.body = body
        self.disablesReminderID = disablesReminderID
    }
}

/// Pure firing decision: a reminder fires when its time has arrived within
/// the grace window, the day matches, and its key has not fired yet. The app
/// is expected to run resident; nothing fires while it is quit.
public enum ReminderEngine {
    public static func due(now: Date, workCalendar: WorkCalendar, customs: [CustomReminder],
                           fired: Set<String>, graceMinutes: Int = 30,
                           calendar: Calendar = .current) -> [DueReminder] {
        let today = calendar.startOfDay(for: now)
        let dayKey = HolidayCalendar.dayKey(for: today, calendar: calendar)
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let schedule = workCalendar.schedule
        var result: [DueReminder] = []

        func within(_ minutes: Int) -> Bool {
            nowMinutes >= minutes && nowMinutes <= minutes + graceMinutes
        }

        if schedule.enabled, !workCalendar.isRestDay(on: today) {
            if schedule.remindStart, within(schedule.startMinutes) {
                let key = "work-start-\(dayKey)"
                if !fired.contains(key) {
                    result.append(DueReminder(key: key, title: "上班提醒", body: "该上班了，记得打卡上班。"))
                }
            }
            if schedule.remindEnd, within(schedule.endMinutes) {
                let key = "work-end-\(dayKey)"
                if !fired.contains(key) {
                    result.append(DueReminder(key: key, title: "下班提醒", body: "到点了，下班打卡，今天也辛苦了。"))
                }
            }
        }

        let weekday = calendar.component(.weekday, from: today)
        for reminder in customs where reminder.enabled {
            let matches: Bool
            let key: String
            switch reminder.rule {
            case .daily:
                matches = true
                key = "custom-\(reminder.id.uuidString)-\(dayKey)"
            case .workdays:
                matches = !workCalendar.isRestDay(on: today)
                key = "custom-\(reminder.id.uuidString)-\(dayKey)"
            case let .weekly(days):
                matches = days.contains(weekday)
                key = "custom-\(reminder.id.uuidString)-\(dayKey)"
            case let .once(date):
                matches = date == dayKey
                key = "once-\(reminder.id.uuidString)"
            }
            guard matches, within(reminder.minutes), !fired.contains(key) else { continue }
            var onceID: UUID?
            if case .once = reminder.rule { onceID = reminder.id }
            result.append(DueReminder(key: key, title: reminder.title, body: "MFish · 自定义提醒",
                                      disablesReminderID: onceID))
        }
        return result
    }

    /// Drop date-keyed entries older than a week; `once-` keys stay until the
    /// reminder is deleted.
    public static func pruneFiredKeys(_ keys: Set<String>, now: Date,
                                      calendar: Calendar = .current) -> Set<String> {
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -7, to: today) else { return keys }
        let cutoffKey = HolidayCalendar.dayKey(for: cutoff, calendar: calendar)
        return Set(keys.filter { key in
            let suffix = String(key.suffix(10))
            guard suffix.count == 10, suffix[suffix.index(suffix.startIndex, offsetBy: 4)] == "-",
                  HolidayCalendar.parseDay(suffix, calendar: calendar) != nil else { return true }
            return suffix >= cutoffKey
        })
    }
}