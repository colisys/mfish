import AppKit
import FishCore
import SwiftUI
import UserNotifications

@main
struct MFishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
        Window("MFish · 上班日历", id: "control") {
            ControlView(model: model)
        }
        .defaultSize(width: 780, height: 620)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "fish")
                .font(.system(size: 11.5, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(model.menuBarText)
                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
        }
        .help("MFish · 摸鱼日历")
        .accessibilityLabel("MFish，\(model.menuBarText)")
    }
}

struct FishFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var calendar = HolidayCalendar(years: [])
    @Published private(set) var sourceCalendar = HolidayCalendar(years: [])
    @Published private(set) var cacheDates: [Int: Date] = [:]
    @Published private(set) var refreshing = false
    @Published private(set) var dataError: String?
    @Published private(set) var loginEnabled = false
    @Published private(set) var config = FishConfig()
    @Published private(set) var configError: String?
    @Published private(set) var records = FishRecords()
    @Published private(set) var reminderError: String?
    @Published private(set) var notificationStatus = "正在读取通知权限…"
    @Published var controlPage: ControlPage = .calendar

    private let configStore: ConfigStore
    private let recordsStore: RecordsStore
    private let cache: HolidayCache
    private let fetcher = HolidayFetcher()
    private var configWritable = true
    private var recordsWritable = true
    private var tickTask: Task<Void, Never>?
    private var lastRefreshAttempt: Date?
    private var lastRefreshSucceeded = false
    private var changingNotifications = false

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MFish")
        configStore = ConfigStore(url: base.appendingPathComponent("config.json"))
        recordsStore = RecordsStore(url: base.appendingPathComponent("records.json"))
        cache = HolidayCache(directory: base.appendingPathComponent("holidays"))
        do { config = try configStore.load() }
        catch {
            configWritable = false
            configError = "无法读取配置；为保护原文件，本次不会写入：\(error.localizedDescription)"
        }
        do { records = try recordsStore.load() }
        catch {
            recordsWritable = false
            reminderError = "无法读取打卡记录；为保护原文件，本次不会写入：\(error.localizedDescription)"
        }
        reloadCalendar()
        loginEnabled = LoginItem.isEnabled(executable: Bundle.main.executableURL?.path)
        tickTask = Task { [weak self] in
            self?.fireDueReminders()
            await self?.refreshIfNeeded()
            await self?.refreshSystemStatus()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                catch { break }
                guard let self = self else { break }
                self.now = Date()
                self.fireDueReminders()
                await self.refreshIfNeeded()
            }
        }
    }

    deinit { tickTask?.cancel() }

    var workCalendar: WorkCalendar { WorkCalendar(holidays: calendar, schedule: config.schedule) }
    var todayKey: String { HolidayCalendar.dayKey(for: now) }
    var todayIsRestDay: Bool { workCalendar.isRestDay(on: now) }
    var todayName: String? { calendar.holidayName(on: now) }
    var todayClock: ClockDay { records.clockIns[todayKey] ?? ClockDay() }

    var restCountdown: (target: Date, name: String?, interval: TimeInterval)? {
        guard let next = workCalendar.nextRestDay(after: now) else { return nil }
        return (next.date, next.name, max(0, next.date.timeIntervalSince(now)))
    }

    var menuBarText: String {
        if todayIsRestDay { return "摸鱼中" }
        guard let countdown = restCountdown else { return "—" }
        return CountdownFormat.compact(countdown.interval)
    }

    var yearProgress: YearProgress { YearProgress(now: now) }
    var almanac: Almanac { Almanac(date: now) }
    var lunar: LunarDate { LunarCalendar.lunar(for: now) }
    var nextHoliday: HolidayPeriod? { calendar.nextHoliday(after: now) }
    var currentYearHasData: Bool { calendar.hasData(forYear: yearProgress.year) }
    var remainingRestDays: Int { workCalendar.remainingRestDays(inYear: yearProgress.year, from: now) }

    func daysUntil(_ period: HolidayPeriod) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now),
                                        to: period.start).day ?? 0
    }

    // MARK: - 打卡

    func clockIn() {
        var day = records.clockIns[todayKey] ?? ClockDay()
        if day.start == nil { day.start = now } else { day.end = now }
        records.clockIns[todayKey] = day
        persistRecords()
    }

    func saveClockDay(_ day: ClockDay, forDateKey key: String) throws {
        guard HolidayCalendar.parseDay(key, calendar: .current) != nil else {
            throw FishFailure("打卡日期无效。")
        }
        guard day.isValid else {
            throw FishFailure("请填写上班时间；下班时间需晚于上班时间。")
        }
        records.clockIns[key] = day
        persistRecords()
    }

    func deleteClockDay(_ key: String) {
        records.clockIns.removeValue(forKey: key)
        persistRecords()
    }

    // MARK: - 假期修改与自定义调休

    func saveOverride(_ override: HolidayOverride, replacingID: UUID? = nil) throws {
        guard let (start, _) = override.dateRange() else {
            throw FishFailure("假期名称不能为空，起止日期需合法：开始不晚于结束，跨度不超过一年。")
        }
        let year = Calendar.current.component(.year, from: start)
        if let replacingID {
            config.overrides.removeAll { $0.id == replacingID }
        }
        config.overrides.removeAll { existing in
            existing.name == override.name
                && existing.dateRange().map { Calendar.current.component(.year, from: $0.0) } == year
        }
        config.overrides.append(override)
        persistConfig()
        reloadCalendar()
    }

    func resetOverride(name: String, year: Int) {
        config.overrides.removeAll { existing in
            existing.name == name
                && existing.dateRange().map { Calendar.current.component(.year, from: $0.0) } == year
        }
        persistConfig()
        reloadCalendar()
    }

    func override(forName name: String, year: Int) -> HolidayOverride? {
        config.overrides.first { existing in
            existing.name == name
                && existing.dateRange().map { Calendar.current.component(.year, from: $0.0) } == year
        }
    }

    func saveDayOverride(_ dayOverride: DayOverride) throws {
        guard dayOverride.isValid() else {
            throw FishFailure("调休标记需要合法日期和非空名称。")
        }
        config.dayOverrides.removeAll { $0.date == dayOverride.date }
        config.dayOverrides.append(dayOverride)
        persistConfig()
        reloadCalendar()
    }

    func deleteDayOverride(id: UUID) {
        config.dayOverrides.removeAll { $0.id == id }
        persistConfig()
        reloadCalendar()
    }

    // MARK: - 作息与自定义提醒

    func saveSchedule(_ schedule: WorkSchedule) throws {
        guard (0..<1440).contains(schedule.startMinutes), (0..<1440).contains(schedule.endMinutes),
              schedule.startMinutes < schedule.endMinutes else {
            throw FishFailure("上班时间需早于下班时间。")
        }
        let validDays: ([Int]) -> Bool = { !$0.isEmpty && $0.allSatisfy { (1...7).contains($0) } }
        guard validDays(schedule.restWeekdays), validDays(schedule.singleRestWeekdays) else {
            throw FishFailure("每周至少需要保留一个休息日。")
        }
        var schedule = schedule
        schedule.restWeekdays = Array(Set(schedule.restWeekdays)).sorted()
        schedule.singleRestWeekdays = Array(Set(schedule.singleRestWeekdays)).sorted()
        config.schedule = schedule
        persistConfig()
    }

    func saveCustomReminder(_ reminder: CustomReminder) throws {
        guard !reminder.title.trimmingCharacters(in: .whitespaces).isEmpty,
              (0..<1440).contains(reminder.minutes) else {
            throw FishFailure("提醒标题不能为空。")
        }
        if case let .weekly(days) = reminder.rule {
            guard !days.isEmpty, days.allSatisfy({ (1...7).contains($0) }) else {
                throw FishFailure("每周提醒至少选择一个星期几。")
            }
        }
        if let index = config.customReminders.firstIndex(where: { $0.id == reminder.id }) {
            config.customReminders[index] = reminder
        } else {
            config.customReminders.append(reminder)
        }
        persistConfig()
    }

    func setCustomEnabled(_ id: UUID, _ enabled: Bool) {
        guard let index = config.customReminders.firstIndex(where: { $0.id == id }) else { return }
        config.customReminders[index].enabled = enabled
        persistConfig()
    }

    func deleteCustomReminder(_ id: UUID) {
        config.customReminders.removeAll { $0.id == id }
        persistConfig()
    }

    func setNotifications(_ enabled: Bool) async {
        guard !changingNotifications else { return }
        changingNotifications = true
        defer { changingNotifications = false }
        if enabled {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                config.notificationsEnabled = granted
                if !granted { reminderError = "通知权限未开启，请在系统设置的“通知”中允许 MFish。" }
            } catch {
                config.notificationsEnabled = false
                reminderError = "请求通知权限失败：\(error.localizedDescription)"
            }
        } else {
            config.notificationsEnabled = false
        }
        persistConfig()
        await refreshSystemStatus()
    }

    // MARK: - 数据源

    func refreshIfNeeded() async {
        let interval: TimeInterval = lastRefreshSucceeded ? 86_400 : 3_600
        if let last = lastRefreshAttempt, Date().timeIntervalSince(last) < interval { return }
        await refresh()
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        lastRefreshAttempt = Date()
        let year = Calendar.current.component(.year, from: Date())
        var anySuccess = false
        var currentYearFailure: String?
        for target in [year, year + 1] {
            do {
                let data = try await fetcher.fetch(year: target, template: config.sourceURLTemplate)
                try cache.save(data, fetchedAt: Date())
                anySuccess = true
            } catch HolidaySourceError.notPublished {
                // 下一年的安排通常到年底才公布，404 属正常情况。
            } catch {
                if target == year { currentYearFailure = error.localizedDescription }
            }
        }
        reloadCalendar()
        lastRefreshSucceeded = anySuccess
        if let failure = currentYearFailure, cache.load(year: year) == nil {
            dataError = "节假日数据更新失败：\(failure)。当前仅按周末计算。"
        } else {
            dataError = nil
        }
    }

    func saveTemplate(_ template: String) throws {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try HolidaySource.url(template: trimmed, year: Calendar.current.component(.year, from: Date()))
        config.sourceURLTemplate = trimmed
        persistConfig()
        lastRefreshAttempt = nil
        Task { await refresh() }
    }

    // MARK: - 系统状态

    func setLoginEnabled(_ enabled: Bool) {
        do { try LoginItem.setEnabled(enabled, executable: Bundle.main.executableURL?.path) }
        catch { configError = "修改登录项失败：\(error.localizedDescription)" }
        loginEnabled = LoginItem.isEnabled(executable: Bundle.main.executableURL?.path)
    }

    func refreshSystemStatus() async {
        loginEnabled = LoginItem.isEnabled(executable: Bundle.main.executableURL?.path)
        let status = await UNUserNotificationCenter.current().notificationSettings()
        switch status.authorizationStatus {
        case .notDetermined: notificationStatus = "尚未请求通知权限"
        case .denied: notificationStatus = "系统已拒绝通知，请在系统设置中开启"
        case .authorized: notificationStatus = "系统已允许通知"
        case .provisional: notificationStatus = "系统允许静默通知"
        case .ephemeral: notificationStatus = "系统临时允许通知"
        @unknown default: notificationStatus = "未知通知权限状态"
        }
    }

    // MARK: - 私有

    private func fireDueReminders() {
        guard config.notificationsEnabled else { return }
        let due = ReminderEngine.due(now: now, workCalendar: workCalendar,
                                     customs: config.customReminders, fired: Set(records.firedKeys))
        guard !due.isEmpty else { return }
        var keys = Set(records.firedKeys)
        var configChanged = false
        for event in due {
            keys.insert(event.key)
            postNotification(title: event.title, body: event.body, id: event.key)
            if let id = event.disablesReminderID,
               let index = config.customReminders.firstIndex(where: { $0.id == id }) {
                config.customReminders[index].enabled = false
                configChanged = true
            }
        }
        records.firedKeys = Array(ReminderEngine.pruneFiredKeys(keys, now: now))
        persistRecords()
        if configChanged { persistConfig() }
    }

    private func postNotification(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                Task { @MainActor in self?.reminderError = "发送通知失败：\(error.localizedDescription)" }
            }
        }
    }

    private func reloadCalendar() {
        var loaded: [HolidayYear] = []
        var dates: [Int: Date] = [:]
        for year in cache.availableYears() {
            if let cached = cache.load(year: year) {
                loaded.append(cached.year)
                dates[year] = cached.fetchedAt
            }
        }
        sourceCalendar = HolidayCalendar(years: loaded)
        calendar = HolidayCalendar(years: loaded, overrides: config.overrides, dayOverrides: config.dayOverrides)
        cacheDates = dates
    }

    private func persistConfig() {
        guard configWritable else { return }
        do { try configStore.save(config) }
        catch { configError = "保存配置失败：\(error.localizedDescription)" }
    }

    private func persistRecords() {
        guard recordsWritable else { return }
        do { try recordsStore.save(records) }
        catch { reminderError = "保存打卡记录失败：\(error.localizedDescription)" }
    }
}