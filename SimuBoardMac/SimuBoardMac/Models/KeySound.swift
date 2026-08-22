import Foundation

enum KeySoundPhase: String, CaseIterable, Sendable {
    case press
    case release
}

enum KeySoundSample: String, CaseIterable, Sendable {
    case genericR0 = "GENERIC_R0"
    case genericR1 = "GENERIC_R1"
    case genericR2 = "GENERIC_R2"
    case genericR3 = "GENERIC_R3"
    case genericR4 = "GENERIC_R4"
    case generic = "GENERIC"
    case space = "SPACE"
    case enter = "ENTER"
    case backspace = "BACKSPACE"
}

enum KeySoundMapper {
    private static let row0: Set<UInt16> = [18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 50]
    private static let row1: Set<UInt16> = [12, 13, 14, 15, 16, 17, 30, 31, 32, 33, 34, 35, 42]
    private static let row2: Set<UInt16> = [0, 1, 2, 3, 4, 5, 37, 38, 39, 40, 41]
    private static let row3: Set<UInt16> = [6, 7, 8, 9, 11, 43, 44, 45, 46, 47]
    static func sample(for keyCode: UInt16, phase: KeySoundPhase, profile: SwitchProfile) -> KeySoundSample? {
        let special: KeySoundSample? = switch keyCode {
        case 49: .space
        case 36, 76: .enter
        case 51, 117: .backspace
        default: nil
        }

        if phase == .release {
            guard profile.supportsReleaseSound else { return nil }
            if profile.hasDedicatedSpecialKeySamples, let special { return special }
            if profile.hasRowSpecificReleaseSamples {
                return genericSample(for: keyCode)
            }
            return .generic
        }
        if profile.hasDedicatedSpecialKeySamples, let special { return special }
        return genericSample(for: keyCode)
    }

    private static func genericSample(for keyCode: UInt16) -> KeySoundSample {
        if row0.contains(keyCode) { return .genericR0 }
        if row1.contains(keyCode) { return .genericR1 }
        if row2.contains(keyCode) { return .genericR2 }
        if row3.contains(keyCode) { return .genericR3 }
        return .genericR4
    }
}
