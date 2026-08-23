import AppKit
import SwiftUI

private struct TypingReportRequest: Hashable {
    let startDate: Date
    let endDate: Date
    let comparisonStartDate: Date?
    let comparisonEndDate: Date?
}

private enum TypingRhythmMode: String, CaseIterable, Identifiable {
    case current = "当前"
    case difference = "差异"

    var id: Self { self }
}

private enum TypingApplicationTableMetrics {
    static let spacing: CGFloat = 8
    static let valueWidth: CGFloat = 56
    static let changeWidth: CGFloat = 104
}

@MainActor
struct TypingStatsHistoryView: View {
    @ObservedObject var model: TypingStatsModel

    @State private var rhythmMode: TypingRhythmMode = .difference
    @State private var showsAllApplicationsSheet = false

    private static var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    private static var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var calendar: Calendar { Self.calendar }
    private var today: Date { Self.today }

    private var selectedRange: TypingDateRange {
        let start = calendar.date(byAdding: .day, value: -364, to: today) ?? today
        return TypingDateRange(startDate: start, endDate: today)
    }

    private var comparisonRange: TypingDateRange {
        let end = calendar.date(byAdding: .day, value: -1, to: selectedRange.startDate)
            ?? selectedRange.startDate
        let start = calendar.date(byAdding: .day, value: -364, to: end) ?? end
        return TypingDateRange(startDate: start, endDate: end)
    }

    private var request: TypingReportRequest {
        TypingReportRequest(
            startDate: selectedRange.startDate,
            endDate: selectedRange.endDate,
            comparisonStartDate: comparisonRange.startDate,
            comparisonEndDate: comparisonRange.endDate
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let heatmapMetrics = heatmapMetrics(for: geometry.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage = model.reportErrorMessage {
                        reportError(errorMessage)
                    }

                    if let report = model.reportSnapshot {
                        reportContent(report, heatmapMetrics: heatmapMetrics)
                            .opacity(model.isLoadingReport ? 0.62 : 1)
                            .overlay {
                                if model.isLoadingReport {
                                    ProgressView("正在更新年度统计…")
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(.regularMaterial, in: Capsule())
                                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                                }
                            }
                            .animation(.easeOut(duration: 0.18), value: model.isLoadingReport)
                    } else if model.isLoadingReport {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("正在整理过去一年的统计")
                                .font(.subheadline.weight(.medium))
                            Text("首次读取较长日期区间时可能需要一点时间。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        emptyReport
                    }
                }
                .padding(20)
                .frame(maxWidth: 1_080)
                .frame(maxWidth: .infinity)
            }
        }
        .task(id: request) {
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch is CancellationError {
                return
            } catch {
                return
            }
            await model.loadReport(
                range: selectedRange,
                comparisonRange: comparisonRange
            )
        }
        .sheet(isPresented: $showsAllApplicationsSheet) {
            if let report = model.reportSnapshot {
                allApplicationsSheet(report)
            }
        }
    }

    @ViewBuilder
    private func reportContent(
        _ report: TypingRangeReportSnapshot,
        heatmapMetrics: TypingHeatmapCellMetrics
    ) -> some View {
        let topPanelHeight = 144 + heatmapMetrics.cellSize * 7

        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    rhythmChanges(
                        report,
                        heatmapMetrics: heatmapMetrics,
                        panelHeight: topPanelHeight
                    )
                        .frame(minWidth: 530, maxWidth: .infinity, alignment: .topLeading)
                    applicationChanges(report, panelHeight: topPanelHeight)
                        .frame(minWidth: 400, maxWidth: 470, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 16) {
                    rhythmChanges(
                        report,
                        heatmapMetrics: heatmapMetrics,
                        panelHeight: topPanelHeight
                    )
                    applicationChanges(report, panelHeight: topPanelHeight)
                }
            }

            TypingYearHeatmap(
                range: report.range,
                days: report.days,
                calendar: calendar,
                metrics: heatmapMetrics
            )
            .padding(16)
            .historyInstrumentPanel()

            insights(report)
        }
    }

    private func heatmapMetrics(for viewportWidth: CGFloat) -> TypingHeatmapCellMetrics {
        let contentWidth = min(1_080, max(0, viewportWidth)) - 40
        let panelContentWidth = max(0, contentWidth - 32)
        let fixedWidth = TypingHeatmapCellMetrics.axisWidth
            + TypingHeatmapCellMetrics.spacing
            + CGFloat(52) * TypingHeatmapCellMetrics.spacing
        let fittedCellSize = (panelContentWidth - fixedWidth) / 53
        let cellSize = min(14, max(10, floor(fittedCellSize * 2) / 2))
        return TypingHeatmapCellMetrics(
            cellSize: cellSize,
            spacing: TypingHeatmapCellMetrics.spacing
        )
    }

    private func reportOverviewStrip(_ report: TypingRangeReportSnapshot) -> some View {
        HStack(spacing: 0) {
            overviewMetric(
                symbol: "keyboard.fill",
                title: "区间总计",
                value: statsCount(report.metrics.characterCount),
                detail: "\(report.metrics.calendarDayCount) 个自然日"
            )

            overviewSeparator

            let delta = changePresentation(
                current: report.metrics.characterCount,
                previous: report.comparisonMetrics?.characterCount ?? 0
            )
            overviewMetric(
                symbol: delta.symbol,
                title: report.comparisonMetrics == nil ? "区间变化" : "相比上期",
                value: report.comparisonMetrics == nil ? "未对比" : delta.text,
                detail: report.comparisonRange.map(dateRangeText) ?? "开启区间对比",
                tint: report.comparisonMetrics == nil ? BattutaVisualStyle.instrumentSecondary : delta.color
            )

            overviewSeparator

            overviewMetric(
                symbol: "chart.bar.fill",
                title: "日均字符",
                value: formattedAverage(report.metrics.dailyAverage),
                detail: "\(report.metrics.activeDayCount) 个活跃日"
            )

            overviewSeparator

            overviewMetric(
                symbol: "bolt.fill",
                title: "区间峰值",
                value: "\(report.metrics.peakCPS) 字/秒",
                detail: report.metrics.bestDay.map { "最佳日 \(shortDate($0.date))" } ?? "暂无输入"
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .historyInstrumentPanel()
        .accessibilityElement(children: .contain)
    }

    private func overviewMetric(
        symbol: String,
        title: String,
        value: String,
        detail: String,
        tint: Color = BattutaVisualStyle.accent
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BattutaVisualStyle.instrumentPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private var overviewSeparator: some View {
        Rectangle()
            .fill(BattutaVisualStyle.instrumentSeparator)
            .frame(width: 1, height: 50)
            .accessibilityHidden(true)
    }

    private func rhythmChanges(
        _ report: TypingRangeReportSnapshot,
        heatmapMetrics: TypingHeatmapCellMetrics,
        panelHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("输入节律变化")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BattutaVisualStyle.instrumentPrimary)

                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                    .help("把过去 365 天按星期和小时聚合；差异模式与此前 365 天比较。")

                Spacer(minLength: 8)

                Picker(
                    "节律显示方式",
                    selection: Binding(
                        get: { report.comparisonRange == nil ? .current : rhythmMode },
                        set: { rhythmMode = $0 }
                    )
                ) {
                    ForEach(TypingRhythmMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 126)
                .disabled(report.comparisonRange == nil)
            }

            TypingWeekdayHourHeatmap(
                values: report.weekdayHourDistribution,
                mode: report.comparisonRange == nil ? .current : rhythmMode,
                currentWeekdayOccurrences: weekdayOccurrences(in: report.range),
                comparisonWeekdayOccurrences: report.comparisonRange.map {
                    weekdayOccurrences(in: $0)
                } ?? [:],
                metrics: heatmapMetrics
            )

            rhythmLegend(hasComparison: report.comparisonRange != nil)
        }
        .padding(16)
        .frame(height: panelHeight, alignment: .top)
        .historyInstrumentPanel()
    }

    private func rhythmLegend(hasComparison: Bool) -> some View {
        HStack(spacing: 24) {
            if hasComparison && rhythmMode == .difference {
                instrumentLegend(color: BattutaVisualStyle.accent, title: "增加（较上期）")
                instrumentLegend(color: BattutaVisualStyle.instrumentSecondary, title: "基本持平", usesDot: true)
                instrumentLegend(color: BattutaVisualStyle.cyan, title: "减少（较上期）")
            } else {
                instrumentLegend(color: BattutaVisualStyle.accent, title: "输入越多颜色越亮")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func instrumentLegend(
        color: Color,
        title: String,
        usesDot: Bool = false
    ) -> some View {
        HStack(spacing: 7) {
            if usesDot {
                Circle().fill(color).frame(width: 4, height: 4)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 13, height: 13)
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
        }
    }

    private func reportSummary(_ report: TypingRangeReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                BattutaCardLabel(title: "区间概览", symbol: "sum")
                Spacer()
                comparisonBadge(report)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(statsCount(report.metrics.characterCount))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text("个字符")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            summaryRow("日均", value: formattedAverage(report.metrics.dailyAverage))
            summaryRow("活跃日期", value: "\(report.metrics.activeDayCount) 天")
            summaryRow("区间峰值", value: "\(report.metrics.peakCPS) 字/秒")
            if let comparison = report.comparisonMetrics {
                summaryRow("对比区间", value: statsCount(comparison.characterCount))
            }

            if !report.coverage.isRangeWithinAvailableDates,
               let firstDate = report.coverage.firstRecordedDate {
                Label(
                    "本机从 \(shortDate(firstDate)) 起有可用记录",
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BattutaVisualStyle.cardPadding)
        .battutaTintedPanel(BattutaVisualStyle.accentStrong, opacity: 0.055)
    }

    @ViewBuilder
    private func comparisonBadge(_ report: TypingRangeReportSnapshot) -> some View {
        if let comparison = report.comparisonMetrics {
            let presentation = changePresentation(
                current: report.metrics.characterCount,
                previous: comparison.characterCount
            )
            Label(presentation.text, systemImage: presentation.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(presentation.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(presentation.color.opacity(0.10), in: Capsule())
                .help("与 \(dateRangeText(report.comparisonRange)) 相比")
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func applicationChanges(
        _ report: TypingRangeReportSnapshot,
        panelHeight: CGFloat
    ) -> some View {
        let hasComparison = report.comparisonRange != nil

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("应用变化")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BattutaVisualStyle.instrumentPrimary)

                Spacer(minLength: 8)

                Text("\(report.applications.count) 个应用")
                    .font(.caption)
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
            }

            if report.applications.isEmpty {
                Label("所选区间没有可显示的应用记录", systemImage: "app.dashed")
                    .font(.caption)
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                applicationTableHeader(hasComparison: hasComparison)
                    .padding(.bottom, 8)

                Rectangle()
                    .fill(BattutaVisualStyle.instrumentSeparator)
                    .frame(height: 1)

                ScrollView(.vertical) {
                    applicationTableRows(
                        report.applications,
                        hasComparison: hasComparison
                    )
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(height: panelHeight, alignment: .top)
        .historyInstrumentPanel()
    }

    private func applicationTable(
        _ report: TypingRangeReportSnapshot,
        applications: [TypingRangeApplicationSummary]
    ) -> some View {
        let hasComparison = report.comparisonRange != nil

        return VStack(spacing: 0) {
            applicationTableHeader(hasComparison: hasComparison)
            .padding(.bottom, 8)

            Rectangle()
                .fill(BattutaVisualStyle.instrumentSeparator)
                .frame(height: 1)

            applicationTableRows(applications, hasComparison: hasComparison)
        }
        .frame(maxWidth: .infinity)
    }

    private func applicationTableRows(
        _ applications: [TypingRangeApplicationSummary],
        hasComparison: Bool
    ) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(applications) { app in
                applicationTableRow(app, hasComparison: hasComparison)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(app.application.displayName)
                    .accessibilityValue(
                        applicationAccessibilityValue(app, hasComparison: hasComparison)
                    )

                Rectangle()
                    .fill(BattutaVisualStyle.instrumentSeparator)
                    .frame(height: 1)
            }
        }
    }

    private func applicationTableHeader(hasComparison: Bool) -> some View {
        HStack(spacing: TypingApplicationTableMetrics.spacing) {
            tableHeader("应用")
                .frame(maxWidth: .infinity, alignment: .leading)

            tableHeader("当前")
                .frame(width: TypingApplicationTableMetrics.valueWidth, alignment: .trailing)

            tableHeader(hasComparison ? "上期" : "占比")
                .frame(width: TypingApplicationTableMetrics.valueWidth, alignment: .trailing)

            if hasComparison {
                tableHeader("变化")
                    .frame(width: TypingApplicationTableMetrics.changeWidth, alignment: .trailing)
            }
        }
    }

    private func applicationTableRow(
        _ app: TypingRangeApplicationSummary,
        hasComparison: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TypingApplicationTableMetrics.spacing) {
            HStack(spacing: 8) {
                TypingReportApplicationIcon(application: app.application)
                Text(app.application.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BattutaVisualStyle.instrumentPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            tableValue(statsCount(app.characterCount))
                .frame(width: TypingApplicationTableMetrics.valueWidth, alignment: .trailing)

            tableValue(
                hasComparison
                    ? statsCount(app.comparisonCharacterCount)
                    : percentText(app.share)
            )
            .frame(width: TypingApplicationTableMetrics.valueWidth, alignment: .trailing)

            if hasComparison {
                applicationDelta(app, hasComparison: true)
                    .frame(width: TypingApplicationTableMetrics.changeWidth, alignment: .trailing)
            }
        }
    }

    private func allApplicationsSheet(_ report: TypingRangeReportSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("全部应用")
                        .font(.title2.weight(.semibold))
                    Text("\(dateRangeText(report.range)) · 共 \(report.applications.count) 个应用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") {
                    showsAllApplicationsSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                applicationTable(report, applications: report.applications)
                    .padding(20)
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 480, idealHeight: 560)
    }

    private func tableHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
            .lineLimit(1)
    }

    private func tableValue(_ value: String) -> some View {
        Text(value)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(BattutaVisualStyle.instrumentPrimary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.66)
    }

    private func applicationDelta(
        _ app: TypingRangeApplicationSummary,
        hasComparison: Bool
    ) -> some View {
        let presentation = applicationChangePresentation(app, hasComparison: hasComparison)
        return Text(presentation.text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(presentation.color)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.68)
    }

    private func applicationChangePresentation(
        _ app: TypingRangeApplicationSummary,
        hasComparison: Bool
    ) -> (text: String, color: Color) {
        guard hasComparison else { return ("—", BattutaVisualStyle.instrumentSecondary) }
        if app.comparisonCharacterCount == 0 {
            return app.characterCount > 0
                ? ("新增", BattutaVisualStyle.accent)
                : ("持平", BattutaVisualStyle.instrumentSecondary)
        }

        let count = app.characterChange
        let percent = abs(Double(count) / Double(app.comparisonCharacterCount) * 100)
            .formatted(.number.precision(.fractionLength(1)))
        if count > 0 {
            return ("+\(statsCount(count))  ↑ \(percent)%", BattutaVisualStyle.accent)
        }
        if count < 0 {
            return ("−\(statsCount(abs(count)))  ↓ \(percent)%", Color(red: 0.96, green: 0.38, blue: 0.35))
        }
        return ("持平", BattutaVisualStyle.instrumentSecondary)
    }

    private func insights(_ report: TypingRangeReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("年度亮点")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BattutaVisualStyle.instrumentPrimary)
                Text("过去 365 天的高峰与输入习惯")
                    .font(.caption)
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                insight(
                    symbol: "trophy.fill",
                    tint: BattutaVisualStyle.amber,
                    title: "最佳一天",
                    value: report.metrics.bestDay.map { statsCount($0.characterCount) } ?? "—",
                    detail: report.metrics.bestDay.map { shortDate($0.date) } ?? "暂无输入"
                )
                insight(
                    symbol: "flame.fill",
                    tint: BattutaVisualStyle.accentStrong,
                    title: "最长连续活跃",
                    value: "\(report.metrics.longestActiveDayStreak) 天",
                    detail: "连续出现有效输入"
                )
                insight(
                    symbol: "calendar.badge.clock",
                    tint: BattutaVisualStyle.cyan,
                    title: "最常输入星期",
                    value: weekdayName(report.metrics.busiestWeekday?.weekday),
                    detail: report.metrics.busiestWeekday.map {
                        "合计 \(statsCount($0.characterCount)) 个字符"
                    } ?? "暂无输入"
                )
                insight(
                    symbol: "clock.fill",
                    tint: BattutaVisualStyle.violet,
                    title: "最常输入时段",
                    value: hourRange(report.metrics.busiestHour?.hour),
                    detail: report.metrics.busiestHour.map {
                        "合计 \(statsCount($0.characterCount)) 个字符"
                    } ?? "暂无输入"
                )
            }
        }
        .padding(16)
        .historyInstrumentPanel()
    }

    private func insight(
        symbol: String,
        tint: Color,
        title: String,
        value: String,
        detail: String
    ) -> some View {
        HStack(spacing: 11) {
            BattutaIconTile(symbol: symbol, tint: tint, size: 34, symbolSize: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BattutaVisualStyle.instrumentPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func reportError(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("这个区间暂时读取失败")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("重试") {
                Task {
                    await model.loadReport(
                        range: selectedRange,
                        comparisonRange: comparisonRange
                    )
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .battutaTintedPanel(.orange, opacity: 0.07)
    }

    private var emptyReport: some View {
        VStack(spacing: 12) {
            BattutaIconTile(symbol: "calendar.badge.exclamationmark", tint: .secondary, size: 48, symbolSize: 20)
            Text("还没有可显示的年度统计")
                .font(.headline)
            Text("先开启统计并输入一段文字，历史页面会在这里逐日积累。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func dateRangeText(_ range: TypingDateRange?) -> String {
        guard let range else { return "未启用" }
        if calendar.isDate(range.startDate, inSameDayAs: range.endDate) {
            return longDate(range.startDate)
        }
        return "\(longDate(range.startDate)) – \(longDate(range.endDate))"
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month().day())
    }

    private func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day())
    }

    private func formattedAverage(_ value: Double) -> String {
        value.formatted(.number.grouping(.automatic).precision(.fractionLength(value < 10 ? 1 : 0)))
    }

    private func percentText(_ share: Double) -> String {
        (share * 100).formatted(.number.precision(.fractionLength(share < 0.1 ? 1 : 0))) + "%"
    }

    private func weekdayName(_ weekday: Int?) -> String {
        guard let weekday, (1...7).contains(weekday) else { return "—" }
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][weekday - 1]
    }

    private func hourRange(_ hour: Int?) -> String {
        guard let hour else { return "—" }
        return String(format: "%02d:00–%02d:00", hour, (hour + 1) % 24)
    }

    private func weekdayOccurrences(in range: TypingDateRange) -> [Int: Int] {
        var result = Dictionary(uniqueKeysWithValues: (1...7).map { ($0, 0) })
        var cursor = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        while cursor <= end {
            result[calendar.component(.weekday, from: cursor), default: 0] += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else {
                break
            }
            cursor = next
        }
        return result
    }

    private func applicationAccessibilityValue(
        _ app: TypingRangeApplicationSummary,
        hasComparison: Bool
    ) -> String {
        var value = "本区间 \(app.characterCount) 个字符，占比 \(percentText(app.share))"
        if hasComparison {
            value += "，对比区间 \(app.comparisonCharacterCount) 个字符，变化 \(changePresentation(current: app.characterCount, previous: app.comparisonCharacterCount).text)"
        }
        return value
    }

    private func changePresentation(
        current: Int64,
        previous: Int64
    ) -> (text: String, symbol: String, color: Color) {
        if previous == 0 {
            if current > 0 {
                return ("新增", "arrow.up.right", BattutaVisualStyle.accent)
            }
            return ("持平", "minus", .secondary)
        }

        let delta = Double(current - previous) / Double(previous)
        let magnitude = abs(delta * 100).formatted(.number.precision(.fractionLength(abs(delta) < 0.1 ? 1 : 0)))
        if delta > 0 {
            return ("+\(magnitude)%", "arrow.up.right", BattutaVisualStyle.accent)
        }
        if delta < 0 {
            return ("−\(magnitude)%", "arrow.down.right", .orange)
        }
        return ("持平", "minus", .secondary)
    }
}

private struct TypingWeekdayHourHeatmap: View {
    let values: [TypingWeekdayHourAggregate]
    let mode: TypingRhythmMode
    let currentWeekdayOccurrences: [Int: Int]
    let comparisonWeekdayOccurrences: [Int: Int]
    let metrics: TypingHeatmapCellMetrics

    private let weekdays = [2, 3, 4, 5, 6, 7, 1]

    private var valuesByID: [Int: TypingWeekdayHourAggregate] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }

    private var maximumCurrent: Double {
        values.map(currentAverage).max() ?? 0
    }

    private var maximumDifference: Double {
        values.map { abs(significantDifference(for: $0)) }.max() ?? 0
    }

    var body: some View {
        Grid(
            alignment: .center,
            horizontalSpacing: metrics.spacing,
            verticalSpacing: metrics.spacing
        ) {
            GridRow {
                Color.clear
                    .frame(width: TypingHeatmapCellMetrics.axisWidth, height: 14)
                    .accessibilityHidden(true)

                ForEach(0..<24, id: \.self) { hour in
                    Text(hour.isMultiple(of: 3) ? "\(hour)" : "")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                        .frame(width: metrics.cellSize, height: 14)
                        .accessibilityHidden(true)
                }
            }

            ForEach(weekdays, id: \.self) { weekday in
                GridRow {
                    Text(weekdayTitle(weekday))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                        .frame(
                            width: TypingHeatmapCellMetrics.axisWidth,
                            height: metrics.cellSize,
                            alignment: .leading
                        )

                    ForEach(0..<24, id: \.self) { hour in
                        let id = (weekday - 1) * 24 + hour
                        rhythmCell(
                            valuesByID[id] ?? TypingWeekdayHourAggregate(
                                weekday: weekday,
                                hour: hour,
                                characterCount: 0,
                                comparisonCharacterCount: 0
                            )
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rhythmCell(_ value: TypingWeekdayHourAggregate) -> some View {
        let delta = significantDifference(for: value)
        let color: Color
        let opacity: Double
        let symbol: String

        switch mode {
        case .current:
            let current = currentAverage(value)
            let intensity = normalized(current, maximum: maximumCurrent)
            color = value.characterCount > 0 ? BattutaVisualStyle.accent : Color.white
            opacity = value.characterCount > 0 ? 0.16 + intensity * 0.60 : 0.08
            symbol = "•"
        case .difference:
            let intensity = normalized(abs(delta), maximum: maximumDifference)
            if delta > 0 {
                color = BattutaVisualStyle.accent
                opacity = 0.14 + intensity * 0.62
                symbol = intensity >= 0.34 ? "↑" : "•"
            } else if delta < 0 {
                color = BattutaVisualStyle.cyan
                opacity = 0.14 + intensity * 0.58
                symbol = intensity >= 0.34 ? "↓" : "•"
            } else {
                color = Color.white
                opacity = 0.08
                symbol = "•"
            }
        }

        return Text(symbol)
            .font(.system(size: max(6, metrics.cellSize * 0.62), weight: .semibold))
            .foregroundStyle(Color.white.opacity(mode == .difference && delta == 0 ? 0.42 : 0.90))
            .frame(width: metrics.cellSize, height: metrics.cellSize)
            .background(
                color.opacity(opacity),
                in: RoundedRectangle(cornerRadius: 2, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.white.opacity(0.035), lineWidth: 1)
            }
            .help(helpText(value))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(weekdayTitle(value.weekday)) \(value.hour) 点")
            .accessibilityValue(helpText(value))
    }

    private func normalized(_ value: Double, maximum: Double) -> Double {
        guard value > 0, maximum > 0 else { return 0 }
        return min(1, sqrt(value / maximum))
    }

    private func currentAverage(_ value: TypingWeekdayHourAggregate) -> Double {
        let occurrences = max(1, currentWeekdayOccurrences[value.weekday, default: 1])
        return Double(value.characterCount) / Double(occurrences)
    }

    private func comparisonAverage(_ value: TypingWeekdayHourAggregate) -> Double {
        let occurrences = max(1, comparisonWeekdayOccurrences[value.weekday, default: 1])
        return Double(value.comparisonCharacterCount) / Double(occurrences)
    }

    private func significantDifference(for value: TypingWeekdayHourAggregate) -> Double {
        let current = currentAverage(value)
        let comparison = comparisonAverage(value)
        let difference = current - comparison
        let tolerance = max(2, max(current, comparison) * 0.05)
        return abs(difference) <= tolerance ? 0 : difference
    }

    private func weekdayTitle(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return "—" }
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][weekday - 1]
    }

    private func helpText(_ value: TypingWeekdayHourAggregate) -> String {
        let hour = String(format: "%02d:00–%02d:00", value.hour, (value.hour + 1) % 24)
        if mode == .current {
            return "\(weekdayTitle(value.weekday)) \(hour)：合计 \(statsCount(value.characterCount))，每个该星期平均 \(averageText(currentAverage(value))) 个字符"
        }
        let current = currentAverage(value)
        let comparison = comparisonAverage(value)
        let delta = current - comparison
        let deltaText = delta > 0 ? "+\(averageText(delta))" : averageText(delta)
        return "\(weekdayTitle(value.weekday)) \(hour)：当前平均 \(averageText(current))，上期平均 \(averageText(comparison))，变化 \(deltaText)"
    }

    private func averageText(_ value: Double) -> String {
        value.formatted(.number.grouping(.automatic).precision(.fractionLength(value < 10 ? 1 : 0)))
    }
}

@MainActor
private struct TypingReportApplicationIcon: View {
    let application: TypingApplicationIdentity

    private var applicationIcon: NSImage? {
        guard let bundleIdentifier = application.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var body: some View {
        Group {
            if let applicationIcon {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(5)
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                    .background(Color.white.opacity(0.08))
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct HistoryInstrumentPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                BattutaVisualStyle.instrumentSurface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
    }
}

private extension View {
    func historyInstrumentPanel() -> some View {
        modifier(HistoryInstrumentPanelModifier())
    }
}
