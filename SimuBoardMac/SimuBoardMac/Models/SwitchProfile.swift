import Foundation

enum SwitchProfile: String, CaseIterable, Identifiable, Sendable {
    case holyPanda = "holypanda"
    case mxBrown = "mxbrown"
    case mxClear = "mxclear"
    case g915Brown = "g915brown"
    case studioTactile = "studiotactile"
    case mxBlue = "mxblue"
    case boxNavy = "boxnavy"
    case boxWhite = "boxwhite"
    case lowProfileBlue = "lowprofileblue"
    case blueAlps = "bluealps"
    case studioClicky = "studioclicky"
    case cream
    case alpaca
    case blackInk = "blackink"
    case redInk = "redink"
    case mxBlack = "mxblack"
    case turquoise
    case keychronRed = "keychronred"
    case topre
    case buckling

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .holyPanda: "Holy Panda"
        case .mxBrown: "Cherry MX Brown"
        case .mxClear: "Cherry MX Clear"
        case .g915Brown: "Logitech G915 TKL Brown"
        case .studioTactile: "Studio Tactile"
        case .mxBlue: "Cherry MX Blue"
        case .boxNavy: "Kailh BOX Navy"
        case .boxWhite: "Kailh BOX White"
        case .lowProfileBlue: "Kailh Low-profile Blue"
        case .blueAlps: "SKCM Blue Alps"
        case .studioClicky: "Studio Clicky"
        case .cream: "NovelKeys Cream"
        case .alpaca: "Alpaca"
        case .blackInk: "Gateron Black Ink"
        case .redInk: "Gateron Red Ink"
        case .mxBlack: "Cherry MX Black"
        case .turquoise: "Turquoise Tealios"
        case .keychronRed: "Keychron Red Linear"
        case .topre: "Topre"
        case .buckling: "IBM Buckling Spring"
        }
    }

    var family: String {
        switch self {
        case .holyPanda, .mxBrown, .mxClear, .g915Brown, .studioTactile: "段落".localized
        case .mxBlue, .boxNavy, .boxWhite, .lowProfileBlue, .blueAlps, .studioClicky: "点击".localized
        case .cream, .alpaca, .blackInk, .redInk, .mxBlack, .turquoise, .keychronRed: "线性".localized
        case .topre: "静电容".localized
        case .buckling: "屈曲弹簧".localized
        }
    }

    var tone: String {
        switch self {
        case .holyPanda: "饱满、集中".localized
        case .mxBrown: "温和、均衡".localized
        case .mxClear: "扎实、段落明显".localized
        case .g915Brown: "轻薄、利落".localized
        case .studioTactile: "近场、细腻".localized
        case .mxBlue: "清脆、经典".localized
        case .boxNavy: "厚重、响亮".localized
        case .boxWhite: "短促、清亮".localized
        case .lowProfileBlue: "薄脆、双向点击".localized
        case .blueAlps: "复古、锐利".localized
        case .studioClicky: "明快、颗粒感".localized
        case .cream: "顺滑、奶油".localized
        case .alpaca: "干净、柔和".localized
        case .blackInk: "低沉、扎实".localized
        case .redInk: "轻快、圆润".localized
        case .mxBlack: "沉稳、硬朗".localized
        case .turquoise: "明亮、顺滑".localized
        case .keychronRed: "干净、轻快".localized
        case .topre: "柔韧、闷响".localized
        case .buckling: "复古、金属感".localized
        }
    }

    var hasDedicatedSpecialKeySamples: Bool {
        switch self {
        case .mxBlue, .mxClear, .studioTactile, .boxWhite, .lowProfileBlue,
             .studioClicky, .keychronRed:
            false
        default:
            true
        }
    }

    var supportsReleaseSound: Bool {
        true
    }

    var hasRowSpecificReleaseSamples: Bool {
        switch self {
        case .mxClear, .g915Brown, .studioTactile, .boxWhite, .lowProfileBlue,
             .studioClicky, .keychronRed:
            true
        default: false
        }
    }
}
