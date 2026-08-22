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
