import Foundation

public enum CountdownFormat {
    /// Menu-bar sized: "2天3小时", "5小时12分", "8分钟".
    public static func compact(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return hours > 0 ? "\(days)天\(hours)小时" : "\(days)天" }
        if hours > 0 { return minutes > 0 ? "\(hours)小时\(minutes)分" : "\(hours)小时" }
        return max(1, minutes) > 1 ? "\(minutes)分钟" : "不到1分钟"
    }

    /// Second-precision menu-bar timer. Negative intervals count upward with a `+` prefix.
    public static func precise(_ interval: TimeInterval) -> String {
        let overtime = interval < 0
        let seconds = overtime ? Int(-interval) : Int(ceil(interval))
        let total = max(0, seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        let clock = String(format: "%02d:%02d:%02d", hours, minutes, remainder)
        let value = days > 0 ? "\(days)天\(clock)" : clock
        return overtime ? "+\(value)" : value
    }
}

public struct YearProgress {
    public let year: Int
    public let fraction: Double
    public let dayOfYear: Int
    public let totalDays: Int

    public init(now: Date, calendar: Calendar = .current) {
        year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
        let nextStart = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? now
        let length = nextStart.timeIntervalSince(start)
        fraction = length > 0 ? min(1, max(0, now.timeIntervalSince(start) / length)) : 0
        dayOfYear = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        totalDays = calendar.range(of: .day, in: .year, for: now)?.count ?? 365
    }
}