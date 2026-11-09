import AppKit
import FishCore
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let error = model.dataError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
            }
            calendarBlock
            almanacSection
            Divider()
            hero
            yearSection
            holidaySection
            Divider()
            clockSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Label("MFish · 摸鱼日历", systemImage: "fish")
                .font(.headline).foregroundStyle(Color.accentColor)
            Spacer()
            if model.refreshing {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var calendarBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Text(String(Calendar.current.component(.day, from: model.now)))
                    .font(.system(size: 40, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                Text(weekday)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 76, height: 76)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(gregorianTitle).font(.caption).foregroundStyle(.secondary)
                Text(model.lunar.monthName + model.lunar.dayName)
                    .font(.title3.bold())
                Text("\(model.lunar.yearGanzhi)年【\(model.lunar.zodiac)】")
                    .font(.callout).foregroundStyle(.secondary)
                Text("\(model.lunar.dayGanzhi)日")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var weekday: String {
        let index = Calendar.current.component(.weekday, from: model.now)
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][index - 1]
    }

    private var gregorianTitle: String {
        let parts = Calendar.current.dateComponents([.year, .month], from: model.now)
        return "\(String(parts.year ?? 0)) 年 \(parts.month ?? 0) 月"
    }

    private var almanacSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(model.almanac.monthBranch)月 · \(model.almanac.officer)日")
                .font(.caption2).foregroundStyle(.secondary)
                .help(model.almanac.basis)
            HStack(alignment: .top, spacing: 12) {
                almanacColumn(title: "宜", items: model.almanac.good, color: .green)
                almanacColumn(title: "忌", items: model.almanac.bad, color: .red)
            }
            Text(model.almanac.motto)
                .font(.caption).foregroundStyle(.secondary).italic()
        }
    }

    private func almanacColumn(title: String, items: [String], color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title).font(.callout.bold()).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items, id: \.self) { Text($0).font(.callout) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.todayIsRestDay {
                Text(model.todayName.map { "\($0) · 摸鱼中" } ?? "周末 · 摸鱼中")
                    .font(.system(size: 26, weight: .bold))
                Text("今天不用上班，尽情摸鱼。")
                    .font(.callout).foregroundStyle(.secondary)
            } else if let countdown = model.restCountdown {
                Text("距下一个休息日").font(.callout).foregroundStyle(.secondary)
                Text(CountdownFormat.compact(countdown.interval))
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                Text("\(FishFormat.day(countdown.target)) · \(countdown.name ?? "周末")")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var yearSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(String(model.yearProgress.year)) 年摸鱼进度")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%.1f%%", model.yearProgress.fraction * 100))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            ProgressView(value: model.yearProgress.fraction)
            Text("第 \(model.yearProgress.dayOfYear) / \(model.yearProgress.totalDays) 天 · 今年还剩 \(model.remainingRestDays) 个休息日\(model.currentYearHasData ? "" : "（未含节假日数据）")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var holidaySection: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    if let holiday = model.nextHoliday {
                        Text("下一个假期：\(holiday.name)").font(.subheadline.weight(.medium))
                        Text("\(FishFormat.shortDay(holiday.start))–\(FishFormat.shortDay(holiday.end)) · 共\(holiday.dayCount)天")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("下一个假期").font(.subheadline.weight(.medium))
                        Text("暂无数据，等待数据源公布")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "calendar")
            }
            Spacer()
            if let holiday = model.nextHoliday {
                Text("还有\(model.daysUntil(holiday))天")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
    }

    private var clockSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日打卡").font(.subheadline.weight(.medium))
                Text(clockSummary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(clockButtonTitle) { model.clockIn() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private var clockSummary: String {
        let clock = model.todayClock
        let start = clock.start.map(FishFormat.time) ?? "--:--"
        let end = clock.end.map(FishFormat.time) ?? "--:--"
        return "上班 \(start) · 下班 \(end)"
    }

    private var clockButtonTitle: String {
        if model.todayClock.start == nil { return "上班打卡" }
        if model.todayClock.end == nil { return "下班打卡" }
        return "更新下班"
    }

    private var footer: some View {
        HStack {
            Button("日历…") { openControl(.calendar) }
            Button("设置…") { openControl(.settings) }
            Spacer()
            Button("退出 MFish") { NSApp.terminate(nil) }
        }
    }

    private func openControl(_ page: ControlPage) {
        model.controlPage = page
        openWindow(id: "control")
        NSApp.activate(ignoringOtherApps: true)
    }
}