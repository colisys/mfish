import SwiftUI

enum ControlPage: String, CaseIterable, Identifiable {
    case calendar, clock, holidays, reminders, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calendar: return "上班日历"
        case .clock: return "打卡"
        case .holidays: return "节假日"
        case .reminders: return "提醒"
        case .settings: return "设置"
        }
    }
    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .clock: return "clock"
        case .holidays: return "calendar.badge.clock"
        case .reminders: return "bell"
        case .settings: return "gearshape"
        }
    }
}

struct ControlView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 170)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.controlPage {
                    case .calendar: CalendarPage(model: model)
                    case .clock: ClockRecordsPage(model: model)
                    case .holidays: HolidaysPage(model: model)
                    case .reminders: RemindersPage(model: model)
                    case .settings: SettingsPage(model: model)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 560)
        .task { await model.refreshSystemStatus() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.refreshSystemStatus() } }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("MFish", systemImage: "fish")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            ForEach(ControlPage.allCases) { item in
                Button { model.controlPage = item } label: {
                    Label(item.title, systemImage: item.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .foregroundColor(model.controlPage == item ? .accentColor : .primary)
                        .background(model.controlPage == item ? Color.accentColor.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.controlPage == item ? .isSelected : [])
            }
            Spacer()
            Text("摸鱼也是生产力")
                .font(.caption2).foregroundStyle(.secondary).padding(10)
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }
}