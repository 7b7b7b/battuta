import AppKit
import Foundation

@MainActor
final class KeyboardHapticFeedback {
    private let minimumInterval: TimeInterval
    private var lastFeedbackTime: TimeInterval?

    init(minimumInterval: TimeInterval = 0.025) {
        self.minimumInterval = minimumInterval
    }

    func performKeyPress() {
        performFeedback(respectingRateLimit: true)
    }

    func performTest() {
        performFeedback(respectingRateLimit: false)
    }

    private func performFeedback(respectingRateLimit: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if respectingRateLimit,
           let lastFeedbackTime,
           now - lastFeedbackTime < minimumInterval {
            return
        }

        lastFeedbackTime = now
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )
    }
}
