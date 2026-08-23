import Foundation
import SwiftUI

/// Shared square-cell geometry for the history page's rhythm and annual grids.
/// Use `.standard` for both grids so their cells and gutters remain visually
/// consistent. The annual grid scales both values together when space is tight.
struct TypingHeatmapCellMetrics: Equatable, Sendable {
    static let axisWidth: CGFloat = 34
    static let spacing: CGFloat = 3
    static let standard = TypingHeatmapCellMetrics(cellSize: 14, spacing: spacing)

    let cellSize: CGFloat
    let spacing: CGFloat

    init(cellSize: CGFloat, spacing: CGFloat) {
        self.cellSize = max(1, cellSize)
        self.spacing = max(0, spacing)
    }

    func scaled(by factor: CGFloat) -> TypingHeatmapCellMetrics {
        TypingHeatmapCellMetrics(
            cellSize: cellSize * factor,
            spacing: spacing * factor
        )
    }
}

/// A compact, GitHub-style contribution grid for a year of typing activity.
///
/// The caller owns the surrounding panel so this view can be composed with the
/// history page's existing instrument-card treatment.
struct TypingYearHeatmap: View {
    let range: TypingDateRange
    let days: [TypingDaySummary]
    let calendar: Calendar
    let preferredMetrics: TypingHeatmapCellMetrics

    private let weekdayLabels = ["一", "", "三", "", "五", "", ""]

    init(
        range: TypingDateRange,
        days: [TypingDaySummary],
        calendar: Calendar,
        cellSize: CGFloat = TypingHeatmapCellMetrics.standard.cellSize,
        cellSpacing: CGFloat = TypingHeatmapCellMetrics.standard.spacing
    ) {
        self.range = range
        self.days = days
        self.calendar = calendar
        preferredMetrics = TypingHeatmapCellMetrics(
            cellSize: cellSize,
            spacing: cellSpacing
        )
    }

    init(
        range: TypingDateRange,
        days: [TypingDaySummary],
        calendar: Calendar,
        metrics: TypingHeatmapCellMetrics
    ) {
        self.range = range
        self.days = days
        self.calendar = calendar
        preferredMetrics = metrics
    }

    private var startDate: Date {
        calendar.startOfDay(for: range.startDate)
    }

    private var endDate: Date {
        calendar.startOfDay(for: range.endDate)
    }

    /// The first visible column always begins on Monday.
    private var gridStartDate: Date {
        calendar.date(
            byAdding: .day,
            value: -mondayBasedWeekdayIndex(for: startDate),
            to: startDate
        ) ?? startDate
    }

    /// The final visible column always ends on Sunday.
    private var gridEndDate: Date {
        let remainingDays = 6 - mondayBasedWeekdayIndex(for: endDate)
        return calendar.date(byAdding: .day, value: remainingDays, to: endDate) ?? endDate
    }

    private var weekCount: Int {
        let dayCount = calendar.dateComponents(
            [.day],
            from: gridStartDate,
            to: gridEndDate
        ).day ?? 0
        return max(1, dayCount / 7 + 1)
    }

    private var summariesByDate: [Date: TypingDaySummary] {
        days.reduce(into: [:]) { result, summary in
            result[calendar.startOfDay(for: summary.date)] = summary
        }
    }

    private var maximumCount: Int64 {
        days.lazy
            .filter { summary in
                let date = calendar.startOfDay(for: summary.date)
                return date >= startDate && date <= endDate
            }
            .map(\.characterCount)
            .max() ?? 0
    }

    private var monthMarkers: [MonthMarker] {
        var markers: [MonthMarker] = []
        var cursor = startDate
        var previousMonth: Int?
        var previousYear: Int?

        while cursor <= endDate {
            let month = calendar.component(.month, from: cursor)
            let year = calendar.component(.year, from: cursor)
            if month != previousMonth || year != previousYear {
                let dayOffset = calendar.dateComponents(
                    [.day],
                    from: gridStartDate,
                    to: cursor
                ).day ?? 0
                markers.append(
                    MonthMarker(
                        date: cursor,
                        weekIndex: max(0, dayOffset / 7)
                    )
                )
                previousMonth = month
                previousYear = year
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else {
                break
            }
            cursor = next
        }

        return markers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("全年输入热力图")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BattutaVisualStyle.instrumentPrimary)

                Text("\(rangeDescription) · 每个方格代表一天，颜色越亮表示输入越多")
                    .font(.caption)
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
            }

            heatmapContent(metrics: preferredMetrics)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heatmapContent(metrics: TypingHeatmapCellMetrics) -> some View {
        let totalWidth = weekdayLabelWidth(metrics)
            + labelGridSpacing(metrics)
            + gridWidth(metrics)

        return VStack(alignment: .leading, spacing: 12 * scale(metrics)) {
            HStack(alignment: .top, spacing: labelGridSpacing(metrics)) {
                weekdayAxis(metrics: metrics)

                VStack(alignment: .leading, spacing: 5 * scale(metrics)) {
                    monthAxis(metrics: metrics)
                    contributionGrid(metrics: metrics)
                }
            }

            legend(metrics: metrics)
                .frame(width: totalWidth, alignment: .trailing)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func weekdayAxis(metrics: TypingHeatmapCellMetrics) -> some View {
        VStack(spacing: 5 * scale(metrics)) {
            Color.clear
                .frame(width: weekdayLabelWidth(metrics), height: 12 * scale(metrics))
                .accessibilityHidden(true)

            VStack(spacing: metrics.spacing) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: max(6, 8 * scale(metrics)), weight: .medium))
                        .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                        .frame(
                            width: weekdayLabelWidth(metrics),
                            height: metrics.cellSize,
                            alignment: .trailing
                        )
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func monthAxis(metrics: TypingHeatmapCellMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: gridWidth(metrics), height: 12 * scale(metrics))

            ForEach(monthMarkers) { marker in
                Text(monthTitle(marker.date))
                    .font(.system(size: max(6, 9 * scale(metrics)), weight: .medium))
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                    .fixedSize()
                    .offset(x: CGFloat(marker.weekIndex) * (metrics.cellSize + metrics.spacing))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: gridWidth(metrics), height: 12 * scale(metrics))
    }

    private func contributionGrid(metrics: TypingHeatmapCellMetrics) -> some View {
        HStack(alignment: .top, spacing: metrics.spacing) {
            ForEach(0..<weekCount, id: \.self) { weekIndex in
                VStack(spacing: metrics.spacing) {
                    ForEach(0..<7, id: \.self) { weekdayIndex in
                        if let date = date(weekIndex: weekIndex, weekdayIndex: weekdayIndex),
                           date >= startDate,
                           date <= endDate
                        {
                            dayCell(date, metrics: metrics)
                        } else {
                            Color.clear
                                .frame(width: metrics.cellSize, height: metrics.cellSize)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .frame(width: gridWidth(metrics), alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("每日输入热力图")
    }

    private func dayCell(_ date: Date, metrics: TypingHeatmapCellMetrics) -> some View {
        let count = summariesByDate[calendar.startOfDay(for: date)]?.characterCount ?? 0
        let level = heatLevel(for: count)
        let dateText = date.formatted(.dateTime.year().month().day().weekday(.wide))
        let helpText = "\(dateText)：\(formattedCount(count)) 个字符"

        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color(for: level))
            .frame(width: metrics.cellSize, height: metrics.cellSize)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(BattutaVisualStyle.instrumentSeparator, lineWidth: 0.5)
            }
            .help(helpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dateText)
            .accessibilityValue("\(formattedCount(count)) 个字符，活跃度第 \(level + 1) 级，共 5 级")
    }

    private func legend(metrics: TypingHeatmapCellMetrics) -> some View {
        HStack(spacing: 6 * scale(metrics)) {
            Text("少")
                .font(.system(size: max(7, 9 * scale(metrics))))
                .foregroundStyle(BattutaVisualStyle.instrumentSecondary)

            HStack(spacing: metrics.spacing) {
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: level))
                        .frame(width: metrics.cellSize, height: metrics.cellSize)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(BattutaVisualStyle.instrumentSeparator, lineWidth: 0.5)
                        }
                }
            }
            .accessibilityHidden(true)

            Text("多")
                .font(.system(size: max(7, 9 * scale(metrics))))
                .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("颜色图例，从少到多，共五级")
    }

    private func gridWidth(_ metrics: TypingHeatmapCellMetrics) -> CGFloat {
        CGFloat(weekCount) * metrics.cellSize
            + CGFloat(max(0, weekCount - 1)) * metrics.spacing
    }

    private func scale(_ metrics: TypingHeatmapCellMetrics) -> CGFloat {
        metrics.cellSize / TypingHeatmapCellMetrics.standard.cellSize
    }

    private func weekdayLabelWidth(_ metrics: TypingHeatmapCellMetrics) -> CGFloat {
        TypingHeatmapCellMetrics.axisWidth
    }

    private func labelGridSpacing(_ metrics: TypingHeatmapCellMetrics) -> CGFloat {
        TypingHeatmapCellMetrics.spacing
    }

    private func date(weekIndex: Int, weekdayIndex: Int) -> Date? {
        calendar.date(
            byAdding: .day,
            value: weekIndex * 7 + weekdayIndex,
            to: gridStartDate
        )
    }

    private func mondayBasedWeekdayIndex(for date: Date) -> Int {
        let foundationWeekday = calendar.component(.weekday, from: date)
        return (foundationWeekday + 5) % 7
    }

    private func heatLevel(for count: Int64) -> Int {
        guard count > 0, maximumCount > 0 else { return 0 }
        let normalized = log1p(Double(count)) / log1p(Double(maximumCount))
        return min(4, max(1, Int(ceil(normalized * 4))))
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 1:
            return BattutaVisualStyle.accent.opacity(0.24)
        case 2:
            return BattutaVisualStyle.accent.opacity(0.42)
        case 3:
            return BattutaVisualStyle.accent.opacity(0.66)
        case 4:
            return BattutaVisualStyle.accent.opacity(0.92)
        default:
            return BattutaVisualStyle.instrumentSeparator.opacity(0.64)
        }
    }

    private var rangeDescription: String {
        let start = startDate.formatted(.dateTime.year().month().day())
        let end = endDate.formatted(.dateTime.year().month().day())
        return "\(start) – \(end)"
    }

    private func monthTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated))
    }

    private func formattedCount(_ count: Int64) -> String {
        count.formatted(.number.grouping(.automatic))
    }
}

private struct MonthMarker: Identifiable {
    let date: Date
    let weekIndex: Int

    var id: Date { date }
}
