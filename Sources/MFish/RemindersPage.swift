import FishCore
import SwiftUI

private enum RuleKind: String, CaseIterable, Identifiable {
    case daily, workdays, weekly, once
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: return "每天"
        case .workdays: return "仅工作日"
        case .weekly: return "每周"
        case .once: return "一次性"
        }
    }
}

private struct ReminderEditorState: Identifiable {
    let id = UUID()
    var reminderID: UUID?
    var title: String
    var time: Date
    var kind: RuleKind
    var weekdays: Set<Int>
    var onceDate: Date
    var enabled: Bool
}

struct RemindersPage: View {
    @ObservedObject var model: AppModel
    @State private var scheduleDraft = WorkSchedule()
    @State private var editing: ReminderEditorState?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("提醒").font(.title2.bold())
                Text("提醒由常驻的 MFish 触发，退出 App 后不会提醒；节假日与调休按合并日历智能跳过。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            notificationPanel
            schedulePanel
            customPanel
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if let reminderError = model.reminderError {
                Text(reminderError).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { scheduleDraft = model.config.schedule }
        .sheet(item: $editing) { state in
            ReminderEditorSheet(state: state) { reminder in
                do {
                    try model.saveCustomReminder(reminder)
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private var notificationPanel: some View {
        FishPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("通知权限").font(.headline)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启用系统通知")
                        Text(model.notificationStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.config.notificationsEnabled },
                                             set: { enabled in Task { await model.setNotifications(enabled) } }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private var schedulePanel: some View {
        FishPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("工作作息").font(.headline)
                    Spacer()
                    Toggle("启用", isOn: $scheduleDraft.enabled)
                        .toggleStyle(.switch)
                }
                VStack(spacing: 10) {
                    row("上班时间") {
                        DatePicker("", selection: timeBinding(\.startMinutes), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 96)
                    }
                    row("下班时间") {
                        DatePicker("", selection: timeBinding(\.endMinutes), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 96)
                    }
                    row("周末模式") {
                        Picker("", selection: $scheduleDraft.weekMode) {
                            Text("双休").tag(WeekMode.double)
                            Text("单休").tag(WeekMode.single)
                            Text("单双交替").tag(WeekMode.alternating)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }
                    if scheduleDraft.weekMode != .single {
                        row(scheduleDraft.weekMode == .alternating ? "双周休息日" : "每周休息日") {
                            WeekdayPicker(days: restDaysBinding(\.restWeekdays))
                        }
                    }
                    if scheduleDraft.weekMode != .double {
                        row(scheduleDraft.weekMode == .alternating ? "单周休息日" : "每周休息日") {
                            WeekdayPicker(days: restDaysBinding(\.singleRestWeekdays))
                        }
                    }
                    if scheduleDraft.weekMode == .alternating {
                        row("锚定周") {
                            DatePicker("", selection: anchorBinding, displayedComponents: .date)
                                .labelsHidden()
                                .frame(width: 120)
                            Picker("", selection: $scheduleDraft.anchorIsSingle) {
                                Text("双休周").tag(false)
                                Text("单休周").tag(true)
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }
                    }
                }
                Text(scheduleDraft.weekMode == .alternating
                     ? "点击圆圈选择休息日；锚定周任选该周中的一天，单双按此交替。节假日与调休优先于个人安排。"
                     : "点击圆圈选择休息日；法定节假日与调休上班优先于此安排。")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack {
                    Toggle("上班提醒", isOn: $scheduleDraft.remindStart)
                        .toggleStyle(.switch)
                    Toggle("下班提醒", isOn: $scheduleDraft.remindEnd)
                        .toggleStyle(.switch)
                    Spacer()
                    Button("保存作息") {
                        do {
                            try model.saveSchedule(scheduleDraft)
                            error = nil
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var customPanel: some View {
        FishPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("自定义提醒").font(.headline)
                    Spacer()
                    Button("添加提醒…") {
                        editing = ReminderEditorState(reminderID: nil, title: "", time: Self.minutesToDate(540),
                                                      kind: .daily, weekdays: [2, 3, 4, 5, 6],
                                                      onceDate: model.now, enabled: true)
                    }
                }
                if model.config.customReminders.isEmpty {
                    Text("还没有自定义提醒，例如“喝水”“周报”“下班前打卡”。")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                ForEach(model.config.customReminders) { reminder in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(get: { reminder.enabled },
                                                 set: { model.setCustomEnabled(reminder.id, $0) }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title).font(.body.weight(.medium))
                            Text("\(Self.minutesText(reminder.minutes)) · \(Self.ruleText(reminder.rule))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { editing = editorState(for: reminder) } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("编辑")
                        Button { model.deleteCustomReminder(reminder.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("删除")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
    }

    private func editorState(for reminder: CustomReminder) -> ReminderEditorState {
        var state = ReminderEditorState(reminderID: reminder.id, title: reminder.title,
                                        time: Self.minutesToDate(reminder.minutes), kind: .daily,
                                        weekdays: [2, 3, 4, 5, 6], onceDate: model.now,
                                        enabled: reminder.enabled)
        switch reminder.rule {
        case .daily: state.kind = .daily
        case .workdays: state.kind = .workdays
        case let .weekly(days):
            state.kind = .weekly
            state.weekdays = Set(days)
        case let .once(date):
            state.kind = .once
            state.onceDate = HolidayCalendar.parseDay(date, calendar: .current) ?? model.now
        }
        return state
    }

    private func timeBinding(_ keyPath: WritableKeyPath<WorkSchedule, Int>) -> Binding<Date> {
        Binding {
            Self.minutesToDate(scheduleDraft[keyPath: keyPath])
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            scheduleDraft[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private func restDaysBinding(_ keyPath: WritableKeyPath<WorkSchedule, [Int]>) -> Binding<Set<Int>> {
        Binding {
            Set(scheduleDraft[keyPath: keyPath])
        } set: { newValue in
            scheduleDraft[keyPath: keyPath] = newValue.sorted()
        }
    }

    private var anchorBinding: Binding<Date> {
        Binding {
            HolidayCalendar.parseDay(scheduleDraft.anchorMonday, calendar: .current) ?? model.now
        } set: { newValue in
            scheduleDraft.anchorMonday = HolidayCalendar.dayKey(for: newValue)
        }
    }

    static func minutesToDate(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutesText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func ruleText(_ rule: RepeatRule) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        switch rule {
        case .daily: return "每天"
        case .workdays: return "仅工作日"
        case let .weekly(days):
            return "每周" + days.sorted().map { names[($0 - 1) % 7] }.joined(separator: "、")
        case let .once(date): return "\(date) 一次"
        }
    }
}

private struct ReminderEditorSheet: View {
    let state: ReminderEditorState
    let onSave: (CustomReminder) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var time: Date
    @State private var kind: RuleKind
    @State private var weekdays: Set<Int>
    @State private var onceDate: Date

    init(state: ReminderEditorState, onSave: @escaping (CustomReminder) -> Void) {
        self.state = state
        self.onSave = onSave
        _title = State(initialValue: state.title)
        _time = State(initialValue: state.time)
        _kind = State(initialValue: state.kind)
        _weekdays = State(initialValue: state.weekdays)
        _onceDate = State(initialValue: state.onceDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.reminderID == nil ? "添加提醒" : "编辑提醒").font(.headline)
            TextField("标题，如：喝水", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("时间")
                Spacer()
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(width: 96)
            }
            Picker("重复", selection: $kind) {
                ForEach(RuleKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if kind == .weekly {
                WeekdayPicker(days: $weekdays)
            }
            if kind == .once {
                DatePicker("日期", selection: $onceDate, displayedComponents: .date)
                Text("一次性提醒触发后会自动停用。").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                    let rule: RepeatRule
                    switch kind {
                    case .daily: rule = .daily
                    case .workdays: rule = .workdays
                    case .weekly: rule = .weekly(Array(weekdays).sorted())
                    case .once: rule = .once(HolidayCalendar.dayKey(for: onceDate))
                    }
                    onSave(CustomReminder(id: state.reminderID ?? UUID(), title: title,
                                          minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0),
                                          rule: rule, enabled: state.enabled))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || (kind == .weekly && weekdays.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}