import AppKit
import Combine
import CoreGraphics

@MainActor
final class InputMonitoringPermissionManager: ObservableObject {
    @Published private(set) var isGranted = CGPreflightListenEventAccess()

    @discardableResult
    func refresh() -> Bool {
        let current = CGPreflightListenEventAccess()
        if current != isGranted { isGranted = current }
        return current
    }

    func request() {
        isGranted = CGRequestListenEventAccess()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
}
