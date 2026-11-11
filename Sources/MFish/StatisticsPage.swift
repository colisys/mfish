import FishCore
import SwiftUI

private struct DailyOvertime: Identifiable {
    let date: Date
    let seconds: Int
    var id: Date { date }
    var minutes: Double { Double(seconds) / 60 }
}

struct StatisticsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("加班统计").font(.title2.bold())
                Text("统计超过下班时间一个提醒间隔的已完成打卡，间隔内打卡不算晚下班。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            summaryPanel(title: "本周", range: weekRange, summary: weekSummary)
            summaryPanel(title: "本月", range: monthRange, summary: monthSummary)

        }
    }

    private var weekRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: model.now)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return (start, end)
    }

    private var monthRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: model.now)
        let start = calendar.date(from: components) ?? calendar.startOfDay(for: model.now)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
    }

    private var weekSummary: OvertimeSummary {
        WorkTimeCalculator.overtimeSummary(clockIns: model.records.clockIns,
                                           from: weekRange.start, until: weekRange.end,
                                           schedule: model.config.schedule,
                                           graceMinutes: model.config.debtReminderIntervalMinutes)
    }

    private var monthSummary: OvertimeSummary {
        WorkTimeCalculator.overtimeSummary(clockIns: model.records.clockIns,
                                           from: monthRange.start, until: monthRange.end,
                                           schedule: model.config.schedule,
                                           graceMinutes: model.config.debtReminderIntervalMinutes)
    }

    private func summaryPanel(title: String, range: (start: Date, end: Date),
                              summary: OvertimeSummary) -> some View {
        FishPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.headline)
                    Text(rangeText(range)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(summary.lateDays) 天超时")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(FishFormat.duration(TimeInterval(summary.totalSeconds)))
                        .font(.system(size: 28, weight: .bold).monospacedDigit())
                    Text("晚下班")
                        .font(.callout).foregroundStyle(.secondary)
                }
                overtimeChart(range: range)
                Divider()
                Text(commentary(for: summary, period: title))
                    .font(.callout)
                    .foregroundStyle(model.config.debtModeEnabled ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dailyOvertime(in range: (start: Date, end: Date)) -> [DailyOvertime] {
        let calendar = Calendar.current
        var days: [DailyOvertime] = []
        var day = range.start
        while day < range.end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            let summary = WorkTimeCalculator.overtimeSummary(
                clockIns: model.records.clockIns, from: day, until: next,
                schedule: model.config.schedule,
                graceMinutes: model.config.debtReminderIntervalMinutes, calendar: calendar)
            days.append(DailyOvertime(date: day, seconds: summary.totalSeconds))
            day = next
        }
        return days
    }

    private func overtimeChart(range: (start: Date, end: Date)) -> some View {
        let days = dailyOvertime(in: range)
        let maximumMinutes = max(30, (days.map(\.minutes).max() ?? 0) * 1.15)
        let summary = WorkTimeCalculator.overtimeSummary(
            clockIns: model.records.clockIns, from: range.start, until: range.end,
            schedule: model.config.schedule,
            graceMinutes: model.config.debtReminderIntervalMinutes)
        let value = summary.totalSeconds > 0
            ? "共 \(summary.lateDays) 天晚下班，累计 \(FishFormat.duration(TimeInterval(summary.totalSeconds)))"
            : "无超时"
        return OvertimeBarChart(days: days, maximumMinutes: maximumMinutes,
                                labelStride: days.count > 7 ? 5 : 1,
                                barColor: model.config.debtModeEnabled ? .orange : .accentColor)
            .frame(height: 170)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("晚下班统计图")
            .accessibilityValue(value)
    }

    private func rangeText(_ range: (start: Date, end: Date)) -> String {
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        return "\(FishFormat.shortDay(range.start))–\(FishFormat.shortDay(lastDay))"
    }

    private func commentary(for summary: OvertimeSummary, period: String) -> String {
        if summary.totalSeconds == 0 {
            return model.config.debtModeEnabled
                ? "\(period)没有被加班偷走时间。继续守住准点下班，自己的生活不该排在工作后面。"
                : "\(period)暂无晚于设定下班时间的打卡。"
        }
        let duration = FishFormat.duration(TimeInterval(summary.totalSeconds))
        guard model.config.debtModeEnabled else {
            return "\(period)有 \(summary.lateDays) 天晚于设定下班时间，累计超时 \(duration)。"
        }

        let activities = [
            "如果用来健身，你能多做几组卧推。",
            "如果用来慢跑，足够完成一次痛快的训练。",
            "如果用来做饭，你可以慢慢准备一顿晚餐，不必惦记着未完的工作。",
            "如果用来陪家人吃饭，这顿饭本不该迟到。",
            "如果用来读书，能安安静静看完一大段，而不是把休息挤到睡前。",
            "如果用来散步放空，你早就能把工作模式切回自己的生活。",
            "如果用来追剧，足够看上一集，不必再从睡眠里挤时间。",
            "如果用来学点新东西，你可以完整听完一节课。",
        ]
        let reminders = [
            "这不是敬业勋章，是实打实被工作拿走的个人时间。",
            "公司不会自动把这段时间还给你，准点下班不是奖励。",
            "别把被拖延的下班当成理所当然。",
            "工时表记下了加班，生活却不会给你补回这一段。",
        ]
        let index = (summary.lateDays + summary.totalSeconds / 60) % activities.count
        let reminder = reminders[(index + summary.lateDays) % reminders.count]
        return "\(period)有 \(summary.lateDays) 天晚下班，浪费了 \(duration)。\(activities[index])\(reminder)"
    }
}

/// 晚下班柱状图。Swift Charts 在 macOS 13 上会把轴标签裁剪到最窄标签的宽度
///（多字标签只剩最后一个字），因此这里用 Canvas 自绘柱、网格与刻度。
private struct OvertimeBarChart: View {
    let days: [DailyOvertime]
    let maximumMinutes: Double
    let labelStride: Int
    let barColor: Color

    private let leadingInset: CGFloat = 38
    private let trailingInset: CGFloat = 2
    private let topInset: CGFloat = 6
    private let bottomInset: CGFloat = 22
    private let calendar = Calendar.current

    private var tickStep: Int {
        let candidates = [5, 10, 15, 20, 30, 60, 120, 240, 480, 960]
        return candidates.first { maximumMinutes / Double($0) <= 4.2 } ?? 960
    }

    var body: some View {
        Canvas { context, size in
            guard !days.isEmpty, maximumMinutes > 0 else { return }
            let plot = CGRect(x: leadingInset, y: topInset,
                              width: max(0, size.width - leadingInset - trailingInset),
                              height: max(0, size.height - topInset - bottomInset))
            let baseline = Path { path in
                path.move(to: CGPoint(x: plot.minX, y: plot.maxY))
                path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            }
            context.stroke(baseline, with: .color(.primary.opacity(0.2)), lineWidth: 1)

            let step = tickStep
            var tick = 0
            while Double(tick) <= maximumMinutes {
                let y = plot.maxY - plot.height * Double(tick) / maximumMinutes
                if tick > 0 {
                    let grid = Path { path in
                        path.move(to: CGPoint(x: plot.minX, y: y))
                        path.addLine(to: CGPoint(x: plot.maxX, y: y))
                    }
                    context.stroke(grid, with: .color(.primary.opacity(0.08)), lineWidth: 1)
                }
                context.draw(Text("\(tick)分").font(.caption2).foregroundColor(.secondary),
                             at: CGPoint(x: plot.minX - 5, y: y), anchor: .trailing)
                tick += step
            }

            let columnWidth = plot.width / Double(days.count)
            let barWidth = columnWidth * 0.65
            for (index, day) in days.enumerated() {
                guard day.minutes > 0 else { continue }
                let barHeight = plot.height * day.minutes / maximumMinutes
                let barRect = CGRect(x: plot.minX + columnWidth * Double(index) + (columnWidth - barWidth) / 2,
                                     y: plot.maxY - barHeight, width: barWidth, height: barHeight)
                context.fill(Path(roundedRect: barRect, cornerRadius: 3), with: .color(barColor))
            }

            for index in stride(from: 0, to: days.count, by: labelStride) {
                let day = days[index].date
                let x = plot.minX + columnWidth * (Double(index) + 0.5)
                context.draw(Text("\(calendar.component(.day, from: day))日")
                    .font(.caption2).foregroundColor(.secondary),
                             at: CGPoint(x: x, y: plot.maxY + 4), anchor: .top)
            }
        }
    }
}
