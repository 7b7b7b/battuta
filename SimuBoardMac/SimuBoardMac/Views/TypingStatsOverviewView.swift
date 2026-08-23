import Charts
import SwiftUI

private struct TypingOverviewMetric: Identifiable {
    let title: String
    let value: String
    var unit: String? = nil
    let detail: String
    let symbol: String

    var id: String { title }
}

private struct TypingTrendPoint: Identifiable {
    let index: Int
    let start: Date
    let value: Double

    var id: Int { index }
}

private struct TypingOverviewTopLayout: Layout {
    let spacing: CGFloat = 16
    let metricGridFraction: CGFloat = 0.42

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 1_000
        let metricGridWidth = max(0, (width - spacing) * metricGridFraction)
        return CGSize(width: width, height: metricGridWidth)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count >= 2 else { return }

        let metricGridWidth = max(0, (bounds.width - spacing) * metricGridFraction)
        let trendWidth = max(0, bounds.width - spacing - metricGridWidth)
        let metricProposal = ProposedViewSize(width: metricGridWidth, height: bounds.height)
        let trendProposal = ProposedViewSize(width: trendWidth, height: bounds.height)

        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: metricProposal
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + metricGridWidth + spacing, y: bounds.minY),
            anchor: .topLeading,
            proposal: trendProposal
        )
    }
}

@MainActor
struct TypingStatsOverviewView: View {
    let snapshot: TypingStatsSnapshot
    let selectedRange: TypingTimelineRange
    let onSelectRange: @MainActor @Sendable (TypingTimelineRange) -> Void

    private var recentTotal: Int64 {
        snapshot.recentBuckets.reduce(0) { $0 + $1.characterCount }
    }

    private var recentPeak: Int64 {
        snapshot.recentBuckets.lazy.map(\.characterCount).max() ?? 0
    }

    private var metrics: [TypingOverviewMetric] {
        [
            TypingOverviewMetric(
                title: "今日字符",
                value: statsCount(snapshot.today.characterCount),
                unit: "字符",
                detail: "按字符键触发估算",
                symbol: "keyboard"
            ),
            TypingOverviewMetric(
                title: "最多应用",
                value: snapshot.today.topAppName ?? "暂无",
                detail: snapshot.apps.first.map {
                    "\(statsCount($0.characterCount)) 个字符"
                } ?? "今天还没有输入",
                symbol: "app.fill"
            ),
            TypingOverviewMetric(
                title: "今日峰值",
                value: statsCount(snapshot.today.peakCPS),
                unit: "字/秒",
                detail: lastInputDescription(snapshot.lastInputAt),
                symbol: "bolt.fill"
            ),
            TypingOverviewMetric(
                title: "活跃时间",
                value: statsActiveTime(snapshot.today.activeSeconds),
                detail: "\(snapshot.today.activeMinuteBuckets) 个输入分钟",
                symbol: "clock.fill"
            ),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TypingOverviewTopLayout {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        spacing: 12
                    ) {
                        ForEach(metrics) { metric in
                            TypingOverviewMetricCard(metric: metric)
                        }
                    }

                    TypingRecentTrendCard(
                        buckets: snapshot.recentBuckets,
                        total: recentTotal,
                        peak: recentPeak,
                        range: snapshot.timelineRange,
                        selectedRange: selectedRange,
                        onSelectRange: onSelectRange
                    )
                }

                TypingAppTimelinePanel(
                    timelines: snapshot.recentAppTimelines,
                    range: snapshot.timelineRange
                )
            }
            .padding(20)
            .frame(maxWidth: 1_080)
            .frame(maxWidth: .infinity)
        }
    }
}

@MainActor
private struct TypingOverviewMetricCard: View {
    let metric: TypingOverviewMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: metric.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BattutaVisualStyle.instrumentPrimary)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Text(metric.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.value)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(BattutaVisualStyle.instrumentPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .allowsTightening(true)
                if let unit = metric.unit {
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .offset(y: -4)

            Spacer(minLength: 8)

            Text(metric.detail)
                .font(.caption2)
                .foregroundStyle(BattutaVisualStyle.instrumentSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(metric.detail)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .aspectRatio(1, contentMode: .fit)
        .background(
            BattutaVisualStyle.instrumentSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 10, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue("\(metric.value) \(metric.unit ?? "")，\(metric.detail)")
    }
}

@MainActor
private struct TypingRecentTrendCard: View {
    let buckets: [TypingBucket]
    let total: Int64
    let peak: Int64
    let range: TypingTimelineRange
    let selectedRange: TypingTimelineRange
    let onSelectRange: @MainActor @Sendable (TypingTimelineRange) -> Void

    private var trendPoints: [TypingTrendPoint] {
        let weights: [Double] = [1, 2, 3, 2, 1]
        let radius = weights.count / 2

        return buckets.indices.map { index in
            var weightedTotal = 0.0
            var weightTotal = 0.0
            for offset in -radius...radius {
                let neighborIndex = index + offset
                guard buckets.indices.contains(neighborIndex) else { continue }
                let weight = weights[offset + radius]
                weightedTotal += Double(buckets[neighborIndex].characterCount) * weight
                weightTotal += weight
            }
            return TypingTrendPoint(
                index: index,
                start: buckets[index].start,
                value: weightTotal > 0 ? weightedTotal / weightTotal : 0
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                BattutaSectionHeading(
                    "输入趋势",
                    subtitle: "\(range.displayTitle) · \(range.bucketDescription)",
                    symbol: "waveform.path.ecg"
                )
                Spacer(minLength: 8)
                Picker(
                    "时间范围",
                    selection: Binding(
                        get: { selectedRange },
                        set: onSelectRange
                    )
                ) {
                    ForEach(TypingTimelineRange.allCases) { timelineRange in
                        Text(timelineRange.rawValue).tag(timelineRange)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 196)
                .help("调整输入趋势与应用时间线的统计范围")
                .accessibilityLabel("统计时间范围")
            }

            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    summary("总计", value: statsCount(total))
                    summary("单格峰值", value: statsCount(peak))
                }
            }

            if total == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(BattutaVisualStyle.accentStrong)
                    Text("这一时段还没有输入")
                        .font(.subheadline.weight(.semibold))
                    Text("开始打字后，曲线会立即出现。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            } else {
                Chart {
                    ForEach(buckets) { bucket in
                        BarMark(
                            x: .value("时间", bucket.start),
                            y: .value("原始字符数", bucket.characterCount)
                        )
                        .foregroundStyle(BattutaVisualStyle.accent.opacity(0.11))
                        .cornerRadius(2)
                    }

                    ForEach(trendPoints) { point in
                        AreaMark(
                            x: .value("时间", point.start),
                            y: .value("平滑趋势", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    BattutaVisualStyle.accent.opacity(0.22),
                                    BattutaVisualStyle.accent.opacity(0.01),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("时间", point.start),
                            y: .value("平滑趋势", point.value)
                        )
                        .foregroundStyle(BattutaVisualStyle.accentStrong)
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: 2.6,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .interpolationMethod(.monotone)
                    }
                }
                .chartXAxis {
                    AxisMarks(
                        values: .stride(
                            by: axisCalendarComponent,
                            count: axisStrideCount
                        )
                    ) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.08))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(for: date))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.10))
                        AxisValueLabel()
                    }
                }
                .accessibilityLabel("\(range.displayTitle)字符数曲线")
                .accessibilityValue("合计 \(total) 个字符，单个区间峰值 \(peak) 个字符")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .battutaPanel(radius: 20)
    }

    private func summary(_ title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var axisCalendarComponent: Calendar.Component {
        switch range {
        case .sevenDays: .day
        case .twentyFourHours, .sixHours: .hour
        case .oneHour: .minute
        }
    }

    private var axisStrideCount: Int {
        switch range {
        case .sevenDays: 1
        case .twentyFourHours: 4
        case .sixHours: 1
        case .oneHour: 15
        }
    }

    private func axisLabel(for date: Date) -> String {
        switch range {
        case .sevenDays:
            date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        case .twentyFourHours:
            date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))
        case .sixHours, .oneHour:
            date.formatted(
                .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            )
        }
    }
}

@MainActor
private struct TypingAppTimelinePanel: View {
    let timelines: [TypingAppTimeline]
    let range: TypingTimelineRange

    private let appWidth: CGFloat = 150
    private let countWidth: CGFloat = 74

    private var globalPeak: Int64 {
        max(1, timelines.lazy.map(\.peakBucketCount).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                BattutaSectionHeading(
                    "应用时间线",
                    subtitle: "\(range.displayTitle) · \(range.bucketDescription)",
                    symbol: "square.grid.3x1.folder.badge.plus"
                )
                Spacer()
                Text("\(timelines.count) 个应用")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BattutaVisualStyle.accentStrong)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(BattutaVisualStyle.accentSoft, in: Capsule())
            }
            .padding(16)

            Divider()

            if timelines.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(BattutaVisualStyle.accentStrong)
                    Text("\(range.displayTitle)还没有应用输入。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 76)
            } else {
                timelineHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                ForEach(Array(timelines.enumerated()), id: \.element.id) { index, timeline in
                    TypingAppTimelineRow(
                        timeline: timeline,
                        globalPeak: globalPeak,
                        appWidth: appWidth,
                        countWidth: countWidth,
                        range: range
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)

                    if index < timelines.count - 1 {
                        Divider().padding(.leading, 16 + appWidth + countWidth + 24)
                    }
                }

                timelineAxis
                    .padding(.horizontal, 16)
                    .padding(.top, 5)
                    .padding(.bottom, 12)
            }
        }
        .battutaPanel(radius: 20)
    }

    private var timelineHeader: some View {
        HStack(spacing: 12) {
            Text("应用")
                .frame(width: appWidth, alignment: .leading)
            Text("区间")
                .frame(width: countWidth, alignment: .trailing)
            Text("输入时间线")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var timelineAxis: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: appWidth, height: 1)
            Color.clear.frame(width: countWidth, height: 1)
            if let buckets = timelines.first?.buckets,
               let first = buckets.first,
               let middle = buckets.dropFirst(buckets.count / 2).first,
                let last = timelines.first?.buckets.last {
                HStack {
                    Text(timelineAxisLabel(first.start))
                    Spacer()
                    Text(timelineAxisLabel(middle.start))
                    Spacer()
                    Text(
                        timelineAxisLabel(
                            last.start.addingTimeInterval(TimeInterval(range.bucketSeconds))
                        )
                    )
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private func timelineAxisLabel(_ date: Date) -> String {
        if range == .sevenDays || range == .twentyFourHours {
            return date.formatted(
                .dateTime.month(.twoDigits).day(.twoDigits)
                    .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            )
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

@MainActor
private struct TypingAppTimelineRow: View {
    let timeline: TypingAppTimeline
    let globalPeak: Int64
    let appWidth: CGFloat
    let countWidth: CGFloat
    let range: TypingTimelineRange

    var body: some View {
        HStack(spacing: 12) {
            Text(timeline.application.displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(timeline.application.displayName)
                .frame(width: appWidth, alignment: .leading)

            Text(statsCount(timeline.rangeCharacterCount))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: countWidth, alignment: .trailing)

            HStack(spacing: range.bucketCount > 84 ? 1 : 2) {
                ForEach(timeline.buckets) { bucket in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: bucket.characterCount))
                        .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)
                        .help(
                            "\(tooltipTimestamp(bucket.start)) · "
                                + "\(bucket.characterCount) 个字符"
                        )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timeline.application.displayName)
        .accessibilityValue(
            "\(range.displayTitle) \(timeline.rangeCharacterCount) 个字符，"
                + "峰值区间 \(timeline.peakBucketCount) 个字符，"
                + activeTimeDescription
        )
    }

    private var activeTimeDescription: String {
        let activeBuckets = timeline.buckets.filter { $0.characterCount > 0 }
        guard let first = activeBuckets.first, let last = activeBuckets.last else {
            return "\(range.displayTitle)没有输入"
        }

        let start = first.start.formatted(date: .omitted, time: .shortened)
        let end = last.start
            .addingTimeInterval(TimeInterval(range.bucketSeconds))
            .formatted(date: .omitted, time: .shortened)
        return "\(start) 至 \(end) 有输入，共 \(activeBuckets.count) 个活跃区间"
    }

    private func tooltipTimestamp(_ date: Date) -> String {
        if range == .sevenDays || range == .twentyFourHours {
            return date.formatted(
                .dateTime.month(.twoDigits).day(.twoDigits)
                    .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            )
        }
        return date.formatted(date: .omitted, time: .standard)
    }

    private func color(for count: Int64) -> Color {
        guard count > 0 else { return Color.white.opacity(0.055) }
        let intensity = min(1, Double(count) / Double(globalPeak))
        if intensity < 0.25 {
            return BattutaVisualStyle.cyan.opacity(0.28)
        }
        if intensity < 0.55 {
            return BattutaVisualStyle.cyan.opacity(0.55)
        }
        if intensity < 0.82 {
            return BattutaVisualStyle.accent.opacity(0.72)
        }
        return BattutaVisualStyle.accentStrong
    }
}
