import Combine
import Foundation

@MainActor
final class TypingStatsModel: ObservableObject {
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

    private let persistence: any TypingStatsPersistence
    private var pendingCharacters: [PendingCharacterKey: Int64] = [:]
    private var pendingKeyPresses: [PendingKeyPressKey: Int64] = [:]
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
        Task { await refresh() }
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
                isRecordingSuspended = false
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
                    lastWriteError = "\(error.localizedDescription) 连续写入失败，输入统计已暂停；打开统计页面刷新或清除数据后可重试。"
                } else {
                    lastWriteError = error.localizedDescription
                    let retrySeconds = min(60, 1 << consecutiveWriteFailures)
                    scheduleFlush(after: .seconds(retrySeconds))
                }
                sourceStatus = .failed(lastWriteError ?? error.localizedDescription)
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
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let didFlush = await flushPending()
        while !Task.isCancelled {
            let requestedRange = timelineRange
            do {
                let loadedSnapshot = try await persistence.loadSnapshot(
                    timelineRange: requestedRange
                )
                guard requestedRange == timelineRange else { continue }
                snapshot = loadedSnapshot
                if didFlush {
                    sourceStatus = .available
                } else if let lastWriteError {
                    sourceStatus = .failed(lastWriteError)
                }
                return
            } catch is CancellationError {
                return
            } catch {
                guard requestedRange == timelineRange else { continue }
                sourceStatus = .failed(error.localizedDescription)
                return
            }
        }
    }

    func loadReport(
        range: TypingDateRange,
        comparisonRange: TypingDateRange?
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
            let report = try await persistence.loadReport(
                range: range,
                comparisonRange: comparisonRange
            )
            guard requestID == reportRequestID, !Task.isCancelled else { return }
            reportSnapshot = report
            reportErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard requestID == reportRequestID else { return }
            reportErrorMessage = error.localizedDescription
        }
    }

    func refreshCurrentReport() async {
        guard let reportSnapshot else { return }
        await loadReport(
            range: reportSnapshot.range,
            comparisonRange: reportSnapshot.comparisonRange
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

        do {
            try await persistence.clearAll()
            consecutiveWriteFailures = 0
            lastWriteError = nil
            isRecordingSuspended = false
            snapshot = try await persistence.loadSnapshot(timelineRange: timelineRange)
            if let previousReportRange {
                reportSnapshot = try await persistence.loadReport(
                    range: previousReportRange,
                    comparisonRange: previousComparisonRange
                )
            } else {
                reportSnapshot = nil
            }
            reportErrorMessage = nil
            sourceStatus = .available
            return true
        } catch {
            lastWriteError = error.localizedDescription
            sourceStatus = .failed(error.localizedDescription)
            return false
        }
    }

    private func scheduleFlush(after delay: Duration = .milliseconds(750)) {
        guard scheduledFlushTask == nil else { return }
        scheduledFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
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
}
