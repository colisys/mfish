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
                    Text("登录时启动")
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.loginEnabled },
                                             set: { model.setLoginEnabled($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Text("建议先将应用复制到 /Applications 或 ~/Applications 再开启；移动应用后需重新开启。")
                    .font(.caption).foregroundStyle(.secondary)
                if let configError = model.configError {
                    Text(configError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var sourcePanel: some View {
        FishPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("节假日数据源").font(.headline)
                TextField("URL 模板", text: $templateDraft)
                    .textFieldStyle(.roundedBorder)
                Text("需为 HTTPS 且包含 {year} 占位符。默认使用 holiday-cn，每日自动同步国务院放假公告，无需随年份更新 App。")
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