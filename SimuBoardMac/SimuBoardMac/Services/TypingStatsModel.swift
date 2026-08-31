import Combine
import Foundation

@MainActor
final class TypingStatsReadStatus: ObservableObject {
    @Published private(set) var lastReadAt: Date?

    func markRead(at date: Date) {
        guard lastReadAt != date else { return }
        lastReadAt = date
    }
}

enum TypingStatsRefreshTarget: Sendable {
    case summary
    case overview
    case history
    case keyboard

    func merged(with other: Self) -> Self {
        func breadth(_ target: Self) -> Int {
            switch target {
            case .summary, .history: 0
            case .keyboard: 1
            case .overview: 2
            }
        }

        return breadth(self) > breadth(other) ? self : other
    }
}

@MainActor
final class TypingStatsModel: ObservableObject {
    private struct PendingRefreshRequest {
        let target: TypingStatsRefreshTarget
        let showsActivity: Bool
        let publishesUnchangedSnapshot: Bool

        func merged(with other: Self) -> Self {
            Self(
                target: target.merged(with: other.target),
                showsActivity: showsActivity || other.showsActivity,
                publishesUnchangedSnapshot: publishesUnchangedSnapshot
                    || other.publishesUnchangedSnapshot
            )
        }
    }

    private struct PendingCharacterKey: Hashable {
        let secondStart: Int64
        let localDate: String
        let application: TypingApplicationIdentity
    }

    private struct PendingKeyPressKey: Hashable {
        let localDate: String
        let keyCode: UInt16
    }

    @Published private(set) var snapshot: TypingStatsSnapshot?
    @Published private(set) var sourceStatus: TypingStatsSourceStatus = .checking
    @Published private(set) var isRefreshing = false
    @Published private(set) var isClearing = false
    @Published private(set) var isRecordingSuspended = false
    @Published private(set) var timelineRange: TypingTimelineRange = .oneHour
    @Published private(set) var reportSnapshot: TypingRangeReportSnapshot?
    @Published private(set) var isLoadingReport = false
    @Published private(set) var reportErrorMessage: String?
    let readStatus = TypingStatsReadStatus()

    private let persistence: any TypingStatsPersistence
    private var pendingCharacters: [PendingCharacterKey: Int64] = [:]
    private var pendingKeyPresses: [PendingKeyPressKey: Int64] = [:]
    private var isRefreshInFlight = false
    private var pendingRefreshRequest: PendingRefreshRequest?
    /// A failed, already-materialized batch is kept separate so retrying never re-sorts
    /// the continuously growing live dictionaries on the main actor.
    private var retryBatch: TypingStatsWriteBatch?
    private var scheduledFlushTask: Task<Void, Never>?
    private var isFlushing = false
    private var flushWaiters: [CheckedContinuation<Bool, Never>] = []
    private var lastWriteError: String?
    private var consecutiveWriteFailures = 0
    private var cachedDateInterval: DateInterval?
    private var cachedDateKey: String?
    private var cachedTimeZoneIdentifier: String?
    private var reportRequestID = 0

    init(persistence: any TypingStatsPersistence = TypingStatsStore()) {
        self.persistence = persistence
    }

    deinit {
        scheduledFlushTask?.cancel()
    }

    var staleDataMessage: String? {
        guard snapshot != nil else { return nil }
        if let lastWriteError { return lastWriteError }
        if case let .failed(message) = sourceStatus { return message }
        return nil
    }

    func selectTimelineRange(_ range: TypingTimelineRange) {
        guard timelineRange != range else { return }
        timelineRange = range
        Task { await refresh(for: .overview, showsActivity: true) }
    }

    /// O(1) hot-path aggregation. No database work or detached task is created per event.
    func recordKeyDown(
        keyCode: UInt16,
        isRepeat: Bool,
        isShortcutModified: Bool,
        application: TypingApplicationIdentity,
        at occurredAt: Date
    ) {
        guard !isClearing, !isRecordingSuspended else { return }
        let dateKey = localDateKey(for: occurredAt)
        var didRecord = false

        if !isRepeat {
            let key = PendingKeyPressKey(localDate: dateKey, keyCode: keyCode)
            pendingKeyPresses[key, default: 0] += 1
            didRecord = true
        }

        if TypingCharacterKeyFilter.countsAsCharacter(
            keyCode: keyCode,
            isShortcutModified: isShortcutModified
        ) {
            let key = PendingCharacterKey(
                secondStart: Int64(occurredAt.timeIntervalSince1970),
                localDate: dateKey,
                application: application
            )
            pendingCharacters[key, default: 0] += 1
            didRecord = true
        }

        if didRecord { scheduleFlush() }
    }

    @discardableResult
    func flushPending() async -> Bool {
        scheduledFlushTask?.cancel()
        scheduledFlushTask = nil

        if isFlushing {
            return await withCheckedContinuation { continuation in
                flushWaiters.append(continuation)
            }
        }

        isFlushing = true
        var succeeded = true

        while true {
            let batch = takeNextBatch()
            guard !batch.isEmpty else { break }

            do {
                try await persistence.record(batch)
                lastWriteError = nil
                consecutiveWriteFailures = 0
                if isRecordingSuspended { isRecordingSuspended = false }
            } catch is CancellationError {
                retryBatch = batch
                scheduleFlush()
                succeeded = false
                break
            } catch {
                retryBatch = batch
                consecutiveWriteFailures = min(consecutiveWriteFailures + 1, 6)
                if consecutiveWriteFailures >= 6 {
                    isRecordingSuspended = true
                    lastWriteError = L10n.format(
                        "%@ 连续写入失败，输入统计已暂停；打开统计页面刷新或清除数据后可重试。",
                        L10n.tr(error.localizedDescription)
                    )
                } else {
                    lastWriteError = L10n.tr(error.localizedDescription)
                    let retrySeconds = min(60, 1 << consecutiveWriteFailures)
                    scheduleFlush(after: .seconds(retrySeconds))
                }
                setSourceStatus(.failed(lastWriteError ?? L10n.tr(error.localizedDescription)))
                succeeded = false
                break
            }
        }

        isFlushing = false

        let waiters = flushWaiters
        flushWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume(returning: succeeded) }
        return succeeded
    }

    func refresh() async {
        await refresh(for: .overview)
    }

    func refresh(
        for target: TypingStatsRefreshTarget,
        showsActivity: Bool = false,
        publishesUnchangedSnapshot: Bool = false
    ) async {
        guard !isRefreshInFlight else {
            let incomingRequest = PendingRefreshRequest(
                target: target,
                showsActivity: showsActivity,
                publishesUnchangedSnapshot: publishesUnchangedSnapshot
            )
            pendingRefreshRequest = pendingRefreshRequest?.merged(with: incomingRequest)
                ?? incomingRequest
            if showsActivity { isRefreshing = true }
            return
        }
        isRefreshInFlight = true
        if showsActivity { isRefreshing = true }
        defer {
            isRefreshInFlight = false
            if let pendingRefreshRequest {
                self.pendingRefreshRequest = nil
                if !pendingRefreshRequest.showsActivity, showsActivity {
                    isRefreshing = false
                }
                Task { [weak self] in
                    await self?.refresh(
                        for: pendingRefreshRequest.target,
                        showsActivity: pendingRefreshRequest.showsActivity,
                        publishesUnchangedSnapshot: pendingRefreshRequest.publishesUnchangedSnapshot
                    )
                }
            } else if showsActivity {
                isRefreshing = false
            }
        }

        let didFlush = await flushPending()
        while !Task.isCancelled {
            let request = snapshotRequest(for: target)
            do {
                let loadedSnapshot = try await persistence.loadSnapshot(request: request)
                guard !Task.isCancelled else { return }
                guard request.timelineRange == timelineRange else { continue }
                readStatus.markRead(at: loadedSnapshot.generatedAt)
                let mergedSnapshot = mergeSnapshot(loadedSnapshot, request: request)
                if publishesUnchangedSnapshot
                    || snapshot?.hasSameVisibleContent(as: mergedSnapshot) != true
                {
                    snapshot = mergedSnapshot
                }
                if didFlush {
                    setSourceStatus(.available)
                } else if let lastWriteError {
                    setSourceStatus(.failed(lastWriteError))
                }
                return
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                guard request.timelineRange == timelineRange else { continue }
                setSourceStatus(.failed(L10n.tr(error.localizedDescription)))
                return
            }
        }
    }

    func loadReport(
        range: TypingDateRange,
        comparisonRange: TypingDateRange?,
        rhythmRange: TypingDateRange? = nil,
        rhythmComparisonRange: TypingDateRange? = nil
    ) async {
        reportRequestID += 1
        let requestID = reportRequestID
        isLoadingReport = true
        defer {
            if requestID == reportRequestID {
                isLoadingReport = false
            }
        }

        _ = await flushPending()
        do {
            let report = try await loadCombinedReport(
                range: range,
                comparisonRange: comparisonRange,
                rhythmRange: rhythmRange,
                rhythmComparisonRange: rhythmComparisonRange
            )
            guard requestID == reportRequestID, !Task.isCancelled else { return }
            if reportSnapshot?.hasSameVisibleContent(as: report) != true {
                reportSnapshot = report
            }
            if reportErrorMessage != nil { reportErrorMessage = nil }
        } catch is CancellationError {
            return
        } catch {
            guard requestID == reportRequestID else { return }
            reportErrorMessage = L10n.tr(error.localizedDescription)
        }
    }

    func refreshCurrentReport() async {
        guard let reportSnapshot else { return }
        await loadReport(
            range: reportSnapshot.range,
            comparisonRange: reportSnapshot.comparisonRange,
            rhythmRange: reportSnapshot.rhythmRange,
            rhythmComparisonRange: reportSnapshot.rhythmComparisonRange
        )
    }

    @discardableResult
    func clearAll() async -> Bool {
        guard !isClearing else { return false }
        isClearing = true
        defer { isClearing = false }

        _ = await flushPending()
        scheduledFlushTask?.cancel()
        scheduledFlushTask = nil
        pendingCharacters.removeAll(keepingCapacity: true)
        pendingKeyPresses.removeAll(keepingCapacity: true)
        retryBatch = nil

        let previousReportRange = reportSnapshot?.range
        let previousComparisonRange = reportSnapshot?.comparisonRange
        let previousRhythmRange = reportSnapshot?.rhythmRange
        let previousRhythmComparisonRange = reportSnapshot?.rhythmComparisonRange

        do {
            try await persistence.clearAll()
            consecutiveWriteFailures = 0
            lastWriteError = nil
            isRecordingSuspended = false
            let loadedSnapshot = try await persistence.loadSnapshot(timelineRange: timelineRange)
            readStatus.markRead(at: loadedSnapshot.generatedAt)
            snapshot = loadedSnapshot
            if let previousReportRange, let previousRhythmRange {
                reportSnapshot = try await loadCombinedReport(
                    range: previousReportRange,
                    comparisonRange: previousComparisonRange,
                    rhythmRange: previousRhythmRange,
                    rhythmComparisonRange: previousRhythmComparisonRange
                )
            } else {
                reportSnapshot = nil
            }
            reportErrorMessage = nil
            sourceStatus = .available
            return true
        } catch {
            lastWriteError = L10n.tr(error.localizedDescription)
            sourceStatus = .failed(L10n.tr(error.localizedDescription))
            return false
        }
    }

    private func loadCombinedReport(
        range: TypingDateRange,
        comparisonRange: TypingDateRange?,
        rhythmRange: TypingDateRange?,
        rhythmComparisonRange: TypingDateRange?
    ) async throws -> TypingRangeReportSnapshot {
        try await persistence.loadReport(
            range: range,
            comparisonRange: comparisonRange,
            rhythmRange: rhythmRange,
            rhythmComparisonRange: rhythmComparisonRange
        )
    }

    private func scheduleFlush(after delay: Duration = .milliseconds(750)) {
        guard scheduledFlushTask == nil else { return }
        scheduledFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay, tolerance: .milliseconds(100))
            } catch {
                return
            }
            guard let self else { return }
            self.scheduledFlushTask = nil
            await self.flushPending()
        }
    }

    private func drainPendingBatch() -> TypingStatsWriteBatch {
        let characterAggregates = pendingCharacters.map { key, count in
            TypingCharacterAggregate(
                secondStart: key.secondStart,
                localDate: key.localDate,
                application: key.application,
                count: count
            )
        }
        .sorted {
            if $0.secondStart != $1.secondStart {
                return $0.secondStart < $1.secondStart
            }
            return $0.application.processKey < $1.application.processKey
        }

        let keyAggregates = pendingKeyPresses.map { key, count in
            TypingKeyAggregate(localDate: key.localDate, keyCode: key.keyCode, count: count)
        }
        .sorted {
            if $0.localDate != $1.localDate { return $0.localDate < $1.localDate }
            return $0.keyCode < $1.keyCode
        }

        pendingCharacters.removeAll(keepingCapacity: true)
        pendingKeyPresses.removeAll(keepingCapacity: true)
        return TypingStatsWriteBatch(
            characterAggregates: characterAggregates,
            keyAggregates: keyAggregates
        )
    }

    private func takeNextBatch() -> TypingStatsWriteBatch {
        if let retryBatch {
            self.retryBatch = nil
            return retryBatch
        }
        return drainPendingBatch()
    }

    private func localDateKey(for date: Date) -> String {
        let timeZone = TimeZone.autoupdatingCurrent
        if let cachedDateInterval,
           date >= cachedDateInterval.start,
           date < cachedDateInterval.end,
           cachedTimeZoneIdentifier == timeZone.identifier,
           let cachedDateKey {
            return cachedDateKey
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let interval = calendar.dateInterval(of: .day, for: date)
        let key = TypingStatsStore.dateKey(for: date, calendar: calendar)
        cachedDateInterval = interval
        cachedDateKey = key
        cachedTimeZoneIdentifier = timeZone.identifier
        return key
    }

    private func snapshotRequest(for target: TypingStatsRefreshTarget) -> TypingStatsSnapshotRequest {
        let sections: TypingStatsSnapshotSections
        switch target {
        case .summary, .history:
            sections = []
        case .overview:
            sections = .all
        case .keyboard:
            sections = [.keyCounts]
        }
        return TypingStatsSnapshotRequest(
            timelineRange: timelineRange,
            sections: sections
        )
    }

    private func mergeSnapshot(
        _ incoming: TypingStatsSnapshot,
        request: TypingStatsSnapshotRequest
    ) -> TypingStatsSnapshot {
        guard let snapshot else { return incoming }
        let sections = request.sections
        return TypingStatsSnapshot(
            generatedAt: incoming.generatedAt,
            lastInputAt: incoming.lastInputAt,
            today: incoming.today,
            timelineRange: incoming.timelineRange,
            recentBuckets: sections.contains(.recentBuckets)
                ? incoming.recentBuckets
                : snapshot.recentBuckets,
            apps: sections.contains(.applications)
                ? incoming.apps
                : snapshot.apps,
            recentAppTimelines: sections.contains(.recentAppTimelines)
                ? incoming.recentAppTimelines
                : snapshot.recentAppTimelines,
            history: sections.contains(.history)
                ? incoming.history
                : snapshot.history,
            todayKeyCounts: sections.contains(.keyCounts)
                ? incoming.todayKeyCounts
                : snapshot.todayKeyCounts,
            allTimeKeyCounts: sections.contains(.keyCounts)
                ? incoming.allTimeKeyCounts
                : snapshot.allTimeKeyCounts
        )
    }

    private func setSourceStatus(_ status: TypingStatsSourceStatus) {
        guard sourceStatus != status else { return }
        sourceStatus = status
    }
}
