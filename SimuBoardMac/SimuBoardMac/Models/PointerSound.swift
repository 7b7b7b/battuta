import Foundation

enum PointerSoundPhase: String, CaseIterable, Sendable {
    case press
    case release
}

enum PointerSoundSample: String, CaseIterable, Sendable {
    case primary = "PRIMARY"
    case secondary = "SECONDARY"
    case middle = "MIDDLE"
}

enum PointerButton: Equatable, Sendable {
    case primary
    case secondary
    case middle
    case auxiliary(Int64)

    var sample: PointerSoundSample {
        switch self {
        case .primary:
            .primary
        case .secondary:
            .secondary
        case .middle, .auxiliary:
            .middle
        }
    }

    /// Adds a subtle distinction when a profile falls back to its primary-button sample.
    var playbackRate: Float {
        switch self {
        case .primary:
            1
        case .secondary:
            0.97
        case .middle:
            1.04
        case .auxiliary:
            1.02
        }
    }

    init(mouseButtonNumber: Int64) {
        self = switch mouseButtonNumber {
        case 0: .primary
        case 1: .secondary
        case 2: .middle
        default: .auxiliary(mouseButtonNumber)
        }
    }
}

struct PointerEvent: Equatable, Sendable {
    let phase: PointerSoundPhase
    let button: PointerButton
}

enum GlobalInputEvent: Sendable {
    case keyboard(KeyboardEvent)
    case pointer(PointerEvent)
}

enum PointerSoundProfile: String, CaseIterable, Identifiable, Sendable {
    case classic
    case silent
    case crisp
    case heavy
    case glass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: "经典微动".localized
        case .silent: "静音微动".localized
        case .crisp: "电竞脆响".localized
        case .heavy: "厚重办公".localized
        case .glass: "玻璃触控板".localized
        }
    }

    var family: String {
        switch self {
        case .classic: "通用鼠标".localized
        case .silent: "静音鼠标".localized
        case .crisp: "轻快点击".localized
        case .heavy: "办公鼠标".localized
        case .glass: "触控板".localized
        }
    }

    var tone: String {
        switch self {
        case .classic: "清晰、均衡".localized
        case .silent: "柔和、低调".localized
        case .crisp: "短促、明亮".localized
        case .heavy: "低沉、扎实".localized
        case .glass: "干净、通透".localized
        }
    }
}
