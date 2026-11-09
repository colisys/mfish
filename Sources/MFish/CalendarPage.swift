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
            Text("休=休息日，假=节假日，班=调休上班；日期下方为假期名称或农历日，圆点表示当天有打卡。")
                .font(.callout).foregroundStyle(.secondary)
            monthNav
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
                    Text("自定义标记：\(existing.name)（\(existing.isOffDay ? "休息" : "上班")）")
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

    private func dayCell(_ date: Date) -> some View {
        let cal = Calendar.current
        let kind = model.workCalendar.kind(on: date)
        let isToday = cal.isDate(date, inSameDayAs: model.now)
        let isSelected = cal.isDate(date, inSameDayAs: selected)
        let hasClock = model.records.clockIns[HolidayCalendar.dayKey(for: date)]?.start != nil
        let subtitle = cellSubtitle(kind, on: date)
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