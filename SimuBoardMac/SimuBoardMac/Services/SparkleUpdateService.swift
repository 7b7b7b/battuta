import Foundation
import Sparkle

@MainActor
final class SparkleUpdateService: AppUpdateInstalling {
    private(set) var state: AppUpdateInstallationState
    var stateDidChange: ((AppUpdateInstallationState) -> Void)?

    private var updater: SPUUpdater?
    private var userDriver: BattutaUpdateUserDriver?

    init(bundle: Bundle = .main) {
        if Self.isDevelopmentBuild {
            state = .unavailable(.developmentBuild)
            return
        }

        guard let feedString = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feedString),
              feedURL.scheme == "https" else {
            state = .unavailable(.notConfigured)
            return
        }

        guard let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let publicKeyData = Data(base64Encoded: publicKey),
              publicKeyData.count == 32 else {
            state = .unavailable(.invalidConfiguration)
            return
        }

        let userDriver = BattutaUpdateUserDriver()
        let updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: userDriver,
            delegate: nil
        )
        self.userDriver = userDriver
        self.updater = updater
        state = .ready

        userDriver.stateDidChange = { [weak self] newState in
            self?.transition(to: newState)
        }

        do {
            try updater.start()
        } catch {
            state = .unavailable(.startupFailed(error.localizedDescription))
            self.updater = nil
            self.userDriver = nil
        }
    }

    func installLatestRelease() {
        guard let updater else { return }
        guard !state.isActive else { return }
        if userDriver?.retryTerminatingApplicationIfNeeded() == true {
            return
        }
        guard updater.canCheckForUpdates else {
            transition(to: .failed("更新服务正忙，请稍后再试。"))
            return
        }

        transition(to: .checking)
        updater.checkForUpdates()
    }

    private func transition(to newState: AppUpdateInstallationState) {
        state = newState
        stateDidChange?(newState)
    }

    private static let isDevelopmentBuild: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()
}

@MainActor
private final class BattutaUpdateUserDriver: NSObject, SPUUserDriver {
    var stateDidChange: ((AppUpdateInstallationState) -> Void)?

    private var currentState: AppUpdateInstallationState = .ready
    private var expectedDownloadLength: UInt64 = 0
    private var downloadedLength: UInt64 = 0
    private var retryTerminatingApplication: (() -> Void)?

    func retryTerminatingApplicationIfNeeded() -> Bool {
        guard let retryTerminatingApplication else { return false }
        transition(to: .installing)
        retryTerminatingApplication()
        return true
    }

    private func transition(to state: AppUpdateInstallationState) {
        currentState = state
        stateDidChange?(state)
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(
            SUUpdatePermissionResponse(
                automaticUpdateChecks: false,
                sendSystemProfile: false
            )
        )
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        transition(to: .checking)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        guard !appcastItem.isInformationOnlyUpdate else {
            transition(to: .failed("这个版本需要前往 GitHub 手动下载安装。"))
            reply(.dismiss)
            return
        }

        transition(to: .downloading(progress: nil))
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        transition(to: .failed("没有可安装的新版本。"))
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        transition(to: .failed("更新失败：\(error.localizedDescription)"))
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedDownloadLength = 0
        downloadedLength = 0
        transition(to: .downloading(progress: nil))
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedDownloadLength = expectedContentLength
        downloadedLength = 0
        transition(to: .downloading(progress: expectedContentLength > 0 ? 0 : nil))
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        downloadedLength &+= length
        guard expectedDownloadLength > 0 else {
            transition(to: .downloading(progress: nil))
            return
        }
        let progress = min(Double(downloadedLength) / Double(expectedDownloadLength), 1)
        transition(to: .downloading(progress: progress))
    }

    func showDownloadDidStartExtractingUpdate() {
        transition(to: .extracting(progress: nil))
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        transition(to: .extracting(progress: min(max(progress, 0), 1)))
    }

    func showReady(
        toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        transition(to: .installing)
        reply(.install)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        if applicationTerminated {
            self.retryTerminatingApplication = nil
            transition(to: .installing)
        } else {
            self.retryTerminatingApplication = retryTerminatingApplication
            transition(
                to: .failed("Battuta 尚未退出。请先关闭正在编辑的窗口，然后重试安装。")
            )
        }
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        retryTerminatingApplication = nil
        transition(to: .ready)
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        retryTerminatingApplication = nil
        if currentState.isActive {
            transition(to: .failed("更新流程已取消，可以重试。"))
        }
    }
}
