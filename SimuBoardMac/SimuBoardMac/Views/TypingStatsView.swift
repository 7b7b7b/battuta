import Charts
import SwiftUI

private enum TypingStatsSection: String, CaseIterable, Identifiable {
    case today = "今日"
    case apps = "应用"
    case history = "历史"
    case keyboard = "键盘"

    var id: Self { self }
}

@MainActor
struct TypingStatsView: View {
    @ObservedObject var model: TypingStatsModel
    @ObservedObject var settings: AppSettings
    @State private var selectedSection: TypingStatsSection = .today
    @State private var showsClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            sectionPicker
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 780, idealWidth: 960, minHeight: 560, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await refreshWhileVisible() }
        .alert("清除全部输入统计？", isPresented: $showsClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                Task { await model.clearAll() }
            }
        } message: {
            Text("今日、历史、应用排行和全部逐键累计都将从本机删除，且无法恢复。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard.badge.clock")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(
                    Color(red: 0.82, green: 1, blue: 0.42),
                    in: RoundedRectangle(cornerRadius: 12)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("输入统计")
                    .font(.title2.weight(.semibold))
                Text("Battuta 本地输入统计")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let snapshot = model.snapshot {
                statusLabel(for: snapshot)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.secondary.opacity(0.08), in: Capsule())
            }

            Button {
                Task { await model.refresh() }
            } label: {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .help("刷新输入统计")
            .accessibilityLabel("刷新输入统计")
            .disabled(model.isRefreshing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var sectionPicker: some View {
        HStack {
            Picker("统计页面", selection: $selectedSection) {
                ForEach(TypingStatsSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Spacer()

            if let snapshot = model.snapshot {
                VStack(alignment: .trailing, spacing: 2) {
                    if let dataDate = snapshot.today.lastUpdatedAt ?? snapshot.lastInputAt {
                        Text("数据截至 \(statsTimestamp(dataDate))")
                    }
                    Text("读取于 \(snapshot.generatedAt.formatted(date: .omitted, time: .standard))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Toggle("记录统计", isOn: $settings.isTypingStatsEnabled)
                .toggleStyle(.switch)
                .help("开启后仅在本机保存聚合统计，不保存输入内容")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.snapshot {
            VStack(spacing: 0) {
                if let message = model.staleDataMessage {
                    refreshWarning(message)
                }
                switch selectedSection {
                case .today:
                    TypingStatsTodayView(snapshot: snapshot)
                case .apps:
                    TypingStatsAppsView(snapshot: snapshot)
                case .history:
                    TypingStatsHistoryView(snapshot: snapshot)
                case .keyboard:
                    TypingStatsKeyboardView(snapshot: snapshot)
                }
            }
        } else {
            switch model.sourceStatus {
            case .checking, .available:
                StatsPlaceholderView(
                    symbol: "chart.xyaxis.line",
                    title: "正在读取统计",
                    message: "正在载入 Battuta 的本地输入统计。",
                    showsProgress: true
                )
            case let .failed(message):
                StatsPlaceholderView(
                    symbol: "exclamationmark.triangle.fill",
                    title: "暂时无法读取统计",
                    message: message,
                    showsProgress: false
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.shield")
            Text("只记录字符键数量、物理键码、时间与前台应用；不保存输入内容。")
            Spacer()
            if model.isClearing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在清除输入统计")
            }
            Button("清除全部统计", role: .destructive) {
                showsClearConfirmation = true
            }
            .buttonStyle(.borderless)
            .disabled(model.isClearing)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    private func refreshWarning(_ message: String) -> some View {
        Label("刷新失败，正在显示上次成功的数据：\(message)", systemImage: "arrow.clockwise.circle")
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background(.orange.opacity(0.08))
    }

    private func statusLabel(for _: TypingStatsSnapshot) -> some View {
        let title: String
        let symbol: String
        let color: Color
        if model.staleDataMessage != nil {
            title = "显示上次数据"
            symbol = "clock.arrow.circlepath"
            color = .orange
        } else if !settings.isTypingStatsEnabled {
            title = "统计已暂停"
            symbol = "pause.circle.fill"
            color = .secondary
        } else {
            title = "本地统计"
            symbol = "chart.bar.fill"
            color = .green
        }
        return Label(title, systemImage: symbol)
            .foregroundStyle(color)
    }

    private func refreshWhileVisible() async {
        await model.refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch is CancellationError {
                return
            } catch {
                return
            }
            await model.refresh()
        }
    }
}

@MainActor
private struct TypingStatsTodayView: View {
    let snapshot: TypingStatsSnapshot

    private var recentTotal: Int64 {
        snapshot.recentBuckets.reduce(0) { $0 + $1.characterCount }
    }

    private var recentPeak: Int64 {
        snapshot.recentBuckets.map(\.characterCount).max() ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)],
                    spacing: 12
                ) {
                    StatsMetricCard(
                        title: "今日字符数",
                        value: statsCount(snapshot.today.characterCount),
                        detail: "按字符键触发估算",
                        symbol: "keyboard",
                        color: .cyan
                    )
                    StatsMetricCard(
                        title: "今日最多应用",
                        value: snapshot.today.topAppName ?? "暂无",
                        detail: snapshot.apps.first.map {
                            "\(statsCount($0.characterCount)) 个字符"
                        } ?? "今天还没有输入",
                        symbol: "app.fill",
                        color: .green
                    )
                    StatsMetricCard(
                        title: "今日峰值速度",
                        value: "\(snapshot.today.peakCPS) 字符/秒",
                        detail: lastInputDescription(snapshot.lastInputAt),
                        symbol: "bolt.fill",
                        color: .yellow
                    )
                    StatsMetricCard(
                        title: "活跃时间",
                        value: statsActiveTime(snapshot.today.activeSeconds),
                        detail: "分布在 \(snapshot.today.activeMinuteBuckets) 个输入分钟",
                        symbol: "clock",
                        color: .mint
                    )
                }

                GroupBox("最近 10 分钟") {
                    VStack(alignment: .leading, spacing: 8) {
                        Chart(snapshot.recentBuckets) { bucket in
                            AreaMark(
                                x: .value("时间", bucket.start),
                                y: .value("字符数", bucket.characterCount)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green.opacity(0.36), .green.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.linear)

                            LineMark(
                                x: .value("时间", bucket.start),
                                y: .value("字符数", bucket.characterCount)
                            )
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.linear)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .minute, count: 2)) {
                                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                                AxisValueLabel(format: .dateTime.hour().minute())
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) {
                                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                                AxisValueLabel()
                            }
                        }
                        .frame(minHeight: 210)
                        .accessibilityLabel("最近十分钟字符数曲线")
                        .accessibilityValue("合计 \(recentTotal) 个字符，单个区间峰值 \(recentPeak) 个字符")

                        Text("每 10 秒汇总一次；空白区间表示没有有效输入。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 5)
                }
            }
            .padding(20)
        }
    }
}

@MainActor
private struct TypingStatsAppsView: View {
    let snapshot: TypingStatsSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今日应用排行")
                            .font(.headline)
                        Text("按字符数排序，仅展示聚合结果。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(snapshot.apps.count == 20 ? "显示前 20 个应用" : "显示 \(snapshot.apps.count) 个应用")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if snapshot.apps.isEmpty {
                    StatsPlaceholderView(
                        symbol: "app.dashed",
                        title: "今天还没有应用统计",
                        message: "开始输入后，应用排行会显示在这里。",
                        showsProgress: false
                    )
                    .frame(minHeight: 300)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(snapshot.apps.enumerated()), id: \.element.id) { index, app in
                            TypingAppRow(
                                rank: index + 1,
                                app: app,
                                total: max(snapshot.today.characterCount, 1)
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

@MainActor
private struct TypingStatsHistoryView: View {
    let snapshot: TypingStatsSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 12)],
                    spacing: 12
                ) {
                    StatsMetricCard(
                        title: "14 天总计",
                        value: statsCount(snapshot.fourteenDayTotal),
                        detail: "\(snapshot.activeDayCount) 个活跃日",
                        symbol: "calendar",
                        color: .cyan
                    )
                    StatsMetricCard(
                        title: "日均字符数",
                        value: statsCount(snapshot.fourteenDayAverage),
                        detail: "包含没有输入的日期",
                        symbol: "chart.bar.xaxis",
                        color: .green
                    )
                    StatsMetricCard(
                        title: "最佳一天",
                        value: snapshot.bestDay.map { statsCount($0.characterCount) } ?? "—",
                        detail: snapshot.bestDay.map {
                            $0.date.formatted(.dateTime.month().day())
                        } ?? "暂无数据",
                        symbol: "trophy.fill",
                        color: .yellow
                    )
                }

                GroupBox("最近 14 天") {
                    Chart(snapshot.history) { day in
                        BarMark(
                            x: .value("日期", day.date, unit: .day),
                            y: .value("字符数", day.characterCount)
                        )
                        .foregroundStyle(
                            day.dateKey == snapshot.today.dateKey
                                ? Color.green
                                : Color.cyan.opacity(0.72)
                        )
                        .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) {
                            AxisGridLine().foregroundStyle(.secondary.opacity(0.10))
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                            AxisValueLabel()
                        }
                    }
                    .frame(minHeight: 235)
                    .padding(.top, 5)
                    .accessibilityLabel("最近十四天字符数柱状图")
                    .accessibilityValue("总计 \(snapshot.fourteenDayTotal) 个字符")
                }

                LazyVStack(spacing: 6) {
                    ForEach(snapshot.history.reversed()) { day in
                        HStack(spacing: 12) {
                            Text(day.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                                .frame(width: 86, alignment: .leading)
                            Text(statsCount(day.characterCount))
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .frame(width: 90, alignment: .trailing)
                            Text(statsActiveTime(day.activeSeconds))
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .trailing)
                            Text(day.topAppName ?? "—")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("峰值 \(day.peakCPS) 字符/秒")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.date.formatted(.dateTime.month().day().weekday(.wide)))
                        .accessibilityValue(
                            "\(day.characterCount) 个字符，活跃 \(statsActiveTime(day.activeSeconds))，"
                                + "最多在 \(day.topAppName ?? "未知应用")，峰值 \(day.peakCPS) 字符每秒"
                        )
                    }
                }
            }
            .padding(20)
        }
    }
}

@MainActor
private struct StatsMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.18)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)，\(detail)")
    }
}

@MainActor
private struct TypingAppRow: View {
    let rank: Int
    let app: TypingAppSummary
    let total: Int64

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(rank <= 3 ? Color.green : Color.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(app.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if let bundleIdentifier = app.bundleIdentifier {
                        Text(bundleIdentifier)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(statsCount(app.characterCount))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }

                ProgressView(value: Double(app.characterCount), total: Double(total))
                    .tint(.green)

                HStack {
                    Text(statsPercent(app.characterCount, total: total))
                    Text("活跃 \(statsActiveTime(app.activeSeconds))")
                    Spacer()
                    Text("峰值 \(app.peakCPS) 字符/秒")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(rank) 名，\(app.displayName)")
        .accessibilityValue(
            "\(app.characterCount) 个字符，占比 \(statsPercent(app.characterCount, total: total))，"
                + "活跃 \(statsActiveTime(app.activeSeconds))，峰值 \(app.peakCPS) 字符每秒"
        )
    }
}

@MainActor
private struct StatsPlaceholderView: View {
    let symbol: String
    let title: String
    let message: String
    let showsProgress: Bool

    var body: some View {
        VStack(spacing: 13) {
            if showsProgress {
                ProgressView()
                    .controlSize(.regular)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func statsCount(_ value: Int64) -> String {
    value.formatted(.number.grouping(.automatic))
}

func statsActiveTime(_ seconds: Int64) -> String {
    if seconds >= 3_600 {
        return "\(seconds / 3_600) 小时 \((seconds % 3_600) / 60) 分"
    }
    if seconds >= 60 {
        return "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
    return "\(seconds) 秒"
}

func statsPercent(_ value: Int64, total: Int64) -> String {
    guard total > 0 else { return "0%" }
    let percent = Double(value) * 100 / Double(total)
    return percent.formatted(.number.precision(.fractionLength(percent < 10 ? 1 : 0))) + "%"
}

func lastInputDescription(_ date: Date?) -> String {
    guard let date else { return "还没有输入记录" }
    if Calendar.current.isDateInToday(date) {
        return "最近输入 \(date.formatted(date: .omitted, time: .shortened))"
    }
    return "最近输入 \(date.formatted(.dateTime.month().day().hour().minute()))"
}

func statsTimestamp(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) {
        return date.formatted(date: .omitted, time: .standard)
    }
    return date.formatted(.dateTime.month().day().hour().minute().second())
}
