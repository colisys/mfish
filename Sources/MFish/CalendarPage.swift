import FishCore
import SwiftUI

struct CalendarPage: View {
    @ObservedObject var model: AppModel
    @State private var month = Date()
    @State private var selected = Date()
    @State private var error: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("上班日历").font(.title2.bold())

            monthNav
            monthWorkSummary
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 58)
                    }
                }
            }
            legend
            Divider()
            dayDetail
            if model.config.debtModeEnabled {
                workHoursComparison
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var monthNav: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Text(monthTitle).font(.headline).frame(minWidth: 110)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            Spacer()
            Button("回到今天") {
                month = model.now
                selected = model.now
            }
        }
    }

    private var monthWorkSummary: some View {
        HStack {
            Label("本月应上班时长", systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(FishFormat.duration(WorkTimeCalculator.expectedWorkDuration(
                inMonth: month, workCalendar: model.workCalendar, schedule: model.config.schedule)))
                .font(.callout.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 4)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                Text(day).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("休", .green)
            legendItem("假", .accentColor)
            legendItem("班", .orange)
            HStack(spacing: 4) {
                Circle().fill(Color.secondary).frame(width: 4, height: 4)
                Text("有打卡").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func legendItem(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.caption2.bold()).foregroundStyle(color)
            Text(color == .green ? "休息" : color == .orange ? "上班" : "假期")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var dayDetail: some View {
        let date = selected
        let key = HolidayCalendar.dayKey(for: date)
        let kind = model.workCalendar.kind(on: date)
        let clock = model.records.clockIns[key]
        let existing = model.config.dayOverrides.first { $0.date == key }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(FishFormat.day(date)).font(.headline)
                Text(kindText(kind, on: date)).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(LunarCalendar.lunar(for: date).fullText)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let clock, clock.start != nil {
                Text("打卡：上班 \(clock.start.map(FishFormat.time) ?? "—") · 下班 \(clock.end.map(FishFormat.time) ?? "—")")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                if let existing {
                    Text("\(existing.name) · \(existing.isOffDay ? "休息" : "上班") · \(overrideTimeText(existing))")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("清除标记") { model.deleteDayOverride(id: existing.id) }
                } else {
                    Button("标记调休上班") { saveDay(key: key, isOffDay: false, name: "自定义调休") }
                    Button("标记额外休息") { saveDay(key: key, isOffDay: true, name: "自定义休息") }
                }
                Spacer()
            }
        }
    }

    private var workHoursComparison: some View {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: selected)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let lastDay = calendar.date(byAdding: .day, value: -1, to: weekEnd) ?? weekEnd
        return FishPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("工时与生活警戒线", systemImage: "heart.text.square")
                        .font(.headline)
                    Spacer()
                    Text("阈值 \(model.config.warningThresholdPercent)%")
                        .font(.caption).foregroundStyle(.secondary)
                }
                hoursComparisonRow(title: "所选日", start: day, end: nextDay,
                                   standardHours: model.config.standardDailyHours, isDaily: true)
                Divider()
                Text("所在周：\(FishFormat.shortDay(weekStart))–\(FishFormat.shortDay(lastDay))")
                    .font(.caption).foregroundStyle(.secondary)
                hoursComparisonRow(title: "所在周", start: weekStart, end: weekEnd,
                                   standardHours: model.config.standardWeeklyHours, isDaily: false)

            }
        }
    }

    private func hoursComparisonRow(title: String, start: Date, end: Date,
                                    standardHours: Double, isDaily: Bool) -> some View {
        let thresholdPercent = model.config.warningThresholdPercent
        let comparison = WorkTimeCalculator.workHoursComparison(
            clockIns: model.records.clockIns, from: start, until: end, standardHours: standardHours,
            thresholdPercent: thresholdPercent, workCalendar: model.workCalendar,
            schedule: model.config.schedule)
        let threshold = FishFormat.duration(TimeInterval(comparison.thresholdSeconds))
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(title) · 标准 \(hoursLabel(standardHours))小时 · 警戒线 \(threshold)")
                .font(.callout.weight(.semibold))
            Text("排班 \(FishFormat.duration(TimeInterval(comparison.scheduledSeconds))) · 已打卡 \(FishFormat.duration(TimeInterval(comparison.actualSeconds)))（\(comparison.completedDays)天完整记录）")
                .font(.callout.monospacedDigit())
            if comparison.needsWarning {
                VStack(alignment: .leading, spacing: 5) {
                    Label(comparison.scheduledExceedsWarning ? "排班工时越过警戒线" : "实际工时越过警戒线",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold)).foregroundStyle(.red)
                    ForEach(Array(warningLines(for: comparison, isDaily: isDaily).enumerated()), id: \.offset) {
                        Text($0.element)
                            .font(.callout).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

            }
        }
    }

    /// Rotating, concrete reminders so repeated days do not read like a template.
    private func warningLines(for comparison: WorkHoursComparison, isDaily: Bool) -> [String] {
        let ratio = comparison.worstRatio
        let count = isDaily ? comparison.completedDays : comparison.completedDays
        let head = isDaily
            ? "这真的值得吗？工时已经超过标准的 \(ratio) 倍。"
            : "这一周的工作量是标准的 \(ratio) 倍，生活被挤到了边角。"
        let dailyPool = [
            "这班是上了，但身体什么时候才休息？",
            "多出来的小时不会写进工资条，只会写进你的疲惫。",
            "公司在算产出，没人替你算睡眠。",
            "今天的时间全给了工位，留给自己的只剩通勤和回不完的消息。",
            "工作可以补，精力不能补打卡。",
            "撑住今天，未必能撑住下一个月。把节奏拿回来。",
            "回家之后你还有几小时？这几小时还要减去吃饭和刷牙。",
        ]
        let weeklyPool = [
            "一周七天，你把最好的清醒时段都交给了公司。",
            "周报写得再漂亮，也换不回这一周的生活。",
            "赶进度的人最容易把周末也交出去，可周一只会照常到来。",
            "工作还在继续，你的恢复时间已经欠账。",
            "这一周的加班时长，够你好好睡几个整觉。",
            "别让“忙完这阵”变成每个月的固定句式。",
            "上班的人是你，被消耗的也是你。",
        ]
        let pool = isDaily ? dailyPool : weeklyPool
        let index = abs(comparison.scheduledSeconds / 60 + count) % pool.count
        let tail = pool[index]
        return [head, tail]
    }

    private func hoursLabel(_ hours: Double) -> String {
        hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
    }

    private func overrideTimeText(_ day: DayOverride) -> String {
        guard let start = day.startMinutes, let end = day.endMinutes else { return "全天" }
        return String(format: "%02d:%02d–%02d:%02d", start / 60, start % 60, end / 60, end % 60)
    }

    private func dayCell(_ date: Date) -> some View {
        let cal = Calendar.current
        let kind = model.workCalendar.kind(on: date)
        let isToday = cal.isDate(date, inSameDayAs: model.now)
        let isSelected = cal.isDate(date, inSameDayAs: selected)
        let hasClock = model.records.clockIns[HolidayCalendar.dayKey(for: date)]?.start != nil
        let timedOverride = model.calendar.timedOverride(on: date)
        let subtitle = timedOverride.map { ($0.name, $0.isOffDay ? Color.green : Color.orange) }
            ?? cellSubtitle(kind, on: date)
        return Button { selected = date } label: {
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    Text("\(cal.component(.day, from: date))")
                        .font(.callout.weight(isToday ? .bold : .regular).monospacedDigit())
                        .foregroundStyle(isToday ? Color.accentColor : .primary)
                    Text(badge(kind))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(badgeColor(kind))
                }
                Text(subtitle.0)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(subtitle.1)
                Circle().fill(Color.secondary).frame(width: 4, height: 4)
                    .opacity(hasClock ? 1 : 0)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(isSelected ? Color.accentColor.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isToday ? Color.accentColor : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cellSubtitle(_ kind: DayKind, on date: Date) -> (String, Color) {
        switch kind {
        case let .holiday(name): return (name, .accentColor)
        case let .makeupWorkday(name): return (name, .orange)
        case .rest, .work: return (LunarCalendar.lunar(for: date).dayName, .secondary)
        }
    }

    private var monthTitle: String {
        let parts = Calendar.current.dateComponents([.year, .month], from: month)
        return "\(String(parts.year ?? 0))年\(parts.month ?? 0)月"
    }

    private var monthDays: [Date?] {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let count = cal.range(of: .day, in: .month, for: start)?.count else { return [] }
        let leading = (cal.component(.weekday, from: start) + 5) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<count {
            days.append(cal.date(byAdding: .day, value: offset, to: start))
        }
        return days
    }

    private func shiftMonth(_ value: Int) {
        month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
    }

    private func badge(_ kind: DayKind) -> String {
        switch kind {
        case .holiday: return "假"
        case .makeupWorkday: return "班"
        case .rest: return "休"
        case .work: return ""
        }
    }

    private func badgeColor(_ kind: DayKind) -> Color {
        switch kind {
        case .holiday: return .accentColor
        case .makeupWorkday: return .orange
        case .rest: return .green
        case .work: return .clear
        }
    }

    private func kindText(_ kind: DayKind, on date: Date) -> String {
        switch kind {
        case let .holiday(name): return "\(name) · 休息"
        case let .makeupWorkday(name): return "\(name) · 上班"
        case .rest: return "休息"
        case .work:
            if Calendar.current.isDateInWeekend(date),
               model.config.schedule.enabled, model.workCalendar.isSingleWeek(containing: date) {
                return "单休周 · 上班"
            }
            return "工作日"
        }
    }

    private func saveDay(key: String, isOffDay: Bool, name: String) {
        do {
            try model.saveDayOverride(DayOverride(date: key, isOffDay: isOffDay, name: name))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}