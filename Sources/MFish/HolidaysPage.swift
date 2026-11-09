import FishCore
import SwiftUI

private struct HolidayEditorState: Identifiable {
    let id = UUID()
    var overrideID: UUID?
    var name: String
    var nameEditable: Bool
    var start: Date
    var end: Date
}

private struct DayEditorState: Identifiable {
    let id = UUID()
    var existing: DayOverride?
    var date: Date
}

struct HolidaysPage: View {
    @ObservedObject var model: AppModel
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var editing: HolidayEditorState?
    @State private var error: String?
    @State private var dayEditing: DayEditorState?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("节假日").font(.title2.bold())
                Spacer()
                Picker("年份", selection: $year) {
                    ForEach(years, id: \.self) { Text("\(String($0)) 年").tag($0) }
                }
                .frame(width: 130)
            }
            Text("修改仅在本机生效，不受数据更新影响。")
                .font(.callout).foregroundStyle(.secondary)
            periodsList
            Button("添加自定义假期…") {
                editing = HolidayEditorState(overrideID: nil, name: "", nameEditable: true,
                                             start: model.now, end: model.now)
            }
            Divider()
            dayOverridesSection
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .sheet(item: $dayEditing) { state in
            DayEditorSheet(state: state) { day in
                try model.saveDayOverride(day, replacingID: state.existing?.id)
            }
        }
        .sheet(item: $editing) { state in
            HolidayEditorSheet(state: state) { override, replacingID in
                do {
                    try model.saveOverride(override, replacingID: replacingID)
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private var years: [Int] {
        Array(Set(model.calendar.dataYears)
            .union([Calendar.current.component(.year, from: model.now)])).sorted()
    }

    private var periodsList: some View {
        let periods = model.holidayListCalendar.periods(inYear: year)
        let officialNames = Set(model.sourceCalendar.periods(inYear: year).map(\.name))
        return VStack(spacing: 6) {
            if periods.isEmpty {
                Text("该年份暂无节假日数据。").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(periods, id: \.start) { period in
                let isOfficial = officialNames.contains(period.name)
                let existing = model.override(forName: period.name, year: year)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(period.name).font(.body.weight(.medium))
                            Text(isOfficial ? (existing == nil ? "官方" : "已修改") : "自定义")
                                .font(.caption2)
                                .foregroundStyle(isOfficial ? (existing == nil ? Color.secondary : Color.orange) : Color.accentColor)
                        }
                        Text("\(FishFormat.shortDay(period.start))–\(FishFormat.shortDay(period.end)) · 共\(period.dayCount)天")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("编辑") {
                        editing = HolidayEditorState(overrideID: existing?.id, name: period.name,
                                                     nameEditable: !isOfficial,
                                                     start: period.start, end: period.end)
                    }
                    if existing != nil {
                        Button(isOfficial ? "恢复官方" : "删除") {
                            model.resetOverride(name: period.name, year: year)
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var dayOverridesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("自定义调休 / 休息日").font(.headline)
            Text("单日标记优先于其他日历规则。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.config.dayOverrides.sorted { $0.date < $1.date }) { dayOverride in
                HStack {
                    Text(dayOverride.date).font(.callout.monospacedDigit())
                    Text(dayOverride.isOffDay ? "休息" : "上班")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(dayOverride.isOffDay ? .green : .orange)
                    Text(dayOverride.name).font(.callout).foregroundStyle(.secondary)
                    Text(timeRangeText(dayOverride)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button("编辑") {
                                            dayEditing = DayEditorState(existing: dayOverride,
                                                date: HolidayCalendar.parseDay(dayOverride.date, calendar: .current) ?? model.now)
                                        }
                    Button("删除") { model.deleteDayOverride(id: dayOverride.id) }
                }
            }
            Button("添加上班／调休…") {
                dayEditing = DayEditorState(date: model.now)
            }
        }
    }


    private func timeRangeText(_ day: DayOverride) -> String {
        guard let start = day.startMinutes, let end = day.endMinutes else { return "全天" }
        return String(format: "%02d:%02d–%02d:%02d", start / 60, start % 60, end / 60, end % 60)
    }

}

private struct DayEditorSheet: View {
    let state: DayEditorState
    let onSave: (DayOverride) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var name: String
    @State private var isOff: Bool
    @State private var allDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var error: String?

    init(state: DayEditorState, onSave: @escaping (DayOverride) throws -> Void) {
        self.state = state
        self.onSave = onSave
        let day = Calendar.current.startOfDay(for: state.date)
        _date = State(initialValue: state.date)
        _name = State(initialValue: state.existing?.name ?? "公司调休")
        _isOff = State(initialValue: state.existing?.isOffDay ?? true)
        _allDay = State(initialValue: state.existing?.isAllDay ?? true)
        _start = State(initialValue: Calendar.current.date(byAdding: .minute,
            value: state.existing?.startMinutes ?? 540, to: day) ?? day)
        _end = State(initialValue: Calendar.current.date(byAdding: .minute,
            value: state.existing?.endMinutes ?? 720, to: day) ?? day)
    }

    private func minutes(_ date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }

    private var invalidTime: Bool { !allDay && minutes(end) <= minutes(start) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(state.existing == nil ? "添加上班／调休" : "编辑上班／调休").font(.headline)
            Form {
                DatePicker("日期", selection: $date, displayedComponents: .date)
                Picker("类型", selection: $isOff) {
                    Text("上班").tag(false)
                    Text("休息／调休").tag(true)
                }
                TextField("名称", text: $name)
                Toggle("全天", isOn: $allDay)
                if !allDay {
                    DatePicker("开始时间", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("结束时间", selection: $end, displayedComponents: .hourAndMinute)
                }
            }
            if invalidTime {
                Text("结束时间需晚于开始时间。")
                    .font(.caption).foregroundStyle(.red)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    do {
                        try onSave(DayOverride(id: state.existing?.id ?? UUID(),
                            date: HolidayCalendar.dayKey(for: date), isOffDay: isOff,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            startMinutes: allDay ? nil : minutes(start),
                            endMinutes: allDay ? nil : minutes(end)))
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(invalidTime || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct HolidayEditorSheet: View {
    let state: HolidayEditorState
    let onSave: (HolidayOverride, UUID?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var start: Date
    @State private var end: Date

    init(state: HolidayEditorState, onSave: @escaping (HolidayOverride, UUID?) -> Void) {
        self.state = state
        self.onSave = onSave
        _name = State(initialValue: state.name)
        _start = State(initialValue: state.start)
        _end = State(initialValue: state.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.nameEditable ? "自定义假期" : "修改假期").font(.headline)
            TextField("名称", text: $name)
                .disabled(!state.nameEditable)
            DatePicker("开始日期", selection: $start, displayedComponents: .date)
            DatePicker("结束日期", selection: $end, displayedComponents: .date)
            Text("起止都算假期；同名假期的官方调休安排会一并被替换。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    onSave(HolidayOverride(name: name,
                                           start: HolidayCalendar.dayKey(for: start),
                                           end: HolidayCalendar.dayKey(for: end)),
                           state.overrideID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}