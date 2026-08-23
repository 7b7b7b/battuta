import Combine
import Foundation

enum AutomaticUpdateCheckPreference: String, Codable, Equatable, Sendable {
    case undecided
    case enabled
    case disabled
}

enum UpdateCheckTrigger: Equatable, Sendable {
    case automatic
    case manual
}

enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(ReleaseSummary)
    case upToDate(SemanticVersion)
    case installedVersionIsNewer(SemanticVersion)
}

struct UpdateCheckSnapshot: Equatable, Sendable {
    let result: UpdateCheckResult
    let checkedAt: Date
}

enum UpdateCheckFailure: Equatable, Sendable {
    case offline
    case timedOut
    case requestedTooSoon(retryAt: Date)
    case rateLimited(retryAt: Date)
    case noPublishedRelease
    case apiVersionRetired
    case invalidInstalledVersion
    case invalidResponse
    case serverUnavailable
}

enum UpdateCheckState: Equatable, Sendable {
    case idle(cached: UpdateCheckSnapshot?)
    case checking(trigger: UpdateCheckTrigger, cached: UpdateCheckSnapshot?)
    case completed(UpdateCheckSnapshot)
    case failed(UpdateCheckFailure, cached: UpdateCheckSnapshot?)

    var snapshot: UpdateCheckSnapshot? {
        switch self {
        case let .idle(cached), let .checking(_, cached), let .failed(_, cached): cached
        case let .completed(snapshot): snapshot
        }
    }

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}

enum AppUpdateInstallerUnavailability: Equatable, Sendable {
    case developmentBuild
    case notConfigured
    case invalidConfiguration
    case startupFailed(String)
}

enum AppUpdateInstallationState: Equatable, Sendable {
    case unavailable(AppUpdateInstallerUnavailability)
    case ready
    case checking
    case downloading(progress: Double?)
    case extracting(progress: Double?)
    case installing
    case failed(String)

    var isActive: Bool {
        switch self {
        case .checking, .downloading, .extracting, .installing:
            true
        case .unavailable, .ready, .failed:
            false
        }
    }

    var canStart: Bool {
        switch self {
        case .ready, .failed:
            true
        case .unavailable, .checking, .downloading, .extracting, .installing:
            false
        }
    }
}

@MainActor
protocol AppUpdateInstalling: AnyObject {
    var state: AppUpdateInstallationState { get }
    var stateDidChange: ((AppUpdateInstallationState) -> Void)? { get set }

    func installLatestRelease()
}

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var automaticCheckPreference: AutomaticUpdateCheckPreference
    @Published private(set) var state: UpdateCheckState
    @Published private(set) var installationState: AppUpdateInstallationState

    let installedVersion: SemanticVersion?

    private let client: GitHubReleaseClient
    private let installer: (any AppUpdateInstalling)?
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private var cache: UpdateCache
    private var inFlightTask: Task<Void, Never>?
    private var inFlightTrigger: UpdateCheckTrigger?
    private var scheduledAutomaticTask: Task<Void, Never>?

    // Opening the menu always asks whether a refresh is due, but automatic
    // network requests remain sparse enough for GitHub's unauthenticated,
    // per-IP quota and for users who open the panel repeatedly.
    private static let automaticRequestSpacing: TimeInterval = 5 * 60
    // Unauthenticated GitHub REST requests share a small per-IP quota. Keep
    // repeated manual checks comfortably below one request per minute.
    private static let manualRequestSpacing: TimeInterval = 65
    private static let cacheKey = "SimuBoard.UpdateChecker.Cache.v1"
    private static let preferenceKey = "SimuBoard.UpdateChecker.AutomaticPreference.v1"

    init(
        client: GitHubReleaseClient = .live(),
        installedVersion: SemanticVersion? = UpdateController.bundledVersion(),
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        installer: (any AppUpdateInstalling)? = nil
    ) {
        self.client = client
        self.installedVersion = installedVersion
        self.defaults = defaults
        self.now = now
        let installer = installer ?? Self.defaultInstaller()
        self.installer = installer
        installationState = installer?.state ?? .unavailable(.notConfigured)

        let cache = Self.loadCache(from: defaults)
        self.cache = cache
        automaticCheckPreference = defaults.string(forKey: Self.preferenceKey)
            .flatMap(AutomaticUpdateCheckPreference.init(rawValue:))
            ?? .undecided
        state = .idle(cached: Self.snapshot(from: cache, installedVersion: installedVersion))
        installer?.stateDidChange = { [weak self] state in
            self?.installationState = state
        }
    }

    var availableRelease: ReleaseSummary? {
        guard let snapshot = state.snapshot,
              case let .updateAvailable(release) = snapshot.result else { return nil }
        return release
    }

    var canInstallAvailableUpdate: Bool {
        availableRelease != nil && installationState.canStart
    }

    func installAvailableUpdate() {
        guard availableRelease != nil else { return }
        installer?.installLatestRelease()
    }

    func enableAutomaticChecks(checkImmediately: Bool = true) {
        setAutomaticCheckPreference(.enabled)
        if checkImmediately {
            scheduleAutomaticCheck(after: 0)
        }
    }

    func disableAutomaticChecks() {
        setAutomaticCheckPreference(.disabled)
        scheduledAutomaticTask?.cancel()
        scheduledAutomaticTask = nil
        if inFlightTrigger == .automatic {
            inFlightTask?.cancel()
        }
    }

    func scheduleAutomaticCheck(after delay: TimeInterval = 2) {
        guard automaticCheckPreference == .enabled else { return }
        scheduledAutomaticTask?.cancel()
        scheduledAutomaticTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > 0 {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await check(trigger: .automatic)
            scheduledAutomaticTask = nil
        }
    }

    func checkManually() {
        Task { @MainActor [weak self] in
            await self?.check(trigger: .manual)
        }
    }

    func check(trigger: UpdateCheckTrigger) async {
        if let inFlightTask {
            await inFlightTask.value
            return
        }

        let currentDate = now()
        let cachedSnapshot = state.snapshot ?? Self.snapshot(from: cache, installedVersion: installedVersion)

        if let retryAt = cache.rateLimitedUntil, retryAt > currentDate {
            state = .failed(.rateLimited(retryAt: retryAt), cached: cachedSnapshot)
            return
        } else if cache.rateLimitedUntil != nil {
            cache.rateLimitedUntil = nil
            saveCache()
        }

        switch trigger {
        case .automatic:
            guard automaticCheckPreference == .enabled,
                  automaticCheckIsDue(at: currentDate) else { return }
        case .manual:
            if let lastAttemptAt = cache.lastAttemptAt,
               currentDate.timeIntervalSince(lastAttemptAt) < Self.manualRequestSpacing {
                state = .failed(
                    .requestedTooSoon(
                        retryAt: lastAttemptAt.addingTimeInterval(Self.manualRequestSpacing)
                    ),
                    cached: cachedSnapshot
                )
                return
            }
        }

        state = .checking(trigger: trigger, cached: cachedSnapshot)
        cache.lastAttemptAt = currentDate
        saveCache()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performCheck(cachedSnapshot: cachedSnapshot)
        }
        inFlightTask = task
        inFlightTrigger = trigger
        await task.value
        inFlightTask = nil
        inFlightTrigger = nil
    }

    private func performCheck(cachedSnapshot: UpdateCheckSnapshot?) async {
        guard let installedVersion else {
            recordFailure(.invalidInstalledVersion, cachedSnapshot: cachedSnapshot)
            return
        }

        do {
            let etag = cache.latestRelease == nil ? nil : cache.etag
            let response = try await client.fetchLatest(etag)
            try Task.checkCancellation()

            let release: ReleaseSummary
            let responseRateLimit: GitHubRateLimit
            switch response {
            case let .modified(latestRelease, etag, rateLimit):
                release = latestRelease
                responseRateLimit = rateLimit
                cache.latestRelease = latestRelease
                cache.etag = etag
            case let .notModified(etag, rateLimit):
                guard let cachedRelease = cache.latestRelease else {
                    recordFailure(.invalidResponse, cachedSnapshot: cachedSnapshot)
                    return
                }
                release = cachedRelease
                responseRateLimit = rateLimit
                cache.etag = etag
            }

            let checkedAt = now()
            cache.lastSuccessfulCheckAt = checkedAt
            cache.lastFailedCheckAt = nil
            if responseRateLimit.remaining == 0,
               let resetAt = responseRateLimit.resetAt,
               resetAt > checkedAt {
                cache.rateLimitedUntil = resetAt
            } else {
                cache.rateLimitedUntil = nil
            }
            saveCache()
            state = .completed(
                UpdateCheckSnapshot(
                    result: Self.result(for: release, installedVersion: installedVersion),
                    checkedAt: checkedAt
                )
            )
        } catch is CancellationError {
            state = .idle(cached: cachedSnapshot)
        } catch let error as URLError {
            if error.code == .cancelled {
                state = .idle(cached: cachedSnapshot)
            } else if error.code == .timedOut {
                recordFailure(.timedOut, cachedSnapshot: cachedSnapshot)
            } else if Self.isOfflineError(error.code) {
                recordFailure(.offline, cachedSnapshot: cachedSnapshot)
            } else {
                recordFailure(.serverUnavailable, cachedSnapshot: cachedSnapshot)
            }
        } catch let error as GitHubReleaseClientError {
            switch error {
            case let .rateLimited(retryAt):
                cache.rateLimitedUntil = retryAt
                recordFailure(.rateLimited(retryAt: retryAt), cachedSnapshot: cachedSnapshot)
            case .noPublishedRelease:
                recordFailure(.noPublishedRelease, cachedSnapshot: cachedSnapshot)
            case .apiVersionRetired:
                recordFailure(.apiVersionRetired, cachedSnapshot: cachedSnapshot)
            case .invalidResponse, .malformedRelease:
                recordFailure(.invalidResponse, cachedSnapshot: cachedSnapshot)
            case let .httpStatus(statusCode):
                recordFailure(
                    statusCode >= 500 ? .serverUnavailable : .invalidResponse,
                    cachedSnapshot: cachedSnapshot
                )
            }
        } catch {
            recordFailure(.serverUnavailable, cachedSnapshot: cachedSnapshot)
        }
    }

    private func automaticCheckIsDue(at date: Date) -> Bool {
        if let lastAttemptAt = cache.lastAttemptAt,
           date.timeIntervalSince(lastAttemptAt) < Self.automaticRequestSpacing {
            return false
        }
        return true
    }

    private func recordFailure(_ failure: UpdateCheckFailure, cachedSnapshot: UpdateCheckSnapshot?) {
        cache.lastFailedCheckAt = now()
        saveCache()
        state = .failed(failure, cached: cachedSnapshot)
    }

    private func setAutomaticCheckPreference(_ preference: AutomaticUpdateCheckPreference) {
        automaticCheckPreference = preference
        defaults.set(preference.rawValue, forKey: Self.preferenceKey)
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }

    private static func bundledVersion(bundle: Bundle = .main) -> SemanticVersion? {
        guard let value = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }
        return SemanticVersion(value)
    }

    private static func defaultInstaller() -> (any AppUpdateInstalling)? {
        #if canImport(Sparkle)
        SparkleUpdateService()
        #else
        nil
        #endif
    }

    private static func loadCache(from defaults: UserDefaults) -> UpdateCache {
        guard let data = defaults.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(UpdateCache.self, from: data) else {
            return UpdateCache()
        }
        return cache
    }

    private static func snapshot(
        from cache: UpdateCache,
        installedVersion: SemanticVersion?
    ) -> UpdateCheckSnapshot? {
        guard let release = cache.latestRelease,
              let installedVersion,
              let checkedAt = cache.lastSuccessfulCheckAt else { return nil }
        return UpdateCheckSnapshot(
            result: result(for: release, installedVersion: installedVersion),
            checkedAt: checkedAt
        )
    }

    private static func result(
        for release: ReleaseSummary,
        installedVersion: SemanticVersion
    ) -> UpdateCheckResult {
        if release.version > installedVersion { return .updateAvailable(release) }
        if release.version == installedVersion { return .upToDate(release.version) }
        return .installedVersionIsNewer(release.version)
    }

    private static func isOfflineError(_ code: URLError.Code) -> Bool {
        switch code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed:
            true
        default:
            false
        }
    }

    isolated deinit {
        scheduledAutomaticTask?.cancel()
        inFlightTask?.cancel()
    }
}

private struct UpdateCache: Codable {
    var etag: String?
    var latestRelease: ReleaseSummary?
    var lastSuccessfulCheckAt: Date?
    var lastFailedCheckAt: Date?
    var lastAttemptAt: Date?
    var rateLimitedUntil: Date?
}

#if DEBUG
extension UpdateController {
    static func preview(
        state: UpdateCheckState,
        preference: AutomaticUpdateCheckPreference = .enabled,
        installationState: AppUpdateInstallationState = .ready,
        installedVersion: SemanticVersion = SemanticVersion(major: 0, minor: 3, patch: 2)
    ) -> UpdateController {
        let suiteName = "SimuBoard.UpdateController.Preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let controller = UpdateController(
            client: .failing(.invalidResponse),
            installedVersion: installedVersion,
            defaults: defaults
        )
        controller.automaticCheckPreference = preference
        controller.state = state
        controller.installationState = installationState
        return controller
    }
}
#endif
