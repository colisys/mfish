import Foundation

public enum RepeatRule: Codable, Equatable {
    case daily
    case workdays
    /// Calendar weekday numbers: 1 = Sunday ... 7 = Saturday.
    case weekly([Int])
    /// One local date "yyyy-MM-dd"; auto-disabled after firing.
    case once(String)
}

public struct CustomReminder: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var minutes: Int
    public var rule: RepeatRule
    public var enabled: Bool

    public init(id: UUID = UUID(), title: String, minutes: Int, rule: RepeatRule, enabled: Bool = true) {
        self.id = id; self.title = title; self.minutes = minutes; self.rule = rule; self.enabled = enabled
    }
}