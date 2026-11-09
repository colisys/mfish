import Foundation

/// Deterministic per-day almanac: the same local date always yields the same
/// picks, so the panel stays stable across relaunches within a day.
public struct Almanac {
    public let good: [String]
    public let bad: [String]
    public let motto: String

    public static let goodItems = [
        "摸鱼", "喝茶", "带薪发呆", "准点下班", "下楼散步", "吃顿好的",
        "逛技术论坛", "给绿植浇水", "整理桌面", "听喜欢的歌", "早点睡觉",
        "喝杯咖啡", "看窗外发呆", "读几页闲书", "撸猫", "囤零食",
    ]
    public static let badItems = [
        "加班", "开周会", "上线发布", "秒回“在吗”", "重构老代码", "立 flag",
        "内卷", "参加没有议程的会", "下班前改需求", "周五发版",
        "徒手改生产配置", "说“我就改一行”",
    ]
    public static let mottos = [
        "摸鱼不是偷懒，是给大脑放年假。",
        "工作做不完，但鱼可以摸完。",
        "今天的鱼，今天摸。",
        "摸鱼一时爽，一直摸鱼一直爽。",
        "效率诚可贵，摸鱼价更高。",
        "鱼还是要摸的，万一实现了呢。",
        "休息是为了走更远的路，摸鱼是为了游得更欢。",
        "别问我在干嘛，我在摸鱼。",
    ]

    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 2000
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        let seed = UInt64(year * 10000 + month * 100 + day)
        var rng = SplitMix64(seed: seed)
        good = Array(Self.goodItems.shuffled(using: &rng).prefix(2))
        bad = Array(Self.badItems.shuffled(using: &rng).prefix(2))
        motto = Self.mottos[Int(rng.next() % UInt64(Self.mottos.count))]
    }
}

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}