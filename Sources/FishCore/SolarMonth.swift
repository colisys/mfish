import Foundation

/// 以十二个「节」划分月建，返回子 0、丑 1、寅 2……亥 11。
///
/// 使用 Julian day、太阳平黄经／平近点角、中心差及简化光行差／章动
/// 计算太阳视黄经。这是适用于现代日期的近似算法，不是高精度星历；
/// UTC 近似代替力学时，交节非常接近当地午夜时可能有一天的误差。
/// 按传入 calendar 的当地日期整日计：交节日从当地日初（通常 00:00）
/// 即采用新月建，而不是等到精确交节瞬间；与农历初一无关。
public enum SolarMonth {
    public static func branchIndex(on date: Date, calendar: Calendar = .current) -> Int {
        guard let day = calendar.dateInterval(of: .day, for: date) else {
            preconditionFailure("Date must have a representable calendar day")
        }
        // 使用半开日期区间的最后可表示时刻，兼容夏令时的 23/25 小时日。
        let endOfDay = Date(timeIntervalSinceReferenceDate: day.end.timeIntervalSinceReferenceDate.nextDown)
        let longitude = apparentSolarLongitude(on: endOfDay)
        // 255°大雪子、285°小寒丑、315°立春寅、345°惊蛰卯，
        // 此后 15°清明辰……225°立冬亥，每隔 30° 切换。
        return Int(floor(normalized(longitude - 255) / 30))
    }

    private static func apparentSolarLongitude(on date: Date) -> Double {
        let julianDay = date.timeIntervalSince1970 / 86400 + 2440587.5
        let t = (julianDay - 2451545.0) / 36525
        let meanLongitude = normalized(280.46646 + t * (36000.76983 + 0.0003032 * t))
        let meanAnomaly = normalized(357.52911 + t * (35999.05029 - 0.0001537 * t))
        let radians = Double.pi / 180
        let m = meanAnomaly * radians
        let center = (1.914602 - t * (0.004817 + 0.000014 * t)) * sin(m)
            + (0.019993 - 0.000101 * t) * sin(2 * m)
            + 0.000289 * sin(3 * m)
        let omega = (125.04 - 1934.136 * t) * radians
        // 常数项为简化光行差，正弦项为主要章动修正。
        return normalized(meanLongitude + center - 0.00569 - 0.00478 * sin(omega))
    }

    private static func normalized(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }
}
