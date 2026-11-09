import FishCore
import SwiftUI

struct SettingsPage: View {
    @ObservedObject var model: AppModel
    @State private var templateDraft = ""
    @State private var templateError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置").font(.title2.bold())
            generalPanel
            warningPanel
            sourcePanel
            cachePanel
            Text("MFish 0.1.0 · GPLv3 · 数据：NateScarlet/holiday-cn")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear {
            templateDraft = model.config.sourceURLTemplate
        }
    }

    private var generalPanel: some View {
        FishPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("通用").font(.headline)
                HStack {
                    Text("讨债模式")
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.config.debtModeEnabled },
                                             set: { model.setDebtModeEnabled($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Text("上班打卡后显示下班倒计时，超时后红色闪烁。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("超时弹窗提醒")
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.config.debtReminderEnabled },
                                             set: { model.setDebtReminderEnabled($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!model.config.debtModeEnabled)
                }
                HStack {
                    Text("提醒间隔")
                    Spacer()
                    Stepper("\(model.config.debtReminderIntervalMinutes) 分钟",
                            value: Binding(get: { model.config.debtReminderIntervalMinutes },
                                           set: { model.setDebtReminderIntervalMinutes($0) }),
                            in: 1...120)
                        .frame(width: 140)
                        .disabled(!model.config.debtModeEnabled || !model.config.debtReminderEnabled)
                }
                Text("超时后定时弹窗，打下班卡后停止。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("登录时启动")
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.loginEnabled },
                                             set: { model.setLoginEnabled($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Text("请先将应用移至「应用程序」；移动后需重新开启。")
                    .font(.caption).foregroundStyle(.secondary)
                if let configError = model.configError {
                    Text(configError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var warningPanel: some View {
        FishPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("工时警戒线").font(.headline)
                    Spacer()
                    Text("仅讨债模式显示")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("每日标准工时")
                    Spacer()
                    Stepper(hoursText(model.config.standardDailyHours),
                            value: Binding(get: { model.config.standardDailyHours },
                                           set: { model.setStandardDailyHours($0) }),
                            in: 0.5...24, step: 0.5)
                        .frame(width: 150)
                }
                HStack {
                    Text("每周标准工时")
                    Spacer()
                    Stepper(hoursText(model.config.standardWeeklyHours),
                            value: Binding(get: { model.config.standardWeeklyHours },
                                           set: { model.setStandardWeeklyHours($0) }),
                            in: 1...168, step: 0.5)
                        .frame(width: 150)
                }
                HStack {
                    Text("警示阈值")
                    Spacer()
                    Stepper("\(model.config.warningThresholdPercent)%",
                            value: Binding(get: { model.config.warningThresholdPercent },
                                           set: { model.setWarningThresholdPercent($0) }),
                            in: 100...400, step: 10)
                        .frame(width: 150)
                }
                Text("工时超过「基准 × 阈值」时警示，仅作健康提醒。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("恢复默认（8小时／40小时／150%）") {
                    model.resetWorkHourWarningDefaults()
                }
            }
        }
    }

    private func hoursText(_ hours: Double) -> String {
        let text = hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
        return "\(text) 小时"
    }

    private var sourcePanel: some View {
        FishPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("节假日数据源").font(.headline)
                TextField("URL 模板", text: $templateDraft)
                    .textFieldStyle(.roundedBorder)
                Text("使用 HTTPS 地址，以 {year} 代表年份。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("保存") { saveTemplate() }
                        .buttonStyle(.borderedProminent)
                    Button("恢复默认") {
                        templateDraft = FishConfig().sourceURLTemplate
                        templateError = nil
                    }
                    Spacer()
                }
                if let templateError {
                    Text(templateError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var cachePanel: some View {
        FishPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("本地缓存").font(.headline)
                    Spacer()
                    Button(model.refreshing ? "正在更新…" : "立即更新") {
                        Task { await model.refresh() }
                    }
                    .disabled(model.refreshing)
                }
                if model.cacheDates.isEmpty {
                    Text("暂无缓存，当前仅按周末计算。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(model.cacheDates.keys.sorted(), id: \.self) { year in
                            HStack {
                                Text("\(String(year)) 年").font(.callout)
                                Spacer()
                                if let fetchedAt = model.cacheDates[year] {
                                    Text("更新于 \(FishFormat.dateTime(fetchedAt))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if let error = model.dataError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func saveTemplate() {
        do {
            try model.saveTemplate(templateDraft)
            templateError = nil
        } catch {
            templateError = error.localizedDescription
        }
    }
}