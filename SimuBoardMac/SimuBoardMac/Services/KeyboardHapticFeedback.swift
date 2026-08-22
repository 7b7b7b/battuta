import AppKit

@MainActor
final class KeyboardHapticFeedback {
    private static let enhancedPulseGap = Duration.milliseconds(10)
    private var pendingEnhancedPulse: Task<Void, Never>?

    func performKeyPress(style: HapticFeedbackStyle) {
        perform(style: style)
    }

    func performTest(style: HapticFeedbackStyle) {
        perform(style: style)
    }

    private func perform(style: HapticFeedbackStyle) {
        pendingEnhancedPulse?.cancel()
        pendingEnhancedPulse = nil

        switch style {
        case .system:
            performPulse(.generic)
        case .enhanced:
            performPulse(.levelChange)
            pendingEnhancedPulse = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: Self.enhancedPulseGap)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.performPulse(.levelChange)
                self?.pendingEnhancedPulse = nil
            }
        }
    }

    private func performPulse(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(
            pattern,
            performanceTime: .now
        )
    }
}
