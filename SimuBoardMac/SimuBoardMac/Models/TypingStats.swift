import Foundation

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

struct TypingBucket: Equatable, Identifiable, Sendable {
    let index: Int
    let start: Date
    let characterCount: Int64

    var id: Int { index }
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

struct TypingApplicationIdentity: Equatable, Hashable, Sendable {
    let processKey: String
    let displayName: String
    let processName: String
    let bundleIdentifier: String?

    static let unknown = TypingApplicationIdentity(
        processKey: "unknown",
        displayName: "未知应用",
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
    let recentBuckets: [TypingBucket]
    let apps: [TypingAppSummary]
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
