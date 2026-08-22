import Foundation
import SQLite3

@main
@MainActor
struct TypingStatsCoreHarness {
    private static var assertions = 0

    static func main() async {
        do {
            try await run()
            print("Typing stats core harness passed: \(assertions) assertions")
        } catch {
            print("Typing stats core harness failed: \(error)")
            exit(1)
        }
    }

    private static func run() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simuboard-native-stats-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 1_787_422_400)
        let calendar = statisticsCalendar
        let todayKey = TypingStatsStore.dateKey(for: now, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayKey = TypingStatsStore.dateKey(for: yesterday, calendar: calendar)
        let databaseURL = directory.appendingPathComponent("typing-stats.sqlite3")
        let store = TypingStatsStore(databaseURL: databaseURL, nowProvider: { now })

        let appOne = TypingApplicationIdentity(
            processKey: "com.example.one",
            displayName: "Example One",
            processName: "ExampleOne",
            bundleIdentifier: "com.example.one"
        )
        let appTwo = TypingApplicationIdentity(
            processKey: "com.example.two",
            displayName: "Example Two",
            processName: "ExampleTwo",
            bundleIdentifier: "com.example.two"
        )
        let nowEpoch = Int64(now.timeIntervalSince1970)
        let yesterdayEpoch = Int64(yesterday.timeIntervalSince1970)

        try await store.record(TypingStatsWriteBatch(
            characterAggregates: [
                TypingCharacterAggregate(
                    secondStart: nowEpoch,
                    localDate: todayKey,
                    application: appOne,
                    count: 3
                ),
                TypingCharacterAggregate(
                    secondStart: nowEpoch,
                    localDate: todayKey,
                    application: appTwo,
                    count: 2
                ),
                TypingCharacterAggregate(
                    secondStart: nowEpoch - 10,
                    localDate: todayKey,
                    application: appOne,
                    count: 4
                ),
                TypingCharacterAggregate(
                    secondStart: yesterdayEpoch,
                    localDate: yesterdayKey,
                    application: appTwo,
                    count: 12
                ),
            ],
            keyAggregates: [
                TypingKeyAggregate(localDate: todayKey, keyCode: 0, count: 5),
                TypingKeyAggregate(localDate: todayKey, keyCode: 56, count: 2),
                TypingKeyAggregate(localDate: yesterdayKey, keyCode: 0, count: 3),
            ]
        ))

        var snapshot = try await store.loadSnapshot()
        try expect(FileManager.default.fileExists(atPath: databaseURL.path), "creates native database")
        let schemaVersion = try readUserVersion(databaseURL)
        try expect(schemaVersion == 1, "creates schema version one")
        try expect(snapshot.today.characterCount == 9, "reads today's character count")
        try expect(snapshot.today.peakCPS == 5, "combines applications for global peak speed")
        try expect(snapshot.today.topAppName == "Example One", "finds today's top application")
        try expect(snapshot.apps.count == 2, "reads both applications")
        try expect(snapshot.apps.first?.displayName == "Example One", "sorts application ranking")
        try expect(snapshot.apps.first?.characterCount == 7, "aggregates characters by application")
        try expect(snapshot.recentBuckets.count == 60, "fills sixty recent buckets")
        try expect(
            snapshot.recentBuckets.reduce(0) { $0 + $1.characterCount } == 9,
            "reads recent character buckets"
        )
        try expect(snapshot.history.count == 14, "fills fourteen history days")
        try expect(
            snapshot.history.first(where: { $0.dateKey == yesterdayKey })?.characterCount == 12,
            "reads prior-day history"
        )
        try expect(snapshot.fourteenDayTotal == 21, "calculates fourteen-day total")
        try expect(snapshot.activeDayCount == 2, "calculates active days")
        try expect(snapshot.todayKeyCounts[0] == 5, "reads today's letter key count")
        try expect(snapshot.todayKeyCounts[56] == 2, "reads today's modifier key count")
        try expect(snapshot.allTimeKeyCounts[0] == 8, "adds lifetime key counts across days")
        try expect(snapshot.allTimePhysicalPresses == 10, "calculates lifetime physical presses")
        try expect(snapshot.lastInputAt != nil, "reads last input timestamp")

        try await store.record(TypingStatsWriteBatch(
            characterAggregates: [
                TypingCharacterAggregate(
                    secondStart: nowEpoch,
                    localDate: todayKey,
                    application: appOne,
                    count: 1
                ),
            ],
            keyAggregates: [
                TypingKeyAggregate(localDate: todayKey, keyCode: 0, count: 1),
            ]
        ))
        snapshot = try await store.loadSnapshot()
        try expect(snapshot.today.characterCount == 10, "adds a later batch without replacing totals")
        try expect(snapshot.today.peakCPS == 6, "updates peak when the same second receives a later batch")
        try expect(snapshot.todayKeyCounts[0] == 6, "adds daily physical key batches")
        try expect(snapshot.allTimeKeyCounts[0] == 9, "adds lifetime physical key batches")

        let reopened = TypingStatsStore(databaseURL: databaseURL, nowProvider: { now })
        let reopenedSnapshot = try await reopened.loadSnapshot()
        try expect(reopenedSnapshot.today == snapshot.today, "persists character totals across reopen")
        try expect(
            reopenedSnapshot.allTimeKeyCounts == snapshot.allTimeKeyCounts,
            "persists lifetime key totals across reopen"
        )
        try await reopened.clearAll()
        let clearedSnapshot = try await reopened.loadSnapshot()
        try expect(clearedSnapshot.today.characterCount == 0, "clears today's characters")
        try expect(clearedSnapshot.apps.isEmpty, "clears application profiles and ranking")
        try expect(clearedSnapshot.todayKeyCounts.isEmpty, "clears today's key counts")
        try expect(clearedSnapshot.allTimeKeyCounts.isEmpty, "clears lifetime key counts")

        try await testModelSemantics(in: directory, now: now, application: appOne)
        try await testFailedBatchMerge(now: now, application: appOne)
        try await testFailureSuspensionAndRecovery(now: now, application: appOne)
        try await testFlushBarrier(now: now, application: appOne)
        try await testClearBarrier(now: now, application: appOne)
        try await testMidnightDateBoundary(now: now, application: appOne)
        try await testRetention(in: directory, now: now, application: appOne)
        try await testFutureSchema(in: directory, now: now)

        try expect(
            TypingStatsStore.defaultDatabaseURL().lastPathComponent == "typing-stats.sqlite3",
            "uses SimuBoard's native database filename"
        )
        try expect(
            TypingCharacterKeyFilter.countsAsCharacter(keyCode: 0, isShortcutModified: false),
            "counts a normal letter as character input"
        )
        try expect(
            !TypingCharacterKeyFilter.countsAsCharacter(keyCode: 0, isShortcutModified: true),
            "does not count Command or Control shortcuts as character input"
        )
        try expect(
            !TypingCharacterKeyFilter.countsAsCharacter(keyCode: 56, isShortcutModified: false),
            "does not count modifiers as character input"
        )
        for keyCode: UInt16 in [71, 102, 104, 110, 114] {
            try expect(
                !TypingCharacterKeyFilter.countsAsCharacter(
                    keyCode: keyCode,
                    isShortcutModified: false
                ),
                "does not count non-character key code \(keyCode) as character input"
            )
        }
        for keyCode: UInt16 in [10, 49, 65, 82, 93, 95] {
            try expect(
                TypingCharacterKeyFilter.countsAsCharacter(
                    keyCode: keyCode,
                    isShortcutModified: false
                ),
                "counts character-producing key code \(keyCode)"
            )
        }
    }

    private static func testModelSemantics(
        in directory: URL,
        now: Date,
        application: TypingApplicationIdentity
    ) async throws {
        let url = directory.appendingPathComponent("model.sqlite3")
        let store = TypingStatsStore(databaseURL: url, nowProvider: { now })
        let model = TypingStatsModel(persistence: store)

        model.recordKeyDown(
            keyCode: 0,
            isRepeat: false,
            isShortcutModified: false,
            application: application,
            at: now
        )
        model.recordKeyDown(
            keyCode: 0,
            isRepeat: true,
            isShortcutModified: false,
            application: application,
            at: now
        )
        model.recordKeyDown(
            keyCode: 56,
            isRepeat: false,
            isShortcutModified: false,
            application: application,
            at: now
        )
        model.recordKeyDown(
            keyCode: 8,
            isRepeat: false,
            isShortcutModified: true,
            application: application,
            at: now
        )
        model.recordKeyDown(
            keyCode: 36,
            isRepeat: false,
            isShortcutModified: false,
            application: application,
            at: now
        )
        await model.refresh()

        guard let snapshot = model.snapshot else {
            throw HarnessError.message("model did not publish native snapshot")
        }
        try expect(snapshot.today.characterCount == 2, "character repeat contributes to input total")
        try expect(snapshot.today.peakCPS == 2, "character repeat contributes to peak speed")
        try expect(snapshot.todayKeyCounts[0] == 1, "repeat does not add a physical key press")
        try expect(snapshot.todayKeyCounts[56] == 1, "modifier adds a physical key press")
        try expect(snapshot.todayKeyCounts[8] == 1, "shortcut key adds a physical key press")
        try expect(snapshot.todayKeyCounts[36] == 1, "return adds a physical key press")
        try expect(snapshot.todayPhysicalPresses == 4, "counts all non-repeat physical presses")
    }

    private static func testFailedBatchMerge(
        now: Date,
        application: TypingApplicationIdentity
    ) async throws {
        let persistence = FlakyTypingStatsPersistence()
        let model = TypingStatsModel(persistence: persistence)
        for _ in 0..<100 {
            model.recordKeyDown(
                keyCode: 0,
                isRepeat: false,
                isShortcutModified: false,
                application: application,
                at: now
            )
        }
        let firstFlush = await model.flushPending()
        try expect(firstFlush == false, "reports the first failed batch")
        let secondFlush = await model.flushPending()
        try expect(secondFlush, "retries a merged failed batch")
        let captured = await persistence.capturedBatch()
        let recordCallCount = await persistence.recordCallCount()
        try expect(recordCallCount == 2, "batches one hundred keys into two attempts")
        try expect(
            captured.characterAggregates.reduce(0) { $0 + $1.count } == 100,
            "does not lose characters after failed write"
        )
        try expect(
            captured.keyAggregates.reduce(0) { $0 + $1.count } == 100,
            "does not lose physical key counts after failed write"
        )
    }

    private static func testFlushBarrier(
        now: Date,
        application: TypingApplicationIdentity
    ) async throws {
        let persistence = GatedTypingStatsPersistence()
        let completion = CompletionProbe()
        let model = TypingStatsModel(persistence: persistence)

        model.recordKeyDown(
            keyCode: 0,
            isRepeat: false,
            isShortcutModified: false,
            application: application,
            at: now
        )
        let owner = Task { await model.flushPending() }
        await persistence.waitUntilAttemptStarted(1)

        model.recordKeyDown(
            keyCode: 1,
            isRepeat: false,
            isShortcutModified: false,
            application: application,
            at: now.addingTimeInterval(1)
        )
        let waiter = Task {
            let result = await model.flushPending()
            await completion.markFinished()
            return result
        }

        await persistence.releaseAttempt(1)
        await persistence.waitUntilAttemptStarted(2)
        let waiterFinishedEarly = await completion.isFinished()
        try expect(
            !waiterFinishedEarly,
            "flush waiter remains blocked while the owner writes a later pending batch"
        )

        await persistence.releaseAttempt(2)
        let ownerResult = await owner.value
        let waiterResult = await waiter.value
        try expect(ownerResult, "flush owner succeeds after draining both batches")
        try expect(waiterResult, "flush waiter succeeds only after the barrier is empty")
        let batches = await persistence.capturedBatches()
        try expect(batches.count == 2, "flush barrier writes both batches before returning")
        try expect(
            batches.flatMap(\.characterAggregates).reduce(0) { $0 + $1.count } == 2,
            "flush barrier retains characters recorded during an in-flight write"
        )
    }

    private static func testFailureSuspensionAndRecovery(
        now: Date,
        application: TypingApplicationIdentity
    ) async throws {
        let persistence = RecoveringTypingStatsPersistence(failuresBeforeSuccess: 6)
        let model = TypingStatsModel(persistence: persistence)
        model.recordKeyDown(
            keyCode: 0,
            isRepeat: false,
            isShortcutModified: false,
            application: application,
            at: now
        )

        for _ in 0..<6 {
            let result = await model.flushPending()
            try expect(!result, "reports each persistence failure before suspension")
        }
        try expect(model.isRecordingSuspended, "suspends recording after six consecutive failures")

        model.recordKeyDown(
            keyCode: 1,
            isRepeat: false,
            isShortcutModified: false,
            application: application,
            at: now.addingTimeInterval(1)
        )
        let recoveryResult = await model.flushPending()
        try expect(recoveryResult, "a later successful flush recovers the frozen batch")
        try expect(!model.isRecordingSuspended, "successful retry resumes recording")

        model.recordKeyDown(
            keyCode: 2,
            isRepeat: false,
            isShortcutModified: false,
            application: application,
            at: now.addingTimeInterval(2)
        )
        let postRecoveryResult = await model.flushPending()
        try expect(postRecoveryResult, "records new input after recovery")
        let successfulCharacters = await persistence.successfulCharacterCount()
        try expect(
            successfulCharacters == 2,
            "drops input received while suspended but keeps pre-failure and post-recovery input"
        )
    }

    private static func testMidnightDateBoundary(
        now: Date,
        application: TypingApplicationIdentity
    ) async throws {
        let persistence = CapturingTypingStatsPersistence()
        let model = TypingStatsModel(persistence: persistence)
        let calendar = statisticsCalendar
        let today = calendar.startOfDay(for: now)
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: today) else {
            throw HarnessError.message("could not make next midnight fixture")
        }

        model.recordKeyDown(
            keyCode: 0,
            isRepeat: false,
            isShortcutModified: false,
            application: application,
            at: nextMidnight.addingTimeInterval(-1)
        )
        model.recordKeyDown(
            keyCode: 1,
            isRepeat: false,
            isShortcutModified: false,
            application: application,
            at: nextMidnight
        )
        let flushResult = await model.flushPending()
        try expect(flushResult, "flushes midnight boundary fixture")

        let batch = await persistence.capturedBatch()
        let expectedDates = Set([
            TypingStatsStore.dateKey(for: nextMidnight.addingTimeInterval(-1), calendar: calendar),
            TypingStatsStore.dateKey(for: nextMidnight, calendar: calendar),
        ])
        try expect(
            Set(batch.characterAggregates.map(\.localDate)) == expectedDates,
            "an event exactly at midnight belongs to the new local day"
        )
        try expect(
            Set(batch.keyAggregates.map(\.localDate)) == expectedDates,
            "physical key counts also cross the midnight boundary"
        )
    }

    private static func testClearBarrier(
        now: Date,
        application: TypingApplicationIdentity
    ) async throws {
        let persistence = GatedClearTypingStatsPersistence(now: now)
        let model = TypingStatsModel(persistence: persistence)
        let clearTask = Task { await model.clearAll() }
        await persistence.waitUntilClearStarted()

        model.recordKeyDown(
            keyCode: 0,
            isRepeat: false,
            isShortcutModified: false,
            application: application,
            at: now
        )
        await persistence.releaseClear()
        let clearResult = await clearTask.value
        let finalFlushResult = await model.flushPending()

        try expect(clearResult, "clear barrier completes successfully")
        try expect(finalFlushResult, "clear barrier leaves no failed pending batch")
        let recordCalls = await persistence.recordCallCount()
        try expect(recordCalls == 0, "keys pressed during clear are not written back after deletion")
    }

    private static func testRetention(
        in directory: URL,
        now: Date,
        application: TypingApplicationIdentity
    ) async throws {
        let url = directory.appendingPathComponent("retention.sqlite3")
        let store = TypingStatsStore(databaseURL: url, nowProvider: { now })
        let calendar = statisticsCalendar
        let oldDate = calendar.date(byAdding: .day, value: -40, to: now) ?? now
        let oldDateKey = TypingStatsStore.dateKey(for: oldDate, calendar: calendar)
        try await store.record(TypingStatsWriteBatch(
            characterAggregates: [
                TypingCharacterAggregate(
                    secondStart: Int64(oldDate.timeIntervalSince1970),
                    localDate: oldDateKey,
                    application: application,
                    count: 9
                ),
            ],
            keyAggregates: [
                TypingKeyAggregate(localDate: oldDateKey, keyCode: 0, count: 7),
            ]
        ))
        let snapshot = try await store.loadSnapshot()
        try expect(snapshot.fourteenDayTotal == 0, "removes old per-second character detail")
        try expect(snapshot.todayKeyCounts[0] == nil, "removes old daily key detail")
        try expect(snapshot.allTimeKeyCounts[0] == 7, "retains lifetime key totals after cleanup")
    }

    private static func testFutureSchema(in directory: URL, now: Date) async throws {
        let url = directory.appendingPathComponent("future.sqlite3")
        var database: OpaquePointer?
        try expect(sqlite3_open(url.path, &database) == SQLITE_OK, "opens future schema fixture")
        guard let database else { throw HarnessError.message("missing future schema database") }
        try execute("PRAGMA user_version = 99;", in: database)
        sqlite3_close_v2(database)

        do {
            _ = try await TypingStatsStore(databaseURL: url, nowProvider: { now }).loadSnapshot()
            throw HarnessError.message("future schema unexpectedly loaded")
        } catch let error as TypingStatsStoreError {
            guard case .incompatibleSchema = error else { throw error }
            assertions += 1
        }
        let schemaVersion = try readUserVersion(url)
        try expect(schemaVersion == 99, "does not rewrite an unsupported future schema")
    }

    private static func readUserVersion(_ url: URL) throws -> Int64 {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            throw HarnessError.message("cannot open fixture to read user_version")
        }
        defer { sqlite3_close_v2(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw HarnessError.message("cannot prepare user_version")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw HarnessError.message("cannot step user_version")
        }
        return sqlite3_column_int64(statement, 0)
    }

    private static func execute(_ sql: String, in database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite \(result)"
            throw HarnessError.message(message)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw HarnessError.message(message) }
        assertions += 1
    }

    private static var statisticsCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        return calendar
    }
}

private actor FlakyTypingStatsPersistence: TypingStatsPersistence {
    private var attempts = 0
    private var captured: TypingStatsWriteBatch = TypingStatsWriteBatch(
        characterAggregates: [],
        keyAggregates: []
    )

    func record(_ batch: TypingStatsWriteBatch) async throws {
        attempts += 1
        if attempts == 1 {
            throw TypingStatsStoreError.busy
        }
        captured = batch
    }

    func loadSnapshot() async throws -> TypingStatsSnapshot {
        throw TypingStatsStoreError.queryFailed("not used")
    }

    func clearAll() async throws {}

    func recordCallCount() -> Int { attempts }
    func capturedBatch() -> TypingStatsWriteBatch { captured }
}

private actor GatedTypingStatsPersistence: TypingStatsPersistence {
    private var batches: [TypingStatsWriteBatch] = []
    private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
    private var releasedAttempts: Set<Int> = []
    private var startWaiters: [(attempt: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func record(_ batch: TypingStatsWriteBatch) async throws {
        let attempt = batches.count + 1
        batches.append(batch)

        let ready = startWaiters.filter { $0.attempt <= attempt }
        startWaiters.removeAll { $0.attempt <= attempt }
        ready.forEach { $0.continuation.resume() }

        if releasedAttempts.remove(attempt) != nil { return }
        await withCheckedContinuation { continuation in
            gates[attempt] = continuation
        }
    }

    func loadSnapshot() async throws -> TypingStatsSnapshot {
        throw TypingStatsStoreError.queryFailed("not used")
    }

    func clearAll() async throws {}

    func waitUntilAttemptStarted(_ attempt: Int) async {
        if batches.count >= attempt { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((attempt, continuation))
        }
    }

    func releaseAttempt(_ attempt: Int) {
        if let continuation = gates.removeValue(forKey: attempt) {
            continuation.resume()
        } else {
            releasedAttempts.insert(attempt)
        }
    }

    func capturedBatches() -> [TypingStatsWriteBatch] { batches }
}

private actor RecoveringTypingStatsPersistence: TypingStatsPersistence {
    private let failuresBeforeSuccess: Int
    private var attempts = 0
    private var successfulCharacters: Int64 = 0

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func record(_ batch: TypingStatsWriteBatch) async throws {
        attempts += 1
        if attempts <= failuresBeforeSuccess {
            throw TypingStatsStoreError.busy
        }
        successfulCharacters += batch.characterAggregates.reduce(0) { $0 + $1.count }
    }

    func loadSnapshot() async throws -> TypingStatsSnapshot {
        throw TypingStatsStoreError.queryFailed("not used")
    }

    func clearAll() async throws {}
    func successfulCharacterCount() -> Int64 { successfulCharacters }
}

private actor CompletionProbe {
    private var finished = false

    func markFinished() { finished = true }
    func isFinished() -> Bool { finished }
}

private actor GatedClearTypingStatsPersistence: TypingStatsPersistence {
    private let now: Date
    private var records = 0
    private var clearStarted = false
    private var clearReleaseRequested = false
    private var clearGate: CheckedContinuation<Void, Never>?
    private var clearStartWaiters: [CheckedContinuation<Void, Never>] = []

    init(now: Date) {
        self.now = now
    }

    func record(_ batch: TypingStatsWriteBatch) async throws {
        records += 1
    }

    func loadSnapshot() async throws -> TypingStatsSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .autoupdatingCurrent
        let dateKey = TypingStatsStore.dateKey(for: now, calendar: calendar)
        let day = TypingDaySummary(
            dateKey: dateKey,
            date: calendar.startOfDay(for: now),
            characterCount: 0,
            peakCPS: 0,
            activeMinuteBuckets: 0,
            activeSeconds: 0,
            topAppName: nil,
            lastUpdatedAt: nil
        )
        return TypingStatsSnapshot(
            generatedAt: now,
            lastInputAt: nil,
            today: day,
            recentBuckets: [],
            apps: [],
            history: [day],
            todayKeyCounts: [:],
            allTimeKeyCounts: [:]
        )
    }

    func clearAll() async throws {
        clearStarted = true
        let waiters = clearStartWaiters
        clearStartWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
        if clearReleaseRequested { return }
        await withCheckedContinuation { continuation in
            clearGate = continuation
        }
    }

    func waitUntilClearStarted() async {
        if clearStarted { return }
        await withCheckedContinuation { continuation in
            clearStartWaiters.append(continuation)
        }
    }

    func releaseClear() {
        if let clearGate {
            self.clearGate = nil
            clearGate.resume()
        } else {
            clearReleaseRequested = true
        }
    }

    func recordCallCount() -> Int { records }
}

private actor CapturingTypingStatsPersistence: TypingStatsPersistence {
    private var captured = TypingStatsWriteBatch(characterAggregates: [], keyAggregates: [])

    func record(_ batch: TypingStatsWriteBatch) async throws {
        captured = batch
    }

    func loadSnapshot() async throws -> TypingStatsSnapshot {
        throw TypingStatsStoreError.queryFailed("not used")
    }

    func clearAll() async throws { captured = TypingStatsWriteBatch(characterAggregates: [], keyAggregates: []) }

    func capturedBatch() -> TypingStatsWriteBatch { captured }
}

private enum HarnessError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message): message
        }
    }
}
