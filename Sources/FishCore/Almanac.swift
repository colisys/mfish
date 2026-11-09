import Foundation

/// A themed interpretation of 十二建除 and 彭祖百忌, not a complete 通书.
/// Solar months change for the whole local civil day containing the solar term.
public struct Almanac {
    public let good: [String]
    public let bad: [String]
    public let motto: String
    public let officer: String
    public let monthBranch: String
    public let basis: String

    private enum Activity: String, CaseIterable {
        case plan = "拟定计划", clean = "整理桌面", celebrate = "分享小成果"
        case connect = "约朋友聊天", settle = "敲定安排", finish = "收尾交接"
        case discard = "清理旧待办", review = "检查备份", deliver = "提交成果"
        case collect = "整理收获", begin = "学点新东西", rest = "静心休养"
        case travel = "出门散步", spend = "添置用品", sign = "签订约定"
        case build = "改动配置", argue = "争论对错", feast = "聚餐小酌"
        case garden = "照料绿植", dress = "添置衣物", cook = "下厨做饭"
        case visit = "登门拜访", groom = "理发整装", repair = "修补旧物"
        case move = "搬动工位", water = "临水出游", save = "整理存款"
        case reflect = "安静复盘", read = "读几页闲书", music = "听首好歌"
    }

    private struct Rule {
        let name: String
        let good: [Activity]
        let bad: [Activity]
        let motto: String
    }

    // Deliberately curated modern analogies: 成 -> completion, 收 -> collection,
    // 除/破 -> clearing old things, 闭 -> quiet rest; not traditional verdicts on work.
    private static let rules: [Rule] = [
        Rule(name: "建", good: [.plan, .begin, .connect, .travel], bad: [.discard, .move, .argue],
             motto: "建日立个小目标，别把整年任务都揽到今天。"),
        Rule(name: "除", good: [.clean, .discard, .groom, .repair], bad: [.sign, .begin, .spend],
             motto: "除去旧待办，也给心里腾个空位。"),
        Rule(name: "满", good: [.celebrate, .feast, .connect, .garden], bad: [.build, .discard, .argue],
             motto: "满日知足，今天的小收获也值得庆祝。"),
        Rule(name: "平", good: [.connect, .clean, .reflect, .read], bad: [.begin, .sign, .argue],
             motto: "平平稳稳过一天，不必事事争个先。"),
        Rule(name: "定", good: [.settle, .plan, .sign, .read], bad: [.travel, .move, .argue],
             motto: "定下安排，也给休息留一个确定的位置。"),
        Rule(name: "执", good: [.finish, .repair, .review, .garden], bad: [.move, .travel, .spend],
             motto: "执着做好一件事，别执着于一直在线。"),
        Rule(name: "破", good: [.discard, .clean, .reflect, .rest], bad: [.sign, .begin, .deliver],
             motto: "破日宜清旧，不宜把自己也消耗掉。"),
        Rule(name: "危", good: [.review, .reflect, .read, .rest], bad: [.travel, .water, .build],
             motto: "危日多检查一遍，少说一句“应该没问题”。"),
        Rule(name: "成", good: [.deliver, .finish, .celebrate, .connect], bad: [.argue, .discard, .build],
             motto: "成一件小事，收一份安心，然后准点散场。"),
        Rule(name: "收", good: [.collect, .save, .review, .read], bad: [.begin, .travel, .spend],
             motto: "收好成果，也收回属于自己的下班时间。"),
        Rule(name: "开", good: [.begin, .connect, .travel, .plan], bad: [.discard, .argue, .build],
             motto: "开一扇新窗，不必同时开十个新坑。"),
        Rule(name: "闭", good: [.rest, .reflect, .read, .music], bad: [.begin, .travel, .deliver],
             motto: "闭日收心，把工作群静音，给生活留白。"),
    ]

    private struct Taboo {
        let traditional: String
        let activity: Activity?
    }

    // The original sayings explain the analogy; e.g. 不开仓 -> avoid spending.
    // No health or medical advice is derived from these traditional sayings.
    private static let stemTaboos: [Taboo] = [
        Taboo(traditional: "甲不开仓", activity: .spend),
        Taboo(traditional: "乙不栽植", activity: .garden),
        Taboo(traditional: "丙不修灶", activity: .cook),
        Taboo(traditional: "丁不剃头", activity: .groom),
        Taboo(traditional: "戊不受田", activity: .sign),
        Taboo(traditional: "己不破券", activity: .sign),
        Taboo(traditional: "庚不经络", activity: .repair),
        Taboo(traditional: "辛不合酱", activity: .cook),
        Taboo(traditional: "壬不汲水", activity: .water),
        Taboo(traditional: "癸不词讼", activity: .argue),
    ]
    private static let branchTaboos: [Taboo] = [
        Taboo(traditional: "子不问卜", activity: nil),
        Taboo(traditional: "丑不冠带", activity: .dress),
        Taboo(traditional: "寅不祭祀", activity: nil),
        Taboo(traditional: "卯不穿井", activity: .build),
        Taboo(traditional: "辰不哭泣", activity: nil),
        Taboo(traditional: "巳不远行", activity: .travel),
        Taboo(traditional: "午不苫盖", activity: .repair),
        Taboo(traditional: "未不服药", activity: nil),
        Taboo(traditional: "申不安床", activity: .move),
        Taboo(traditional: "酉不会客", activity: .visit),
        Taboo(traditional: "戌不吃犬", activity: nil),
        Taboo(traditional: "亥不嫁娶", activity: .sign),
    ]

    public static var goodItems: [String] { Activity.allCases.map(\.rawValue) }
    public static var badItems: [String] { Activity.allCases.map(\.rawValue) }
    public static var mottos: [String] { rules.map(\.motto) }

    public init(date: Date, calendar: Calendar = .current) {
        let ganzhi = Array(LunarCalendar.lunar(for: date, calendar: calendar).dayGanzhi).map(String.init)
        let stem = LunarCalendar.stems.firstIndex(of: ganzhi[0]) ?? 0
        let branch = LunarCalendar.branches.firstIndex(of: ganzhi[1]) ?? 0
        let month = SolarMonth.branchIndex(on: date, calendar: calendar)
        let rule = Self.rules[(branch - month + 12) % 12]
        let taboos = [Self.stemTaboos[stem], Self.branchTaboos[branch]]
        var avoided = [Activity]()
        for activity in taboos.compactMap(\.activity) + rule.bad where !avoided.contains(activity) {
            avoided.append(activity)
        }
        // Quiet fallback activities are never chosen from a forbidden category.
        let allowed = (rule.good + [.rest, .read, .music, .reflect]).filter { !avoided.contains($0) }
        var selected = [Activity]()
        for activity in allowed where !selected.contains(activity) { selected.append(activity) }
        good = selected.prefix(3).map(\.rawValue)
        bad = avoided.prefix(3).map(\.rawValue)
        motto = rule.motto
        officer = rule.name
        monthBranch = LunarCalendar.branches[month]
        basis = "月建\(monthBranch)，日支\(LunarCalendar.branches[branch])，十二建除为\(rule.name)日。\(taboos.map(\.traditional).joined(separator: "、"))；宜忌为现代趣味转译，仅供娱乐。"
    }
}
