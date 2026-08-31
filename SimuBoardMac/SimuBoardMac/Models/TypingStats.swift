import Foundation

/// Automatic value range shared by every one-way typing heatmap.
///
/// Only non-zero values currently represented by the view participate in the
/// range. Small samples use their real maximum; larger samples cap the range at
/// P95 so one exceptional bucket does not make every other cell look empty.
struct TypingHeatmapScale: Equatable, Sendable {
    static let percentileSampleThreshold = 20

    let low: Double
    let high: Double
    let hasValues: Bool

    init(values: [Double]) {
        let nonzeroValues = values
            .filter { $0.isFinite && $0 > 0 }
            .sorted()

        guard let minimum = nonzeroValues.first,
              let upperBound = Self.automaticUpperBound(for: nonzeroValues) else {
            low = 0
            high = 0
            hasValues = false
            return
        }

        low = minimum
        high = max(minimum, upperBound)
        hasValues = true
    }

    func normalized(_ value: Double) -> Double {
        guard hasValues, value.isFinite, value > 0 else { return 0 }
        guard high > low else { return 1 }
        return min(1, max(0, (value - low) / (high - low)))
    }

    fileprivate static func automaticUpperBound(for sortedValues: [Double]) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        guard sortedValues.count >= percentileSampleThreshold else {
            return sortedValues.last
        }

        // Linear-interpolated P95 matches the Windows implementation and keeps
        // the threshold stable as visible samples enter or leave the range.
        let position = 0.95 * Double(sortedValues.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        let lower = sortedValues[lowerIndex]
        let upper = sortedValues[upperIndex]
        return lower + (upper - lower) * (position - Double(lowerIndex))
    }
}

/// Symmetric automatic range for a difference heatmap. Zero always maps to the
/// neutral centre and positive/negative values share the same P95 magnitude.
struct TypingDivergingHeatmapScale: Equatable, Sendable {
    let limit: Double
    let hasValues: Bool

    init(values: [Double]) {
        let magnitudes = values
            .lazy
            .map(abs)
            .filter { $0.isFinite && $0 > 0 }
            .sorted()

        guard let upperBound = TypingHeatmapScale.automaticUpperBound(for: magnitudes) else {
            limit = 0
            hasValues = false
            return
        }

        limit = upperBound
        hasValues = true
    }

    func normalized(_ value: Double) -> Double {
        guard hasValues, value.isFinite, limit > 0 else { return 0 }
        return min(1, max(-1, value / limit))
    }
}

struct TypingDaySummary: Equatable, Identifiable, Sendable {
    let dateKey: String
    let date: Date
    let characterCount: Int64
    let peakCPS: Int64
    /// Number of natural minute buckets that contained input, not elapsed minutes.
    let activeMinuteBuckets: Int64
    let activeSeconds: Int64
    let topAppName: String?
    let lastUpdatedAt: Date?

    var id: String { dateKey }
}

/// A range of local calendar days. Both `startDate` and `endDate` are included.
///
/// The persistence layer normalizes the values to local day boundaries so callers
/// can pass dates directly from a date picker. Reversed inputs are accepted and
/// stored in chronological order.
struct TypingDateRange: Equatable, Sendable {
    let startDate: Date
    let endDate: Date

    init(startDate: Date, endDate: Date) {
        if startDate <= endDate {
            self.startDate = startDate
            self.endDate = endDate
        } else {
            self.startDate = endDate
            self.endDate = startDate
        }
    }
}

struct TypingRhythmDateRanges: Equatable, Sendable {
    let current: TypingDateRange
    let comparison: TypingDateRange

    /// Today plus the preceding six local calendar days, compared with the
    /// seven local calendar days immediately before that window.
    static func rollingSevenDays(endingAt date: Date, calendar: Calendar) -> Self {
        let currentEnd = calendar.startOfDay(for: date)
        let currentStart = calendar.date(byAdding: .day, value: -6, to: currentEnd)
            ?? currentEnd
        let comparisonEnd = calendar.date(byAdding: .day, value: -1, to: currentStart)
            ?? currentStart
        let comparisonStart = calendar.date(byAdding: .day, value: -6, to: comparisonEnd)
            ?? comparisonEnd
        return Self(
            current: TypingDateRange(startDate: currentStart, endDate: currentEnd),
            comparison: TypingDateRange(
                startDate: comparisonStart,
                endDate: comparisonEnd
            )
        )
    }
}

struct TypingWeekdayAggregate: Equatable, Identifiable, Sendable {
    /// Foundation calendar weekday: 1 is Sunday and 7 is Saturday.
    let weekday: Int
    let characterCount: Int64
    let activeDayCount: Int

    var id: Int { weekday }
}

struct TypingHourAggregate: Equatable, Identifiable, Sendable {
    /// Local wall-clock hour in the range 0...23.
    let hour: Int
    let characterCount: Int64
    let activeDayCount: Int
    let peakCPS: Int64

    var id: Int { hour }
}

struct TypingWeekdayHourAggregate: Equatable, Identifiable, Sendable {
    /// Foundation calendar weekday: 1 is Sunday and 7 is Saturday.
    let weekday: Int
    /// Local wall-clock hour in the range 0...23.
    let hour: Int
    let characterCount: Int64
    let comparisonCharacterCount: Int64

    /// Stable weekday-major position in the complete 7 x 24 matrix.
    var id: Int { (weekday - 1) * 24 + hour }
}

struct TypingRangeMetrics: Equatable, Sendable {
    let characterCount: Int64
    let calendarDayCount: Int
    let activeDayCount: Int
    /// Average over every requested calendar day, including days with no input.
    let dailyAverage: Double
    /// Average over days that contain at least one recorded character.
    let activeDayAverage: Double
    let peakCPS: Int64
    let bestDay: TypingDaySummary?
    let longestActiveDayStreak: Int
    let busiestWeekday: TypingWeekdayAggregate?
    let busiestHour: TypingHourAggregate?
}

struct TypingRangeApplicationSummary: Equatable, Identifiable, Sendable {
    let application: TypingApplicationIdentity
    let characterCount: Int64
    let comparisonCharacterCount: Int64
    let activeDayCount: Int
    let comparisonActiveDayCount: Int
    let share: Double
    let comparisonShare: Double
    let characterChange: Int64
    /// Fractional change, where `0.25` means +25%. Nil means there is no
    /// comparison baseline (the comparison count is zero).
    let relativeCharacterChange: Double?

    var id: String { application.processKey }
}

struct TypingReportDataCoverage: Equatable, Sendable {
    let firstRecordedDate: Date?
    let lastRecordedDate: Date?
    let requestedDayCount: Int
    /// Requested days that contain at least one permanent daily aggregate.
    let recordedDayCount: Int
    /// True when the requested endpoints fall inside the permanent aggregate's
    /// first-to-last recorded date span. Empty dates inside that span are valid.
    let isRangeWithinAvailableDates: Bool
}

struct TypingRangeReportSnapshot: Equatable, Sendable {
    let generatedAt: Date
    let range: TypingDateRange
    let comparisonRange: TypingDateRange?
    /// The shorter period used by the weekday/hour rhythm panel. It can differ
    /// from the annual range used by the rest of the history report.
    let rhythmRange: TypingDateRange
    let rhythmComparisonRange: TypingDateRange?
    let metrics: TypingRangeMetrics
    let comparisonMetrics: TypingRangeMetrics?
    /// One entry for every requested calendar day, including zero-value days.
    let days: [TypingDaySummary]
    let weekdayDistribution: [TypingWeekdayAggregate]
    let hourlyDistribution: [TypingHourAggregate]
    /// Complete 7 x 24 local-time rhythm matrix, ordered Sunday through
    /// Saturday and hour 0 through 23. Missing current/comparison cells are zero.
    let weekdayHourDistribution: [TypingWeekdayHourAggregate]
    /// Union of applications found in the selected and comparison ranges.
    let applications: [TypingRangeApplicationSummary]
    let coverage: TypingReportDataCoverage

    /// Refresh timestamps are metadata; they must not force the full history view
    /// to rebuild when every value visible to the user is unchanged.
    func hasSameVisibleContent(as other: TypingRangeReportSnapshot) -> Bool {
        range == other.range
            && comparisonRange == other.comparisonRange
            && rhythmRange == other.rhythmRange
            && rhythmComparisonRange == other.rhythmComparisonRange
            && metrics == other.metrics
            && comparisonMetrics == other.comparisonMetrics
            && days == other.days
            && weekdayDistribution == other.weekdayDistribution
            && hourlyDistribution == other.hourlyDistribution
            && weekdayHourDistribution == other.weekdayHourDistribution
            && applications == other.applications
            && coverage == other.coverage
    }
}

struct TypingBucket: Equatable, Identifiable, Sendable {
    let index: Int
    let start: Date
    let characterCount: Int64

    var id: Int { index }
}

struct TypingStatsSnapshotSections: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let recentBuckets = TypingStatsSnapshotSections(rawValue: 1 << 0)
    static let applications = TypingStatsSnapshotSections(rawValue: 1 << 1)
    static let recentAppTimelines = TypingStatsSnapshotSections(rawValue: 1 << 2)
    static let history = TypingStatsSnapshotSections(rawValue: 1 << 3)
    static let keyCounts = TypingStatsSnapshotSections(rawValue: 1 << 4)

    static let all: TypingStatsSnapshotSections = [
        .recentBuckets,
        .applications,
        .recentAppTimelines,
        .history,
        .keyCounts,
    ]
}

struct TypingStatsSnapshotRequest: Equatable, Sendable {
    let timelineRange: TypingTimelineRange
    let sections: TypingStatsSnapshotSections
}

enum TypingTimelineRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays = "7d"
    case twentyFourHours = "24h"
    case sixHours = "6h"
    case oneHour = "1h"

    var id: Self { self }

    var durationSeconds: Int64 {
        bucketSeconds * Int64(bucketCount)
    }

    var bucketSeconds: Int64 {
        switch self {
        case .sevenDays: 7_200
        case .twentyFourHours: 900
        case .sixHours: 300
        case .oneHour: 60
        }
    }

    var bucketCount: Int {
        switch self {
        case .sevenDays: 84
        case .twentyFourHours: 96
        case .sixHours: 72
        case .oneHour: 60
        }
    }

    var displayTitle: String {
        switch self {
        case .sevenDays: "最近 7 天".localized
        case .twentyFourHours: "最近 24 小时".localized
        case .sixHours: "最近 6 小时".localized
        case .oneHour: "最近 1 小时".localized
        }
    }

    var bucketDescription: String {
        switch self {
        case .sevenDays: "每格 2 小时".localized
        case .twentyFourHours: "每格 15 分钟".localized
        case .sixHours: "每格 5 分钟".localized
        case .oneHour: "每格 1 分钟".localized
        }
    }

    var refreshIntervalSeconds: Double {
        switch self {
        case .sevenDays: 60
        case .twentyFourHours: 30
        case .sixHours: 15
        case .oneHour: 5
        }
    }
}

struct TypingAppSummary: Equatable, Identifiable, Sendable {
    let processKey: String
    let displayName: String
    let processName: String
    let bundleIdentifier: String?
    let characterCount: Int64
    let activeMinuteBuckets: Int64
    let activeSeconds: Int64
    let peakCPS: Int64

    var id: String { processKey }
}

struct TypingAppTimeline: Equatable, Identifiable, Sendable {
    let application: TypingApplicationIdentity
    let buckets: [TypingBucket]

    var id: String { application.processKey }

    var rangeCharacterCount: Int64 {
        buckets.reduce(0) { $0 + $1.characterCount }
    }

    var peakBucketCount: Int64 {
        buckets.lazy.map(\.characterCount).max() ?? 0
    }
}

struct TypingApplicationIdentity: Equatable, Hashable, Sendable {
    let processKey: String
    let displayName: String
    let processName: String
    let bundleIdentifier: String?

    static let unknown = TypingApplicationIdentity(
        processKey: "unknown",
        displayName: "未知应用".localized,
        processName: "unknown",
        bundleIdentifier: nil
    )
}

struct TypingCharacterAggregate: Equatable, Sendable {
    let secondStart: Int64
    let localDate: String
    let application: TypingApplicationIdentity
    let count: Int64
}

struct TypingKeyAggregate: Equatable, Sendable {
    let localDate: String
    let keyCode: UInt16
    let count: Int64
}

struct TypingStatsWriteBatch: Equatable, Sendable {
    let characterAggregates: [TypingCharacterAggregate]
    let keyAggregates: [TypingKeyAggregate]

    var isEmpty: Bool {
        characterAggregates.isEmpty && keyAggregates.isEmpty
    }
}

struct TypingStatsSnapshot: Equatable, Sendable {
    let generatedAt: Date
    let lastInputAt: Date?
    let today: TypingDaySummary
    let timelineRange: TypingTimelineRange
    let recentBuckets: [TypingBucket]
    let apps: [TypingAppSummary]
    let recentAppTimelines: [TypingAppTimeline]
    let history: [TypingDaySummary]
    let todayKeyCounts: [UInt16: Int64]
    let allTimeKeyCounts: [UInt16: Int64]

    var fourteenDayTotal: Int64 {
        history.reduce(0) { $0 + $1.characterCount }
    }

    var fourteenDayAverage: Int64 {
        guard !history.isEmpty else { return 0 }
        return fourteenDayTotal / Int64(history.count)
    }

    var bestDay: TypingDaySummary? {
        history.lazy.filter { $0.characterCount > 0 }
            .max { $0.characterCount < $1.characterCount }
    }

    var activeDayCount: Int {
        history.lazy.filter { $0.characterCount > 0 }.count
    }

    var todayPhysicalPresses: Int64 {
        todayKeyCounts.values.reduce(0, +)
    }

    var allTimePhysicalPresses: Int64 {
        allTimeKeyCounts.values.reduce(0, +)
    }

    /// Ignore `generatedAt` when deciding whether an automatic refresh needs to
    /// invalidate the heavy snapshot views. Read time is published separately.
    func hasSameVisibleContent(as other: TypingStatsSnapshot) -> Bool {
        lastInputAt == other.lastInputAt
            && today == other.today
            && timelineRange == other.timelineRange
            && recentBuckets == other.recentBuckets
            && apps == other.apps
            && recentAppTimelines == other.recentAppTimelines
            && history == other.history
            && todayKeyCounts == other.todayKeyCounts
            && allTimeKeyCounts == other.allTimeKeyCounts
    }
}

enum TypingStatsSourceStatus: Equatable, Sendable {
    case checking
    case available
    case failed(String)
}

enum TypingCharacterKeyFilter {
    /// Hardware keys that can directly contribute one text character. An allow-list
    /// prevents new function/media key codes from silently inflating character totals.
    private static let characterKeyCodes: Set<UInt16> = Set(
        Array(UInt16(0)...UInt16(35))
            + Array(UInt16(37)...UInt16(47))
            + [49, 50] // Space and backquote
            + [65, 67, 69, 75, 78, 81] // Keypad punctuation/operators
            + Array(UInt16(82)...UInt16(89))
            + [91, 92, 93, 94, 95] // Keypad 8/9 and ISO/JIS character keys
    )

    static func countsAsCharacter(keyCode: UInt16, isShortcutModified: Bool) -> Bool {
        !isShortcutModified && characterKeyCodes.contains(keyCode)
    }
}
