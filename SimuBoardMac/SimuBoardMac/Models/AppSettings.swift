import Combine
import Foundation

enum HapticFeedbackStyle: String, CaseIterable, Identifiable {
    case system
    case enhanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "系统"
        case .enhanced: "强劲"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let selectedProfile = "selectedProfile"
        static let volume = "volume"
        static let releaseSound = "releaseSound"
        static let pitchVariation = "pitchVariation"
        static let hapticFeedback = "hapticFeedback"
        static let hapticFeedbackStyle = "hapticFeedbackStyle"
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

    @Published var hapticFeedbackStyleID: String {
        didSet { defaults.set(hapticFeedbackStyleID, forKey: Key.hapticFeedbackStyle) }
    }

    var selectedProfile: SwitchProfile {
        get { SwitchProfile(rawValue: selectedProfileID) ?? .holyPanda }
        set { selectedProfileID = newValue.rawValue }
    }

    var hapticFeedbackStyle: HapticFeedbackStyle {
        get { HapticFeedbackStyle(rawValue: hapticFeedbackStyleID) ?? .enhanced }
        set { hapticFeedbackStyleID = newValue.rawValue }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        selectedProfileID = defaults.string(forKey: Key.selectedProfile) ?? SwitchProfile.holyPanda.rawValue
        volume = defaults.object(forKey: Key.volume) as? Double ?? 0.42
        playsReleaseSound = defaults.object(forKey: Key.releaseSound) as? Bool ?? true
        usesPitchVariation = defaults.object(forKey: Key.pitchVariation) as? Bool ?? true
        isHapticFeedbackEnabled = defaults.object(forKey: Key.hapticFeedback) as? Bool ?? false
        hapticFeedbackStyleID = defaults.string(forKey: Key.hapticFeedbackStyle)
            ?? HapticFeedbackStyle.enhanced.rawValue

        if SwitchProfile(rawValue: selectedProfileID) == nil {
            selectedProfileID = SwitchProfile.holyPanda.rawValue
        }
        if HapticFeedbackStyle(rawValue: hapticFeedbackStyleID) == nil {
            hapticFeedbackStyleID = HapticFeedbackStyle.enhanced.rawValue
        }
    }
}
