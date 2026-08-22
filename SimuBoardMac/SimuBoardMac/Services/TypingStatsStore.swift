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
    func loadSnapshot() async throws -> TypingStatsSnapshot
    func clearAll() async throws
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
    private static let schemaVersion: Int64 = 1
    private static let recentBucketSeconds: Int64 = 10
    private static let recentBucketCount = 60
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

    func loadSnapshot() async throws -> TypingStatsSnapshot {
        let database = try openDatabaseIfNeeded()
        let now = nowProvider()
        let calendar = Self.statisticsCalendar
        let todayKey = Self.dateKey(for: now, calendar: calendar)

        try execute("BEGIN;", in: database)
        do {
            let snapshot = TypingStatsSnapshot(
                generatedAt: now,
                lastInputAt: try loadLastInputDate(from: database),
                today: try loadDaySummary(
                    dateKey: todayKey,
                    date: calendar.startOfDay(for: now),
                    from: database
                ),
                recentBuckets: try loadRecentBuckets(now: now, from: database),
                apps: try loadApps(dateKey: todayKey, limit: 20, from: database),
                history: try loadHistory(now: now, calendar: calendar, from: database),
                todayKeyCounts: try loadKeyCounts(dateKey: todayKey, from: database),
                allTimeKeyCounts: try loadAllTimeKeyCounts(from: database)
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
                    PRAGMA user_version = 1;
                    """,
                    in: database
                )
                try execute("COMMIT;", in: database)
            } catch {
                try? execute("ROLLBACK;", in: database)
                throw error
            }
        }

        try validateSchema(in: database)
    }

    private func validateSchema(in database: OpaquePointer) throws {
        let requiredSchema: [String: Set<String>] = [
            "AppProfile": [
                "Id", "ProcessKey", "ProcessName", "DisplayName", "BundleIdentifier",
                "UpdatedAtUtc",
            ],
            "CharacterSecondStat": [
                "SecondStartUtc", "LocalDate", "AppId", "CharacterCount", "UpdatedAtUtc",
            ],
            "KeyDailyStat": ["LocalDate", "KeyCode", "PressCount", "UpdatedAtUtc"],
            "KeyTotalStat": ["KeyCode", "PressCount", "UpdatedAtUtc"],
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
                SecondStartUtc, LocalDate, AppId, CharacterCount, UpdatedAtUtc
            ) VALUES (?1, ?2, ?3, ?4, ?5)
            ON CONFLICT(SecondStartUtc, AppId) DO UPDATE SET
                CharacterCount = CharacterCount + excluded.CharacterCount,
                UpdatedAtUtc = excluded.UpdatedAtUtc;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(aggregate.secondStart, at: 1, to: statement, in: database)
        try bind(aggregate.localDate, at: 2, to: statement, in: database)
        try bind(applicationID, at: 3, to: statement, in: database)
        try bind(aggregate.count, at: 4, to: statement, in: database)
        try bind(updatedAt, at: 5, to: statement, in: database)
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

        let keyStatement = try prepare(
            "DELETE FROM KeyDailyStat WHERE LocalDate < ?1;",
            in: database
        )
        defer { sqlite3_finalize(keyStatement) }
        try bind(cutoffKey, at: 1, to: keyStatement, in: database)
        try stepToCompletion(keyStatement, in: database)

        try execute(
            """
            DELETE FROM AppProfile
            WHERE Id NOT IN (
                SELECT AppId FROM CharacterSecondStat GROUP BY AppId
            );
            """,
            in: database
        )
        return todayKey
    }

    private func loadDaySummary(
        dateKey: String,
        date: Date,
        from database: OpaquePointer
    ) throws -> TypingDaySummary {
        let totals = try prepare(
            """
            SELECT COALESCE(SUM(CharacterCount), 0),
                   COUNT(DISTINCT SecondStartUtc / 60),
                   COUNT(DISTINCT SecondStartUtc),
                   MAX(UpdatedAtUtc)
            FROM CharacterSecondStat
            WHERE LocalDate = ?1;
            """,
            in: database
        )
        defer { sqlite3_finalize(totals) }
        try bind(dateKey, at: 1, to: totals, in: database)
        let totalsResult = sqlite3_step(totals)
        guard totalsResult == SQLITE_ROW else { throw queryError(database, code: totalsResult) }

        return TypingDaySummary(
            dateKey: dateKey,
            date: date,
            characterCount: sqlite3_column_int64(totals, 0),
            peakCPS: try loadPeakCPS(dateKey: dateKey, from: database),
            activeMinuteBuckets: sqlite3_column_int64(totals, 1),
            activeSeconds: sqlite3_column_int64(totals, 2),
            topAppName: try loadTopAppName(dateKey: dateKey, from: database),
            lastUpdatedAt: self.date(at: 3, in: totals)
        )
    }

    private func loadPeakCPS(dateKey: String, from database: OpaquePointer) throws -> Int64 {
        let statement = try prepare(
            """
            SELECT COALESCE(MAX(CharactersPerSecond), 0)
            FROM (
                SELECT SUM(CharacterCount) AS CharactersPerSecond
                FROM CharacterSecondStat
                WHERE LocalDate = ?1
                GROUP BY SecondStartUtc
            );
            """,
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
            FROM CharacterSecondStat stat
            JOIN AppProfile ap ON ap.Id = stat.AppId
            WHERE stat.LocalDate = ?1
            GROUP BY stat.AppId
            ORDER BY SUM(stat.CharacterCount) DESC, ap.DisplayName COLLATE NOCASE, stat.AppId
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

    private func loadRecentBuckets(now: Date, from database: OpaquePointer) throws -> [TypingBucket] {
        let bucketSeconds = Self.recentBucketSeconds
        let end = Int64(now.timeIntervalSince1970)
        let alignedEnd = end - end % bucketSeconds + bucketSeconds
        let start = alignedEnd - Int64(Self.recentBucketCount) * bucketSeconds
        var counts = Array(repeating: Int64(0), count: Self.recentBucketCount)

        let statement = try prepare(
            """
            SELECT CAST((SecondStartUtc - ?1) / ?3 AS INTEGER) AS BucketIndex,
                   SUM(CharacterCount)
            FROM CharacterSecondStat
            WHERE SecondStartUtc >= ?1 AND SecondStartUtc < ?2
            GROUP BY BucketIndex
            ORDER BY BucketIndex;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(start, at: 1, to: statement, in: database)
        try bind(alignedEnd, at: 2, to: statement, in: database)
        try bind(bucketSeconds, at: 3, to: statement, in: database)

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw queryError(database, code: result) }
            let index = Int(sqlite3_column_int64(statement, 0))
            if counts.indices.contains(index) {
                counts[index] = sqlite3_column_int64(statement, 1)
            }
        }

        return counts.indices.map { index in
            TypingBucket(
                index: index,
                start: Date(timeIntervalSince1970: TimeInterval(start + Int64(index) * bucketSeconds)),
                characterCount: counts[index]
            )
        }
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
                   SUM(stat.CharacterCount) AS Characters,
                   COUNT(DISTINCT stat.SecondStartUtc / 60) AS ActiveMinutes,
                   COUNT(DISTINCT stat.SecondStartUtc) AS ActiveSeconds,
                   MAX(stat.CharacterCount) AS PeakCPS
            FROM CharacterSecondStat stat
            JOIN AppProfile ap ON ap.Id = stat.AppId
            WHERE stat.LocalDate = ?1
            GROUP BY stat.AppId
            ORDER BY Characters DESC, ap.DisplayName COLLATE NOCASE
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
                   SUM(CharacterCount),
                   COUNT(DISTINCT SecondStartUtc / 60),
                   COUNT(DISTINCT SecondStartUtc),
                   MAX(UpdatedAtUtc)
            FROM CharacterSecondStat
            WHERE LocalDate BETWEEN ?1 AND ?2
            GROUP BY LocalDate
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
                peakCPS: 0,
                activeMinuteBuckets: sqlite3_column_int64(totals, 2),
                activeSeconds: sqlite3_column_int64(totals, 3),
                topAppName: nil,
                lastUpdatedAt: self.date(at: 4, in: totals)
            )
        }

        let peaks = try loadDailyPeaks(startKey: startKey, endKey: endKey, from: database)
        let topApps = try loadDailyTopApps(startKey: startKey, endKey: endKey, from: database)
        for (dateKey, summary) in stored {
            stored[dateKey] = TypingDaySummary(
                dateKey: summary.dateKey,
                date: summary.date,
                characterCount: summary.characterCount,
                peakCPS: peaks[dateKey] ?? 0,
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
                SELECT stat.LocalDate, stat.AppId, SUM(stat.CharacterCount) AS Characters
                FROM CharacterSecondStat stat
                WHERE stat.LocalDate BETWEEN ?1 AND ?2
                GROUP BY stat.LocalDate, stat.AppId
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
            "SELECT MAX(SecondStartUtc) FROM CharacterSecondStat;",
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
