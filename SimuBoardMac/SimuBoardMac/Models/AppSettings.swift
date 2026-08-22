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
        static let pointerSoundEnabled = "pointerSoundEnabled"
        static let selectedPointerProfile = "selectedPointerProfile"
        static let pointerVolume = "pointerVolume"
        static let pointerReleaseSound = "pointerReleaseSound"
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

    @Published var isPointerSoundEnabled: Bool {
        didSet { defaults.set(isPointerSoundEnabled, forKey: Key.pointerSoundEnabled) }
    }

    @Published var selectedPointerProfileID: String {
        didSet { defaults.set(selectedPointerProfileID, forKey: Key.selectedPointerProfile) }
    }

    @Published var pointerVolume: Double {
        didSet { defaults.set(pointerVolume, forKey: Key.pointerVolume) }
    }

    @Published var playsPointerReleaseSound: Bool {
        didSet { defaults.set(playsPointerReleaseSound, forKey: Key.pointerReleaseSound) }
    }

    var selectedProfile: SwitchProfile {
        get { SwitchProfile(rawValue: selectedProfileID) ?? .holyPanda }
        set { selectedProfileID = newValue.rawValue }
    }

    var selectedPointerProfile: PointerSoundProfile {
        get { PointerSoundProfile(rawValue: selectedPointerProfileID) ?? .classic }
        set { selectedPointerProfileID = newValue.rawValue }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        selectedProfileID = defaults.string(forKey: Key.selectedProfile) ?? SwitchProfile.holyPanda.rawValue
        let storedKeyboardVolume = defaults.object(forKey: Key.volume) as? Double ?? 0.42
        volume = storedKeyboardVolume
        playsReleaseSound = defaults.object(forKey: Key.releaseSound) as? Bool ?? true
        usesPitchVariation = defaults.object(forKey: Key.pitchVariation) as? Bool ?? true
        isPointerSoundEnabled = defaults.object(forKey: Key.pointerSoundEnabled) as? Bool ?? false
        let storedPointerProfileID = defaults.string(forKey: Key.selectedPointerProfile)
            ?? PointerSoundProfile.classic.rawValue
        selectedPointerProfileID = PointerSoundProfile(rawValue: storedPointerProfileID) == nil
            ? PointerSoundProfile.classic.rawValue
            : storedPointerProfileID
        let storedPointerVolume = defaults.object(forKey: Key.pointerVolume) as? Double
        let resolvedPointerVolume = storedPointerVolume ?? storedKeyboardVolume * 0.65
        pointerVolume = min(max(resolvedPointerVolume, 0), 1)
        playsPointerReleaseSound = defaults.object(forKey: Key.pointerReleaseSound) as? Bool ?? true
        if selectedPointerProfileID != storedPointerProfileID {
            defaults.set(selectedPointerProfileID, forKey: Key.selectedPointerProfile)
        }
        if storedPointerVolume == nil || storedPointerVolume != pointerVolume {
            defaults.set(pointerVolume, forKey: Key.pointerVolume)
        }
    }
}
