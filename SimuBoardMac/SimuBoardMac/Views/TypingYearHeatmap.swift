import AppKit
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
@MainActor
struct TypingYearHeatmap: View, Equatable {
    private let presentation: TypingYearHeatmapPresentation
    private let preferredMetrics: TypingHeatmapCellMetrics

    private let weekdayLabels = ["一", "", "三", "", "五", "", ""]

    init(
        range: TypingDateRange,
        days: [TypingDaySummary],
        calendar: Calendar,
        cellSize: CGFloat = TypingHeatmapCellMetrics.standard.cellSize,
        cellSpacing: CGFloat = TypingHeatmapCellMetrics.standard.spacing
    ) {
        presentation = TypingYearHeatmapPresentation(
            range: range,
            days: days,
            calendar: calendar
        )
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
        presentation = TypingYearHeatmapPresentation(
            range: range,
            days: days,
            calendar: calendar
        )
        preferredMetrics = metrics
    }

    var body: some View {
        let exposesEmptyCellsToAssistiveTech = NSWorkspace.shared.isVoiceOverEnabled
            || NSWorkspace.shared.isSwitchControlEnabled

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("全年输入热力图")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BattutaVisualStyle.instrumentPrimary)

                Text("\(presentation.rangeDescription) · 每个方格代表一天，颜色越亮表示输入越多")
                    .font(.caption)
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
            }

            heatmapContent(
                presentation: presentation,
                metrics: preferredMetrics,
                exposesEmptyCellsToAssistiveTech: exposesEmptyCellsToAssistiveTech
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heatmapContent(
        presentation: TypingYearHeatmapPresentation,
        metrics: TypingHeatmapCellMetrics,
        exposesEmptyCellsToAssistiveTech: Bool
    ) -> some View {
        let totalWidth = weekdayLabelWidth(metrics)
            + labelGridSpacing(metrics)
            + gridWidth(presentation: presentation, metrics: metrics)

        return VStack(alignment: .leading, spacing: 12 * scale(metrics)) {
            HStack(alignment: .top, spacing: labelGridSpacing(metrics)) {
                weekdayAxis(metrics: metrics)

                VStack(alignment: .leading, spacing: 5 * scale(metrics)) {
                    monthAxis(presentation: presentation, metrics: metrics)
                    contributionGrid(
                        presentation: presentation,
                        metrics: metrics,
                        exposesEmptyCellsToAssistiveTech: exposesEmptyCellsToAssistiveTech
                    )
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

    private func monthAxis(
        presentation: TypingYearHeatmapPresentation,
        metrics: TypingHeatmapCellMetrics
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(
                    width: gridWidth(presentation: presentation, metrics: metrics),
                    height: 12 * scale(metrics)
                )

            ForEach(presentation.monthMarkers) { marker in
                Text(marker.title)
                    .font(.system(size: max(6, 9 * scale(metrics)), weight: .medium))
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                    .fixedSize()
                    .offset(x: CGFloat(marker.weekIndex) * (metrics.cellSize + metrics.spacing))
                    .accessibilityHidden(true)
            }
        }
        .frame(
            width: gridWidth(presentation: presentation, metrics: metrics),
            height: 12 * scale(metrics)
        )
    }

    private func contributionGrid(
        presentation: TypingYearHeatmapPresentation,
        metrics: TypingHeatmapCellMetrics,
        exposesEmptyCellsToAssistiveTech: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: metrics.spacing) {
            ForEach(presentation.weeks) { week in
                VStack(spacing: metrics.spacing) {
                    ForEach(week.cells) { cell in
                        if cell.isVisible {
                            dayCell(
                                cell,
                                metrics: metrics,
                                exposesEmptyCellsToAssistiveTech: exposesEmptyCellsToAssistiveTech
                            )
                        } else {
                            Color.clear
                                .frame(width: metrics.cellSize, height: metrics.cellSize)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .frame(
            width: gridWidth(presentation: presentation, metrics: metrics),
            alignment: .leading
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("每日输入热力图")
    }

    private func dayCell(
        _ cell: TypingYearHeatmapPresentation.DayCell,
        metrics: TypingHeatmapCellMetrics,
        exposesEmptyCellsToAssistiveTech: Bool
    ) -> some View {
        let content = RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color(for: cell.level))
            .frame(width: metrics.cellSize, height: metrics.cellSize)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(BattutaVisualStyle.instrumentSeparator, lineWidth: 0.5)
            }

        return Group {
            if cell.hasInput {
                content
                    .help(cell.helpText)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(cell.dateText)
                    .accessibilityValue(cell.accessibilityValue)
            } else if exposesEmptyCellsToAssistiveTech {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        cell.date?.formatted(.dateTime.year().month().day().weekday(.wide))
                            ?? "没有输入的日期"
                    )
                    .accessibilityValue("0 个字符")
            } else {
                content.accessibilityHidden(true)
            }
        }
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

    private func gridWidth(
        presentation: TypingYearHeatmapPresentation,
        metrics: TypingHeatmapCellMetrics
    ) -> CGFloat {
        CGFloat(presentation.weekCount) * metrics.cellSize
            + CGFloat(max(0, presentation.weekCount - 1)) * metrics.spacing
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

}

/// Immutable render data keeps calendar traversal, indexing, and string formatting
/// out of the per-cell SwiftUI body path.
private struct TypingYearHeatmapPresentation: Equatable {
    struct DayCell: Identifiable, Equatable {
        let id: Int
        let date: Date?
        let isVisible: Bool
        let hasInput: Bool
        let level: Int
        let dateText: String
        let helpText: String
        let accessibilityValue: String
    }

    struct Week: Identifiable, Equatable {
        let index: Int
        let cells: [DayCell]

        var id: Int { index }
    }

    let rangeDescription: String
    let weekCount: Int
    let monthMarkers: [MonthMarker]
    let weeks: [Week]

    init(range: TypingDateRange, days: [TypingDaySummary], calendar: Calendar) {
        let startDate = calendar.startOfDay(for: range.startDate)
        let endDate = calendar.startOfDay(for: range.endDate)
        let gridStartDate = calendar.date(
            byAdding: .day,
            value: -Self.mondayBasedWeekdayIndex(for: startDate, calendar: calendar),
            to: startDate
        ) ?? startDate
        let remainingDays = 6 - Self.mondayBasedWeekdayIndex(for: endDate, calendar: calendar)
        let gridEndDate = calendar.date(byAdding: .day, value: remainingDays, to: endDate) ?? endDate
        let gridDayCount = calendar.dateComponents(
            [.day],
            from: gridStartDate,
            to: gridEndDate
        ).day ?? 0
        let resolvedWeekCount = max(1, gridDayCount / 7 + 1)
        let countsByDate = days.reduce(into: [Date: Int64]()) { result, summary in
            result[calendar.startOfDay(for: summary.date)] = summary.characterCount
        }
        let maximumCount = countsByDate.reduce(into: Int64(0)) { maximum, entry in
            guard entry.key >= startDate, entry.key <= endDate else { return }
            maximum = max(maximum, entry.value)
        }

        rangeDescription = "\(startDate.formatted(.dateTime.year().month().day())) – \(endDate.formatted(.dateTime.year().month().day()))"
        weekCount = resolvedWeekCount
        monthMarkers = Self.monthMarkers(
            from: startDate,
            through: endDate,
            gridStartDate: gridStartDate,
            calendar: calendar
        )
        weeks = (0..<resolvedWeekCount).map { weekIndex in
            let cells = (0..<7).map { weekdayIndex in
                let id = weekIndex * 7 + weekdayIndex
                let date = calendar.date(
                    byAdding: .day,
                    value: id,
                    to: gridStartDate
                ) ?? startDate
                guard date >= startDate, date <= endDate else {
                    return DayCell(
                        id: id,
                        date: nil,
                        isVisible: false,
                        hasInput: false,
                        level: 0,
                        dateText: "",
                        helpText: "",
                        accessibilityValue: ""
                    )
                }

                let count = countsByDate[date] ?? 0
                let level = Self.heatLevel(for: count, maximumCount: maximumCount)
                guard count > 0 else {
                    return DayCell(
                        id: id,
                        date: date,
                        isVisible: true,
                        hasInput: false,
                        level: level,
                        dateText: "",
                        helpText: "",
                        accessibilityValue: ""
                    )
                }
                let dateText = date.formatted(.dateTime.year().month().day().weekday(.wide))
                let formattedCount = count.formatted(.number.grouping(.automatic))
                return DayCell(
                    id: id,
                    date: date,
                    isVisible: true,
                    hasInput: count > 0,
                    level: level,
                    dateText: dateText,
                    helpText: "\(dateText)：\(formattedCount) 个字符",
                    accessibilityValue: "\(formattedCount) 个字符，活跃度第 \(level + 1) 级，共 5 级"
                )
            }
            return Week(index: weekIndex, cells: cells)
        }
    }

    private static func mondayBasedWeekdayIndex(for date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    private static func heatLevel(for count: Int64, maximumCount: Int64) -> Int {
        guard count > 0, maximumCount > 0 else { return 0 }
        let normalized = log1p(Double(count)) / log1p(Double(maximumCount))
        return min(4, max(1, Int(ceil(normalized * 4))))
    }

    private static func monthMarkers(
        from startDate: Date,
        through endDate: Date,
        gridStartDate: Date,
        calendar: Calendar
    ) -> [MonthMarker] {
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
                        title: cursor.formatted(.dateTime.month(.abbreviated)),
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
}

private struct MonthMarker: Identifiable, Equatable {
    let date: Date
    let title: String
    let weekIndex: Int

    var id: Date { date }
}
