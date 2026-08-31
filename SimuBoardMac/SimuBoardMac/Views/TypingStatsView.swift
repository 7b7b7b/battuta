import Charts
import SwiftUI

private enum TypingStatsSection: String, CaseIterable, Identifiable, Hashable {
    case today = "今日"
    case history = "历史"
    case keyboard = "键盘"

    var id: Self { self }
}

private struct TypingStatsRefreshTask: Hashable {
    let section: TypingStatsSection
    let timelineRange: TypingTimelineRange
    let isRecordingEnabled: Bool
}

@MainActor
struct TypingStatsView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var model: TypingStatsModel
    @ObservedObject var settings: AppSettings
    @State private var selectedSection: TypingStatsSection = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--stats-history") {
            return .history
        }
        if ProcessInfo.processInfo.arguments.contains("--stats-keyboard") {
            return .keyboard
        }
        #endif
        return .today
    }()
    @State private var showsClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
            footer
        }
        // Recreate only the rendered subtree when the app language changes.
        // State owned by TypingStatsView (such as the selected tab) remains
        // intact, while cached formatters, pickers and heatmap labels refresh.
        .id(locale.identifier)
        .frame(minWidth: 820, idealWidth: 1_040, minHeight: 600, idealHeight: 760)
        .battutaWindowGlass()
        .tint(BattutaVisualStyle.actionAccent)
        .task(
            id: TypingStatsRefreshTask(
                section: selectedSection,
                timelineRange: model.timelineRange,
                isRecordingEnabled: settings.isTypingStatsEnabled
            )
        ) {
            await refreshWhileVisible(
                section: selectedSection,
                range: model.timelineRange
            )
        }
        .alert("清除全部输入统计？", isPresented: $showsClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                Task { await model.clearAll() }
            }
        } message: {
            Text("今日、历史、应用排行和全部逐键累计都将从本机删除，且无法恢复。")
        }
    }

    private var topBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                BattutaIconTile(
                    symbol: "chart.bar.xaxis",
                    tint: BattutaVisualStyle.accentStrong,
                    size: 42,
                    symbolSize: 18
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("输入统计")
                        .font(.title2.weight(.semibold))
                    Text("清晰了解每天的输入习惯")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.snapshot != nil {
                    let presentation = statusPresentation
                    BattutaStatusPill(
                        title: presentation.title,
                        symbol: presentation.symbol,
                        tint: presentation.color
                    )
                }

                Toggle("记录统计", isOn: $settings.isTypingStatsEnabled)
                    .toggleStyle(.switch)
                    .help("开启后仅在本机保存聚合统计，不保存输入内容")

                Button {
                    Task {
                        await model.refresh(
                            for: refreshTarget(for: selectedSection),
                            showsActivity: true,
                            publishesUnchangedSnapshot: true
                        )
                        if selectedSection == .history {
                            await model.refreshCurrentReport()
                        }
                    }
                } label: {
                    if model.isRefreshing || model.isLoadingReport {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .help("刷新输入统计")
                .accessibilityLabel("刷新输入统计")
                .disabled(model.isRefreshing || model.isLoadingReport)
            }

            HStack(spacing: 16) {
                Picker("统计页面", selection: $selectedSection) {
                    ForEach(TypingStatsSection.allCases) { section in
                        Text(L10n.tr(section.rawValue)).tag(section)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

                if let snapshot = model.snapshot {
                    TypingStatsDataFreshnessView(
                        readStatus: model.readStatus,
                        dataDate: snapshot.today.lastUpdatedAt ?? snapshot.lastInputAt,
                        fallbackReadDate: snapshot.generatedAt
                    )
                }
            }
        }
        .padding(.horizontal, BattutaVisualStyle.pagePadding)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            BattutaVisualStyle.separator.opacity(0.65).frame(height: 1)
        }
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
                    TypingStatsOverviewView(
                        snapshot: snapshot,
                        selectedRange: model.timelineRange,
                        onSelectRange: { model.selectTimelineRange($0) }
                    )
                case .history:
                    TypingStatsHistoryView(model: model)
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
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(BattutaVisualStyle.accentStrong)
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
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            BattutaVisualStyle.separator.opacity(0.65).frame(height: 1)
        }
    }

    private func refreshWarning(_ message: String) -> some View {
        Label(
            L10n.format("刷新失败，正在显示上次成功的数据：%@", message),
            systemImage: "arrow.clockwise.circle"
        )
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background {
                ZStack {
                    BattutaVisualStyle.surface
                    Color.orange.opacity(0.08)
                }
            }
    }

    private var statusPresentation: (title: String, symbol: String, color: Color) {
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
            color = BattutaVisualStyle.accentStrong
        }
        return (title, symbol, color)
    }

    private func refreshWhileVisible(
        section: TypingStatsSection,
        range: TypingTimelineRange
    ) async {
        await model.refresh(for: refreshTarget(for: section))
        // The history page owns its one-off annual report refresh. Keeping the
        // today-page polling loop alive here needlessly rebuilt the full 365-day
        // chart every few seconds while the user was reading or scrolling it.
        guard section != .history, settings.isTypingStatsEnabled else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(
                    for: .seconds(refreshInterval(for: section, range: range)),
                    tolerance: .milliseconds(750)
                )
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard settings.isTypingStatsEnabled,
                  selectedSection == section,
                  model.timelineRange == range else {
                return
            }
            await model.refresh(for: refreshTarget(for: section))
        }
    }

    private func refreshInterval(
        for section: TypingStatsSection,
        range: TypingTimelineRange
    ) -> Double {
        switch section {
        case .today:
            return range.refreshIntervalSeconds
        case .history:
            return max(60, range.refreshIntervalSeconds)
        case .keyboard:
            return max(15, range.refreshIntervalSeconds)
        }
    }

    private func refreshTarget(for section: TypingStatsSection) -> TypingStatsRefreshTarget {
        switch section {
        case .today:
            .overview
        case .history:
            .history
        case .keyboard:
            .keyboard
        }
    }
}

@MainActor
private struct TypingStatsDataFreshnessView: View {
    @ObservedObject var readStatus: TypingStatsReadStatus
    let dataDate: Date?
    let fallbackReadDate: Date

    var body: some View {
        HStack(spacing: 12) {
            if let dataDate {
                Label(
                    L10n.format("数据截至 %@", statsTimestamp(dataDate)),
                    systemImage: "clock"
                )
            }
            Text(
                L10n.format(
                    "读取于 %@",
                    (readStatus.lastReadAt ?? fallbackReadDate).formatted(
                        .dateTime.hour().minute().second().locale(L10n.locale)
                    )
                )
            )
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
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
                StatsInstrumentCard(
                    title: "今日输入",
                    symbol: "keyboard",
                    value: statsCount(snapshot.today.characterCount),
                    unit: "个字符",
                    valueDetail: "按字符键触发估算",
                    cornerMetric: StatsInstrumentMetric(
                        title: "今日峰值",
                        value: L10n.format("%@ 字/秒", statsCount(snapshot.today.peakCPS))
                    ),
                    metrics: [
                        StatsInstrumentMetric(
                            title: "最多应用",
                            value: snapshot.today.topAppName ?? L10n.tr("暂无"),
                            detail: snapshot.apps.first.map {
                                L10n.format("%@ 个字符", statsCount($0.characterCount))
                            } ?? L10n.tr("今天还没有输入")
                        ),
                        StatsInstrumentMetric(
                            title: "活跃时间",
                            value: statsActiveTime(snapshot.today.activeSeconds),
                            detail: L10n.format(
                                "%@ 个输入分钟",
                                "\(snapshot.today.activeMinuteBuckets)"
                            )
                        ),
                        StatsInstrumentMetric(
                            title: "空格键",
                            value: L10n.format(
                                "%@ 次",
                                statsCount(snapshot.todayKeyCounts[49, default: 0])
                            ),
                            detail: "不含长按连发"
                        ),
                    ],
                    accessibilityValue: L10n.format(
                        "今日 %@ 个字符，最多应用 %@，峰值 %@ 字符每秒，活跃 %@，空格键 %@ 次",
                        statsCount(snapshot.today.characterCount),
                        snapshot.today.topAppName ?? L10n.tr("暂无"),
                        statsCount(snapshot.today.peakCPS),
                        statsActiveTime(snapshot.today.activeSeconds),
                        statsCount(snapshot.todayKeyCounts[49, default: 0])
                    )
                )

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        BattutaSectionHeading(
                            "最近 10 分钟",
                            subtitle: "每 10 秒聚合一次本地输入",
                            symbol: "waveform.path.ecg"
                        )
                        Spacer()
                        HStack(spacing: 14) {
                            chartSummary("合计", value: statsCount(recentTotal))
                            chartSummary("区间峰值", value: statsCount(recentPeak))
                        }
                    }

                    if recentTotal == 0 {
                        HStack(spacing: 12) {
                            Image(systemName: "keyboard")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(BattutaVisualStyle.accentStrong)
                                .frame(width: 32, height: 32)
                                .background(BattutaVisualStyle.accentSoft, in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text("这一时段还没有输入")
                                    .font(.subheadline.weight(.semibold))
                                Text("开始打字后，趋势会立即出现在这里。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    } else {
                        Chart(snapshot.recentBuckets) { bucket in
                            AreaMark(
                                x: .value("时间", bucket.start),
                                y: .value("字符数", bucket.characterCount)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        BattutaVisualStyle.accent.opacity(0.34),
                                        BattutaVisualStyle.accent.opacity(0.015),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.linear)

                            LineMark(
                                x: .value("时间", bucket.start),
                                y: .value("字符数", bucket.characterCount)
                            )
                            .foregroundStyle(BattutaVisualStyle.accentStrong)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.linear)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .minute, count: 2)) {
                                AxisGridLine().foregroundStyle(.secondary.opacity(0.10))
                                AxisValueLabel(format: .dateTime.hour().minute())
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) {
                                AxisGridLine().foregroundStyle(.secondary.opacity(0.10))
                                AxisValueLabel()
                            }
                        }
                        .frame(minHeight: 235)
                        .accessibilityLabel(L10n.tr("最近十分钟字符数曲线"))
                        .accessibilityValue(
                            L10n.format(
                                "合计 %@ 个字符，单个区间峰值 %@ 个字符",
                                statsCount(recentTotal),
                                statsCount(recentPeak)
                            )
                        )

                        Text("空白区间表示没有有效输入。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(BattutaVisualStyle.cardPadding)
                .battutaPanel()
            }
            .padding(20)
            .frame(maxWidth: 1_080)
            .frame(maxWidth: .infinity)
        }
    }

    private func chartSummary(_ title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(L10n.tr(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
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
                    Text(
                        snapshot.apps.count == 20
                            ? L10n.tr("显示前 20 个应用")
                            : L10n.format("显示 %@ 个应用", "\(snapshot.apps.count)")
                    )
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
                    LazyVStack(spacing: 0) {
                        ForEach(Array(snapshot.apps.enumerated()), id: \.element.id) { index, app in
                            TypingAppRow(
                                rank: index + 1,
                                app: app,
                                total: max(snapshot.today.characterCount, 1)
                            )
                            if index < snapshot.apps.count - 1 {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .battutaPanel()
                }
            }
            .padding(20)
            .frame(maxWidth: 1_080)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct StatsInstrumentMetric: Identifiable {
    let title: String
    let value: String
    var detail: String? = nil

    var id: String { title }
}

@MainActor
private struct StatsInstrumentCard: View {
    let title: String
    let symbol: String
    let value: String
    let unit: String
    let valueDetail: String
    let cornerMetric: StatsInstrumentMetric
    let metrics: [StatsInstrumentMetric]
    let accessibilityValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Label(L10n.tr(title), systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BattutaVisualStyle.instrumentPrimary)
                    .labelStyle(.titleAndIcon)

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(cornerMetric.value)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(BattutaVisualStyle.instrumentPrimary)
                        .monospacedDigit()
                    Text(L10n.tr(cornerMetric.title))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                }
            }

            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(value)
                            .font(.system(size: 50, weight: .bold, design: .rounded))
                            .foregroundStyle(BattutaVisualStyle.instrumentPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                        Text(L10n.tr(unit))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                    }

                    Text(L10n.tr(valueDetail))
                        .font(.caption2)
                        .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                }
                .frame(minWidth: 220, alignment: .leading)
                .layoutPriority(1)

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                        if index > 0 {
                            Rectangle()
                                .fill(BattutaVisualStyle.instrumentSeparator)
                                .frame(width: 1, height: 44)
                                .padding(.horizontal, 14)
                                .accessibilityHidden(true)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.tr(metric.title))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                            Text(metric.value)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BattutaVisualStyle.instrumentPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.72)
                                .help(metric.value)
                            if let detail = metric.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .minimumScaleFactor(0.78)
                                    .help(detail)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            BattutaVisualStyle.instrumentSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BattutaVisualStyle.instrumentStroke, lineWidth: 1)
        }
        .shadow(color: BattutaVisualStyle.panelShadow, radius: 12, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr(title))
        .accessibilityValue(accessibilityValue)
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
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(rank <= 3 ? BattutaVisualStyle.accentStrong : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    (rank <= 3 ? BattutaVisualStyle.accentSoft : Color.secondary.opacity(0.08)),
                    in: Circle()
                )

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
                    .tint(BattutaVisualStyle.accentStrong)

                HStack {
                    Text(statsPercent(app.characterCount, total: total))
                    Text(L10n.format("活跃 %@", statsActiveTime(app.activeSeconds)))
                    Spacer()
                    Text(L10n.format("峰值 %@ 字符/秒", statsCount(app.peakCPS)))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.format("第 %@ 名，%@", "\(rank)", app.displayName)
        )
        .accessibilityValue(
            L10n.format(
                "%@ 个字符，占比 %@，活跃 %@，峰值 %@ 字符每秒",
                statsCount(app.characterCount),
                statsPercent(app.characterCount, total: total),
                statsActiveTime(app.activeSeconds),
                statsCount(app.peakCPS)
            )
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
                BattutaIconTile(symbol: symbol, tint: .secondary, size: 48, symbolSize: 21)
            }
            Text(L10n.tr(title))
                .font(.headline)
            Text(L10n.tr(message))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

func statsCount(_ value: Int64) -> String {
    value.formatted(.number.grouping(.automatic).locale(L10n.locale))
}

func statsPrefersChineseUI(locale: Locale = L10n.locale) -> Bool {
    if let languageCode = locale.language.languageCode?.identifier {
        return languageCode.hasPrefix("zh")
    }
    return locale.identifier.lowercased().hasPrefix("zh")
}

func statsActiveTime(_ seconds: Int64) -> String {
    if seconds >= 3_600 {
        return L10n.format(
            "%@ 小时 %@ 分",
            "\(seconds / 3_600)",
            "\((seconds % 3_600) / 60)"
        )
    }
    if seconds >= 60 {
        return L10n.format("%@ 分 %@ 秒", "\(seconds / 60)", "\(seconds % 60)")
    }
    return L10n.format("%@ 秒", "\(seconds)")
}

func statsPercent(_ value: Int64, total: Int64) -> String {
    guard total > 0 else { return "0%" }
    let percent = Double(value) * 100 / Double(total)
    return percent.formatted(
        .number
            .precision(.fractionLength(percent < 10 ? 1 : 0))
            .locale(L10n.locale)
    ) + "%"
}

func lastInputDescription(_ date: Date?) -> String {
    guard let date else { return L10n.tr("还没有输入记录") }
    if Calendar.current.isDateInToday(date) {
        return L10n.format(
            "最近输入 %@",
            date.formatted(.dateTime.hour().minute().locale(L10n.locale))
        )
    }
    return L10n.format(
        "最近输入 %@",
        date.formatted(.dateTime.month().day().hour().minute().locale(L10n.locale))
    )
}

func statsTimestamp(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) {
        return date.formatted(.dateTime.hour().minute().second().locale(L10n.locale))
    }
    return date.formatted(
        .dateTime.month().day().hour().minute().second().locale(L10n.locale)
    )
}
