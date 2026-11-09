import Foundation

public struct LunarDate: Equatable {
    public let monthName: String
    public let dayName: String
    public let yearGanzhi: String
    public let zodiac: String
    public let dayGanzhi: String

    public init(monthName: String, dayName: String, yearGanzhi: String, zodiac: String, dayGanzhi: String) {
        self.monthName = monthName; self.dayName = dayName
        self.yearGanzhi = yearGanzhi; self.zodiac = zodiac; self.dayGanzhi = dayGanzhi
    }

    public var fullText: String { "\(yearGanzhi)年【\(zodiac)】\(monthName)\(dayName)" }
}

/// Local lunar conversion via Foundation's Chinese calendar. The year pillar
/// switches at 正月初一 (modern almanac convention); the day pillar uses the
/// continuous sexagenary cycle anchored at 1949-10-01 = 甲子日.
public enum LunarCalendar {
    public static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    public static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    public static let zodiacs = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]
    public static let monthNames = ["正月", "二月", "三月", "四月", "五月", "六月",
                                    "七月", "八月", "九月", "十月", "冬月", "腊月"]
    public static let dayNames = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                                  "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                                  "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]

    public static func lunar(for date: Date, calendar: Calendar = .current) -> LunarDate {
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = calendar.timeZone
        let comps = chinese.dateComponents([.era, .year, .month, .day], from: date)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let monthName = (comps.isLeapMonth == true ? "闰" : "") + monthNames[(month - 1) % 12]
        let dayName = dayNames[(day - 1) % 30]

        var yearGanzhi = ""
        var zodiac = ""
        var newYear = DateComponents()
        newYear.era = comps.era
        newYear.year = comps.year
        newYear.month = 1
        newYear.day = 1
        if let newYearDate = chinese.date(from: newYear) {
            let gregorianYear = calendar.component(.year, from: newYearDate)
            let stem = ((gregorianYear - 4) % 10 + 10) % 10
            let branch = ((gregorianYear - 4) % 12 + 12) % 12
            yearGanzhi = stems[stem] + branches[branch]
            zodiac = zodiacs[branch]
        }

        let anchor = calendar.date(from: DateComponents(year: 1949, month: 10, day: 1)) ?? date
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: anchor),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        let index = ((days % 60) + 60) % 60
        let dayGanzhi = stems[index % 10] + branches[index % 12]

        return LunarDate(monthName: monthName, dayName: dayName,
                         yearGanzhi: yearGanzhi, zodiac: zodiac, dayGanzhi: dayGanzhi)
    }
}