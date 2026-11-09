import Charts
import FishCore
import SwiftUI

struct StatisticsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("加班统计").font(.title2.bold())
                Text("统计晚于设定下班时间的已完成打卡。")
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
                                           schedule: model.config.schedule)
    }

    private var monthSummary: OvertimeSummary {
        WorkTimeCalculator.overtimeSummary(clockIns: model.records.clockIns,
                                           from: monthRange.start, until: monthRange.end,
                                           schedule: model.config.schedule)
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

    private struct DailyOvertime: Identifiable {
        let date: Date
        let seconds: Int
        var id: Date { date }
        var minutes: Double { Double(seconds) / 60 }
    }

    private func dailyOvertime(in range: (start: Date, end: Date)) -> [DailyOvertime] {
        let calendar = Calendar.current
        var days: [DailyOvertime] = []
        var day = range.start
        while day < range.end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            let summary = WorkTimeCalculator.overtimeSummary(
                clockIns: model.records.clockIns, from: day, until: next,
                schedule: model.config.schedule, calendar: calendar)
            days.append(DailyOvertime(date: day, seconds: summary.totalSeconds))
            day = next
        }
        return days
    }

    private func overtimeChart(range: (start: Date, end: Date)) -> some View {
        let days = dailyOvertime(in: range)
        let maximumMinutes = max(30, (days.map(\.minutes).max() ?? 0) * 1.15)
        return Chart(days) { day in
            BarMark(
                x: .value("日期", day.date, unit: .day),
                y: .value("晚下班（分钟）", day.minutes)
            )
            .foregroundStyle(model.config.debtModeEnabled ? Color.orange : Color.accentColor)
            .cornerRadius(3)
            .accessibilityLabel(FishFormat.shortDay(day.date))
            .accessibilityValue(day.seconds > 0
                ? "晚下班 \(FishFormat.duration(TimeInterval(day.seconds)))" : "无超时")
        }
        .chartXScale(domain: range.start...range.end)
        .chartYScale(domain: 0...maximumMinutes)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: days.count > 7 ? 5 : 1)) { _ in
                AxisTick()
                AxisValueLabel(format: .dateTime.day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text("\(minutes, specifier: "%.0f")分")
                    }
                }
            }
        }
        .chartXAxisLabel("日期", alignment: .trailing)
        .frame(height: 170)
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
