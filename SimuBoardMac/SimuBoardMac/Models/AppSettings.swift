import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let selectedProfile = "selectedProfile"
        static let volume = "volume"
        static let releaseSound = "releaseSound"
        static let pitchVariation = "pitchVariation"
        static let hapticFeedback = "hapticFeedback"
    }

    private let defaults: UserDefaults

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.enabled) }
    }

    @Published var selectedProfileID: String {
        didSet { defaults.set(selectedProfileID, forKey: Key.selectedProfile) }
    }

    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: Key.volume) }
    }

    @Published var playsReleaseSound: Bool {
        didSet { defaults.set(playsReleaseSound, forKey: Key.releaseSound) }
    }

    @Published var usesPitchVariation: Bool {
        didSet { defaults.set(usesPitchVariation, forKey: Key.pitchVariation) }
    }

    @Published var isHapticFeedbackEnabled: Bool {
        didSet { defaults.set(isHapticFeedbackEnabled, forKey: Key.hapticFeedback) }
    }

    var selectedProfile: SwitchProfile {
        get { SwitchProfile(rawValue: selectedProfileID) ?? .holyPanda }
        set { selectedProfileID = newValue.rawValue }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        selectedProfileID = defaults.string(forKey: Key.selectedProfile) ?? SwitchProfile.holyPanda.rawValue
        volume = defaults.object(forKey: Key.volume) as? Double ?? 0.42
        playsReleaseSound = defaults.object(forKey: Key.releaseSound) as? Bool ?? true
        usesPitchVariation = defaults.object(forKey: Key.pitchVariation) as? Bool ?? true
        isHapticFeedbackEnabled = defaults.object(forKey: Key.hapticFeedback) as? Bool ?? false

        if SwitchProfile(rawValue: selectedProfileID) == nil {
            selectedProfileID = SwitchProfile.holyPanda.rawValue
        }
    }
}
