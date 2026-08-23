import Foundation

enum UpdateInstallerHarnessFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message): message
        }
    }
}

@MainActor
private final class FakeUpdateInstaller: AppUpdateInstalling {
    private(set) var state: AppUpdateInstallationState
    var stateDidChange: ((AppUpdateInstallationState) -> Void)?
    private(set) var installCallCount = 0

    init(state: AppUpdateInstallationState = .ready) {
        self.state = state
    }

    func installLatestRelease() {
        installCallCount += 1
        transition(to: .checking)
    }

    func transition(to newState: AppUpdateInstallationState) {
        state = newState
        stateDidChange?(newState)
    }
}

@main
struct UpdateInstallerCoreHarness {
    @MainActor
    static func main() async throws {
        let release = try ReleaseSummary(
            tagName: "v1.0.0",
            releaseURL: URL(string: "https://github.com/7b7b7b/battuta/releases/tag/v1.0.0")!,
            publishedAt: nil
        )
        let response = GitHubReleaseFetchResult.modified(
            release: release,
            etag: "update-installer-harness",
            rateLimit: GitHubRateLimit(remaining: 59, resetAt: nil)
        )
        let defaultsName = "Battuta.UpdateInstallerCoreHarness.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsName) else {
            throw UpdateInstallerHarnessFailure.assertion("could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let installer = FakeUpdateInstaller()
        let controller = UpdateController(
            client: .constant(response),
            installedVersion: SemanticVersion(major: 0, minor: 9, patch: 0),
            defaults: defaults,
            installer: installer
        )

        try check(!controller.canInstallAvailableUpdate, "installer must stay gated until an update is known")
        controller.installAvailableUpdate()
        try check(installer.installCallCount == 0, "install must not start without an available release")

        await controller.check(trigger: .manual)
        try check(controller.canInstallAvailableUpdate, "known release and ready installer should enable one-click update")

        controller.installAvailableUpdate()
        try check(installer.installCallCount == 1, "one-click update should invoke the installer exactly once")
        try check(controller.installationState == .checking, "installer state must propagate to the update UI")
        try check(!controller.canInstallAvailableUpdate, "an active update must disable duplicate install actions")

        installer.transition(to: .downloading(progress: 0.42))
        try check(
            controller.installationState == .downloading(progress: 0.42),
            "download progress must propagate to the update UI"
        )
        installer.transition(to: .failed("test failure"))
        try check(controller.canInstallAvailableUpdate, "a failed attempt should remain retryable")

        print("Update installer core harness passed: 8 assertions")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw UpdateInstallerHarnessFailure.assertion(message)
        }
    }
}
