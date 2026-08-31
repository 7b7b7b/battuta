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
        try testRollingRhythmRanges(now: now, calendar: calendar)
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
        try expect(schemaVersion == 2, "creates schema version two")
        try expect(snapshot.today.characterCount == 9, "reads today's character count")
        try expect(snapshot.today.peakCPS == 5, "combines applications for global peak speed")
        try expect(snapshot.today.topAppName == "Example One", "finds today's top application")
        try expect(snapshot.apps.count == 2, "reads both applications")
        try expect(snapshot.apps.first?.displayName == "Example One", "sorts application ranking")
        try expect(snapshot.apps.first?.characterCount == 7, "aggregates characters by application")
        try expect(snapshot.timelineRange == .oneHour, "uses one hour as the default timeline range")
        try expect(snapshot.recentAppTimelines.count == 2, "builds timelines for both applications")
        try expect(
            snapshot.recentAppTimelines.first?.rangeCharacterCount == 7,
            "aggregates the top application's selected-range timeline"
        )
        try expect(
            snapshot.recentAppTimelines.first?.buckets.count == 60,
            "fills sixty buckets for each application timeline"
        )
        try expect(snapshot.recentBuckets.count == 60, "fills sixty recent buckets")
        try expect(
            snapshot.recentBuckets.reduce(0) { $0 + $1.characterCount } == 9,
            "reads recent character buckets"
        )

        for range in TypingTimelineRange.allCases {
            let rangedSnapshot = try await store.loadSnapshot(timelineRange: range)
            try expect(
                rangedSnapshot.timelineRange == range,
                "preserves the selected \(range.rawValue) timeline range"
            )
            try expect(
                rangedSnapshot.recentBuckets.count == range.bucketCount,
                "fills the configured number of \(range.rawValue) buckets"
            )
            if let first = rangedSnapshot.recentBuckets.first,
               let last = rangedSnapshot.recentBuckets.last {
                let coveredSeconds = Int64(
                    last.start.addingTimeInterval(TimeInterval(range.bucketSeconds))
                        .timeIntervalSince(first.start)
                )
                try expect(
                    coveredSeconds == range.durationSeconds,
                    "covers the complete \(range.rawValue) duration"
                )
            } else {
                throw HarnessError.message("missing \(range.rawValue) buckets")
            }
            let expectedTotal: Int64 = range == .sevenDays ? 21 : 9
            try expect(
                rangedSnapshot.recentBuckets.reduce(0) { $0 + $1.characterCount }
                    == expectedTotal,
                "reads the correct \(range.rawValue) range total"
            )
        }
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
        let keyCountOnlySnapshot = try await store.loadSnapshot(
            request: TypingStatsSnapshotRequest(
                timelineRange: .oneHour,
                sections: [.keyCounts]
            )
        )
        try expect(
            keyCountOnlySnapshot.today.characterCount == 9,
            "lightweight snapshot still loads the header day summary"
        )
        try expect(
            keyCountOnlySnapshot.todayKeyCounts[0] == 5
                && keyCountOnlySnapshot.allTimeKeyCounts[0] == 8,
            "lightweight snapshot still loads requested key counts"
        )
        try expect(keyCountOnlySnapshot.apps.isEmpty, "lightweight snapshot skips application ranking")
        try expect(
            keyCountOnlySnapshot.recentBuckets.isEmpty
                && keyCountOnlySnapshot.recentAppTimelines.isEmpty
                && keyCountOnlySnapshot.history.isEmpty,
            "lightweight snapshot skips recent timelines and history"
        )

        let twoDayReport = try await store.loadReport(range: TypingDateRange(
            startDate: yesterday,
            endDate: now
        ))
        try expect(twoDayReport.days.count == 2, "fills every day in an inclusive report range")
        try expect(
            twoDayReport.days.first?.dateKey == yesterdayKey
                && twoDayReport.days.last?.dateKey == todayKey,
            "orders an inclusive report calendar chronologically"
        )
        try expect(twoDayReport.metrics.characterCount == 21, "reports the selected range total")
        try expect(twoDayReport.metrics.calendarDayCount == 2, "counts requested calendar days")
        try expect(twoDayReport.metrics.activeDayCount == 2, "counts active report days")
        try expect(twoDayReport.metrics.dailyAverage == 10.5, "averages over calendar days")
        try expect(twoDayReport.metrics.activeDayAverage == 10.5, "averages over active days")
        try expect(twoDayReport.metrics.peakCPS == 12, "reports the range peak CPS")
        try expect(
            twoDayReport.metrics.bestDay?.dateKey == yesterdayKey,
            "reports the highest-volume day"
        )
        try expect(
            twoDayReport.metrics.longestActiveDayStreak == 2,
            "reports the longest consecutive active-day streak"
        )
        let expectedBusiestWeekday = calendar.component(.weekday, from: yesterday)
        try expect(
            twoDayReport.metrics.busiestWeekday?.weekday == expectedBusiestWeekday,
            "reports the busiest weekday"
        )
        let expectedBusiestHour = calendar.component(.hour, from: now)
        try expect(
            twoDayReport.metrics.busiestHour?.hour == expectedBusiestHour,
            "reports the busiest local hour"
        )
        try expect(twoDayReport.weekdayDistribution.count == 7, "fills seven weekday values")
        try expect(twoDayReport.hourlyDistribution.count == 24, "fills twenty-four hour values")
        try expect(
            twoDayReport.weekdayHourDistribution.count == 168,
            "fills the complete seven-by-twenty-four rhythm matrix"
        )
        try expect(
            Set(twoDayReport.weekdayHourDistribution.map(\.id)).count == 168,
            "gives every rhythm cell a unique stable identity"
        )
        let yesterdayRhythmCell = twoDayReport.weekdayHourDistribution.first {
            $0.weekday == calendar.component(.weekday, from: yesterday)
                && $0.hour == calendar.component(.hour, from: yesterday)
        }
        let todayRhythmCell = twoDayReport.weekdayHourDistribution.first {
            $0.weekday == calendar.component(.weekday, from: now)
                && $0.hour == calendar.component(.hour, from: now)
        }
        try expect(
            yesterdayRhythmCell?.characterCount == 12,
            "places prior-day input in its local weekday and hour cell"
        )
        try expect(
            todayRhythmCell?.characterCount == 9,
            "places current-day input in its local weekday and hour cell"
        )
        let zeroHour = (calendar.component(.hour, from: now) + 1) % 24
        let zeroRhythmCell = twoDayReport.weekdayHourDistribution.first {
            $0.weekday == calendar.component(.weekday, from: now) && $0.hour == zeroHour
        }
        try expect(
            zeroRhythmCell?.characterCount == 0
                && zeroRhythmCell?.comparisonCharacterCount == 0,
            "zero-fills a rhythm cell missing from both ranges"
        )
        try expect(twoDayReport.coverage.requestedDayCount == 2, "reports requested coverage days")
        try expect(twoDayReport.coverage.recordedDayCount == 2, "reports recorded coverage days")
        try expect(
            twoDayReport.coverage.isRangeWithinAvailableDates,
            "recognizes a range inside permanent aggregate coverage"
        )
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let threeDayReport = try await store.loadReport(range: TypingDateRange(
            startDate: twoDaysAgo,
            endDate: now
        ))
        try expect(threeDayReport.days.count == 3, "fills zero-value calendar days")
        try expect(
            threeDayReport.days.first?.characterCount == 0,
            "represents a day without input as a zero-value day"
        )
        try expect(threeDayReport.metrics.dailyAverage == 7, "includes zero days in daily average")
        try expect(
            threeDayReport.metrics.activeDayAverage == 10.5,
            "excludes zero days from active-day average"
        )
        try expect(
            threeDayReport.metrics.longestActiveDayStreak == 2,
            "does not count a leading zero day in the active streak"
        )
        try expect(
            !threeDayReport.coverage.isRangeWithinAvailableDates,
            "identifies a request that begins before recorded coverage"
        )

        let comparisonReport = try await store.loadReport(
            range: TypingDateRange(startDate: now, endDate: now),
            comparisonRange: TypingDateRange(startDate: yesterday, endDate: yesterday)
        )
        try expect(comparisonReport.metrics.characterCount == 9, "reports current comparison total")
        try expect(
            comparisonReport.comparisonMetrics?.characterCount == 12,
            "reports comparison-period total"
        )
        let comparedOne = comparisonReport.applications.first {
            $0.application.processKey == appOne.processKey
        }
        let comparedTwo = comparisonReport.applications.first {
            $0.application.processKey == appTwo.processKey
        }
        try expect(comparedOne?.characterCount == 7, "reports current application volume")
        try expect(
            comparedOne?.comparisonCharacterCount == 0,
            "includes applications absent from the comparison period"
        )
        try expect(
            comparedOne?.relativeCharacterChange == nil,
            "marks a zero comparison baseline as non-comparable"
        )
        try expect(comparedTwo?.characterChange == -10, "reports absolute application change")
        try expect(
            abs((comparedTwo?.relativeCharacterChange ?? 0) - (-10.0 / 12.0)) < 0.000_001,
            "reports relative application change"
        )
        let currentRhythmCell = comparisonReport.weekdayHourDistribution.first {
            $0.weekday == calendar.component(.weekday, from: now)
                && $0.hour == calendar.component(.hour, from: now)
        }
        let baselineRhythmCell = comparisonReport.weekdayHourDistribution.first {
            $0.weekday == calendar.component(.weekday, from: yesterday)
                && $0.hour == calendar.component(.hour, from: yesterday)
        }
        try expect(
            currentRhythmCell?.characterCount == 9
                && currentRhythmCell?.comparisonCharacterCount == 0,
            "keeps current rhythm counts in the selected weekday-hour cell"
        )
        try expect(
            baselineRhythmCell?.characterCount == 0
                && baselineRhythmCell?.comparisonCharacterCount == 12,
            "places comparison rhythm counts by their own weekday and hour"
        )
        try expect(
            comparisonReport.weekdayHourDistribution.reduce(0) {
                $0 + $1.comparisonCharacterCount
            } == 12,
            "preserves the comparison range total across rhythm cells"
        )
        let twoDaysAgoRange = TypingDateRange(startDate: twoDaysAgo, endDate: twoDaysAgo)
        let splitRangeReport = try await store.loadReport(
            range: TypingDateRange(startDate: now, endDate: now),
            comparisonRange: twoDaysAgoRange,
            rhythmRange: TypingDateRange(startDate: now, endDate: now),
            rhythmComparisonRange: TypingDateRange(
                startDate: yesterday,
                endDate: yesterday
            )
        )
        try expect(
            splitRangeReport.comparisonMetrics?.characterCount == 0,
            "keeps the annual comparison independent from the rhythm comparison"
        )
        try expect(
            splitRangeReport.weekdayHourDistribution.reduce(0) {
                $0 + $1.characterCount
            } == 9,
            "loads the requested rolling rhythm period"
        )
        try expect(
            splitRangeReport.weekdayHourDistribution.reduce(0) {
                $0 + $1.comparisonCharacterCount
            } == 12,
            "loads a nonzero immediately preceding rhythm period"
        )
        try expect(
            splitRangeReport.rhythmRange == TypingDateRange(
                startDate: calendar.startOfDay(for: now),
                endDate: calendar.startOfDay(for: now)
            ) && splitRangeReport.rhythmComparisonRange == TypingDateRange(
                startDate: calendar.startOfDay(for: yesterday),
                endDate: calendar.startOfDay(for: yesterday)
            ),
            "reports the independent rhythm date ranges used for the matrix"
        )
        let reversedReport = try await store.loadReport(range: TypingDateRange(
            startDate: now,
            endDate: yesterday
        ))
        try expect(
            reversedReport.range.startDate <= reversedReport.range.endDate
                && reversedReport.metrics.characterCount == 21,
            "normalizes a reversed date range"
        )

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
        try expect(clearedSnapshot.recentAppTimelines.isEmpty, "clears application timelines")
        try expect(clearedSnapshot.todayKeyCounts.isEmpty, "clears today's key counts")
        try expect(clearedSnapshot.allTimeKeyCounts.isEmpty, "clears lifetime key counts")

        try await testModelSemantics(in: directory, now: now, application: appOne)
        try await testPartialSnapshotRefreshMerging(now: now, application: appOne)
        try await testQueuedRefreshPriority(now: now)
        try await testFailedBatchMerge(now: now, application: appOne)
        try await testFailureSuspensionAndRecovery(now: now, application: appOne)
        try await testFlushBarrier(now: now, application: appOne)
        try await testClearBarrier(now: now, application: appOne)
        try await testMidnightDateBoundary(now: now, application: appOne)
        try await testRetention(in: directory, now: now, application: appOne)
        try testReusableStatementRecovery()
        try await testVersionOneMigration(in: directory, now: now, application: appOne)
        try await testTimelineRangeBoundaries(
            in: directory,
            now: now,
            application: appOne
        )
        try await testFutureSchema(in: directory, now: now)
        try testHeatmapScale()
        try testHeatmapHoverSourceContract()

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

    private static func testReusableStatementRecovery() throws {
        var database: OpaquePointer?
        guard sqlite3_open(":memory:", &database) == SQLITE_OK, let database else {
            throw HarnessError.message("could not create statement-cache fixture")
        }
        let connection = TypingStatsSQLiteConnection(pointer: database)
        guard sqlite3_exec(
            database,
            "CREATE TABLE Probe (Value INTEGER PRIMARY KEY);",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw HarnessError.message("could not create statement-cache table")
        }

        let sql = "INSERT INTO Probe (Value) VALUES (?1);"
        let first = try connection.reusableStatement(for: .upsertApplication, sql: sql)
        sqlite3_bind_int64(first, 1, 1)
        try expect(sqlite3_step(first) == SQLITE_DONE, "primes a reusable SQLite statement")

        let duplicate = try connection.reusableStatement(for: .upsertApplication, sql: sql)
        sqlite3_bind_int64(duplicate, 1, 1)
        try expect(
            sqlite3_step(duplicate) & 0xFF == SQLITE_CONSTRAINT,
            "captures a reusable statement constraint failure"
        )

        let recovered = try connection.reusableStatement(for: .upsertApplication, sql: sql)
        sqlite3_bind_int64(recovered, 1, 2)
        try expect(
            sqlite3_step(recovered) == SQLITE_DONE,
            "recovers a cached statement after a prior SQLite constraint failure"
        )
    }

    private static func testRollingRhythmRanges(
        now: Date,
        calendar: Calendar
    ) throws {
        let ranges = TypingRhythmDateRanges.rollingSevenDays(
            endingAt: now,
            calendar: calendar
        )
        try expect(
            calendar.dateComponents(
                [.day],
                from: ranges.current.startDate,
                to: ranges.current.endDate
            ).day == 6,
            "uses seven inclusive local days for the current rhythm period"
        )
        try expect(
            calendar.dateComponents(
                [.day],
                from: ranges.comparison.startDate,
                to: ranges.comparison.endDate
            ).day == 6,
            "uses seven inclusive local days for the comparison rhythm period"
        )
        try expect(
            calendar.date(byAdding: .day, value: 1, to: ranges.comparison.endDate)
                == ranges.current.startDate,
            "keeps the rolling rhythm periods adjacent without overlap"
        )
        try expect(
            ranges.current.endDate == calendar.startOfDay(for: now),
            "ends the current rhythm period on today"
        )

        let nextDay = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let nextRanges = TypingRhythmDateRanges.rollingSevenDays(
            endingAt: nextDay,
            calendar: calendar
        )
        try expect(
            nextRanges.current.startDate
                == calendar.date(byAdding: .day, value: 1, to: ranges.current.startDate)
                && nextRanges.current.endDate
                    == calendar.date(byAdding: .day, value: 1, to: ranges.current.endDate)
                && nextRanges.comparison.startDate
                    == calendar.date(byAdding: .day, value: 1, to: ranges.comparison.startDate)
                && nextRanges.comparison.endDate
                    == calendar.date(byAdding: .day, value: 1, to: ranges.comparison.endDate),
            "rolls both rhythm periods forward at the next local midnight"
        )
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

    private static func testPartialSnapshotRefreshMerging(
        now: Date,
        application: TypingApplicationIdentity
    ) async throws {
        let persistence = PartialSnapshotTypingStatsPersistence(now: now, application: application)
        let model = TypingStatsModel(persistence: persistence)

        await model.refresh()
        guard let overviewSnapshot = model.snapshot else {
            throw HarnessError.message("overview refresh did not publish a snapshot")
        }
        try expect(overviewSnapshot.apps.count == 1, "overview refresh loads application ranking")
        try expect(overviewSnapshot.recentBuckets.count == 1, "overview refresh loads recent buckets")
        try expect(overviewSnapshot.todayKeyCounts[0] == 1, "overview refresh loads key counts")
        try expect(model.readStatus.lastReadAt == now, "initial refresh publishes its read time")

        let laterReadDate = now.addingTimeInterval(10)
        await persistence.setGeneratedAt(laterReadDate)
        await model.refresh(for: .summary)
        guard let summarySnapshot = model.snapshot else {
            throw HarnessError.message("summary refresh cleared the snapshot")
        }
        try expect(summarySnapshot.apps.count == 1, "summary refresh preserves cached application ranking")
        try expect(
            summarySnapshot.recentBuckets.count == 1,
            "summary refresh preserves cached recent buckets"
        )
        try expect(summarySnapshot.todayKeyCounts[0] == 1, "summary refresh preserves cached key counts")
        try expect(
            summarySnapshot.generatedAt == overviewSnapshot.generatedAt,
            "unchanged automatic refresh does not republish the heavy snapshot"
        )
        try expect(
            model.readStatus.lastReadAt == laterReadDate,
            "unchanged automatic refresh still publishes the visible read time"
        )

        await persistence.setKeyboardCount(5)
        await model.refresh(for: .keyboard)
        guard let keyboardSnapshot = model.snapshot else {
            throw HarnessError.message("keyboard refresh cleared the snapshot")
        }
        try expect(keyboardSnapshot.todayKeyCounts[0] == 5, "keyboard refresh updates key counts")
        try expect(
            keyboardSnapshot.apps.count == 1 && keyboardSnapshot.recentBuckets.count == 1,
            "keyboard refresh preserves overview-only data while updating key counts"
        )
    }

    private static func testQueuedRefreshPriority(now: Date) async throws {
        let persistence = GatedSnapshotTypingStatsPersistence(now: now)
        let model = TypingStatsModel(persistence: persistence)

        let initialRefresh = Task { await model.refresh(for: .summary) }
        await persistence.waitUntilLoadStarted(1)

        await model.refresh(for: .keyboard, showsActivity: true)
        try expect(model.isRefreshing, "queued manual refresh immediately shows activity")
        await model.refresh(for: .summary)

        await persistence.releaseLoad(1)
        await initialRefresh.value
        await persistence.waitUntilLoadStarted(2)

        let requests = await persistence.capturedRequests()
        try expect(requests.count == 2, "runs a queued refresh after the active request")
        try expect(
            requests[1].sections.contains(.keyCounts),
            "summary polling does not overwrite a queued keyboard refresh"
        )

        await persistence.releaseLoad(2)
        for _ in 0..<100 {
            if !model.isRefreshing { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        try expect(!model.isRefreshing, "queued manual refresh clears activity after completion")
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

    private static func testTimelineRangeBoundaries(
        in directory: URL,
        now: Date,
        application: TypingApplicationIdentity
    ) async throws {
        let rollingNow = now.addingTimeInterval(37.4)
        let endExclusive = Int64(rollingNow.timeIntervalSince1970) + 1
        let start = endExclusive - TypingTimelineRange.oneHour.durationSeconds
        let databaseURL = directory.appendingPathComponent(
            "typing-stats-range-boundaries.sqlite3"
        )
        let store = TypingStatsStore(databaseURL: databaseURL, nowProvider: { rollingNow })
        let dateKey = TypingStatsStore.dateKey(for: rollingNow, calendar: statisticsCalendar)

        try await store.record(TypingStatsWriteBatch(
            characterAggregates: [
                TypingCharacterAggregate(
                    secondStart: start - 1,
                    localDate: dateKey,
                    application: application,
                    count: 11
                ),
                TypingCharacterAggregate(
                    secondStart: start,
                    localDate: dateKey,
                    application: application,
                    count: 2
                ),
                TypingCharacterAggregate(
                    secondStart: endExclusive - 1,
                    localDate: dateKey,
                    application: application,
                    count: 3
                ),
                TypingCharacterAggregate(
                    secondStart: endExclusive,
                    localDate: dateKey,
                    application: application,
                    count: 13
                ),
            ],
            keyAggregates: []
        ))

        let snapshot = try await store.loadSnapshot(timelineRange: .oneHour)
        try expect(
            snapshot.recentBuckets.reduce(0) { $0 + $1.characterCount } == 5,
            "one-hour range includes its first and last second without adjacent data"
        )
        try expect(
            snapshot.recentBuckets.first?.start
                == Date(timeIntervalSince1970: TimeInterval(start)),
            "rolling range starts at the exact requested boundary"
        )
        try expect(
            snapshot.recentBuckets.last?.start.addingTimeInterval(60)
                == Date(timeIntervalSince1970: TimeInterval(endExclusive)),
            "rolling range ends at the current second instead of a future minute"
        )
        try expect(
            snapshot.recentAppTimelines.first?.rangeCharacterCount == 5,
            "application heatmap total matches the global rolling range"
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
        try expect(snapshot.todayKeyCounts[0] == nil, "does not mix old keys into today's detail")
        try expect(snapshot.allTimeKeyCounts[0] == 7, "retains lifetime key totals after cleanup")
        let retainedSecondRows = try readScalar(
            "SELECT COUNT(*) FROM CharacterSecondStat;",
            from: url
        )
        try expect(
            retainedSecondRows == 0,
            "deletes second-level detail after the retention window"
        )
        let retainedDailyKeyCount = try readScalar(
            "SELECT PressCount FROM KeyDailyStat WHERE LocalDate = '\(oldDateKey)';",
            from: url
        )
        try expect(
            retainedDailyKeyCount == 7,
            "keeps per-day key counts permanently"
        )
        let oldReport = try await store.loadReport(range: TypingDateRange(
            startDate: oldDate,
            endDate: oldDate
        ))
        try expect(
            oldReport.metrics.characterCount == 9,
            "keeps daily character aggregates after detailed cleanup"
        )
        try expect(
            oldReport.applications.first?.characterCount == 9,
            "keeps application-day aggregates after detailed cleanup"
        )
        try expect(
            oldReport.hourlyDistribution.reduce(0) { $0 + $1.characterCount } == 9,
            "keeps hour-day aggregates after detailed cleanup"
        )
    }

    private static func testVersionOneMigration(
        in directory: URL,
        now: Date,
        application: TypingApplicationIdentity
    ) async throws {
        let url = directory.appendingPathComponent("version-one.sqlite3")
        var database: OpaquePointer?
        try expect(sqlite3_open(url.path, &database) == SQLITE_OK, "opens v1 migration fixture")
        guard let database else { throw HarnessError.message("missing v1 migration database") }
        let calendar = statisticsCalendar
        let dateKey = TypingStatsStore.dateKey(for: now, calendar: calendar)
        let second = Int64(now.timeIntervalSince1970)
        let escapedProcessKey = application.processKey.replacingOccurrences(of: "'", with: "''")
        let escapedDisplayName = application.displayName.replacingOccurrences(of: "'", with: "''")
        let escapedProcessName = application.processName.replacingOccurrences(of: "'", with: "''")
        do {
            try execute(
                """
                CREATE TABLE AppProfile (
                    Id INTEGER PRIMARY KEY,
                    ProcessKey TEXT NOT NULL UNIQUE,
                    ProcessName TEXT NOT NULL,
                    DisplayName TEXT NOT NULL,
                    BundleIdentifier TEXT,
                    UpdatedAtUtc INTEGER NOT NULL
                );
                CREATE TABLE CharacterSecondStat (
                    SecondStartUtc INTEGER NOT NULL,
                    LocalDate TEXT NOT NULL,
                    AppId INTEGER NOT NULL REFERENCES AppProfile(Id),
                    CharacterCount INTEGER NOT NULL CHECK(CharacterCount >= 0),
                    UpdatedAtUtc INTEGER NOT NULL,
                    PRIMARY KEY (SecondStartUtc, AppId)
                ) WITHOUT ROWID;
                CREATE INDEX IX_CharacterSecondStat_Date
                    ON CharacterSecondStat(LocalDate, SecondStartUtc);
                CREATE INDEX IX_CharacterSecondStat_DateApp
                    ON CharacterSecondStat(LocalDate, AppId);
                CREATE TABLE KeyDailyStat (
                    LocalDate TEXT NOT NULL,
                    KeyCode INTEGER NOT NULL,
                    PressCount INTEGER NOT NULL CHECK(PressCount >= 0),
                    UpdatedAtUtc INTEGER NOT NULL,
                    PRIMARY KEY (LocalDate, KeyCode)
                ) WITHOUT ROWID;
                CREATE TABLE KeyTotalStat (
                    KeyCode INTEGER PRIMARY KEY,
                    PressCount INTEGER NOT NULL CHECK(PressCount >= 0),
                    UpdatedAtUtc INTEGER NOT NULL
                );
                INSERT INTO AppProfile (
                    Id, ProcessKey, ProcessName, DisplayName, BundleIdentifier, UpdatedAtUtc
                ) VALUES (
                    1, '\(escapedProcessKey)', '\(escapedProcessName)',
                    '\(escapedDisplayName)', NULL, \(second)
                );
                INSERT INTO CharacterSecondStat (
                    SecondStartUtc, LocalDate, AppId, CharacterCount, UpdatedAtUtc
                ) VALUES
                    (\(second), '\(dateKey)', 1, 3, \(second)),
                    (\(second - 60), '\(dateKey)', 1, 4, \(second));
                INSERT INTO KeyDailyStat VALUES ('\(dateKey)', 0, 6, \(second));
                INSERT INTO KeyTotalStat VALUES (0, 6, \(second));
                PRAGMA user_version = 1;
                """,
                in: database
            )
        } catch {
            sqlite3_close_v2(database)
            throw error
        }
        sqlite3_close_v2(database)

        let migrated = TypingStatsStore(databaseURL: url, nowProvider: { now })
        var snapshot = try await migrated.loadSnapshot()
        let migratedVersion = try readUserVersion(url)
        try expect(migratedVersion == 2, "migrates a v1 database to schema two")
        try expect(snapshot.today.characterCount == 7, "backfills permanent daily totals")
        try expect(snapshot.today.activeMinuteBuckets == 2, "backfills active minutes")
        try expect(snapshot.today.activeSeconds == 2, "backfills active seconds")
        try expect(snapshot.today.peakCPS == 4, "backfills daily peak speed")
        let report = try await migrated.loadReport(range: TypingDateRange(
            startDate: now,
            endDate: now
        ))
        try expect(report.applications.first?.characterCount == 7, "backfills app-day totals")
        try expect(
            report.hourlyDistribution.reduce(0) { $0 + $1.characterCount } == 7,
            "backfills hour-day totals"
        )

        try await migrated.record(TypingStatsWriteBatch(
            characterAggregates: [
                TypingCharacterAggregate(
                    secondStart: second,
                    localDate: dateKey,
                    application: application,
                    count: 2
                ),
            ],
            keyAggregates: []
        ))
        snapshot = try await migrated.loadSnapshot()
        try expect(snapshot.today.characterCount == 9, "continues aggregate totals after migration")
        try expect(snapshot.today.peakCPS == 5, "continues peak tracking after migration")
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

    private static func testHeatmapScale() throws {
        let empty = TypingHeatmapScale(
            values: [0, -Double.infinity, Double.infinity, Double.nan]
        )
        try expect(!empty.hasValues, "ignores zero and non-finite heatmap values")
        try expect(empty.normalized(8) == 0, "keeps an empty heatmap scale at zero")

        let sparse = TypingHeatmapScale(values: [0, 2, 6, 10])
        try expect(sparse.low == 2 && sparse.high == 10, "uses min and max for a sparse heatmap")
        try expect(sparse.normalized(2) == 0, "maps the visible minimum to the start of the ramp")
        try expect(sparse.normalized(6) == 0.5, "interpolates sparse heatmap values linearly")
        try expect(sparse.normalized(20) == 1, "clamps values beyond the automatic upper bound")
        try expect(sparse.normalized(0) == 0, "keeps zero cells outside the colored range")

        let uniform = TypingHeatmapScale(values: [5, 5, 5])
        try expect(uniform.normalized(5) == 1, "lights a uniform non-zero heatmap")

        let dense = TypingHeatmapScale(
            values: (1...20).map(Double.init) + [100]
        )
        try expect(dense.low == 1 && dense.high == 20, "uses interpolated P95 for a dense heatmap")
        try expect(dense.normalized(10.5) == 0.5, "linearly maps values inside the P95 range")
        try expect(dense.normalized(100) == 1, "clips a dense outlier at P95")

        let diverging = TypingDivergingHeatmapScale(
            values: (-20 ... -1).map(Double.init) + [100]
        )
        try expect(diverging.limit == 20, "uses absolute P95 for a symmetric difference range")
        try expect(diverging.normalized(-10) == -0.5, "maps negative differences symmetrically")
        try expect(diverging.normalized(10) == 0.5, "maps positive differences symmetrically")
        try expect(diverging.normalized(100) == 1, "clamps difference outliers symmetrically")
        try expect(diverging.normalized(0) == 0, "keeps zero at the diverging neutral centre")
    }

    private static func testHeatmapHoverSourceContract() throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let annualSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "SimuBoardMac/SimuBoardMac/Views/TypingYearHeatmap.swift"
            ),
            encoding: .utf8
        )
        let rhythmSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "SimuBoardMac/SimuBoardMac/Views/TypingStatsReportView.swift"
            ),
            encoding: .utf8
        )
        let overviewSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "SimuBoardMac/SimuBoardMac/Views/TypingStatsOverviewView.swift"
            ),
            encoding: .utf8
        )
        let keyboardSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "SimuBoardMac/SimuBoardMac/Views/TypingStatsKeyboardView.swift"
            ),
            encoding: .utf8
        )
        let styleSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "SimuBoardMac/SimuBoardMac/Views/BattutaVisualStyle.swift"
            ),
            encoding: .utf8
        )

        let annualGrid = try sourceSlice(
            annualSource,
            from: "private struct TypingYearHeatmapInteractiveGrid: View",
            to: "/// Immutable render data"
        )
        try expect(
            annualGrid.contains(".onHover")
                && annualGrid.contains(".onTapGesture")
                && annualGrid.contains("BattutaHeatmapTooltip"),
            "shows annual cell details immediately and supports click pinning"
        )
        try expect(
            !annualGrid.contains(".help(")
                && annualSource.contains(
                    "detailText: L10n.format(\"%@ · %@ 个字符\", dateText, formattedCount)"
                ),
            "does not rely on AppKit's delayed annual help tooltip"
        )

        let rhythmCell = try sourceSlice(
            rhythmSource,
            from: "private struct TypingWeekdayHourInteractiveGrid: View",
            to: "@MainActor\nprivate enum TypingReportApplicationIconCache"
        )
        try expect(
            rhythmCell.contains(".onHover")
                && rhythmCell.contains(".onTapGesture")
                && rhythmCell.contains("BattutaHeatmapTooltip")
                && !rhythmCell.contains(".help(cell.detail)"),
            "shows rhythm cell details immediately and supports click pinning"
        )
        try expect(
            rhythmSource.contains("statsCount(value.characterCount)")
                && rhythmSource.contains("statsCount(value.comparisonCharacterCount)"),
            "includes current and comparison character totals in rhythm hover details"
        )
        try expect(
            annualSource.contains("TypingHeatmapScale(values: visibleCounts)")
                && rhythmSource.contains("TypingDivergingHeatmapScale")
                && overviewSource.contains("TypingHeatmapScale")
                && keyboardSource.contains("TypingHeatmapScale"),
            "recomputes automatic ranges for every displayed heatmap family"
        )
        try expect(
            annualSource.contains("BattutaHeatmapLegend")
                && rhythmSource.contains("BattutaHeatmapLegend")
                && overviewSource.contains("BattutaHeatmapLegend")
                && keyboardSource.contains("BattutaHeatmapLegend")
                && styleSource.contains("LinearGradient")
                && styleSource.contains("BattutaHeatmapPalette.sequentialGradient"),
            "uses continuous legends backed by the same shared heatmap palette"
        )
    }

    private static func sourceSlice(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        guard let start = source.range(of: startMarker)?.lowerBound,
              let end = source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound else {
            throw HarnessError.message("could not isolate source contract between markers")
        }
        return source[start..<end]
    }

    private static func sourceOffset(of marker: String, in source: Substring) throws -> Int {
        guard let range = source.range(of: marker) else {
            throw HarnessError.message("source contract is missing: \(marker)")
        }
        return source.distance(from: source.startIndex, to: range.lowerBound)
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

    private static func readScalar(_ sql: String, from url: URL) throws -> Int64 {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            throw HarnessError.message("cannot open fixture to read scalar")
        }
        defer { sqlite3_close_v2(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw HarnessError.message("cannot prepare scalar")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw HarnessError.message("cannot step scalar")
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

    func loadSnapshot(timelineRange: TypingTimelineRange) async throws -> TypingStatsSnapshot {
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

    func loadSnapshot(timelineRange: TypingTimelineRange) async throws -> TypingStatsSnapshot {
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

    func loadSnapshot(timelineRange: TypingTimelineRange) async throws -> TypingStatsSnapshot {
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

    func loadSnapshot(timelineRange: TypingTimelineRange) async throws -> TypingStatsSnapshot {
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
            timelineRange: timelineRange,
            recentBuckets: [],
            apps: [],
            recentAppTimelines: [],
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

    func loadSnapshot(timelineRange: TypingTimelineRange) async throws -> TypingStatsSnapshot {
        throw TypingStatsStoreError.queryFailed("not used")
    }

    func clearAll() async throws { captured = TypingStatsWriteBatch(characterAggregates: [], keyAggregates: []) }

    func capturedBatch() -> TypingStatsWriteBatch { captured }
}

private actor GatedSnapshotTypingStatsPersistence: TypingStatsPersistence {
    private let now: Date
    private var requests: [TypingStatsSnapshotRequest] = []
    private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
    private var releasedLoads: Set<Int> = []
    private var startWaiters: [(attempt: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(now: Date) {
        self.now = now
    }

    func record(_ batch: TypingStatsWriteBatch) async throws {}

    func loadSnapshot(timelineRange: TypingTimelineRange) async throws -> TypingStatsSnapshot {
        try await loadSnapshot(
            request: TypingStatsSnapshotRequest(
                timelineRange: timelineRange,
                sections: .all
            )
        )
    }

    func loadSnapshot(request: TypingStatsSnapshotRequest) async throws -> TypingStatsSnapshot {
        let attempt = requests.count + 1
        requests.append(request)

        let ready = startWaiters.filter { $0.attempt <= attempt }
        startWaiters.removeAll { $0.attempt <= attempt }
        ready.forEach { $0.continuation.resume() }

        if releasedLoads.remove(attempt) == nil {
            await withCheckedContinuation { continuation in
                gates[attempt] = continuation
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        let day = TypingDaySummary(
            dateKey: TypingStatsStore.dateKey(for: now, calendar: calendar),
            date: calendar.startOfDay(for: now),
            characterCount: 0,
            peakCPS: 0,
            activeMinuteBuckets: 0,
            activeSeconds: 0,
            topAppName: nil,
            lastUpdatedAt: nil
        )
        let keyCounts: [UInt16: Int64] = request.sections.contains(.keyCounts)
            ? [0: Int64(attempt)]
            : [:]
        return TypingStatsSnapshot(
            generatedAt: now.addingTimeInterval(TimeInterval(attempt)),
            lastInputAt: nil,
            today: day,
            timelineRange: request.timelineRange,
            recentBuckets: [],
            apps: [],
            recentAppTimelines: [],
            history: [],
            todayKeyCounts: keyCounts,
            allTimeKeyCounts: keyCounts
        )
    }

    func clearAll() async throws {}

    func waitUntilLoadStarted(_ attempt: Int) async {
        if requests.count >= attempt { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((attempt, continuation))
        }
    }

    func releaseLoad(_ attempt: Int) {
        if let continuation = gates.removeValue(forKey: attempt) {
            continuation.resume()
        } else {
            releasedLoads.insert(attempt)
        }
    }

    func capturedRequests() -> [TypingStatsSnapshotRequest] { requests }
}

private actor PartialSnapshotTypingStatsPersistence: TypingStatsPersistence {
    private let now: Date
    private let application: TypingApplicationIdentity
    private var keyboardCount: Int64 = 1
    private var generatedAt: Date

    init(now: Date, application: TypingApplicationIdentity) {
        self.now = now
        self.application = application
        generatedAt = now
    }

    func record(_ batch: TypingStatsWriteBatch) async throws {}

    func loadSnapshot(timelineRange: TypingTimelineRange) async throws -> TypingStatsSnapshot {
        try await loadSnapshot(
            request: TypingStatsSnapshotRequest(
                timelineRange: timelineRange,
                sections: .all
            )
        )
    }

    func loadSnapshot(request: TypingStatsSnapshotRequest) async throws -> TypingStatsSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        let today = TypingDaySummary(
            dateKey: TypingStatsStore.dateKey(for: now, calendar: calendar),
            date: calendar.startOfDay(for: now),
            characterCount: 3,
            peakCPS: 3,
            activeMinuteBuckets: 1,
            activeSeconds: 1,
            topAppName: application.displayName,
            lastUpdatedAt: now
        )
        let recentBuckets = request.sections.contains(.recentBuckets)
            ? [TypingBucket(index: 0, start: now, characterCount: 3)]
            : []
        let apps = request.sections.contains(.applications)
            ? [
                TypingAppSummary(
                    processKey: application.processKey,
                    displayName: application.displayName,
                    processName: application.processName,
                    bundleIdentifier: application.bundleIdentifier,
                    characterCount: 3,
                    activeMinuteBuckets: 1,
                    activeSeconds: 1,
                    peakCPS: 3
                ),
            ]
            : []
        let appTimelines = request.sections.contains(.recentAppTimelines)
            ? [TypingAppTimeline(application: application, buckets: recentBuckets)]
            : []
        let history = request.sections.contains(.history) ? [today] : []
        let keyCounts = request.sections.contains(.keyCounts) ? [UInt16(0): keyboardCount] : [:]

        return TypingStatsSnapshot(
            generatedAt: generatedAt,
            lastInputAt: now,
            today: today,
            timelineRange: request.timelineRange,
            recentBuckets: recentBuckets,
            apps: apps,
            recentAppTimelines: appTimelines,
            history: history,
            todayKeyCounts: keyCounts,
            allTimeKeyCounts: keyCounts
        )
    }

    func loadReport(
        range: TypingDateRange,
        comparisonRange: TypingDateRange?
    ) async throws -> TypingRangeReportSnapshot {
        throw TypingStatsStoreError.queryFailed("not used")
    }

    func clearAll() async throws {}

    func setKeyboardCount(_ count: Int64) {
        keyboardCount = count
    }

    func setGeneratedAt(_ date: Date) {
        generatedAt = date
    }
}

private enum HarnessError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message): message
        }
    }
}
