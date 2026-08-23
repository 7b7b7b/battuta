import AppKit
import SwiftUI

@MainActor
final class SimuBoardAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.applicationShouldTerminate(sender) ?? .terminateNow
    }
}

@main
@MainActor
struct SimuBoardApp: App {
    @NSApplicationDelegateAdaptor(SimuBoardAppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        appDelegate.model = model

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--show-stats")
            || arguments.contains("--show-diy")
            || arguments.contains("--show-menu-preview")
        {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if arguments.contains("--show-stats") {
                    model.openTypingStats()
                }
                if arguments.contains("--show-diy") {
                    model.openSoundPackEditor()
                }
                if arguments.contains("--show-menu-preview") {
                    BattutaDebugPreviewWindow.showMenu(model: model)
                }
            }
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .onAppear {
                    model.updates.scheduleAutomaticCheck(after: 0)
                }
        } label: {
            Image(systemName: "keyboard.badge.ellipsis")
                .accessibilityLabel("Battuta")
        }
        .menuBarExtraStyle(.window)
    }
}

#if DEBUG
@MainActor
private enum BattutaDebugPreviewWindow {
    private static var window: NSWindow?

    static func showMenu(model: AppModel) {
        let controller = BattutaGlassHostingController(rootView: MenuBarView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Battuta · 菜单预览"
        BattutaWindowChrome.apply(to: window)
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
#endif
