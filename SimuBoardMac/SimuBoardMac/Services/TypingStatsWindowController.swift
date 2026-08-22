import AppKit
import SwiftUI

@MainActor
final class TypingStatsWindowController: NSWindowController, NSWindowDelegate {
    private weak var appModel: AppModel?

    init(appModel: AppModel) {
        self.appModel = appModel

        let content = TypingStatsView(
            model: appModel.typingStats,
            settings: appModel.settings
        )
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Battuta · 输入统计"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 960, height: 680))
        window.contentMinSize = NSSize(width: 780, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        appModel?.typingStatsWindowDidClose(self)
    }
}
