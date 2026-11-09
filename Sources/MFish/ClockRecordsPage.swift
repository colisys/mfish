import FishCore
import SwiftUI

private struct ClockEditorState: Identifiable {
    let id = UUID()
    var dateKey: String?
    var date: Date
    var start: Date
    var hasEnd: Bool
    var end: Date
}

struct ClockRecordsPage: View {
    @ObservedObject var model: AppModel
    @State private var editing: ClockEditorState?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("打卡记录").font(.title2.bold())
                    Text("在面板一键打卡；这里可以补记、修改或删除任意一天的记录。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("补记打卡…") {
                    editing = ClockEditorState(dateKey: nil, date: model.now,
                                               start: timeDate(model.config.schedule.startMinutes),
                                               hasEnd: false,
                                               end: timeDate(model.config.schedule.endMinutes))
                }
            }
            FishPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("全部记录").font(.headline)
                        Spacer()
                        Text("共 \(model.records.clockIns.count) 天")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.records.clockIns.isEmpty {
                        Text("还没有打卡记录，点菜单栏鱼图标即可打卡。")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                    ForEach(model.records.clockIns.keys.sorted(by: >), id: \.self) { key in
                        recordRow(key)
                    }
                    Text("工时为上班到下班的时长，未扣除午休。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if let reminderError = model.reminderError {
                Text(reminderError).font(.caption).foregroundStyle(.red)
            }
        }
        .sheet(item: $editing) { state in
            ClockEditorSheet(state: state, takenKeys: Set(model.records.clockIns.keys)) { key, day in
                do {
                    try model.saveClockDay(day, forDateKey: key)
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func recordRow(_ key: String) -> some View {
        let day = model.records.clockIns[key] ?? ClockDay()
        let date = HolidayCalendar.parseDay(key, calendar: .current)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(date.map(FishFormat.day) ?? key).font(.body.weight(.medium))
                    if key == model.todayKey {
                        Text("今天").font(.caption2.weight(.medium)).foregroundStyle(Color.accentColor)
                    }
                }
                Text("上班 \(day.start.map(FishFormat.time) ?? "--:--") · 下班 \(day.end.map(FishFormat.time) ?? "--:--")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(durationText(day)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Button { editing = editorState(for: key) } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("编辑")
            Button { model.deleteClockDay(key) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .padding(.vertical, 2)
    }

    private func editorState(for key: String) -> ClockEditorState {
        let day = model.records.clockIns[key] ?? ClockDay()
        return ClockEditorState(dateKey: key,
                                date: HolidayCalendar.parseDay(key, calendar: .current) ?? model.now,
                                start: day.start ?? timeDate(model.config.schedule.startMinutes),
                                hasEnd: day.end != nil,
                                end: day.end ?? timeDate(model.config.schedule.endMinutes))
    }

    private func timeDate(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: model.now) ?? model.now
    }

    private func durationText(_ day: ClockDay) -> String {
        guard let start = day.start, let end = day.end else { return "—" }
        let minutes = max(0, Int(end.timeIntervalSince(start)) / 60)
        return "\(minutes / 60)小时\(minutes % 60)分"
    }
}

private struct ClockEditorSheet: View {
    let state: ClockEditorState
    let takenKeys: Set<String>
    let onSave: (String, ClockDay) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var start: Date
    @State private var hasEnd: Bool
    @State private var end: Date

    init(state: ClockEditorState, takenKeys: Set<String>, onSave: @escaping (String, ClockDay) -> Void) {
        self.state = state
        self.takenKeys = takenKeys
        self.onSave = onSave
        _date = State(initialValue: state.date)
        _start = State(initialValue: state.start)
        _hasEnd = State(initialValue: state.hasEnd)
        _end = State(initialValue: state.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.dateKey == nil ? "补记打卡" : "编辑打卡").font(.headline)
            if state.dateKey == nil {
                DatePicker("日期", selection: $date, displayedComponents: .date)
            } else {
                HStack {
                    Text("日期")
                    Spacer()
                    Text(FishFormat.day(date)).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("上班时间")
                Spacer()
                DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(width: 96)
            }
            HStack {
                Text("下班时间")
                Spacer()
                if hasEnd {
                    DatePicker("", selection: $end, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 96)
                }
                Toggle("", isOn: $hasEnd)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if isDuplicate {
                Text("该日期已有打卡记录，可直接在列表中编辑。")
                    .font(.caption).foregroundStyle(.orange)
            } else if !endAfterStart {
                Text("下班时间需晚于上班时间。")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    let day = ClockDay(start: combine(start), end: hasEnd ? combine(end) : nil)
                    onSave(HolidayCalendar.dayKey(for: date), day)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isDuplicate || !endAfterStart)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var isDuplicate: Bool {
        state.dateKey == nil && takenKeys.contains(HolidayCalendar.dayKey(for: date))
    }

    private var endAfterStart: Bool {
        guard hasEnd else { return true }
        let cal = Calendar.current
        let s = cal.dateComponents([.hour, .minute], from: start)
        let e = cal.dateComponents([.hour, .minute], from: end)
        return (e.hour ?? 0) * 60 + (e.minute ?? 0) > (s.hour ?? 0) * 60 + (s.minute ?? 0)
    }

    private func combine(_ time: Date) -> Date? {
        let cal = Calendar.current
        let parts = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: date)
    }
}