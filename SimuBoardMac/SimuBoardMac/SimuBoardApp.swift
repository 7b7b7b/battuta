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
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .onAppear {
                    appDelegate.model = model
                    model.updates.scheduleAutomaticCheck(after: 0)
                }
        } label: {
            Image(systemName: "keyboard.badge.ellipsis")
                .accessibilityLabel("SimuBoard")
        }
        .menuBarExtraStyle(.window)
    }
}
