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

struct HolidaysPage: View {
    @ObservedObject var model: AppModel
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var editing: HolidayEditorState?
    @State private var error: String?
    @State private var dayDate = Date()
    @State private var dayIsOff = false
    @State private var dayName = "公司调休"

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
            Text("修改只影响本机计算，保存在配置中；数据源更新不会覆盖你的修改。")
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
        let periods = model.calendar.periods(inYear: year)
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
                            Text(existing == nil ? "官方" : isOfficial ? "已修改" : "自定义")
                                .font(.caption2)
                                .foregroundStyle(existing == nil ? Color.secondary : isOfficial ? Color.orange : Color.accentColor)
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
            Text("单日标记优先于一切规则，适合公司自己的调休安排；也可以在“上班日历”里点选日期标记。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.config.dayOverrides.sorted { $0.date < $1.date }) { dayOverride in
                HStack {
                    Text(dayOverride.date).font(.callout.monospacedDigit())
                    Text(dayOverride.isOffDay ? "休息" : "上班")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(dayOverride.isOffDay ? .green : .orange)
                    Text(dayOverride.name).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("删除") { model.deleteDayOverride(id: dayOverride.id) }
                }
            }
            HStack {
                DatePicker("", selection: $dayDate, displayedComponents: .date)
                    .labelsHidden().frame(width: 110)
                Picker("", selection: $dayIsOff) {
                    Text("上班").tag(false)
                    Text("休息").tag(true)
                }
                .labelsHidden().frame(width: 80)
                TextField("名称", text: $dayName).frame(width: 110)
                Button("添加") {
                    do {
                        try model.saveDayOverride(DayOverride(date: HolidayCalendar.dayKey(for: dayDate),
                                                              isOffDay: dayIsOff, name: dayName))
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
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