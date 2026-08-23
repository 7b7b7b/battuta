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
        let hostingController = BattutaGlassHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Battuta · 输入统计"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        BattutaWindowChrome.apply(to: window)
        window.setContentSize(NSSize(width: 1_040, height: 760))
        window.contentMinSize = NSSize(width: 820, height: 600)
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
