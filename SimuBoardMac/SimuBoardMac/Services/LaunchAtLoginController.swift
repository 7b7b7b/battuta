import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    enum State: Equatable {
        case disabled
        case enabled
        case requiresApproval
        case notRegistered
        case needsApplicationInstall
        case failed(String)
    }

    @Published private(set) var state: State = .disabled

    private let service: SMAppService
    private let bundleURLProvider: () -> URL
    private var desiredEnabled = false
    private var operationError: String?

    init(
        service: SMAppService = .mainApp,
        bundleURLProvider: @escaping () -> URL = { Bundle.main.bundleURL }
    ) {
        self.service = service
        self.bundleURLProvider = bundleURLProvider
    }

    func reconcile(desiredEnabled: Bool) {
        self.desiredEnabled = desiredEnabled
        operationError = nil

        if desiredEnabled {
            registerIfNeeded()
        } else {
            unregisterIfNeeded()
        }
    }

    func refresh() {
        updateState()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    nonisolated static func isInstalledApplication(
        at bundleURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let bundlePath = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        let applicationRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]

        return applicationRoots.contains { root in
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            return bundlePath == rootPath || bundlePath.hasPrefix(rootPath + "/")
        }
    }

    private func registerIfNeeded() {
        guard Self.isInstalledApplication(at: bundleURLProvider()) else {
            state = .needsApplicationInstall
            return
        }

        switch service.status {
        case .enabled, .requiresApproval:
            updateState()
        case .notRegistered, .notFound:
            do {
                try service.register()
                updateState()
            } catch {
                operationError = L10n.format(
                    "无法启用登录时启动：%@",
                    L10n.tr(error.localizedDescription)
                )
                updateState()
            }
        @unknown default:
            state = .notRegistered
        }
    }

    private func unregisterIfNeeded() {
        switch service.status {
        case .notRegistered, .notFound:
            updateState()
        case .enabled, .requiresApproval:
            do {
                try service.unregister()
                updateState()
            } catch {
                operationError = L10n.format(
                    "无法关闭登录时启动：%@",
                    L10n.tr(error.localizedDescription)
                )
                updateState()
            }
        @unknown default:
            state = .disabled
        }
    }

    private func updateState() {
        guard desiredEnabled else {
            switch service.status {
            case .notRegistered, .notFound:
                operationError = nil
                state = .disabled
            case .enabled, .requiresApproval:
                state = .failed(
                    operationError
                        ?? L10n.tr("系统登录项仍然开启，请重试或在系统设置中关闭 Battuta。")
                )
            @unknown default:
                state = operationError.map(State.failed) ?? .disabled
            }
            return
        }
        guard Self.isInstalledApplication(at: bundleURLProvider()) else {
            state = .needsApplicationInstall
            return
        }

        switch service.status {
        case .enabled:
            operationError = nil
            state = .enabled
        case .requiresApproval:
            operationError = nil
            state = .requiresApproval
        case .notRegistered, .notFound:
            state = operationError.map(State.failed) ?? .notRegistered
        @unknown default:
            state = operationError.map(State.failed) ?? .notRegistered
        }
    }
}
