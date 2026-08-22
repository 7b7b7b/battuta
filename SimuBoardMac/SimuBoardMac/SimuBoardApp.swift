import SwiftUI

@main
@MainActor
struct SimuBoardApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(systemName: "keyboard.badge.ellipsis")
                .accessibilityLabel("SimuBoard")
        }
        .menuBarExtraStyle(.window)
    }
}
