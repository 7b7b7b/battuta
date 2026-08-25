import Foundation
import SQLite3

private final class TypingStatsSQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close_v2(pointer)
    }
}

protocol TypingStatsPersistence: Sendable {
    func record(_ batch: TypingStatsWriteBatch) async throws
    func loadSnapshot(timelineRange: TypingTimelineRange) async throws -> TypingStatsSnapshot
    func loadSnapshot(request: TypingStatsSnapshotRequest) async throws -> TypingStatsSnapshot
    func loadReport(
        range: TypingDateRange,
        comparisonRange: TypingDateRange?
    ) async throws -> TypingRangeReportSnapshot
    func clearAll() async throws
}

extension TypingStatsPersistence {
    func loadSnapshot() async throws -> TypingStatsSnapshot {
        try await loadSnapshot(timelineRange: .oneHour)
    }

    func loadSnapshot(request: TypingStatsSnapshotRequest) async throws -> TypingStatsSnapshot {
        try await loadSnapshot(timelineRange: request.timelineRange)
    }

    func loadReport(range: TypingDateRange) async throws -> TypingRangeReportSnapshot {
        try await loadReport(range: range, comparisonRange: nil)
    }

    func loadReport(
        range: TypingDateRange,
        comparisonRange: TypingDateRange?
    ) async throws -> TypingRangeReportSnapshot {
        throw TypingStatsStoreError.queryFailed("此统计数据源不支持历史区间报告。")
    }
}

enum TypingStatsStoreError: Error, Equatable, LocalizedError, Sendable {
    case cannotCreateDirectory(String)
    case cannotOpen(String)
    case incompatibleSchema
    case busy
    case corrupt
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case let .cannotCreateDirectory(message):
            "无法创建 Battuta 统计目录：\(message)"
        case let .cannotOpen(message):
            "无法打开 Battuta 本地统计：\(message)"
        case .incompatibleSchema:
            "Battuta 本地统计数据库版本不兼容。"
        case .busy:
            "本地统计数据库暂时繁忙，请稍后重试。"
        case .corrupt:
            "本地统计数据库无法读取或已经损坏。"
        case let .queryFailed(message):
            "读取 Battuta 本地统计失败：\(message)"
        }
    }
}

actor TypingStatsStore: TypingStatsPersistence {
    private struct RecentTimelineData {
        let buckets: [TypingBucket]
        let appTimelines: [TypingAppTimeline]
    }

    private struct NormalizedDateRange {
        let value: TypingDateRange
        let startKey: String
        let endKey: String
        let dayCount: Int
    }

    private struct ApplicationRangeValue {
        let application: TypingApplicationIdentity
        let characterCount: Int64
        let activeDayCount: Int
    }

    private static let schemaVersion: Int64 = 2
    private static let historyDayCount = 14
    private static let detailedRetentionDays = 31

    let databaseURL: URL
    private let nowProvider: @Sendable () -> Date
    private var connection: TypingStatsSQLiteConnection?
    private var cachedApplicationIDs: [String: Int64] = [:]
    private var lastCleanupDateKey: String?

    init(
        databaseURL: URL = TypingStatsStore.defaultDatabaseURL(),
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.databaseURL = databaseURL
        self.nowProvider = nowProvider
    }

    nonisolated static func defaultDatabaseURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("SimuBoard", isDirectory: true)
            .appendingPathComponent("typing-stats.sqlite3", isDirectory: false)
    }

    func record(_ batch: TypingStatsWriteBatch) async throws {
        guard !batch.isEmpty else { return }
        let database = try openDatabaseIfNeeded()
        let updatedAt = Int64(nowProvider().timeIntervalSince1970)

        try execute("BEGIN IMMEDIATE;", in: database)
        do {
            var resolvedApplications: [TypingApplicationIdentity: Int64] = [:]
            for aggregate in batch.characterAggregates where aggregate.count > 0 {
                let applicationID: Int64
                if let cached = resolvedApplications[aggregate.application] {
                    applicationID = cached
                } else {
                    applicationID = try upsertApplication(
                        aggregate.application,
                        updatedAt: updatedAt,
                        in: database
                    )
                    resolvedApplications[aggregate.application] = applicationID
                }
                try upsertCharacterAggregate(
                    aggregate,
                    applicationID: applicationID,
                    updatedAt: updatedAt,
                    in: database
                )
            }

            for aggregate in batch.keyAggregates where aggregate.count > 0 {
                try upsertKeyAggregate(aggregate, updatedAt: updatedAt, in: database)
            }

            let cleanupDateKey = try performCleanupIfNeeded(now: nowProvider(), in: database)
            try execute("COMMIT;", in: database)
            if let cleanupDateKey {
                lastCleanupDateKey = cleanupDateKey
                cachedApplicationIDs.removeAll(keepingCapacity: true)
            }
        } catch {
            try? execute("ROLLBACK;", in: database)
            cachedApplicationIDs.removeAll(keepingCapacity: true)
            throw error
        }
    }

    func loadSnapshot(timelineRange: TypingTimelineRange) async throws -> TypingStatsSnapshot {
        try await loadSnapshot(
            request: TypingStatsSnapshotRequest(
                timelineRange: timelineRange,
                sections: .all
            )
        )
    }

    func loadSnapshot(request: TypingStatsSnapshotRequest) async throws -> TypingStatsSnapshot {
        let database = try openDatabaseIfNeeded()
        let now = nowProvider()
        let calendar = Self.statisticsCalendar
        let todayKey = Self.dateKey(for: now, calendar: calendar)
        let sections = request.sections
        let needsRecentTimeline = !sections.intersection([.recentBuckets, .recentAppTimelines]).isEmpty

        try execute("BEGIN;", in: database)
        do {
            let rankedApps = sections.contains(.applications)
                ? try loadApps(dateKey: todayKey, limit: 100, from: database)
                : []
            let recentTimeline = needsRecentTimeline
                ? try loadRecentTimeline(
                    now: now,
                    range: request.timelineRange,
                    from: database
                )
                : RecentTimelineData(buckets: [], appTimelines: [])
            let snapshot = TypingStatsSnapshot(
                generatedAt: now,
                lastInputAt: try loadLastInputDate(from: database),
                today: try loadDaySummary(
                    dateKey: todayKey,
                    date: calendar.startOfDay(for: now),
                    from: database
                ),
                timelineRange: request.timelineRange,
                recentBuckets: sections.contains(.recentBuckets) ? recentTimeline.buckets : [],
                apps: sections.contains(.applications) ? Array(rankedApps.prefix(20)) : [],
                recentAppTimelines: sections.contains(.recentAppTimelines) ? recentTimeline.appTimelines : [],
                history: sections.contains(.history)
                    ? try loadHistory(now: now, calendar: calendar, from: database)
                    : [],
                todayKeyCounts: sections.contains(.keyCounts)
                    ? try loadKeyCounts(dateKey: todayKey, from: database)
                    : [:],
                allTimeKeyCounts: sections.contains(.keyCounts)
                    ? try loadAllTimeKeyCounts(from: database)
                    : [:]
            )
            try execute("COMMIT;", in: database)
            return snapshot
        } catch {
            try? execute("ROLLBACK;", in: database)
            throw error
        }
    }

    func loadReport(
        range: TypingDateRange,
        comparisonRange: TypingDateRange?
    ) async throws -> TypingRangeReportSnapshot {
        let database = try openDatabaseIfNeeded()
        let generatedAt = nowProvider()
        let calendar = Self.statisticsCalendar
        let selected = Self.normalized(range: range, calendar: calendar)
        let comparison = comparisonRange.map {
            Self.normalized(range: $0, calendar: calendar)
        }

        // A single deferred transaction pins every current/comparison/coverage
        // SELECT to the same WAL snapshot without taking a writer lock.
        try execute("BEGIN;", in: database)
        do {
            let days = try loadRangeDays(range: selected, calendar: calendar, from: database)
            let weekdays = Self.weekdayDistribution(days: days, calendar: calendar)
            let hours = try loadHourDistribution(range: selected, from: database)
            let weekdayHourCounts = try loadWeekdayHourCounts(
                range: selected,
                from: database
            )
            let metrics = Self.rangeMetrics(
                days: days,
                weekdays: weekdays,
                hours: hours
            )

            let comparisonDays: [TypingDaySummary]
            let comparisonMetrics: TypingRangeMetrics?
            let comparisonWeekdayHourCounts: [Int: Int64]
            if let comparison {
                comparisonDays = try loadRangeDays(
                    range: comparison,
                    calendar: calendar,
                    from: database
                )
                let comparisonWeekdays = Self.weekdayDistribution(
                    days: comparisonDays,
                    calendar: calendar
                )
                let comparisonHours = try loadHourDistribution(
                    range: comparison,
                    from: database
                )
                comparisonMetrics = Self.rangeMetrics(
                    days: comparisonDays,
                    weekdays: comparisonWeekdays,
                    hours: comparisonHours
                )
                comparisonWeekdayHourCounts = try loadWeekdayHourCounts(
                    range: comparison,
                    from: database
                )
            } else {
                comparisonDays = []
                comparisonMetrics = nil
                comparisonWeekdayHourCounts = [:]
            }

            let currentApplications = try loadApplicationRangeValues(
                range: selected,
                from: database
            )
            let comparisonApplications = try comparison.map {
                try loadApplicationRangeValues(range: $0, from: database)
            } ?? [:]
            let applications = Self.mergeApplicationRangeValues(
                current: currentApplications,
                comparison: comparisonApplications,
                currentTotal: metrics.characterCount,
                comparisonTotal: comparisonMetrics?.characterCount ?? 0
            )
            let coverage = try loadDataCoverage(
                range: selected,
                recordedDayCount: metrics.activeDayCount,
                calendar: calendar,
                from: database
            )

            let snapshot = TypingRangeReportSnapshot(
                generatedAt: generatedAt,
                range: selected.value,
                comparisonRange: comparison?.value,
                metrics: metrics,
                comparisonMetrics: comparisonMetrics,
                days: days,
                weekdayDistribution: weekdays,
                hourlyDistribution: hours,
                weekdayHourDistribution: Self.weekdayHourDistribution(
                    current: weekdayHourCounts,
                    comparison: comparisonWeekdayHourCounts
                ),
                applications: applications,
                coverage: coverage
            )
            try execute("COMMIT;", in: database)
            return snapshot
        } catch {
            try? execute("ROLLBACK;", in: database)
            throw error
        }
    }

    func clearAll() async throws {
        let database = try openDatabaseIfNeeded()
        try execute("PRAGMA secure_delete = ON;", in: database)
        try execute("BEGIN IMMEDIATE;", in: database)
        do {
            try execute("DELETE FROM CharacterSecondStat;", in: database)
            try execute("DELETE FROM KeyDailyStat;", in: database)
            try execute("DELETE FROM KeyTotalStat;", in: database)
            try execute("DELETE FROM HourDayStat;", in: database)
            try execute("DELETE FROM AppDayStat;", in: database)
            try execute("DELETE FROM DayStat;", in: database)
            try execute("DELETE FROM AppProfile;", in: database)
            try execute("COMMIT;", in: database)
            cachedApplicationIDs.removeAll(keepingCapacity: true)
            lastCleanupDateKey = nil
        } catch {
            try? execute("ROLLBACK;", in: database)
            cachedApplicationIDs.removeAll(keepingCapacity: true)
            throw error
        }

        // The logical deletion above is authoritative; these are best-effort file compaction steps.
        try? execute("PRAGMA wal_checkpoint(TRUNCATE);", in: database)
        try? execute("VACUUM;", in: database)
    }

    private func openDatabaseIfNeeded() throws -> OpaquePointer {
        if let connection { return connection.pointer }

        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw TypingStatsStoreError.cannotCreateDirectory(error.localizedDescription)
        }

        var openedDatabase: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &openedDatabase, flags, nil)
        guard result == SQLITE_OK, let openedDatabase else {
            let message = openedDatabase.map { String(cString: sqlite3_errmsg($0)) }
                ?? "SQLite \(result)"
            if let openedDatabase { sqlite3_close_v2(openedDatabase) }
            throw mapSQLiteError(code: result, message: message)
        }

        do {
            sqlite3_extended_result_codes(openedDatabase, 1)
            sqlite3_busy_timeout(openedDatabase, 1_000)
            try execute("PRAGMA foreign_keys = ON;", in: openedDatabase)
            try execute("PRAGMA journal_mode = WAL;", in: openedDatabase)
            try execute("PRAGMA synchronous = NORMAL;", in: openedDatabase)
            try migrateIfNeeded(openedDatabase)
            connection = TypingStatsSQLiteConnection(pointer: openedDatabase)
            return openedDatabase
        } catch {
            sqlite3_close_v2(openedDatabase)
            throw error
        }
    }

    private func migrateIfNeeded(_ database: OpaquePointer) throws {
        let version = try userVersion(in: database)
        guard version <= Self.schemaVersion else {
            throw TypingStatsStoreError.incompatibleSchema
        }

        if version == 0 {
            try execute("BEGIN IMMEDIATE;", in: database)
            do {
                try execute(
                    """
                    CREATE TABLE IF NOT EXISTS AppProfile (
                        Id INTEGER PRIMARY KEY,
                        ProcessKey TEXT NOT NULL UNIQUE,
                        ProcessName TEXT NOT NULL,
                        DisplayName TEXT NOT NULL,
                        BundleIdentifier TEXT,
                        UpdatedAtUtc INTEGER NOT NULL
                    );
                    CREATE TABLE IF NOT EXISTS CharacterSecondStat (
                        SecondStartUtc INTEGER NOT NULL,
                        LocalDate TEXT NOT NULL,
                        LocalHour INTEGER NOT NULL CHECK(LocalHour BETWEEN 0 AND 23),
                        AppId INTEGER NOT NULL REFERENCES AppProfile(Id),
                        CharacterCount INTEGER NOT NULL CHECK(CharacterCount >= 0),
                        UpdatedAtUtc INTEGER NOT NULL,
                        PRIMARY KEY (SecondStartUtc, AppId)
                    ) WITHOUT ROWID;
                    CREATE INDEX IF NOT EXISTS IX_CharacterSecondStat_Date
                        ON CharacterSecondStat(LocalDate, SecondStartUtc);
                    CREATE INDEX IF NOT EXISTS IX_CharacterSecondStat_DateApp
                        ON CharacterSecondStat(LocalDate, AppId);
                    CREATE TABLE IF NOT EXISTS KeyDailyStat (
                        LocalDate TEXT NOT NULL,
                        KeyCode INTEGER NOT NULL,
                        PressCount INTEGER NOT NULL CHECK(PressCount >= 0),
                        UpdatedAtUtc INTEGER NOT NULL,
                        PRIMARY KEY (LocalDate, KeyCode)
                    ) WITHOUT ROWID;
                    CREATE TABLE IF NOT EXISTS KeyTotalStat (
                        KeyCode INTEGER PRIMARY KEY,
                        PressCount INTEGER NOT NULL CHECK(PressCount >= 0),
                        UpdatedAtUtc INTEGER NOT NULL
                    );
                    """,
                    in: database
                )
                try createPermanentAggregateSchema(in: database)
                try execute("PRAGMA user_version = 2;", in: database)
                try execute("COMMIT;", in: database)
            } catch {
                try? execute("ROLLBACK;", in: database)
                throw error
            }
        }

        if version == 1 {
            try execute("BEGIN IMMEDIATE;", in: database)
            do {
                let secondColumns = try columnNames(
                    in: "CharacterSecondStat",
                    database: database
                )
                if !secondColumns.contains("LocalHour") {
                    try execute(
                        "ALTER TABLE CharacterSecondStat ADD COLUMN LocalHour INTEGER NOT NULL DEFAULT 0;",
                        in: database
                    )
                    try execute(
                        """
                        UPDATE CharacterSecondStat
                        SET LocalHour = CAST(strftime('%H', SecondStartUtc, 'unixepoch', 'localtime') AS INTEGER);
                        """,
                        in: database
                    )
                }
                try createPermanentAggregateSchema(in: database)
                try backfillPermanentAggregates(in: database)
                try execute("PRAGMA user_version = 2;", in: database)
                try execute("COMMIT;", in: database)
            } catch {
                try? execute("ROLLBACK;", in: database)
                throw error
            }
        }

        try validateSchema(in: database)
    }

    private func createPermanentAggregateSchema(in database: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS DayStat (
                LocalDate TEXT PRIMARY KEY,
                CharacterCount INTEGER NOT NULL CHECK(CharacterCount >= 0),
                ActiveMinuteBuckets INTEGER NOT NULL CHECK(ActiveMinuteBuckets >= 0),
                ActiveSeconds INTEGER NOT NULL CHECK(ActiveSeconds >= 0),
                PeakCPS INTEGER NOT NULL CHECK(PeakCPS >= 0),
                LastInputUtc INTEGER NOT NULL,
                UpdatedAtUtc INTEGER NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS AppDayStat (
                LocalDate TEXT NOT NULL,
                AppId INTEGER NOT NULL REFERENCES AppProfile(Id),
                CharacterCount INTEGER NOT NULL CHECK(CharacterCount >= 0),
                ActiveMinuteBuckets INTEGER NOT NULL CHECK(ActiveMinuteBuckets >= 0),
                ActiveSeconds INTEGER NOT NULL CHECK(ActiveSeconds >= 0),
                PeakCPS INTEGER NOT NULL CHECK(PeakCPS >= 0),
                UpdatedAtUtc INTEGER NOT NULL,
                PRIMARY KEY (LocalDate, AppId)
            ) WITHOUT ROWID;
            CREATE INDEX IF NOT EXISTS IX_AppDayStat_AppDate
                ON AppDayStat(AppId, LocalDate);
            CREATE TABLE IF NOT EXISTS HourDayStat (
                LocalDate TEXT NOT NULL,
                LocalHour INTEGER NOT NULL CHECK(LocalHour BETWEEN 0 AND 23),
                CharacterCount INTEGER NOT NULL CHECK(CharacterCount >= 0),
                ActiveMinuteBuckets INTEGER NOT NULL CHECK(ActiveMinuteBuckets >= 0),
                ActiveSeconds INTEGER NOT NULL CHECK(ActiveSeconds >= 0),
                PeakCPS INTEGER NOT NULL CHECK(PeakCPS >= 0),
                UpdatedAtUtc INTEGER NOT NULL,
                PRIMARY KEY (LocalDate, LocalHour)
            ) WITHOUT ROWID;

            CREATE TRIGGER IF NOT EXISTS TR_CharacterSecondStat_AggregateInsert
            AFTER INSERT ON CharacterSecondStat
            BEGIN
                INSERT INTO DayStat (
                    LocalDate, CharacterCount, ActiveMinuteBuckets, ActiveSeconds,
                    PeakCPS, LastInputUtc, UpdatedAtUtc
                ) VALUES (
                    NEW.LocalDate,
                    NEW.CharacterCount,
                    CASE WHEN (
                        SELECT COUNT(*) FROM CharacterSecondStat
                        WHERE LocalDate = NEW.LocalDate
                          AND SecondStartUtc / 60 = NEW.SecondStartUtc / 60
                    ) = 1 THEN 1 ELSE 0 END,
                    CASE WHEN (
                        SELECT COUNT(*) FROM CharacterSecondStat
                        WHERE LocalDate = NEW.LocalDate
                          AND SecondStartUtc = NEW.SecondStartUtc
                    ) = 1 THEN 1 ELSE 0 END,
                    (SELECT COALESCE(SUM(CharacterCount), 0) FROM CharacterSecondStat
                     WHERE LocalDate = NEW.LocalDate
                       AND SecondStartUtc = NEW.SecondStartUtc),
                    NEW.SecondStartUtc,
                    NEW.UpdatedAtUtc
                ) ON CONFLICT(LocalDate) DO UPDATE SET
                    CharacterCount = DayStat.CharacterCount + excluded.CharacterCount,
                    ActiveMinuteBuckets = DayStat.ActiveMinuteBuckets
                        + excluded.ActiveMinuteBuckets,
                    ActiveSeconds = DayStat.ActiveSeconds + excluded.ActiveSeconds,
                    PeakCPS = MAX(DayStat.PeakCPS, excluded.PeakCPS),
                    LastInputUtc = MAX(DayStat.LastInputUtc, excluded.LastInputUtc),
                    UpdatedAtUtc = MAX(DayStat.UpdatedAtUtc, excluded.UpdatedAtUtc);

                INSERT INTO AppDayStat (
                    LocalDate, AppId, CharacterCount, ActiveMinuteBuckets,
                    ActiveSeconds, PeakCPS, UpdatedAtUtc
                ) VALUES (
                    NEW.LocalDate,
                    NEW.AppId,
                    NEW.CharacterCount,
                    CASE WHEN (
                        SELECT COUNT(*) FROM CharacterSecondStat
                        WHERE LocalDate = NEW.LocalDate
                          AND AppId = NEW.AppId
                          AND SecondStartUtc / 60 = NEW.SecondStartUtc / 60
                    ) = 1 THEN 1 ELSE 0 END,
                    1,
                    NEW.CharacterCount,
                    NEW.UpdatedAtUtc
                ) ON CONFLICT(LocalDate, AppId) DO UPDATE SET
                    CharacterCount = AppDayStat.CharacterCount + excluded.CharacterCount,
                    ActiveMinuteBuckets = AppDayStat.ActiveMinuteBuckets
                        + excluded.ActiveMinuteBuckets,
                    ActiveSeconds = AppDayStat.ActiveSeconds + excluded.ActiveSeconds,
                    PeakCPS = MAX(AppDayStat.PeakCPS, excluded.PeakCPS),
                    UpdatedAtUtc = MAX(AppDayStat.UpdatedAtUtc, excluded.UpdatedAtUtc);

                INSERT INTO HourDayStat (
                    LocalDate, LocalHour, CharacterCount, ActiveMinuteBuckets,
                    ActiveSeconds, PeakCPS, UpdatedAtUtc
                ) VALUES (
                    NEW.LocalDate,
                    NEW.LocalHour,
                    NEW.CharacterCount,
                    CASE WHEN (
                        SELECT COUNT(*) FROM CharacterSecondStat
                        WHERE LocalDate = NEW.LocalDate
                          AND LocalHour = NEW.LocalHour
                          AND SecondStartUtc / 60 = NEW.SecondStartUtc / 60
                    ) = 1 THEN 1 ELSE 0 END,
                    CASE WHEN (
                        SELECT COUNT(*) FROM CharacterSecondStat
                        WHERE LocalDate = NEW.LocalDate
                          AND LocalHour = NEW.LocalHour
                          AND SecondStartUtc = NEW.SecondStartUtc
                    ) = 1 THEN 1 ELSE 0 END,
                    (SELECT COALESCE(SUM(CharacterCount), 0) FROM CharacterSecondStat
                     WHERE LocalDate = NEW.LocalDate
                       AND LocalHour = NEW.LocalHour
                       AND SecondStartUtc = NEW.SecondStartUtc),
                    NEW.UpdatedAtUtc
                ) ON CONFLICT(LocalDate, LocalHour) DO UPDATE SET
                    CharacterCount = HourDayStat.CharacterCount + excluded.CharacterCount,
                    ActiveMinuteBuckets = HourDayStat.ActiveMinuteBuckets
                        + excluded.ActiveMinuteBuckets,
                    ActiveSeconds = HourDayStat.ActiveSeconds + excluded.ActiveSeconds,
                    PeakCPS = MAX(HourDayStat.PeakCPS, excluded.PeakCPS),
                    UpdatedAtUtc = MAX(HourDayStat.UpdatedAtUtc, excluded.UpdatedAtUtc);
            END;

            CREATE TRIGGER IF NOT EXISTS TR_CharacterSecondStat_AggregateUpdate
            AFTER UPDATE OF CharacterCount ON CharacterSecondStat
            BEGIN
                UPDATE DayStat SET
                    CharacterCount = CharacterCount + NEW.CharacterCount - OLD.CharacterCount,
                    PeakCPS = MAX(
                        PeakCPS,
                        (SELECT COALESCE(SUM(CharacterCount), 0)
                         FROM CharacterSecondStat
                         WHERE LocalDate = NEW.LocalDate
                           AND SecondStartUtc = NEW.SecondStartUtc)
                    ),
                    LastInputUtc = MAX(LastInputUtc, NEW.SecondStartUtc),
                    UpdatedAtUtc = MAX(UpdatedAtUtc, NEW.UpdatedAtUtc)
                WHERE LocalDate = NEW.LocalDate;

                UPDATE AppDayStat SET
                    CharacterCount = CharacterCount + NEW.CharacterCount - OLD.CharacterCount,
                    PeakCPS = MAX(PeakCPS, NEW.CharacterCount),
                    UpdatedAtUtc = MAX(UpdatedAtUtc, NEW.UpdatedAtUtc)
                WHERE LocalDate = NEW.LocalDate AND AppId = NEW.AppId;

                UPDATE HourDayStat SET
                    CharacterCount = CharacterCount + NEW.CharacterCount - OLD.CharacterCount,
                    PeakCPS = MAX(
                        PeakCPS,
                        (SELECT COALESCE(SUM(CharacterCount), 0)
                         FROM CharacterSecondStat
                         WHERE LocalDate = NEW.LocalDate
                           AND LocalHour = NEW.LocalHour
                           AND SecondStartUtc = NEW.SecondStartUtc)
                    ),
                    UpdatedAtUtc = MAX(UpdatedAtUtc, NEW.UpdatedAtUtc)
                WHERE LocalDate = NEW.LocalDate AND LocalHour = NEW.LocalHour;
            END;
            """,
            in: database
        )
    }

    private func backfillPermanentAggregates(in database: OpaquePointer) throws {
        try execute(
            """
            DELETE FROM HourDayStat;
            DELETE FROM AppDayStat;
            DELETE FROM DayStat;

            INSERT INTO DayStat (
                LocalDate, CharacterCount, ActiveMinuteBuckets, ActiveSeconds,
                PeakCPS, LastInputUtc, UpdatedAtUtc
            )
            SELECT LocalDate,
                   SUM(CharacterCount),
                   COUNT(DISTINCT SecondStartUtc / 60),
                   COUNT(DISTINCT SecondStartUtc),
                   0,
                   MAX(SecondStartUtc),
                   MAX(UpdatedAtUtc)
            FROM CharacterSecondStat
            GROUP BY LocalDate;
            UPDATE DayStat
            SET PeakCPS = COALESCE((
                SELECT MAX(CharactersPerSecond)
                FROM (
                    SELECT SUM(CharacterCount) AS CharactersPerSecond
                    FROM CharacterSecondStat
                    WHERE LocalDate = DayStat.LocalDate
                    GROUP BY SecondStartUtc
                )
            ), 0);

            INSERT INTO AppDayStat (
                LocalDate, AppId, CharacterCount, ActiveMinuteBuckets,
                ActiveSeconds, PeakCPS, UpdatedAtUtc
            )
            SELECT LocalDate,
                   AppId,
                   SUM(CharacterCount),
                   COUNT(DISTINCT SecondStartUtc / 60),
                   COUNT(DISTINCT SecondStartUtc),
                   MAX(CharacterCount),
                   MAX(UpdatedAtUtc)
            FROM CharacterSecondStat
            GROUP BY LocalDate, AppId;

            INSERT INTO HourDayStat (
                LocalDate, LocalHour, CharacterCount, ActiveMinuteBuckets,
                ActiveSeconds, PeakCPS, UpdatedAtUtc
            )
            SELECT LocalDate,
                   LocalHour,
                   SUM(CharacterCount),
                   COUNT(DISTINCT SecondStartUtc / 60),
                   COUNT(DISTINCT SecondStartUtc),
                   0,
                   MAX(UpdatedAtUtc)
            FROM CharacterSecondStat
            GROUP BY LocalDate, LocalHour;
            UPDATE HourDayStat
            SET PeakCPS = COALESCE((
                SELECT MAX(CharactersPerSecond)
                FROM (
                    SELECT SUM(stat.CharacterCount) AS CharactersPerSecond
                    FROM CharacterSecondStat stat
                    WHERE stat.LocalDate = HourDayStat.LocalDate
                      AND stat.LocalHour = HourDayStat.LocalHour
                    GROUP BY stat.SecondStartUtc
                )
            ), 0);
            """,
            in: database
        )
    }

    private func validateSchema(in database: OpaquePointer) throws {
        let requiredSchema: [String: Set<String>] = [
            "AppProfile": [
                "Id", "ProcessKey", "ProcessName", "DisplayName", "BundleIdentifier",
                "UpdatedAtUtc",
            ],
            "CharacterSecondStat": [
                "SecondStartUtc", "LocalDate", "LocalHour", "AppId", "CharacterCount",
                "UpdatedAtUtc",
            ],
            "KeyDailyStat": ["LocalDate", "KeyCode", "PressCount", "UpdatedAtUtc"],
            "KeyTotalStat": ["KeyCode", "PressCount", "UpdatedAtUtc"],
            "DayStat": [
                "LocalDate", "CharacterCount", "ActiveMinuteBuckets", "ActiveSeconds",
                "PeakCPS", "LastInputUtc", "UpdatedAtUtc",
            ],
            "AppDayStat": [
                "LocalDate", "AppId", "CharacterCount", "ActiveMinuteBuckets",
                "ActiveSeconds", "PeakCPS", "UpdatedAtUtc",
            ],
            "HourDayStat": [
                "LocalDate", "LocalHour", "CharacterCount", "ActiveMinuteBuckets",
                "ActiveSeconds", "PeakCPS", "UpdatedAtUtc",
            ],
        ]

        for (table, requiredColumns) in requiredSchema {
            let availableColumns = try columnNames(in: table, database: database)
            guard requiredColumns.isSubset(of: availableColumns) else {
                throw TypingStatsStoreError.incompatibleSchema
            }
        }
    }

    private func userVersion(in database: OpaquePointer) throws -> Int64 {
        let statement = try prepare("PRAGMA user_version;", in: database)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else { throw queryError(database, code: result) }
        return sqlite3_column_int64(statement, 0)
    }

    private func columnNames(in table: String, database: OpaquePointer) throws -> Set<String> {
        let statement = try prepare("SELECT name FROM pragma_table_info(?1);", in: database)
        defer { sqlite3_finalize(statement) }
        try bind(table, at: 1, to: statement, in: database)

        var names: Set<String> = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return names }
            guard result == SQLITE_ROW else { throw queryError(database, code: result) }
            if let name = text(at: 0, in: statement) { names.insert(name) }
        }
    }

    private func upsertApplication(
        _ application: TypingApplicationIdentity,
        updatedAt: Int64,
        in database: OpaquePointer
    ) throws -> Int64 {
        let upsert = try prepare(
            """
            INSERT INTO AppProfile (
                ProcessKey, ProcessName, DisplayName, BundleIdentifier, UpdatedAtUtc
            ) VALUES (?1, ?2, ?3, ?4, ?5)
            ON CONFLICT(ProcessKey) DO UPDATE SET
                ProcessName = excluded.ProcessName,
                DisplayName = excluded.DisplayName,
                BundleIdentifier = excluded.BundleIdentifier,
                UpdatedAtUtc = excluded.UpdatedAtUtc;
            """,
            in: database
        )
        defer { sqlite3_finalize(upsert) }
        try bind(application.processKey, at: 1, to: upsert, in: database)
        try bind(application.processName, at: 2, to: upsert, in: database)
        try bind(application.displayName, at: 3, to: upsert, in: database)
        try bind(application.bundleIdentifier, at: 4, to: upsert, in: database)
        try bind(updatedAt, at: 5, to: upsert, in: database)
        try stepToCompletion(upsert, in: database)

        if let cached = cachedApplicationIDs[application.processKey] { return cached }

        let select = try prepare(
            "SELECT Id FROM AppProfile WHERE ProcessKey = ?1 LIMIT 1;",
            in: database
        )
        defer { sqlite3_finalize(select) }
        try bind(application.processKey, at: 1, to: select, in: database)
        let result = sqlite3_step(select)
        guard result == SQLITE_ROW else { throw queryError(database, code: result) }
        let identifier = sqlite3_column_int64(select, 0)
        cachedApplicationIDs[application.processKey] = identifier
        return identifier
    }

    private func upsertCharacterAggregate(
        _ aggregate: TypingCharacterAggregate,
        applicationID: Int64,
        updatedAt: Int64,
        in database: OpaquePointer
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO CharacterSecondStat (
                SecondStartUtc, LocalDate, LocalHour, AppId, CharacterCount, UpdatedAtUtc
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            ON CONFLICT(SecondStartUtc, AppId) DO UPDATE SET
                CharacterCount = CharacterCount + excluded.CharacterCount,
                UpdatedAtUtc = excluded.UpdatedAtUtc;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(aggregate.secondStart, at: 1, to: statement, in: database)
        try bind(aggregate.localDate, at: 2, to: statement, in: database)
        try bind(Self.localHour(for: aggregate.secondStart), at: 3, to: statement, in: database)
        try bind(applicationID, at: 4, to: statement, in: database)
        try bind(aggregate.count, at: 5, to: statement, in: database)
        try bind(updatedAt, at: 6, to: statement, in: database)
        try stepToCompletion(statement, in: database)
    }

    private func upsertKeyAggregate(
        _ aggregate: TypingKeyAggregate,
        updatedAt: Int64,
        in database: OpaquePointer
    ) throws {
        let daily = try prepare(
            """
            INSERT INTO KeyDailyStat (LocalDate, KeyCode, PressCount, UpdatedAtUtc)
            VALUES (?1, ?2, ?3, ?4)
            ON CONFLICT(LocalDate, KeyCode) DO UPDATE SET
                PressCount = PressCount + excluded.PressCount,
                UpdatedAtUtc = excluded.UpdatedAtUtc;
            """,
            in: database
        )
        defer { sqlite3_finalize(daily) }
        try bind(aggregate.localDate, at: 1, to: daily, in: database)
        try bind(Int64(aggregate.keyCode), at: 2, to: daily, in: database)
        try bind(aggregate.count, at: 3, to: daily, in: database)
        try bind(updatedAt, at: 4, to: daily, in: database)
        try stepToCompletion(daily, in: database)

        let total = try prepare(
            """
            INSERT INTO KeyTotalStat (KeyCode, PressCount, UpdatedAtUtc)
            VALUES (?1, ?2, ?3)
            ON CONFLICT(KeyCode) DO UPDATE SET
                PressCount = PressCount + excluded.PressCount,
                UpdatedAtUtc = excluded.UpdatedAtUtc;
            """,
            in: database
        )
        defer { sqlite3_finalize(total) }
        try bind(Int64(aggregate.keyCode), at: 1, to: total, in: database)
        try bind(aggregate.count, at: 2, to: total, in: database)
        try bind(updatedAt, at: 3, to: total, in: database)
        try stepToCompletion(total, in: database)
    }

    private func performCleanupIfNeeded(
        now: Date,
        in database: OpaquePointer
    ) throws -> String? {
        let calendar = Self.statisticsCalendar
        let todayKey = Self.dateKey(for: now, calendar: calendar)
        guard lastCleanupDateKey != todayKey else { return nil }
        guard let cutoffDate = calendar.date(
            byAdding: .day,
            value: -Self.detailedRetentionDays,
            to: calendar.startOfDay(for: now)
        ) else { return nil }
        let cutoffKey = Self.dateKey(for: cutoffDate, calendar: calendar)
        let statement = try prepare(
            "DELETE FROM CharacterSecondStat WHERE LocalDate < ?1;",
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(cutoffKey, at: 1, to: statement, in: database)
        try stepToCompletion(statement, in: database)

        // Daily and application/hour aggregates are intentionally permanent.
        // AppProfile rows remain because AppDayStat keeps their historic identity.
        return todayKey
    }

    private func loadDaySummary(
        dateKey: String,
        date: Date,
        from database: OpaquePointer
    ) throws -> TypingDaySummary {
        let totals = try prepare(
            """
            SELECT CharacterCount,
                   PeakCPS,
                   ActiveMinuteBuckets,
                   ActiveSeconds,
                   UpdatedAtUtc
            FROM DayStat
            WHERE LocalDate = ?1;
            """,
            in: database
        )
        defer { sqlite3_finalize(totals) }
        try bind(dateKey, at: 1, to: totals, in: database)
        let totalsResult = sqlite3_step(totals)
        if totalsResult == SQLITE_DONE {
            return Self.emptyDay(dateKey: dateKey, date: date)
        }
        guard totalsResult == SQLITE_ROW else { throw queryError(database, code: totalsResult) }

        return TypingDaySummary(
            dateKey: dateKey,
            date: date,
            characterCount: sqlite3_column_int64(totals, 0),
            peakCPS: sqlite3_column_int64(totals, 1),
            activeMinuteBuckets: sqlite3_column_int64(totals, 2),
            activeSeconds: sqlite3_column_int64(totals, 3),
            topAppName: try loadTopAppName(dateKey: dateKey, from: database),
            lastUpdatedAt: self.date(at: 4, in: totals)
        )
    }

    private func loadPeakCPS(dateKey: String, from database: OpaquePointer) throws -> Int64 {
        let statement = try prepare(
            "SELECT COALESCE(PeakCPS, 0) FROM DayStat WHERE LocalDate = ?1;",
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(dateKey, at: 1, to: statement, in: database)
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else { throw queryError(database, code: result) }
        return sqlite3_column_int64(statement, 0)
    }

    private func loadTopAppName(dateKey: String, from database: OpaquePointer) throws -> String? {
        let statement = try prepare(
            """
            SELECT ap.DisplayName
            FROM AppDayStat stat
            JOIN AppProfile ap ON ap.Id = stat.AppId
            WHERE stat.LocalDate = ?1
            GROUP BY stat.AppId
            ORDER BY stat.CharacterCount DESC, ap.DisplayName COLLATE NOCASE, stat.AppId
            LIMIT 1;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(dateKey, at: 1, to: statement, in: database)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw queryError(database, code: result) }
        return text(at: 0, in: statement)
    }

    private func loadRecentTimeline(
        now: Date,
        range: TypingTimelineRange,
        from database: OpaquePointer
    ) throws -> RecentTimelineData {
        let bucketSeconds = range.bucketSeconds
        let bucketCount = range.bucketCount
        // Anchor buckets to the actual rolling window. Rounding the end up to a
        // natural bucket boundary would label future time and omit the oldest
        // part of a requested range (up to two hours for the seven-day view).
        let endExclusive = Int64(now.timeIntervalSince1970) + 1
        let start = endExclusive - range.durationSeconds
        var totalCounts = Array(repeating: Int64(0), count: bucketCount)
        var identities: [String: TypingApplicationIdentity] = [:]
        var sparseAppCounts: [String: [Int: Int64]] = [:]

        let statement = try prepare(
            """
            SELECT ap.ProcessKey,
                   ap.DisplayName,
                   ap.ProcessName,
                   ap.BundleIdentifier,
                   CAST((stat.SecondStartUtc - ?1) / ?3 AS INTEGER) AS BucketIndex,
                   SUM(stat.CharacterCount)
            FROM CharacterSecondStat stat
            JOIN AppProfile ap ON ap.Id = stat.AppId
            WHERE stat.SecondStartUtc >= ?1 AND stat.SecondStartUtc < ?2
            GROUP BY stat.AppId, BucketIndex
            ORDER BY stat.AppId, BucketIndex;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(start, at: 1, to: statement, in: database)
        try bind(endExclusive, at: 2, to: statement, in: database)
        try bind(bucketSeconds, at: 3, to: statement, in: database)

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw queryError(database, code: result) }
            guard let processKey = text(at: 0, in: statement) else { continue }
            let index = Int(sqlite3_column_int64(statement, 4))
            guard totalCounts.indices.contains(index) else { continue }
            let count = sqlite3_column_int64(statement, 5)
            totalCounts[index] += count
            sparseAppCounts[processKey, default: [:]][index] = count
            identities[processKey] = TypingApplicationIdentity(
                processKey: processKey,
                displayName: text(at: 1, in: statement) ?? "未知应用",
                processName: text(at: 2, in: statement) ?? "unknown",
                bundleIdentifier: text(at: 3, in: statement)
            )
        }

        let buckets = totalCounts.indices.map { index in
            TypingBucket(
                index: index,
                start: Date(timeIntervalSince1970: TimeInterval(start + Int64(index) * bucketSeconds)),
                characterCount: totalCounts[index]
            )
        }
        let recentKeys = identities.keys.sorted { left, right in
            let leftTotal = sparseAppCounts[left, default: [:]].values.reduce(0, +)
            let rightTotal = sparseAppCounts[right, default: [:]].values.reduce(0, +)
            if leftTotal != rightTotal { return leftTotal > rightTotal }
            let leftName = identities[left]?.displayName ?? left
            let rightName = identities[right]?.displayName ?? right
            let nameOrder = leftName.localizedCaseInsensitiveCompare(rightName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return left < right
        }
        let timelines = recentKeys.prefix(20).compactMap { processKey -> TypingAppTimeline? in
            let application = identities[processKey]
            guard let application else { return nil }
            let counts = sparseAppCounts[processKey, default: [:]]
            return TypingAppTimeline(
                application: application,
                buckets: (0..<bucketCount).map { index in
                    TypingBucket(
                        index: index,
                        start: Date(
                            timeIntervalSince1970: TimeInterval(start + Int64(index) * bucketSeconds)
                        ),
                        characterCount: counts[index, default: 0]
                    )
                }
            )
        }

        return RecentTimelineData(
            buckets: buckets,
            appTimelines: timelines
        )
    }

    private func loadApps(
        dateKey: String,
        limit: Int,
        from database: OpaquePointer
    ) throws -> [TypingAppSummary] {
        let statement = try prepare(
            """
            SELECT ap.ProcessKey,
                   ap.DisplayName,
                   ap.ProcessName,
                   ap.BundleIdentifier,
                   stat.CharacterCount AS Characters,
                   stat.ActiveMinuteBuckets AS ActiveMinutes,
                   stat.ActiveSeconds AS ActiveSeconds,
                   stat.PeakCPS AS PeakCPS
            FROM AppDayStat stat
            JOIN AppProfile ap ON ap.Id = stat.AppId
            WHERE stat.LocalDate = ?1
            GROUP BY stat.AppId
            ORDER BY Characters DESC, ap.DisplayName COLLATE NOCASE, stat.AppId
            LIMIT ?2;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(dateKey, at: 1, to: statement, in: database)
        try bind(Int64(max(1, min(limit, 100))), at: 2, to: statement, in: database)

        var output: [TypingAppSummary] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return output }
            guard result == SQLITE_ROW else { throw queryError(database, code: result) }
            output.append(TypingAppSummary(
                processKey: text(at: 0, in: statement) ?? "unknown:\(output.count)",
                displayName: text(at: 1, in: statement) ?? "未知应用",
                processName: text(at: 2, in: statement) ?? "unknown",
                bundleIdentifier: text(at: 3, in: statement),
                characterCount: sqlite3_column_int64(statement, 4),
                activeMinuteBuckets: sqlite3_column_int64(statement, 5),
                activeSeconds: sqlite3_column_int64(statement, 6),
                peakCPS: sqlite3_column_int64(statement, 7)
            ))
        }
    }

    private func loadHistory(
        now: Date,
        calendar: Calendar,
        from database: OpaquePointer
    ) throws -> [TypingDaySummary] {
        let today = calendar.startOfDay(for: now)
        guard let startDate = calendar.date(
            byAdding: .day,
            value: -(Self.historyDayCount - 1),
            to: today
        ) else { return [] }
        let startKey = Self.dateKey(for: startDate, calendar: calendar)
        let endKey = Self.dateKey(for: today, calendar: calendar)

        var stored: [String: TypingDaySummary] = [:]
        let totals = try prepare(
            """
            SELECT LocalDate,
                   CharacterCount,
                   PeakCPS,
                   ActiveMinuteBuckets,
                   ActiveSeconds,
                   UpdatedAtUtc
            FROM DayStat
            WHERE LocalDate BETWEEN ?1 AND ?2
            ORDER BY LocalDate;
            """,
            in: database
        )
        defer { sqlite3_finalize(totals) }
        try bind(startKey, at: 1, to: totals, in: database)
        try bind(endKey, at: 2, to: totals, in: database)
        while true {
            let result = sqlite3_step(totals)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw queryError(database, code: result) }
            guard let dateKey = text(at: 0, in: totals),
                  let date = Self.date(from: dateKey, calendar: calendar) else { continue }
            stored[dateKey] = TypingDaySummary(
                dateKey: dateKey,
                date: date,
                characterCount: sqlite3_column_int64(totals, 1),
                peakCPS: sqlite3_column_int64(totals, 2),
                activeMinuteBuckets: sqlite3_column_int64(totals, 3),
                activeSeconds: sqlite3_column_int64(totals, 4),
                topAppName: nil,
                lastUpdatedAt: self.date(at: 5, in: totals)
            )
        }

        let topApps = try loadDailyTopApps(startKey: startKey, endKey: endKey, from: database)
        for (dateKey, summary) in stored {
            stored[dateKey] = TypingDaySummary(
                dateKey: summary.dateKey,
                date: summary.date,
                characterCount: summary.characterCount,
                peakCPS: summary.peakCPS,
                activeMinuteBuckets: summary.activeMinuteBuckets,
                activeSeconds: summary.activeSeconds,
                topAppName: topApps[dateKey],
                lastUpdatedAt: summary.lastUpdatedAt
            )
        }

        return (0..<Self.historyDayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }
            let key = Self.dateKey(for: date, calendar: calendar)
            return stored[key] ?? Self.emptyDay(dateKey: key, date: date)
        }
    }

    private func loadDailyPeaks(
        startKey: String,
        endKey: String,
        from database: OpaquePointer
    ) throws -> [String: Int64] {
        let statement = try prepare(
            """
            SELECT LocalDate, MAX(CharactersPerSecond)
            FROM (
                SELECT LocalDate, SecondStartUtc, SUM(CharacterCount) AS CharactersPerSecond
                FROM CharacterSecondStat
                WHERE LocalDate BETWEEN ?1 AND ?2
                GROUP BY LocalDate, SecondStartUtc
            )
            GROUP BY LocalDate;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(startKey, at: 1, to: statement, in: database)
        try bind(endKey, at: 2, to: statement, in: database)
        var output: [String: Int64] = [:]
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return output }
            guard result == SQLITE_ROW else { throw queryError(database, code: result) }
            if let key = text(at: 0, in: statement) {
                output[key] = sqlite3_column_int64(statement, 1)
            }
        }
    }

    private func loadDailyTopApps(
        startKey: String,
        endKey: String,
        from database: OpaquePointer
    ) throws -> [String: String] {
        let statement = try prepare(
            """
            WITH AppTotals AS (
                SELECT stat.LocalDate, stat.AppId, stat.CharacterCount AS Characters
                FROM AppDayStat stat
                WHERE stat.LocalDate BETWEEN ?1 AND ?2
            ), Ranked AS (
                SELECT totals.LocalDate,
                       ap.DisplayName,
                       ROW_NUMBER() OVER (
                           PARTITION BY totals.LocalDate
                           ORDER BY totals.Characters DESC, ap.DisplayName COLLATE NOCASE, totals.AppId
                       ) AS Position
                FROM AppTotals totals
                JOIN AppProfile ap ON ap.Id = totals.AppId
            )
            SELECT LocalDate, DisplayName
            FROM Ranked
            WHERE Position = 1;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(startKey, at: 1, to: statement, in: database)
        try bind(endKey, at: 2, to: statement, in: database)
        var output: [String: String] = [:]
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return output }
            guard result == SQLITE_ROW else { throw queryError(database, code: result) }
            if let key = text(at: 0, in: statement), let value = text(at: 1, in: statement) {
                output[key] = value
            }
        }
    }

    private func loadRangeDays(
        range: NormalizedDateRange,
        calendar: Calendar,
        from database: OpaquePointer
    ) throws -> [TypingDaySummary] {
        var stored: [String: TypingDaySummary] = [:]
        let statement = try prepare(
            """
            SELECT LocalDate,
                   CharacterCount,
                   PeakCPS,
                   ActiveMinuteBuckets,
                   ActiveSeconds,
                   UpdatedAtUtc
            FROM DayStat
            WHERE LocalDate BETWEEN ?1 AND ?2
            ORDER BY LocalDate;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(range.startKey, at: 1, to: statement, in: database)
        try bind(range.endKey, at: 2, to: statement, in: database)
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw queryError(database, code: result) }
            guard let key = text(at: 0, in: statement),
                  let date = Self.date(from: key, calendar: calendar) else { continue }
            stored[key] = TypingDaySummary(
                dateKey: key,
                date: date,
                characterCount: sqlite3_column_int64(statement, 1),
                peakCPS: sqlite3_column_int64(statement, 2),
                activeMinuteBuckets: sqlite3_column_int64(statement, 3),
                activeSeconds: sqlite3_column_int64(statement, 4),
                topAppName: nil,
                lastUpdatedAt: self.date(at: 5, in: statement)
            )
        }

        let topApps = try loadDailyTopApps(
            startKey: range.startKey,
            endKey: range.endKey,
            from: database
        )
        return (0..<range.dayCount).compactMap { offset in
            guard let date = calendar.date(
                byAdding: .day,
                value: offset,
                to: range.value.startDate
            ) else { return nil }
            let key = Self.dateKey(for: date, calendar: calendar)
            guard let summary = stored[key] else {
                return Self.emptyDay(dateKey: key, date: date)
            }
            return TypingDaySummary(
                dateKey: summary.dateKey,
                date: summary.date,
                characterCount: summary.characterCount,
                peakCPS: summary.peakCPS,
                activeMinuteBuckets: summary.activeMinuteBuckets,
                activeSeconds: summary.activeSeconds,
                topAppName: topApps[key],
                lastUpdatedAt: summary.lastUpdatedAt
            )
        }
    }

    private func loadHourDistribution(
        range: NormalizedDateRange,
        from database: OpaquePointer
    ) throws -> [TypingHourAggregate] {
        var stored: [Int: TypingHourAggregate] = [:]
        let statement = try prepare(
            """
            SELECT LocalHour,
                   SUM(CharacterCount),
                   COUNT(DISTINCT LocalDate),
                   MAX(PeakCPS)
            FROM HourDayStat
            WHERE LocalDate BETWEEN ?1 AND ?2
            GROUP BY LocalHour
            ORDER BY LocalHour;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(range.startKey, at: 1, to: statement, in: database)
        try bind(range.endKey, at: 2, to: statement, in: database)
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw queryError(database, code: result) }
            let hour = Int(sqlite3_column_int64(statement, 0))
            guard (0...23).contains(hour) else { continue }
            stored[hour] = TypingHourAggregate(
                hour: hour,
                characterCount: sqlite3_column_int64(statement, 1),
                activeDayCount: Int(sqlite3_column_int64(statement, 2)),
                peakCPS: sqlite3_column_int64(statement, 3)
            )
        }
        return (0...23).map { hour in
            stored[hour] ?? TypingHourAggregate(
                hour: hour,
                characterCount: 0,
                activeDayCount: 0,
                peakCPS: 0
            )
        }
    }

    private func loadWeekdayHourCounts(
        range: NormalizedDateRange,
        from database: OpaquePointer
    ) throws -> [Int: Int64] {
        let statement = try prepare(
            """
            SELECT CAST(strftime('%w', LocalDate) AS INTEGER) + 1 AS FoundationWeekday,
                   LocalHour,
                   SUM(CharacterCount)
            FROM HourDayStat
            WHERE LocalDate BETWEEN ?1 AND ?2
            GROUP BY FoundationWeekday, LocalHour
            ORDER BY FoundationWeekday, LocalHour;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(range.startKey, at: 1, to: statement, in: database)
        try bind(range.endKey, at: 2, to: statement, in: database)
        var output: [Int: Int64] = [:]
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return output }
            guard result == SQLITE_ROW else { throw queryError(database, code: result) }
            let weekday = Int(sqlite3_column_int64(statement, 0))
            let hour = Int(sqlite3_column_int64(statement, 1))
            guard (1...7).contains(weekday), (0...23).contains(hour) else { continue }
            output[(weekday - 1) * 24 + hour] = sqlite3_column_int64(statement, 2)
        }
    }

    private func loadApplicationRangeValues(
        range: NormalizedDateRange,
        from database: OpaquePointer
    ) throws -> [String: ApplicationRangeValue] {
        let statement = try prepare(
            """
            SELECT ap.ProcessKey,
                   ap.DisplayName,
                   ap.ProcessName,
                   ap.BundleIdentifier,
                   SUM(stat.CharacterCount),
                   COUNT(DISTINCT stat.LocalDate)
            FROM AppDayStat stat
            JOIN AppProfile ap ON ap.Id = stat.AppId
            WHERE stat.LocalDate BETWEEN ?1 AND ?2
            GROUP BY stat.AppId
            ORDER BY SUM(stat.CharacterCount) DESC,
                     ap.DisplayName COLLATE NOCASE,
                     stat.AppId;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(range.startKey, at: 1, to: statement, in: database)
        try bind(range.endKey, at: 2, to: statement, in: database)
        var output: [String: ApplicationRangeValue] = [:]
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return output }
            guard result == SQLITE_ROW else { throw queryError(database, code: result) }
            guard let processKey = text(at: 0, in: statement) else { continue }
            output[processKey] = ApplicationRangeValue(
                application: TypingApplicationIdentity(
                    processKey: processKey,
                    displayName: text(at: 1, in: statement) ?? "未知应用",
                    processName: text(at: 2, in: statement) ?? "unknown",
                    bundleIdentifier: text(at: 3, in: statement)
                ),
                characterCount: sqlite3_column_int64(statement, 4),
                activeDayCount: Int(sqlite3_column_int64(statement, 5))
            )
        }
    }

    private func loadDataCoverage(
        range: NormalizedDateRange,
        recordedDayCount: Int,
        calendar: Calendar,
        from database: OpaquePointer
    ) throws -> TypingReportDataCoverage {
        let statement = try prepare(
            "SELECT MIN(LocalDate), MAX(LocalDate) FROM DayStat;",
            in: database
        )
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else { throw queryError(database, code: result) }
        let firstKey = text(at: 0, in: statement)
        let lastKey = text(at: 1, in: statement)
        let firstDate = firstKey.flatMap { Self.date(from: $0, calendar: calendar) }
        let lastDate = lastKey.flatMap { Self.date(from: $0, calendar: calendar) }
        let isWithin = if let firstKey, let lastKey {
            range.startKey >= firstKey && range.endKey <= lastKey
        } else {
            false
        }
        return TypingReportDataCoverage(
            firstRecordedDate: firstDate,
            lastRecordedDate: lastDate,
            requestedDayCount: range.dayCount,
            recordedDayCount: recordedDayCount,
            isRangeWithinAvailableDates: isWithin
        )
    }

    private static func normalized(
        range: TypingDateRange,
        calendar: Calendar
    ) -> NormalizedDateRange {
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        let orderedStart = min(start, end)
        let orderedEnd = max(start, end)
        let difference = calendar.dateComponents(
            [.day],
            from: orderedStart,
            to: orderedEnd
        ).day ?? 0
        let value = TypingDateRange(startDate: orderedStart, endDate: orderedEnd)
        return NormalizedDateRange(
            value: value,
            startKey: dateKey(for: orderedStart, calendar: calendar),
            endKey: dateKey(for: orderedEnd, calendar: calendar),
            dayCount: max(1, difference + 1)
        )
    }

    private static func weekdayDistribution(
        days: [TypingDaySummary],
        calendar: Calendar
    ) -> [TypingWeekdayAggregate] {
        var counts = Array(repeating: Int64(0), count: 7)
        var activeDays = Array(repeating: 0, count: 7)
        for day in days {
            let weekday = calendar.component(.weekday, from: day.date)
            guard (1...7).contains(weekday) else { continue }
            counts[weekday - 1] += day.characterCount
            if day.characterCount > 0 { activeDays[weekday - 1] += 1 }
        }
        return (1...7).map { weekday in
            TypingWeekdayAggregate(
                weekday: weekday,
                characterCount: counts[weekday - 1],
                activeDayCount: activeDays[weekday - 1]
            )
        }
    }

    private static func weekdayHourDistribution(
        current: [Int: Int64],
        comparison: [Int: Int64]
    ) -> [TypingWeekdayHourAggregate] {
        (1...7).flatMap { weekday in
            (0...23).map { hour in
                let key = (weekday - 1) * 24 + hour
                return TypingWeekdayHourAggregate(
                    weekday: weekday,
                    hour: hour,
                    characterCount: current[key, default: 0],
                    comparisonCharacterCount: comparison[key, default: 0]
                )
            }
        }
    }

    private static func rangeMetrics(
        days: [TypingDaySummary],
        weekdays: [TypingWeekdayAggregate],
        hours: [TypingHourAggregate]
    ) -> TypingRangeMetrics {
        let total = days.reduce(Int64(0)) { $0 + $1.characterCount }
        let activeDays = days.filter { $0.characterCount > 0 }
        let bestDay = activeDays.sorted { left, right in
            if left.characterCount != right.characterCount {
                return left.characterCount > right.characterCount
            }
            return left.date < right.date
        }.first
        var longestStreak = 0
        var currentStreak = 0
        for day in days {
            if day.characterCount > 0 {
                currentStreak += 1
                longestStreak = max(longestStreak, currentStreak)
            } else {
                currentStreak = 0
            }
        }
        let busiestWeekday = weekdays.filter { $0.characterCount > 0 }.sorted { left, right in
            if left.characterCount != right.characterCount {
                return left.characterCount > right.characterCount
            }
            if left.activeDayCount != right.activeDayCount {
                return left.activeDayCount > right.activeDayCount
            }
            return left.weekday < right.weekday
        }.first
        let busiestHour = hours.filter { $0.characterCount > 0 }.sorted { left, right in
            if left.characterCount != right.characterCount {
                return left.characterCount > right.characterCount
            }
            if left.activeDayCount != right.activeDayCount {
                return left.activeDayCount > right.activeDayCount
            }
            return left.hour < right.hour
        }.first
        return TypingRangeMetrics(
            characterCount: total,
            calendarDayCount: days.count,
            activeDayCount: activeDays.count,
            dailyAverage: days.isEmpty ? 0 : Double(total) / Double(days.count),
            activeDayAverage: activeDays.isEmpty
                ? 0
                : Double(total) / Double(activeDays.count),
            peakCPS: days.lazy.map(\.peakCPS).max() ?? 0,
            bestDay: bestDay,
            longestActiveDayStreak: longestStreak,
            busiestWeekday: busiestWeekday,
            busiestHour: busiestHour
        )
    }

    private static func mergeApplicationRangeValues(
        current: [String: ApplicationRangeValue],
        comparison: [String: ApplicationRangeValue],
        currentTotal: Int64,
        comparisonTotal: Int64
    ) -> [TypingRangeApplicationSummary] {
        let keys = Set(current.keys).union(comparison.keys)
        return keys.compactMap { key -> TypingRangeApplicationSummary? in
            guard let identity = current[key]?.application ?? comparison[key]?.application else {
                return nil
            }
            let currentValue = current[key]
            let comparisonValue = comparison[key]
            let count = currentValue?.characterCount ?? 0
            let baseline = comparisonValue?.characterCount ?? 0
            return TypingRangeApplicationSummary(
                application: identity,
                characterCount: count,
                comparisonCharacterCount: baseline,
                activeDayCount: currentValue?.activeDayCount ?? 0,
                comparisonActiveDayCount: comparisonValue?.activeDayCount ?? 0,
                share: currentTotal > 0 ? Double(count) / Double(currentTotal) : 0,
                comparisonShare: comparisonTotal > 0
                    ? Double(baseline) / Double(comparisonTotal)
                    : 0,
                characterChange: count - baseline,
                relativeCharacterChange: baseline > 0
                    ? Double(count - baseline) / Double(baseline)
                    : nil
            )
        }.sorted { left, right in
            if left.characterCount != right.characterCount {
                return left.characterCount > right.characterCount
            }
            if left.comparisonCharacterCount != right.comparisonCharacterCount {
                return left.comparisonCharacterCount > right.comparisonCharacterCount
            }
            let nameOrder = left.application.displayName.localizedCaseInsensitiveCompare(
                right.application.displayName
            )
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return left.application.processKey < right.application.processKey
        }
    }

    private func loadKeyCounts(
        dateKey: String,
        from database: OpaquePointer
    ) throws -> [UInt16: Int64] {
        let statement = try prepare(
            "SELECT KeyCode, PressCount FROM KeyDailyStat WHERE LocalDate = ?1;",
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(dateKey, at: 1, to: statement, in: database)
        return try readKeyCounts(from: statement, database: database)
    }

    private func loadAllTimeKeyCounts(from database: OpaquePointer) throws -> [UInt16: Int64] {
        let statement = try prepare("SELECT KeyCode, PressCount FROM KeyTotalStat;", in: database)
        defer { sqlite3_finalize(statement) }
        return try readKeyCounts(from: statement, database: database)
    }

    private func readKeyCounts(
        from statement: OpaquePointer,
        database: OpaquePointer
    ) throws -> [UInt16: Int64] {
        var output: [UInt16: Int64] = [:]
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return output }
            guard result == SQLITE_ROW else { throw queryError(database, code: result) }
            let rawKeyCode = sqlite3_column_int64(statement, 0)
            guard let keyCode = UInt16(exactly: rawKeyCode) else { continue }
            output[keyCode] = sqlite3_column_int64(statement, 1)
        }
    }

    private func loadLastInputDate(from database: OpaquePointer) throws -> Date? {
        let statement = try prepare(
            "SELECT MAX(LastInputUtc) FROM DayStat;",
            in: database
        )
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else { throw queryError(database, code: result) }
        return date(at: 0, in: statement)
    }

    private func prepare(_ sql: String, in database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw queryError(database, code: result)
        }
        return statement
    }

    private func execute(_ sql: String, in database: OpaquePointer) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw queryError(database, code: result) }
    }

    private func stepToCompletion(_ statement: OpaquePointer, in database: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else { throw queryError(database, code: result) }
    }

    private func bind(
        _ value: String,
        at index: Int32,
        to statement: OpaquePointer,
        in database: OpaquePointer
    ) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result = sqlite3_bind_text(statement, index, value, -1, transient)
        guard result == SQLITE_OK else { throw queryError(database, code: result) }
    }

    private func bind(
        _ value: String?,
        at index: Int32,
        to statement: OpaquePointer,
        in database: OpaquePointer
    ) throws {
        guard let value else {
            let result = sqlite3_bind_null(statement, index)
            guard result == SQLITE_OK else { throw queryError(database, code: result) }
            return
        }
        try bind(value, at: index, to: statement, in: database)
    }

    private func bind(
        _ value: Int64,
        at index: Int32,
        to statement: OpaquePointer,
        in database: OpaquePointer
    ) throws {
        let result = sqlite3_bind_int64(statement, index, value)
        guard result == SQLITE_OK else { throw queryError(database, code: result) }
    }

    private func text(at index: Int32, in statement: OpaquePointer) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func date(at index: Int32, in statement: OpaquePointer) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, index)))
    }

    private func queryError(_ database: OpaquePointer, code: Int32) -> TypingStatsStoreError {
        mapSQLiteError(code: code, message: String(cString: sqlite3_errmsg(database)))
    }

    private func mapSQLiteError(code: Int32, message: String) -> TypingStatsStoreError {
        let primaryCode = code & 0xFF
        let normalizedMessage = message.lowercased()
        if primaryCode == SQLITE_SCHEMA
            || normalizedMessage.contains("no such table")
            || normalizedMessage.contains("no such column") {
            return .incompatibleSchema
        }
        return switch primaryCode {
        case SQLITE_BUSY, SQLITE_LOCKED:
            .busy
        case SQLITE_CORRUPT, SQLITE_NOTADB:
            .corrupt
        case SQLITE_CANTOPEN:
            .cannotOpen(message)
        default:
            .queryFailed(message)
        }
    }

    private static var statisticsCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    nonisolated static func dateKey(for date: Date, calendar: Calendar? = nil) -> String {
        let calendar = calendar ?? statisticsCalendar
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private nonisolated static func localHour(for secondStart: Int64) -> Int64 {
        let date = Date(timeIntervalSince1970: TimeInterval(secondStart))
        return Int64(statisticsCalendar.component(.hour, from: date))
    }

    private nonisolated static func date(from key: String, calendar: Calendar) -> Date? {
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2]))
    }

    private nonisolated static func emptyDay(dateKey: String, date: Date) -> TypingDaySummary {
        TypingDaySummary(
            dateKey: dateKey,
            date: date,
            characterCount: 0,
            peakCPS: 0,
            activeMinuteBuckets: 0,
            activeSeconds: 0,
            topAppName: nil,
            lastUpdatedAt: nil
        )
    }
}
